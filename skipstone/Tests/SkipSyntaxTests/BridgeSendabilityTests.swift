// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import SkipSyntax
import XCTest

final class BridgeSendabilityTests: XCTestCase {
    func testSendableBuiltinResults() async throws {
        for result in ["Int", "String?", "[Int]", "[String: [Int?]]", "Set<String>", "(Int, String)"] {
            for throwsKeyword in ["", "throws"] {
                let bridge = try await generateBridge(swift: """
                #if !SKIP_BRIDGE
                public func fetch() async \(throwsKeyword) -> \(result) { fatalError() }
                #endif
                """, native: false)
                assertReturnIsolation(bridge, unsafe: false)
            }
        }
    }

    func testNativeSendableProtocolResults() async throws {
        for result in ["Sample.Component", "[Sample.Component]", "[Sample.Component]?", "[String: [Sample.Component?]]"] {
            for throwsKeyword in ["", "throws"] {
                let bridge = try await generateBridge(swift: """
                public enum Sample {
                    public struct Component: Sendable {
                        public let value: Int
                    }
                }
                public protocol API {
                    func fetch() async \(throwsKeyword) -> \(result)
                }
                """, native: true)
                assertReturnIsolation(bridge, unsafe: false)
            }
        }
    }

    func testNativeSendableExtensionResult() async throws {
        let bridge = try await generateBridge(swift: """
        public struct Component { public let value: Int }
        extension Component: Sendable {}
        public protocol API { func fetch() async throws -> [Component] }
        """, native: true)
        assertReturnIsolation(bridge, unsafe: false)
    }

    func testNonSendableResultsKeepUnsafeIsolation() async throws {
        for native in [false, true] {
            for result in ["Component", "Component?", "[Component]", "[String: Component]"] {
                for throwsKeyword in ["", "throws"] {
                    let declarations = """
                    public final class Component { public var value: Int = 0 }
                    public protocol API { func fetch() async \(throwsKeyword) -> \(result) }
                    """
                    let source = native ? declarations : "#if !SKIP_BRIDGE\n\(declarations)\n#endif"
                    let bridge = try await generateBridge(swift: source, native: native)
                    assertReturnIsolation(bridge, unsafe: true)
                }
            }
        }
    }

    func testUnconstrainedGenericResultKeepsUnsafeIsolation() async throws {
        let bridge = try await generateBridge(swift: """
        #if !SKIP_BRIDGE
        public func fetch<T>() async throws -> T { fatalError() }
        #endif
        """, native: false)
        assertReturnIsolation(bridge, unsafe: true)
    }

    func testConditionalConformanceIsNotAssumed() async throws {
        let bridge = try await generateBridge(swift: """
        public final class Component { public var value: Int = 0 }
        public struct Box<T> {
            public let value: T
            // SKIP @nobridge
            public init(_ value: T) { self.value = value }
        }
        extension Box: Sendable where T: Sendable {}
        public protocol API { func fetch() async throws -> Box<Component> }
        """, native: true)
        assertReturnIsolation(bridge, unsafe: true)
    }

    func testNativeTypealiasResult() async throws {
        let bridge = try await generateBridge(swift: """
        public struct Component: Sendable { public let value: Int }
        public typealias Components = [Component]
        public protocol API { func fetch() async throws -> Components }
        """, native: true)
        assertReturnIsolation(bridge, unsafe: false)
    }

    func testNativeUncheckedSendableResult() async throws {
        let bridge = try await generateBridge(swift: """
        public final class Component: @unchecked Sendable { public let value: Int = 0 }
        public protocol API { func fetch() async throws -> Component }
        """, native: true)
        assertReturnIsolation(bridge, unsafe: false)
    }

    func testUserDefinedSendableProtocolIsNotTheMarkerProtocol() async throws {
        let bridge = try await generateBridge(swift: """
        public protocol Sendable {}
        public final class Component: Sendable { public var value: Int = 0 }
        public protocol API { func fetch() async throws -> Component }
        """, native: true)
        assertReturnIsolation(bridge, unsafe: true)
    }

    func testTranspiledConformanceIsNotAssumed() async throws {
        let bridge = try await generateBridge(swift: """
        #if !SKIP_BRIDGE
        public struct Component: Sendable { public let value: Int }
        public protocol API { func fetch() async throws -> Component }
        #endif
        """, native: false)
        assertReturnIsolation(bridge, unsafe: true)
    }

