import XCTest
import SkipDrive

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
public class SkipCommandTests : XCTestCase {
    public func testSkipCommands() async throws {
        try await XCTAssertEqualX("Skip version \(skipVersion)", skip("version").out)
    }

    public func testSkipCreate() async throws {
        let tempDir = NSTemporaryDirectory() + "skip_app/\(UUID().uuidString)/"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let (stdout, strerr) = try await skip("create", "--test", "-d", tempDir, "cool_app")
        XCTAssertEqual("", strerr, "command stderr was not empty")

        let out = stdout.split(separator: "\n")
        XCTAssertEqual("Creating project cool_app from template skipapp", out.first)
    }

    /// Runs the tool with the given arguments, returning the entire output string as well as a function to parse it to `JSON`
    func skip(_ args: String...) async throws -> (out: String, err: String) {
        let out = BufferedOutputByteStream()
        let err = BufferedOutputByteStream()
        try await SkipDriver.run(args, out: out, err: err)
        return (out.bytes.description.trimmingCharacters(in: .whitespacesAndNewlines), err.bytes.description.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Cover for `XCTAssertEqual` that permit async autoclosures.
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
public func XCTAssertEqualX<T>(_ expression1: T, _ expression2: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}
