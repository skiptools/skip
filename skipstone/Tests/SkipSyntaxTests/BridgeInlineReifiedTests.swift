// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import SkipSyntax
import XCTest

// Regression for skiptools/skip-firebase#81 / #91: a generic `@inline(__always)` function is
// emitted as a Kotlin `inline fun <reified T>`, which has NO JVM-callable method. The bridge
// generator must therefore NOT emit a JNI getMethodID lookup for it — that force-unwrap
// (`getMethodID("decoded", ...)!`) returns nil and traps at class load for native-Swift Android
// callers. Native-Swift callers use the `@inline(__always)` Swift body directly (inlined).
// Reproduces on an `open` class that has a subclass (the #91 shape, where the reified method is
// lifted to an extension function).
final class BridgeInlineReifiedTests: XCTestCase {
    private var transformers: [KotlinTransformer] {
        return builtinKotlinTransformers() + [KotlinBridgeTransformer()]
    }

    func testReifiedInlineMethodIsNotBridged() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        open class SnapC {
            @inline(__always) public func decoded<T: Decodable>() throws -> T { fatalError() }
        }
        public final class QuerySnapC: SnapC {
        }
        #endif
        """, kotlin: """
        open class SnapC: skip.lib.SwiftProjecting {

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }

        inline fun <reified T> SnapC.decoded(): T where T: Decodable {
            fatalError()
        }
        class QuerySnapC: SnapC() {

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object: SnapC.CompanionClass() {
            }
        }
        """, swiftBridgeSupport: """
        open class SnapC: BridgedFromKotlin {
            nonisolated private static let Java_class = try! JClass(name: "SnapC")
            nonisolated public let Java_peer: JObject
            nonisolated public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            nonisolated public init(Java_peer: JObject) {
                self.Java_peer = Java_peer
            }
            public init() {
                Java_peer = jniContext {
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: [], args: [])
                    return JObject(ptr)
                }
            }
            nonisolated private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "()V")!
            nonisolated public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            nonisolated public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        @_cdecl("Java_SnapC_Swift_1projectionImpl")
        public func SnapC_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = SnapC.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        public final class QuerySnapC: SnapC, BridgedFinalClass {
            nonisolated private static let Java_class = try! JClass(name: "QuerySnapC")
            nonisolated public required init(Java_ptr: JavaObjectPointer) {
                super.init(Java_ptr: Java_ptr)
            }
            nonisolated public override init(Java_peer: JObject) {
                super.init(Java_peer: Java_peer)
            }
            public init() {
                let Java_peer = jniContext {
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: [], args: [])
                    return JObject(ptr)
                }
                super.init(Java_peer: Java_peer)
            }
            nonisolated private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "()V")!
        }
        @_cdecl("Java_QuerySnapC_Swift_1projectionImpl")
        public func QuerySnapC_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = QuerySnapC.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    // Same JVM-uncallable inline-reified shape, but hand-authored via `// SKIP DECLARE:` (no
    // `@inline(__always)` attribute). This is skip-firebase's FirestoreDecoder.decode(from:) shape,
    // reached from DocumentSnapshot.decoded() — so #91 is only fully closed once this path is
    // excluded from bridging too. Assert no `getMethodID(name: "decode"` lookup is generated.
    func testSkipDeclareReifiedMethodIsNotBridged() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public class Decoder {
            // SKIP DECLARE: public inline fun <reified T : Decodable> decode(from: Dictionary<String, Any>): T
            public func decode<T: Decodable>(from data: [String: Any]) throws -> T { fatalError() }
        }
        #endif
        """, kotlin: """
        open class Decoder: skip.lib.SwiftProjecting {
            public inline fun <reified T : Decodable> decode(from: Dictionary<String, Any>): T {
                val data = from
                fatalError()
            }

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        public class Decoder: BridgedFromKotlin {
            nonisolated private static let Java_class = try! JClass(name: "Decoder")
            nonisolated public let Java_peer: JObject
            nonisolated public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            nonisolated public init(Java_peer: JObject) {
                self.Java_peer = Java_peer
            }
            public init() {
                Java_peer = jniContext {
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: [], args: [])
                    return JObject(ptr)
                }
            }
            nonisolated private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "()V")!
            nonisolated public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            nonisolated public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        @_cdecl("Java_Decoder_Swift_1projectionImpl")
        public func Decoder_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = Decoder.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }
}
