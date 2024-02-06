// Copyright 2023 Skip
import XCTest
import SkipDrive

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
class SkipCommandTests : XCTestCase {
    func testSkipVersion() async throws {
        var versionOut = try await skip("version")
        if versionOut.hasSuffix(" (debug)") {
            versionOut.removeLast(" (debug)".count)
        }

        XCTAssertEqual("Skip version \(SkipDrive.skipVersion)", versionOut)
    }

    func testSkipVersionJSON() async throws {
        try await XCTAssertEqualAsync(SkipDrive.skipVersion, skip("version", "--json").parseJSONObject()["version"] as? String)
    }

    func testSkipWelcome() async throws {
        try await skip("welcome")
    }

    func testSkipWelcomeJSON() async throws {
        let welcome = try await skip("welcome", "--json", "--json-array").parseJSONArray()
        XCTAssertNotEqual(0, welcome.count, "Welcome message should not be empty")
    }

    func testSkipDoctor() async throws {
        // run `skip doctor` with JSON array output and make sure we can parse the result
        let doctor = try await skip("doctor", "-jA").parseJSONMessages()
        XCTAssertGreaterThan(doctor.count, 5, "doctor output should have contained some lines")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("macOS version") }), "missing macOS version")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Swift version") }), "missing Swift version")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Xcode version") }), "missing Xcode version")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Xcode tools") }), "missing Xcode tools")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Homebrew version") }), "missing Homebrew version")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Gradle version") }), "missing Gradle version")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Java version") }), "missing Java version")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Android Debug Bridge version") }), "missing Android Debug Bridge version")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Android SDK licenses:") }), "missing Android SDK licenses")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Check Skip Updates") }), "missing Check Skip Updates")
    }

    func testSkipDevices() async throws {
        let devices = try await skip("devices", "-jA").parseJSONArray()
        XCTAssertGreaterThanOrEqual(devices.count, 0)
    }

    func testSkipCheckup() async throws {
        if ProcessInfo.processInfo.environment["CI"] != nil {
            throw XCTSkip("skipping checkup test on CI due to unknown failure")
        }
        let checkup = try await skip("checkup", "-jA").parseJSONMessages()
        XCTAssertGreaterThan(checkup.count, 5, "checkup output should have contained some lines")
    }

    func testSkipCreate() async throws {
        if ProcessInfo.processInfo.environment["CI"] != nil {
            throw XCTSkip("skipping checkup test on CI due to unknown failure")
        }
        let tempDir = try mktmp()
        let projectName = "hello-skip"
        let appName = "HelloSkip"
        let out = try await skip("init", "-jA", "--show-tree", "-d", tempDir, "--appid", "com.company.HelloSkip", projectName, appName)
        let msgs = try out.parseJSONMessages()

        XCTAssertEqual("Initializing Skip application \(projectName)", msgs.first)
        let dir = tempDir + "/" + projectName + "/"

        let xcodeproj = "Darwin/" + appName + ".xcodeproj"
        let xcconfig = "Darwin/" + appName + ".xcconfig"
        for path in ["Package.swift", xcodeproj, xcconfig, "Sources", "Tests"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir + path), "missing file at: \(path)")
        }

        XCTAssertEqual(msgs.dropLast(1).last ?? "", """
        .
        ├─ Android
        │  ├─ app
        │  │  ├─ build.gradle.kts
        │  │  ├─ proguard-rules.pro
        │  │  └─ src
        │  │     └─ main
        │  │        ├─ AndroidManifest.xml
        │  │        ├─ kotlin
        │  │        │  └─ hello
        │  │        │     └─ skip
        │  │        │        └─ Main.kt
        │  │        └─ res
        │  │           ├─ mipmap-hdpi
        │  │           │  └─ ic_launcher.png
        │  │           ├─ mipmap-mdpi
        │  │           │  └─ ic_launcher.png
        │  │           ├─ mipmap-xhdpi
        │  │           │  └─ ic_launcher.png
        │  │           ├─ mipmap-xxhdpi
        │  │           │  └─ ic_launcher.png
        │  │           └─ mipmap-xxxhdpi
        │  │              └─ ic_launcher.png
        │  ├─ gradle
        │  │  └─ wrapper
        │  │     └─ gradle-wrapper.properties
        │  ├─ gradle.properties
        │  └─ settings.gradle.kts
        ├─ Darwin
        │  ├─ Assets.xcassets
        │  │  ├─ AccentColor.colorset
        │  │  │  └─ Contents.json
        │  │  ├─ AppIcon.appiconset
        │  │  │  ├─ AppIcon-20@2x.png
        │  │  │  ├─ AppIcon-20@2x~ipad.png
        │  │  │  ├─ AppIcon-20@3x.png
        │  │  │  ├─ AppIcon-20~ipad.png
        │  │  │  ├─ AppIcon-29.png
        │  │  │  ├─ AppIcon-29@2x.png
        │  │  │  ├─ AppIcon-29@2x~ipad.png
        │  │  │  ├─ AppIcon-29@3x.png
        │  │  │  ├─ AppIcon-29~ipad.png
        │  │  │  ├─ AppIcon-40@2x.png
        │  │  │  ├─ AppIcon-40@2x~ipad.png
        │  │  │  ├─ AppIcon-40@3x.png
        │  │  │  ├─ AppIcon-40~ipad.png
        │  │  │  ├─ AppIcon-83.5@2x~ipad.png
        │  │  │  ├─ AppIcon@2x.png
        │  │  │  ├─ AppIcon@2x~ipad.png
        │  │  │  ├─ AppIcon@3x.png
        │  │  │  ├─ AppIcon~ios-marketing.png
        │  │  │  ├─ AppIcon~ipad.png
        │  │  │  └─ Contents.json
        │  │  └─ Contents.json
        │  ├─ Entitlements.plist
        │  ├─ HelloSkip.xcconfig
        │  ├─ HelloSkip.xcodeproj
        │  │  └─ project.pbxproj
        │  └─ Sources
        │     └─ HelloSkipAppMain.swift
        ├─ Package.resolved
        ├─ Package.swift
        ├─ README.md
        ├─ Skip.env
        ├─ Sources
        │  └─ HelloSkip
        │     ├─ ContentView.swift
        │     ├─ HelloSkip.swift
        │     ├─ HelloSkipApp.swift
        │     ├─ Resources
        │     │  └─ Localizable.xcstrings
        │     └─ Skip
        │        └─ skip.yml
        └─ Tests
           └─ HelloSkipTests
              ├─ HelloSkipTests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)
    }

    func XXXtestSkipInit() async throws {
        let tempDir = try mktmp()
        let name = "cool-lib"
        let out = try await skip("lib", "init", "-jA", "--show-tree", "-d", tempDir, name, "CoolA", "CoolB", "CoolC", "CoolD", "CoolE")
        let msgs = try out.parseJSONMessages()

        XCTAssertEqual("Initializing Skip library \(name)", msgs.first)

        let dir = tempDir + "/" + name + "/"
        for path in ["Package.swift", "Sources/CoolA", "Sources/CoolA", "Sources/CoolE", "Tests", "Tests/CoolATests/Skip/skip.yml"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir + path), "missing file at: \(path)")
        }

        let project = try await loadProjectPackage(dir)
        XCTAssertEqual(name, project.name)

        XCTAssertEqual(msgs.dropLast(1).last ?? "", """
        .
        ├─ Package.resolved
        ├─ Package.swift
        ├─ README.md
        ├─ Sources
        │  ├─ CoolA
        │  │  ├─ CoolA.swift
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  ├─ CoolB
        │  │  ├─ CoolB.swift
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  ├─ CoolC
        │  │  ├─ CoolC.swift
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  ├─ CoolD
        │  │  ├─ CoolD.swift
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  └─ CoolE
        │     ├─ CoolE.swift
        │     ├─ Resources
        │     │  └─ Localizable.xcstrings
        │     └─ Skip
        │        └─ skip.yml
        └─ Tests
           ├─ CoolATests
           │  ├─ CoolATests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           ├─ CoolBTests
           │  ├─ CoolBTests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           ├─ CoolCTests
           │  ├─ CoolCTests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           ├─ CoolDTests
           │  ├─ CoolDTests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           └─ CoolETests
              ├─ CoolETests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)

    }

    func NOtestSkipTestReport() async throws {
        let xunit = try mktmpFile(contents: Data(xunitResults.utf8))
        let tempDir = try mktmp()
        let junit = tempDir + "/" + "testDebugUnitTest"
        try FileManager.default.createDirectory(atPath: junit, withIntermediateDirectories: true)
        try Data(junitResults.utf8).write(to: URL(fileURLWithPath: junit + "/TEST-skip.zip.SkipZipTests.xml"))

        // .build/plugins/outputs/skip-zip/SkipZipTests/skipstone/SkipZip/.build/SkipZip/test-results/testDebugUnitTest/TEST-skip.zip.SkipZipTests.xml
        let report = try await skip("test", "--configuration", "debug", "--test", "--max-column-length", "15", "--xunit", xunit, "--junit", junit)
        XCTAssertEqual(report, """
        | Test         | Case            | Swift | Kotlin |
        | ------------ | --------------- | ----- | ------ |
        | SkipZipTests | testArchive     | PASS  | SKIP   |
        | SkipZipTests | testDeflateInfl | PASS  | PASS   |
        | SkipZipTests | testMissingTest | PASS  | ????   |
        |              |                 | 100%  | 33%    |
        """)
    }

    /// Runs the tool with the given arguments, returning the entire output string as well as a function to parse it to `JSON`
    @discardableResult func skip(checkError: Bool = true, printOutput: Bool = false, _ args: String...) async throws -> String {
        // turn "-[SkipCommandTests testSomeTest]" into "testSomeTest"
        let testName = testRun?.test.name.split(separator: " ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) ?? "TEST"

        // the default SPM location of the current skip CLI for testing
        var skiptools = [
            ".build/artifacts/skip/skip/skip.artifactbundle/macos/skip",
            ".build/plugins/tools/debug/skip",
        ]

        // when running tests from Xcode, we need to use the tool download folder, which seems to be placed in one of the environment property `__XCODE_BUILT_PRODUCTS_DIR_PATHS`, so check those folders and override if skip is found
        for checkFolder in (ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] ?? "").split(separator: ":") {
            let xcodeSkipPath = checkFolder.description + "/skip"
            if FileManager.default.isExecutableFile(atPath: xcodeSkipPath) {
                skiptools.append(xcodeSkipPath)
            }
        }

        struct SkipLaunchError : LocalizedError { var errorDescription: String? }

        guard let skiptool = skiptools.last(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw SkipLaunchError(errorDescription: "Could not locate the skip executable in any of the paths: \(skiptools.joined(separator: " "))")
        }

        let cmd = [skiptool] + args
        if printOutput {
            print("running: \(cmd.joined(separator: " "))")
        }

        //let result = try await Process.popen(arguments: cmd, loggingHandler: nil)

        var outputLines: [String] = []
        var result: ProcessResult? = nil
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb" // override TERM to prevent skip from using ANSI colors or progress animations
        for try await outputLine in Process.streamLines(command: cmd, environment: env, includeStdErr: true, onExit: { result = $0 }) {
            if printOutput {
                print("\(testName)> \(outputLine)")
            }
            outputLines.append(outputLine)
        }

        guard let result = result else {
            throw SkipLaunchError(errorDescription: "command did not exit: \(cmd)")
        }
        // Throw if there was a non zero termination.
        guard result.exitStatus == .terminated(code: 0) else {
            throw ProcessResult.Error.nonZeroExit(result)
        }

        return outputLines.joined(separator: "\n")
    }

}

