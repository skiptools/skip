import XCTest
import SkipDrive

public class SkipCommandTests : XCTestCase {
    public func testSkipCommands() async throws {
        try await XCTAssertEqualX("Skip version \(skipVersion)", skip("version").out)
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
public func XCTAssertEqualX<T>(_ expression1: T, _ expression2: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}
