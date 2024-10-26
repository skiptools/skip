// Copyright 2023 Skip
#if !SKIP
#if canImport(SkipDrive)
import SkipDrive
#if os(macOS)
@_exported import XCTest

/// A `XCTestCase` that invokes the `gradle` process.
///
/// When run as part of a test suite, JUnit XML test reports are parsed and converted to Xcode issues, along with any reverse-source mappings from transpiled Kotlin back into the original Swift.
@available(macOS 13, macCatalyst 16, *)
@available(iOS, unavailable, message: "Gradle tests can only be run on macOS")
@available(watchOS, unavailable, message: "Gradle tests can only be run on macOS")
@available(tvOS, unavailable, message: "Gradle tests can only be run on macOS")
public protocol XCGradleHarness : GradleHarness {
}

@available(macOS 13, macCatalyst 16, *)
@available(iOS, unavailable, message: "Gradle tests can only be run on macOS")
@available(watchOS, unavailable, message: "Gradle tests can only be run on macOS")
@available(tvOS, unavailable, message: "Gradle tests can only be run on macOS")
extension XCGradleHarness where Self : XCTestCase {

    /// Invoke the Gradle tests using the Robolectric simulator, or the specified device emulator/device ID (or blank string to use the first one)
    ///
    /// - Parameters:
    ///   - device: the device ID to test against, defaulting to the `ANDROID_SERIAL` environment property.
    ///
    /// - SeeAlso: https://developer.android.com/studio/test/command-line
    /// - SeeAlso: https://docs.gradle.org/current/userguide/java_testing.html#test_filtering
    public func runGradleTests(device: String? = ProcessInfo.processInfo.environment["ANDROID_SERIAL"], file: StaticString = #file, line: UInt = #line) async throws {
        do {
            #if DEBUG
            let testAction = device == nil ? "testDebug" : "connectedDebugAndroidTest"
            #else
            // there is no "connectedReleaseAndroidTest" target for some reason, so release tests against an Android emulator/simulator do not work
            let testAction = device == nil ? "testRelease" : "connectedAndroidTest"
            #endif
            let info = !["NO", "no", "false", "0"].contains(ProcessInfo.processInfo.environment["SKIP_GRADLE_VERBOSE"] ?? "NO")
            try await invokeGradle(actions: [testAction], info: info, deviceID: device)
            print("Completed gradle test run for \(device ?? "local")")
        } catch {
            XCTFail("\((error as? LocalizedError)?.localizedDescription ?? error.localizedDescription)", file: file, line: line)
        }
    }

