import SkipSyntax
import XCTest

final class BridgeToSwiftTests: XCTestCase {
    private var transformers: [KotlinTransformer] {
        return builtinKotlinTransformers() + [KotlinBridgeTransformer()]
    }

    func testLetSupportedLiteral() async throws {
        try await check(swift: """
        public let b = true
        """, kotlin: """
        val b = true
        """, swiftBridgeSupport: """
        public let b = true
        """, transformers: transformers)

        try await check(swift: """
        public let i = 1
        """, kotlin: """
        val i = 1
        """, swiftBridgeSupport: """
        public let i: Int = 1
        """, transformers: transformers)

        try await check(swift: """
        public let i: Int32 = 1
        """, kotlin: """
        val i: Int = 1
        """, swiftBridgeSupport: """
        public let i: Int32 = 1
        """, transformers: transformers)

        try await check(swift: """
        public let d = 5.0
        """, kotlin: """
        val d = 5.0
        """, swiftBridgeSupport: """
        public let d: Double = 5.0
        """, transformers: transformers)

        try await check(swift: """
        public let d: Double = 5
        """, kotlin: """
        val d: Double = 5.0
        """, swiftBridgeSupport: """
        public let d: Double = 5
        """, transformers: transformers)

        try await check(swift: """
        public let d: Double? = nil
        """, kotlin: """
        val d: Double? = null
        """, swiftBridgeSupport: """
        public let d: Double? = nil
        """, transformers: transformers)

        try await check(swift: """
        public let d: Double? = 5
        """, kotlin: """
        val d: Double? = 5.0
        """, swiftBridgeSupport: """
        public let d: Double? = 5
        """, transformers: transformers)

        try await check(swift: """
        public let f = Float(1)
        """, kotlin: """
        val f = 1f
        """, swiftBridgeSupport: """
        public let f: Float = 1
        """, transformers: transformers)

        try await check(swift: """
        public let s = "Hello"
        """, kotlin: """
        val s = "Hello"
        """, swiftBridgeSupport: """
        public let s = "Hello"
        """, transformers: transformers)

        try await check(swift: """
        public let l = Int64(1)
        """, kotlin: """
        val l = 1L
        """, swiftBridgeSupport: """
        public let l: Int64 = 1
        """, transformers: transformers)
    }

    func testLetUnsupportedLiteral() async throws {
        try await check(swift: """
        public let s = "ab\\(1 + 1)c"
        """, kotlin: """
        val s = "ab${1 + 1}c"
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var s: String {
            get {
                return jniContext {
                    let value_java: String = try! Java_SourceKt.callStatic(method: Java_get_s_methodID, args: [])
                    return value_java
                }
            }
        }
        private let Java_get_s_methodID = Java_SourceKt.getStaticMethodID(name: "getS", sig: "()Ljava/lang/String;")!
        """, transformers: transformers)

        try await check(swift: """
        public let b: Bool? = true
        """, kotlin: """
        val b: Boolean? = true
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var b: Bool? {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer? = try! Java_SourceKt.callStatic(method: Java_get_b_methodID, args: [])
                    return Bool?.fromJavaObject(value_java)
                }
            }
        }
        private let Java_get_b_methodID = Java_SourceKt.getStaticMethodID(name: "getB", sig: "()Ljava/lang/Boolean;")!
        """, transformers: transformers)
    }

    func testLetNonLiteral() async throws {
        try await check(swift: """
        public let i = 1 + 1
        """, kotlin: """
        val i = 1 + 1
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var i: Int {
            get {
                return jniContext {
                    let value_java: Int32 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, args: [])
                    return Int(value_java)
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()I")!
        """, transformers: transformers)

        try await check(swift: """
        public let i = Int64(1 + 1)
        """, kotlin: """
        val i = Long(1 + 1)
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var i: Int64 {
            get {
                return jniContext {
                    let value_java: Int64 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, args: [])
                    return value_java
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()J")!
        """, transformers: transformers)
    }

    func testStoredVar() async throws {
        try await check(swift: """
        public var i = 1
        """, kotlin: """
        var i = 1
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var i: Int {
            get {
                return jniContext {
                    let value_java: Int32 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, args: [])
                    return Int(value_java)
                }
            }
            set {
                jniContext {
                    let value_java = Int32(newValue).toJavaParameter()
                    try! Java_SourceKt.callStatic(method: Java_set_i_methodID, args: [value_java])
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()I")!
        private let Java_set_i_methodID = Java_SourceKt.getStaticMethodID(name: "setI", sig: "(I)V")!
        """, transformers: transformers)
    }

    func testBridgeIgnoredVar() async throws {
        try await check(swift: """
        @BridgeIgnored
        public var i = 1
        // SKIP @BridgeIgnored
        public var j = 1
        public let s = ""
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
        private var i = 1
        private var j = 1
        public let s = ""
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
        private(set) public var i = 1
        """, kotlin: """
        var i = 1
            private set
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var i: Int {
            get {
                return jniContext {
                    let value_java: Int32 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, args: [])
                    return Int(value_java)
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()I")!
        """, transformers: transformers)

        try await check(swift: """
        public private(set) var d: Double {
            get {
                return 1.0
            }
            set {
                print("set")
            }
        }
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
                    let value_java: Double = try! Java_SourceKt.callStatic(method: Java_get_d_methodID, args: [])
                    return value_java
                }
            }
        }
        private let Java_get_d_methodID = Java_SourceKt.getStaticMethodID(name: "getD", sig: "()D")!
        """, transformers: transformers)
    }

