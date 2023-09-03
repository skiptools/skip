import XCTest
import SkipDrive

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
class SkipCommandTests : XCTestCase {
    func testSkipVersion() async throws {
        try await XCTAssertEqualX("Skip version \(skipVersion)", skip("version").out)
    }

    func testSkipWelcome() async throws {
        try await skip("welcome")
    }

    func testSkipSelftest() async throws {
        try await skip("selftest")
    }

    func testSkipDoctor() async throws {
        try await skip("doctor")
    }

    func testSkipCreate() async throws {
        let tempDir = try mktmp()
        let name = "cool_app"
        let (stdout, _) = try await skip("create", "--no-build", "--no-test", "-d", tempDir, name)
        //print("skip create stdout: \(stdout)")
        let out = stdout.split(separator: "\n")
        XCTAssertEqual("Creating project \(name) from template skipapp", out.first)
        let dir = tempDir + "/" + name + "/"
        for path in ["Package.swift", "App.xcodeproj", "App.xcconfig", "Sources", "Tests"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir + path), "missing file at: \(path)")
        }

        let project = try await loadProjectPackage(dir)
        XCTAssertEqual("App", project.name)

        let config = try await loadProjectConfig(dir + "/App.xcodeproj", scheme: "App")
        XCTAssertEqual("App", config.first?.buildSettings["PROJECT_NAME"])

        //try await skip("check", "-d", tempDir)
    }

    func testSkipInit() async throws {
        let tempDir = try mktmp()
        let name = "cool-lib"
        let (stdout, _) = try await skip("init", "--no-build", "--no-test", "-d", tempDir, name, "CoolA") // , "CoolB", "CoolC", "CoolD", "CoolE")
        let out = stdout.split(separator: "\n")
        XCTAssertEqual("Initializing Skip library \(name)", out.first)
        let dir = tempDir + "/" + name + "/"
        for path in ["Package.swift", "Sources/CoolA", "Sources/CoolA", "Sources/CoolAKt", "Tests", "Tests/CoolAKtTests", "Tests/CoolAKtTests/Skip/skip.yml"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir + path), "missing file at: \(path)")
        }

        let project = try await loadProjectPackage(dir)
        XCTAssertEqual(name, project.name)

        //try await skip("check", "-d", tempDir)
    }

    func testSkipTestReport() async throws {
        let xunit = try mktmpFile(contents: Data(xunitResults.utf8))
        let tempDir = try mktmp()
        let junit = tempDir + "/" + "testDebugUnitTest"
        try FileManager.default.createDirectory(atPath: junit, withIntermediateDirectories: true)
        try Data(junitResults.utf8).write(to: URL(fileURLWithPath: junit + "/TEST-skip.zip.SkipZipTests.xml"))

        // .build/plugins/outputs/skip-zip/SkipZipKtTests/skip-transpiler/SkipZip/.build/SkipZip/test-results/testDebugUnitTest/TEST-skip.zip.SkipZipTests.xml
        let report = try await skip("test", "--configuration", "debug", "--no-test", "--max-column-length", "15", "--xunit", xunit, "--junit", junit)
        XCTAssertEqual(report.out, """
        | Test         | Case            | Swift | Kotlin |
        | ------------ | --------------- | ----- | ------ |
        | SkipZipTests | testArchive     | PASS  | SKIP   |
        | SkipZipTests | testDeflateInfl | PASS  | PASS   |
        | SkipZipTests | testMissingTest | PASS  | ????   |
        |              |                 | 100%  | 33%    |
        """)
        
//        +--------------+-----------------+-------+--------+
//        | Test         | Case            | Swift | Kotlin |
//        +--------------+-----------------+-------+--------+
//        | SkipZipTests | testArchive     | PASS  | SKIP   |
//        | SkipZipTests | testDeflateInfl | PASS  | PASS   |
//        | SkipZipTests | testMissingTest | PASS  | ????   |
//        +--------------+-----------------+-------+--------+
    }

    /// Runs the tool with the given arguments, returning the entire output string as well as a function to parse it to `JSON`
    @discardableResult func skip(checkError: Bool = true, _ args: String...) async throws -> (out: String, err: String) {
        #if canImport(SkipDriver)
        let out = BufferedOutputByteStream()
        let err = BufferedOutputByteStream()

        try await SkipDriver.run(args, out: out, err: err)

        let outString = out.bytes.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let errString = err.bytes.description.trimmingCharacters(in: .whitespacesAndNewlines)

        if checkError {
            if !errString.isEmpty {
                struct SkipErrorResult : LocalizedError {
                    var errorDescription: String?
                }
                throw SkipErrorResult(errorDescription: "")
            }
        }
        return (out: outString, err: errString)
        #else
        // we are not linking to the skip driver, so fork the process instead with the proper arguments

        let result = try await Process.popen(arguments: ["skip"] + args, loggingHandler: nil)
        // Throw if there was a non zero termination.
        guard result.exitStatus == .terminated(code: 0) else {
            throw ProcessResult.Error.nonZeroExit(result)
        }
        let (out, err) = try (result.utf8Output(), result.utf8stderrOutput())
        return (out: out.trimmingCharacters(in: .whitespacesAndNewlines), err: err.trimmingCharacters(in: .whitespacesAndNewlines))
        #endif
    }

}

