@_exported import SkipPack
@_exported import XCTest
import Skip
import os.log

fileprivate let logger = Logger(subsystem: "skip", category: "testing")

/// The base class for executing a transpiled test case.
open class SkipTranspilerTestCase : XCTestCase {
    /// Whether the fork the tests from the XCTestCase
    public static var testInProcess = true

    /// The list of modules that should be the transpilation target
    open var targets: SkipTargetSet? { nil }


    open override func setUp() async throws {
        try await super.setUp()
    }
}

extension SkipTranspilerTestCase {
    public func runGradleTests() async throws {
        guard let targets = targets else {
            struct NoTargetsSpecifiedError : Error { }
            throw NoTargetsSpecifiedError()
        }

        // locate the root package for this test case (assuming shallow test directory structure of Tests/ModuleName/TestCase.swift)
        let srcRoot = URL(fileURLWithPath: targets.sourceBase.description, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        // turn SomeLibTests.SomeLibTests/ into SomeLibTests/
        let testOutputBase = self.className.split(separator: ".").first ?? .init(self.className)
        try await SkipAssembler.transpileAndTest(testCase: Self.testInProcess ? self : nil, root: srcRoot, targets: targets, destRoot: "\(SkipAssembler.kipFolderName)/\(testOutputBase)")
    }
}

extension SkipAssembler {
    @discardableResult public static func transpileAndTest(testCase: SkipTranspilerTestCase?, root packageRoot: URL, sourceFolder: String = "Sources", testsFolder: String? = "Tests", targets: SkipTargetSet, destRoot: String, overwrite: Bool = true, studioID: String = androidStudioBundleID) async throws -> URL {
        logger.info("transpiling and testing: \(targets.target.moduleName) from: \(packageRoot.path)")

        // transpile and assemble the gradle project in the given destination
        let (destRoot, paths) = try await SkipAssembler.assemble(root: packageRoot, targets: targets, destRoot: destRoot)

        #if DEBUG
        let target = "testDebugUnitTest"
        #else
        let target = "testReleaseUnitTest"
        #endif

        guard let testCase = testCase else {
            logger.info("skipping test cases; run or watch manually with: \(destRoot.path)/gradlew -p \(destRoot.path) test -t")
            return destRoot // only fork the tests if we have specified a test case
        }

        let verbose = { false }()

        logger.debug("exec: \(destRoot.appendingPathComponent("gradlew").path)")
        let args = [
            destRoot.appendingPathComponent("gradlew").path,
            "--no-daemon",
            "--console", "plain",
            verbose ? "--info" : nil,
            "--stacktrace",
            "--rerun-tasks", // re-run tests
            "--project-dir", destRoot.path,
            target,
        ].compactMap({ $0 })

        let env = [
            // if the gradle.properties contains `org.gradle.jvmargs`, then that need to match here otherwise a daemon will be forked regardless of the "--no-daemon" flag
            // "GRADLE_OPTS": "-Xmx512m -Dorg.gradle.daemon=false", // otherwise: “To honour the JVM settings for this build a single-use Daemon process will be forked.”
            "ANDROID_HOME": ("~/Library/Android/sdk" as NSString).expandingTildeInPath, // the standard install for the SDK
            // overrides JAVA_HOME
            // "JAVA_HOME": "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home",
        ]

        try await System.exec(URL(fileURLWithPath: "/usr/bin/env", isDirectory: false), arguments: args, environment: env, workingDirectory: destRoot) { outputLine in
            logger.debug("gradle: \(outputLine)")
            // errors look like: java.lang.AssertionError at SkipFoundationTests.kt:13
            let line = outputLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("java.lang.AssertionError") {
                if let fileLine = outputLine.components(separatedBy: " at ").last,
                   let fileName = fileLine.split(separator: ":").first,
                   let fileLine = Int(fileLine.split(separator: ":").last ?? "") {
                    // the file is unfortunately only the last path component, so we need to manually find it to match it back to the issue so Xcode can jump to the right line in the generated content; so we look up the full path from the list of transpiled URLs (hoping the test file names are unique)
                    let filePath = paths.first(where: { $0.lastPathComponent == fileName })?.path ?? String(fileName)
                    testCase.record(XCTIssue(type: .assertionFailure, compactDescription: line, detailedDescription: line, sourceCodeContext: XCTSourceCodeContext(location: XCTSourceCodeLocation(filePath: filePath, lineNumber: fileLine)), associatedError: nil, attachments: []))
                }
                //XCTFail(line)
            }
        }

        return destRoot
    }
}

extension XCTestCase {
    /// Checks that the given Swift compiles to the specified Kotlin.
    public func check(swift: String, kotlin: String? = nil, file: StaticString = #file, line: UInt = #line) async throws {
        /// Creates a temporary file with the given name and optional contents.
        func tmpFile(named fileName: String, contents: String? = nil) throws -> URL {
            let tmpDir = URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let tmpFile = URL(fileURLWithPath: fileName, isDirectory: false, relativeTo: tmpDir)
            if let contents = contents {
                try contents.write(to: tmpFile, atomically: true, encoding: .utf8)
            }
            return tmpFile
        }

        let srcFile = try tmpFile(named: "Source.swift", contents: swift)
        if let kotlin = kotlin {
            let tp = Transpiler(sourceFiles: [Source.File(path: srcFile.path)])
            try await tp.transpile(handler: { transpilation in
                logger.debug("transpilation: \(transpilation.output.content)")
                XCTAssertEqual(kotlin.trimmingCharacters(in: .whitespacesAndNewlines), transpilation.output.content.trimmingCharacters(in: .whitespacesAndNewlines), file: file, line: line)
            })
        }
    }

}