    func testWillSetDidSet() async throws {
        try await check(swift: """
        public private(set) var i: Int32 = 1 {
            willSet {
                print("willSet")
            }
            didSet {
                print("didSet")
            }
        }
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
                    let value_java: Int32 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, args: [])
                    return value_java
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()I")!
        """, transformers: transformers)
    }

    func testComputedVar() async throws {
        try await check(swift: """
        public var i: Int64 {
            get {
                return 1
            }
            set {
            }
        }
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
                    let value_java: Int64 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, args: [])
                    return value_java
                }
            }
            set {
                jniContext {
                    let value_java = newValue.toJavaParameter()
                    try! Java_SourceKt.callStatic(method: Java_set_i_methodID, args: [value_java])
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()J")!
        private let Java_set_i_methodID = Java_SourceKt.getStaticMethodID(name: "setI", sig: "(J)V")!
        """, transformers: transformers)
    }

    func testKeywordVar() async throws {
        try await check(swift: """
        public var object = ""
        """, kotlin: """
        var object_ = ""
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var object: String {
            get {
                return jniContext {
                    let value_java: String = try! Java_SourceKt.callStatic(method: Java_get_object__methodID, args: [])
                    return value_java
                }
            }
            set {
                jniContext {
                    let value_java = newValue.toJavaParameter()
                    try! Java_SourceKt.callStatic(method: Java_set_object__methodID, args: [value_java])
                }
            }
        }
        private let Java_get_object__methodID = Java_SourceKt.getStaticMethodID(name: "getObject_", sig: "()Ljava/lang/String;")!
        private let Java_set_object__methodID = Java_SourceKt.getStaticMethodID(name: "setObject_", sig: "(Ljava/lang/String;)V")!
        """, transformers: transformers)
    }

    func testThrowsVar() async throws {
        try await checkProducesMessage(swift: """
        public var i: Int {
            get throws {
                return 0
            }
        }
        """, transformers: transformers)
    }

    func testAsyncVar() async throws {
        try await checkProducesMessage(swift: """
        public var i: Int {
            get async {
                return 0
            }
        }
        """, transformers: transformers)
    }

    func testOptionalVar() async throws {
        try await check(swift: """
        public var i: Int? = 1
        """, kotlin: """
        var i: Int? = 1
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var i: Int? {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer? = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, args: [])
                    return Int?.fromJavaObject(value_java)
                }
            }
            set {
                jniContext {
                    let value_java = newValue.toJavaParameter()
                    try! Java_SourceKt.callStatic(method: Java_set_i_methodID, args: [value_java])
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
        public class C {
        }
        public var c = C()
        """, kotlin: """
        open class C {

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        var c = C()
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
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
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        public var c: C {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer = try! Java_SourceKt.callStatic(method: Java_get_c_methodID, args: [])
                    return C.fromJavaObject(value_java)
                }
            }
            set {
                jniContext {
                    let value_java = newValue.toJavaObject()!.toJavaParameter()
                    try! Java_SourceKt.callStatic(method: Java_set_c_methodID, args: [value_java])
                }
            }
        }
        private let Java_get_c_methodID = Java_SourceKt.getStaticMethodID(name: "getC", sig: "()LC;")!
        private let Java_set_c_methodID = Java_SourceKt.getStaticMethodID(name: "setC", sig: "(LC;)V")!
        """, transformers: transformers)
    }

    func testOptionalTranspiledBridgedTypeVar() async throws {
        try await check(swift: """
        public class C {
        }
        public var c: C? = C()
        """, kotlin: """
        open class C {

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        var c: C? = C()
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
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
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        public var c: C? {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer? = try! Java_SourceKt.callStatic(method: Java_get_c_methodID, args: [])
                    return C?.fromJavaObject(value_java)
                }
            }
            set {
                jniContext {
                    let value_java = newValue.toJavaObject().toJavaParameter()
                    try! Java_SourceKt.callStatic(method: Java_set_c_methodID, args: [value_java])
                }
            }
        }
        private let Java_get_c_methodID = Java_SourceKt.getStaticMethodID(name: "getC", sig: "()LC;")!
        private let Java_set_c_methodID = Java_SourceKt.getStaticMethodID(name: "setC", sig: "(LC;)V")!
        """, transformers: transformers)
    }

