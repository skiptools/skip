import XCTest
import SkipBuild
import SkipSyntax
import struct JSON.JSON
import TSCBasic

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

    public func testSnippets() async throws {
        func snippet(swift: String, kotlin: String?, messages: [String]? = nil) async throws {
            let srcFile = try tmpFile(named: "Source.swift", contents: swift)
            let (out, err, json) = try await tool("snippet", "-jM", srcFile.path)
            struct SnippetResult : Decodable {
                let kotlin: String?
                let messages: [Message]?
                let duration: TimeInterval
            }

            let result = try SnippetResult(json: json())
            XCTAssertEqual(kotlin, result.kotlin?.trimmingCharacters(in: .whitespacesAndNewlines))
            XCTAssertEqual(messages, result.messages?.isEmpty == true ? nil : result.messages?.map(\.message))
            XCTAssertNotEqual("", out)
            XCTAssertEqual("", err)
        }

        try await snippet(swift: "// SKIP INSERT: abc", kotlin: "abc")

        try await snippet(swift: "struct SomeStruct { }", kotlin: """
        internal class SomeStruct {
        }
        """)

        try await snippet(swift: "class SomeClass { }", kotlin: """
        internal open class SomeClass {
        }
        """)

        try await snippet(swift: "enum SomeEnum { }", kotlin: """
        internal enum class SomeEnum {
        }
        """)

        try await snippet(swift: "func abc() { }", kotlin: """
        internal fun abc() = Unit
        """)

        try await snippet(swift: "func num() -> Int64 { Int64(1) }", kotlin: """
        internal fun num(): Long = Long(1)
        """)

        try await snippet(swift: """
        class C {
            init(i: Int) {
            }
            convenience init(x: Double) {
                if x < 0.0 {
                    self.init(i: -1)
                } else {
                    self.init(i: Int(x))
                }
                print("double")
            }
        }
        """, kotlin: """
        internal open class C {
            internal constructor(i: Int) {
            }
            internal constructor(x: Double) {
                if (x < 0.0) {
                    this(i = -1)
                } else {
                    this(i = Int(x))
                }
                print("double")
            }
        }
        """, messages: [
            "A Kotlin constructor can only include a single top-level call to another \'this\' or \'super\' constructor\n            self.init(i: -1)\n            ^~~~~~~~~~~~~~~~",
            "A Kotlin constructor can only include a single top-level call to another \'this\' or \'super\' constructor\n            self.init(i: Int(x))\n            ^~~~~~~~~~~~~~~~~~~~"
        ])


        // check maximum snippet size errors
        try await snippet(swift: String(repeating: " ", count: (1024 * 25)), kotlin: "")
//        try await snippet(swift: String(repeating: " ", count: (1024 * 25) + 1), kotlin: nil, messages: [
//            "Snippet too large 26 KB"
//        ])
    }

    /// Creates a temporary file with the given name and optional contents.
    func tmpFile(named fileName: String, contents: String? = nil) throws -> URL {
        let tmpDir = URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tmpFile = URL(fileURLWithPath: fileName, isDirectory: false, relativeTo: tmpDir)
        if let contents = contents {
            try contents.write(to: tmpFile, atomically: true, encoding: .utf8)
        }
        return tmpFile
    }

    /// Demo of reproducing a transpiler crash in-process by taking the arguments from the xcode plug-in log and running them manually
    public func XXXtestSkipRunnerCrash() async throws {
        let _ = try await tool("transpile",
             "--output-folder",
             "~/Library/Developer/Xcode/DerivedData/Skip-XXX/SourcePackages/plugins/skiphub.output/SkipFoundationKt/skip-transpiler/SkipFoundation/src/main/kotlin",
             "--module-root",
             "~/Library/Developer/Xcode/DerivedData/Skip-XXX/SourcePackages/plugins/skiphub.output/SkipFoundationKt/skip-transpiler/SkipFoundation",
             "--skip-folder",
             "/opt/src/github/skiptools/skiphub/Sources/SkipFoundationKt/skip",
             "--module",
             "SkipFoundation:/opt/src/github/skiptools/skiphub/Sources/SkipFoundation",
             "--module",
             "SkipLib:/opt/src/github/skiptools/skiphub/Sources/SkipLibKt",
             "--link",
             "SkipLib:../../../SkipLibKt/skip-transpiler/SkipLib",
             "~/skiptools/skiphub/Sources/SkipFoundation/Bundle.swift",
             "~/skiptools/skiphub/Sources/SkipFoundation/UUID.swift"
        )
    }

    /// Runs the tool with the given arguments, returning the entire output string as well as a function to parse it to `JSON`
    func tool(_ args: String...) async throws -> (out: String, err: String, json: () throws -> JSON) {
        let out = BufferedOutputByteStream()
        let err = BufferedOutputByteStream()
        try await SkipRunnerExecutor.run(args, out: out, err: err)
        return (out.bytes.description.trimmingCharacters(in: .whitespacesAndNewlines), err.bytes.description.trimmingCharacters(in: .whitespacesAndNewlines), { try JSON.parse(out.bytes.description.utf8Data) })
    }

}

/// Cover for `XCTAssertEqual` that permit async values
public func XCTAssertEqualX<T>(_ expression1: T, _ expression2: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}

