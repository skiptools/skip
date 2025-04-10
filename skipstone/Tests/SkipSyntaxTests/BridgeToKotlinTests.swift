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

    func testNoBridgeVar() async throws {
        try await check(swiftBridge: """
        // SKIP @nobridge
        public var s = ""
        @BridgeIgnored
        public var i = 1
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

    func testUnavailableVar() async throws {
        try await check(swiftBridge: """
        @available(*, unavailable)
        public var s = ""
        """, kotlin: """
        """, swiftBridgeSupport: """
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

    func testTupleVar() async throws {
        try await check(swiftBridge: """
        public var t = ("s", 1)
        """, kotlin: """
        var t: Tuple2<String, Int>
            get() = Swift_t()
            set(newValue) {
                Swift_t_set(newValue)
            }
        private external fun Swift_t(): Tuple2<String, Int>
        private external fun Swift_t_set(value: Tuple2<String, Int>)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1t")
        func BridgeKt_Swift_t(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer {
            return SwiftTuple.javaObject(for: t, options: [])!
        }
        @_cdecl("Java_BridgeKt_Swift_1t_1set")
        func BridgeKt_Swift_t_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer) {
            t = SwiftTuple.tuple(forJavaObject: value, options: [])! as (String, Int)
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
        try await check(swiftBridge: """
        public var i: Int {
            get throws {
                return 0
            }
        }
        """, kotlin: """
        val i: Int
            get() = Swift_i()!!
        private external fun Swift_i(): Int?
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer? {
            do {
                let f_return_swift = try Int32(i)
                return f_return_swift.toJavaObject(options: [])
            } catch {
                JThrowable.throw(error, options: [], env: Java_env)
                return nil
            }
        }
        """, transformers: transformers)
    }

    func testMainActorVar() async throws {
        try await check(swiftBridge: """
        @MainActor
        public var i = 0
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
            return SkipBridge.assumeMainActorUnchecked {
                return Int32(i)
            }
        }
        @_cdecl("Java_BridgeKt_Swift_1i_1set")
        func BridgeKt_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: Int32) {
            SkipBridge.assumeMainActorUnchecked {
                i = Int(value)
            }
        }
        """, transformers: transformers)
    }

    func testThrowsMainActorVar() async throws {
        try await check(swiftBridge: """
        @MainActor
        public var i: Int {
            get throws {
                return 0
            }
        }
        """, kotlin: """
        val i: Int
            get() = Swift_i()!!
        private external fun Swift_i(): Int?
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer? {
            do {
                return try SkipBridge.assumeMainActorUnchecked {
                    let f_return_swift = try Int32(i)
                    return f_return_swift.toJavaObject(options: [])
                }
            } catch {
                JThrowable.throw(error, options: [], env: Java_env)
                return nil
            }
        }
        """, transformers: transformers)
    }

    func testAsyncVar() async throws {
        try await check(swiftBridge: """
        public var i: Int {
            get async {
                return 0
            }
        }
        """, kotlin: """
        suspend fun i(): Int = Async.run {
            kotlin.coroutines.suspendCoroutine { f_continuation ->
                Swift_callback_i() { f_return ->
                    f_continuation.resumeWith(kotlin.Result.success(f_return))
                }
            }
        }
        private external fun Swift_callback_i(f_callback: (Int) -> Unit)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1callback_1i")
        func BridgeKt_Swift_callback_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ f_callback: JavaObjectPointer) {
            let f_callback_swift = SwiftClosure1.closure(forJavaObject: f_callback, options: [])! as (Int) -> Void
            Task {
                let f_return_swift = await i
                f_callback_swift(f_return_swift)
            }
        }
        """, transformers: transformers)
    }

    func testAsyncThrowsVar() async throws {
        try await check(swiftBridge: """
        public var i: Int {
            get async throws {
                return 0
            }
        }
        """, kotlin: """
        suspend fun i(): Int = Async.run {
            kotlin.coroutines.suspendCoroutine { f_continuation ->
                Swift_callback_i() { f_return, f_error ->
                    if (f_error != null) {
                        f_continuation.resumeWith(kotlin.Result.failure(f_error))
                    } else {
                        f_continuation.resumeWith(kotlin.Result.success(f_return!!))
                    }
                }
            }
        }
        private external fun Swift_callback_i(f_callback: (Int?, Throwable?) -> Unit)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1callback_1i")
        func BridgeKt_Swift_callback_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ f_callback: JavaObjectPointer) {
            let f_callback_swift = SwiftClosure2.closure(forJavaObject: f_callback, options: [])! as (Int?, JavaObjectPointer?) -> Void
            Task {
                do {
                    let f_return_swift = try await i
                    f_callback_swift(f_return_swift, nil)
                } catch {
                    jniContext {
                        f_callback_swift(nil, JThrowable.toThrowable(error, options: [])!)
                    }
                }
            }
        }
        """, transformers: transformers)
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
        public final class C {
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
        class C: skip.lib.SwiftProjecting {

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
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
        public final class C: BridgedFromKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public init() {
                Java_peer = jniContext {
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: [], args: [])
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """], transformers: transformers)
    }

    func testOptionalTranspiledBridgedTypeVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
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
        class C: skip.lib.SwiftProjecting {

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
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
        public final class C: BridgedFromKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public init() {
                Java_peer = jniContext {
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: [], args: [])
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """], transformers: transformers)
    }

    func testCompiledBridgedTypeVar() async throws {
        try await check(swiftBridge: """
        public final class C {
        }
        public var c = C()
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
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
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
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
        public final class C {
        }
        public var c: C? = C()
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
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
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
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

    func testUnbridgableVar() async throws {
        try await checkProducesMessage(swift: """
        class C {
        }
        public var c: C = C()
        """, isSwiftBridge: true, transformers: transformers)
    }

    func testClosureVar() async throws {
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
            c = SwiftClosure1.closure(forJavaObject: value, options: [])! as (Int) -> String
        }
        """, transformers: transformers)
    }

    func testVoidClosureVar() async throws {
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
            c = SwiftClosure0.closure(forJavaObject: value, options: [])! as () -> Void
        }
        """, transformers: transformers)
    }

    func testAnyVar() async throws {
        try await check(swiftBridge: """
        public var a: Any = 1
        """, kotlin: """
        var a: Any
            get() = Swift_a().sref({ a = it })
            set(newValue) {
                @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                Swift_a_set(newValue)
            }
        private external fun Swift_a(): Any
        private external fun Swift_a_set(value: Any)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1a")
        func BridgeKt_Swift_a(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer {
            return AnyBridging.toJavaObject(a, options: [])!
        }
        @_cdecl("Java_BridgeKt_Swift_1a_1set")
        func BridgeKt_Swift_a_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer) {
            a = AnyBridging.fromJavaObject(value, options: [])!
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

    func testNoBridgeFunction() async throws {
        try await check(swiftBridge: """
        // SKIP @nobridge
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
                JThrowable.throw(error, options: [], env: Java_env)
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
                JThrowable.throw(error, options: [], env: Java_env)
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
        public final class C {
        }
        public func f(c: C) -> C {
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        fun f(c: C): C = Swift_f_0(c)
        private external fun Swift_f_0(c: C): C
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaObjectPointer) -> JavaObjectPointer {
            let p_0_swift = C.fromJavaObject(p_0, options: [])
            let f_return_swift = f(c: p_0_swift)
            return f_return_swift.toJavaObject(options: [])!
        }
        """, transformers: transformers)
    }

    func testEscapingClosureFunction() async throws {
        try await check(swiftBridge: """
        public func f(c: @escaping (Int) -> Void) -> Int? {
            return nil
        }
        """, kotlin: """
        fun f(c: (Int) -> Unit): Int? = Swift_f_0(c)
        private external fun Swift_f_0(c: (Int) -> Unit): Int?
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaObjectPointer) -> JavaObjectPointer? {
            let p_0_swift = SwiftClosure1.closure(forJavaObject: p_0, options: [])! as (Int) -> Void
            let f_return_swift = f(c: p_0_swift)
            return f_return_swift.toJavaObject(options: [])
        }
        """, transformers: transformers)
    }

    func testVariadicFunction() async throws {
        try await checkProducesMessage(swift: """
        public func f(i: Int...) { }
        """, isSwiftBridge: true, transformers: transformers)
    }

    func testMainActorFunction() async throws {
        try await check(swiftBridge: """
        @MainActor
        public func f(i: Int) -> Int {
            return i
        }
        """, kotlin: """
        fun f(i: Int): Int = Swift_f_0(i)
        private external fun Swift_f_0(i: Int): Int
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32) -> Int32 {
            let p_0_swift = Int(p_0)
            return SkipBridge.assumeMainActorUnchecked {
                let f_return_swift = f(i: p_0_swift)
                return Int32(f_return_swift)
            }
        }
        """, transformers: transformers)
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
                        f_callback_swift(nil, JThrowable.toThrowable(error, options: [])!)
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
                        f_callback_swift(JThrowable.toThrowable(error, options: [])!)
                    }
                }
            }
        }
        """, transformers: transformers)
    }

    func testClass() async throws {
        try await check(swiftBridge: """
        public final class C {
            public var i = 1
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Int)

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testOpenClass() async throws {
        try await check(swiftBridge: """
        open class C {
            open var i = 1
        }
        """, kotlin: """
        open class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            open var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Int)

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedToKotlinBaseClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                let constructor = Java_findConstructor(base: Self.Java_class, Self.Java_constructor_methodID)
                return try! constructor.cls.create(ctor: constructor.ctor, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testInnerClass() async throws {
        try await check(swiftBridge: """
        public enum A {
            public final class B {
                public struct C {
                    public var b = B()
                }
            }
        }
        """, kotlin: """
        enum class A {
            ;
            class B: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
                var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

                constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                    this.Swift_peer = Swift_peer
                }

                fun finalize() {
                    Swift_release(Swift_peer)
                    Swift_peer = skip.bridge.SwiftObjectNil
                }
                private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

                constructor() {
                    Swift_peer = Swift_constructor()
                }
                private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

                override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

                override fun equals(other: Any?): Boolean {
                    if (other !is skip.bridge.SwiftPeerBridged) return false
                    return Swift_peer == other.Swift_peer()
                }

                override fun hashCode(): Int = Swift_peer.hashCode()
                class C: MutableStruct, skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
                    var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

                    constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                        this.Swift_peer = Swift_peer
                    }

                    fun finalize() {
                        Swift_release(Swift_peer)
                        Swift_peer = skip.bridge.SwiftObjectNil
                    }
                    private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

                    override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

                    override fun equals(other: Any?): Boolean {
                        if (other !is skip.bridge.SwiftPeerBridged) return false
                        return Swift_peer == other.Swift_peer()
                    }

                    override fun hashCode(): Int = Swift_peer.hashCode()

                    var b: A.B
                        get() = Swift_b(Swift_peer)
                        set(newValue) {
                            willmutate()
                            try {
                                Swift_b_set(Swift_peer, newValue)
                            } finally {
                                didmutate()
                            }
                        }
                    private external fun Swift_b(Swift_peer: skip.bridge.SwiftObjectPointer): A.B
                    private external fun Swift_b_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: A.B)
                    constructor(b: A.B = B()) {
                        Swift_peer = Swift_constructor_0(b)
                    }
                    private external fun Swift_constructor_0(b: A.B): skip.bridge.SwiftObjectPointer

                    override var supdate: ((Any) -> Unit)? = null
                    override var smutatingcount = 0
                    override fun scopy(): MutableStruct = A.B.C(b)

                    override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
                    private external fun Swift_projectionImpl(options: Int): () -> Any

                    companion object {
                    }
                }

                override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
                private external fun Swift_projectionImpl(options: Int): () -> Any

                companion object {
                }
            }

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension A {
        }
        extension A.B: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "A$B")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
        }
        extension A.B.C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "A$B$C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                let box: SwiftValueTypeBox<Self> = ptr.pointee()!
                return box.value
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let box = SwiftValueTypeBox(self)
                let Swift_peer = SwiftObjectPointer.pointer(to: box, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_A_00024B_Swift_1constructor")
        func A$B_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = A.B()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_A_00024B_Swift_1release")
        func A$B_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: A.B.self)
        }
        @_cdecl("Java_A_00024B_Swift_1projectionImpl")
        func A$B_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = A.B.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        @_cdecl("Java_A_00024B_00024C_Swift_1release")
        func A$B$C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: SwiftValueTypeBox<A.B.C>.self)
        }
        @_cdecl("Java_A_00024B_00024C_Swift_1b")
        func A$B$C_Swift_b(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer {
            let peer_swift: SwiftValueTypeBox<A.B.C> = Swift_peer.pointee()!
            return peer_swift.value.b.toJavaObject(options: [])!
        }
        @_cdecl("Java_A_00024B_00024C_Swift_1b_1set")
        func A$B$C_Swift_b_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: JavaObjectPointer) {
            let peer_swift: SwiftValueTypeBox<A.B.C> = Swift_peer.pointee()!
            peer_swift.value.b = A.B.fromJavaObject(value, options: [])
        }
        @_cdecl("Java_A_00024B_00024C_Swift_1constructor_10")
        func A$B$C_Swift_constructor_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaObjectPointer) -> SwiftObjectPointer {
            let p_0_swift = A.B.fromJavaObject(p_0, options: [])
            let f_return_swift = SwiftValueTypeBox(A.B.C(b: p_0_swift))
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_A_00024B_00024C_Swift_1projectionImpl")
        func A$B$C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = A.B.C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }                       
        """, transformers: transformers)
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
        public final class C {
            private init(i: Int) {
            }
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testConstructor() async throws {
        try await check(swiftBridge: """
        public final class C {
            public init(i: Int) {
            }
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            constructor(i: Int) {
                Swift_peer = Swift_constructor_0(i)
            }
            private external fun Swift_constructor_0(i: Int): skip.bridge.SwiftObjectPointer

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testThrowsConstructor() async throws {
        try await check(swiftBridge: """
        public final class C {
            public init(i: Int) throws {
            }
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            constructor(i: Int) {
                Swift_peer = Swift_constructor_0(i)
            }
            private external fun Swift_constructor_0(i: Int): skip.bridge.SwiftObjectPointer

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        @_cdecl("Java_C_Swift_1constructor_10")
        func C_Swift_constructor_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32) -> SwiftObjectPointer {
            let p_0_swift = Int(p_0)
            do {
                let f_return_swift = try C(i: p_0_swift)
                return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
            } catch {
                JThrowable.throw(error, options: [], env: Java_env)
                return SwiftObjectNil
            }
        }
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
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
        public final class C {
            deinit {
            }
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testMemberConstant() async throws {
        try await check(swiftBridge: """
        public final class C {
            public let i = 0
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            val i = 0

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testMemberVar() async throws {
        try await check(swiftBridge: """
        public final class C {
            public var i = 0
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Int)

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testMemberFunction() async throws {
        try await check(swiftBridge: """
        public final class C {
            public func add(a: Int, b: Int) -> Int {
                return a + b
            }
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            fun add(a: Int, b: Int): Int = Swift_add_0(Swift_peer, a, b)
            private external fun Swift_add_0(Swift_peer: skip.bridge.SwiftObjectPointer, a: Int, b: Int): Int

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testAsyncMemberFunction() async throws {
        try await check(swiftBridge: """
        public final class C {
            public func add() async -> Int {
                return 1
            }
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            suspend fun add(): Int = Async.run {
                kotlin.coroutines.suspendCoroutine { f_continuation ->
                    Swift_callback_add_0(Swift_peer) { f_return ->
                        f_continuation.resumeWith(kotlin.Result.success(f_return))
                    }
                }
            }
            private external fun Swift_callback_add_0(Swift_peer: skip.bridge.SwiftObjectPointer, f_callback: (Int) -> Unit)

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testStaticConstant() async throws {
        try await check(swiftBridge: """
        public final class C {
            public static let i = 0
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {

                val i = 0
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testStaticVar() async throws {
        try await check(swiftBridge: """
        public final class C {
            public static var i = 0
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {

                var i: Int
                    get() = Swift_Companion_i()
                    set(newValue) {
                        Swift_Companion_i_set(newValue)
                    }
                private external fun Swift_Companion_i(): Int
                private external fun Swift_Companion_i_set(value: Int)
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testStaticFunction() async throws {
        try await check(swiftBridge: """
        public final class C {
            public static func add(a: Int, b: Int) -> Int {
                return a + b
            }
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {

                fun add(a: Int, b: Int): Int = Swift_Companion_add_0(a, b)
                private external fun Swift_Companion_add_0(a: Int, b: Int): Int
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
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
        public final class C {
            @BridgeIgnored
            public var i = 1
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testCommonProtocols() async throws {
        try await check(swiftBridge: """
        public final class C: Equatable, Hashable, Comparable, Sendable {
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
        class C: Comparable<C>, skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Int)
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
            fun hash(into: InOut<Hasher>) {
                val hasher = into
                hasher.value.combine(Swift_hashvalue(Swift_peer))
            }
            private external fun Swift_hashvalue(Swift_peer: skip.bridge.SwiftObjectPointer): Long
            override fun compareTo(other: C): Int {
                if (this == other) return 0
                fun islessthan(lhs: C, rhs: C): Boolean {
                    return Swift_islessthan(lhs, rhs)
                }
                return if (islessthan(this, other)) -1 else 1
            }
            private external fun Swift_islessthan(lhs: C, rhs: C): Boolean

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testCodable() async throws {
        try await check(swiftBridge: """
        public final class C: Codable {
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
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Int)

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testSubclassOfBridged() async throws {
        try await check(swiftBridge: """
        public class Base {
            public var i = 0
        
            public init(i: Int) {
                self.i = i
            }
        }
        public class Sub1: Base {
            public var s = ""
        
            public init(i: Int, s: String) {
                self.s = s
                super.init(i: i)
            }
        }
        public final class Sub2: Base {
        }
        public var base: Base = Sub2(i: 1)
        """, kotlin: """
        open class Base: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            open var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Int)
            constructor(i: Int) {
                Swift_peer = Swift_constructor_0(i)
            }
            private external fun Swift_constructor_0(i: Int): skip.bridge.SwiftObjectPointer

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        open class Sub1: Base {

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?): super(Swift_peer = Swift_peer, marker = marker)

            open var s: String
                get() = Swift_s(Swift_peer)
                set(newValue) {
                    Swift_s_set(Swift_peer, newValue)
                }
            private external fun Swift_s(Swift_peer: skip.bridge.SwiftObjectPointer): String
            private external fun Swift_s_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: String)
            constructor(i: Int, s: String): super(Swift_peer = Swift_Companion_constructor_0(i, s), marker = null) {
            }

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object: CompanionClass() {
                private external fun Swift_Companion_constructor_0(i: Int, s: String): skip.bridge.SwiftObjectPointer
            }
            open class CompanionClass: Base.CompanionClass() {
            }
        }
        class Sub2: Base {

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?): super(Swift_peer = Swift_peer, marker = marker)

            constructor(i: Int): super(Swift_peer = Swift_Companion_constructor_0(i), marker = null) {
            }

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object: Base.CompanionClass() {
                private external fun Swift_Companion_constructor_0(i: Int): skip.bridge.SwiftObjectPointer
            }
        }
        var base: Base
            get() = Swift_base()
            set(newValue) {
                Swift_base_set(newValue)
            }
        private external fun Swift_base(): Base
        private external fun Swift_base_set(value: Base)
        """, swiftBridgeSupport: """
        extension Base: BridgedToKotlin, BridgedToKotlinBaseClass {
            private static let Java_class = try! JClass(name: "Base")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                let constructor = Java_findConstructor(base: Self.Java_class, Self.Java_constructor_methodID)
                return try! constructor.cls.create(ctor: constructor.ctor, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
        }
        extension Sub1: BridgedToKotlinSubclass1 {
            private static let Java_class = try! JClass(name: "Sub1")
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
            public static let Java_subclass1Constructor = (Java_class, Java_constructor_methodID)
        }
        extension Sub2: BridgedToKotlinSubclass1, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "Sub2")
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
            public static let Java_subclass1Constructor = (Java_class, Java_constructor_methodID)
        }
        @_cdecl("Java_Base_Swift_1release")
        func Base_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: Base.self)
        }
        @_cdecl("Java_Base_Swift_1i")
        func Base_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int32 {
            let peer_swift: Base = Swift_peer.pointee()!
            return Int32(peer_swift.i)
        }
        @_cdecl("Java_Base_Swift_1i_1set")
        func Base_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: Int32) {
            let peer_swift: Base = Swift_peer.pointee()!
            peer_swift.i = Int(value)
        }
        @_cdecl("Java_Base_Swift_1constructor_10")
        func Base_Swift_constructor_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32) -> SwiftObjectPointer {
            let p_0_swift = Int(p_0)
            let f_return_swift = Base(i: p_0_swift)
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_Base_Swift_1projectionImpl")
        func Base_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = Base.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        @_cdecl("Java_Sub1_Swift_1s")
        func Sub1_Swift_s(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaString {
            let peer_swift: Sub1 = Swift_peer.pointee()!
            return peer_swift.s.toJavaObject(options: [])!
        }
        @_cdecl("Java_Sub1_Swift_1s_1set")
        func Sub1_Swift_s_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: JavaString) {
            let peer_swift: Sub1 = Swift_peer.pointee()!
            peer_swift.s = String.fromJavaObject(value, options: [])
        }
        @_cdecl("Java_Sub1_00024Companion_Swift_1Companion_1constructor_10")
        func Sub1_Swift_Companion_constructor_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32, _ p_1: JavaString) -> SwiftObjectPointer {
            let p_0_swift = Int(p_0)
            let p_1_swift = String.fromJavaObject(p_1, options: [])
            let f_return_swift = Sub1(i: p_0_swift, s: p_1_swift)
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_Sub1_Swift_1projectionImpl")
        func Sub1_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = Sub1.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        @_cdecl("Java_Sub2_00024Companion_Swift_1Companion_1constructor_10")
        func Sub2_Swift_Companion_constructor_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32) -> SwiftObjectPointer {
            let p_0_swift = Int(p_0)
            let f_return_swift = Sub2(i: p_0_swift)
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_Sub2_Swift_1projectionImpl")
        func Sub2_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = Sub2.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        @_cdecl("Java_BridgeKt_Swift_1base")
        func BridgeKt_Swift_base(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer {
            return base.toJavaObject(options: [])!
        }
        @_cdecl("Java_BridgeKt_Swift_1base_1set")
        func BridgeKt_Swift_base_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer) {
            base = AnyBridging.fromJavaObject(value, toBaseType: Base.self, options: [])!
        }
        """, transformers: transformers)
    }

    func testSubclassOfBridgedNoConstructors() async throws {
        try await check(swiftBridge: """
        public class Base {
        }
        public class Sub: Base {
        }
        """, kotlin: """
        open class Base: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        open class Sub: Base {

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?): super(Swift_peer = Swift_peer, marker = marker)

            constructor(): super(Swift_peer = Swift_constructor(), marker = null)

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object: CompanionClass() {
                private external fun Swift_Companion_constructor(): skip.bridge.SwiftObjectPointer
            }
            open class CompanionClass: Base.CompanionClass() {
            }
        }
        """, swiftBridgeSupport: """
        extension Base: BridgedToKotlin, BridgedToKotlinBaseClass {
            private static let Java_class = try! JClass(name: "Base")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                let constructor = Java_findConstructor(base: Self.Java_class, Self.Java_constructor_methodID)
                return try! constructor.cls.create(ctor: constructor.ctor, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
        }
        extension Sub: BridgedToKotlinSubclass1 {
            private static let Java_class = try! JClass(name: "Sub")
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
            public static let Java_subclass1Constructor = (Java_class, Java_constructor_methodID)
        }
        @_cdecl("Java_Base_Swift_1constructor")
        func Base_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = Base()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_Base_Swift_1release")
        func Base_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: Base.self)
        }
        @_cdecl("Java_Base_Swift_1projectionImpl")
        func Base_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = Base.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        @_cdecl("Java_Sub_00024Companion_Swift_1Companion_1constructor")
        func Sub_Swift_Companion_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = Sub()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_Sub_Swift_1projectionImpl")
        func Sub_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = Sub.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testSubclassOfUnbridged() async throws {
        try await check(swiftBridge: """
        // SKIP @nobridge
        public class Base {
            public var i = 0
        
            public init(i: Int) {
                self.i = i
            }
        }
        public class Sub1: Base {
            public var s = ""
        
            public init(i: Int, s: String) {
                self.s = s
                super.init(i: i)
            }
        }
        public final class Sub2: Base {
        }
        public var sub1 = Sub1()
        """, kotlin: """
        open class Sub1: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            open var s: String
                get() = Swift_s(Swift_peer)
                set(newValue) {
                    Swift_s_set(Swift_peer, newValue)
                }
            private external fun Swift_s(Swift_peer: skip.bridge.SwiftObjectPointer): String
            private external fun Swift_s_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: String)
            constructor(i: Int, s: String) {
                Swift_peer = Swift_constructor_0(i, s)
            }
            private external fun Swift_constructor_0(i: Int, s: String): skip.bridge.SwiftObjectPointer

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        class Sub2: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        var sub1: Sub1
            get() = Swift_sub1()
            set(newValue) {
                Swift_sub1_set(newValue)
            }
        private external fun Swift_sub1(): Sub1
        private external fun Swift_sub1_set(value: Sub1)
        """, swiftBridgeSupport: """
        extension Sub1: BridgedToKotlin, BridgedToKotlinBaseClass {
            private static let Java_class = try! JClass(name: "Sub1")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                let constructor = Java_findConstructor(base: Self.Java_class, Self.Java_constructor_methodID)
                return try! constructor.cls.create(ctor: constructor.ctor, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
        }
        extension Sub2: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "Sub2")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_Sub1_Swift_1release")
        func Sub1_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: Sub1.self)
        }
        @_cdecl("Java_Sub1_Swift_1s")
        func Sub1_Swift_s(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaString {
            let peer_swift: Sub1 = Swift_peer.pointee()!
            return peer_swift.s.toJavaObject(options: [])!
        }
        @_cdecl("Java_Sub1_Swift_1s_1set")
        func Sub1_Swift_s_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: JavaString) {
            let peer_swift: Sub1 = Swift_peer.pointee()!
            peer_swift.s = String.fromJavaObject(value, options: [])
        }
        @_cdecl("Java_Sub1_Swift_1constructor_10")
        func Sub1_Swift_constructor_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32, _ p_1: JavaString) -> SwiftObjectPointer {
            let p_0_swift = Int(p_0)
            let p_1_swift = String.fromJavaObject(p_1, options: [])
            let f_return_swift = Sub1(i: p_0_swift, s: p_1_swift)
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_Sub1_Swift_1projectionImpl")
        func Sub1_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = Sub1.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        @_cdecl("Java_Sub2_Swift_1constructor")
        func Sub2_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = Sub2()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_Sub2_Swift_1release")
        func Sub2_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: Sub2.self)
        }
        @_cdecl("Java_Sub2_Swift_1projectionImpl")
        func Sub2_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = Sub2.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        @_cdecl("Java_BridgeKt_Swift_1sub1")
        func BridgeKt_Swift_sub1(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer {
            return sub1.toJavaObject(options: [])!
        }
        @_cdecl("Java_BridgeKt_Swift_1sub1_1set")
        func BridgeKt_Swift_sub1_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer) {
            sub1 = AnyBridging.fromJavaObject(value, toBaseType: Sub1.self, options: [])!
        }
        """, transformers: transformers)
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
        class S: MutableStruct, skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
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
            private external fun Swift_i(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Int)
            constructor(s: String) {
                Swift_peer = Swift_constructor_0(s)
            }
            private external fun Swift_constructor_0(s: String): skip.bridge.SwiftObjectPointer
            fun f(): Int = Swift_f_1(Swift_peer)
            private external fun Swift_f_1(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private constructor(copy: skip.lib.MutableStruct) {
                Swift_peer = Swift_constructor_2(copy)
            }
            private external fun Swift_constructor_2(copy: skip.lib.MutableStruct): skip.bridge.SwiftObjectPointer

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(this as MutableStruct)

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

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
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_S_Swift_1projectionImpl")
        func S_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = S.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
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
        class S: Comparable<S>, MutableStruct, skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

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
            private external fun Swift_i(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Int)
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
            private external fun Swift_constructor_0(i: Int): skip.bridge.SwiftObjectPointer

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
            private external fun Swift_hashvalue(Swift_peer: skip.bridge.SwiftObjectPointer): Long

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

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
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_S_Swift_1projectionImpl")
        func S_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = S.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testStructDecodableConstructor() async throws {
        try await check(swiftBridge: """
        public struct S: Decodable {
            public var i = 0
            public init(from decoder: Decoder) throws {
            }
        }
        """, kotlin: """
        class S: MutableStruct, skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
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
            private external fun Swift_i(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Int)
            private constructor(copy: skip.lib.MutableStruct) {
                Swift_peer = Swift_constructor_0(copy)
            }
            private external fun Swift_constructor_0(copy: skip.lib.MutableStruct): skip.bridge.SwiftObjectPointer

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(this as MutableStruct)

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

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
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        func S_Swift_constructor_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaObjectPointer) -> SwiftObjectPointer {
            let p_0_swift = S.fromJavaObject(p_0, options: [])
            let f_return_swift = SwiftValueTypeBox(p_0_swift)
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_S_Swift_1projectionImpl")
        func S_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = S.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testStructConstructorInternalProperties() async throws {
        try await check(swiftBridge: """
        public struct S {
            public var i: Int
            let s: String
        }
        """, kotlin: """
        class S: MutableStruct, skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
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
            private external fun Swift_i(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Int)
            private constructor(copy: skip.lib.MutableStruct) {
                Swift_peer = Swift_constructor_0(copy)
            }
            private external fun Swift_constructor_0(copy: skip.lib.MutableStruct): skip.bridge.SwiftObjectPointer

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(this as MutableStruct)

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

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
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        func S_Swift_constructor_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaObjectPointer) -> SwiftObjectPointer {
            let p_0_swift = S.fromJavaObject(p_0, options: [])
            let f_return_swift = SwiftValueTypeBox(p_0_swift)
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_S_Swift_1projectionImpl")
        func S_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = S.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
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
        public final class C: P {
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
        class C: P, skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun a(): Unit = Swift_a_0(Swift_peer)
            private external fun Swift_a_0(Swift_peer: skip.bridge.SwiftObjectPointer)
            override fun f(): Unit = Swift_f_1(Swift_peer)
            private external fun Swift_f_1(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
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
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testProtocolTypeMembers() async throws {
        try await check(swiftBridge: """
        public protocol P {
        }
        public final class C {
            public var p: (any P)?
            public func f(p: any P) -> (any P)? {
                return nil
            }
        }
        """, kotlin: """
        interface P {
        }
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            var p: P?
                get() = Swift_p(Swift_peer).sref({ this.p = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    Swift_p_set(Swift_peer, newValue)
                }
            private external fun Swift_p(Swift_peer: skip.bridge.SwiftObjectPointer): P?
            private external fun Swift_p_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: P?)
            fun f(p: P): P? = Swift_f_0(Swift_peer, p)
            private external fun Swift_f_0(Swift_peer: skip.bridge.SwiftObjectPointer, p: P): P?

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
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
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
            return AnyBridging.toJavaObject(peer_swift.p, options: [])
        }
        @_cdecl("Java_C_Swift_1p_1set")
        func C_Swift_p_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: JavaObjectPointer?) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.p = AnyBridging.fromJavaObject(value, options: []) { P_BridgeImpl?.fromJavaObject(value, options: []) as Any } as! (any P)?
        }
        @_cdecl("Java_C_Swift_1f_10")
        func C_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ p_0: JavaObjectPointer) -> JavaObjectPointer? {
            let p_0_swift = AnyBridging.fromJavaObject(p_0, options: []) { P_BridgeImpl.fromJavaObject(p_0, options: []) as Any } as! (any P)
            let peer_swift: C = Swift_peer.pointee()!
            let f_return_swift = peer_swift.f(p: p_0_swift)
            return AnyBridging.toJavaObject(f_return_swift, options: [])
        }
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
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

    func testProtocolExtension() async throws {
        try await check(swiftBridge: """
        public protocol P {
            var i: Int { get set }
            func a(i: Int) -> Int
        }
        extension P {
            public var i: Int {
                get { 0 }
                set { }
            }
            public func a(i: Int) -> Int {
                return 0
            }
            public func b() {
            }
        }
        """, kotlin: """
        interface P {
            var i: Int
                get() = Swift_P_i(this)
                set(newValue) {
                    Swift_P_i_set(this, newValue)
                }
            fun a(i: Int): Int = Swift_P_a_0(this, i)
            fun b(): Unit = Swift_P_b_1(this)
        }
        private external fun Swift_P_b_1(Java_iface: P)
        private external fun Swift_P_a_0(Java_iface: P, i: Int): Int
        private external fun Swift_P_i(Java_iface: P): Int
        private external fun Swift_P_i_set(Java_iface: P, value: Int)
        """, swiftBridgeSupport: """
        public final class P_BridgeImpl: P, BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "P")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public var i: Int {
                get {
                    return jniContext {
                        let value_java: Int32 = try! Java_peer.call(method: Self.Java_get_i_methodID, options: [], args: [])
                        return Int(value_java)
                    }
                }
                set {
                    jniContext {
                        let value_java = Int32(newValue).toJavaParameter(options: [])
                        try! Java_peer.call(method: Self.Java_set_i_methodID, options: [], args: [value_java])
                    }
                }
            }
            private static let Java_get_i_methodID = Java_class.getMethodID(name: "getI", sig: "()I")!
            private static let Java_set_i_methodID = Java_class.getMethodID(name: "setI", sig: "(I)V")!
            public func a(i p_0: Int) -> Int {
                return jniContext {
                    let p_0_java = Int32(p_0).toJavaParameter(options: [])
                    let f_return_java: Int32 = try! Java_peer.call(method: Self.Java_a_0_methodID, options: [], args: [p_0_java])
                    return Int(f_return_java)
                }
            }
            private static let Java_a_0_methodID = Java_class.getMethodID(name: "a", sig: "(I)I")!
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        @_cdecl("Java_BridgeKt_Swift_1P_1i")
        func BridgeKt_Swift_P_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Java_iface: JavaObjectPointer) -> Int32 {
            let peer_swift = AnyBridging.fromJavaObject(Java_iface, options: []) as! any P
            return Int32(peer_swift.i)
        }
        @_cdecl("Java_BridgeKt_Swift_1P_1i_1set")
        func BridgeKt_Swift_P_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Java_iface: JavaObjectPointer, _ value: Int32) {
            let peer_swift = AnyBridging.fromJavaObject(Java_iface, options: []) as! any P
            peer_swift.i = Int(value)
        }
        @_cdecl("Java_BridgeKt_Swift_1P_1a_10")
        func BridgeKt_Swift_P_a_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Java_iface: JavaObjectPointer, _ p_0: Int32) -> Int32 {
            let p_0_swift = Int(p_0)
            let peer_swift = AnyBridging.fromJavaObject(Java_iface, options: []) as! any P
            let f_return_swift = peer_swift.a(i: p_0_swift)
            return Int32(f_return_swift)
        }
        @_cdecl("Java_BridgeKt_Swift_1P_1b_11")
        func BridgeKt_Swift_P_b_1(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Java_iface: JavaObjectPointer) {
            let peer_swift = AnyBridging.fromJavaObject(Java_iface, options: []) as! any P
            peer_swift.b()
        }
        """, transformers: transformers)
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
        enum class E(override val rawValue: Int, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): skip.lib.SwiftProjecting {

            a(100),
            b(101);
            val string: String
                get() = Swift_string(name)
            private external fun Swift_string(name: String): String
            fun negate(): Int = Swift_negate_0(name)
            private external fun Swift_negate_0(name: String): Int

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
                fun init(rawValue: Int): E? {
                    return when (rawValue) {
                        100 -> E.a
                        101 -> E.b
                        else -> null
                    }
                }
                fun init(string: String): E = Swift_Companion_init_1(string)
                private external fun Swift_Companion_init_1(string: String): E
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
        @_cdecl("Java_E_00024Companion_Swift_1Companion_1init_11")
        func E_Swift_Companion_init_1(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaString) -> JavaObjectPointer {
            let p_0_swift = String.fromJavaObject(p_0, options: [])
            let f_return_swift = E.init(string: p_0_swift)
            return f_return_swift.toJavaObject(options: [])!
        }
        @_cdecl("Java_E_Swift_1projectionImpl")
        func E_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = E.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testNamespaceEnum() async throws {
        // Empty enums sometimes used as namespaces
        try await check(swiftBridge: """
        public enum E {
            public struct S {
            }
        }
        """, kotlin: """
        enum class E {
            ;
            class S: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
                var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

                constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                    this.Swift_peer = Swift_peer
                }

                fun finalize() {
                    Swift_release(Swift_peer)
                    Swift_peer = skip.bridge.SwiftObjectNil
                }
                private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

                constructor() {
                    Swift_peer = Swift_constructor()
                }
                private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

                override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

                override fun equals(other: Any?): Boolean {
                    if (other !is skip.bridge.SwiftPeerBridged) return false
                    return Swift_peer == other.Swift_peer()
                }

                override fun hashCode(): Int = Swift_peer.hashCode()

                override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
                private external fun Swift_projectionImpl(options: Int): () -> Any

                companion object {
                }
            }

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension E {
        }
        extension E.S: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "E$S")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                let box: SwiftValueTypeBox<Self> = ptr.pointee()!
                return box.value
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let box = SwiftValueTypeBox(self)
                let Swift_peer = SwiftObjectPointer.pointer(to: box, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_E_00024S_Swift_1constructor")
        func E$S_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = SwiftValueTypeBox(E.S())
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_E_00024S_Swift_1release")
        func E$S_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: SwiftValueTypeBox<E.S>.self)
        }
        @_cdecl("Java_E_00024S_Swift_1projectionImpl")
        func E$S_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = E.S.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testEnumWithAssociatedValue() async throws {
        try await check(swiftBridge: """
        public enum E {
            case a(i: Int, String), b
            public var intValue: Int? {
                switch self {
                case .a(let value):
                    return value
                case .b:
                    return nil
            }
        }
        """, kotlin: """
        sealed class E: skip.lib.SwiftProjecting {

            class ACase(val associated0: Int, val associated1: String): E() {
                val i = associated0
            }
            class BCase: E() {
            }
            val intValue: Int?
                get() = Swift_intValue(javaClass.name)
            private external fun Swift_intValue(className: String): Int?

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
                fun a(i: Int, associated1: String): E = ACase(i, associated1)
                val b: E = BCase()
            }
        }
        """, swiftBridgeSupport: """
        extension E: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "E")
            private static let Java_Companion_class = try! JClass(name: "E$Companion")
            private static let Java_Companion = JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: "Companion", sig: "LE$Companion;")!, options: []))
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let className = Java_className(of: obj!, options: options)
                return fromJavaClassName(className, obj!, options: options)
            }
            fileprivate static func fromJavaClassName(_ className: String, _ obj: JavaObjectPointer, options: JConvertibleOptions) -> Self {
                switch className {
                case "E$ACase":
                    let associated0_java: Int32 = try! obj.call(method: Self.Java_a_associated0_methodID, options: options, args: [])
                    let associated0 = Int(associated0_java)
                    let associated1_java: String = try! obj.call(method: Self.Java_a_associated1_methodID, options: options, args: [])
                    let associated1 = associated1_java
                    return .a(i: associated0, associated1)
                case "E$BCase":
                    return .b
                default: fatalError()
                }
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                switch self {
                case .a(let associated0, let associated1):
                    let associated0_java = Int32(associated0).toJavaParameter(options: options)
                    let associated1_java = associated1.toJavaParameter(options: options)
                    return try! Self.Java_Companion.call(method: Self.Java_Companion_a_methodID, options: options, args: [associated0_java, associated1_java])
                case .b:
                    return try! Self.Java_Companion.call(method: Self.Java_Companion_b_methodID, options: options, args: [])
                }
            }
            private static let Java_a_class = try! JClass(name: "E$ACase")
            private static let Java_a_associated0_methodID = Java_a_class.getMethodID(name: "getAssociated0", sig: "()I")!
            private static let Java_a_associated1_methodID = Java_a_class.getMethodID(name: "getAssociated1", sig: "()Ljava/lang/String;")!
            private static let Java_Companion_a_methodID = Java_Companion_class.getMethodID(name: "a", sig: "(ILjava/lang/String;)LE;")!
            private static let Java_Companion_b_methodID = Java_Companion_class.getMethodID(name: "getB", sig: "()LE;")!
        }
        @_cdecl("Java_E_Swift_1intValue")
        func E_Swift_intValue(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ className: JavaString) -> JavaObjectPointer? {
            let className_swift = String.fromJavaObject(className, options: [])
            let peer_swift = E.fromJavaClassName(className_swift, Java_target, options: [])
            return peer_swift.intValue.toJavaObject(options: [])
        }
        @_cdecl("Java_E_Swift_1projectionImpl")
        func E_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = E.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testClassWithExtension() async throws {
        try await check(swiftBridge: """
        public final class C {
        }
        extension C {
            public static func s() {
            }
            public func f() {
            }
            func g() {
            }
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()
            open fun f(): Unit = Swift_f_1(Swift_peer)
            private external fun Swift_f_1(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {

                fun s(): Unit = Swift_Companion_s_0()
                private external fun Swift_Companion_s_0()
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_00024Companion_Swift_1Companion_1s_10")
        func C_Swift_Companion_s_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) {
            C.s()
        }
        @_cdecl("Java_C_Swift_1f_11")
        func C_Swift_f_1(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.f()
        }
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testClassWithPublicExtension() async throws {
        try await check(swiftBridge: """
        public final class C {
        }
        public extension C {
            func f() {
            }
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            open fun f(): Unit = Swift_f_0(Swift_peer)
            private external fun Swift_f_0(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1f_10")
        func C_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.f()
        }
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testClassWithUnbridgedExtension() async throws {
        try await check(swiftBridge: """
        public final class C {
        }
        // SKIP @nobridge
        extension C {
            public func f() {
            }
            func g() {
            }
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testExtensionFunction() async throws {
        try await checkProducesMessage(swift: """
        extension Int {
            public var zero: Int {
                return 0
            }
        }
        """, isSwiftBridge: true, transformers: transformers)

        try await check(swiftBridge: """
        extension Int {
            // SKIP @nobridge
            public var zero: Int {
                return 0
            }
        }
        """, kotlin: """
        """, swiftBridgeSupport: """
        """, transformers: transformers)
    }

    func testObservable() async throws {
        try await check(swiftBridge: """
        import SkipFuse
        @Observable
        public final class C {
            public var i = 1
        }
        """, kotlin: """
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Int)

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        import SkipFuse
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)

        KotlinBridgeTransformer.testSkipAndroidBridge = true
        defer { KotlinBridgeTransformer.testSkipAndroidBridge = false }
        
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
        public final class C {
            public var urls: [URL] = []
            public var map = ["a": [1]]
            public var set: Set<Int> = [1, 2, 3]
            public func perform(action: (URL) -> Int) {
            }
        }
        """, kotlins: ["""
        import skip.lib.Array
        import skip.lib.Set

        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            var urls: kotlin.collections.List<java.net.URI>
                get() = Swift_urls(Swift_peer)
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    Swift_urls_set(Swift_peer, newValue)
                }
            private external fun Swift_urls(Swift_peer: skip.bridge.SwiftObjectPointer): kotlin.collections.List<java.net.URI>
            private external fun Swift_urls_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: kotlin.collections.List<java.net.URI>)
            var map: kotlin.collections.Map<String, kotlin.collections.List<Int>>
                get() = Swift_map(Swift_peer)
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    Swift_map_set(Swift_peer, newValue)
                }
            private external fun Swift_map(Swift_peer: skip.bridge.SwiftObjectPointer): kotlin.collections.Map<String, kotlin.collections.List<Int>>
            private external fun Swift_map_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: kotlin.collections.Map<String, kotlin.collections.List<Int>>)
            var set: kotlin.collections.Set<Int>
                get() = Swift_set(Swift_peer)
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    Swift_set_set(Swift_peer, newValue)
                }
            private external fun Swift_set(Swift_peer: skip.bridge.SwiftObjectPointer): kotlin.collections.Set<Int>
            private external fun Swift_set_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: kotlin.collections.Set<Int>)
            fun perform(action: (java.net.URI) -> Int): Unit = Swift_perform_0(Swift_peer, action)
            private external fun Swift_perform_0(Swift_peer: skip.bridge.SwiftObjectPointer, action: (java.net.URI) -> Int)

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, """
        internal open class URL: SwiftCustomBridged, KotlinConverting<java.net.URI> {
        }
        """], swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1set")
        func C_Swift_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer {
            let peer_swift: C = Swift_peer.pointee()!
            return peer_swift.set.toJavaObject(options: [.kotlincompat])!
        }
        @_cdecl("Java_C_Swift_1set_1set")
        func C_Swift_set_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: JavaObjectPointer) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.set = Set<Int>.fromJavaObject(value, options: [.kotlincompat])
        }
        @_cdecl("Java_C_Swift_1perform_10")
        func C_Swift_perform_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ p_0: JavaObjectPointer) {
            let p_0_swift = SwiftClosure1.closure(forJavaObject: p_0, options: [.kotlincompat])! as (URL) -> Int
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.perform(action: p_0_swift)
        }
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [.kotlincompat])!
        }
        """, transformers: transformers)
    }

    func testTupleKotlinCompatibilityOption() async throws {
        let transformers = builtinKotlinTransformers() + [KotlinBridgeTransformer(options: .kotlincompat)]
        try await check(supportingSwift: """
        class URL: SwiftCustomBridged, KotlinConverting<java.net.URI> {
        }
        """, swiftBridge: """
        public final class C {
            public var t2: (URL, Int)
            public var t3: (String, Int, Bool)
            public func f() -> (String, Int, Bool, Double) {
            }
        }
        """, kotlins: ["""
        class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            var t2: kotlin.Pair<java.net.URI, Int>
                get() = Swift_t2(Swift_peer)
                set(newValue) {
                    Swift_t2_set(Swift_peer, newValue)
                }
            private external fun Swift_t2(Swift_peer: skip.bridge.SwiftObjectPointer): kotlin.Pair<java.net.URI, Int>
            private external fun Swift_t2_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: kotlin.Pair<java.net.URI, Int>)
            var t3: kotlin.Triple<String, Int, Boolean>
                get() = Swift_t3(Swift_peer)
                set(newValue) {
                    Swift_t3_set(Swift_peer, newValue)
                }
            private external fun Swift_t3(Swift_peer: skip.bridge.SwiftObjectPointer): kotlin.Triple<String, Int, Boolean>
            private external fun Swift_t3_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: kotlin.Triple<String, Int, Boolean>)
            fun f(): Tuple4<String, Int, Boolean, Double> = Swift_f_0(Swift_peer)
            private external fun Swift_f_0(Swift_peer: skip.bridge.SwiftObjectPointer): Tuple4<String, Int, Boolean, Double>

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, """
        internal open class URL: SwiftCustomBridged, KotlinConverting<java.net.URI> {
        }
        """], swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1t2")
        func C_Swift_t2(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer {
            let peer_swift: C = Swift_peer.pointee()!
            return SwiftTuple.javaObject(for: peer_swift.t2, options: [.kotlincompat])!
        }
        @_cdecl("Java_C_Swift_1t2_1set")
        func C_Swift_t2_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: JavaObjectPointer) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.t2 = SwiftTuple.tuple(forJavaObject: value, options: [.kotlincompat])! as (URL, Int)
        }
        @_cdecl("Java_C_Swift_1t3")
        func C_Swift_t3(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer {
            let peer_swift: C = Swift_peer.pointee()!
            return SwiftTuple.javaObject(for: peer_swift.t3, options: [.kotlincompat])!
        }
        @_cdecl("Java_C_Swift_1t3_1set")
        func C_Swift_t3_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: JavaObjectPointer) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.t3 = SwiftTuple.tuple(forJavaObject: value, options: [.kotlincompat])! as (String, Int, Bool)
        }
        @_cdecl("Java_C_Swift_1f_10")
        func C_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer {
            let peer_swift: C = Swift_peer.pointee()!
            let f_return_swift = peer_swift.f()
            return SwiftTuple.javaObject(for: f_return_swift, options: [.kotlincompat])!
        }
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [.kotlincompat])!
        }
        """, transformers: transformers)
    }

    func testActor() async throws {
        try await check(swiftBridge: """
        public actor A {
            public var x: Int {
                return 0
            }
            public nonisolated var y = 1
            public func f(i: Int) -> String {
                return ""
            }
            public nonisolated func g() -> Int {
                return 0
            }
        }
        """, kotlin: """
        class A: Actor, skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            override val isolatedContext = Actor.isolatedContext()
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            suspend fun x(): Int = Actor.run(this) {
                kotlin.coroutines.suspendCoroutine { f_continuation ->
                    Swift_callback_x(Swift_peer) { f_return ->
                        f_continuation.resumeWith(kotlin.Result.success(f_return))
                    }
                }
            }
            private external fun Swift_callback_x(Swift_peer: skip.bridge.SwiftObjectPointer, f_callback: (Int) -> Unit)
            var y: Int
                get() = Swift_y(Swift_peer)
                set(newValue) {
                    Swift_y_set(Swift_peer, newValue)
                }
            private external fun Swift_y(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private external fun Swift_y_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Int)
            suspend fun f(i: Int): String = Actor.run(this) {
                kotlin.coroutines.suspendCoroutine { f_continuation ->
                    Swift_callback_f_0(Swift_peer, i) { f_return ->
                        f_continuation.resumeWith(kotlin.Result.success(f_return))
                    }
                }
            }
            private external fun Swift_callback_f_0(Swift_peer: skip.bridge.SwiftObjectPointer, i: Int, f_callback: (String) -> Unit)
            fun g(): Int = Swift_g_1(Swift_peer)
            private external fun Swift_g_1(Swift_peer: skip.bridge.SwiftObjectPointer): Int

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension A: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "A")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public nonisolated func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_A_Swift_1constructor")
        func A_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = A()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_A_Swift_1release")
        func A_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: A.self)
        }
        @_cdecl("Java_A_Swift_1callback_1x")
        func A_Swift_callback_x(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ f_callback: JavaObjectPointer) {
            let f_callback_swift = SwiftClosure1.closure(forJavaObject: f_callback, options: [])! as (Int) -> Void
            let peer_swift: A = Swift_peer.pointee()!
            Task {
                let f_return_swift = await peer_swift.x
                f_callback_swift(f_return_swift)
            }
        }
        @_cdecl("Java_A_Swift_1y")
        func A_Swift_y(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int32 {
            let peer_swift: A = Swift_peer.pointee()!
            return Int32(peer_swift.y)
        }
        @_cdecl("Java_A_Swift_1y_1set")
        func A_Swift_y_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: Int32) {
            let peer_swift: A = Swift_peer.pointee()!
            peer_swift.y = Int(value)
        }
        @_cdecl("Java_A_Swift_1callback_1f_10")
        func A_Swift_callback_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ p_0: Int32, _ f_callback: JavaObjectPointer) {
            let p_0_swift = Int(p_0)
            let f_callback_swift = SwiftClosure1.closure(forJavaObject: f_callback, options: [])! as (String) -> Void
            let peer_swift: A = Swift_peer.pointee()!
            Task {
                let f_return_swift = await peer_swift.f(i: p_0_swift)
                f_callback_swift(f_return_swift)
            }
        }
        @_cdecl("Java_A_Swift_1g_11")
        func A_Swift_g_1(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int32 {
            let peer_swift: A = Swift_peer.pointee()!
            let f_return_swift = peer_swift.g()
            return Int32(f_return_swift)
        }
        @_cdecl("Java_A_Swift_1projectionImpl")
        func A_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = A.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testTypealias() async throws {
        try await check(swiftBridge: """
        public typealias IntArray = [Int]
        """, kotlin: """
        import skip.lib.Array

        typealias IntArray = Array<Int>
        """, swiftBridgeSupport: """
        """, transformers: transformers)
    }

    func testErrorType() async throws {
        try await check(swiftBridge: """
        public struct CustomError: Error {
            private let description: String
        
            public init(description: String) {
                self.description = description
            }
        }
        """, kotlin: """
        class CustomError: Exception, Error, skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?): super() {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            constructor(description: String): super() {
                Swift_peer = Swift_constructor_0(description)
            }
            private external fun Swift_constructor_0(description: String): skip.bridge.SwiftObjectPointer

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension CustomError: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "CustomError")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                let box: SwiftValueTypeBox<Self> = ptr.pointee()!
                return box.value
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let box = SwiftValueTypeBox(self)
                let Swift_peer = SwiftObjectPointer.pointer(to: box, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_CustomError_Swift_1release")
        func CustomError_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: SwiftValueTypeBox<CustomError>.self)
        }
        @_cdecl("Java_CustomError_Swift_1constructor_10")
        func CustomError_Swift_constructor_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaString) -> SwiftObjectPointer {
            let p_0_swift = String.fromJavaObject(p_0, options: [])
            let f_return_swift = SwiftValueTypeBox(CustomError(description: p_0_swift))
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_CustomError_Swift_1projectionImpl")
        func CustomError_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = CustomError.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testEnumErrorType() async throws {
        try await check(swiftBridge: """
        public enum E: Error {
            case case1
            case case2
        }
        """, kotlin: """
        sealed class E: Exception(), Error, skip.lib.SwiftProjecting {

            class Case1Case: E() {
                override fun equals(other: Any?): Boolean = other is Case1Case
                override fun hashCode(): Int = "Case1Case".hashCode()
            }
            class Case2Case: E() {
                override fun equals(other: Any?): Boolean = other is Case2Case
                override fun hashCode(): Int = "Case2Case".hashCode()
            }

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
                val case1: E
                    get() = Case1Case()
                val case2: E
                    get() = Case2Case()
            }
        }
        """, swiftBridgeSupport: """
        extension E: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "E")
            private static let Java_Companion_class = try! JClass(name: "E$Companion")
            private static let Java_Companion = JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: "Companion", sig: "LE$Companion;")!, options: []))
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let className = Java_className(of: obj!, options: options)
                return fromJavaClassName(className, obj!, options: options)
            }
            fileprivate static func fromJavaClassName(_ className: String, _ obj: JavaObjectPointer, options: JConvertibleOptions) -> Self {
                switch className {
                case "E$Case1Case":
                    return .case1
                case "E$Case2Case":
                    return .case2
                default: fatalError()
                }
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                switch self {
                case .case1:
                    return try! Self.Java_Companion.call(method: Self.Java_Companion_case1_methodID, options: options, args: [])
                case .case2:
                    return try! Self.Java_Companion.call(method: Self.Java_Companion_case2_methodID, options: options, args: [])
                }
            }
            private static let Java_Companion_case1_methodID = Java_Companion_class.getMethodID(name: "getCase1", sig: "()LE;")!
            private static let Java_Companion_case2_methodID = Java_Companion_class.getMethodID(name: "getCase2", sig: "()LE;")!
        }
        @_cdecl("Java_E_Swift_1projectionImpl")
        func E_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = E.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testGenericClass() async throws {
        try await check(swiftBridge: """
        public class C<T> {
            public var value: T
            public var optionalValue: T?
            @MainActor public var mainActorValue: T
        
            // SKIP @nobridge
            public init(value: T) {
            }
        
            public func identity(p: T, o: T? = nil, _ i: Int) -> T {
                return p
            }
        
            @MainActor public func mainActorIdentity(p: T) -> T {
                return p
            }
        }
        """, kotlin: """
        open class C<T>: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_isequal(Swift_peer, other.Swift_peer())
            }
            private external fun Swift_isequal(lhs: skip.bridge.SwiftObjectPointer, rhs: skip.bridge.SwiftObjectPointer): Boolean

            override fun hashCode(): Int = Swift_hashvalue(Swift_peer).hashCode()
            private external fun Swift_hashvalue(Swift_peer: skip.bridge.SwiftObjectPointer): Long

            open var value: T
                get() = (Swift_value(Swift_peer) as T).sref({ this.value = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    Swift_value_set(Swift_peer, newValue as Any)
                }
            private external fun Swift_value(Swift_peer: skip.bridge.SwiftObjectPointer): Any
            private external fun Swift_value_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Any)
            open var optionalValue: T?
                get() = (Swift_optionalValue(Swift_peer) as T?).sref({ this.optionalValue = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    Swift_optionalValue_set(Swift_peer, newValue as Any?)
                }
            private external fun Swift_optionalValue(Swift_peer: skip.bridge.SwiftObjectPointer): Any?
            private external fun Swift_optionalValue_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Any?)
            open var mainActorValue: T
                get() = (Swift_mainActorValue(Swift_peer) as T).sref({ this.mainActorValue = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    Swift_mainActorValue_set(Swift_peer, newValue as Any)
                }
            private external fun Swift_mainActorValue(Swift_peer: skip.bridge.SwiftObjectPointer): Any
            private external fun Swift_mainActorValue_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Any)
            open fun identity(p: T, o: T? = null, i: Int): T = Swift_identity_0(Swift_peer, p as Any, o as Any?, i) as T
            private external fun Swift_identity_0(Swift_peer: skip.bridge.SwiftObjectPointer, p: Any, o: Any?, i: Int): Any
            open fun mainActorIdentity(p: T): T = Swift_mainActorIdentity_1(Swift_peer, p as Any) as T
            private external fun Swift_mainActorIdentity_1(Swift_peer: skip.bridge.SwiftObjectPointer, p: Any): Any

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedToKotlinBaseClass, BridgedFinalClass {
            private static var Java_class: JClass { try! JClass(name: "C") }
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                let typeErased: C_TypeErased = ptr.pointee()!
                return typeErased.genericvalue as! Self
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let typeErased = toTypeErased()
                let Swift_peer = SwiftObjectPointer.pointer(to: typeErased, retain: true)
                let constructor = Java_findConstructor(base: Self.Java_class, Self.Java_constructor_methodID)
                return try! constructor.cls.create(ctor: constructor.ctor, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static var Java_constructor_methodID: JavaMethodID { Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")! }
        }
        extension C: TypeErasedConvertible {
            public func toTypeErased() -> AnyObject {
                let typeErased = C_TypeErased(self)
                typeErased.get_value = { [unowned typeErased] in (typeErased.genericvalue as! Self).value }
                typeErased.set_value = { [unowned typeErased] in (typeErased.genericvalue as! Self).value = $0 as! T }
                typeErased.get_optionalValue = { [unowned typeErased] in (typeErased.genericvalue as! Self).optionalValue }
                typeErased.set_optionalValue = { [unowned typeErased] in (typeErased.genericvalue as! Self).optionalValue = $0 as! T? }
                typeErased.get_mainActorValue = { [unowned typeErased] in (typeErased.genericvalue as! Self).mainActorValue }
                typeErased.set_mainActorValue = { [unowned typeErased] in (typeErased.genericvalue as! Self).mainActorValue = $0 as! T }
                typeErased.identity_0 = { [unowned typeErased] in (typeErased.genericvalue as! Self).identity(p: $0 as! T, o: $1 as! T?, $2) }
                typeErased.mainActorIdentity_1 = { [unowned typeErased] in (typeErased.genericvalue as! Self).mainActorIdentity(p: $0 as! T) }
                return typeErased
            }
        }
        private final class C_TypeErased {
            let genericvalue: Any
            let genericptr: SwiftObjectPointer
            init(_ value: AnyObject) {
                self.genericvalue = value
                self.genericptr = SwiftObjectPointer.pointer(to: value, retain: false)
            }
            var get_value: (() -> Any)!
            var set_value: ((Any) -> Void)!
            var get_optionalValue: (() -> Any?)!
            var set_optionalValue: ((Any?) -> Void)!
            var get_mainActorValue: (@MainActor () -> Any)!
            var set_mainActorValue: (@MainActor (Any) -> Void)!
            var identity_0: ((Any, Any?, Int) -> Any)!
            var mainActorIdentity_1: (@MainActor (Any) -> Any)!
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C_TypeErased.self)
        }
        @_cdecl("Java_C_Swift_1value")
        func C_Swift_value(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer {
            let peer_swift: C_TypeErased = Swift_peer.pointee()!
            return AnyBridging.toJavaObject(peer_swift.get_value(), options: [])!
        }
        @_cdecl("Java_C_Swift_1value_1set")
        func C_Swift_value_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: JavaObjectPointer) {
            let peer_swift: C_TypeErased = Swift_peer.pointee()!
            peer_swift.set_value(AnyBridging.fromJavaObject(value, options: [])!)
        }
        @_cdecl("Java_C_Swift_1optionalValue")
        func C_Swift_optionalValue(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer? {
            let peer_swift: C_TypeErased = Swift_peer.pointee()!
            return AnyBridging.toJavaObject(peer_swift.get_optionalValue(), options: [])
        }
        @_cdecl("Java_C_Swift_1optionalValue_1set")
        func C_Swift_optionalValue_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: JavaObjectPointer?) {
            let peer_swift: C_TypeErased = Swift_peer.pointee()!
            peer_swift.set_optionalValue(AnyBridging.fromJavaObject(value, options: []))
        }
        @_cdecl("Java_C_Swift_1mainActorValue")
        func C_Swift_mainActorValue(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer {
            let peer_swift: C_TypeErased = Swift_peer.pointee()!
            return SkipBridge.assumeMainActorUnchecked {
                return AnyBridging.toJavaObject(peer_swift.get_mainActorValue(), options: [])!
            }
        }
        @_cdecl("Java_C_Swift_1mainActorValue_1set")
        func C_Swift_mainActorValue_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: JavaObjectPointer) {
            let peer_swift: C_TypeErased = Swift_peer.pointee()!
            SkipBridge.assumeMainActorUnchecked {
                peer_swift.set_mainActorValue(AnyBridging.fromJavaObject(value, options: [])!)
            }
        }
        @_cdecl("Java_C_Swift_1identity_10")
        func C_Swift_identity_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ p_0: JavaObjectPointer, _ p_1: JavaObjectPointer?, _ p_2: Int32) -> JavaObjectPointer {
            let p_0_swift = AnyBridging.fromJavaObject(p_0, options: [])!
            let p_1_swift = AnyBridging.fromJavaObject(p_1, options: [])
            let p_2_swift = Int(p_2)
            let peer_swift: C_TypeErased = Swift_peer.pointee()!
            let f_return_swift = peer_swift.identity_0(p_0_swift, p_1_swift, p_2_swift)
            return AnyBridging.toJavaObject(f_return_swift, options: [])!
        }
        @_cdecl("Java_C_Swift_1mainActorIdentity_11")
        func C_Swift_mainActorIdentity_1(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ p_0: JavaObjectPointer) -> JavaObjectPointer {
            let p_0_swift = AnyBridging.fromJavaObject(p_0, options: [])!
            let peer_swift: C_TypeErased = Swift_peer.pointee()!
            return SkipBridge.assumeMainActorUnchecked {
                let f_return_swift = peer_swift.mainActorIdentity_1(p_0_swift)
                return AnyBridging.toJavaObject(f_return_swift, options: [])!
            }
        }
        @_cdecl("Java_C_Swift_1isequal")
        func C_Swift_isequal(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ lhs: SwiftObjectPointer, _ rhs: SwiftObjectPointer) -> Bool {
            let lhs_swift: C_TypeErased = lhs.pointee()!
            let rhs_swift: C_TypeErased = rhs.pointee()!
            return lhs_swift.genericptr == rhs_swift.genericptr
        }
        @_cdecl("Java_C_Swift_1hashvalue")
        func C_Swift_hashvalue(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int64 {
            let peer_swift: C_TypeErased = Swift_peer.pointee()!
            return Int64(peer_swift.genericptr.hashValue)
        }
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let ptr = SwiftObjectPointer.peer(of: Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let peer_swift: C_TypeErased = ptr.pointee()!
            let projection = peer_swift.genericvalue
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testGenericStruct() async throws {
        try await check(swiftBridge: """
        public struct S<T> {
            public var value: T
        
            // SKIP @nobridge
            public init(value: T) {
            }
        
            public func identity(p: T, o: T? = nil, _ i: Int) -> T {
                return p
            }
            public mutating func mutatingVoid() {
            }
            public mutating func mutatingRet(p: T) -> Int {
                return 0
            }
        }
        """, kotlin: """
        class S<T>: MutableStruct, skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            var value: T
                get() = (Swift_value(Swift_peer) as T).sref({ this.value = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    willmutate()
                    try {
                        Swift_value_set(Swift_peer, newValue as Any)
                    } finally {
                        didmutate()
                    }
                }
            private external fun Swift_value(Swift_peer: skip.bridge.SwiftObjectPointer): Any
            private external fun Swift_value_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Any)
            fun identity(p: T, o: T? = null, i: Int): T = Swift_identity_0(Swift_peer, p as Any, o as Any?, i) as T
            private external fun Swift_identity_0(Swift_peer: skip.bridge.SwiftObjectPointer, p: Any, o: Any?, i: Int): Any
            fun mutatingVoid() {
                willmutate()
                try {
                    Swift_mutatingVoid_1(Swift_peer)
                } finally {
                    didmutate()
                }
            }
            private external fun Swift_mutatingVoid_1(Swift_peer: skip.bridge.SwiftObjectPointer)
            fun mutatingRet(p: T): Int {
                willmutate()
                try {
                    return Swift_mutatingRet_2(Swift_peer, p as Any)
                } finally {
                    didmutate()
                }
            }
            private external fun Swift_mutatingRet_2(Swift_peer: skip.bridge.SwiftObjectPointer, p: Any): Int
            private constructor(copy: skip.lib.MutableStruct) {
                Swift_peer = Swift_constructor_3(copy)
            }
            private external fun Swift_constructor_3(copy: skip.lib.MutableStruct): skip.bridge.SwiftObjectPointer

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S<T>(this as MutableStruct)

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        extension S: BridgedToKotlin {
            private static var Java_class: JClass { try! JClass(name: "S") }
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                let typeErased: S_TypeErased = ptr.pointee()!
                return typeErased.genericvalue as! Self
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let typeErased = toTypeErased()
                let Swift_peer = SwiftObjectPointer.pointer(to: typeErased, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static var Java_constructor_methodID: JavaMethodID { Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")! }
        }
        extension S: TypeErasedConvertible {
            public func toTypeErased() -> AnyObject {
                let typeErased = S_TypeErased(self)
                typeErased.get_value = { [unowned typeErased] in (typeErased.genericvalue as! Self).value }
                typeErased.set_value = { [unowned typeErased] in
                    var genericvalue = typeErased.genericvalue as! Self
                    genericvalue.value = $0 as! T
                    typeErased.genericvalue = genericvalue
                }
                typeErased.identity_0 = { [unowned typeErased] in (typeErased.genericvalue as! Self).identity(p: $0 as! T, o: $1 as! T?, $2) }
                typeErased.mutatingVoid_1 = { [unowned typeErased] in
                    var genericvalue = typeErased.genericvalue as! Self
                    genericvalue.mutatingVoid()
                    typeErased.genericvalue = genericvalue
                }
                typeErased.mutatingRet_2 = { [unowned typeErased] in
                    var genericvalue = typeErased.genericvalue as! Self
                    let genericreturn = genericvalue.mutatingRet(p: $0 as! T)
                    typeErased.genericvalue = genericvalue
                return genericreturn
                }
                return typeErased
            }
        }
        private final class S_TypeErased {
            var genericvalue: Any
            init(_ value: Any) {
                self.genericvalue = value
            }
            var get_value: (() -> Any)!
            var set_value: ((Any) -> Void)!
            var identity_0: ((Any, Any?, Int) -> Any)!
            var mutatingVoid_1: (() -> Void)!
            var mutatingRet_2: ((Any) -> Int)!
        }
        @_cdecl("Java_S_Swift_1release")
        func S_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: S_TypeErased.self)
        }
        @_cdecl("Java_S_Swift_1value")
        func S_Swift_value(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer {
            let peer_swift: S_TypeErased = Swift_peer.pointee()!
            return AnyBridging.toJavaObject(peer_swift.get_value(), options: [])!
        }
        @_cdecl("Java_S_Swift_1value_1set")
        func S_Swift_value_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: JavaObjectPointer) {
            let peer_swift: S_TypeErased = Swift_peer.pointee()!
            peer_swift.set_value(AnyBridging.fromJavaObject(value, options: [])!)
        }
        @_cdecl("Java_S_Swift_1identity_10")
        func S_Swift_identity_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ p_0: JavaObjectPointer, _ p_1: JavaObjectPointer?, _ p_2: Int32) -> JavaObjectPointer {
            let p_0_swift = AnyBridging.fromJavaObject(p_0, options: [])!
            let p_1_swift = AnyBridging.fromJavaObject(p_1, options: [])
            let p_2_swift = Int(p_2)
            let peer_swift: S_TypeErased = Swift_peer.pointee()!
            let f_return_swift = peer_swift.identity_0(p_0_swift, p_1_swift, p_2_swift)
            return AnyBridging.toJavaObject(f_return_swift, options: [])!
        }
        @_cdecl("Java_S_Swift_1mutatingVoid_11")
        func S_Swift_mutatingVoid_1(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            let peer_swift: S_TypeErased = Swift_peer.pointee()!
            peer_swift.mutatingVoid_1()
        }
        @_cdecl("Java_S_Swift_1mutatingRet_12")
        func S_Swift_mutatingRet_2(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ p_0: JavaObjectPointer) -> Int32 {
            let p_0_swift = AnyBridging.fromJavaObject(p_0, options: [])!
            let peer_swift: S_TypeErased = Swift_peer.pointee()!
            let f_return_swift = peer_swift.mutatingRet_2(p_0_swift)
            return Int32(f_return_swift)
        }
        @_cdecl("Java_S_Swift_1constructor_13")
        func S_Swift_constructor_3(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaObjectPointer) -> SwiftObjectPointer {
            let ptr = SwiftObjectPointer.peer(of: p_0, options: [])
            let peer_swift: S_TypeErased = ptr.pointee()!
            let f_return_swift = (peer_swift.genericvalue as! TypeErasedConvertible).toTypeErased()
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_S_Swift_1projectionImpl")
        func S_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let ptr = SwiftObjectPointer.peer(of: Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let peer_swift: S_TypeErased = ptr.pointee()!
            let projection = peer_swift.genericvalue
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testGenericEnum() async throws {
        try await check(swiftBridge: """
        public enum E<T> {
            case a(T)
            case b
        
            public func aValue() -> T? {
                switch self {
                case .a(let value):
                    return value
                case .b:
                    return nil
                
            }
        }
        """, kotlin: """
        sealed class E<out T>: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {

            class ACase<T>(val associated0: T): E<T>() {
            }
            class BCase: E<Nothing>() {
            }
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()
            fun aValue(): T? = Swift_aValue_0(Swift_peer) as T?
            private external fun Swift_aValue_0(Swift_peer: skip.bridge.SwiftObjectPointer): Any?

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
                fun <T> a(associated0: T): E<T> = ACase(associated0)
                val b: E<Nothing> = BCase()
            }
        }
        """, swiftBridgeSupport: """
        extension E: BridgedToKotlin {
            private static var Java_class: JClass { try! JClass(name: "E") }
            private static var Java_Companion_class: JClass { try! JClass(name: "E$Companion") }
            private static var Java_Companion: JObject { JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: "Companion", sig: "LE$Companion;")!, options: [])) }
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                let typeErased: E_TypeErased = ptr.pointee()!
                return typeErased.genericvalue as! Self
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let typeErased = toTypeErased()
                let Swift_peer = SwiftObjectPointer.pointer(to: typeErased, retain: true)
                let setSwift_peerMethodID = Self.Java_class.getMethodID(name: "setSwift_peer", sig: "(J)V")!
                switch self {
                case .a(let associated0):
                    let associated0_java = AnyBridging.toJavaObject(associated0, options: options)!.toJavaParameter(options: options)
                    let ptr: JavaObjectPointer = try! Self.Java_Companion.call(method: Self.Java_Companion_a_methodID, options: options, args: [associated0_java])
                    try! ptr.call(method: setSwift_peerMethodID, options: options, args: [Swift_peer.toJavaParameter(options: options)])
                    return ptr
                case .b:
                    let ptr: JavaObjectPointer = try! Self.Java_Companion.call(method: Self.Java_Companion_b_methodID, options: options, args: [])
                    try! ptr.call(method: setSwift_peerMethodID, options: options, args: [Swift_peer.toJavaParameter(options: options)])
                    return ptr
                }
            }
            private static var Java_Companion_a_methodID: JavaMethodID { Java_Companion_class.getMethodID(name: "a", sig: "(Ljava/lang/Object;)LE;")! }
            private static var Java_Companion_b_methodID: JavaMethodID { Java_Companion_class.getMethodID(name: "getB", sig: "()LE;")! }
        }
        extension E: TypeErasedConvertible {
            public func toTypeErased() -> AnyObject {
                let typeErased = E_TypeErased(self)
                typeErased.aValue_0 = { [unowned typeErased] in (typeErased.genericvalue as! Self).aValue() }
                return typeErased
            }
        }
        private final class E_TypeErased {
            let genericvalue: Any
            init(_ value: Any) {
                self.genericvalue = value
            }
            var aValue_0: (() -> Any?)!
        }
        @_cdecl("Java_E_Swift_1release")
        func E_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: E_TypeErased.self)
        }
        @_cdecl("Java_E_Swift_1aValue_10")
        func E_Swift_aValue_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer? {
            let peer_swift: E_TypeErased = Swift_peer.pointee()!
            let f_return_swift = peer_swift.aValue_0()
            return AnyBridging.toJavaObject(f_return_swift, options: [])
        }
        @_cdecl("Java_E_Swift_1projectionImpl")
        func E_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let ptr = SwiftObjectPointer.peer(of: Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let peer_swift: E_TypeErased = ptr.pointee()!
            let projection = peer_swift.genericvalue
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testGenericProtocol() async throws {
        try await check(swiftBridge: """
        public protocol P {
            associatedtype T
            func f(p: T) -> T
        }
        public final class C: P {
            public func f(p: Int) -> Int {
                return p
            }
        }
        """, kotlin: """
        interface P<T> {
            fun f(p: T): T
        }
        class C: P<Int>, skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun f(p: Int): Int = Swift_f_0(Swift_peer, p)
            private external fun Swift_f_0(Swift_peer: skip.bridge.SwiftObjectPointer, p: Int): Int

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        public final class P_BridgeImpl<T>: P, BridgedFromKotlin {
            private static var Java_class: JClass { try! JClass(name: "P") }
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public func f(p p_0: T) -> T {
                return jniContext {
                    let p_0_java = AnyBridging.toJavaObject(p_0, options: [])!.toJavaParameter(options: [])
                    let f_return_java: JavaObjectPointer = try! Java_peer.call(method: Self.Java_f_0_methodID, options: [], args: [p_0_java])
                    return AnyBridging.fromJavaObject(f_return_java, options: []) as! T
                }
            }
            private static var Java_f_0_methodID: JavaMethodID { Java_class.getMethodID(name: "f", sig: "(Ljava/lang/Object;)Ljava/lang/Object;")! }
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        extension C: BridgedToKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1f_10")
        func C_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ p_0: Int32) -> Int32 {
            let p_0_swift = Int(p_0)
            let peer_swift: C = Swift_peer.pointee()!
            let f_return_swift = peer_swift.f(p: p_0_swift)
            return Int32(f_return_swift)
        }
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testGenericFunction() async throws {
        try await check(swiftBridge: """
        public func f<T>(p: T) -> T {
            return p
        }
        """, kotlin: """
        fun <T> f(p: T): T = Swift_f_0(p as Any) as T
        private external fun Swift_f_0(p: Any): Any
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaObjectPointer) -> JavaObjectPointer {
            let p_0_swift = AnyBridging.fromJavaObject(p_0, options: [])!
            let f_return_swift = f(p: p_0_swift)
            return AnyBridging.toJavaObject(f_return_swift, options: [])!
        }
        """, transformers: transformers)
    }

    func testConstrainedGenericFunction() async throws {
        try await check(swiftBridge: """
        protocol P {
        }
        public class C {
        }
        public func f<Param, Ret>(p: Param) -> Ret where Param: P, Param: C, Ret: P {
            return p
        }
        """, kotlin: """
        open class C: skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        fun <Param, Ret> f(p: Param): Ret where Param: C = Swift_f_0(p as Any) as Ret
        private external fun Swift_f_0(p: Any): Any
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin, BridgedToKotlinBaseClass {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                return ptr.pointee()!
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                let constructor = Java_findConstructor(base: Self.Java_class, Self.Java_constructor_methodID)
                return try! constructor.cls.create(ctor: constructor.ctor, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaObjectPointer) -> JavaObjectPointer {
            let p_0_swift = AnyBridging.fromJavaObject(p_0, toBaseType: (P & C).self, options: [])!
            let f_return_swift = f(p: p_0_swift)
            return AnyBridging.toJavaObject(f_return_swift, options: [])!
        }
        """, transformers: transformers)
    }

    func testAsyncGenericFunction() async throws {
        try await check(swiftBridge: """
        public func f<T>(p: T) async throws -> T {
            return p
        }
        """, kotlin: """
        suspend fun <T> f(p: T): T = Async.run {
            kotlin.coroutines.suspendCoroutine { f_continuation ->
                Swift_callback_f_0(p as Any) { f_return, f_error ->
                    if (f_error != null) {
                        f_continuation.resumeWith(kotlin.Result.failure(f_error))
                    } else {
                        f_continuation.resumeWith(kotlin.Result.success(f_return!! as T))
                    }
                }
            }
        }
        private external fun Swift_callback_f_0(p: Any, f_callback: (Any?, Throwable?) -> Unit)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1callback_1f_10")
        func BridgeKt_Swift_callback_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaObjectPointer, _ f_callback: JavaObjectPointer) {
            let p_0_swift = AnyBridging.fromJavaObject(p_0, options: [])!
            let f_callback_swift = SwiftClosure2.closure(forJavaObject: f_callback, options: [])! as (Any?, JavaObjectPointer?) -> Void
            Task {
                do {
                    let f_return_swift = try await f(p: p_0_swift)
                    f_callback_swift(f_return_swift, nil)
                } catch {
                    jniContext {
                        f_callback_swift(nil, JThrowable.toThrowable(error, options: [])!)
                    }
                }
            }
        }
        """, transformers: transformers)
    }

    func testBridgedView() async throws {
        try await check(swiftBridge: """
        #if canImport(SkipSwiftUI)
        import SkipFuseUI
        #endif
        public struct V: View {
            public let i: Int
            private var s = ""
            public init(i: Int) {
                self.i = i
            }
            public var body: some View {
                Text("Hello")
            }
        }
        """, kotlin: """
        class V: skip.ui.View, skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun body(): skip.ui.View {
                return skip.ui.ComposeBuilder { composectx: skip.ui.ComposeContext -> Swift_composableBody(Swift_peer)?.Compose(composectx) ?: skip.ui.ComposeResult.ok }
            }
            private external fun Swift_composableBody(Swift_peer: skip.bridge.SwiftObjectPointer): skip.ui.View?

            val i: Int
                get() = Swift_i(Swift_peer)
            private external fun Swift_i(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            constructor(i: Int) {
                Swift_peer = Swift_constructor_0(i)
            }
            private external fun Swift_constructor_0(i: Int): skip.bridge.SwiftObjectPointer

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """

        import SkipFuseUI
        extension V: BridgedToKotlin, SkipUIBridging, SkipUI.View {
            private static let Java_class = try! JClass(name: "V")
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                let box: SwiftValueTypeBox<Self> = ptr.pointee()!
                return box.value
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let box = SwiftValueTypeBox(self)
                let Swift_peer = SwiftObjectPointer.pointer(to: box, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
            public var Java_view: any SkipUI.View {
                return self
            }
        }
        @_cdecl("Java_V_Swift_1release")
        func V_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: SwiftValueTypeBox<V>.self)
        }
        @_cdecl("Java_V_Swift_1i")
        func V_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int32 {
            let peer_swift: SwiftValueTypeBox<V> = Swift_peer.pointee()!
            return Int32(peer_swift.value.i)
        }
        @_cdecl("Java_V_Swift_1constructor_10")
        func V_Swift_constructor_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32) -> SwiftObjectPointer {
            let p_0_swift = Int(p_0)
            let f_return_swift = SwiftValueTypeBox(V(i: p_0_swift))
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        @_cdecl("Java_V_Swift_1projectionImpl")
        func V_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = V.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        @_cdecl("Java_V_Swift_1composableBody")
        func V_Swift_composableBody(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer? {
            let peer_swift: SwiftValueTypeBox<V> = Swift_peer.pointee()!
            return SkipBridge.assumeMainActorUnchecked {
                let body = peer_swift.value.body
                return ((body as? SkipUIBridging)?.Java_view as? JConvertible)?.toJavaObject(options: [])
            }
        }
        """, transformers: transformers)
    }

    func testUnbridgedView() async throws {
        try await check(swiftBridge: """
        import SkipFuseUI
        protocol P {
        }
        struct V: View, P {
            private var s = ""
            @State var count = 1
            init(s: String) {
                self.s = s
            }
            var body: some View {
                Text("Hello")
            }
        }
        """, kotlin: """
        internal class V: skip.ui.View, skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            @androidx.compose.runtime.Composable
            override fun ComposeContent(composectx: skip.ui.ComposeContext) {
                val rememberedcount = androidx.compose.runtime.saveable.rememberSaveable(stateSaver = composectx.stateSaver as androidx.compose.runtime.saveable.Saver<skip.ui.StateSupport, Any>) { androidx.compose.runtime.mutableStateOf(Swift_initState_count(Swift_peer)) }
                Swift_syncState_count(Swift_peer, rememberedcount.value)
                super.ComposeContent(composectx)
            }
            private external fun Swift_initState_count(Swift_peer: skip.bridge.SwiftObjectPointer): skip.ui.StateSupport
            private external fun Swift_syncState_count(Swift_peer: skip.bridge.SwiftObjectPointer, support: skip.ui.StateSupport)

            override fun body(): skip.ui.View {
                return skip.ui.ComposeBuilder { composectx: skip.ui.ComposeContext -> Swift_composableBody(Swift_peer)?.Compose(composectx) ?: skip.ui.ComposeResult.ok }
            }
            private external fun Swift_composableBody(Swift_peer: skip.bridge.SwiftObjectPointer): skip.ui.View?

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        }
        """, swiftBridgeSupport: """

        import SkipFuseUI
        extension V: BridgedToKotlin, SkipUIBridging, SkipUI.View {
            private static let Java_class = try! JClass(name: "V")
            static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                let box: SwiftValueTypeBox<Self> = ptr.pointee()!
                return box.value
            }
            func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let box = SwiftValueTypeBox(self)
                let Swift_peer = SwiftObjectPointer.pointer(to: box, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
            func Java_initState_count() -> SkipUI.StateSupport {
                return $count.valueBox!.Java_initStateSupport()
            }
            func Java_syncState_count(support: SkipUI.StateSupport) {
                $count.valueBox!.Java_syncStateSupport(support)
            }
            var Java_view: any SkipUI.View {
                return self
            }
        }
        @_cdecl("Java_V_Swift_1release")
        func V_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: SwiftValueTypeBox<V>.self)
        }
        @_cdecl("Java_V_Swift_1projectionImpl")
        func V_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = V.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        @_cdecl("Java_V_Swift_1initState_1count")
        func V_Swift_initState_count(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer {
            let peer_swift: SwiftValueTypeBox<V> = Swift_peer.pointee()!
            return peer_swift.value.Java_initState_count().toJavaObject(options: [])!
        }
        @_cdecl("Java_V_Swift_1syncState_1count")
        func V_Swift_syncState_count(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ support: JavaObjectPointer) {
            let peer_swift: SwiftValueTypeBox<V> = Swift_peer.pointee()!
            let support_swift = SkipUI.StateSupport.fromJavaObject(support, options: [])
            peer_swift.value.Java_syncState_count(support: support_swift)
        }
        @_cdecl("Java_V_Swift_1composableBody")
        func V_Swift_composableBody(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer? {
            let peer_swift: SwiftValueTypeBox<V> = Swift_peer.pointee()!
            return SkipBridge.assumeMainActorUnchecked {
                let body = peer_swift.value.body
                return ((body as? SkipUIBridging)?.Java_view as? JConvertible)?.toJavaObject(options: [])
            }
        }
        """, transformers: transformers)
    }

    func testEnumView() async throws {
        try await check(swiftBridge: """
        import SkipSwiftUI
        public enum E: View {
            case a
            public var body: some View {
                switch self {
                case .a:
                    Text("A")
                }
            }
        }
        """, kotlin: """
        enum class E: skip.ui.View, skip.lib.SwiftProjecting {

            a;

            override fun body(): skip.ui.View {
                return skip.ui.ComposeBuilder { composectx: skip.ui.ComposeContext -> Swift_composableBody()?.Compose(composectx) ?: skip.ui.ComposeResult.ok }
            }
            private external fun Swift_composableBody(): skip.ui.View?

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        import SkipSwiftUI
        extension E: BridgedToKotlin, SkipUIBridging, SkipUI.View {
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
                default: fatalError()
                }
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let name = switch self {
                case .a: "a"
                }
                return try! Self.Java_class.callStatic(method: Self.Java_valueOf_methodID, options: options, args: [name.toJavaParameter(options: options)])
            }
            private static let Java_name_methodID = Java_class.getMethodID(name: "name", sig: "()Ljava/lang/String;")!
            private static let Java_valueOf_methodID = Java_class.getStaticMethodID(name: "valueOf", sig: "(Ljava/lang/String;)LE;")!
            public var Java_view: any SkipUI.View {
                return self
            }
        }
        @_cdecl("Java_E_Swift_1projectionImpl")
        func E_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = E.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        @_cdecl("Java_E_Swift_1composableBody")
        func E_Swift_composableBody(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer? {
            let peer_swift = E.fromJavaObject(Java_target, options: [])
            return SkipBridge.assumeMainActorUnchecked {
                let body = peer_swift.body
                return ((body as? SkipUIBridging)?.Java_view as? JConvertible)?.toJavaObject(options: [])
            }
        }
        """, transformers: transformers)
    }

    func testFocusState() async throws {
        try await check(swiftBridge: """
        import SkipFuseUI
        struct V: View {
            @FocusState var focused: Bool
            var body: some View {
                Text("Hello")
            }
        }
        """, kotlin: """
        internal class V: skip.ui.View, skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            @androidx.compose.runtime.Composable
            override fun ComposeContent(composectx: skip.ui.ComposeContext) {
                val rememberedfocused = androidx.compose.runtime.saveable.rememberSaveable(stateSaver = composectx.stateSaver as androidx.compose.runtime.saveable.Saver<skip.ui.StateSupport, Any>) { androidx.compose.runtime.mutableStateOf(Swift_initState_focused(Swift_peer)) }
                Swift_syncState_focused(Swift_peer, rememberedfocused.value)
                super.ComposeContent(composectx)
            }
            private external fun Swift_initState_focused(Swift_peer: skip.bridge.SwiftObjectPointer): skip.ui.StateSupport
            private external fun Swift_syncState_focused(Swift_peer: skip.bridge.SwiftObjectPointer, support: skip.ui.StateSupport)

            override fun body(): skip.ui.View {
                return skip.ui.ComposeBuilder { composectx: skip.ui.ComposeContext -> Swift_composableBody(Swift_peer)?.Compose(composectx) ?: skip.ui.ComposeResult.ok }
            }
            private external fun Swift_composableBody(Swift_peer: skip.bridge.SwiftObjectPointer): skip.ui.View?

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        }
        """, swiftBridgeSupport: """

        import SkipFuseUI
        extension V: BridgedToKotlin, SkipUIBridging, SkipUI.View {
            private static let Java_class = try! JClass(name: "V")
            static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                let box: SwiftValueTypeBox<Self> = ptr.pointee()!
                return box.value
            }
            func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let box = SwiftValueTypeBox(self)
                let Swift_peer = SwiftObjectPointer.pointer(to: box, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
            func Java_initState_focused() -> SkipUI.StateSupport {
                return $focused.valueBox!.Java_initStateSupport()
            }
            func Java_syncState_focused(support: SkipUI.StateSupport) {
                $focused.valueBox!.Java_syncStateSupport(support)
            }
            var Java_view: any SkipUI.View {
                return self
            }
        }
        @_cdecl("Java_V_Swift_1release")
        func V_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: SwiftValueTypeBox<V>.self)
        }
        @_cdecl("Java_V_Swift_1projectionImpl")
        func V_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = V.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        @_cdecl("Java_V_Swift_1initState_1focused")
        func V_Swift_initState_focused(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer {
            let peer_swift: SwiftValueTypeBox<V> = Swift_peer.pointee()!
            return peer_swift.value.Java_initState_focused().toJavaObject(options: [])!
        }
        @_cdecl("Java_V_Swift_1syncState_1focused")
        func V_Swift_syncState_focused(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ support: JavaObjectPointer) {
            let peer_swift: SwiftValueTypeBox<V> = Swift_peer.pointee()!
            let support_swift = SkipUI.StateSupport.fromJavaObject(support, options: [])
            peer_swift.value.Java_syncState_focused(support: support_swift)
        }
        @_cdecl("Java_V_Swift_1composableBody")
        func V_Swift_composableBody(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer? {
            let peer_swift: SwiftValueTypeBox<V> = Swift_peer.pointee()!
            return SkipBridge.assumeMainActorUnchecked {
                let body = peer_swift.value.body
                return ((body as? SkipUIBridging)?.Java_view as? JConvertible)?.toJavaObject(options: [])
            }
        }
        """, transformers: transformers)
    }

    func testAppStorage() async throws {
        try await check(swiftBridge: """
        import SkipFuseUI
        struct V: View {
            @AppStorage var value = false
            var body: some View {
                Text("Hello")
            }
        }
        """, kotlin: """
        internal class V: skip.ui.View, skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            @androidx.compose.runtime.Composable
            override fun ComposeContent(composectx: skip.ui.ComposeContext) {
                val rememberedvalue = androidx.compose.runtime.saveable.rememberSaveable(stateSaver = composectx.stateSaver as androidx.compose.runtime.saveable.Saver<skip.ui.AppStorageSupport, Any>) { androidx.compose.runtime.mutableStateOf(Swift_initState_value(Swift_peer)) }
                Swift_syncState_value(Swift_peer, rememberedvalue.value)
                super.ComposeContent(composectx)
            }
            private external fun Swift_initState_value(Swift_peer: skip.bridge.SwiftObjectPointer): skip.ui.AppStorageSupport
            private external fun Swift_syncState_value(Swift_peer: skip.bridge.SwiftObjectPointer, support: skip.ui.AppStorageSupport)

            override fun body(): skip.ui.View {
                return skip.ui.ComposeBuilder { composectx: skip.ui.ComposeContext -> Swift_composableBody(Swift_peer)?.Compose(composectx) ?: skip.ui.ComposeResult.ok }
            }
            private external fun Swift_composableBody(Swift_peer: skip.bridge.SwiftObjectPointer): skip.ui.View?

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        }
        """, swiftBridgeSupport: """

        import SkipFuseUI
        extension V: BridgedToKotlin, SkipUIBridging, SkipUI.View {
            private static let Java_class = try! JClass(name: "V")
            static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                let box: SwiftValueTypeBox<Self> = ptr.pointee()!
                return box.value
            }
            func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let box = SwiftValueTypeBox(self)
                let Swift_peer = SwiftObjectPointer.pointer(to: box, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
            func Java_initState_value() -> SkipUI.AppStorageSupport {
                return $value.appStorageBox!.Java_initStateSupport()
            }
            func Java_syncState_value(support: SkipUI.AppStorageSupport) {
                $value.appStorageBox!.Java_syncStateSupport(support)
            }
            var Java_view: any SkipUI.View {
                return self
            }
        }
        @_cdecl("Java_V_Swift_1release")
        func V_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: SwiftValueTypeBox<V>.self)
        }
        @_cdecl("Java_V_Swift_1projectionImpl")
        func V_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = V.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        @_cdecl("Java_V_Swift_1initState_1value")
        func V_Swift_initState_value(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer {
            let peer_swift: SwiftValueTypeBox<V> = Swift_peer.pointee()!
            return peer_swift.value.Java_initState_value().toJavaObject(options: [])!
        }
        @_cdecl("Java_V_Swift_1syncState_1value")
        func V_Swift_syncState_value(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ support: JavaObjectPointer) {
            let peer_swift: SwiftValueTypeBox<V> = Swift_peer.pointee()!
            let support_swift = SkipUI.AppStorageSupport.fromJavaObject(support, options: [])
            peer_swift.value.Java_syncState_value(support: support_swift)
        }
        @_cdecl("Java_V_Swift_1composableBody")
        func V_Swift_composableBody(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer? {
            let peer_swift: SwiftValueTypeBox<V> = Swift_peer.pointee()!
            return SkipBridge.assumeMainActorUnchecked {
                let body = peer_swift.value.body
                return ((body as? SkipUIBridging)?.Java_view as? JConvertible)?.toJavaObject(options: [])
            }
        }
        """, transformers: transformers)
    }

    func testIfSkipBlock() async throws {
        try await check(swiftBridge: """
        #if os(Android)
        public var x = 1
        #endif
        #if SKIP
        var kotlinX = 2
        // SKIP @nobridge
        var kotlinY = ""
        #endif
        """, kotlin: """
        var x: Int
            get() = Swift_x()
            set(newValue) {
                Swift_x_set(newValue)
            }
        private external fun Swift_x(): Int
        private external fun Swift_x_set(value: Int)
        internal var kotlinX = 2
        internal var kotlinY = ""
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1x")
        func BridgeKt_Swift_x(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int32 {
            return Int32(x)
        }
        @_cdecl("Java_BridgeKt_Swift_1x_1set")
        func BridgeKt_Swift_x_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: Int32) {
            x = Int(value)
        }
        import SkipBridge

        private let Java_BridgeKt = try! JClass(name: "BridgeKt")
        var kotlinX: Int {
            get {
                return jniContext {
                    let value_java: Int32 = try! Java_BridgeKt.callStatic(method: Java_get_kotlinX_methodID, options: [], args: [])
                    return Int(value_java)
                }
            }
            set {
                jniContext {
                    let value_java = Int32(newValue).toJavaParameter(options: [])
                    try! Java_BridgeKt.callStatic(method: Java_set_kotlinX_methodID, options: [], args: [value_java])
                }
            }
        }
        private let Java_get_kotlinX_methodID = Java_BridgeKt.getStaticMethodID(name: "getKotlinX", sig: "()I")!
        private let Java_set_kotlinX_methodID = Java_BridgeKt.getStaticMethodID(name: "setKotlinX", sig: "(I)V")!
        """, transformers: transformers)
    }

    func testIfSkipBlockAnyDynamicObject() async throws {
        try await check(swiftBridge: """
        #if os(Android)
        public func readKotlinDate() {
            let d = kotlinDate
            try print(d.toString() as String)
        }
        #endif
        #if SKIP
        // SKIP @bridge
        var kotlinDate: java.util.Date = java.util.Date()
        #endif
        """, kotlin: """
        fun readKotlinDate(): Unit = Swift_readKotlinDate_0()
        private external fun Swift_readKotlinDate_0()
        internal var kotlinDate: java.util.Date = java.util.Date()
            get() = field.sref({ kotlinDate = it })
            set(newValue) {
                field = newValue.sref()
            }
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1readKotlinDate_10")
        func BridgeKt_Swift_readKotlinDate_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) {
            readKotlinDate()
        }
        import SkipBridge

        private let Java_BridgeKt = try! JClass(name: "BridgeKt")
        var kotlinDate: AnyDynamicObject {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer = try! Java_BridgeKt.callStatic(method: Java_get_kotlinDate_methodID, options: [], args: [])
                    return AnyDynamicObject.fromJavaObject(value_java, options: [])
                }
            }
            set {
                jniContext {
                    let value_java = newValue.toJavaObject(options: [])!.toJavaParameter(options: [])
                    try! Java_BridgeKt.callStatic(method: Java_set_kotlinDate_methodID, options: [], args: [value_java])
                }
            }
        }
        private let Java_get_kotlinDate_methodID = Java_BridgeKt.getStaticMethodID(name: "getKotlinDate", sig: "()Ljava/util/Date;")!
        private let Java_set_kotlinDate_methodID = Java_BridgeKt.getStaticMethodID(name: "setKotlinDate", sig: "(Ljava/util/Date;)V")!
        """, transformers: transformers)
    }

    func testIfSkipBlockContentComposer() async throws {
        try await check(swiftBridge: """
        #if os(Android)
        import SkipFuseUI
        
        struct V: View {
            var body: some View {
                ComposeView { HelloComposer("hello") }
            }
        }
        #endif
        #if SKIP
        struct HelloComposer: ContentComposer {
            let message: String
        
            @Composable func Compose(context: ComposeContext) {
                androidx.compose.material3.Text(message)
            }
        }
        #endif
        """, kotlin: """
        import androidx.compose.runtime.Composable

        internal class V: skip.ui.View, skip.bridge.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.SwiftObjectPointer = skip.bridge.SwiftObjectNil

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_peer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun body(): skip.ui.View {
                return skip.ui.ComposeBuilder { composectx: skip.ui.ComposeContext -> Swift_composableBody(Swift_peer)?.Compose(composectx) ?: skip.ui.ComposeResult.ok }
            }
            private external fun Swift_composableBody(Swift_peer: skip.bridge.SwiftObjectPointer): skip.ui.View?

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        }
        internal class HelloComposer: ContentComposer, skip.lib.SwiftProjecting {
            internal val message: String

            @Composable
            override fun Compose(context: ComposeContext): Unit = androidx.compose.material3.Text(message)

            constructor(message: String) {
                this.message = message
            }

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        }
        """, swiftBridgeSupport: """
        import SkipFuseUI
        extension V: BridgedToKotlin, SkipUIBridging, SkipUI.View {
            private static let Java_class = try! JClass(name: "V")
            static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!, options: options)
                let box: SwiftValueTypeBox<Self> = ptr.pointee()!
                return box.value
            }
            func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                let box = SwiftValueTypeBox(self)
                let Swift_peer = SwiftObjectPointer.pointer(to: box, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
            var Java_view: any SkipUI.View {
                return self
            }
        }
        @_cdecl("Java_V_Swift_1release")
        func V_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: SwiftValueTypeBox<V>.self)
        }
        @_cdecl("Java_V_Swift_1projectionImpl")
        func V_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = V.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        @_cdecl("Java_V_Swift_1composableBody")
        func V_Swift_composableBody(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> JavaObjectPointer? {
            let peer_swift: SwiftValueTypeBox<V> = Swift_peer.pointee()!
            return SkipBridge.assumeMainActorUnchecked {
                let body = peer_swift.value.body
                return ((body as? SkipUIBridging)?.Java_view as? JConvertible)?.toJavaObject(options: [])
            }
        }
        import SkipBridge

        struct HelloComposer: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "HelloComposer")
            var Java_peer: JObject
            init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            var message: String {
                get {
                    return jniContext {
                        let value_java: String = try! Java_peer.call(method: Self.Java_get_message_methodID, options: [], args: [])
                        return value_java
                    }
                }
            }
            private static let Java_get_message_methodID = Java_class.getMethodID(name: "getMessage", sig: "()Ljava/lang/String;")!

            public init(message p_0: String) {
                Java_peer = jniContext {
                    let p_0_java = p_0.toJavaParameter(options: [])
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_0_methodID, options: [], args: [p_0_java])
                    return JObject(ptr)
                }
            }
            private static let Java_constructor_0_methodID = Java_class.getMethodID(name: "<init>", sig: "(Ljava/lang/String;)V")!
        }
        @_cdecl("Java_HelloComposer_Swift_1projectionImpl")
        func HelloComposer_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = HelloComposer.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    public func testBundleModule() async throws {
        KotlinBundleTransformer.testSkipAndroidBridge = true
        defer { KotlinBundleTransformer.testSkipAndroidBridge = false }

        try await check(swiftBridge: """
        let x = 1
        """, kotlin: """
        """, kotlinPackageSupport: """
        internal val skip.foundation.Bundle.Companion.module: skip.foundation.Bundle
            get() = _moduleBundle
        private val _moduleBundle: skip.foundation.Bundle by lazy {
            skip.foundation.Bundle(_ModuleBundleLocator::class)
        }
        internal class _ModuleBundleLocator {}
        class _ModuleBundleAccessor_ {
            val moduleBundle = _moduleBundle
        }
        """, swiftBridgeSupport: """

        import Foundation
        import SkipAndroidBridge

        typealias Bundle = AndroidModuleBundle
        class AndroidModuleBundle : AndroidBundle, @unchecked Sendable {
            required init(_ bundle: SkipAndroidBridge.BundleAccess) {
                super.init(bundle)
            }

            init?(path: String) {
                super.init(path: path, moduleName: "") {
                    try! AnyDynamicObject(className: ".module._ModuleBundleAccessor_").moduleBundle!
                }
            }

            override init?(url: URL) {
                super.init(url: url)
            }
        }

        let NSLocalizedString = AndroidLocalizedString()
        """, transformers: transformers)
    }
}