    func testCompiledBridgedTypeVar() async throws {
        try await check(swift: """
        public var c = C()
        """, swiftBridge: """
        public class C {
        }
        """, kotlins: ["""
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
        """, """
        var c = C()
        """], swiftBridgeSupports: ["""
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            public func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
        """, """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var c: C {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer = try! Java_SourceKt.callStatic(method: Java_get_c_methodID, args: [])
                    return C.fromJavaObject(value_java)
                }
            }
            set {
                jniContext {
                    let value_java = newValue.toJavaObject()!.toJavaParameter()
                    try! Java_SourceKt.callStatic(method: Java_set_c_methodID, args: [value_java])
                }
            }
        }
        private let Java_get_c_methodID = Java_SourceKt.getStaticMethodID(name: "getC", sig: "()LC;")!
        private let Java_set_c_methodID = Java_SourceKt.getStaticMethodID(name: "setC", sig: "(LC;)V")!
        """], transformers: transformers)
    }

    func testUnbridgableTypeVar() async throws {
        try await checkProducesMessage(swift: """
        public var c: C = C()
        """, transformers: transformers)

        try await checkProducesMessage(swift: """
        // SKIP @BridgeIgnored
        public class C {
        }
        public var c = C()
        """, transformers: transformers)
    }

    func testClosureTypeVar() async throws {
        try await check(swift: """
        public var c: (Int) -> String = { _ in "" }
        """, kotlin: """
        var c: (Int) -> String = { _ -> "" }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var c: (Int) -> String {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer = try! Java_SourceKt.callStatic(method: Java_get_c_methodID, args: [])
                    return { let closure_swift = JavaBackedClosure<String>(value_java); return { p0 in try! closure_swift.invoke(p0) } }()
                }
            }
            set {
                jniContext {
                    let value_java = SwiftClosure1.javaObject(for: newValue).toJavaParameter()
                    try! Java_SourceKt.callStatic(method: Java_set_c_methodID, args: [value_java])
                }
            }
        }
        private let Java_get_c_methodID = Java_SourceKt.getStaticMethodID(name: "getC", sig: "()Lkotlin/jvm/functions/Function1;")!
        private let Java_set_c_methodID = Java_SourceKt.getStaticMethodID(name: "setC", sig: "(Lkotlin/jvm/functions/Function1;)V")!
        """, transformers: transformers)
    }

    func testVoidClosureTypeVar() async throws {
        try await check(swift: """
        public var c: () -> Void = { }
        """, kotlin: """
        var c: () -> Unit = { ->  }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var c: () -> Void {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer = try! Java_SourceKt.callStatic(method: Java_get_c_methodID, args: [])
                    return { let closure_swift = JavaBackedClosure<Void>(value_java); return { try! closure_swift.invoke() } }()
                }
            }
            set {
                jniContext {
                    let value_java = SwiftClosure0.javaObject(for: newValue).toJavaParameter()
                    try! Java_SourceKt.callStatic(method: Java_set_c_methodID, args: [value_java])
                }
            }
        }
        private let Java_get_c_methodID = Java_SourceKt.getStaticMethodID(name: "getC", sig: "()Lkotlin/jvm/functions/Function0;")!
        private let Java_set_c_methodID = Java_SourceKt.getStaticMethodID(name: "setC", sig: "(Lkotlin/jvm/functions/Function0;)V")!
        """, transformers: transformers)
    }

    func testFunction() async throws {
        try await check(swift: """
        public func f(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        """, kotlin: """
        fun f(i: Int, s: String): Int = i + (Int(s) ?: 0)
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f(i p_0: Int, s p_1: String) -> Int {
            return jniContext {
                let p_0_java = Int32(p_0).toJavaParameter()
                let p_1_java = p_1.toJavaParameter()
                let f_return_java: Int32 = try! Java_SourceKt.callStatic(method: Java_f_methodID, args: [p_0_java, p_1_java])
                return Int(f_return_java)
            }
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(ILjava/lang/String;)I")!
        """, transformers: transformers)
    }

    func testBridgeIgnoredFunction() async throws {
        try await check(swift: """
        @BridgeIgnored
        public func f(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        // SKIP @BridgeIgnored
        public func g(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        """, kotlin: """
        fun f(i: Int, s: String): Int = i + (Int(s) ?: 0)
        fun g(i: Int, s: String): Int = i + (Int(s) ?: 0)
        """, swiftBridgeSupport: """
        """, transformers: transformers)
    }

    func testPrivateFunction() async throws {
        try await check(swift: """
        private func f(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        private func g(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        """, kotlin: """
        private fun f(i: Int, s: String): Int = i + (Int(s) ?: 0)
        private fun g(i: Int, s: String): Int = i + (Int(s) ?: 0)
        """, swiftBridgeSupport: """
        """, transformers: transformers)
    }

    func testThrowsFunction() async throws {
        try await check(swift: """
        public func f() throws {
        }
        """, kotlin: """
        fun f() = Unit
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f() throws {
            try jniContext {
                do {
                    try Java_SourceKt.callStatic(method: Java_f_methodID, args: [])
                } catch let error as ThrowableError {
                    throw error
                } catch {
                    fatalError(String(describing: error))
                }
            }
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "()V")!
        """, transformers: transformers)
    }

    func testFunctionParameterLabel() async throws {
        try await check(swift: """
        public func nolabel(_ i: Int) {
        }
        """, kotlin: """
        fun nolabel(i: Int) = Unit
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func nolabel(_ p_0: Int) {
            jniContext {
                let p_0_java = Int32(p_0).toJavaParameter()
                try! Java_SourceKt.callStatic(method: Java_nolabel_methodID, args: [p_0_java])
            }
        }
        private let Java_nolabel_methodID = Java_SourceKt.getStaticMethodID(name: "nolabel", sig: "(I)V")!
        """, transformers: transformers)
    }