/// Create a temporary directory
func mktmp(baseName: String = "SkipDriveTests") throws -> String {
    let tempDir = [NSTemporaryDirectory(), baseName, UUID().uuidString].joined(separator: "/")
    try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    return tempDir
}

/// Create a temporary directory
func mktmpFile(baseName: String = "SkipDriveTests", named: String = "file-\(UUID().uuidString)", contents: Data) throws -> String {
    let tempDir = try mktmp(baseName: baseName)
    let tempFile = tempDir + "/" + named
    try contents.write(to: URL(fileURLWithPath: tempFile), options: .atomic)
    return tempFile
}

func loadProjectPackage(_ path: String) async throws -> PackageManifest {
    try await execJSON(["swift", "package", "dump-package", "--package-path", path])
}

func loadProjectConfig(_ path: String, scheme: String? = nil) async throws -> [ProjectBuildSettings] {
    try await execJSON(["xcodebuild", "-showBuildSettings", "-json", "-project", path] + (scheme == nil ? [] : ["-scheme", scheme!]))
}

func execJSON<T: Decodable>(_ arguments: [String]) async throws -> T {
    let output = try await Process.checkNonZeroExit(arguments: arguments, loggingHandler: nil)
    return try JSONDecoder().decode(T.self, from: Data(output.utf8))
}

/// Cover for `XCTAssertEqual` that permit async autoclosures.
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
func XCTAssertEqualX<T>(_ expression1: T, _ expression2: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}



/// An incomplete representation of package JSON, to be filled in as needed for the purposes of the tool
/// The output from `swift package dump-package`.
struct PackageManifest : Hashable, Decodable {
    var name: String
    //var toolsVersion: String // can be string or dict
    var products: [Product]
    var dependencies: [Dependency]
    //var targets: [Either<Target>.Or<String>]
    var platforms: [SupportedPlatform]
    var cModuleName: String?
    var cLanguageStandard: String?
    var cxxLanguageStandard: String?

    struct Target: Hashable, Decodable {
        enum TargetType: String, Hashable, Decodable {
            case regular
            case test
            case system
        }

        var `type`: TargetType
        var name: String
        var path: String?
        var excludedPaths: [String]?
        //var dependencies: [String]? // dict
        //var resources: [String]? // dict
        var settings: [String]?
        var cModuleName: String?
        // var providers: [] // apt, brew, etc.
    }


    struct Product : Hashable, Decodable {
        //var `type`: ProductType // can be string or dict
        var name: String
        var targets: [String]

        enum ProductType: String, Hashable, Decodable, CaseIterable {
            case library
            case executable
        }
    }

    struct Dependency : Hashable, Decodable {
        var name: String?
        var url: String?
        //var requirement: Requirement // revision/range/branch/exact
    }

    struct SupportedPlatform : Hashable, Decodable {
        var platformName: String
        var version: String
    }
}


/// The output from `xcodebuild -showBuildSettings -json -project Project.xcodeproj -scheme SchemeName`
struct ProjectBuildSettings : Decodable {
    let target: String
    let action: String
    let buildSettings: [String: String]
}




// sample test output generated with the following command in the skip-zip package:
// swift test --enable-code-coverage --parallel --xunit-output=.build/swift-xunit.xml --filter=SkipZipTests

// .build/plugins/outputs/skip-zip/SkipZipKtTests/skip-transpiler/SkipZip/.build/SkipZip/test-results/testDebugUnitTest/TEST-skip.zip.SkipZipTests.xml
let junitResults = """
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="skip.zip.SkipZipTests" tests="2" skipped="1" failures="0" errors="0" timestamp="2023-08-23T16:53:50" hostname="zap.local" time="0.02">
  <properties/>
  <testcase name="testDeflateInflate" classname="skip.zip.SkipZipTests" time="0.019"/>
  <testcase name="testArchive$SkipZip_debugUnitTest" classname="skip.zip.SkipZipTests" time="0.001">
    <skipped/>
  </testcase>
  <system-out><![CDATA[]]></system-out>
  <system-err><![CDATA[Aug 23, 2023 12:53:50 PM skip.foundation.SkipLogger log
INFO: running test
]]></system-err>
</testsuite>
"""

// .build/swift-xunit.xml
let xunitResults = """
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
<testsuite name="TestResults" errors="0" tests="4" failures="0" time="15.553686000999999">
<testcase classname="SkipZipTests.SkipZipTests" name="testDeflateInflate" time="0.047230875">
</testcase>
<testcase classname="SkipZipTests.SkipZipTests" name="testArchive" time="7.729590584">
</testcase>
<testcase classname="SkipZipTests.SkipZipTests" name="testMissingTest" time="0.01">
</testcase>
<testcase classname="SkipZipKtTests.SkipZipKtTests" name="testSkipModule" time="7.729628">
</testcase>
</testsuite>
</testsuites>
"""
