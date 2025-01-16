import SkipSyntax
import XCTest

final class BridgeToSwiftTests: XCTestCase {
    private var transformers: [KotlinTransformer] {
        return builtinKotlinTransformers() + [KotlinBridgeTransformer()]
    }

    func testLetSupportedLiteral() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public let b = true
        #endif
        """, kotlin: """
        val b = true
        """, swiftBridgeSupport: """
        public let b = true
        """, transformers: transformers)

        try await check(swift: """
        #if !SKIP_BRIDGE
        public let i = 1
        #endif
        """, kotlin: """
        val i = 1
        """, swiftBridgeSupport: """
        public let i: Int = 1
        """, transformers: transformers)

        try await check(swift: """
        #if !SKIP_BRIDGE
        public let i: Int32 = 1
        #endif
        """, kotlin: """
        val i: Int = 1
        """, swiftBridgeSupport: """
        public let i: Int32 = 1
        """, transformers: transformers)

        try await check(swift: """
        #if !SKIP_BRIDGE
        public let d = 5.0
        #endif
        """, kotlin: """
        val d = 5.0
        """, swiftBridgeSupport: """
        public let d: Double = 5.0
        """, transformers: transformers)

        try await check(swift: """
        #if !SKIP_BRIDGE
        public let d: Double = 5
        #endif
        """, kotlin: """
        val d: Double = 5.0
        """, swiftBridgeSupport: """
        public let d: Double = 5
        """, transformers: transformers)

        try await check(swift: """
        #if !SKIP_BRIDGE
        public let d: Double? = nil
        #endif
        """, kotlin: """
        val d: Double? = null
        """, swiftBridgeSupport: """
        public let d: Double? = nil
        """, transformers: transformers)

        try await check(swift: """
        #if !SKIP_BRIDGE
        public let d: Double? = 5
        #endif
        """, kotlin: """
        val d: Double? = 5.0
        """, swiftBridgeSupport: """
        public let d: Double? = 5
        """, transformers: transformers)

        try await check(swift: """
        #if !SKIP_BRIDGE
        public let f = Float(1)
        #endif
        """, kotlin: """
        val f = 1f
        """, swiftBridgeSupport: """
        public let f: Float = 1
        """, transformers: transformers)

        try await check(swift: """
        #if !SKIP_BRIDGE
        public let s = "Hello"
        #endif
        """, kotlin: """
        val s = "Hello"
        """, swiftBridgeSupport: """
        public let s = "Hello"
        """, transformers: transformers)

        try await check(swift: """
        #if !SKIP_BRIDGE
        public let l = Int64(1)
        #endif
        """, kotlin: """
        val l = 1L
        """, swiftBridgeSupport: """
        public let l: Int64 = 1
        """, transformers: transformers)
    }

    func testLetUnsupportedLiteral() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public let s = "ab\\(1 + 1)c"
        #endif
        """, kotlin: """
        val s = "ab${1 + 1}c"
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var s: String {
            get {
                return jniContext {
                    let value_java: String = try! Java_SourceKt.callStatic(method: Java_get_s_methodID, options: [], args: [])
                    return value_java
                }
            }
        }
        private let Java_get_s_methodID = Java_SourceKt.getStaticMethodID(name: "getS", sig: "()Ljava/lang/String;")!
        """, transformers: transformers)

        try await check(swift: """
        #if !SKIP_BRIDGE
        public let b: Bool? = true
        #endif
        """, kotlin: """
        val b: Boolean? = true
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var b: Bool? {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer? = try! Java_SourceKt.callStatic(method: Java_get_b_methodID, options: [], args: [])
                    return Bool?.fromJavaObject(value_java, options: [])
                }
            }
        }
        private let Java_get_b_methodID = Java_SourceKt.getStaticMethodID(name: "getB", sig: "()Ljava/lang/Boolean;")!
        """, transformers: transformers)
    }

    func testLetNonLiteral() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public let i = 1 + 1
        #endif
        """, kotlin: """
        val i = 1 + 1
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var i: Int {
            get {
                return jniContext {
                    let value_java: Int32 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, options: [], args: [])
                    return Int(value_java)
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()I")!
        """, transformers: transformers)

        try await check(swift: """
        #if !SKIP_BRIDGE
        public let i = Int64(1 + 1)
        #endif
        """, kotlin: """
        val i = Long(1 + 1)
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var i: Int64 {
            get {
                return jniContext {
                    let value_java: Int64 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, options: [], args: [])
                    return value_java
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()J")!
        """, transformers: transformers)
    }

    func testStoredVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public var i = 1
        #endif
        """, kotlin: """
        var i = 1
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var i: Int {
            get {
                return jniContext {
                    let value_java: Int32 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, options: [], args: [])
                    return Int(value_java)
                }
            }
            set {
                jniContext {
                    let value_java = Int32(newValue).toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_set_i_methodID, options: [], args: [value_java])
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()I")!
        private let Java_set_i_methodID = Java_SourceKt.getStaticMethodID(name: "setI", sig: "(I)V")!
        """, transformers: transformers)
    }

    func testNoBridgeVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        // SKIP @nobridge
        public var i = 1
        @BridgeIgnored
        public var j = 1
        public let s = ""
        #endif
        """, kotlin: """
        var i = 1
        var j = 1
        val s = ""
        """, swiftBridgeSupport: """
        public let s = ""
        """, transformers: transformers)
    }

    func testPrivateVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        private var i = 1
        private var j = 1
        public let s = ""
        #endif
        """, kotlin: """
        private var i = 1
        private var j = 1
        val s = ""
        """, swiftBridgeSupport: """
        public let s = ""
        """, transformers: transformers)
    }

    func testPrivateSetVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        private(set) public var i = 1
        #endif
        """, kotlin: """
        var i = 1
            private set
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var i: Int {
            get {
                return jniContext {
                    let value_java: Int32 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, options: [], args: [])
                    return Int(value_java)
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()I")!
        """, transformers: transformers)

        try await check(swift: """
        #if !SKIP_BRIDGE
        public private(set) var d: Double {
            get {
                return 1.0
            }
            set {
                print("set")
            }
        }
        #endif
        """, kotlin: """
        var d: Double
            get() = 1.0
            private set(newValue) {
                print("set")
            }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var d: Double {
            get {
                return jniContext {
                    let value_java: Double = try! Java_SourceKt.callStatic(method: Java_get_d_methodID, options: [], args: [])
                    return value_java
                }
            }
        }
        private let Java_get_d_methodID = Java_SourceKt.getStaticMethodID(name: "getD", sig: "()D")!
        """, transformers: transformers)
    }

    func testWillSetDidSet() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public private(set) var i: Int32 = 1 {
            willSet {
                print("willSet")
            }
            didSet {
                print("didSet")
            }
        }
        #endif
        """, kotlin: """
        var i: Int = 1
            private set(newValue) {
                print("willSet")
                field = newValue
                print("didSet")
            }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var i: Int32 {
            get {
                return jniContext {
                    let value_java: Int32 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, options: [], args: [])
                    return value_java
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()I")!
        """, transformers: transformers)
    }

    func testComputedVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public var i: Int64 {
            get {
                return 1
            }
            set {
            }
        }
        #endif
        """, kotlin: """
        var i: Long
            get() = 1
            set(newValue) {
            }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var i: Int64 {
            get {
                return jniContext {
                    let value_java: Int64 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, options: [], args: [])
                    return value_java
                }
            }
            set {
                jniContext {
                    let value_java = newValue.toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_set_i_methodID, options: [], args: [value_java])
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()J")!
        private let Java_set_i_methodID = Java_SourceKt.getStaticMethodID(name: "setI", sig: "(J)V")!
        """, transformers: transformers)
    }

    func testKeywordVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public var object = ""
        #endif
        """, kotlin: """
        var object_ = ""
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var object: String {
            get {
                return jniContext {
                    let value_java: String = try! Java_SourceKt.callStatic(method: Java_get_object_methodID, options: [], args: [])
                    return value_java
                }
            }
            set {
                jniContext {
                    let value_java = newValue.toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_set_object_methodID, options: [], args: [value_java])
                }
            }
        }
        private let Java_get_object_methodID = Java_SourceKt.getStaticMethodID(name: "getObject_", sig: "()Ljava/lang/String;")!
        private let Java_set_object_methodID = Java_SourceKt.getStaticMethodID(name: "setObject_", sig: "(Ljava/lang/String;)V")!
        """, transformers: transformers)
    }

    func testThrowsVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public var i: Int {
            get throws {
                return 0
            }
        }
        #endif
        """, kotlin: """
        val i: Int
            get() = 0
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var i: Int {
            get throws {
                return try jniContext {
                    do {
                        let value_java: Int32 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, options: [], args: [])
                        return Int(value_java)
                    } catch let error as (Error & JConvertible) {
                        throw error
                    } catch {
                        fatalError(String(describing: error))
                    }
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()I")!
        """, transformers: transformers)
    }

    func testAsyncVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public var i: Int {
            get async {
                return 0
            }
        }
        #endif
        """, kotlin: """
        suspend fun i(): Int = Async.run l@{
            return@l 0
        }
        fun callback_i(f_return_callback: (Int) -> Unit) {
            Task {
                f_return_callback(i())
            }
        }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var i: Int {
            get async {
                return await withCheckedContinuation { f_continuation in
                    let f_return_callback: (Int) -> Void = { f_return in
                        f_continuation.resume(returning: f_return)
                    }
                    jniContext {
                        let f_return_callback_java = SwiftClosure1.javaObject(for: f_return_callback, options: []).toJavaParameter(options: [])
                        try! Java_SourceKt.callStatic(method: Java_i_methodID, options: [], args: [f_return_callback_java])
                    }
                }
            }
        }
        private let Java_i_methodID = Java_SourceKt.getStaticMethodID(name: "callback_i", sig: "(Lkotlin/jvm/functions/Function1;)V")!
        """, transformers: transformers)
    }

    func testAsyncThrowsVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public var i: Int {
            get async throws {
                return 0
            }
        }
        #endif
        """, kotlin: """
        suspend fun i(): Int = Async.run l@{
            return@l 0
        }
        fun callback_i(f_return_callback: (Int?, Throwable?) -> Unit) {
            Task {
                try {
                    f_return_callback(i(), null)
                } catch(t: Throwable) {
                    f_return_callback(null, t)
                }
            }
        }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var i: Int {
            get async throws {
                return try await withCheckedThrowingContinuation { f_continuation in
                    let f_return_callback: (Int?, JavaObjectPointer?) -> Void = { f_return, f_error in
                        if let f_error {
                            f_continuation.resume(throwing: JThrowable.toError(f_error, options: []))
                        } else {
                            f_continuation.resume(returning: f_return!)
                        }
                    }
                    jniContext {
                        let f_return_callback_java = SwiftClosure2.javaObject(for: f_return_callback, options: []).toJavaParameter(options: [])
                        try! Java_SourceKt.callStatic(method: Java_i_methodID, options: [], args: [f_return_callback_java])
                    }
                }
            }
        }
        private let Java_i_methodID = Java_SourceKt.getStaticMethodID(name: "callback_i", sig: "(Lkotlin/jvm/functions/Function2;)V")!
        """, transformers: transformers)
    }

    func testOptionalVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public var i: Int? = 1
        #endif
        """, kotlin: """
        var i: Int? = 1
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var i: Int? {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer? = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, options: [], args: [])
                    return Int?.fromJavaObject(value_java, options: [])
                }
            }
            set {
                jniContext {
                    let value_java = newValue.toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_set_i_methodID, options: [], args: [value_java])
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()Ljava/lang/Integer;")!
        private let Java_set_i_methodID = Java_SourceKt.getStaticMethodID(name: "setI", sig: "(Ljava/lang/Integer;)V")!
        """, transformers: transformers)
    }

    func testUnwrappedOptionalVar() async throws {
        try await checkProducesMessage(swift: """
        public var s: String!
        """, transformers: transformers)
    }

    func testLazyVar() async throws {
        try await checkProducesMessage(swift: """
        public lazy var s: String = createString()
        """, transformers: transformers)
    }

    func testTranspiledBridgedTypeVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
        }
        public var c = C()
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        var c = C()
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
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
        public var c: C {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer = try! Java_SourceKt.callStatic(method: Java_get_c_methodID, options: [], args: [])
                    return C.fromJavaObject(value_java, options: [])
                }
            }
            set {
                jniContext {
                    let value_java = newValue.toJavaObject(options: [])!.toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_set_c_methodID, options: [], args: [value_java])
                }
            }
        }
        private let Java_get_c_methodID = Java_SourceKt.getStaticMethodID(name: "getC", sig: "()LC;")!
        private let Java_set_c_methodID = Java_SourceKt.getStaticMethodID(name: "setC", sig: "(LC;)V")!
        """, transformers: transformers)
    }

    func testOptionalTranspiledBridgedTypeVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
        }
        public var c: C? = C()
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        var c: C? = C()
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
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
        public var c: C? {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer? = try! Java_SourceKt.callStatic(method: Java_get_c_methodID, options: [], args: [])
                    return C?.fromJavaObject(value_java, options: [])
                }
            }
            set {
                jniContext {
                    let value_java = newValue.toJavaObject(options: []).toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_set_c_methodID, options: [], args: [value_java])
                }
            }
        }
        private let Java_get_c_methodID = Java_SourceKt.getStaticMethodID(name: "getC", sig: "()LC;")!
        private let Java_set_c_methodID = Java_SourceKt.getStaticMethodID(name: "setC", sig: "(LC;)V")!
        """, transformers: transformers)
    }

    func testCompiledBridgedTypeVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public var c = C()
        #endif
        """, swiftBridge: """
        public final class C {
        }
        """, kotlins: ["""
        class C: skip.bridge.kt.SwiftPeerBridged, skip.lib.SwiftProjecting {
            var Swift_peer: skip.bridge.kt.SwiftObjectPointer = skip.bridge.kt.SwiftObjectNil
        
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
        
            override fun Swift_peer(): skip.bridge.kt.SwiftObjectPointer = Swift_peer
        
            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.kt.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_peer()
            }
        
            override fun hashCode(): Int = Swift_peer.hashCode()
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, """
        var c = C()
        """], swiftBridgeSupports: ["""
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var c: C {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer = try! Java_SourceKt.callStatic(method: Java_get_c_methodID, options: [], args: [])
                    return C.fromJavaObject(value_java, options: [])
                }
            }
            set {
                jniContext {
                    let value_java = newValue.toJavaObject(options: [])!.toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_set_c_methodID, options: [], args: [value_java])
                }
            }
        }
        private let Java_get_c_methodID = Java_SourceKt.getStaticMethodID(name: "getC", sig: "()LC;")!
        private let Java_set_c_methodID = Java_SourceKt.getStaticMethodID(name: "setC", sig: "(LC;)V")!
        """], transformers: transformers)
    }

    func testUnbridgableVar() async throws {
        try await checkProducesMessage(swift: """
        public var c: C = C()
        """, transformers: transformers)

        try await checkProducesMessage(swift: """
        // SKIP @nobridge
        public class C {
        }
        public var c = C()
        """, transformers: transformers)
    }

    func testJavaTypeVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        #if SKIP
        public var d: java.util.Date = java.util.Date()
        public var bds: [java.math.BigDecimal]? = nil
        #endif
        #endif
        """, kotlin: """
        import skip.lib.Array
        
        var d: java.util.Date = java.util.Date()
            get() = field.sref({ d = it })
            set(newValue) {
                field = newValue.sref()
            }
        var bds: Array<java.math.BigDecimal>? = null
            get() = field.sref({ bds = it })
            set(newValue) {
                field = newValue.sref()
            }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var d: AnyDynamicObject {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer = try! Java_SourceKt.callStatic(method: Java_get_d_methodID, options: [], args: [])
                    return AnyDynamicObject.fromJavaObject(value_java, options: [])
                }
            }
            set {
                jniContext {
                    let value_java = newValue.toJavaObject(options: [])!.toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_set_d_methodID, options: [], args: [value_java])
                }
            }
        }
        private let Java_get_d_methodID = Java_SourceKt.getStaticMethodID(name: "getD", sig: "()Ljava/util/Date;")!
        private let Java_set_d_methodID = Java_SourceKt.getStaticMethodID(name: "setD", sig: "(Ljava/util/Date;)V")!
        public var bds: [AnyDynamicObject]? {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer? = try! Java_SourceKt.callStatic(method: Java_get_bds_methodID, options: [], args: [])
                    return [AnyDynamicObject]?.fromJavaObject(value_java, options: [])
                }
            }
            set {
                jniContext {
                    let value_java = newValue.toJavaObject(options: []).toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_set_bds_methodID, options: [], args: [value_java])
                }
            }
        }
        private let Java_get_bds_methodID = Java_SourceKt.getStaticMethodID(name: "getBds", sig: "()Lskip/lib/Array;")!
        private let Java_set_bds_methodID = Java_SourceKt.getStaticMethodID(name: "setBds", sig: "(Lskip/lib/Array;)V")!
        """, transformers: transformers)
    }

    func testClosureVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public var c: (Int) -> String = { _ in "" }
        #endif
        """, kotlin: """
        var c: (Int) -> String = { _ -> "" }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var c: (Int) -> String {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer = try! Java_SourceKt.callStatic(method: Java_get_c_methodID, options: [], args: [])
                    return { let closure_swift = JavaBackedClosure<String>(value_java, options: []); return { p0 in try! closure_swift.invoke(p0) } }()
                }
            }
            set {
                jniContext {
                    let value_java = SwiftClosure1.javaObject(for: newValue, options: [])!.toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_set_c_methodID, options: [], args: [value_java])
                }
            }
        }
        private let Java_get_c_methodID = Java_SourceKt.getStaticMethodID(name: "getC", sig: "()Lkotlin/jvm/functions/Function1;")!
        private let Java_set_c_methodID = Java_SourceKt.getStaticMethodID(name: "setC", sig: "(Lkotlin/jvm/functions/Function1;)V")!
        """, transformers: transformers)
    }

    func testVoidClosureVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public var c: () -> Void = { }
        #endif
        """, kotlin: """
        var c: () -> Unit = { ->  }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var c: () -> Void {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer = try! Java_SourceKt.callStatic(method: Java_get_c_methodID, options: [], args: [])
                    return { let closure_swift = JavaBackedClosure<Void>(value_java, options: []); return { try! closure_swift.invoke() } }()
                }
            }
            set {
                jniContext {
                    let value_java = SwiftClosure0.javaObject(for: newValue, options: [])!.toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_set_c_methodID, options: [], args: [value_java])
                }
            }
        }
        private let Java_get_c_methodID = Java_SourceKt.getStaticMethodID(name: "getC", sig: "()Lkotlin/jvm/functions/Function0;")!
        private let Java_set_c_methodID = Java_SourceKt.getStaticMethodID(name: "setC", sig: "(Lkotlin/jvm/functions/Function0;)V")!
        """, transformers: transformers)
    }

    func testTupleVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public var t = ("s", 1)
        #endif
        """, kotlin: """
        var t = Tuple2("s", 1)
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var t: (String, Int) {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer = try! Java_SourceKt.callStatic(method: Java_get_t_methodID, options: [], args: [])
                    return SwiftTuple.tuple(forJavaObject: value_java, options: [])!
                }
            }
            set {
                jniContext {
                    let value_java = SwiftTuple.javaObject(for: newValue, options: [])!.toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_set_t_methodID, options: [], args: [value_java])
                }
            }
        }
        private let Java_get_t_methodID = Java_SourceKt.getStaticMethodID(name: "getT", sig: "()Lskip/lib/Tuple2;")!
        private let Java_set_t_methodID = Java_SourceKt.getStaticMethodID(name: "setT", sig: "(Lskip/lib/Tuple2;)V")!
        """, transformers: transformers)
    }

    func testAnyVar() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public var a: Any = 1
        #endif
        """, kotlin: """
        var a: Any = 1
            get() = field.sref({ a = it })
            set(newValue) {
                field = newValue.sref()
            }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var a: Any {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer = try! Java_SourceKt.callStatic(method: Java_get_a_methodID, options: [], args: [])
                    return AnyBridging.fromJavaObject(value_java, options: [])!
                }
            }
            set {
                jniContext {
                    let value_java = ((newValue as? JConvertible)?.toJavaObject(options: []))!.toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_set_a_methodID, options: [], args: [value_java])
                }
            }
        }
        private let Java_get_a_methodID = Java_SourceKt.getStaticMethodID(name: "getA", sig: "()Ljava/lang/Object;")!
        private let Java_set_a_methodID = Java_SourceKt.getStaticMethodID(name: "setA", sig: "(Ljava/lang/Object;)V")!
        """, transformers: transformers)
    }

    func testFunction() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public func f(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        #endif
        """, kotlin: """
        fun f(i: Int, s: String): Int = i + (Int(s) ?: 0)
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f(i p_0: Int, s p_1: String) -> Int {
            return jniContext {
                let p_0_java = Int32(p_0).toJavaParameter(options: [])
                let p_1_java = p_1.toJavaParameter(options: [])
                let f_return_java: Int32 = try! Java_SourceKt.callStatic(method: Java_f_0_methodID, options: [], args: [p_0_java, p_1_java])
                return Int(f_return_java)
            }
        }
        private let Java_f_0_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(ILjava/lang/String;)I")!
        """, transformers: transformers)
    }

    func testNoBridgeFunction() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        // SKIP @nobridge
        public func f(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        @BridgeIgnored
        public func g(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        #endif
        """, kotlin: """
        fun f(i: Int, s: String): Int = i + (Int(s) ?: 0)
        fun g(i: Int, s: String): Int = i + (Int(s) ?: 0)
        """, swiftBridgeSupport: """
        """, transformers: transformers)
    }

    func testPrivateFunction() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        private func f(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        private func g(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        #endif
        """, kotlin: """
        private fun f(i: Int, s: String): Int = i + (Int(s) ?: 0)
        private fun g(i: Int, s: String): Int = i + (Int(s) ?: 0)
        """, swiftBridgeSupport: """
        """, transformers: transformers)
    }

    func testThrowsFunction() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public func f() throws {
        }
        #endif
        """, kotlin: """
        fun f() = Unit
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f() throws {
            try jniContext {
                do {
                    try Java_SourceKt.callStatic(method: Java_f_0_methodID, options: [], args: [])
                } catch let error as (Error & JConvertible) {
                    throw error
                } catch {
                    fatalError(String(describing: error))
                }
            }
        }
        private let Java_f_0_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "()V")!
        """, transformers: transformers)
    }

    func testFunctionParameterLabel() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public func nolabel(_ i: Int) {
        }
        #endif
        """, kotlin: """
        fun nolabel(i: Int) = Unit
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func nolabel(_ p_0: Int) {
            jniContext {
                let p_0_java = Int32(p_0).toJavaParameter(options: [])
                try! Java_SourceKt.callStatic(method: Java_nolabel_0_methodID, options: [], args: [p_0_java])
            }
        }
        private let Java_nolabel_0_methodID = Java_SourceKt.getStaticMethodID(name: "nolabel", sig: "(I)V")!
        """, transformers: transformers)
    }

    func testFunctionParameterDefaultValue() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public func f(i: Int = 0) -> Int {
            return i
        }
        #endif
        """, kotlin: """
        fun f(i: Int = 0): Int = i
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f(i p_0: Int = 0) -> Int {
            return jniContext {
                let p_0_java = Int32(p_0).toJavaParameter(options: [])
                let f_return_java: Int32 = try! Java_SourceKt.callStatic(method: Java_f_0_methodID, options: [], args: [p_0_java])
                return Int(f_return_java)
            }
        }
        private let Java_f_0_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(I)I")!
        """, transformers: transformers)
    }

    func testFunctionParameterLabelOverload() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public func f(i: Int) -> Int {
            return i
        }
        public func f(value: Int) -> Int {
            return value
        }
        #endif
        """, kotlin: """
        fun f(i: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null): Int = i
        fun f(value: Int): Int = value
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f(i p_0: Int) -> Int {
            return jniContext {
                let p_0_java = Int32(p_0).toJavaParameter(options: [])
                let p_1_java = JavaParameter(l: nil)
                let f_return_java: Int32 = try! Java_SourceKt.callStatic(method: Java_f_0_methodID, options: [], args: [p_0_java, p_1_java])
                return Int(f_return_java)
            }
        }
        private let Java_f_0_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(ILjava/lang/Void;)I")!
        public func f(value p_0: Int) -> Int {
            return jniContext {
                let p_0_java = Int32(p_0).toJavaParameter(options: [])
                let f_return_java: Int32 = try! Java_SourceKt.callStatic(method: Java_f_1_methodID, options: [], args: [p_0_java])
                return Int(f_return_java)
            }
        }
        private let Java_f_1_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(I)I")!
        """, transformers: transformers)
    }

    func testKeywordFunction() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public func object(object: Int) {
        }
        #endif
        """, kotlin: """
        fun object_(object_: Int) = Unit
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func object(object p_0: Int) {
            jniContext {
                let p_0_java = Int32(p_0).toJavaParameter(options: [])
                try! Java_SourceKt.callStatic(method: Java_object__0_methodID, options: [], args: [p_0_java])
            }
        }
        private let Java_object__0_methodID = Java_SourceKt.getStaticMethodID(name: "object_", sig: "(I)V")!
        """, transformers: transformers)
    }

    func testOptionalFunction() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public func f(i: Int?) -> Int? {
            return nil
        }
        #endif
        """, kotlin: """
        fun f(i: Int?): Int? = null
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f(i p_0: Int?) -> Int? {
            return jniContext {
                let p_0_java = p_0.toJavaParameter(options: [])
                let f_return_java: JavaObjectPointer? = try! Java_SourceKt.callStatic(method: Java_f_0_methodID, options: [], args: [p_0_java])
                return Int?.fromJavaObject(f_return_java, options: [])
            }
        }
        private let Java_f_0_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(Ljava/lang/Integer;)Ljava/lang/Integer;")!
        """, transformers: transformers)
    }

    func testBridgedObjectFunction() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
        }
        public func f(c: C) -> C {
        }
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        fun f(c: C): C = Unit
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
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
        public func f(c p_0: C) -> C {
            return jniContext {
                let p_0_java = p_0.toJavaObject(options: [])!.toJavaParameter(options: [])
                let f_return_java: JavaObjectPointer = try! Java_SourceKt.callStatic(method: Java_f_0_methodID, options: [], args: [p_0_java])
                return C.fromJavaObject(f_return_java, options: [])
            }
        }
        private let Java_f_0_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(LC;)LC;")!
        """, transformers: transformers)
    }

    func testVariadicFunction() async throws {
        try await checkProducesMessage(swift: """
        public func f(i: Int...) { }
        """, transformers: transformers)
    }

    func testAsyncFunction() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public func f(i: Int) async -> Int {
            return i
        }
        #endif
        """, kotlin: """
        suspend fun f(i: Int): Int = Async.run l@{
            return@l i
        }
        fun callback_f(i: Int, f_return_callback: (Int) -> Unit) {
            Task {
                f_return_callback(f(i = i))
            }
        }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f(i p_0: Int) async -> Int {
            return await withCheckedContinuation { f_continuation in
                let f_return_callback: (Int) -> Void = { f_return in
                    f_continuation.resume(returning: f_return)
                }
                jniContext {
                    let f_return_callback_java = SwiftClosure1.javaObject(for: f_return_callback, options: []).toJavaParameter(options: [])
                    let p_0_java = Int32(p_0).toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_f_0_methodID, options: [], args: [p_0_java, f_return_callback_java])
                }
            }
        }
        private let Java_f_0_methodID = Java_SourceKt.getStaticMethodID(name: "callback_f", sig: "(ILkotlin/jvm/functions/Function1;)V")!
        """, transformers: transformers)
    }

    func testMainActorAsyncFunction() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        @MainActor
        public func f(i: Int) async -> Int {
            return i
        }
        #endif
        """, kotlin: """
        suspend fun f(i: Int): Int = MainActor.run l@{
            return@l i
        }
        fun callback_f(i: Int, f_return_callback: (Int) -> Unit) {
            Task {
                f_return_callback(f(i = i))
            }
        }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f(i p_0: Int) async -> Int {
            return await withCheckedContinuation { f_continuation in
                let f_return_callback: (Int) -> Void = { f_return in
                    f_continuation.resume(returning: f_return)
                }
                jniContext {
                    let f_return_callback_java = SwiftClosure1.javaObject(for: f_return_callback, options: []).toJavaParameter(options: [])
                    let p_0_java = Int32(p_0).toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_f_0_methodID, options: [], args: [p_0_java, f_return_callback_java])
                }
            }
        }
        private let Java_f_0_methodID = Java_SourceKt.getStaticMethodID(name: "callback_f", sig: "(ILkotlin/jvm/functions/Function1;)V")!
        """, transformers: transformers)
    }

    func testAsyncVoidFunction() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public func f() async {
        }
        #endif
        """, kotlin: """
        suspend fun f(): Unit = Unit
        fun callback_f(f_return_callback: () -> Unit) {
            Task {
                f()
                f_return_callback()
            }
        }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f() async {
            await withCheckedContinuation { f_continuation in
                let f_return_callback: () -> Void = {
                    f_continuation.resume()
                }
                jniContext {
                    let f_return_callback_java = SwiftClosure0.javaObject(for: f_return_callback, options: []).toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_f_0_methodID, options: [], args: [f_return_callback_java])
                }
            }
        }
        private let Java_f_0_methodID = Java_SourceKt.getStaticMethodID(name: "callback_f", sig: "(Lkotlin/jvm/functions/Function0;)V")!
        """, transformers: transformers)
    }

    func testAsyncThrowsFunction() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public func f() async throws -> Int {
            return 1
        }
        #endif
        """, kotlin: """
        suspend fun f(): Int = Async.run l@{
            return@l 1
        }
        fun callback_f(f_return_callback: (Int?, Throwable?) -> Unit) {
            Task {
                try {
                    f_return_callback(f(), null)
                } catch(t: Throwable) {
                    f_return_callback(null, t)
                }
            }
        }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f() async throws -> Int {
            return try await withCheckedThrowingContinuation { f_continuation in
                let f_return_callback: (Int?, JavaObjectPointer?) -> Void = { f_return, f_error in
                    if let f_error {
                        f_continuation.resume(throwing: JThrowable.toError(f_error, options: []))
                    } else {
                        f_continuation.resume(returning: f_return!)
                    }
                }
                jniContext {
                    let f_return_callback_java = SwiftClosure2.javaObject(for: f_return_callback, options: []).toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_f_0_methodID, options: [], args: [f_return_callback_java])
                }
            }
        }
        private let Java_f_0_methodID = Java_SourceKt.getStaticMethodID(name: "callback_f", sig: "(Lkotlin/jvm/functions/Function2;)V")!
        """, transformers: transformers)
    }

    func testAsyncThrowsVoidFunction() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public func f(i: Int) async throws {
        }
        #endif
        """, kotlin: """
        suspend fun f(i: Int): Unit = Unit
        fun callback_f(i: Int, f_return_callback: (Throwable?) -> Unit) {
            Task {
                try {
                    f(i = i)
                    f_return_callback(null)
                } catch(t: Throwable) {
                    f_return_callback(t)
                }
            }
        }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f(i p_0: Int) async throws {
            return try await withCheckedThrowingContinuation { f_continuation in
                let f_return_callback: (JavaObjectPointer?) -> Void = { f_error in
                    if let f_error {
                        f_continuation.resume(throwing: JThrowable.toError(f_error, options: []))
                    } else {
                        f_continuation.resume()
                    }
                }
                jniContext {
                    let f_return_callback_java = SwiftClosure1.javaObject(for: f_return_callback, options: []).toJavaParameter(options: [])
                    let p_0_java = Int32(p_0).toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_f_0_methodID, options: [], args: [p_0_java, f_return_callback_java])
                }
            }
        }
        private let Java_f_0_methodID = Java_SourceKt.getStaticMethodID(name: "callback_f", sig: "(ILkotlin/jvm/functions/Function1;)V")!
        """, transformers: transformers)
    }

    func testClass() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
            public var i = 1
        }
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
            var i = 1
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
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
        try await check(swift: """
        #if !SKIP_BRIDGE
        open class C {
            open func f() {
            }
        }
        #endif
        """, kotlin: """
        open class C: skip.lib.SwiftProjecting {
            open fun f() = Unit
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        open class C: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "C")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public init(Java_peer: JObject) {
                self.Java_peer = Java_peer
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
        
            open func f() {
                jniContext {
                    try! Java_peer.call(method: Self.Java_f_0_methodID, options: [], args: [])
                }
            }
            private static let Java_f_0_methodID = Java_class.getMethodID(name: "f", sig: "()V")!
        }
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testNoBridgeClass() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        // SKIP @nobridge
        public class C {
        }
        @BridgeIgnored
        public class D {
        }
        #endif
        """, kotlin: """
        open class C {
        
            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        open class D {
        
            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        """, transformers: transformers)
    }

    func testPrivateClass() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        private class C {
        }
        class D {
        }
        #endif
        """, kotlin: """
        private open class C {
        }
        internal open class D {
        }
        """, swiftBridgeSupport: """
        """, transformers: transformers)
    }

    func testInnerClass() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public enum A {
            public final class B {
                public struct C {
                    public var b = B()
                }
            }
        }
        #endif
        """, kotlin: """
        enum class A: skip.lib.SwiftProjecting {
            ;
            class B: skip.lib.SwiftProjecting {
                @Suppress("MUST_BE_INITIALIZED")
                class C: MutableStruct, skip.lib.SwiftProjecting {
                    var b: A.B
                        set(newValue) {
                            willmutate()
                            field = newValue
                            didmutate()
                        }
        
                    constructor(b: A.B = B()) {
                        this.b = b
                    }
        
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
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
        public enum A: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "A")
            private var Java_peer: JavaObjectPointer {
                return toJavaObject(options: [])!
            }
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let name: String = try! obj!.call(method: Java_name_methodID, options: options, args: [])
                return fromJavaName(name)
            }
            fileprivate static func fromJavaName(_ name: String) -> Self {
                fatalError()
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                fatalError()
            }
            private static let Java_name_methodID = Java_class.getMethodID(name: "name", sig: "()Ljava/lang/String;")!
        }
        @_cdecl("Java_A_Swift_1projectionImpl")
        func A_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = A.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        extension A {
            public final class B: BridgedFromKotlin, BridgedFinalClass {
                private static let Java_class = try! JClass(name: "A$B")
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
        }
        @_cdecl("Java_A_00024B_Swift_1projectionImpl")
        func A$B_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = A.B.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        extension A.B {
            public struct C: BridgedFromKotlin {
                private static let Java_class = try! JClass(name: "A$B$C")
                public var Java_peer: JObject
                public init(Java_ptr: JavaObjectPointer) {
                    Java_peer = JObject(Java_ptr)
                }
                private static let Java_scopy_methodID = Java_class.getMethodID(name: "scopy", sig: "()Lskip/lib/MutableStruct;")!
                public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                    return .init(Java_ptr: obj!)
                }
                public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                    return Java_peer.safePointer()
                }
        
                public var b: A.B {
                    get {
                        return jniContext {
                            let value_java: JavaObjectPointer = try! Java_peer.call(method: Self.Java_get_b_methodID, options: [], args: [])
                            return A.B.fromJavaObject(value_java, options: [])
                        }
                    }
                    set {
                        jniContext {
                            Java_peer = try! JObject(Java_peer.call(method: Self.Java_scopy_methodID, options: [], args: []))
                            let value_java = newValue.toJavaObject(options: [])!.toJavaParameter(options: [])
                            try! Java_peer.call(method: Self.Java_set_b_methodID, options: [], args: [value_java])
                        }
                    }
                }
                private static let Java_get_b_methodID = Java_class.getMethodID(name: "getB", sig: "()LA$B;")!
                private static let Java_set_b_methodID = Java_class.getMethodID(name: "setB", sig: "(LA$B;)V")!
        
                public init(b p_0: A.B) {
                    Java_peer = jniContext {
                        let p_0_java = p_0.toJavaObject(options: [])!.toJavaParameter(options: [])
                        let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_0_methodID, options: [], args: [p_0_java])
                        return JObject(ptr)
                    }
                }
                private static let Java_constructor_0_methodID = Java_class.getMethodID(name: "<init>", sig: "(LA$B;)V")!
            }
        }
        @_cdecl("Java_A_00024B_00024C_Swift_1projectionImpl")
        func A$B$C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = A.B.C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testPrivateConstructor() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
            private init(i: Int) {
            }
        }
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
            private constructor(i: Int) {
            }
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
        public final class C: BridgedFromKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
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
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testConstructor() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
            public init(i: Int) {
            }
        }
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
            constructor(i: Int) {
            }
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
        public final class C: BridgedFromKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
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
        
            public init(i p_0: Int) {
                Java_peer = jniContext {
                    let p_0_java = Int32(p_0).toJavaParameter(options: [])
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_0_methodID, options: [], args: [p_0_java])
                    return JObject(ptr)
                }
            }
            private static let Java_constructor_0_methodID = Java_class.getMethodID(name: "<init>", sig: "(I)V")!
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
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
            public init(i: Int) throws {
            }
        }
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
            constructor(i: Int) {
            }
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
        public final class C: BridgedFromKotlin, BridgedFinalClass {
            private static let Java_class = try! JClass(name: "C")
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
        
            public init(i p_0: Int) throws {
                Java_peer = try jniContext {
                    let p_0_java = Int32(p_0).toJavaParameter(options: [])
                    let ptr = try Self.Java_class.create(ctor: Self.Java_constructor_0_methodID, options: [], args: [p_0_java])
                    return JObject(ptr)
                }
            }
            private static let Java_constructor_0_methodID = Java_class.getMethodID(name: "<init>", sig: "(I)V")!
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
            }
        }
        """, transformers: transformers)
    }

    func testDestructor() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
            deinit {
            }
        }
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
            fun finalize() = Unit
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
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
        """, transformers: transformers)
    }

    func testMemberConstant() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
            public let i = 0
        }
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
            val i = 0
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
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
        
            public let i: Int = 0
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
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
            public var i = 0
        }
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
            var i = 0
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
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
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
            public func add(a: Int, b: Int) -> Int {
                return a + b
            }
        }
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
            fun add(a: Int, b: Int): Int = a + b
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
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
        
            public func add(a p_0: Int, b p_1: Int) -> Int {
                return jniContext {
                    let p_0_java = Int32(p_0).toJavaParameter(options: [])
                    let p_1_java = Int32(p_1).toJavaParameter(options: [])
                    let f_return_java: Int32 = try! Java_peer.call(method: Self.Java_add_0_methodID, options: [], args: [p_0_java, p_1_java])
                    return Int(f_return_java)
                }
            }
            private static let Java_add_0_methodID = Java_class.getMethodID(name: "add", sig: "(II)I")!
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
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
            public func add() async -> Int {
                return 1
            }
        }
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
            suspend fun add(): Int = Async.run l@{
                return@l 1
            }
            fun callback_add(f_return_callback: (Int) -> Unit) {
                Task {
                    f_return_callback(add())
                }
            }
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
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
        
            public func add() async -> Int {
                return await withCheckedContinuation { f_continuation in
                    let f_return_callback: (Int) -> Void = { f_return in
                        f_continuation.resume(returning: f_return)
                    }
                    jniContext {
                        let f_return_callback_java = SwiftClosure1.javaObject(for: f_return_callback, options: []).toJavaParameter(options: [])
                        try! Java_peer.call(method: Self.Java_add_0_methodID, options: [], args: [f_return_callback_java])
                    }
                }
            }
            private static let Java_add_0_methodID = Java_class.getMethodID(name: "callback_add", sig: "(Lkotlin/jvm/functions/Function1;)V")!
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
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
            public static let i = 0
        }
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
                val i = 0
            }
        }
        """, swiftBridgeSupport: """
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
        
            public static let i: Int = 0
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
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
            public static var i = 0
        }
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
                var i = 0
            }
        }
        """, swiftBridgeSupport: """
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
            private static let Java_Companion_class = try! JClass(name: "C$Companion")
            private static let Java_Companion = JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: "Companion", sig: "LC$Companion;")!, options: []))
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        
            public static var i: Int {
                get {
                    return jniContext {
                        let value_java: Int32 = try! Java_Companion.call(method: Java_Companion_get_i_methodID, options: [], args: [])
                        return Int(value_java)
                    }
                }
                set {
                    jniContext {
                        let value_java = Int32(newValue).toJavaParameter(options: [])
                        try! Java_Companion.call(method: Java_Companion_set_i_methodID, options: [], args: [value_java])
                    }
                }
            }
            private static let Java_Companion_get_i_methodID = Java_Companion_class.getMethodID(name: "getI", sig: "()I")!
            private static let Java_Companion_set_i_methodID = Java_Companion_class.getMethodID(name: "setI", sig: "(I)V")!
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
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
            public static func add(a: Int, b: Int) -> Int {
                return a + b
            }
        }
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
                fun add(a: Int, b: Int): Int = a + b
            }
        }
        """, swiftBridgeSupport: """
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
            private static let Java_Companion_class = try! JClass(name: "C$Companion")
            private static let Java_Companion = JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: "Companion", sig: "LC$Companion;")!, options: []))
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        
            public static func add(a p_0: Int, b p_1: Int) -> Int {
                return jniContext {
                    let p_0_java = Int32(p_0).toJavaParameter(options: [])
                    let p_1_java = Int32(p_1).toJavaParameter(options: [])
                    let f_return_java: Int32 = try! Java_Companion.call(method: Java_Companion_add_0_methodID, options: [], args: [p_0_java, p_1_java])
                    return Int(f_return_java)
                }
            }
            private static let Java_Companion_add_0_methodID = Java_Companion_class.getMethodID(name: "add", sig: "(II)I")!
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
        """, transformers: transformers)
    }

    func testUnbridgedMember() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
            @BridgeIgnored
            public var i = 1
        }
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
            var i = 1
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
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
        """, transformers: transformers)
    }

    func testCommonProtocols() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C: Equatable, Hashable, Comparable {
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
        #endif
        """, kotlin: """
        class C: Comparable<C>, skip.lib.SwiftProjecting {
            var i = 1
            override fun equals(other: Any?): Boolean {
                if (other !is C) {
                    return false
                }
                val lhs = this
                val rhs = other
                return lhs.i == rhs.i
            }
            override fun hashCode(): Int {
                var hasher = Hasher()
                hash(into = InOut<Hasher>({ hasher }, { hasher = it }))
                return hasher.finalize()
            }
            fun hash(into: InOut<Hasher>) {
                val hasher = into
                hasher.value.combine(i)
            }
            override fun compareTo(other: C): Int {
                if (this == other) return 0
                fun islessthan(lhs: C, rhs: C): Boolean {
                    return lhs.i < rhs.i
                }
                return if (islessthan(this, other)) -1 else 1
            }
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
        public final class C: Equatable, Hashable, Comparable, BridgedFromKotlin, BridgedFinalClass {
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
        
            public static func ==(lhs: C, rhs: C) -> Bool {
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
        
            public static func <(lhs: C, rhs: C) -> Bool {
                return jniContext {
                    let lhs_java = lhs.toJavaObject(options: [])!
                    let rhs_java = rhs.toJavaParameter(options: [])
                    let f_return_java = try! Int32.call(Java_compareTo_methodID, on: lhs_java, options: [], args: [rhs_java])
                    return f_return_java < 0
                }
            }
            private static let Java_compareTo_methodID = Java_class.getMethodID(name: "compareTo", sig: "(Ljava/lang/Object;)I")!
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
        try await check(swift: """
        #if !SKIP_BRIDGE
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
        #endif
        """, kotlin: """
        class C: Codable, skip.lib.SwiftProjecting {
            var i = 1
        
            private enum class CK(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                i("i");
        
                companion object {
                    fun init(rawValue: String): C.CK? {
                        return when (rawValue) {
                            "i" -> CK.i
                            else -> null
                        }
                    }
                }
            }
        
            fun encode(to: Encoder) = Unit
        
            constructor(from: Decoder) {
            }
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
        
                private fun CK(rawValue: String): C.CK? = CK.init(rawValue = rawValue)
            }
        }
        """, swiftBridgeSupport: """
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
        try await check(swift: """
        #if !SKIP_BRIDGE
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
        public class Sub2: Base {
        }
        public var base: Base = Sub2(i: 1)
        #endif
        """, kotlin: """
        open class Base: skip.lib.SwiftProjecting {
            open var i = 0
        
            constructor(i: Int) {
                this.i = i
            }
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        open class Sub1: Base {
            open var s = ""
        
            constructor(i: Int, s: String): super(i = i) {
                this.s = s
            }
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object: CompanionClass() {
            }
            open class CompanionClass: Base.CompanionClass() {
            }
        }
        open class Sub2: Base {
        
            constructor(i: Int): super(i) {
            }
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object: CompanionClass() {
            }
            open class CompanionClass: Base.CompanionClass() {
            }
        }
        var base: Base = Sub2(i = 1)
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public class Base: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "Base")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public init(Java_peer: JObject) {
                self.Java_peer = Java_peer
            }
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
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
        
            public init(i p_0: Int) {
                Java_peer = jniContext {
                    let p_0_java = Int32(p_0).toJavaParameter(options: [])
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_0_methodID, options: [], args: [p_0_java])
                    return JObject(ptr)
                }
            }
            private static let Java_constructor_0_methodID = Java_class.getMethodID(name: "<init>", sig: "(I)V")!
        }
        @_cdecl("Java_Base_Swift_1projectionImpl")
        func Base_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = Base.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        public class Sub1: Base {
            private static let Java_class = try! JClass(name: "Sub1")
            public required init(Java_ptr: JavaObjectPointer) {
                super.init(Java_ptr: Java_ptr)
            }
            public init(Java_peer: JObject) {
                super.init(Java_peer: Java_peer)
            }
        
            public var s: String {
                get {
                    return jniContext {
                        let value_java: String = try! Java_peer.call(method: Self.Java_get_s_methodID, options: [], args: [])
                        return value_java
                    }
                }
                set {
                    jniContext {
                        let value_java = newValue.toJavaParameter(options: [])
                        try! Java_peer.call(method: Self.Java_set_s_methodID, options: [], args: [value_java])
                    }
                }
            }
            private static let Java_get_s_methodID = Java_class.getMethodID(name: "getS", sig: "()Ljava/lang/String;")!
            private static let Java_set_s_methodID = Java_class.getMethodID(name: "setS", sig: "(Ljava/lang/String;)V")!
        
            public init(i p_0: Int, s p_1: String) {
                let Java_peer = jniContext {
                    let p_0_java = Int32(p_0).toJavaParameter(options: [])
                    let p_1_java = p_1.toJavaParameter(options: [])
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_0_methodID, options: [], args: [p_0_java, p_1_java])
                    return JObject(ptr)
                }
                super.init(Java_peer: Java_peer)
            }
            private static let Java_constructor_0_methodID = Java_class.getMethodID(name: "<init>", sig: "(ILjava/lang/String;)V")!
        }
        @_cdecl("Java_Sub1_Swift_1projectionImpl")
        func Sub1_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = Sub1.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        public class Sub2: Base {
            private static let Java_class = try! JClass(name: "Sub2")
            public required init(Java_ptr: JavaObjectPointer) {
                super.init(Java_ptr: Java_ptr)
            }
            public init(Java_peer: JObject) {
                super.init(Java_peer: Java_peer)
            }
        
            public init(i p_0: Int) {
                let Java_peer = jniContext {
                    let p_0_java = Int32(p_0).toJavaParameter(options: [])
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_0_methodID, options: [], args: [p_0_java])
                    return JObject(ptr)
                }
                super.init(Java_peer: Java_peer)
            }
            private static let Java_constructor_0_methodID = Java_class.getMethodID(name: "<init>", sig: "(I)V")!
        }
        @_cdecl("Java_Sub2_Swift_1projectionImpl")
        func Sub2_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = Sub2.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        public var base: Base {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer = try! Java_SourceKt.callStatic(method: Java_get_base_methodID, options: [], args: [])
                    return AnyBridging.fromJavaObject(value_java, toBaseType: Base.self, options: [])!
                }
            }
            set {
                jniContext {
                    let value_java = newValue.toJavaObject(options: [])!.toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_set_base_methodID, options: [], args: [value_java])
                }
            }
        }
        private let Java_get_base_methodID = Java_SourceKt.getStaticMethodID(name: "getBase", sig: "()LBase;")!
        private let Java_set_base_methodID = Java_SourceKt.getStaticMethodID(name: "setBase", sig: "(LBase;)V")!
        """, transformers: transformers)
    }

    func testSubclassOfBridgedNoConstructors() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public class Base {
        }
        public class Sub: Base {
        }
        #endif
        """, kotlin: """
        open class Base: skip.lib.SwiftProjecting {
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        open class Sub: Base() {
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object: CompanionClass() {
            }
            open class CompanionClass: Base.CompanionClass() {
            }
        }
        """, swiftBridgeSupport: """
        public class Base: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "Base")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public init(Java_peer: JObject) {
                self.Java_peer = Java_peer
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
        @_cdecl("Java_Base_Swift_1projectionImpl")
        func Base_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = Base.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        public class Sub: Base {
            private static let Java_class = try! JClass(name: "Sub")
            public required init(Java_ptr: JavaObjectPointer) {
                super.init(Java_ptr: Java_ptr)
            }
            public init(Java_peer: JObject) {
                super.init(Java_peer: Java_peer)
            }
            public init() {
                let Java_peer = jniContext {
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: [], args: [])
                    return JObject(ptr)
                }
                super.init(Java_peer: Java_peer)
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "()V")!
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
        try await check(swift: """
        #if !SKIP_BRIDGE
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
        public class Sub2: Base {
        }
        public var sub1 = Sub1()
        #endif
        """, kotlin: """
        open class Base {
            open var i = 0
        
            constructor(i: Int) {
                this.i = i
            }
        
            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        open class Sub1: Base, skip.lib.SwiftProjecting {
            open var s = ""
        
            constructor(i: Int, s: String): super(i = i) {
                this.s = s
            }
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object: CompanionClass() {
            }
            open class CompanionClass: Base.CompanionClass() {
            }
        }
        open class Sub2: Base, skip.lib.SwiftProjecting {
        
            constructor(i: Int): super(i) {
            }
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object: CompanionClass() {
            }
            open class CompanionClass: Base.CompanionClass() {
            }
        }
        var sub1 = Sub1()
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public class Sub1: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "Sub1")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public init(Java_peer: JObject) {
                self.Java_peer = Java_peer
            }
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        
            public var s: String {
                get {
                    return jniContext {
                        let value_java: String = try! Java_peer.call(method: Self.Java_get_s_methodID, options: [], args: [])
                        return value_java
                    }
                }
                set {
                    jniContext {
                        let value_java = newValue.toJavaParameter(options: [])
                        try! Java_peer.call(method: Self.Java_set_s_methodID, options: [], args: [value_java])
                    }
                }
            }
            private static let Java_get_s_methodID = Java_class.getMethodID(name: "getS", sig: "()Ljava/lang/String;")!
            private static let Java_set_s_methodID = Java_class.getMethodID(name: "setS", sig: "(Ljava/lang/String;)V")!
        
            public init(i p_0: Int, s p_1: String) {
                Java_peer = jniContext {
                    let p_0_java = Int32(p_0).toJavaParameter(options: [])
                    let p_1_java = p_1.toJavaParameter(options: [])
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_0_methodID, options: [], args: [p_0_java, p_1_java])
                    return JObject(ptr)
                }
            }
            private static let Java_constructor_0_methodID = Java_class.getMethodID(name: "<init>", sig: "(ILjava/lang/String;)V")!
        }
        @_cdecl("Java_Sub1_Swift_1projectionImpl")
        func Sub1_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = Sub1.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        public class Sub2: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "Sub2")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public init(Java_peer: JObject) {
                self.Java_peer = Java_peer
            }
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        
            public init(i p_0: Int) {
                Java_peer = jniContext {
                    let p_0_java = Int32(p_0).toJavaParameter(options: [])
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_0_methodID, options: [], args: [p_0_java])
                    return JObject(ptr)
                }
            }
            private static let Java_constructor_0_methodID = Java_class.getMethodID(name: "<init>", sig: "(I)V")!
        }
        @_cdecl("Java_Sub2_Swift_1projectionImpl")
        func Sub2_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = Sub2.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        public var sub1: Sub1 {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer = try! Java_SourceKt.callStatic(method: Java_get_sub1_methodID, options: [], args: [])
                    return AnyBridging.fromJavaObject(value_java, toBaseType: Sub1.self, options: [])!
                }
            }
            set {
                jniContext {
                    let value_java = newValue.toJavaObject(options: [])!.toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_set_sub1_methodID, options: [], args: [value_java])
                }
            }
        }
        private let Java_get_sub1_methodID = Java_SourceKt.getStaticMethodID(name: "getSub1", sig: "()LSub1;")!
        private let Java_set_sub1_methodID = Java_SourceKt.getStaticMethodID(name: "setSub1", sig: "(LSub1;)V")!
        """, transformers: transformers)
    }

    func testStruct() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public struct S {
            public var i = 1
            public init(_ s: String) {
                self.i = Int(s) ?? 0
            }
            public mutating func inc() {
                i += 1
            }
        }
        #endif
        """, kotlin: """
        class S: MutableStruct, skip.lib.SwiftProjecting {
            var i = 1
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }
            constructor(s: String) {
                this.i = Int(s) ?: 0
            }
            fun inc() {
                willmutate()
                try {
                    i += 1
                } finally {
                    didmutate()
                }
            }
        
            private constructor(copy: MutableStruct) {
                @Suppress("NAME_SHADOWING", "UNCHECKED_CAST") val copy = copy as S
                this.i = copy.i
            }
        
            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(this as MutableStruct)
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
        public struct S: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "S")
            public var Java_peer: JObject
            public init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            private static let Java_scopy_methodID = Java_class.getMethodID(name: "scopy", sig: "()Lskip/lib/MutableStruct;")!
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
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
                        Java_peer = try! JObject(Java_peer.call(method: Self.Java_scopy_methodID, options: [], args: []))
                        let value_java = Int32(newValue).toJavaParameter(options: [])
                        try! Java_peer.call(method: Self.Java_set_i_methodID, options: [], args: [value_java])
                    }
                }
            }
            private static let Java_get_i_methodID = Java_class.getMethodID(name: "getI", sig: "()I")!
            private static let Java_set_i_methodID = Java_class.getMethodID(name: "setI", sig: "(I)V")!
        
            public init(_ p_0: String) {
                Java_peer = jniContext {
                    let p_0_java = p_0.toJavaParameter(options: [])
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_0_methodID, options: [], args: [p_0_java])
                    return JObject(ptr)
                }
            }
            private static let Java_constructor_0_methodID = Java_class.getMethodID(name: "<init>", sig: "(Ljava/lang/String;)V")!
        
            public mutating func inc() {
                jniContext {
                    Java_peer = try! JObject(Java_peer.call(method: Self.Java_scopy_methodID, options: [], args: []))
                    try! Java_peer.call(method: Self.Java_inc_1_methodID, options: [], args: [])
                }
            }
            private static let Java_inc_1_methodID = Java_class.getMethodID(name: "inc", sig: "()V")!
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
        try await check(swift: """
        #if !SKIP_BRIDGE
        public struct S {
            public var i: Int
            let s: String
        }
        #endif
        """, kotlin: """
        @Suppress("MUST_BE_INITIALIZED")
        class S: MutableStruct, skip.lib.SwiftProjecting {
            var i: Int
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }
            internal val s: String

            internal constructor(i: Int, s: String) {
                this.i = i
                this.s = s
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(i, s)

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        public struct S: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "S")
            public var Java_peer: JObject
            public init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            private static let Java_scopy_methodID = Java_class.getMethodID(name: "scopy", sig: "()Lskip/lib/MutableStruct;")!
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
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
                        Java_peer = try! JObject(Java_peer.call(method: Self.Java_scopy_methodID, options: [], args: []))
                        let value_java = Int32(newValue).toJavaParameter(options: [])
                        try! Java_peer.call(method: Self.Java_set_i_methodID, options: [], args: [value_java])
                    }
                }
            }
            private static let Java_get_i_methodID = Java_class.getMethodID(name: "getI", sig: "()I")!
            private static let Java_set_i_methodID = Java_class.getMethodID(name: "setI", sig: "(I)V")!
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
        try await check(swift: """
        #if !SKIP_BRIDGE
        @BridgeIgnored
        public protocol Unbridged {
        }
        public protocol P: Unbridged {
            var i: Int { get set }
            func f() -> Int
        }
        public final class C: P {
            public func f() {
                return 1
            }
        }
        #endif
        """, kotlin: """
        interface Unbridged {
        }
        interface P: Unbridged {
            var i: Int
            fun f(): Int
        }
        class C: P, skip.lib.SwiftProjecting {
            override fun f(): Unit = 1
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
        public protocol P {
        
            var i: Int { get set }
        
            func f() -> Int
        }
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
            public func f() -> Int {
                return jniContext {
                    let f_return_java: Int32 = try! Java_peer.call(method: Self.Java_f_0_methodID, options: [], args: [])
                    return Int(f_return_java)
                }
            }
            private static let Java_f_0_methodID = Java_class.getMethodID(name: "f", sig: "()I")!
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        public final class C: P, BridgedFromKotlin, BridgedFinalClass {
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
        
            public func f() {
                jniContext {
                    try! Java_peer.call(method: Self.Java_f_0_methodID, options: [], args: [])
                }
            }
            private static let Java_f_0_methodID = Java_class.getMethodID(name: "f", sig: "()V")!
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
        try await check(swift: """
        #if !SKIP_BRIDGE
        public protocol P {
        }
        public final class C {
            public var p: (any P)?
            public func f(p: any P) -> (any P)? {
                return nil
            }
        }
        #endif
        """, kotlin: """
        interface P {
        }
        class C: skip.lib.SwiftProjecting {
            var p: P? = null
                get() = field.sref({ this.p = it })
                set(newValue) {
                    field = newValue.sref()
                }
            fun f(p: P): P? = null
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
        public protocol P {
        }
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
        
            public var p: (any P)? {
                get {
                    return jniContext {
                        let value_java: JavaObjectPointer? = try! Java_peer.call(method: Self.Java_get_p_methodID, options: [], args: [])
                        return AnyBridging.fromJavaObject(value_java, options: []) { P_BridgeImpl?.fromJavaObject(value_java, options: []) as Any } as! (any P)?
                    }
                }
                set {
                    jniContext {
                        let value_java = ((newValue as? JConvertible)?.toJavaObject(options: [])).toJavaParameter(options: [])
                        try! Java_peer.call(method: Self.Java_set_p_methodID, options: [], args: [value_java])
                    }
                }
            }
            private static let Java_get_p_methodID = Java_class.getMethodID(name: "getP", sig: "()LP;")!
            private static let Java_set_p_methodID = Java_class.getMethodID(name: "setP", sig: "(LP;)V")!
        
            public func f(p p_0: (any P)) -> (any P)? {
                return jniContext {
                    let p_0_java = ((p_0 as? JConvertible)?.toJavaObject(options: []))!.toJavaParameter(options: [])
                    let f_return_java: JavaObjectPointer? = try! Java_peer.call(method: Self.Java_f_0_methodID, options: [], args: [p_0_java])
                    return AnyBridging.fromJavaObject(f_return_java, options: []) { P_BridgeImpl?.fromJavaObject(f_return_java, options: []) as Any } as! (any P)?
                }
            }
            private static let Java_f_0_methodID = Java_class.getMethodID(name: "f", sig: "(LP;)LP;")!
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
        """, transformers: transformers)
    }

    func testEnum() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
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
        #endif
        """, kotlin: """
        enum class E(override val rawValue: Int, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): RawRepresentable<Int>, skip.lib.SwiftProjecting {
            a(100),
            b(101);
        
            val string: String
                get() {
                    when (this) {
                        E.a -> return "a"
                        E.b -> return "b"
                    }
                }
        
            fun negate(): Int = this.rawValue * -1
        
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
        
                fun init(string: String): E {
                    when (string) {
                        "a" -> return E.a
                        else -> return E.b
                    }
                }
            }
        }
        fun E(string: String): E = E.init(string = string)
        
        fun E(rawValue: Int): E? = E.init(rawValue = rawValue)
        """, swiftBridgeSupport: """
        public enum E: Int, BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "E")
            private var Java_peer: JavaObjectPointer {
                return toJavaObject(options: [])!
            }
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
        
            case `a` = 100
        
            case `b`
        
            public var string: String {
                get {
                    return jniContext {
                        let value_java: String = try! Java_peer.call(method: Self.Java_get_string_methodID, options: [], args: [])
                        return value_java
                    }
                }
            }
            private static let Java_get_string_methodID = Java_class.getMethodID(name: "getString", sig: "()Ljava/lang/String;")!
        
            public func negate() -> Int {
                return jniContext {
                    let f_return_java: Int32 = try! Java_peer.call(method: Self.Java_negate_0_methodID, options: [], args: [])
                    return Int(f_return_java)
                }
            }
            private static let Java_negate_0_methodID = Java_class.getMethodID(name: "negate", sig: "()I")!
        
            public init(string p_0: String) {
                self = jniContext {
                    let p_0_java = p_0.toJavaParameter(options: [])
                    let f_return_java: JavaObjectPointer = try! Self.Java_Companion.call(method: Self.Java_Companion_init_1_methodID, options: [], args: [p_0_java])
                    return Self.fromJavaObject(f_return_java, options: [])
                }
            }
            private static let Java_Companion_init_1_methodID = Java_Companion_class.getMethodID(name: "init", sig: "(Ljava/lang/String;)LE;")!
        }
        @_cdecl("Java_E_Swift_1projectionImpl")
        func E_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = E.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testEnumWithAssociatedValue() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public enum E {
            case a(i: Int, String), b
            public var intValue: Int? {
                switch self {
                case .a(let value, _):
                    return value
                case .b:
                    return nil
            }
        }
        #endif
        """, kotlin: """
        sealed class E: skip.lib.SwiftProjecting {
            class ACase(val associated0: Int, val associated1: String): E() {
                val i = associated0
            }
            class BCase: E() {
            }
            val intValue: Int?
                get() {
                    when (this) {
                        is E.ACase -> {
                            val value = this.associated0
                            return value
                        }
                        is E.BCase -> return null
                    }
                }
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
                fun a(i: Int, associated1: String): E = ACase(i, associated1)
                val b: E = BCase()
            }
        }
        """, swiftBridgeSupport: """
        public enum E: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "E")
            private var Java_peer: JavaObjectPointer {
                return toJavaObject(options: [])!
            }
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
        
            case `a`(i: Int, String)
        
            case `b`
        
            public var intValue: Int? {
                get {
                    return jniContext {
                        let value_java: JavaObjectPointer? = try! Java_peer.call(method: Self.Java_get_intValue_methodID, options: [], args: [])
                        return Int?.fromJavaObject(value_java, options: [])
                    }
                }
            }
            private static let Java_get_intValue_methodID = Java_class.getMethodID(name: "getIntValue", sig: "()Ljava/lang/Integer;")!
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
        try await check(swift: """
        #if !SKIP_BRIDGE
        public class C {
        }
        extension C {
            public static func s() {
            }
            public func f() {
            }
            func g() {
            }
        }
        #endif
        """, kotlin: """
        open class C: skip.lib.SwiftProjecting {
            open fun f() = Unit
            internal open fun g() = Unit
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object: CompanionClass() {
        
                override fun s() = Unit
            }
            open class CompanionClass {
                open fun s() = C.s()
            }
        }
        """, swiftBridgeSupport: """
        public class C: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "C")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public init(Java_peer: JObject) {
                self.Java_peer = Java_peer
            }
            public init() {
                Java_peer = jniContext {
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: [], args: [])
                    return JObject(ptr)
                }
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "()V")!
            private static let Java_Companion_class = try! JClass(name: "C$Companion")
            private static let Java_Companion = JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: "Companion", sig: "LC$Companion;")!, options: []))
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        
            public static func s() {
                jniContext {
                    try! Java_Companion.call(method: Java_Companion_s_0_methodID, options: [], args: [])
                }
            }
            private static let Java_Companion_s_0_methodID = Java_Companion_class.getMethodID(name: "s", sig: "()V")!
        
            public func f() {
                jniContext {
                    try! Java_peer.call(method: Self.Java_f_1_methodID, options: [], args: [])
                }
            }
            private static let Java_f_1_methodID = Java_class.getMethodID(name: "f", sig: "()V")!
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
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
        }
        public extension C {
            func f() {
            }
        }
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
        
            open fun f() = Unit
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
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
        
            public func f() {
                jniContext {
                    try! Java_peer.call(method: Self.Java_f_0_methodID, options: [], args: [])
                }
            }
            private static let Java_f_0_methodID = Java_class.getMethodID(name: "f", sig: "()V")!
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
        try await check(swift: """
        #if !SKIP_BRIDGE
        public final class C {
        }
        // SKIP @nobridge
        extension C {
            public func f() {
            }
        }
        #endif
        """, kotlin: """
        class C: skip.lib.SwiftProjecting {
        
            open fun f() = Unit
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
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
        """, transformers: transformers)
    }

    func testExtensionFunction() async throws {
        try await checkProducesMessage(swift: """
        #if !SKIP_BRIDGE
        extension Int {
            public var zero: Int {
                return 0
            }
        }
        #endif
        """, transformers: transformers)
    }

    func testActor() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
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
        #endif
        """, kotlin: """
        class A: Actor, skip.lib.SwiftProjecting {
            override val isolatedContext = Actor.isolatedContext()
            suspend fun x(): Int = Actor.run(this) l@{
                return@l 0
            }
            fun callback_x(f_return_callback: (Int) -> Unit) {
                Task {
                    f_return_callback(x())
                }
            }
            var y = 1
            suspend fun f(i: Int): String = Actor.run(this) l@{
                return@l ""
            }
            fun callback_f(i: Int, f_return_callback: (String) -> Unit) {
                Task {
                    f_return_callback(f(i = i))
                }
            }
            fun g(): Int = 0
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
        public actor A: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "A")
            public nonisolated let Java_peer: JObject
            public init(Java_ptr: JavaObjectPointer) {
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
            public nonisolated func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        
            public var x: Int {
                get async {
                    return await withCheckedContinuation { f_continuation in
                        let f_return_callback: (Int) -> Void = { f_return in
                            f_continuation.resume(returning: f_return)
                        }
                        jniContext {
                            let f_return_callback_java = SwiftClosure1.javaObject(for: f_return_callback, options: []).toJavaParameter(options: [])
                            try! Java_peer.call(method: Self.Java_x_methodID, options: [], args: [f_return_callback_java])
                        }
                    }
                }
            }
            private static let Java_x_methodID = Java_class.getMethodID(name: "callback_x", sig: "(Lkotlin/jvm/functions/Function1;)V")!
        
            public nonisolated var y: Int {
                get {
                    return jniContext {
                        let value_java: Int32 = try! Java_peer.call(method: Self.Java_get_y_methodID, options: [], args: [])
                        return Int(value_java)
                    }
                }
                set {
                    jniContext {
                        let value_java = Int32(newValue).toJavaParameter(options: [])
                        try! Java_peer.call(method: Self.Java_set_y_methodID, options: [], args: [value_java])
                    }
                }
            }
            private static let Java_get_y_methodID = Java_class.getMethodID(name: "getY", sig: "()I")!
            private static let Java_set_y_methodID = Java_class.getMethodID(name: "setY", sig: "(I)V")!
        
            public func f(i p_0: Int) async -> String {
                return await withCheckedContinuation { f_continuation in
                    let f_return_callback: (String) -> Void = { f_return in
                        f_continuation.resume(returning: f_return)
                    }
                    jniContext {
                        let f_return_callback_java = SwiftClosure1.javaObject(for: f_return_callback, options: []).toJavaParameter(options: [])
                        let p_0_java = Int32(p_0).toJavaParameter(options: [])
                        try! Java_peer.call(method: Self.Java_f_0_methodID, options: [], args: [p_0_java, f_return_callback_java])
                    }
                }
            }
            private static let Java_f_0_methodID = Java_class.getMethodID(name: "callback_f", sig: "(ILkotlin/jvm/functions/Function1;)V")!
        
            public nonisolated func g() -> Int {
                return jniContext {
                    let f_return_java: Int32 = try! Java_peer.call(method: Self.Java_g_1_methodID, options: [], args: [])
                    return Int(f_return_java)
                }
            }
            private static let Java_g_1_methodID = Java_class.getMethodID(name: "g", sig: "()I")!
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
        try await check(swift: """
        #if !SKIP_BRIDGE
        public typealias IntArray = [Int]
        #endif
        """, kotlin: """
        import skip.lib.Array
        
        typealias IntArray = Array<Int>
        """, swiftBridgeSupport: """
        public typealias IntArray = [Int]
        """, transformers: transformers)
    }

    func testErrorType() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public struct CustomError: Error {
        }
        #endif
        """, kotlin: """
        class CustomError: Exception(), Error, skip.lib.SwiftProjecting {
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object {
            }
        }
        """, swiftBridgeSupport: """
        public struct CustomError: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "CustomError")
            public var Java_peer: JObject
            public init(Java_ptr: JavaObjectPointer) {
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
        @_cdecl("Java_CustomError_Swift_1projectionImpl")
        func CustomError_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = CustomError.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testEnumErrorType() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public enum E: Error {
            case case1
            case case2
        }
        #endif
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
        public enum E: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "E")
            private var Java_peer: JavaObjectPointer {
                return toJavaObject(options: [])!
            }
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
        
            case `case1`
        
            case `case2`
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
        try await check(swift: """
        #if !SKIP_BRIDGE
        public class C<T> {
            public var value: T
            public var optionalValue: T?
        
            public static func intFactory(_ value: Int) -> C<Int> {
                return C(value: value)
            }
        
            public init(value: T) {
                self.value = value
            }
        
            public func identity(p: T, o: T? = nil, _ i: Int) -> T {
                return p
            }
        }
        #endif
        """, kotlin: """
        @Suppress("MUST_BE_INITIALIZED", "MUST_BE_INITIALIZED_OR_FINAL_OR_ABSTRACT")
        open class C<T>: skip.lib.SwiftProjecting {
            open var value: T
                get() = field.sref({ this.value = it })
                set(newValue) {
                    field = newValue.sref()
                }
            open var optionalValue: T? = null
                get() = field.sref({ this.optionalValue = it })
                set(newValue) {
                    field = newValue.sref()
                }
        
            constructor(value: T) {
                this.value = value
            }
        
            open fun identity(p: T, o: T? = null, i: Int): T = p.sref()
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object: CompanionClass() {
        
                override fun intFactory(value: Int): C<Int> = C(value = value)
            }
            open class CompanionClass {
                open fun intFactory(value: Int): C<Int> = C.intFactory(value)
            }
        }
        """, swiftBridgeSupport: """
        public class C<T>: BridgedFromKotlin, BridgedFinalClass {
            private static var Java_class: JClass { try! JClass(name: "C") }
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public init(Java_peer: JObject) {
                self.Java_peer = Java_peer
            }
            private static var Java_Companion_class: JClass { try! JClass(name: "C$Companion") }
            private static var Java_Companion: JObject { JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: "Companion", sig: "LC$Companion;")!, options: [])) }
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        
            public var value: T {
                get {
                    return jniContext {
                        let value_java: JavaObjectPointer = try! Java_peer.call(method: Self.Java_get_value_methodID, options: [], args: [])
                        return AnyBridging.fromJavaObject(value_java, options: []) as! T
                    }
                }
                set {
                    jniContext {
                        let value_java = ((newValue as? JConvertible)?.toJavaObject(options: []))!.toJavaParameter(options: [])
                        try! Java_peer.call(method: Self.Java_set_value_methodID, options: [], args: [value_java])
                    }
                }
            }
            private static var Java_get_value_methodID: JavaMethodID { Java_class.getMethodID(name: "getValue", sig: "()Ljava/lang/Object;")! }
            private static var Java_set_value_methodID: JavaMethodID { Java_class.getMethodID(name: "setValue", sig: "(Ljava/lang/Object;)V")! }
        
            public var optionalValue: T? {
                get {
                    return jniContext {
                        let value_java: JavaObjectPointer? = try! Java_peer.call(method: Self.Java_get_optionalValue_methodID, options: [], args: [])
                        return AnyBridging.fromJavaObject(value_java, options: []) as! T?
                    }
                }
                set {
                    jniContext {
                        let value_java = ((newValue as? JConvertible)?.toJavaObject(options: [])).toJavaParameter(options: [])
                        try! Java_peer.call(method: Self.Java_set_optionalValue_methodID, options: [], args: [value_java])
                    }
                }
            }
            private static var Java_get_optionalValue_methodID: JavaMethodID { Java_class.getMethodID(name: "getOptionalValue", sig: "()Ljava/lang/Object;")! }
            private static var Java_set_optionalValue_methodID: JavaMethodID { Java_class.getMethodID(name: "setOptionalValue", sig: "(Ljava/lang/Object;)V")! }
        
            public static func intFactory(_ p_0: Int) -> C<Int> {
                return jniContext {
                    let p_0_java = Int32(p_0).toJavaParameter(options: [])
                    let f_return_java: JavaObjectPointer = try! Java_Companion.call(method: Java_Companion_intFactory_0_methodID, options: [], args: [p_0_java])
                    return AnyBridging.fromJavaObject(f_return_java, toBaseType: C<Int>.self, options: [])!
                }
            }
            private static var Java_Companion_intFactory_0_methodID: JavaMethodID { Java_Companion_class.getMethodID(name: "intFactory", sig: "(I)LC;")! }
        
            public init(value p_0: T) {
                Java_peer = jniContext {
                    let p_0_java = ((p_0 as? JConvertible)?.toJavaObject(options: []))!.toJavaParameter(options: [])
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_1_methodID, options: [], args: [p_0_java])
                    return JObject(ptr)
                }
            }
            private static var Java_constructor_1_methodID: JavaMethodID { Java_class.getMethodID(name: "<init>", sig: "(Ljava/lang/Object;)V")! }
        
            public func identity(p p_0: T, o p_1: T? = nil, _ p_2: Int) -> T {
                return jniContext {
                    let p_0_java = ((p_0 as? JConvertible)?.toJavaObject(options: []))!.toJavaParameter(options: [])
                    let p_1_java = ((p_1 as? JConvertible)?.toJavaObject(options: [])).toJavaParameter(options: [])
                    let p_2_java = Int32(p_2).toJavaParameter(options: [])
                    let f_return_java: JavaObjectPointer = try! Java_peer.call(method: Self.Java_identity_2_methodID, options: [], args: [p_0_java, p_1_java, p_2_java])
                    return AnyBridging.fromJavaObject(f_return_java, options: []) as! T
                }
            }
            private static var Java_identity_2_methodID: JavaMethodID { Java_class.getMethodID(name: "identity", sig: "(Ljava/lang/Object;Ljava/lang/Object;I)Ljava/lang/Object;")! }
        }
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C<Any>.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testConstrainedGenericClass() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public protocol P {
        }
        public class C<T> where T: P {
            public var value: T
        
            public init(value: T) {
                self.value = value
            }
        }
        #endif
        """, kotlin: """
        interface P {
        }
        @Suppress("MUST_BE_INITIALIZED", "MUST_BE_INITIALIZED_OR_FINAL_OR_ABSTRACT")
        open class C<T>: skip.lib.SwiftProjecting where T: P {
            open var value: T
                get() = field.sref({ this.value = it })
                set(newValue) {
                    field = newValue.sref()
                }
        
            constructor(value: T) {
                this.value = value
            }
        
            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any
        
            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        public protocol P {
        }
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
        public class C<T>: BridgedFromKotlin, BridgedFinalClass where T: P {
            private static var Java_class: JClass { try! JClass(name: "C") }
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public init(Java_peer: JObject) {
                self.Java_peer = Java_peer
            }
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        
            public var value: T {
                get {
                    return jniContext {
                        let value_java: JavaObjectPointer = try! Java_peer.call(method: Self.Java_get_value_methodID, options: [], args: [])
                        return AnyBridging.fromJavaObject(value_java, options: []) as! T
                    }
                }
                set {
                    jniContext {
                        let value_java = ((newValue as? JConvertible)?.toJavaObject(options: []))!.toJavaParameter(options: [])
                        try! Java_peer.call(method: Self.Java_set_value_methodID, options: [], args: [value_java])
                    }
                }
            }
            private static var Java_get_value_methodID: JavaMethodID { Java_class.getMethodID(name: "getValue", sig: "()Ljava/lang/Object;")! }
            private static var Java_set_value_methodID: JavaMethodID { Java_class.getMethodID(name: "setValue", sig: "(Ljava/lang/Object;)V")! }
        
            public init(value p_0: T) {
                Java_peer = jniContext {
                    let p_0_java = ((p_0 as? JConvertible)?.toJavaObject(options: []))!.toJavaParameter(options: [])
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_0_methodID, options: [], args: [p_0_java])
                    return JObject(ptr)
                }
            }
            private static var Java_constructor_0_methodID: JavaMethodID { Java_class.getMethodID(name: "<init>", sig: "(Ljava/lang/Object;)V")! }
        }
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C<P>.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testGenericStruct() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public struct S<T> {
            public var value: T
        
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
        #endif
        """, kotlin: """
        @Suppress("MUST_BE_INITIALIZED")
        class S<T>: MutableStruct, skip.lib.SwiftProjecting {
            var value: T
                get() = field.sref({ this.value = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    willmutate()
                    field = newValue
                    didmutate()
                }

            constructor(value: T) {
            }

            fun identity(p: T, o: T? = null, i: Int): T = p.sref()
            fun mutatingVoid() = Unit
            fun mutatingRet(p: T): Int {
                willmutate()
                try {
                    return 0
                } finally {
                    didmutate()
                }
            }

            private constructor(copy: MutableStruct) {
                @Suppress("NAME_SHADOWING", "UNCHECKED_CAST") val copy = copy as S<T>
                this.value = copy.value
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S<T>(this as MutableStruct)

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        public struct S<T>: BridgedFromKotlin {
            private static var Java_class: JClass { try! JClass(name: "S") }
            public var Java_peer: JObject
            public init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            private static var Java_scopy_methodID: JavaMethodID { Java_class.getMethodID(name: "scopy", sig: "()Lskip/lib/MutableStruct;")! }
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            public var value: T {
                get {
                    return jniContext {
                        let value_java: JavaObjectPointer = try! Java_peer.call(method: Self.Java_get_value_methodID, options: [], args: [])
                        return AnyBridging.fromJavaObject(value_java, options: []) as! T
                    }
                }
                set {
                    jniContext {
                        Java_peer = try! JObject(Java_peer.call(method: Self.Java_scopy_methodID, options: [], args: []))
                        let value_java = ((newValue as? JConvertible)?.toJavaObject(options: []))!.toJavaParameter(options: [])
                        try! Java_peer.call(method: Self.Java_set_value_methodID, options: [], args: [value_java])
                    }
                }
            }
            private static var Java_get_value_methodID: JavaMethodID { Java_class.getMethodID(name: "getValue", sig: "()Ljava/lang/Object;")! }
            private static var Java_set_value_methodID: JavaMethodID { Java_class.getMethodID(name: "setValue", sig: "(Ljava/lang/Object;)V")! }

            public init(value p_0: T) {
                Java_peer = jniContext {
                    let p_0_java = ((p_0 as? JConvertible)?.toJavaObject(options: []))!.toJavaParameter(options: [])
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_0_methodID, options: [], args: [p_0_java])
                    return JObject(ptr)
                }
            }
            private static var Java_constructor_0_methodID: JavaMethodID { Java_class.getMethodID(name: "<init>", sig: "(Ljava/lang/Object;)V")! }

            public func identity(p p_0: T, o p_1: T? = nil, _ p_2: Int) -> T {
                return jniContext {
                    let p_0_java = ((p_0 as? JConvertible)?.toJavaObject(options: []))!.toJavaParameter(options: [])
                    let p_1_java = ((p_1 as? JConvertible)?.toJavaObject(options: [])).toJavaParameter(options: [])
                    let p_2_java = Int32(p_2).toJavaParameter(options: [])
                    let f_return_java: JavaObjectPointer = try! Java_peer.call(method: Self.Java_identity_1_methodID, options: [], args: [p_0_java, p_1_java, p_2_java])
                    return AnyBridging.fromJavaObject(f_return_java, options: []) as! T
                }
            }
            private static var Java_identity_1_methodID: JavaMethodID { Java_class.getMethodID(name: "identity", sig: "(Ljava/lang/Object;Ljava/lang/Object;I)Ljava/lang/Object;")! }

            public mutating func mutatingVoid() {
                jniContext {
                    Java_peer = try! JObject(Java_peer.call(method: Self.Java_scopy_methodID, options: [], args: []))
                    try! Java_peer.call(method: Self.Java_mutatingVoid_2_methodID, options: [], args: [])
                }
            }
            private static var Java_mutatingVoid_2_methodID: JavaMethodID { Java_class.getMethodID(name: "mutatingVoid", sig: "()V")! }

            public mutating func mutatingRet(p p_0: T) -> Int {
                return jniContext {
                    Java_peer = try! JObject(Java_peer.call(method: Self.Java_scopy_methodID, options: [], args: []))
                    let p_0_java = ((p_0 as? JConvertible)?.toJavaObject(options: []))!.toJavaParameter(options: [])
                    let f_return_java: Int32 = try! Java_peer.call(method: Self.Java_mutatingRet_3_methodID, options: [], args: [p_0_java])
                    return Int(f_return_java)
                }
            }
            private static var Java_mutatingRet_3_methodID: JavaMethodID { Java_class.getMethodID(name: "mutatingRet", sig: "(Ljava/lang/Object;)I")! }
        }
        @_cdecl("Java_S_Swift_1projectionImpl")
        func S_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = S<Any>.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testGenericProtocol() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public protocol P {
            associatedtype T
            func f(p: T) -> T
        }
        public final class C: P {
            public func f(p: Int) -> Int {
                return p
            }
        }
        #endif
        """, kotlin: """
        interface P<T> {
            fun f(p: T): T
        }
        class C: P<Int>, skip.lib.SwiftProjecting {
            override fun f(p: Int): Int = p

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
            }
        }
        """, swiftBridgeSupport: """
        public protocol P {
            associatedtype T

            func f(p p_0: T) -> T
        }
        public final class P_BridgeImpl<T>: P, BridgedFromKotlin {
            private static var Java_class: JClass { try! JClass(name: "P") }
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public func f(p p_0: T) -> T {
                return jniContext {
                    let p_0_java = ((p_0 as? JConvertible)?.toJavaObject(options: []))!.toJavaParameter(options: [])
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
        public final class C: P, BridgedFromKotlin, BridgedFinalClass {
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

            public func f(p p_0: Int) -> Int {
                return jniContext {
                    let p_0_java = Int32(p_0).toJavaParameter(options: [])
                    let f_return_java: Int32 = try! Java_peer.call(method: Self.Java_f_0_methodID, options: [], args: [p_0_java])
                    return Int(f_return_java)
                }
            }
            private static let Java_f_0_methodID = Java_class.getMethodID(name: "f", sig: "(I)I")!
        }
        @_cdecl("Java_C_Swift_1projectionImpl")
        func C_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = C.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testGenericEnum() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
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
        #endif
        """, kotlin: """
        sealed class E<out T>: skip.lib.SwiftProjecting {
            class ACase<T>(val associated0: T): E<T>() {
            }
            class BCase: E<Nothing>() {
            }

            fun aValue(): T? {
                when (this) {
                    is E.ACase -> {
                        val value = this.associated0
                        return value.sref()
                    }
                    is E.BCase -> return null
                }
            }

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object {
                fun <T> a(associated0: T): E<T> = ACase(associated0)
                val b: E<Nothing> = BCase()
            }
        }
        """, swiftBridgeSupport: """
        public enum E<T>: BridgedFromKotlin {
            private static var Java_class: JClass { try! JClass(name: "E") }
            private var Java_peer: JavaObjectPointer {
                return toJavaObject(options: [])!
            }
            private static var Java_Companion_class: JClass { try! JClass(name: "E$Companion") }
            private static var Java_Companion: JObject { JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: "Companion", sig: "LE$Companion;")!, options: [])) }
            public static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {
                let className = Java_className(of: obj!, options: options)
                return fromJavaClassName(className, obj!, options: options)
            }
            fileprivate static func fromJavaClassName(_ className: String, _ obj: JavaObjectPointer, options: JConvertibleOptions) -> Self {
                switch className {
                case "E$ACase":
                    let associated0_java: JavaObjectPointer = try! obj.call(method: Self.Java_a_associated0_methodID, options: options, args: [])
                    let associated0 = AnyBridging.fromJavaObject(associated0_java, options: []) as! T
                    return .a(associated0)
                case "E$BCase":
                    return .b
                default: fatalError()
                }
            }
            public func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {
                switch self {
                case .a(let associated0):
                    let associated0_java = ((associated0 as? JConvertible)?.toJavaObject(options: options))!.toJavaParameter(options: options)
                    return try! Self.Java_Companion.call(method: Self.Java_Companion_a_methodID, options: options, args: [associated0_java])
                case .b:
                    return try! Self.Java_Companion.call(method: Self.Java_Companion_b_methodID, options: options, args: [])
                }
            }
            private static var Java_a_class: JClass { try! JClass(name: "E$ACase") }
            private static var Java_a_associated0_methodID: JavaMethodID { Java_a_class.getMethodID(name: "getAssociated0", sig: "()Ljava/lang/Object;")! }
            private static var Java_Companion_a_methodID: JavaMethodID { Java_Companion_class.getMethodID(name: "a", sig: "(Ljava/lang/Object;)LE;")! }
            private static var Java_Companion_b_methodID: JavaMethodID { Java_Companion_class.getMethodID(name: "getB", sig: "()LE;")! }

            case `a`(T)

            case `b`

            public func aValue() -> T? {
                return jniContext {
                    let f_return_java: JavaObjectPointer? = try! Java_peer.call(method: Self.Java_aValue_0_methodID, options: [], args: [])
                    return AnyBridging.fromJavaObject(f_return_java, options: []) as! T?
                }
            }
            private static var Java_aValue_0_methodID: JavaMethodID { Java_class.getMethodID(name: "aValue", sig: "()Ljava/lang/Object;")! }
        }
        @_cdecl("Java_E_Swift_1projectionImpl")
        func E_Swift_projectionImpl(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ options: Int32) -> JavaObjectPointer {
            let projection = E<Any>.fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))
            let factory: () -> Any = { projection }
            return SwiftClosure0.javaObject(for: factory, options: [])!
        }
        """, transformers: transformers)
    }

    func testGenericFunction() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public func f<T>(p: T) -> T {
            return p
        }
        #endif
        """, kotlin: """
        fun <T> f(p: T): T = p.sref()
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f<T>(p p_0: T) -> T {
            return jniContext {
                let p_0_java = ((p_0 as? JConvertible)?.toJavaObject(options: []))!.toJavaParameter(options: [])
                let f_return_java: JavaObjectPointer = try! Java_SourceKt.callStatic(method: Java_f_0_methodID, options: [], args: [p_0_java])
                return AnyBridging.fromJavaObject(f_return_java, options: []) as! T
            }
        }
        private let Java_f_0_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(Ljava/lang/Object;)Ljava/lang/Object;")!
        """, transformers: transformers)
    }

    func testConstrainedGenericFunction() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public protocol P {
        }
        public class C {
        }
        public func f<Param, Ret>(p: Param) -> Ret where Param: P, Param: C, Ret: P {
            return p
        }
        #endif
        """, kotlin: """
        interface P {
        }
        open class C: skip.lib.SwiftProjecting {

            override fun Swift_projection(options: Int): () -> Any = Swift_projectionImpl(options)
            private external fun Swift_projectionImpl(options: Int): () -> Any

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        fun <Param, Ret> f(p: Param): Ret where Param: P, Param: C, Ret: P = p
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public protocol P {
        }
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
        public class C: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "C")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public init(Java_peer: JObject) {
                self.Java_peer = Java_peer
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
        public func f<Param, Ret>(p p_0: Param) -> Ret where Param: P, Param: C, Ret: P {
            return jniContext {
                let p_0_java = p_0.toJavaObject(options: [])!.toJavaParameter(options: [])
                let f_return_java: JavaObjectPointer = try! Java_SourceKt.callStatic(method: Java_f_0_methodID, options: [], args: [p_0_java])
                return AnyBridging.fromJavaObject(f_return_java, options: []) as! Ret
            }
        }
        private let Java_f_0_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(Ljava/lang/Object;)Ljava/lang/Object;")!
        """, transformers: transformers)
    }

    func testAsyncGenericFunction() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        public func f<T>(p: T) async throws -> T {
            return p
        }
        #endif
        """, kotlin: """
        suspend fun <T> f(p: T): T = Async.run l@{
            return@l p.sref()
        }
        fun <T> callback_f(p: T, f_return_callback: (T?, Throwable?) -> Unit) {
            Task {
                try {
                    f_return_callback(f(p = p), null)
                } catch(t: Throwable) {
                    f_return_callback(null, t)
                }
            }
        }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f<T>(p p_0: T) async throws -> T {
            return try await withCheckedThrowingContinuation { f_continuation in
                let f_return_callback: (T?, JavaObjectPointer?) -> Void = { f_return, f_error in
                    if let f_error {
                        f_continuation.resume(throwing: JThrowable.toError(f_error, options: []))
                    } else {
                        f_continuation.resume(returning: f_return!)
                    }
                }
                jniContext {
                    let f_return_callback_java = SwiftClosure2.javaObject(for: f_return_callback, options: []).toJavaParameter(options: [])
                    let p_0_java = ((p_0 as? JConvertible)?.toJavaObject(options: []))!.toJavaParameter(options: [])
                    try! Java_SourceKt.callStatic(method: Java_f_0_methodID, options: [], args: [p_0_java, f_return_callback_java])
                }
            }
        }
        private let Java_f_0_methodID = Java_SourceKt.getStaticMethodID(name: "callback_f", sig: "(Ljava/lang/Object;Lkotlin/jvm/functions/Function2;)V")!
        """, transformers: transformers)
    }

    func testImports() async throws {
        try await check(swift: """
        #if !SKIP_BRIDGE
        import Foundation
        public var i: Int {
            return 1
        }
        #endif
        """, kotlin: """
        import skip.foundation.*
        val i: Int
            get() = 1
        """, swiftBridgeSupport: """

        import Foundation
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var i: Int {
            get {
                return jniContext {
                    let value_java: Int32 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, options: [], args: [])
                    return Int(value_java)
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()I")!
        """, transformers: transformers)
    }

    func testIfNotSkipBridgeWarning() async throws {
        try await checkProducesMessage(swift: """
        public let i = 1
        """, transformers: transformers)

        try await check(swift: """
        // Some comments here
        
        import Foundation
        
        private var x = 0
        
        #if !SKIP_BRIDGE
        public let i = 1
        #endif
        
        // More stuff here
        """, kotlin: """
        // Some comments here

        import skip.foundation.*

        private var x = 0

        val i = 1

        // More stuff here
        """, swiftBridgeSupport: """

        import Foundation
        public let i: Int = 1
        """, transformers: transformers)
    }
}