/// A JSON object
typealias JSONObject = [String: Any]

private extension String {
    /// Attempts to parse the given String as a JSON object
    func parseJSONObject(file: StaticString = #file, line: UInt = #line) throws -> JSONObject {
        do {
            let json = try JSONSerialization.jsonObject(with: Data(utf8), options: [])
            if let obj = json as? JSONObject {
                return obj
            } else {
                struct CannotParseJSONIntoObject : LocalizedError { var errorDescription: String? }
                throw CannotParseJSONIntoObject(errorDescription: "JSON object was of wrong type: \(type(of: json))")
            }
        } catch {
            XCTFail("Error parsing JSON Object from: \(self)", file: file, line: line)
            throw error
        }
    }

    /// Attempts to parse the given String as a JSON object
    func parseJSONArray(file: StaticString = #file, line: UInt = #line) throws -> [Any] {
        var str = self.trimmingCharacters(in: .whitespacesAndNewlines)

        // workround for test failures: sometimes stderr has a line line: "2023-10-27 17:04:18.587523-0400 skip[91666:2692850] [client] No error handler for XPC error: Connection invalid"; this seems to be a side effect of running `skip doctor` from within Xcode
        if str.hasSuffix("No error handler for XPC error: Connection invalid") {
            str = str.split(separator: "\n").dropLast().joined(separator: "\n")
        }

        do {
            let json = try JSONSerialization.jsonObject(with: Data(utf8), options: [])
            if let arr = json as? [Any] {
                return arr
            } else {
                struct CannotParseJSONIntoArray : LocalizedError { var errorDescription: String? }
                throw CannotParseJSONIntoArray(errorDescription: "JSON object was of wrong type: \(type(of: json))")
            }
        } catch {
            XCTFail("Error parsing JSON Array from: \(self)", file: file, line: line)
            throw error
        }
    }

    func parseJSONMessages(file: StaticString = #file, line: UInt = #line) throws -> [String] {
        try parseJSONArray(file: file, line: line).compactMap({ ($0 as? JSONObject)?["msg"] as? String })
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
