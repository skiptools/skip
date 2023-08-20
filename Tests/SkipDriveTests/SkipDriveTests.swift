import XCTest
import SkipDrive

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
public class SkipCommandTests : XCTestCase {
    public func testSkipVersion() async throws {
        try await XCTAssertEqualX("Skip version \(skipVersion)", skip("version").out)
    }

    public func testSkipCreate() async throws {
        let tempDir = try mktmp()
        let name = "cool_app"
        let (stdout, _) = try await skip("create", "--no-build", "--no-test", "-d", tempDir, name)
        let out = stdout.split(separator: "\n")
        XCTAssertEqual("Creating project \(name) from template skipapp", out.first)
        let dir = tempDir + "/" + name + "/"
        for path in ["Package.swift", "App.xcodeproj", "App.xcconfig", "Sources", "Tests"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir + path), "missing file at: \(path)")
        }

        let project = try await loadProjectPackage(dir)
        XCTAssertEqual("App", project.name)

        // TODO
        //let config = try await loadProjectConfig(dir + "/App.xcodeproj", scheme: "App")
        //XCTAssertEqual("App", config.first?.buildSettings["PROJECT_NAME"])

        //try await skip("check", "-d", tempDir)
    }

    public func testSkipInit() async throws {
        throw XCTSkip("TODO")

        let tempDir = try mktmp()
        let name = "cool-lib"
        let (stdout, _) = try await skip("init", "--build", "--test", "-d", tempDir, name, "CoolA", "CoolB", "CoolC", "CoolD", "CoolE")
        let out = stdout.split(separator: "\n")
        XCTAssertEqual("Creating library project \(name)", out.first)
        let dir = tempDir + "/" + name + "/"
        for path in ["Package.swift", "Sources/CoolA", "Sources/CoolE", "Sources/CoolEKt", "Tests", "Tests/CoolEKtTests"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir + path), "missing file at: \(path)")
        }

        //try await skip("check", "-d", tempDir)
    }

    public func testSkipDoctor() async throws {
        throw XCTSkip("TODO")
        try await skip("doctor")
    }

    /// Runs the tool with the given arguments, returning the entire output string as well as a function to parse it to `JSON`
    @discardableResult func skip(checkError: Bool = true, _ args: String...) async throws -> (out: String, err: String) {
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
    }

    /// Create a temporary directory
    func mktmp(baseName: String = "SkipDriveTests") throws -> String {
        let tempDir = [NSTemporaryDirectory(), baseName, UUID().uuidString].joined(separator: "/")
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
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
public func XCTAssertEqualX<T>(_ expression1: T, _ expression2: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}
