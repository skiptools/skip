import SkipSyntax
import XCTest

final class BridgeToKotlinTests: XCTestCase {
    private var transformers: [KotlinTransformer] {
        return builtinKotlinTransformers() + [KotlinBridgeTransformer()]
    }

    func testLetSupportedLiteral() async throws {
        try await check(swiftBridge: """
        public let b = true
        """, kotlin: """
        val b = true
        """, swiftBridgeSupport: """
        """, transformers: transformers)

        try await check(swiftBridge: """
        public let i = 1
        """, kotlin: """
        val i = 1
        """, swiftBridgeSupport: """
        """, transformers: transformers)

        try await check(swiftBridge: """
        public let i: Int32 = 1
        """, kotlin: """
        val i: Int = 1
        """, swiftBridgeSupport: """
        """, transformers: transformers)

        try await check(swiftBridge: """
        public let d = 5.0
        """, kotlin: """
        val d = 5.0
        """, swiftBridgeSupport: """
        """, transformers: transformers)

        try await check(swiftBridge: """
        public let d: Double = 5
        """, kotlin: """
        val d: Double = 5.0
        """, swiftBridgeSupport: """
        """, transformers: transformers)

        try await check(swiftBridge: """
        public let d: Double? = nil
        """, kotlin: """
        val d: Double? = null
        """, swiftBridgeSupport: """
        """, transformers: transformers)

        try await check(swiftBridge: """
        public let d: Double? = 5
        """, kotlin: """
        val d: Double? = 5.0
        """, swiftBridgeSupport: """
        """, transformers: transformers)

        try await check(swiftBridge: """
        public let s = "Hello"
        """, kotlin: """
        val s = "Hello"
        """, swiftBridgeSupport: """
        """, transformers: transformers)
    }

    func testLetUnsupportedLiteral() async throws {
        try await check(swiftBridge: """
        public let f: Float = 1
        """, kotlin: """
        val f: Float
            get() = Swift_f()
        private external fun Swift_f(): Float
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f")
        func BridgeKt_Swift_f(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Float {
            return f
        }
        """, transformers: transformers)

        try await check(swiftBridge: """
        public let i: Int64 = 1
        """, kotlin: """
        val i: Long
            get() = Swift_i()
        private external fun Swift_i(): Long
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int64 {
            return i
        }
        """, transformers: transformers)

        try await check(swiftBridge: """
        public let s = "ab\\(1 + 1)c"
        """, kotlin: """
        val s: String
            get() = Swift_s()
        private external fun Swift_s(): String
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1s")
        func BridgeKt_Swift_s(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaString {
            return s.toJavaObject(options: [])!
        }
        """, transformers: transformers)
    }

    func testLetNonLiteral() async throws {
        try await check(swiftBridge: """
        public let i = 1 + 1
        """, kotlin: """
        val i: Int
            get() = Swift_i()
        private external fun Swift_i(): Int
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int32 {
            return Int32(i)
        }
        """, transformers: transformers)

        try await check(swiftBridge: """
        public let i: Int32 = 1 + 1
        """, kotlin: """
        val i: Int
            get() = Swift_i()
        private external fun Swift_i(): Int
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int32 {
            return i
        }
        """, transformers: transformers)

        try await check(swiftBridge: """
        public let s = "ab" + "c"
        """, kotlin: """
        val s: String
            get() = Swift_s()
        private external fun Swift_s(): String
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1s")
        func BridgeKt_Swift_s(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaString {
            return s.toJavaObject(options: [])!
        }
        """, transformers: transformers)
    }

    func testStoredVar() async throws {
        try await check(swiftBridge: """
        public var i = 1
        """, kotlin: """
        var i: Int
            get() = Swift_i()
            set(newValue) {
                Swift_i_set(newValue)
            }
        private external fun Swift_i(): Int
        private external fun Swift_i_set(value: Int)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int32 {
            return Int32(i)
        }
        @_cdecl("Java_BridgeKt_Swift_1i_1set")
        func BridgeKt_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: Int32) {
            i = Int(value)
        }
        """, transformers: transformers)

        try await check(swiftBridge: """
        public var s = ""
        """, kotlin: """
        var s: String
            get() = Swift_s()
            set(newValue) {
                Swift_s_set(newValue)
            }
        private external fun Swift_s(): String
        private external fun Swift_s_set(value: String)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1s")
        func BridgeKt_Swift_s(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaString {
            return s.toJavaObject(options: [])!
        }
        @_cdecl("Java_BridgeKt_Swift_1s_1set")
        func BridgeKt_Swift_s_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaString) {
            s = String.fromJavaObject(value, options: [])
        }
        """, transformers: transformers)
    }

    func testBridgeIgnoredVar() async throws {
        try await check(swiftBridge: """
        @BridgeIgnored
        public var i = 1
        // SKIP @BridgeIgnored
        public var s = ""
        """, kotlin: """
        """, swiftBridgeSupport: """
        """, transformers: transformers)
    }

    func testPrivateVar() async throws {
        try await check(swiftBridge: """
        private var i = 1
        public let s = ""
        """, kotlin: """
        val s = ""
        """, swiftBridgeSupport: """
        """, transformers: transformers)
    }

    func testPrivateSetVar() async throws {
        try await check(swiftBridge: """
        public private(set) var i = 1
        """, kotlin: """
        val i: Int
            get() = Swift_i()
        private external fun Swift_i(): Int
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int32 {
            return Int32(i)
        }
        """, transformers: transformers)

        try await check(swiftBridge: """
        public private(set) var d: Double {
            get {
                return 1.0
            }
            set {
                print("set")
            }
        }
        """, kotlin: """
        val d: Double
            get() = Swift_d()
        private external fun Swift_d(): Double
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1d")
        func BridgeKt_Swift_d(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Double {
            return d
        }
        """, transformers: transformers)
    }

    func testUnicodeNameVar() async throws {
        // TODO
    }

    func testWillSetDidSet() async throws {
        try await check(swiftBridge: """
        public var s = "" {
            willSet {
                print("willSet")
            }
            didSet {
                print("didSet")
            }
        }
        """, kotlin: """
        var s: String
            get() = Swift_s()
            set(newValue) {
                Swift_s_set(newValue)
            }
        private external fun Swift_s(): String
        private external fun Swift_s_set(value: String)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1s")
        func BridgeKt_Swift_s(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaString {
            return s.toJavaObject(options: [])!
        }
        @_cdecl("Java_BridgeKt_Swift_1s_1set")
        func BridgeKt_Swift_s_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaString) {
            s = String.fromJavaObject(value, options: [])
        }
        """, transformers: transformers)
    }

    func testComputedVar() async throws {
        try await check(swiftBridge: """
        public var i: Int64 {
            get {
                return 1
            }
            set {
            }
        }
        """, kotlin: """
        var i: Long
            get() = Swift_i()
            set(newValue) {
                Swift_i_set(newValue)
            }
        private external fun Swift_i(): Long
        private external fun Swift_i_set(value: Long)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int64 {
            return i
        }
        @_cdecl("Java_BridgeKt_Swift_1i_1set")
        func BridgeKt_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: Int64) {
            i = value
        }
        """, transformers: transformers)
    }