    func testFunctionParameterDefaultValue() async throws {
        try await check(swift: """
        public func f(i: Int = 0) -> Int {
            return i
        }
        """, kotlin: """
        fun f(i: Int = 0): Int = i
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f(i p_0: Int = 0) -> Int {
            return jniContext {
                let p_0_java = Int32(p_0).toJavaParameter()
                let f_return_java: Int32 = try! Java_SourceKt.callStatic(method: Java_f_methodID, args: [p_0_java])
                return Int(f_return_java)
            }
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(I)I")!
        """, transformers: transformers)
    }

    func testFunctionParameterLabelOverload() async throws {
        try await check(swift: """
        public func f(i: Int) -> Int {
            return i
        }
        public func f(value: Int) -> Int {
            return value
        }
        """, kotlin: """
        fun f(i: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null): Int = i
        fun f(value: Int): Int = value
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f(i p_0: Int) -> Int {
            return jniContext {
                let p_0_java = Int32(p_0).toJavaParameter()
                let p_1_java = JavaParameter(l: nil)
                let f_return_java: Int32 = try! Java_SourceKt.callStatic(method: Java_f_methodID, args: [p_0_java, p_1_java])
                return Int(f_return_java)
            }
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(ILjava/lang/Void;)I")!
        public func f(value p_0: Int) -> Int {
            return jniContext {
                let p_0_java = Int32(p_0).toJavaParameter()
                let f_return_java: Int32 = try! Java_SourceKt.callStatic(method: Java_f_methodID, args: [p_0_java])
                return Int(f_return_java)
            }
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(I)I")!
        """, transformers: transformers)
    }

    func testKeywordFunction() async throws {
        try await check(swift: """
        public func object(object: Int) {
        }
        """, kotlin: """
        fun object_(object_: Int) = Unit
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func object(object p_0: Int) {
            jniContext {
                let p_0_java = Int32(p_0).toJavaParameter()
                try! Java_SourceKt.callStatic(method: Java_object__methodID, args: [p_0_java])
            }
        }
        private let Java_object__methodID = Java_SourceKt.getStaticMethodID(name: "object_", sig: "(I)V")!
        """, transformers: transformers)
    }

    func testOptionalFunction() async throws {
        try await check(swift: """
        public func f(i: Int?) -> Int? {
            return nil
        }
        """, kotlin: """
        fun f(i: Int?): Int? = null
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f(i p_0: Int?) -> Int? {
            return jniContext {
                let p_0_java = p_0.toJavaParameter()
                let f_return_java: JavaObjectPointer? = try! Java_SourceKt.callStatic(method: Java_f_methodID, args: [p_0_java])
                return Int?.fromJavaObject(f_return_java)
            }
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(Ljava/lang/Integer;)Ljava/lang/Integer;")!
        """, transformers: transformers)
    }

    func testBridgedObjectFunction() async throws {
        try await check(swift: """
        public class C {
        }
        public func f(c: C) -> C {
        }
        """, kotlin: """
        open class C {

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        fun f(c: C): C = Unit
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
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
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        public func f(c p_0: C) -> C {
            return jniContext {
                let p_0_java = p_0.toJavaObject()!.toJavaParameter()
                let f_return_java: JavaObjectPointer = try! Java_SourceKt.callStatic(method: Java_f_methodID, args: [p_0_java])
                return C.fromJavaObject(f_return_java)
            }
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(LC;)LC;")!
        """, transformers: transformers)
    }

    func testVariadicFunction() async throws {
        try await checkProducesMessage(swift: """
        public func f(i: Int...) { }
        """, transformers: transformers)
    }

    func testAsyncFunction() async throws {
        try await check(swift: """
        public func f(i: Int) async -> Int {
            return i
        }
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
                    let f_return_callback_java = SwiftClosure1.javaObject(for: f_return_callback).toJavaParameter()
                    let p_0_java = Int32(p_0).toJavaParameter()
                    try! Java_SourceKt.callStatic(method: Java_f_methodID, args: [p_0_java, f_return_callback_java])
                }
            }
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "callback_f", sig: "(ILkotlin/jvm/functions/Function1;)V")!
        """, transformers: transformers)
    }

    func testMainActorAsyncFunction() async throws {
        try await check(swift: """
        @MainActor
        public func f(i: Int) async -> Int {
            return i
        }
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
                    let f_return_callback_java = SwiftClosure1.javaObject(for: f_return_callback).toJavaParameter()
                    let p_0_java = Int32(p_0).toJavaParameter()
                    try! Java_SourceKt.callStatic(method: Java_f_methodID, args: [p_0_java, f_return_callback_java])
                }
            }
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "callback_f", sig: "(ILkotlin/jvm/functions/Function1;)V")!
        """, transformers: transformers)
    }

