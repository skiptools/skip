@_exported import SkipPack
import Skip
@_exported import XCTest
import os.log

fileprivate let logger = Logger(subsystem: "skip", category: "test")

/// The base class for executing a transpiled test case.
open class SkipTestCase : XCTestCase {
    /// The list of modules that should be the transpilation target
    open var targets: SkipTargetSet? { nil }


    open override func setUp() async throws {
        try await super.setUp()
    }

    public func testTranspiledTests() async throws {
        guard let targets = targets else {
            if type(of: self) == SkipTestCase.self {
                return // we are the base type
            }
            struct NoTargetsSpecifiedError : Error { }
            throw NoTargetsSpecifiedError()
        }

        let srcRoot = URL(fileURLWithPath: targets.sourceBase.description, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        logger.info("transpiling and testing: \(targets.target.moduleName) from: \(srcRoot.path)")

        let destRoot = try await SkipAssembler.assemble(root: srcRoot, targets: targets, destRoot: ".build/skip/\(self.className)")

        #if DEBUG
        let target = "testDebugUnitTest"
        #else
        let target = "testReleaseUnitTest"
        #endif

        let verbose = { false }()

        do {
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
                "ANDROID_HOME": ("~/Library/Android/sdk" as NSString).expandingTildeInPath,
                "JAVA_HOME": "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home",
            ]

            try await System.exec(URL(fileURLWithPath: "/usr/bin/env", isDirectory: false), arguments: args, environment: env, workingDirectory: destRoot) { outputLine in
                logger.info("gradle: \(outputLine)")
            }
        } catch let Process.RunProcessError.nonZeroExit(errorCode, stdout, stderr) {
            let output = try stdout.readString() + stderr.readString()
            XCTFail("error \(errorCode) running script:\(output)")
        }
    }
}

extension XCTestCase {
    /// Checks that the given Swift compiles to the specified Kotlin.
    public func check(swift: String, kotlin: String? = nil, file: StaticString = #file, line: UInt = #line) async throws {
        let srcFile = try tmpFile(named: "Source.swift", contents: swift)
        if let kotlin = kotlin {
            let tp = Transpiler(sourceFiles: [Source.File(path: srcFile.path)])
            try await tp.transpile(handler: { transpilation in
                logger.debug("transpilation: \(transpilation.output.content)")
                XCTAssertEqual(kotlin.trimmingCharacters(in: .whitespacesAndNewlines), transpilation.output.content.trimmingCharacters(in: .whitespacesAndNewlines), file: file, line: line)
            })
        }
    }

    /// Creates a temporary file with the given name and optional contents.
    public func tmpFile(named fileName: String, contents: String? = nil) throws -> URL {
        let tmpDir = URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tmpFile = URL(fileURLWithPath: fileName, isDirectory: false, relativeTo: tmpDir)
        if let contents = contents {
            try contents.write(to: tmpFile, atomically: true, encoding: .utf8)
        }
        return tmpFile
    }
}
