import XCTest
import SkipBuild
import SkipRunner
import var SkipSyntax.skipVersion
import struct JSON.JSON
import TSCBasic

#if !SKIP
public class SkipRunnerTests : XCTestCase {
    public func testSkipRunnerCommands() async throws {
        let v = skipVersion

        try await XCTAssertEqualX(v, tool("version", "-jM").json()["version"]?.string)
        try await XCTAssertEqualX(v, tool("version", "-JM").json()["version"]?.string)

        #if DEBUG
        let debug = true
        try await XCTAssertEqualX("skip version \(v) (debug)", tool("version").out)

        func endOfFirstLine(_ output: String, count: Int) throws -> String {
            let firstLine = try XCTUnwrap(output.split(separator: "\n").first)
            return String(firstLine.suffix(count)).trimmingCharacters(in: .whitespaces)
        }

        // test sending plain console messages to stdout; ensure that trace messages are only sent when verbose is enabled
        //XCTAssertEqualX("note: info message", try endOfFirstLine(await tool("info", "-ME").out, count: "note: info message".count))
        //XCTAssertEqualX("trace: trace message", try endOfFirstLine(await tool("info", "-MEv").out, count: "trace: trace message".count)) // verbose variant starts with "remark:"

        #else
        let debug = false
        try await XCTAssertEqualX("skip version \(v)", tool("version").out)
        #endif

        try await XCTAssertEqualX(debug, tool("info", "-JA").json().array?.last?["debug"]?.boolean)
    }

    /// Demo of reproducing a transpiler crash in-process by taking the arguments from the xcode plug-in log and running them manually
    public func XXXtestSkipRunnerCrash() async throws {
        let _ = try await tool("transpile",
             "--output-folder",
             "~/Library/Developer/Xcode/DerivedData/Skip-XXX/SourcePackages/plugins/skip-core.output/SkipFoundationKt/SkipTranspilePlugIn/SkipFoundation/src/main/kotlin",
             "--module-root",
             "~/Library/Developer/Xcode/DerivedData/Skip-XXX/SourcePackages/plugins/skip-core.output/SkipFoundationKt/SkipTranspilePlugIn/SkipFoundation",
             "--skip-folder",
             "/opt/src/github/skiptools/skip-core/Sources/SkipFoundationKt/skip",
             "--module",
             "SkipFoundation:/opt/src/github/skiptools/skip-core/Sources/SkipFoundation",
             "--module",
             "SkipLib:/opt/src/github/skiptools/skip-core/Sources/SkipLibKt",
             "--link",
             "SkipLib:../../../SkipLibKt/SkipTranspilePlugIn/SkipLib",
             "~/skiptools/skip-core/Sources/SkipFoundation/Bundle.swift",
             "~/skiptools/skip-core/Sources/SkipFoundation/UUID.swift"
        )
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