    func testAsyncVoidFunction() async throws {
        try await check(swift: """
        public func f() async {
        }
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
                    let f_return_callback_java = SwiftClosure0.javaObject(for: f_return_callback).toJavaParameter()
                    try! Java_SourceKt.callStatic(method: Java_f_methodID, args: [f_return_callback_java])
                }
            }
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "callback_f", sig: "(Lkotlin/jvm/functions/Function0;)V")!
        """, transformers: transformers)
    }

    func testAsyncThrowsFunction() async throws {
        try await check(swift: """
        public func f() async throws -> Int {
            return 1
        }
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
                        f_continuation.resume(throwing: ThrowableError(throwable: f_error))
                    } else {
                        f_continuation.resume(returning: f_return!)
                    }
                }
                jniContext {
                    let f_return_callback_java = SwiftClosure2.javaObject(for: f_return_callback).toJavaParameter()
                    try! Java_SourceKt.callStatic(method: Java_f_methodID, args: [f_return_callback_java])
                }
            }
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "callback_f", sig: "(Lkotlin/jvm/functions/Function2;)V")!
        """, transformers: transformers)
    }

    func testAsyncThrowsVoidFunction() async throws {
        try await check(swift: """
        public func f(i: Int) async throws {
        }
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
                        f_continuation.resume(throwing: ThrowableError(throwable: f_error))
                    } else {
                        f_continuation.resume()
                    }
                }
                jniContext {
                    let f_return_callback_java = SwiftClosure1.javaObject(for: f_return_callback).toJavaParameter()
                    let p_0_java = Int32(p_0).toJavaParameter()
                    try! Java_SourceKt.callStatic(method: Java_f_methodID, args: [p_0_java, f_return_callback_java])
                }
            }
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "callback_f", sig: "(ILkotlin/jvm/functions/Function1;)V")!
        """, transformers: transformers)
    }

    func testClass() async throws {
        try await check(swift: """
        public class C {
            public var i = 1
        }
        """, kotlin: """
        open class C {
            open var i = 1

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
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
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            public var i: Int {
                get {
                    return jniContext {
                        let value_java: Int32 = try! Java_peer.call(method: Self.Java_get_i_methodID, args: [])
                        return Int(value_java)
                    }
                }
                set {
                    jniContext {
                        let value_java = Int32(newValue).toJavaParameter()
                        try! Java_peer.call(method: Self.Java_set_i_methodID, args: [value_java])
                    }
                }
            }
            private static let Java_get_i_methodID = Java_class.getMethodID(name: "getI", sig: "()I")!
            private static let Java_set_i_methodID = Java_class.getMethodID(name: "setI", sig: "(I)V")!
        }
        """, transformers: transformers)
    }

    func testOpenClass() async throws {
        try await check(swift: """
        open class C {
            open func f() {
            }
        }
        """, kotlin: """
        open class C {
            open fun f() = Unit

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
            public init() {
                Java_peer = jniContext {
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [])
                    return JObject(ptr)
                }
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "()V")!
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            open func f() {
                jniContext {
                    try! Java_peer.call(method: Self.Java_f_methodID, args: [])
                }
            }
            private static let Java_f_methodID = Java_class.getMethodID(name: "f", sig: "()V")!
        }
        """, transformers: transformers)
    }

    func testBridgeIgnoredClass() async throws {
        try await check(swift: """
        @BridgeIgnored 
        public class C {
        }
        // SKIP @BridgeIgnored 
        public class D {
        }
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
        private class C {
        }
        class D {
        }
        """, kotlin: """
        private open class C {
        }
        internal open class D {
        }
        """, swiftBridgeSupport: """
        """, transformers: transformers)
    }

    func testInnerClass() async throws {
        try await checkProducesMessage(swift: """
        public class D {
            public class C {
            }
        }
        """, transformers: transformers)
    }

    func testPrivateConstructor() async throws {
        try await check(swift: """
        public class C {
            private init(i: Int) {
            }
        }
        """, kotlin: """
        open class C {
            private constructor(i: Int) {
            }

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        public class C: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "C")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        """, transformers: transformers)
    }

    func testConstructor() async throws {
        try await check(swift: """
        public class C {
            public init(i: Int) {
            }
        }
        """, kotlin: """
        open class C {
            constructor(i: Int) {
            }

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        public class C: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "C")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            public init(i p_0: Int) {
                Java_peer = jniContext {
                    let p_0_java = Int32(p_0).toJavaParameter()
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [p_0_java])
                    return JObject(ptr)
                }
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(I)V")!
        }
        """, transformers: transformers)
    }

    func testThrowsConstructor() async throws {
        try await check(swift: """
        public class C {
            public init(i: Int) throws {
            }
        }
        """, kotlin: """
        open class C {
            constructor(i: Int) {
            }

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        public class C: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "C")
            public let Java_peer: JObject
            public required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            public init(i p_0: Int) throws {
                Java_peer = try jniContext {
                    let p_0_java = Int32(p_0).toJavaParameter()
                    let ptr = try Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [p_0_java])
                    return JObject(ptr)
                }
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(I)V")!
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
        public class C {
            deinit {
            }
        }
        """, kotlin: """
        open class C {
            open fun finalize() = Unit

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
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
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        """, transformers: transformers)
    }

