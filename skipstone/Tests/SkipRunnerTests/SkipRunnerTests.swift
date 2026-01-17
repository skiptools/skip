// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
import SkipBuild
import SkipSyntax
import struct JSON.JSON
import TSCBasic

public class SkipRunnerTests : XCTestCase {
    public func testSkipRunnerCommands() async throws {
        let v = SkipBuild.skipVersion

        XCTAssertEqual(SkipBuild.skipVersion, SkipSyntax.skipVersion) // they point to the same field, so it would be surprising if they differed

        try await XCTAssertEqualAsync(v, skipstone(["version", "-jM"]).json()["version"]?.string)
        try await XCTAssertEqualAsync(v, skipstone(["version", "-JM"]).json()["version"]?.string)

        #if DEBUG
        let debug = true
        try await XCTAssertEqualAsync("Skip version \(v) (debug)", skipstone(["version"]).out)

        func endOfFirstLine(_ output: String, count: Int) throws -> String {
            let firstLine = try XCTUnwrap(output.split(separator: "\n").first)
            return String(firstLine.suffix(count)).trimmingCharacters(in: .whitespaces)
        }

        // test sending plain console messages to stdout; ensure that trace messages are only sent when verbose is enabled
        //XCTAssertEqualAsync("note: info message", try endOfFirstLine(await skipstone("info", "-ME").out, count: "note: info message".count))
        //XCTAssertEqualAsync("trace: trace message", try endOfFirstLine(await skipstone("info", "-MEv").out, count: "trace: trace message".count)) // verbose variant starts with "remark:"

        #else
        let debug = false
        try await XCTAssertEqualAsync("Skip version \(v)", skipstone("version").out)
        #endif

        try await XCTAssertEqualAsync(debug, skipstone(["info", "-JA"]).json().array?.last?["debug"]?.boolean)
    }

    public func testSnippets() async throws {
        func snippet(swift: String, kotlin: String?, messages: [String]? = nil) async throws {
            let srcFile = try tmpFile(named: "Source.swift", contents: swift)
            let (out, err, json) = try await skipstone(["snippet", "-jM", srcFile.path])
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
            ;
        }
        """)

        try await snippet(swift: "func abc() { }", kotlin: """
        internal fun abc() = Unit
        """)

        try await snippet(swift: "func num() -> Int64 { Int64(1) }", kotlin: """
        internal fun num(): Long = 1L
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
            "A Kotlin constructor can only include a single top-level call to another \'this\' or \'super\' constructor", "A Kotlin constructor can only include a single top-level call to another \'this\' or \'super\' constructor"
        ])


        // check maximum snippet size errors
        //try await snippet(swift: String(repeating: " ", count: 1024), kotlin: "")
        try await snippet(swift: String(repeating: " ", count: 1024 + 1), kotlin: nil, messages: [
            "Snippet too large 1 KB"
        ])
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

}

/// Cover for `XCTAssertEqual` that permit async values
public func XCTAssertEqualAsync<T>(_ expression1: T, _ expression2: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}