    /// The index just past the `}` closing the first `{` at or after `index`.
    private static func closingBraceIndex(after index: String.Index, in text: String) -> String.Index {
        var depth = 0
        var i = index
        while i < text.endIndex {
            if text[i] == "{" {
                depth += 1
            } else if text[i] == "}" {
                depth -= 1
                if depth == 0 {
                    return text.index(after: i)
                }
            }
            i = text.index(after: i)
        }
        return text.endIndex
    }

    func testGeneratedContinuationCompilesWithoutWarnings() async throws {
        #if compiler(<6.0)
        throw XCTSkip("This regression check requires Swift 6 language mode.")
        #else
        // Compile the generated continuation and callback verbatim. JNI dispatch is replaced
        // with a use of the callback so this test does not require an Android SDK or JVM.
        for sendable in [false, true] {
            for optional in [false, true] {
                for throwsKeyword in ["", "throws"] {
                    let component = sendable
                        ? "public struct Component: Sendable { public let value: Int }"
                        : "public final class Component { public var value: Int = 0 }"
                    let result = "[Component]" + (optional ? "?" : "")
                    let declarations = """
                    \(component)
                    public protocol API { func fetch() async \(throwsKeyword) -> \(result) }
                    """
                    let bridge = try await generateBridge(swift: declarations, native: true)
                    let start = try XCTUnwrap(bridge.range(of: "public func fetch()"))
                    let function = String(bridge[start.lowerBound..<Self.closingBraceIndex(after: start.lowerBound, in: bridge)])
                    let dispatch = try XCTUnwrap(function.range(of: "jniContext {"))
                    let dispatchEnd = Self.closingBraceIndex(after: dispatch.lowerBound, in: function)
                    let continuation = function.replacingCharacters(in: dispatch.upperBound..<function.index(before: dispatchEnd), with: " _ = f_return_callback ")
                    let source = """
                    \(component)
                    typealias JavaObjectPointer = OpaquePointer
                    enum BridgeTestError: Error { case failure }
                    enum JThrowable {
                        static func toError(_ pointer: JavaObjectPointer, options: [Int]) -> (any Error)? {
                            BridgeTestError.failure
                        }
                    }
                    final class BridgedJob: Sendable {
                        func attach(_ job: JavaObjectPointer) {}
                        func cancel() {}
                        func error(_ throwable: JavaObjectPointer, options: [Int]) -> any Error { BridgeTestError.failure }
                    }
                    func jniContext<T>(_ block: () throws -> T) rethrows -> T { try block() }
                    \(continuation)
                    """
                    let file = try tmpFile(named: "Continuation.swift", contents: source)
                    let process = Process()
                    let output = Pipe()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = ["swiftc", "-typecheck", "-swift-version", "6", "-warnings-as-errors", file.path]
                    process.standardOutput = output
                    process.standardError = output
                    try process.run()
                    let diagnostics = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
                }
            }
        }
        #endif
    }

    private func assertReturnIsolation(_ bridge: String, unsafe: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(bridge.contains("let f_return_value = f_return"), bridge, file: file, line: line)
        XCTAssertEqual(bridge.contains("nonisolated(unsafe) let f_return_value"), unsafe, bridge, file: file, line: line)
        XCTAssertTrue(bridge.contains("f_continuation.resume(returning: f_return_value)"), bridge, file: file, line: line)
    }

    private func generateBridge(swift: String, native: Bool) async throws -> String {
        let file = try tmpFile(named: native ? "Bridge.swift" : "Source.swift", contents: swift)
        let path = Source.FilePath(path: file.path)
        let transpiler = Transpiler(transpileFiles: native ? [] : [path], bridgeFiles: native ? [path] : [], autoBridge: .public, codebaseInfo: CodebaseInfo(), transformers: builtinKotlinTransformers() + [KotlinBridgeTransformer()])
        var bridge = ""
        try await transpiler.transpile { transpilation in
            XCTAssertTrue(transpilation.messages.isEmpty, transpilation.messages.map(\.formattedMessage).joined(separator: "\n"))
            if transpilation.outputType == .bridgeToSwift || transpilation.outputType == .bridgeFromSwift {
                bridge += transpilation.output.content
            }
        }
        return bridge
    }
}
