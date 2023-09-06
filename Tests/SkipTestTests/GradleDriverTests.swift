// Copyright 2023 Skip
import XCTest
@testable import SkipTest
import SkipDrive

#if os(macOS)
#if !SKIP
final class GradleDriverTests: XCTestCase {
    func testGradleVersion() async throws {
        let driver = try await GradleDriver()
        let result = try await driver.execGradle(in: URL(fileURLWithPath: NSTemporaryDirectory()), args: ["-v"], onExit: { _ in })
        guard let line = try await result.first(where: { line in
            line.hasPrefix("Gradle ")
        }) else {
            return XCTFail("No Gradle line in output")
        }

        let _ = line
    }

    /// Initialize a new Gradle project with the Kotlin DSL and run the test cases,
    /// parsing the output and checking for the errors and failures that are inserted into the test.
    @available(macOS 13, *)
    func testGradleInitTest() async throws {
        let driver = try await GradleDriver()

        let sampleName = "SampleGradleProject"
        let samplePackage = "simple.demo.project"

        let tmp = try FileManager.default.createTmpDir(name: sampleName)

        // 1. gradle init --type kotlin-library --dsl kotlin --console plain --no-daemon --offline --project-name=ExampleDemo --package=example.demo --test-framework=kotlintest --incubating
        print("creating sample project in:", tmp.path)
        for try await line in try await driver.execGradle(in: tmp, args: [
            "init",
            "--type=kotlin-library",
            "--dsl=kotlin",
            "--project-name=\(sampleName)",
            "--package=\(samplePackage)",
            "--incubating", // use new incubating features, and avoid the prompt "Generate build using new APIs"
            "--offline", // do not use the network
        ], onExit: Process.expectZeroExitCode) {
            let _ = line
            //print("INIT >", line)
        }

        let modname = "lib"

        let files = try FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: [], options: [.skipsHiddenFiles])
        let fileNames = Set(files.map(\.lastPathComponent))

        XCTAssertTrue(fileNames.isSubset(of: [modname, "settings.gradle.kts", "gradlew", "gradlew.bat", "gradle", "gradle.properties"]), "unexpected files were created by gradle init: \(fileNames.sorted())")

        // work around recent change that adds "languageVersion.set(JavaLanguageVersion.of(20))" to the build.gradle.kts
        func fixupBuildGradle() throws {
            let buildPath = tmp.appendingPathComponent(modname).appendingPathComponent("build.gradle.kts")
            let buildGradleData = try Data(contentsOf: buildPath)
            var buildGradleContents = String(data: buildGradleData, encoding: String.Encoding.utf8)
            buildGradleContents = buildGradleContents?.replacingOccurrences(of: "languageVersion.set(JavaLanguageVersion.of(", with: "languageVersion.set(JavaLanguageVersion.of(17)) // Skip replaced: ((") // just comment it out if it exists
            try buildGradleContents?.write(to: buildPath, atomically: true, encoding: String.Encoding.utf8)
        }

        try fixupBuildGradle()

        // the module name we created
        let lib = URL(fileURLWithPath: modname, isDirectory: true, relativeTo: tmp)

        var runIndex = 0

        // 2. gradle test --console plain --rerun-tasks
        for (failure, error, failFast) in [
            (false, false, false),
            (true, false, false),
            (true, true, false),
            //(true, true, true),
        ] {
            runIndex += 1
            // let canRunOffline = runIndex > 0 // after the initial run (when the dependencies should be downloaded and cached), we should be able to run the tests in offline mode

            // sabotage the test so it failes
            if failure || error {
                try sabotageTest(failure: failure, error: error)
            }

            let (output, parseResults) = try await driver.launchGradleProcess(in: tmp, module: modname, actions: ["test"], arguments: [], failFast: failFast, offline: false, exitHandler: { result in
                if !failure && !error {
                    guard case .terminated(0) = result.exitStatus else {
                        // we failed, but did not expect an error
                        return XCTFail("unexpected gradle process failure when running tests with failure=\(failure) error=\(error) failFast=\(failFast)")
                    }
                }
            })

            for try await line in output {
                let _ = line
                //print("TEST >", line)
            }

            let results = try parseResults()

            XCTAssertEqual(1, results.count)
            let firstResult = try XCTUnwrap(results.first)

            // failFast should max the error count at 1, but it doesn't seem to work — maybe related to https://github.com/gradle/gradle/issues/4562
            let expectedFailCount = (failure ? 1 : 0) + (error ? 1 : 0)
            XCTAssertEqual(expectedFailCount + 1, firstResult.tests)
            XCTAssertEqual(expectedFailCount, firstResult.failures)

            // gather up all the failures and ensure we see the ones we expect
            let allFailures = firstResult.testCases.flatMap(\.failures).map(\.message).map {
                $0.split(separator: ":").last?.trimmingCharacters(in: .whitespaces)
            }

            if failure {
                XCTAssertEqual("THIS TEST CASE ALWAYS FAILS", allFailures.first)
            }

            if error {
                XCTAssertEqual("THIS TEST CASE ALWAYS THROWS", allFailures.last)
            }
        }

        /// Add some test cases we know will fail to ensure they show up in the test results folder
        func sabotageTest(failure: Bool, error: Bool) throws {
            let samplePackageFolder = samplePackage.split(separator: ".").joined(separator: "/") // turn some.package into some/package
            let testCaseURL = URL(fileURLWithPath: "src/test/kotlin/" + samplePackageFolder + "/LibraryTest.kt", isDirectory: false, relativeTo: lib)
            var testCaseContents = try String(contentsOf: testCaseURL)

            if failure {
                // tack new failing and error test cases to the end by replacing the final test
                if !testCaseContents.contains("@Test fun someTestCaseThatAlwaysFails()") {
                    testCaseContents = testCaseContents.replacingOccurrences(of: "\n}\n", with: """

                        // added by GradleDriverTests.sabotageTest()
                        @Test fun someTestCaseThatAlwaysFails() {
                            assertTrue(false, "THIS TEST CASE ALWAYS FAILS")
                        }

                    }

                    """)
                }
            }

            if error {
                if !testCaseContents.contains("@Test fun someTestCaseThatAlwaysThrows()") {
                    // tack new failing and error test cases to the end by replacing the final test
                    testCaseContents = testCaseContents.replacingOccurrences(of: "\n}\n", with: """

                        // added by GradleDriverTests.sabotageTest()
                        @Test fun someTestCaseThatAlwaysThrows() {
                            throw Exception("THIS TEST CASE ALWAYS THROWS")
                        }

                    }

                    """)
                }
            }

            try testCaseContents.write(to: testCaseURL, atomically: true, encoding: String.Encoding.utf8)
        }
    }
}
#endif
#endif