    func testArrayVar() async throws {
        try await check(swiftBridge: """
        public var a = [1, 2, 3]
        """, kotlin: """
        import skip.lib.Array

        var a: Array<Int>
            get() = Swift_a().sref({ a = it })
            set(newValue) {
                @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                Swift_a_set(newValue)
            }
        private external fun Swift_a(): Array<Int>
        private external fun Swift_a_set(value: Array<Int>)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1a")
        func BridgeKt_Swift_a(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer {
            return a.toJavaObject(options: [])!
        }
        @_cdecl("Java_BridgeKt_Swift_1a_1set")
        func BridgeKt_Swift_a_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer) {
            a = [Int].fromJavaObject(value, options: [])
        }
        """, transformers: transformers)
    }

    func testKeywordVar() async throws {
        try await check(swiftBridge: """
        public var object: String {
            get {
                return ""
            }
        }
        """, kotlin: """
        val object_: String
            get() = Swift_object()
        private external fun Swift_object(): String
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1object")
        func BridgeKt_Swift_object(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaString {
            return object.toJavaObject(options: [])!
        }
        """, transformers: transformers)
    }

    func testThrowsVar() async throws {
        try await checkProducesMessage(swift: """
        public var i: Int {
            get throws {
                return 0
            }
        }
        """, isSwiftBridge: true, transformers: transformers)
    }

    func testAsyncVar() async throws {
        try await checkProducesMessage(swift: """
        public var i: Int {
            get async {
                return 0
            }
        }
        """, isSwiftBridge: true, transformers: transformers)
    }

    func testOptionalVar() async throws {
        try await check(swiftBridge: """
        public var i: Int? = 1
        """, kotlin: """
        var i: Int?
            get() = Swift_i()
            set(newValue) {
                Swift_i_set(newValue)
            }
        private external fun Swift_i(): Int?
        private external fun Swift_i_set(value: Int?)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer? {
            return i.toJavaObject(options: [])
        }
        @_cdecl("Java_BridgeKt_Swift_1i_1set")
        func BridgeKt_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer?) {
            i = Int?.fromJavaObject(value, options: [])
        }
        """, transformers: transformers)
    }

    func testUnwrappedOptionalVar() async throws {
        try await checkProducesMessage(swift: """
        public var s: String!
        """, isSwiftBridge: true, transformers: transformers)
    }

    func testLazyVar() async throws {
        try await checkProducesMessage(swift: """
        public lazy var s: String = createString()
        """, isSwiftBridge: true, transformers: transformers)
    }

    func testTranspiledBridgedTypeVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public class C {
        }
        #endif
        """, swiftBridge: """
        public var c = C()
        """, kotlins: ["""
        var c: C
            get() = Swift_c()
            set(newValue) {
                Swift_c_set(newValue)
            }
        private external fun Swift_c(): C
        private external fun Swift_c_set(value: C)
        """, """
        open class C {

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """], swiftBridgeSupports: ["""
        @_cdecl("Java_BridgeKt_Swift_1c")
        func BridgeKt_Swift_c(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer {
            return c.toJavaObject(options: [])!
        }
        @_cdecl("Java_BridgeKt_Swift_1c_1set")
        func BridgeKt_Swift_c_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer) {
            c = C.fromJavaObject(value, options: [])
        }
        """, """
        public class C: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "C")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public init() {
                Java_peer = jniContext {
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [])
                    return JObject(ptr)
                }
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "()V")!
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        """], transformers: transformers)
    }

    func testOptionalTranspiledBridgedTypeVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public class C {
        }
        #endif
        """, swiftBridge: """
        public var c: C? = C()
        """, kotlins: ["""
        var c: C?
            get() = Swift_c()
            set(newValue) {
                Swift_c_set(newValue)
            }
        private external fun Swift_c(): C?
        private external fun Swift_c_set(value: C?)
        """, """
        open class C {

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """], swiftBridgeSupports: ["""
        @_cdecl("Java_BridgeKt_Swift_1c")
        func BridgeKt_Swift_c(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer? {
            return c.toJavaObject(options: [])
        }
        @_cdecl("Java_BridgeKt_Swift_1c_1set")
        func BridgeKt_Swift_c_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer?) {
            c = C?.fromJavaObject(value, options: [])
        }
        """, """
        public class C: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "C")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public init() {
                Java_peer = jniContext {
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [])
                    return JObject(ptr)
                }
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "()V")!
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        """], transformers: transformers)
    }

    func testCompiledBridgedTypeVar() async throws {
        try await check(swiftBridge: """
        public class C {
        }
        public var c = C()
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer
        
            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()
        
            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        var c: C
            get() = Swift_c()
            set(newValue) {
                Swift_c_set(newValue)
            }
        private external fun Swift_c(): C
        private external fun Swift_c_set(value: C)
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_BridgeKt_Swift_1c")
        func BridgeKt_Swift_c(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer {
            return c.toJavaObject(options: [])!
        }
        @_cdecl("Java_BridgeKt_Swift_1c_1set")
        func BridgeKt_Swift_c_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer) {
            c = C.fromJavaObject(value, options: [])
        }
        """, transformers: transformers)
    }

    func testOptionalCompiledBridgedTypeVar() async throws {
        try await check(swiftBridge: """
        public class C {
        }
        public var c: C? = C()
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer
        
            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()
        
            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        var c: C?
            get() = Swift_c()
            set(newValue) {
                Swift_c_set(newValue)
            }
        private external fun Swift_c(): C?
        private external fun Swift_c_set(value: C?)
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_BridgeKt_Swift_1c")
        func BridgeKt_Swift_c(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer? {
            return c.toJavaObject(options: [])
        }
        @_cdecl("Java_BridgeKt_Swift_1c_1set")
        func BridgeKt_Swift_c_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer?) {
            c = C?.fromJavaObject(value, options: [])
        }
        """, transformers: transformers)
    }

    func testUnbridgableTypeVar() async throws {
        try await checkProducesMessage(swift: """
        class C {
        }
        public var c: C = C()
        """, isSwiftBridge: true, transformers: transformers)
    }

    func testClosureTypeVar() async throws {
        try await check(swiftBridge: """
        public var c: (Int) -> String = { _ in "" }
        """, kotlin: """
        var c: (Int) -> String
            get() = Swift_c()
            set(newValue) {
                Swift_c_set(newValue)
            }
        private external fun Swift_c(): (Int) -> String
        private external fun Swift_c_set(value: (Int) -> String)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1c")
        func BridgeKt_Swift_c(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer {
            return SwiftClosure1.javaObject(for: c, options: [])!
        }
        @_cdecl("Java_BridgeKt_Swift_1c_1set")
        func BridgeKt_Swift_c_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer) {
            c = SwiftClosure1.closure(forJavaObject: value, options: [])!
        }
        """, transformers: transformers)
    }

    func testVoidClosureTypeVar() async throws {
        try await check(swiftBridge: """
        public var c: () -> Void = { }
        """, kotlin: """
        var c: () -> Unit
            get() = Swift_c()
            set(newValue) {
                Swift_c_set(newValue)
            }
        private external fun Swift_c(): () -> Unit
        private external fun Swift_c_set(value: () -> Unit)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1c")
        func BridgeKt_Swift_c(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer {
            return SwiftClosure0.javaObject(for: c, options: [])!
        }
        @_cdecl("Java_BridgeKt_Swift_1c_1set")
        func BridgeKt_Swift_c_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer) {
            c = SwiftClosure0.closure(forJavaObject: value, options: [])!
        }
        """, transformers: transformers)
    }

    func testFunction() async throws {
        try await check(swiftBridge: """
        public func f(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        """, kotlin: """
        fun f(i: Int, s: String): Int = Swift_f_0(i, s)
        private external fun Swift_f_0(i: Int, s: String): Int
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32, _ p_1: JavaString) -> Int32 {
            let p_0_swift = Int(p_0)
            let p_1_swift = String.fromJavaObject(p_1, options: [])
            let f_return_swift = f(i: p_0_swift, s: p_1_swift)
            return Int32(f_return_swift)
        }
        """, transformers: transformers)
    }

    func testBridgeIgnoredFunction() async throws {
        try await check(swiftBridge: """
        // SKIP @BridgeIgnored
        public func f(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        """, kotlin: """
        """, swiftBridgeSupport: """
        """)
    }

    func testPrivateFunction() async throws {
        try await check(swiftBridge: """
        private func f() {
        }
        public func g() {
        }
        """, kotlin: """
        fun g(): Unit = Swift_g_0()
        private external fun Swift_g_0()
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1g_10")
        func BridgeKt_Swift_g_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) {
            g()
        }
        """, transformers: transformers)
    }

    func testThrowsFunction() async throws {
        try await check(swiftBridge: """
        public func f() throws -> Int {
            return 1
        }
        """, kotlin: """
        fun f(): Int = Swift_f_0()!!
        private external fun Swift_f_0(): Int?
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer? {
            do {
                let f_return_swift = try f()
                return f_return_swift.toJavaObject(options: [])
            } catch {
                JavaThrowError(error, env: Java_env)
                return nil
            }
        }
        """, transformers: transformers)
    }

    func testThrowsVoidFunction() async throws {
        try await check(swiftBridge: """
        public func f(i: Int) throws {
        }
        """, kotlin: """
        fun f(i: Int): Unit = Swift_f_0(i)
        private external fun Swift_f_0(i: Int)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32) {
            let p_0_swift = Int(p_0)
            do {
                try f(i: p_0_swift)
            } catch {
                JavaThrowError(error, env: Java_env)
            }
        }
        """, transformers: transformers)
    }

    func testFunctionParameterLabel() async throws {
        try await check(swiftBridge: """
        public func f(_ i: Int) {
        }
        """, kotlin: """
        fun f(i: Int): Unit = Swift_f_0(i)
        private external fun Swift_f_0(i: Int)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32) {
            let p_0_swift = Int(p_0)
            f(p_0_swift)
        }
        """, transformers: transformers)
    }

    func testFunctionParameterDefaultValue() async throws {
        try await check(swiftBridge: """
        public func f(i: Int = 0) -> Int {
            return i
        }
        """, kotlin: """
        fun f(i: Int = 0): Int = Swift_f_0(i)
        private external fun Swift_f_0(i: Int): Int
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32) -> Int32 {
            let p_0_swift = Int(p_0)
            let f_return_swift = f(i: p_0_swift)
            return Int32(f_return_swift)
        }
        """, transformers: transformers)
    }

    func testFunctionParameterLabelOverload() async throws {
        try await check(swiftBridge: """
        public func f(i: Int) -> Int {
            return i
        }
        public func f(value: Int) -> Int {
            return value
        }
        """, kotlin: """
        fun f(i: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null): Int = Swift_f_0(i)
        private external fun Swift_f_0(i: Int): Int
        fun f(value: Int): Int = Swift_f_1(value)
        private external fun Swift_f_1(value: Int): Int
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32) -> Int32 {
            let p_0_swift = Int(p_0)
            let f_return_swift = f(i: p_0_swift)
            return Int32(f_return_swift)
        }
        @_cdecl("Java_BridgeKt_Swift_1f_11")
        func BridgeKt_Swift_f_1(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32) -> Int32 {
            let p_0_swift = Int(p_0)
            let f_return_swift = f(value: p_0_swift)
            return Int32(f_return_swift)
        }
        """, transformers: transformers)
    }

    func testKeywordFunction() async throws {
        try await check(swiftBridge: """
        public func object(object: Int) {
        }
        """, kotlin: """
        fun object_(object_: Int): Unit = Swift_object_0(object_)
        private external fun Swift_object_0(object_: Int)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1object_10")
        func BridgeKt_Swift_object_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32) {
            let p_0_swift = Int(p_0)
            object(object: p_0_swift)
        }
        """, transformers: transformers)
    }

    func testOptionalFunction() async throws {
        try await check(swiftBridge: """
        public func f(i: Int?) -> Int? {
            return nil
        }
        """, kotlin: """
        fun f(i: Int?): Int? = Swift_f_0(i)
        private external fun Swift_f_0(i: Int?): Int?
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaObjectPointer?) -> JavaObjectPointer? {
            let p_0_swift = Int?.fromJavaObject(p_0, options: [])
            let f_return_swift = f(i: p_0_swift)
            return f_return_swift.toJavaObject(options: [])
        }
        """, transformers: transformers)
    }

    func testBridgedObjectFunction() async throws {
        try await check(swiftBridge: """
        public class C {
        }
        public func f(c: C) -> C {
        }
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        fun f(c: C): C = Swift_f_0(c)
        private external fun Swift_f_0(c: C): C
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaObjectPointer) -> JavaObjectPointer {
            let p_0_swift = C.fromJavaObject(p_0, options: [])
            let f_return_swift = f(c: p_0_swift)
            return f_return_swift.toJavaObject(options: [])!
        }
        """, transformers: transformers)
    }

    func testVariadicFunction() async throws {
        try await checkProducesMessage(swift: """
        public func f(i: Int...) { }
        """, isSwiftBridge: true, transformers: transformers)
    }

    func testAsyncFunction() async throws {
        try await check(swiftBridge: """
        public func f(i: Int) async -> Int {
            return i
        }
        """, kotlin: """
        suspend fun f(i: Int): Int = Async.run {
            kotlin.coroutines.suspendCoroutine { f_continuation ->
                Swift_callback_f_0(i) { f_return ->
                    f_continuation.resumeWith(kotlin.Result.success(f_return))
                }
            }
        }
        private external fun Swift_callback_f_0(i: Int, f_callback: (Int) -> Unit)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1callback_1f_10")
        func BridgeKt_Swift_callback_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32, _ f_callback: JavaObjectPointer) {
            let p_0_swift = Int(p_0)
            let f_callback_swift = SwiftClosure1.closure(forJavaObject: f_callback, options: [])! as (Int) -> Void
            Task {
                let f_return_swift = await f(i: p_0_swift)
                f_callback_swift(f_return_swift)
            }
        }
        """, transformers: transformers)
    }

    func testMainActorAsyncFunction() async throws {
        try await check(swiftBridge: """
        @MainActor
        public func f(i: Int) async -> Int {
            return i
        }
        """, kotlin: """
        suspend fun f(i: Int): Int = MainActor.run {
            kotlin.coroutines.suspendCoroutine { f_continuation ->
                Swift_callback_f_0(i) { f_return ->
                    f_continuation.resumeWith(kotlin.Result.success(f_return))
                }
            }
        }
        private external fun Swift_callback_f_0(i: Int, f_callback: (Int) -> Unit)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1callback_1f_10")
        func BridgeKt_Swift_callback_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32, _ f_callback: JavaObjectPointer) {
            let p_0_swift = Int(p_0)
            let f_callback_swift = SwiftClosure1.closure(forJavaObject: f_callback, options: [])! as (Int) -> Void
            Task {
                let f_return_swift = await f(i: p_0_swift)
                f_callback_swift(f_return_swift)
            }
        }
        """, transformers: transformers)
    }

    func testAsyncVoidFunction() async throws {
        try await check(swiftBridge: """
        public func f() async {
        }
        """, kotlin: """
        suspend fun f(): Unit = Async.run {
            kotlin.coroutines.suspendCoroutine { f_continuation ->
                Swift_callback_f_0() {
                    f_continuation.resumeWith(kotlin.Result.success(Unit))
                }
            }
        }
        private external fun Swift_callback_f_0(f_callback: () -> Unit)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1callback_1f_10")
        func BridgeKt_Swift_callback_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ f_callback: JavaObjectPointer) {
            let f_callback_swift = SwiftClosure0.closure(forJavaObject: f_callback, options: [])! as () -> Void
            Task {
                await f()
                f_callback_swift()
            }
        }
        """, transformers: transformers)
    }

    func testAsyncThrowsFunction() async throws {
        try await check(swiftBridge: """
        public func f() async throws -> Int {
            return 1
        }
        """, kotlin: """
        suspend fun f(): Int = Async.run {
            kotlin.coroutines.suspendCoroutine { f_continuation ->
                Swift_callback_f_0() { f_return, f_error ->
                    if (f_error != null) {
                        f_continuation.resumeWith(kotlin.Result.failure(f_error))
                    } else {
                        f_continuation.resumeWith(kotlin.Result.success(f_return!!))
                    }
                }
            }
        }
        private external fun Swift_callback_f_0(f_callback: (Int?, Throwable?) -> Unit)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1callback_1f_10")
        func BridgeKt_Swift_callback_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ f_callback: JavaObjectPointer) {
            let f_callback_swift = SwiftClosure2.closure(forJavaObject: f_callback, options: [])! as (Int?, JavaObjectPointer?) -> Void
            Task {
                do {
                    let f_return_swift = try await f()
                    f_callback_swift(f_return_swift, nil)
                } catch {
                    jniContext {
                        f_callback_swift(nil, JavaErrorThrowable(error, env: Java_env))
                    }
                }
            }
        }
        """, transformers: transformers)
    }

    func testAsyncThrowsVoidFunction() async throws {
        try await check(swiftBridge: """
        public func f(i: Int) async throws {
        }
        """, kotlin: """
        suspend fun f(i: Int): Unit = Async.run {
            kotlin.coroutines.suspendCoroutine { f_continuation ->
                Swift_callback_f_0(i) { f_error ->
                    if (f_error != null) {
                        f_continuation.resumeWith(kotlin.Result.failure(f_error))
                    } else {
                        f_continuation.resumeWith(kotlin.Result.success(Unit))
                    }
                }
            }
        }
        private external fun Swift_callback_f_0(i: Int, f_callback: (Throwable?) -> Unit)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1callback_1f_10")
        func BridgeKt_Swift_callback_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32, _ f_callback: JavaObjectPointer) {
            let p_0_swift = Int(p_0)
            let f_callback_swift = SwiftClosure1.closure(forJavaObject: f_callback, options: [])! as (JavaObjectPointer?) -> Void
            Task {
                do {
                    try await f(i: p_0_swift)
                    f_callback_swift(nil)
                } catch {
                    jniContext {
                        f_callback_swift(JavaErrorThrowable(error, env: Java_env))
                    }
                }
            }
        }
        """, transformers: transformers)
    }

    func testClass() async throws {
        try await check(swiftBridge: """
        public class C {
            public var i = 1
        }
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer
        
            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            open var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.kt.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.kt.SwiftObjectPointer, value: Int)

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_C_Swift_1i")
        func C_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int32 {
            let peer_swift: C = Swift_peer.pointee()!
            return Int32(peer_swift.i)
        }
        @_cdecl("Java_C_Swift_1i_1set")
        func C_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: Int32) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.i = Int(value)
        }
        """, transformers: transformers)
    }

    func testGenericClass() async throws {
        try await checkProducesMessage(swift: """
        public class C<T> {
            var value: T
            func f(v: T) -> T {
                return v
            }
        }
        """, isSwiftBridge: true, transformers: transformers)
    }

    func testOpenClass() async throws {
        try await check(swiftBridge: """
        open class C {
            open var i = 1
        }
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            open var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.kt.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.kt.SwiftObjectPointer, value: Int)

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_C_Swift_1i")
        func C_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int32 {
            let peer_swift: C = Swift_peer.pointee()!
            return Int32(peer_swift.i)
        }
        @_cdecl("Java_C_Swift_1i_1set")
        func C_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: Int32) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.i = Int(value)
        }
        """, transformers: transformers)
    }

    func testInnerClass() async throws {
        try await checkProducesMessage(swift: """
        public class D {
            public class C {
            }
        }
        """, isSwiftBridge: true, transformers: transformers)
    }

    func testPrivateClass() async throws {
        try await check(swiftBridge: """
        public let i = 0
        private class C {
        }
        """, kotlin: """
        val i = 0
        """, swiftBridgeSupport: """
        """, transformers: transformers)
    }

    func testPrivateConstructor() async throws {
        try await check(swiftBridge: """
        public class C {
            private init(i: Int) {
            }
        }
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        """, transformers: transformers)
    }

    func testConstructor() async throws {
        try await check(swiftBridge: """
        public class C {
            public init(i: Int) {
            }
        }
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer
        
            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            constructor(i: Int) {
                Swift_peer = Swift_constructor_0(i)
            }
            private external fun Swift_constructor_0(i: Int): skip.bridge.kt.SwiftObjectPointer

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_C_Swift_1constructor_10")
        func C_Swift_constructor_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32) -> SwiftObjectPointer {
            let p_0_swift = Int(p_0)
            let f_return_swift = C(i: p_0_swift)
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        """, transformers: transformers)
    }

    func testThrowsConstructor() async throws {
        try await check(swiftBridge: """
        public class C {
            public init(i: Int) throws {
            }
        }
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            constructor(i: Int) {
                Swift_peer = Swift_constructor_0(i)!!
            }
            private external fun Swift_constructor_0(i: Int): skip.bridge.kt.SwiftObjectPointer

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_C_Swift_1constructor_10")
        func C_Swift_constructor_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32) -> SwiftObjectPointer? {
            let p_0_swift = Int(p_0)
            do {
                let f_return_swift = try C(i: p_0_swift)
                return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
            } catch {
                JavaThrowError(error, env: Java_env)
                return nil
            }
        }
        """, transformers: transformers)
    }

    func testOptionalConstructor() async throws {
        try await checkProducesMessage(swift: """
        public class C {
            public init?(i: Int) {
                return nil
            }
        }
        """, isSwiftBridge: true, transformers: transformers)
    }

    func testDestructor() async throws {
        try await check(swiftBridge: """
        public class C {
            deinit {
            }
        }
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        """, transformers: transformers)
    }

    func testMemberConstant() async throws {
        try await check(swiftBridge: """
        public class C {
            public let i = 0
        }
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            val i = 0

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        """, transformers: transformers)
    }

    func testMemberVar() async throws {
        try await check(swiftBridge: """
        public class C {
            public var i = 0
        }
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            open var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.kt.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.kt.SwiftObjectPointer, value: Int)

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_C_Swift_1i")
        func C_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int32 {
            let peer_swift: C = Swift_peer.pointee()!
            return Int32(peer_swift.i)
        }
        @_cdecl("Java_C_Swift_1i_1set")
        func C_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: Int32) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.i = Int(value)
        }
        """, transformers: transformers)
    }

    func testMemberFunction() async throws {
        try await check(swiftBridge: """
        public class C {
            public func add(a: Int, b: Int) -> Int {
                return a + b
            }
        }
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()
        
            open fun add(a: Int, b: Int): Int = Swift_add_0(Swift_peer, a, b)
            private external fun Swift_add_0(Swift_peer: skip.bridge.kt.SwiftObjectPointer, a: Int, b: Int): Int

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_C_Swift_1add_10")
        func C_Swift_add_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ p_0: Int32, _ p_1: Int32) -> Int32 {
            let p_0_swift = Int(p_0)
            let p_1_swift = Int(p_1)
            let peer_swift: C = Swift_peer.pointee()!
            let f_return_swift = peer_swift.add(a: p_0_swift, b: p_1_swift)
            return Int32(f_return_swift)
        }
        """, transformers: transformers)
    }

    func testAsyncMemberFunction() async throws {
        try await check(swiftBridge: """
        public class C {
            public func add() async -> Int {
                return 1
            }
        }
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            open suspend fun add(): Int = Async.run {
                kotlin.coroutines.suspendCoroutine { f_continuation ->
                    Swift_callback_add_0(Swift_peer) { f_return ->
                        f_continuation.resumeWith(kotlin.Result.success(f_return))
                    }
                }
            }
            private external fun Swift_callback_add_0(Swift_peer: skip.bridge.kt.SwiftObjectPointer, f_callback: (Int) -> Unit)

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_C_Swift_1callback_1add_10")
        func C_Swift_callback_add_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ f_callback: JavaObjectPointer) {
            let f_callback_swift = SwiftClosure1.closure(forJavaObject: f_callback, options: [])! as (Int) -> Void
            let peer_swift: C = Swift_peer.pointee()!
            Task {
                let f_return_swift = await peer_swift.add()
                f_callback_swift(f_return_swift)
            }
        }
        """, transformers: transformers)
    }

    func testStaticConstant() async throws {
        try await check(swiftBridge: """
        public class C {
            public static let i = 0
        }
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            companion object: CompanionClass() {

                override val i = 0
            }
            open class CompanionClass {
                open val i
                    get() = C.i
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        """, transformers: transformers)
    }

    func testStaticVar() async throws {
        try await check(swiftBridge: """
        public class C {
            public static var i = 0
        }
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            companion object: CompanionClass() {

                override var i: Int
                    get() = Swift_Companion_i()
                    set(newValue) {
                        Swift_Companion_i_set(newValue)
                    }
                private external fun Swift_Companion_i(): Int
                private external fun Swift_Companion_i_set(value: Int)
            }
            open class CompanionClass {
                open var i: Int
                    get() = C.i
                    set(newValue) {
                        C.i = newValue
                    }
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_C_00024Companion_Swift_1Companion_1i")
        func C_Swift_Companion_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int32 {
            return Int32(C.i)
        }
        @_cdecl("Java_C_00024Companion_Swift_1Companion_1i_1set")
        func C_Swift_Companion_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: Int32) {
            C.i = Int(value)
        }
        """, transformers: transformers)
    }

    func testStaticFunction() async throws {
        try await check(swiftBridge: """
        public class C {
            public static func add(a: Int, b: Int) -> Int {
                return a + b
            }
        }
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            companion object: CompanionClass() {

                override fun add(a: Int, b: Int): Int = Swift_Companion_add_0(a, b)
                private external fun Swift_Companion_add_0(a: Int, b: Int): Int
            }
            open class CompanionClass {
                open fun add(a: Int, b: Int): Int = C.add(a = a, b = b)
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_C_00024Companion_Swift_1Companion_1add_10")
        func C_Swift_Companion_add_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32, _ p_1: Int32) -> Int32 {
            let p_0_swift = Int(p_0)
            let p_1_swift = Int(p_1)
            let f_return_swift = C.add(a: p_0_swift, b: p_1_swift)
            return Int32(f_return_swift)
        }
        """, transformers: transformers)
    }

    func testSubscript() async throws {
        try await checkProducesMessage(swift: """
        public class C {
            public subscript(index: Int) -> Int {
                get {
                    return 0
                }
                set {
                }
            }
        }
        """, isSwiftBridge: true, transformers: transformers)
    }

    func testUnbridgedMember() async throws {
        try await check(swiftBridge: """
        public class C {
            @BridgeIgnored
            public var i = 1
        }
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        """, transformers: transformers)
    }

    func testCommonProtocols() async throws {
        try await check(swiftBridge: """
        public class C: Equatable, Hashable, Comparable {
            public var i = 1
            public static func ==(lhs: C, rhs: C) -> Bool {
                return lhs.i == rhs.i
            }
            public func hash(into hasher: inout Hasher) {
                hasher.combine(i)
            }
            public static func <(lhs: C, rhs: C) -> Bool {
                return lhs.i < rhs.i
            }
        }
        """, kotlin: """
        open class C: Comparable<C>, skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            open var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.kt.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.kt.SwiftObjectPointer, value: Int)
            override fun equals(other: Any?): Boolean {
                if (other !is C) {
                    return false
                }
                val lhs = this
                val rhs = other
                return Swift_isequal(lhs, rhs)
            }
            private external fun Swift_isequal(lhs: C, rhs: C): Boolean
            override fun hashCode(): Int {
                var hasher = Hasher()
                hash(into = InOut<Hasher>({ hasher }, { hasher = it }))
                return hasher.finalize()
            }
            open fun hash(into: InOut<Hasher>) {
                val hasher = into
                hasher.value.combine(Swift_hashvalue(Swift_peer))
            }
            private external fun Swift_hashvalue(Swift_peer: skip.bridge.kt.SwiftObjectPointer): Long
            override fun compareTo(other: C): Int {
                if (this == other) return 0
                fun islessthan(lhs: C, rhs: C): Boolean {
                    return Swift_islessthan(lhs, rhs)
                }
                return if (islessthan(this, other)) -1 else 1
            }
            private external fun Swift_islessthan(lhs: C, rhs: C): Boolean

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_C_Swift_1i")
        func C_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int32 {
            let peer_swift: C = Swift_peer.pointee()!
            return Int32(peer_swift.i)
        }
        @_cdecl("Java_C_Swift_1i_1set")
        func C_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: Int32) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.i = Int(value)
        }
        @_cdecl("Java_C_Swift_1isequal")
        func C_Swift_isequal(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ lhs: JavaObjectPointer, _ rhs: JavaObjectPointer) -> Bool {
            let lhs_swift = C.fromJavaObject(lhs, options: [])
            let rhs_swift = C.fromJavaObject(rhs, options: [])
            return lhs_swift == rhs_swift
        }
        @_cdecl("Java_C_Swift_1hashvalue")
        func C_Swift_hashvalue(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int64 {
            let peer_swift: C = Swift_peer.pointee()!
            return Int64(peer_swift.hashValue)
        }
        @_cdecl("Java_C_Swift_1islessthan")
        func C_Swift_islessthan(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ lhs: JavaObjectPointer, _ rhs: JavaObjectPointer) -> Bool {
            let lhs_swift = C.fromJavaObject(lhs, options: [])
            let rhs_swift = C.fromJavaObject(rhs, options: [])
            return lhs_swift < rhs_swift
        }
        """, transformers: transformers)
    }

    func testCodable() async throws {
        try await check(swiftBridge: """
        public class C: Codable {
            public var i = 1
        
            private enum CK: CodingKey {
                case i
            }

            public func encode(to encoder: Encoder) {
            }

            public init(from decoder: Decoder) {
            }
        }
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            open var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.kt.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.kt.SwiftObjectPointer, value: Int)

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_C_Swift_1i")
        func C_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int32 {
            let peer_swift: C = Swift_peer.pointee()!
            return Int32(peer_swift.i)
        }
        @_cdecl("Java_C_Swift_1i_1set")
        func C_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: Int32) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.i = Int(value)
        }
        """, transformers: transformers)
    }

    func testSubclass() async throws {
        try await checkProducesMessage(swift: """
        public class Base {
        }
        public class Sub: Base {
        }
        """, isSwiftBridge: true, transformers: transformers)
    }

    func testStruct() async throws {
        try await check(swiftBridge: """
        public struct S {
            public var i = 1
            public init(s: String) {
                self.i = Int(s)!
            }
            public func f() -> Int {
                return i
            }
        }
        """, kotlin: """
        class S: MutableStruct, skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    willmutate()
                    try {
                        Swift_i_set(Swift_peer, newValue)
                    } finally {
                        didmutate()
                    }
                }
            private external fun Swift_i(Swift_peer: skip.bridge.kt.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.kt.SwiftObjectPointer, value: Int)
            constructor(s: String) {
                Swift_peer = Swift_constructor_0(s)
            }
            private external fun Swift_constructor_0(s: String): skip.bridge.kt.SwiftObjectPointer
            fun f(): Int = Swift_f_1(Swift_peer)
            private external fun Swift_f_1(Swift_peer: skip.bridge.kt.SwiftObjectPointer): Int
            private constructor(copy: skip.lib.MutableStruct) {
                Swift_peer = Swift_constructor_2(copy)
            }
            private external fun Swift_constructor_2(copy: skip.lib.MutableStruct): skip.bridge.kt.SwiftObjectPointer

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(this as MutableStruct)

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension S: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "S")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                let box: SwiftValueTypeBox<Self> = ptr.pointee()!
                return box.value
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let box = SwiftValueTypeBox(self)
                let Swift_peer = SwiftObjectPointer.pointer(to: box, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_S_Swift_1release")
        func S_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: SwiftValueTypeBox<S>.self)
        }
        @_cdecl("Java_S_Swift_1i")
        func S_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int32 {
            let peer_swift: SwiftValueTypeBox<S> = Swift_peer.pointee()!
            return Int32(peer_swift.value.i)
        }
        @_cdecl("Java_S_Swift_1i_1set")
        func S_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: Int32) {
            let peer_swift: SwiftValueTypeBox<S> = Swift_peer.pointee()!
            peer_swift.value.i = Int(value)
        }
        @_cdecl("Java_S_Swift_1constructor_10")
        func S_Swift_constructor_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaString) -> SwiftObjectPointer {
            let p_0_swift = String.fromJavaObject(p_0, options: [])
            let f_return_swift = SwiftValueTypeBox(S(s: p_0_swift))
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_S_Swift_1f_11")
        func S_Swift_f_1(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int32 {
            let peer_swift: SwiftValueTypeBox<S> = Swift_peer.pointee()!
            let f_return_swift = peer_swift.value.f()
            return Int32(f_return_swift)
        }
        @_cdecl("Java_S_Swift_1constructor_12")
        func S_Swift_constructor_2(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaObjectPointer) -> SwiftObjectPointer {
            let p_0_swift = S.fromJavaObject(p_0, options: [])
            let f_return_swift = SwiftValueTypeBox(p_0_swift)
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        """, transformers: transformers)
    }

    func testStructCommonProtocols() async throws {
        try await check(swiftBridge: """
        public struct S: Equatable, Hashable, Comparable {
            public var i = 1
            public static func <(lhs: C, rhs: C) -> Bool {
                return lhs.i < rhs.i
            }
        }
        """, kotlin: """
        class S: Comparable<S>, MutableStruct, skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    willmutate()
                    try {
                        Swift_i_set(Swift_peer, newValue)
                    } finally {
                        didmutate()
                    }
                }
            private external fun Swift_i(Swift_peer: skip.bridge.kt.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.kt.SwiftObjectPointer, value: Int)
            override fun compareTo(other: C): Int {
                if (this == other) return 0
                fun islessthan(lhs: C, rhs: C): Boolean {
                    return Swift_islessthan(lhs, rhs)
                }
                return if (islessthan(this, other)) -1 else 1
            }
            private external fun Swift_islessthan(lhs: S, rhs: S): Boolean
            constructor(i: Int = 1) {
                Swift_peer = Swift_constructor_0(i)
            }
            private external fun Swift_constructor_0(i: Int): skip.bridge.kt.SwiftObjectPointer

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(i)
            override fun equals(other: Any?): Boolean {
                if (other === this) return true
                if (other !is S) return false
                return Swift_isequal(this, other)
            }
            private external fun Swift_isequal(lhs: S, rhs: S): Boolean
            override fun hashCode(): Int = Swift_hashvalue(Swift_peer).hashCode()
            private external fun Swift_hashvalue(Swift_peer: skip.bridge.kt.SwiftObjectPointer): Long

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension S: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "S")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                let box: SwiftValueTypeBox<Self> = ptr.pointee()!
                return box.value
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let box = SwiftValueTypeBox(self)
                let Swift_peer = SwiftObjectPointer.pointer(to: box, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_S_Swift_1release")
        func S_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: SwiftValueTypeBox<S>.self)
        }
        @_cdecl("Java_S_Swift_1i")
        func S_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int32 {
            let peer_swift: SwiftValueTypeBox<S> = Swift_peer.pointee()!
            return Int32(peer_swift.value.i)
        }
        @_cdecl("Java_S_Swift_1i_1set")
        func S_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: Int32) {
            let peer_swift: SwiftValueTypeBox<S> = Swift_peer.pointee()!
            peer_swift.value.i = Int(value)
        }
        @_cdecl("Java_S_Swift_1islessthan")
        func S_Swift_islessthan(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ lhs: JavaObjectPointer, _ rhs: JavaObjectPointer) -> Bool {
            let lhs_swift = S.fromJavaObject(lhs, options: [])
            let rhs_swift = S.fromJavaObject(rhs, options: [])
            return lhs_swift < rhs_swift
        }
        @_cdecl("Java_S_Swift_1constructor_10")
        func S_Swift_constructor_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32) -> SwiftObjectPointer {
            let p_0_swift = Int(p_0)
            let f_return_swift = SwiftValueTypeBox(S(i: p_0_swift))
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_S_Swift_1isequal")
        func S_Swift_isequal(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ lhs: JavaObjectPointer, _ rhs: JavaObjectPointer) -> Bool {
            let lhs_swift = S.fromJavaObject(lhs, options: [])
            let rhs_swift = S.fromJavaObject(rhs, options: [])
            return lhs_swift == rhs_swift
        }
        @_cdecl("Java_S_Swift_1hashvalue")
        func S_Swift_hashvalue(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int64 {
            let peer_swift: SwiftValueTypeBox<S> = Swift_peer.pointee()!
            return Int64(peer_swift.value.hashValue)
        }
        """, transformers: transformers)
    }

    func testProtocolConformance() async throws {
        try await check(swiftBridge: """
        @BridgeIgnored
        public protocol Unbridged {
            func x()
        }
        protocol Unbridged2 {
            func y()
        }
        public protocol Base: Equatable, Hashable {
            func a()
        }
        public protocol P: Base, Unbridged, Unbridged2 {
            func f() -> Int
        }
        public class C: P {
            public func a() {
            }
            public func f() {
                return 1
            }
        }
        """, kotlin: """
        interface Base {
            fun a()
        }
        interface P: Base {
            fun f(): Int
        }
        open class C: P, skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun a(): Unit = Swift_a_0(Swift_peer)
            private external fun Swift_a_0(Swift_peer: skip.bridge.kt.SwiftObjectPointer)
            override fun f(): Unit = Swift_f_1(Swift_peer)
            private external fun Swift_f_1(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        public final class Base_BridgeImpl: Base, BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "Base")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public func a() {
                jniContext {
                    try! Java_peer.call(method: Self.Java_a_0_methodID, options: [], args: [])
                }
            }
            private static let Java_a_0_methodID = Java_class.getMethodID(name: "a", sig: "()V")!
            public static func ==(lhs: Base_BridgeImpl, rhs: Base_BridgeImpl) -> Bool {
                return jniContext {
                    let lhs_java = lhs.toJavaObject(options: [])!
                    let rhs_java = rhs.toJavaParameter(options: [])
                    return try! Bool.call(Java_isequal_methodID, on: lhs_java, options: [], args: [rhs_java])
                }
            }
            private static let Java_isequal_methodID = Java_class.getMethodID(name: "equals", sig: "(Ljava/lang/Object;)Z")!
            public func hash(into hasher: inout Hasher) {
                let hashCode: Int32 = jniContext {
                    return try! Java_peer.call(method: Self.Java_hashCode_methodID, options: [], args: [])
                }
                hasher.combine(hashCode)
            }
            private static let Java_hashCode_methodID = Java_class.getMethodID(name: "hashCode", sig: "()I")!
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        public final class P_BridgeImpl: P, BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "P")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public func f() -> Int {
                return jniContext {
                    let f_return_java: Int32 = try! Java_peer.call(method: Self.Java_f_0_methodID, options: [], args: [])
                    return Int(f_return_java)
                }
            }
            private static let Java_f_0_methodID = Java_class.getMethodID(name: "f", sig: "()I")!
            public func a() {
                jniContext {
                    try! Java_peer.call(method: Self.Java_a_1_methodID, options: [], args: [])
                }
            }
            private static let Java_a_1_methodID = Java_class.getMethodID(name: "a", sig: "()V")!
            public static func ==(lhs: P_BridgeImpl, rhs: P_BridgeImpl) -> Bool {
                return jniContext {
                    let lhs_java = lhs.toJavaObject(options: [])!
                    let rhs_java = rhs.toJavaParameter(options: [])
                    return try! Bool.call(Java_isequal_methodID, on: lhs_java, options: [], args: [rhs_java])
                }
            }
            private static let Java_isequal_methodID = Java_class.getMethodID(name: "equals", sig: "(Ljava/lang/Object;)Z")!
            public func hash(into hasher: inout Hasher) {
                let hashCode: Int32 = jniContext {
                    return try! Java_peer.call(method: Self.Java_hashCode_methodID, options: [], args: [])
                }
                hasher.combine(hashCode)
            }
            private static let Java_hashCode_methodID = Java_class.getMethodID(name: "hashCode", sig: "()I")!
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_C_Swift_1a_10")
        func C_Swift_a_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.a()
        }
        @_cdecl("Java_C_Swift_1f_11")
        func C_Swift_f_1(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.f()
        }
        """, transformers: transformers)
    }

    func testProtocolTypeMembers() async throws {
        try await check(swiftBridge: """
        public protocol P {
        }
        public class C {
            public var p: (any P)?
            public func f(p: any P) -> (any P)? {
                return nil
            }
        }
        """, kotlin: """
        interface P {
        }
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            open var p: P?
                get() = Swift_p(Swift_peer).sref({ this.p = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    Swift_p_set(Swift_peer, newValue)
                }
            private external fun Swift_p(Swift_peer: skip.bridge.kt.SwiftObjectPointer): P?
            private external fun Swift_p_set(Swift_peer: skip.bridge.kt.SwiftObjectPointer, value: P?)
            open fun f(p: P): P? = Swift_f_0(Swift_peer, p)
            private external fun Swift_f_0(Swift_peer: skip.bridge.kt.SwiftObjectPointer, p: P): P?

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        public final class P_BridgeImpl: P, BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "P")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_C_Swift_1p")
        func C_Swift_p(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer? {
            let peer_swift: C = Swift_peer.pointee()!
            return ((peer_swift.p as? JConvertible)?.toJavaObject(options: []))
        }
        @_cdecl("Java_C_Swift_1p_1set")
        func C_Swift_p_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: JavaObjectPointer?) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.p = P_BridgeImpl?.fromJavaObject(value, options: [])
        }
        @_cdecl("Java_C_Swift_1f_10")
        func C_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ p_0: JavaObjectPointer) -> JavaObjectPointer? {
            let p_0_swift = P_BridgeImpl.fromJavaObject(p_0, options: [])
            let peer_swift: C = Swift_peer.pointee()!
            let f_return_swift = peer_swift.f(p: p_0_swift)
            return ((f_return_swift as? JConvertible)?.toJavaObject(options: []))
        }
        """, transformers: transformers)
    }

    func testStaticProtocolRequirements() async throws {
        try await checkProducesMessage(swift: """
        public protocol P {
            static var i: Int { get }
            var s: String { get }
        }
        """, isSwiftBridge: true, transformers: transformers)
    }

    func testEnum() async throws {
        try await check(swiftBridge: """
        public enum E: Int {
            case a = 100, `b`
        
            public init(string: String) {
                switch string {
                case "a": self = .a
                default: self = .b
                }
            }
        
            public var string: String {
                switch self {
                case .a: return "a"
                case .b: return "b"
                }
            }
        
            public func negate() -> Int {
                return self.rawValue * -1
            }
        }
        """, kotlin: """
        enum class E(override val rawValue: Int, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null) {

            a(100),
            b(101);
            val string: String
                get() = Swift_string(name)
            private external fun Swift_string(name: String): String
            fun negate(): Int = Swift_negate_0(name)
            private external fun Swift_negate_0(name: String): Int

            companion object {
                fun init(rawValue: Int): E? {
                    return when (rawValue) {
                        100 -> E.a
                        101 -> E.b
                        else -> null
                    }
                }
                fun init(string: String): E = Swift_Companion_init_2(string)
                private external fun Swift_Companion_init_2(string: String): E
            }
        }
        fun E(string: String): E = E.init(string = string)

        fun E(rawValue: Int): E? = E.init(rawValue = rawValue)
        """, swiftBridgeSupport: """
        extension E: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "E")
            private static let Java_Companion_class = try! JClass(name: "E$Companion")
            private static let Java_Companion = JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: "Companion", sig: "LE$Companion;")!, options: []))
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let name: String = try! obj!.call(method: Java_name_methodID, options: options, args: [])
                return fromJavaName(name)
            }
            fileprivate static func fromJavaName(_ name: String) -> Self {
                return switch name {
                case "a": .a
                case "b": .b
                default: fatalError()
                }
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let name = switch self {
                case .a: "a"
                case .b: "b"
                }
                return try! Self.Java_class.callStatic(method: Self.Java_valueOf_methodID, options: options, args: [name.toJavaParameter(options: options)])
            }
            private static let Java_name_methodID = Java_class.getMethodID(name: "name", sig: "()Ljava/lang/String;")!
            private static let Java_valueOf_methodID = Java_class.getStaticMethodID(name: "valueOf", sig: "(Ljava/lang/String;)LE;")!
        }
        @_cdecl("Java_E_Swift_1string")
        func E_Swift_string(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ name: JavaString) -> JavaString {
            let name_swift = String.fromJavaObject(name, options: [])
            let peer_swift = E.fromJavaName(name_swift)
            return peer_swift.string.toJavaObject(options: [])!
        }
        @_cdecl("Java_E_Swift_1negate_10")
        func E_Swift_negate_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ name: JavaString) -> Int32 {
            let name_swift = String.fromJavaObject(name, options: [])
            let peer_swift = E.fromJavaName(name_swift)
            let f_return_swift = peer_swift.negate()
            return Int32(f_return_swift)
        }
        @_cdecl("Java_E_00024Companion_Swift_1Companion_1init_12")
        func E_Swift_Companion_init_2(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaString) -> JavaObjectPointer {
            let p_0_swift = String.fromJavaObject(p_0, options: [])
            let f_return_swift = E.init(string: p_0_swift)
            return f_return_swift.toJavaObject(options: [])!
        }
        """, transformers: transformers)
    }

    func testEnumWithAssociatedValue() async throws {
        // TODO
        try await checkProducesMessage(swift: """
        public enum E {
            case a(Int), b
        }
        """, isSwiftBridge: true, transformers: transformers)
    }

    func testClassWithExtension() async throws {
        // TODO
//        try await check(swiftBridge: """
//        public class C {
//        }
//        extension C {
//            public static func s() {
//            }
//            public func f() {
//            }
//        }
//        """, kotlin: """
//        """, swiftBridgeSupport: """
//        """)
    }

    func testObservable() async throws {
        try await check(swiftBridge: """
        import SkipFuse
        @Observable
        public class C {
            public var i = 1
        }
        """, kotlin: """
        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            open var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.kt.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.kt.SwiftObjectPointer, value: Int)

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        import SkipFuse
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_C_Swift_1i")
        func C_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int32 {
            let peer_swift: C = Swift_peer.pointee()!
            return Int32(peer_swift.i)
        }
        @_cdecl("Java_C_Swift_1i_1set")
        func C_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: Int32) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.i = Int(value)
        }
        """, transformers: transformers)

        try await checkProducesMessage(swift: """
        @Observable
        public class C {
            public var i = 1
        }
        """, isSwiftBridge: true, transformers: transformers)
    }

    func testKotlinCompatibilityOption() async throws {
        let transformers = builtinKotlinTransformers() + [KotlinBridgeTransformer(options: .kotlincompat)]
        try await check(supportingSwift: """
        class URL: SwiftCustomBridged, KotlinConverting<java.net.URI> {
        }
        """, swiftBridge: """
        public class C {
            public var urls: [URL] = []
            public var map = ["a": [1]]
            public func perform(action: (URL) -> Int) {
            }
        }
        """, kotlins: ["""
        import skip.lib.Array

        open class C: skip.bridge.kt.SwiftPeerBridged {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.kt.SwiftObjectPointer, marker: skip.bridge.kt.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.kt.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.kt.SwiftObjectPointer

            override fun Swift_bridgedPeer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            open var urls: kotlin.collections.List<java.net.URI>
                get() = Swift_urls(Swift_peer)
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    Swift_urls_set(Swift_peer, newValue)
                }
            private external fun Swift_urls(Swift_peer: skip.bridge.kt.SwiftObjectPointer): kotlin.collections.List<java.net.URI>
            private external fun Swift_urls_set(Swift_peer: skip.bridge.kt.SwiftObjectPointer, value: kotlin.collections.List<java.net.URI>)
            open var map: kotlin.collections.Map<String, kotlin.collections.List<Int>>
                get() = Swift_map(Swift_peer)
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    Swift_map_set(Swift_peer, newValue)
                }
            private external fun Swift_map(Swift_peer: skip.bridge.kt.SwiftObjectPointer): kotlin.collections.Map<String, kotlin.collections.List<Int>>
            private external fun Swift_map_set(Swift_peer: skip.bridge.kt.SwiftObjectPointer, value: kotlin.collections.Map<String, kotlin.collections.List<Int>>)
            open fun perform(action: (java.net.URI) -> Int): Unit = Swift_perform_0(Swift_peer, action)
            private external fun Swift_perform_0(Swift_peer: skip.bridge.kt.SwiftObjectPointer, action: (java.net.URI) -> Int)

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, """
        internal open class URL: SwiftCustomBridged, KotlinConverting<java.net.URI> {
        }
        """], swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/kt/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_C_Swift_1urls")
        func C_Swift_urls(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer {
            let peer_swift: C = Swift_peer.pointee()!
            return peer_swift.urls.toJavaObject(options: [.kotlincompat])!
        }
        @_cdecl("Java_C_Swift_1urls_1set")
        func C_Swift_urls_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: JavaObjectPointer) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.urls = [URL].fromJavaObject(value, options: [.kotlincompat])
        }
        @_cdecl("Java_C_Swift_1map")
        func C_Swift_map(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer {
            let peer_swift: C = Swift_peer.pointee()!
            return peer_swift.map.toJavaObject(options: [.kotlincompat])!
        }
        @_cdecl("Java_C_Swift_1map_1set")
        func C_Swift_map_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: JavaObjectPointer) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.map = [String: [Int]].fromJavaObject(value, options: [.kotlincompat])
        }
        @_cdecl("Java_C_Swift_1perform_10")
        func C_Swift_perform_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ p_0: JavaObjectPointer) {
            let p_0_swift = SwiftClosure1.closure(forJavaObject: p_0, options: [.kotlincompat])!
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.perform(action: p_0_swift)
        }
        """, transformers: transformers)
    }
}
