import XCTest
import SkipBuild
import SkipRunner
import struct JSON.JSON
import TSCBasic

#if !SKIP
public class SkipRunnerTests : XCTestCase {
    public func testSkipRunnerCommands() async throws {
        let v = skipVersion

        #if DEBUG
        try await XCTAssertEqualX("skip version \(v) (debug)", tool("version").out)
        try await XCTAssertEqualX(v, tool("version", "-jM").json()["version"]?.string)
        try await XCTAssertEqualX(v, tool("version", "-JM").json()["version"]?.string)
        #else
        try await XCTAssertEqualX("skip version \(v)", tool("version").out)
        try await XCTAssertEqualX(v, tool("version", "-jM").json()["version"]?.string)
        try await XCTAssertEqualX(v, tool("version", "-JM").json()["version"]?.string)
        #endif
    }

    /// Runs the tool with the given arguments, returning the entire output string as well as a function to parse it to `JSON`
    func tool(_ args: String...) async throws -> (out: String, err: String, json: () throws -> JSON) {
        let out = BufferedOutputByteStream()
        let err = BufferedOutputByteStream()
        try await SkipCommandExecutor.run(args, out: out, err: err)
        return (out.bytes.description.trimmingCharacters(in: .whitespacesAndNewlines), err.bytes.description.trimmingCharacters(in: .whitespacesAndNewlines), { try JSON.parse(out.bytes.description.utf8Data) })
    }

}

/// Cover for `XCTAssertEqual` that permit async values
public func XCTAssertEqualX<T>(_ expression1: T, _ expression2: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}

#endif