    func testMemberConstant() async throws {
        try await check(swift: """
        public class C {
            public let i = 0
        }
        """, kotlin: """
        open class C {
            val i = 0

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
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
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            public let i: Int = 0
        }
        """, transformers: transformers)
    }

    func testMemberVar() async throws {
        try await check(swift: """
        public class C {
            public var i = 0
        }
        """, kotlin: """
        open class C {
            open var i = 0

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
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
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            public var i: Int {
                get {
                    return jniContext {
                        let value_java: Int32 = try! Java_peer.call(method: Self.Java_get_i_methodID, args: [])
                        return Int(value_java)
                    }
                }
                set {
                    jniContext {
                        let value_java = Int32(newValue).toJavaParameter()
                        try! Java_peer.call(method: Self.Java_set_i_methodID, args: [value_java])
                    }
                }
            }
            private static let Java_get_i_methodID = Java_class.getMethodID(name: "getI", sig: "()I")!
            private static let Java_set_i_methodID = Java_class.getMethodID(name: "setI", sig: "(I)V")!
        }
        """, transformers: transformers)
    }

    func testMemberFunction() async throws {
        try await check(swift: """
        public class C {
            public func add(a: Int, b: Int) -> Int {
                return a + b
            }
        }
        """, kotlin: """
        open class C {
            open fun add(a: Int, b: Int): Int = a + b

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
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
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            public func add(a p_0: Int, b p_1: Int) -> Int {
                return jniContext {
                    let p_0_java = Int32(p_0).toJavaParameter()
                    let p_1_java = Int32(p_1).toJavaParameter()
                    let f_return_java: Int32 = try! Java_peer.call(method: Self.Java_add_methodID, args: [p_0_java, p_1_java])
                    return Int(f_return_java)
                }
            }
            private static let Java_add_methodID = Java_class.getMethodID(name: "add", sig: "(II)I")!
        }
        """, transformers: transformers)
    }

    func testAsyncMemberFunction() async throws {
        try await check(swift: """
        public class C {
            public func add() async -> Int {
                return 1
            }
        }
        """, kotlin: """
        open class C {
            open suspend fun add(): Int = Async.run l@{
                return@l 1
            }
            fun callback_add(f_return_callback: (Int) -> Unit) {
                Task {
                    f_return_callback(add())
                }
            }

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
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
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            public func add() async -> Int {
                return await withCheckedContinuation { f_continuation in
                    let f_return_callback: (Int) -> Void = { f_return in
                        f_continuation.resume(returning: f_return)
                    }
                    jniContext {
                        let f_return_callback_java = SwiftClosure1.javaObject(for: f_return_callback).toJavaParameter()
                        try! Java_peer.call(method: Self.Java_add_methodID, args: [f_return_callback_java])
                    }
                }
            }
            private static let Java_add_methodID = Java_class.getMethodID(name: "callback_add", sig: "(Lkotlin/jvm/functions/Function1;)V")!
        }
        """, transformers: transformers)
    }

    func testStaticConstant() async throws {
        try await check(swift: """
        public class C {
            public static let i = 0
        }
        """, kotlin: """
        open class C {

            companion object: CompanionClass() {
                override val i = 0
            }
            open class CompanionClass {
                open val i
                    get() = C.i
            }
        }
        """, swiftBridgeSupport: """
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
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            public static let i: Int = 0
        }
        """, transformers: transformers)
    }

    func testStaticVar() async throws {
        try await check(swift: """
        public class C {
            public static var i = 0
        }
        """, kotlin: """
        open class C {

            companion object: CompanionClass() {
                override var i = 0
            }
            open class CompanionClass {
                open var i
                    get() = C.i
                    set(newValue) {
                        C.i = newValue
                    }
            }
        }
        """, swiftBridgeSupport: """
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
            private static let Java_Companion_class = try! JClass(name: "C$Companion")
            private static let Java_Companion = JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: "Companion", sig: "LC$Companion;")!))
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            public static var i: Int {
                get {
                    return jniContext {
                        let value_java: Int32 = try! Java_Companion.call(method: Java_Companion_get_i_methodID, args: [])
                        return Int(value_java)
                    }
                }
                set {
                    jniContext {
                        let value_java = Int32(newValue).toJavaParameter()
                        try! Java_Companion.call(method: Java_Companion_set_i_methodID, args: [value_java])
                    }
                }
            }
            private static let Java_Companion_get_i_methodID = Java_Companion_class.getMethodID(name: "getI", sig: "()I")!
            private static let Java_Companion_set_i_methodID = Java_Companion_class.getMethodID(name: "setI", sig: "(I)V")!
        }
        """, transformers: transformers)
    }

