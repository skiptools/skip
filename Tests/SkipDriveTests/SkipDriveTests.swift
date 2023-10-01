// Copyright 2023 Skip
import XCTest
import SkipDrive

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
class SkipCommandTests : XCTestCase {
    func testSkipVersion() async throws {
        var versionOut = try await skip("version").out
        if versionOut.hasSuffix(" (debug)") {
            versionOut.removeLast(" (debug)".count)
        }

        XCTAssertEqual("Skip version \(SkipDrive.skipVersion)", versionOut)
    }

    func testSkipVersionJSON() async throws {
        try await XCTAssertEqualAsync(SkipDrive.skipVersion, skip("version", "--json").out.parseJSONObject()["version"] as? String)
    }

    func testSkipWelcome() async throws {
        try await skip("welcome")
    }

    func testSkipWelcomeJSON() async throws {
        let welcome = try await skip("welcome", "--json", "--json-array").out.parseJSONArray()
        XCTAssertNotEqual(0, welcome.count, "Welcome message should not be empty")
    }

    func XXXtestSkipCheckup() async throws {
        try await skip("checkup")
    }

    func testSkipDoctor() async throws {
        try await skip("doctor")
    }

    func testSkipCreate() async throws {
        let tempDir = try mktmp()
        let templateModuleName = "WeatherApp"
        let name = "cool_app"
        let (stdout, _) = try await skip("app", "create", "--no-build", "--no-test", "-d", tempDir, name)
        //print("skip create stdout: \(stdout)")
        let out = stdout.split(separator: "\n")
        XCTAssertEqual("Creating project \(name) from template skipapp", out.first)
        let dir = tempDir + "/" + name + "/"
        for path in ["Package.swift", templateModuleName + ".xcodeproj", "App.xcconfig", "Sources", "Tests"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir + path), "missing file at: \(path)")
        }

        let project = try await loadProjectPackage(dir)
        XCTAssertEqual(templateModuleName, project.name)

        let config = try await loadProjectConfig(dir + "/\(templateModuleName).xcodeproj", scheme: "App")
        XCTAssertEqual(templateModuleName, config.first?.buildSettings["PROJECT_NAME"])

        // run the app checks and verify JSON output
        //let checkResults = try await skip("app", "check", "--json", "-d", tempDir).out.parseJSONArray()
    }

    func testSkipInit() async throws {
        let tempDir = try mktmp()
        let name = "cool-lib"
        let (stdout, _) = try await skip("lib", "init", "--no-build", "--no-test", "-d", tempDir, name, "CoolA") // , "CoolB", "CoolC", "CoolD", "CoolE")
        let out = stdout.split(separator: "\n")
        XCTAssertEqual("Initializing Skip library \(name)", out.first)
        let dir = tempDir + "/" + name + "/"
        for path in ["Package.swift", "Sources/CoolA", "Sources/CoolA", "Tests", "Tests/CoolATests/Skip/skip.yml"] {
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

        // .build/plugins/outputs/skip-zip/SkipZipTests/skipstone/SkipZip/.build/SkipZip/test-results/testDebugUnitTest/TEST-skip.zip.SkipZipTests.xml
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
        // the default SPM location of the current skip CLI for testing
        var skiptool = ".build/artifacts/skip/skip/skip.artifactbundle/macos/skip"

        // when running tests from Xcode, we need to use the tool download folder, which seems to be placed in one of the envrionment property `__XCODE_BUILT_PRODUCTS_DIR_PATHS`, so check those folders and override if skip is found
        for checkFolder in (ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] ?? "").split(separator: ":") {
            let xcodeSkipPath = checkFolder.description + "/skip"
            if FileManager.default.isExecutableFile(atPath: xcodeSkipPath) {
                skiptool = xcodeSkipPath
                break
            }
        }

        let result = try await Process.popen(arguments: [skiptool] + args, loggingHandler: nil)

        // Throw if there was a non zero termination.
        guard result.exitStatus == .terminated(code: 0) else {
            throw ProcessResult.Error.nonZeroExit(result)
        }
        let (out, err) = try (result.utf8Output(), result.utf8stderrOutput())

        return (out: out.trimmingCharacters(in: .whitespacesAndNewlines), err: err.trimmingCharacters(in: .whitespacesAndNewlines))
    }

}

/// A JSON object
typealias JSONObject = [String: Any]

private extension String {
    /// Attempts to parse the given String as a JSON object
    func parseJSONObject() throws -> JSONObject {
        let json = try JSONSerialization.jsonObject(with: Data(utf8), options: [])
        if let obj = json as? JSONObject {
            return obj
        } else {
            struct CannotParseJSONIntoObject : LocalizedError { var errorDescription: String? }
            throw CannotParseJSONIntoObject(errorDescription: "JSON object was of wrong type: \(type(of: json))")
        }
    }

    /// Attempts to parse the given String as a JSON object
    func parseJSONArray() throws -> [Any] {
        let json = try JSONSerialization.jsonObject(with: Data(utf8), options: [])
        if let arr = json as? [Any] {
            return arr
        } else {
            struct CannotParseJSONIntoArray : LocalizedError { var errorDescription: String? }
            throw CannotParseJSONIntoArray(errorDescription: "JSON object was of wrong type: \(type(of: json))")
        }
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
func XCTAssertEqualAsync<T>(_ expression1: T, _ expression2: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) where T : Equatable {
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

// .build/plugins/outputs/skip-zip/SkipZipTests/skipstone/SkipZip/.build/SkipZip/test-results/testDebugUnitTest/TEST-skip.zip.SkipZipTests.xml
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
<testcase classname="SkipZipTests.XCSkipTest" name="testSkipModule" time="7.729628">
</testcase>
</testsuite>
</testsuites>
"""
