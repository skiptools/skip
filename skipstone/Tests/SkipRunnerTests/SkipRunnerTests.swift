import XCTest
import SkipBuild
import SkipRunner
import JSON

#if !SKIP
public class SkipRunnerTests : XCTestCase {
    public func testSkipRunnerCommands() async throws {
        let v = skipVersion

        try await XCTAssertEqualX("skip version \(v)", tool("version").out)
        try await XCTAssertEqualX(["version": .string(v)], tool("version", "-j").json())

        try await XCTAssertEqualX("{\"version\":\"\(v)\"}", tool("version", "-j").out)
        try await XCTAssertEqualX(tool("version", "-J").out, """
            {
              "version" : "\(v)"
            }
            """)
    }

    /// Runs the tool with the given arguments, returning the entire output string as well as a function to parse it to `JSON`
    func tool(_ args: String...) async throws -> (out: String, err: String, json: () throws -> JSON) {
        let out = BufferedOutputByteStream()
        let err = BufferedOutputByteStream()
        try await Runner.run(args, out: out, err: err)
        return (out.bytes.description.trimmingCharacters(in: .whitespacesAndNewlines), err.bytes.description.trimmingCharacters(in: .whitespacesAndNewlines), { try JSON.parse(out.bytes.description.utf8Data) })
    }

}

/// Cover for `XCTAssertEqual` that permit async values
public func XCTAssertEqualX<T>(_ expression1: T, _ expression2: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}

#endif