    func testStaticFunction() async throws {
        try await check(swift: """
        public class C {
            public static func add(a: Int, b: Int) -> Int {
                return a + b
            }
        }
        """, kotlin: """
        open class C {

            companion object: CompanionClass() {
                override fun add(a: Int, b: Int): Int = a + b
            }
            open class CompanionClass {
                open fun add(a: Int, b: Int): Int = C.add(a = a, b = b)
            }
        }
        """, swiftBridgeSupport: """
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
            private static let Java_Companion_class = try! JClass(name: "C$Companion")
            private static let Java_Companion = JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: "Companion", sig: "LC$Companion;")!))
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            public static func add(a p_0: Int, b p_1: Int) -> Int {
                return jniContext {
                    let p_0_java = Int32(p_0).toJavaParameter()
                    let p_1_java = Int32(p_1).toJavaParameter()
                    let f_return_java: Int32 = try! Java_Companion.call(method: Java_Companion_add_methodID, args: [p_0_java, p_1_java])
                    return Int(f_return_java)
                }
            }
            private static let Java_Companion_add_methodID = Java_Companion_class.getMethodID(name: "add", sig: "(II)I")!
        }
        """, transformers: transformers)
    }

    func testUnbridgedMember() async throws {
        try await check(swift: """
        public class C {
            @BridgeIgnored
            public var i = 1
        }
        """, kotlin: """
        open class C {
            open var i = 1

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
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
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        """, transformers: transformers)
    }

    func testCommonProtocols() async throws {
        try await check(swift: """
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
        open class C: Comparable<C> {
            open var i = 1
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
            open fun hash(into: InOut<Hasher>) {
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

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
        public class C: Equatable, Hashable, Comparable, BridgedFromKotlin {
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
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            public var i: Int {
                get {
                    return jniContext {
                        let value_java: Int32 = try! Java_peer.call(method: Self.Java_get_i_methodID, args: [])
                        return Int(value_java)
                    }
                }
                set {
                    jniContext {
                        let value_java = Int32(newValue).toJavaParameter()
                        try! Java_peer.call(method: Self.Java_set_i_methodID, args: [value_java])
                    }
                }
            }
            private static let Java_get_i_methodID = Java_class.getMethodID(name: "getI", sig: "()I")!
            private static let Java_set_i_methodID = Java_class.getMethodID(name: "setI", sig: "(I)V")!

            public static func ==(lhs: C, rhs: C) -> Bool {
                return jniContext {
                    let lhs_java = lhs.toJavaObject()!
                    let rhs_java = rhs.toJavaObject()!
                    return try! Bool.call(Java_isequal_methodID, on: lhs_java, args: [rhs_java.toJavaParameter()])
                }
            }
            private static let Java_isequal_methodID = Java_class.getMethodID(name: "equals", sig: "(Ljava/lang/Object;)Z")!

            public func hash(into hasher: inout Hasher) {
                let hashCode: Int32 = jniContext {
                    return try! Java_peer.call(method: Self.Java_hashCode_methodID, args: [])
                }
                hasher.combine(hashCode)
            }
            private static let Java_hashCode_methodID = Java_class.getMethodID(name: "hashCode", sig: "()I")!

            public static func <(lhs: C, rhs: C) -> Bool {
                return jniContext {
                    let lhs_java = lhs.toJavaObject()!
                    let rhs_java = rhs.toJavaObject()!
                    let f_return_java = try! Int32.call(Java_compareTo_methodID, on: lhs_java, args: [rhs_java.toJavaParameter()])
                    return f_return_java < 0
                }
            }
            private static let Java_compareTo_methodID = Java_class.getMethodID(name: "compareTo", sig: "(Ljava/lang/Object;)I")!
        }
        """, transformers: transformers)
    }

    func testCodable() async throws {
        try await check(swift: """
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
        open class C: Codable {
            open var i = 1

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

            open fun encode(to: Encoder) = Unit

            constructor(from: Decoder) {
            }

            companion object: CompanionClass() {

                private fun CK(rawValue: String): C.CK? = CK.init(rawValue = rawValue)
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
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
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            public var i: Int {
                get {
                    return jniContext {
                        let value_java: Int32 = try! Java_peer.call(method: Self.Java_get_i_methodID, args: [])
                        return Int(value_java)
                    }
                }
                set {
                    jniContext {
                        let value_java = Int32(newValue).toJavaParameter()
                        try! Java_peer.call(method: Self.Java_set_i_methodID, args: [value_java])
                    }
                }
            }
            private static let Java_get_i_methodID = Java_class.getMethodID(name: "getI", sig: "()I")!
            private static let Java_set_i_methodID = Java_class.getMethodID(name: "setI", sig: "(I)V")!
        }
        """, transformers: transformers)
    }

    func testSubclass() async throws {
        try await checkProducesMessage(swift: """
        public class Base {
        }
        public class Sub: Base {
        }
        """, transformers: transformers)
    }