    /// Invokes the `gradle` process with the specified arguments.
    ///
    /// This is typically used to invoke test cases, but any actions and arguments can be specified, which can be used to drive the Gradle project in custom ways from a Skip test case.
    /// - Parameters:
    ///   - actions: the actions to invoke, such as `test` or `assembleDebug`
    ///   - arguments: and additional arguments
    ///   - deviceID: the optional device ID against which to run
    ///   - moduleSuffix: the expected module name for automatic test determination
    ///   - sourcePath: the full path to the test case call site, which is used to determine the package root
    @available(macOS 13, macCatalyst 16, iOS 16, tvOS 16, watchOS 8, *)
    func invokeGradle(actions: [String], arguments: [String] = [], info: Bool = false, deviceID: String? = nil, testFilter: String? = nil, moduleName: String? = nil, maxMemory: UInt64? = ProcessInfo.processInfo.physicalMemory, fromSourceFileRelativeToPackageRoot sourcePath: StaticString? = #file) async throws {

        // the filters should be passed through to the --tests argument, but they don't seem to work for Android unit tests, neighter for Robolectric nor connected tests
        precondition(testFilter == nil, "test filtering does not yet work")

        var actions = actions
        //let isTestAction = testFilter != nil
        let isTestAction = actions.contains(where: { $0.hasPrefix("test") })


        // override test targets so we can specify "SKIP_GRADLE_TEST_TARGET=connectedDebugAndroidTest" and have the tests run against the Android emulator (e.g., using reactivecircus/android-emulator-runner@v2 with CI)
        let override = ProcessInfo.processInfo.environment["SKIP_GRADLE_TEST_TARGET"]
        if let testOverride = override {
            actions = actions.map {
                $0 == "test" || $0 == "testDebug" || $0 == "testRelease" ? testOverride : $0
            }
        }

        let testModuleSuffix = "Tests"
        let moduleSuffix = isTestAction ? testModuleSuffix : ""

        if #unavailable(macOS 13, macCatalyst 16) {
            fatalError("unsupported platform")
        } else {
            // only run in subclasses, not in the base test
            if self.className == "SkipUnit.XCGradleHarness" {
                // TODO: add a general system gradle checkup test here
            } else {
                let selfType = type(of: self)
                let moduleName = moduleName ?? String(reflecting: selfType).components(separatedBy: ".").first ?? ""
                if isTestAction && !moduleName.hasSuffix(moduleSuffix) {
                    throw InvalidModuleNameError(errorDescription: "The module name '\(moduleName)' is invalid for running gradle tests; it must end with '\(moduleSuffix)'")
                }
                let driver = try await GradleDriver()

                let dir = try pluginOutputFolder(moduleName: moduleName, linkingInto: linkFolder(forSourceFile: sourcePath))

                // tests are run in the merged base module (e.g., "SkipLib") that corresponds to this test module name ("SkipLibTests")
                let baseModuleName = moduleName.dropLast(testModuleSuffix.count).description

                var testProcessResult: ProcessResult? = nil

                var env: [String: String] = ProcessInfo.processInfo.environmentWithDefaultToolPaths
                if let deviceID = deviceID, !deviceID.isEmpty {
                    env["ANDROID_SERIAL"] = deviceID
                }

                var args = arguments
                if let testFilter = testFilter {
                    // NOTE: test filtering does not seem to work; no patterns are matched,
                    args += ["--tests", testFilter]
                }

                // specify additional arguments in the GRADLE_ARGUMENT variable, such as `-P android.testInstrumentationRunnerArguments.package=skip.ui.SkipUITests`
                if let gradleArgument = env["GRADLE_ARGUMENT"] {
                    args += [gradleArgument]
                }

                let (output, parseResults) = try await driver.launchGradleProcess(in: dir, module: baseModuleName, actions: actions, arguments: args, environment: env, info: info, maxMemory: maxMemory, exitHandler: { result in
                    // do not fail on non-zero exit code because we want to be able to parse the test results first
                    testProcessResult = result
                })

                var previousOutput: AsyncLineOutput.Element? = nil
                for try await pout in output {
                    let line = pout.line
                    print(outputPrefix, line)
                    // check for errors and report them to the IDE with a 1-line buffer
                    scanGradleOutput(line1: previousOutput?.line ?? line, line2: line)
                    previousOutput = pout
                }

                let failedTests: [String]

                // if any of the actions are a test case, when try to parse the XML results
                if isTestAction {
                    let testSuites = try parseResults()
                    // the absense of any test data probably indicates some sort of mis-configuration or else a build failure
                    if testSuites.isEmpty {
                        XCTFail("No tests were run; this may indicate an issue with running the tests on \(deviceID ?? "Robolectric"). See the test output and Report Navigator log for details.")
                    }
                    failedTests = reportTestResults(testSuites, dir).map(\.fullName)
                } else {
                    failedTests = []
                }

                switch testProcessResult?.exitStatus {
                case .terminated(let code):
                    // this is a general error that is reported whenever gradle fails, so that the overall test will fail even when we cannot parse any build errors or test failures
                    // there should be additional messages in the log to provide better indication of where the test failed
                    if code != 0 {
                        if !failedTests.isEmpty {
                            // TODO: output test summary and/or a log file and have the xcode error link to the file so the user can see a summary of the failed tests
                            throw GradleDriverError("The gradle action \(actions) failed with \(failedTests.count) test \(failedTests.count == 1 ? "failure" : "failures"). Review the logs for individual test case results. Failed tests: \(failedTests.joined(separator: ", "))")
                        } else {
                            throw GradleDriverError("gradle \(actions.first?.description ?? "") failed, which may indicate a build error or a test failure. Examine the log tab for more details. See https://skip.tools/docs")
                        }
                    }
                default:
                    throw GradleBuildError(errorDescription: "Gradle failed with result: \(testProcessResult?.description ?? "")")
                }
            }
        }
    }


    /// The contents typically contain a stack trace, which we need to parse in order to try to figure out the source code and line of the failure:
    /// ```
    ///  org.junit.ComparisonFailure: expected:<ABC[]> but was:<ABC[DEF]>
    ///      at org.junit.Assert.assertEquals(Assert.java:117)
    ///      at org.junit.Assert.assertEquals(Assert.java:146)
    ///      at skip.unit.XCTestCase.XCTAssertEqual(XCTest.kt:31)
    ///      at skip.lib.SkipLibTests.testSkipLib$SkipLib(SkipLibTests.kt:16)
    ///      at java.base/jdk.internal.reflect.DirectMethodHandleAccessor.invoke(DirectMethodHandleAccessor.java:104)
    ///      at java.base/java.lang.reflect.Method.invoke(Method.java:578)
    ///      at org.junit.runners.model.FrameworkMethod$1.runReflectiveCall(FrameworkMethod.java:59)
    /// ```
    ///
    /// ```
    /// java.lang.AssertionError: ABCX != ABC
    ///      at org.junit.Assert.fail(Assert.java:89)
    ///      at org.junit.Assert.assertTrue(Assert.java:42)
    ///      at skip.unit.XCTestCase$DefaultImpls.XCTAssertEqual(XCTest.kt:68)
    ///      at app.model.AppModelTests.XCTAssertEqual(AppModelTests.kt:10)
    ///      at app.model.AppModelTests.testAppModelA$AppModel_debugUnitTest(AppModelTests.kt:14)
    /// ```
    ///
    /// ```
    ///  java.lang.AssertionError: ABCZ != ABC
    ///      at org.junit.Assert.fail(Assert.java:89)
    ///      at org.junit.Assert.assertTrue(Assert.java:42)
    ///      at skip.unit.XCTestCase$DefaultImpls.XCTAssertEqual(XCTest.kt:68)
    ///      at app.model.AppModelTests.XCTAssertEqual(AppModelTests.kt:10)
    ///      at app.model.AppModelTests$testAppModelB$2.invokeSuspend(AppModelTests.kt:31)
    ///      at app.model.AppModelTests$testAppModelB$2.invoke(AppModelTests.kt)
    ///      at app.model.AppModelTests$testAppModelB$2.invoke(AppModelTests.kt)
    ///      at skip.lib.Async$Companion$run$2.invokeSuspend(Concurrency.kt:153)
    ///      at _COROUTINE._BOUNDARY._(CoroutineDebugging.kt:46)
    ///      at app.model.AppModelTests$runtestAppModelB$1$1.invokeSuspend(AppModelTests.kt:23)
    ///      at app.model.AppModelTests$runtestAppModelB$1.invokeSuspend(AppModelTests.kt:23)
    ///      at kotlinx.coroutines.test.TestBuildersKt__TestBuildersKt$runTest$2$1$1.invokeSuspend(TestBuilders.kt:314)
    /// ```
    ///
    private func extractSourceLocation(dir: URL, moduleName: String, failure: GradleDriver.TestFailure) -> (kotlin: SourceLocation?, swift: SourceLocation?) {
        let modulePath = dir.appendingPathComponent(String(moduleName), isDirectory: true)

        // turn: "at skip.lib.SkipLibTests.testSkipLib$SkipLib(SkipLibTests.kt:16)"
        // into: src/main/skip/lib/SkipLibTests.kt line: 16

        // take the bottom-most nested stack trace, since that should be the one with the true call stack in the case of a coroutine test
        let stackTrace = failure.contents?.split(separator: "\nCaused by: ").last ?? ""

        var skipNextLine = false

        for line in stackTrace.split(separator: "\n") {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            // make sure it matches the pattern: "at skip.lib.SkipLibTests.testSkipLib$SkipLib(SkipLibTests.kt:16)"
            if !trimmedLine.hasPrefix("at ") || !line.hasSuffix(")") {
                continue
            }

            if skipNextLine {
                skipNextLine = false
                continue
            }

            let lineParts = trimmedLine.dropFirst(3).dropLast().split(separator: "(").map(\.description) // drop the "at" and final paren

            // get the contents of the final parens, like: (SkipLibTests.kt:16)
            guard lineParts.count == 2,
                  let stackElement = lineParts.first,
                  let fileLine = lineParts.last else {
                continue
            }

            if stackElement.hasPrefix("org.junit.") {
                // skip over JUnit stack elements
                // e.g.: at org.junit.Assert.assertNotNull(Assert.java:723)
                continue
            }

            if stackElement.hasPrefix("skip.unit.XCTestCase") {
                // skip over assertion wrappers
                // e.g.: at skip.unit.XCTestCase$DefaultImpls.XCTAssertNotNil(XCTest.kt:55)
                if stackElement.hasPrefix("skip.unit.XCTestCase$DefaultImpls") {
                    // this means that the next line will be the inlined implementation of an assertion of other XCUnit extension, which should be ignored (since the line number is not useful). E.g.:
                    // app.model.AppModelTests.XCTAssertEqual(AppModelTests.kt:10)
                    skipNextLine = true
                }
                continue
            }

            if !stackElement.contains("$") {
                // the test case itself will contain 
                // e.g.: at skip.unit.XCTestCase$DefaultImpls.XCTAssertNotNil(XCTest.kt:55)
                continue
            }

            // check the format of the "SkipLibTests.kt:16" line, and only continut for Kotlin files
            let parts = fileLine.split(separator: ":").map(\.description)
            guard parts.count == 2,
                  let fileName = parts.first,
                  let fileLine = parts.last,
                  let fileLineNumber = Int(fileLine),
                  fileName.hasSuffix(".kt") else {
                continue
            }

            // now look at the stackElement like "skip.lib.SkipLibTests.testSkipLib$SkipLib" and turn it into "skip/lib/SkipLibTests.kt"
            let packageElements = stackElement.split(separator: ".").map(\.description)

            // we have the base file name; now construct the file path based on the package name of the failing stack
            // we need to check in both the base source folders of the project: "src/test/kotlin/" and "src/main/kotlin/"
            // also include (legacy) Java paths, which by convention can also contain Kotlin files
            for folder in [
                modulePath.appendingPathComponent("src/test/kotlin/", isDirectory: true),
                modulePath.appendingPathComponent("src/main/kotlin/", isDirectory: true),
                modulePath.appendingPathComponent("src/test/java/", isDirectory: true),
                modulePath.appendingPathComponent("src/main/java/", isDirectory: true),
            ] {
                var filePath = folder

                for packagePart in packageElements {
                    if packagePart.lowercased() != packagePart {
                        // assume the convention of package names being lower-case and class names being camel-case
                        break
                    }
                    filePath = filePath.appendingPathComponent(packagePart, isDirectory: true)
                }

                // finally, tack on the name of the kotlin file to the end of the path
                filePath = filePath.appendingPathComponent(fileName, isDirectory: false)

                // check whether the file exists; if not, it may be in another of the root folders
                if FileManager.default.fileExists(atPath: filePath.path) {
                    let kotlinLocation = SourceLocation(path: filePath.path, position: .init(line: fileLineNumber, column: 0))
                    let swiftLocation = try? kotlinLocation.findSourceMapLine()
                    return (kotlinLocation, swiftLocation)
                }
            }
        }

        return (nil, nil)
    }

    /// Parse the console output from Gradle and looks for errors of the form
    ///
    /// ```
    /// e: file:///…/skiphub.output/SkipSQLTests/skipstone/SkipSQL/src/main/kotlin/skip/sql/SkipSQL.kt:94:26 Function invocation 'blob(...)' expected
    /// ```
    public func scanGradleOutput(line1: String, line2: String) {
        guard var issue = parseGradleOutput(line1: line1, line2: line2) else {
            return
        }

        // only turn errors into assertion failures
        if issue.kind != .error {
            return
        }

        if var location = issue.location, 
            let linkDestination = try? FileManager.default.destinationOfSymbolicLink(atPath: location.path) {
            // attempt the map the error back any originally linking source projects, since it is better the be editing the canonical Xcode version of the file as Xcode is able to provide details about it
            location.path = linkDestination
            issue.location = location
        }

        record(XCTIssue(type: .assertionFailure, compactDescription: issue.message, detailedDescription: issue.message, sourceCodeContext: XCTSourceCodeContext(location: issue.location?.contextLocation), associatedError: nil, attachments: []))

        // if the error maps back to a Swift source file, then also report that location
        if let swiftLocation = try? issue.location?.findSourceMapLine() {
            record(XCTIssue(type: .assertionFailure, compactDescription: issue.message, detailedDescription: issue.message, sourceCodeContext: XCTSourceCodeContext(location: swiftLocation.contextLocation), associatedError: nil, attachments: []))
        }
    }

    /// Parse the test suite results and output the summary to standard out
    /// - Returns: an array of failed test case names
    private func reportTestResults(_ testSuites: [GradleDriver.TestSuite], _ dir: URL, showStreams: Bool = true) -> [GradleDriver.TestCase] {

        // do one intial pass to show the stdout and stderror
        if showStreams {
            for testSuite in testSuites {
                let testSuiteName = testSuite.name.split(separator: ".").last?.description ?? testSuite.name

                // all the stdout/stderr is batched together for all test tests, so output it all at the end
                // and line up the spaced with the "GRADLE TEST CASE" line describing the test
                if let systemOut = testSuite.systemOut {
                    print("JUNIT TEST STDOUT: \(testSuiteName):")
                    let prefix = "STDOUT> "
                    print(prefix + systemOut.split(separator: "\n").joined(separator: "\n" + prefix))
                }
                if let systemErr = testSuite.systemErr {
                    print("JUNIT TEST STDERR: \(testSuiteName):")
                    let prefix = "STDERR> "
                    print(prefix + systemErr.split(separator: "\n").joined(separator: "\n" + prefix))
                }
            }
        }

        var passTotal = 0, failTotal = 0, skipTotal = 0, suiteTotal = 0, testsTotal = 0
        var timeTotal = 0.0
        //var failedTests: [String] = []

        // parse the test result XML files and convert test failures into XCTIssues with links to the failing source and line
        for testSuite in testSuites {
            // Turn "skip.foundation.TestDateIntervalFormatter" into "TestDateIntervalFormatter"
            let testSuiteName = testSuite.name.split(separator: ".").last?.description ?? testSuite.name

            suiteTotal += 1
            var pass = 0, fail = 0, skip = 0
            var timeSuite = 0.0
            defer {
                passTotal += pass
                failTotal += fail
                skipTotal += skip
                timeTotal += timeSuite
            }

            for testCase in testSuite.testCases {
                testsTotal += 1
                if testCase.skipped {
                    skip += 1
                } else if testCase.failures.isEmpty {
                    pass += 1
                } else {
                    fail += 1
                }
                timeSuite += testCase.time

                var msg = ""

                // msg += className + "." // putting the class name in makes the string long

                let nameParts = testCase.name.split(separator: "$")

                // test case names are like: "testSystemRandomNumberGenerator$SkipFoundation()" or "runtestAppModelB$AppModel_debugUnitTest"
                let testName = nameParts.first?.description ?? testCase.name
                msg += testSuiteName + "." + testName

                if !testCase.skipped {
                    msg += " (" + testCase.time.description + ") " // add in the time for profiling
                }

                print("JUNIT TEST", testCase.skipped ? "SKIPPED" : testCase.failures.isEmpty ? "PASSED" : "FAILED", msg)
                // add a failure for each reported failure
                for failure in testCase.failures {
                    var failureMessage = failure.message
                    let trimPrefixes = [
                        "testSkipModule(): ",
                        //"java.lang.AssertionError: ",
                    ]
                    for trimPrefix in trimPrefixes {
                        if failureMessage.hasPrefix(trimPrefix) {
                            failureMessage.removeFirst(trimPrefix.count)
                        }
                    }

                    let failureContents = failure.contents ?? ""
                    print(failureContents)

                    // extract the file path and report the failing file and line to Xcode via an issue
                    var msg = msg
                    msg += failure.type ?? ""
                    msg += ": "
                    msg += failureMessage
                    msg += ": "
                    msg += failureContents // add the stack trace

                    // convert the failure into an XCTIssue so we can see where in the source it failed
                    let issueType: XCTIssueReference.IssueType

                    // check for common known assertion failure exception types
                    if failure.type?.hasPrefix("org.junit.") == true
                        || failure.type?.hasPrefix("org.opentest4j.") == true {
                        issueType = .assertionFailure
                    } else {
                        // we might rather mark it as a `thrownError`, but Xcode seems to only report a single thrownError, whereas it will report multiple `assertionFailure`
                        // issueType = .thrownError
                        issueType = .assertionFailure
                    }

                    guard let moduleName = nameParts.dropFirst().first?.split(separator: "_").first?.description else {
                        let desc = "Could not extract module name from test case name: \(testCase.name)"
                        let issue = XCTIssue(type: .assertionFailure, compactDescription: desc, detailedDescription: desc, sourceCodeContext: XCTSourceCodeContext(), associatedError: nil, attachments: [])
                        record(issue)

                        continue
                    }

                    let (kotlinLocation, swiftLocation) = extractSourceLocation(dir: dir, moduleName: moduleName, failure: failure)

                    // and report the Kotlin error so the user can jump to the right place
                    if let kotlinLocation = kotlinLocation {
                        let issue = XCTIssue(type: issueType, compactDescription: failure.message, detailedDescription: failure.contents, sourceCodeContext: XCTSourceCodeContext(location: kotlinLocation.contextLocation), associatedError: nil, attachments: [])
                        record(issue)
                    }

                    // we managed to link up the Kotlin line with the Swift source file, so add an initial issue with the swift location
                    if let swiftLocation = swiftLocation {
                        let issue = XCTIssue(type: issueType, compactDescription: failure.message, detailedDescription: failure.contents, sourceCodeContext: XCTSourceCodeContext(location: swiftLocation.contextLocation), associatedError: nil, attachments: [])
                        record(issue)
                    }
                }
            }

            print("JUNIT TEST SUITE: \(testSuiteName): PASSED \(pass) FAILED \(fail) SKIPPED \(skip) TIME \(round(timeSuite * 100.0) / 100.0)")
        }


        var failedTests: [GradleDriver.TestCase] = []
        // show all the failures just before the final summary for ease of browsing
        for testSuite in testSuites {
            for testCase in testSuite.testCases {
                if !testCase.failures.isEmpty {
                    failedTests.append(testCase)
                }
                for failure in testCase.failures {
                    print(testCase.name, failure.message)
                    if let stackTrace = failure.contents {
                        print(stackTrace)
                    }
                }
            }
        }

        let passPercentage = Double(passTotal) / (testsTotal == 0 ? Double.nan : Double(testsTotal))
        print("JUNIT SUITES \(suiteTotal) TESTS \(testsTotal) PASSED \(passTotal) (\(round(passPercentage * 100))%) FAILED \(failTotal) SKIPPED \(skipTotal) TIME \(round(timeTotal * 100.0) / 100.0)")

        return failedTests
    }

}

extension SourceLocation {
    /// Returns a `XCTSourceCodeLocation` suitable for reporting from a test case
    var contextLocation: XCTSourceCodeLocation {
        XCTSourceCodeLocation(filePath: path, lineNumber: position.line)
    }
}

struct InvalidModuleNameError : LocalizedError {
    var errorDescription: String?
}

struct GradleBuildError : LocalizedError {
    var errorDescription: String?
}

#endif // os(macOS)
#endif // canImport(SkipDrive)
#endif // !SKIP