    func testStruct() async throws {
        try await check(swift: """
        public struct S {
            public var i = 1
            public init(_ s: String) {
                self.i = Int(s) ?? 0
            }
            public mutating func inc() {
                i += 1
            }
        }
        """, kotlin: """
        class S: MutableStruct {
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
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            public var i: Int {
                get {
                    return jniContext {
                        let value_java: Int32 = try! Java_peer.call(method: Self.Java_get_i_methodID, args: [])
                        return Int(value_java)
                    }
                }
                set {
                    jniContext {
                        Java_peer = try! JObject(Java_peer.call(method: Self.Java_scopy_methodID, args: []))
                        let value_java = Int32(newValue).toJavaParameter()
                        try! Java_peer.call(method: Self.Java_set_i_methodID, args: [value_java])
                    }
                }
            }
            private static let Java_get_i_methodID = Java_class.getMethodID(name: "getI", sig: "()I")!
            private static let Java_set_i_methodID = Java_class.getMethodID(name: "setI", sig: "(I)V")!

            public init(_ p_0: String) {
                Java_peer = jniContext {
                    let p_0_java = p_0.toJavaParameter()
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [p_0_java])
                    return JObject(ptr)
                }
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(Ljava/lang/String;)V")!

            public mutating func inc() {
                jniContext {
                    Java_peer = try! JObject(Java_peer.call(method: Self.Java_scopy_methodID, args: []))
                    try! Java_peer.call(method: Self.Java_inc_methodID, args: [])
                }
            }
            private static let Java_inc_methodID = Java_class.getMethodID(name: "inc", sig: "()V")!
        }
        """, transformers: transformers)
    }

    func testProtocolConformance() async throws {
        try await check(swift: """
        @BridgeIgnored
        public protocol Unbridged {
        }
        public protocol P: Unbridged {
            var i: Int { get set }
            func f() -> Int
        }
        public class C: P {
            public func f() {
                return 1
            }
        }
        """, kotlin: """
        interface Unbridged {
        }
        interface P: Unbridged {
            var i: Int
            fun f(): Int
        }
        open class C: P {
            override fun f(): Unit = 1

            companion object: CompanionClass() {
            }
            open class CompanionClass {
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
                        let value_java: Int32 = try! Java_peer.call(method: Self.Java_get_i_methodID, args: [])
                        return Int(value_java)
                    }
                }
                set {
                    jniContext {
                        let value_java = Int32(newValue).toJavaParameter()
                        try! Java_peer.call(method: Self.Java_set_i_methodID, args: [value_java])
                    }
                }
            }
            private static let Java_get_i_methodID = Java_class.getMethodID(name: "getI", sig: "()I")!
            private static let Java_set_i_methodID = Java_class.getMethodID(name: "setI", sig: "(I)V")!
            public func f() -> Int {
                return jniContext {
                    let f_return_java: Int32 = try! Java_peer.call(method: Self.Java_f_methodID, args: [])
                    return Int(f_return_java)
                }
            }
            private static let Java_f_methodID = Java_class.getMethodID(name: "f", sig: "()I")!
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        public class C: P, BridgedFromKotlin {
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
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            public func f() {
                jniContext {
                    try! Java_peer.call(method: Self.Java_f_methodID, args: [])
                }
            }
            private static let Java_f_methodID = Java_class.getMethodID(name: "f", sig: "()V")!
        }
        """, transformers: transformers)
    }

    func testProtocolTypeMembers() async throws {
        try await check(swift: """
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
        open class C {
            open var p: P? = null
                get() = field.sref({ this.p = it })
                set(newValue) {
                    field = newValue.sref()
                }
            open fun f(p: P): P? = null

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
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
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
            public static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            public func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            public var p: (any P)? {
                get {
                    return jniContext {
                        let value_java: JavaObjectPointer? = try! Java_peer.call(method: Self.Java_get_p_methodID, args: [])
                        return P_BridgeImpl?.fromJavaObject(value_java)
                    }
                }
                set {
                    jniContext {
                        let value_java = ((newValue as? JConvertible)?.toJavaObject()).toJavaParameter()
                        try! Java_peer.call(method: Self.Java_set_p_methodID, args: [value_java])
                    }
                }
            }
            private static let Java_get_p_methodID = Java_class.getMethodID(name: "getP", sig: "()LP;")!
            private static let Java_set_p_methodID = Java_class.getMethodID(name: "setP", sig: "(LP;)V")!

            public func f(p p_0: (any P)) -> (any P)? {
                return jniContext {
                    let p_0_java = ((p_0 as? JConvertible)?.toJavaObject())!.toJavaParameter()
                    let f_return_java: JavaObjectPointer? = try! Java_peer.call(method: Self.Java_f_methodID, args: [p_0_java])
                    return P_BridgeImpl?.fromJavaObject(f_return_java)
                }
            }
            private static let Java_f_methodID = Java_class.getMethodID(name: "f", sig: "(LP;)LP;")!
        }
        """, transformers: transformers)
    }

    func testEnum() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToSwift
        enum E {
            case a, b
        }
        """)
    }

    func testEnumWithAssociatedValue() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToSwift
        enum E {
            case a(Int), b
        }
        """)
    }

    func testClassWithExtension() async throws {
        // TODO
//        try await check(swift: """
//        @BridgeToSwift
//        class C {
//        }
//        extension C {
//            static func s() {
//            }
//            func f() {
//            }
//        }
//        """, kotlin: """
//        """, swiftBridgeSupport: """
//        """)
    }

    func testImports() async throws {
        try await check(swift: """
        import Foundation
        public var i: Int {
            return 1
        }
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
                    let value_java: Int32 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, args: [])
                    return Int(value_java)
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()I")!
        """, transformers: transformers)
    }
}
