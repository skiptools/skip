import XCTest

final class BridgeToKotlinTests: XCTestCase {
    func testWrongBridgeType() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToSwift
        var i = 1
        """, isSwiftBridge: true)

        try await checkProducesMessage(swift: """
        // SKIP @BridgeToSwift
        var i = 1
        """, isSwiftBridge: true)
    }

    func testLetSupportedLiteral() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        let b = true
        """, kotlin: """
        internal val b = true
        """, swiftBridgeSupport: """
        """)

        try await check(swiftBridge: """
        @BridgeToKotlin
        let i = 1
        """, kotlin: """
        internal val i = 1
        """, swiftBridgeSupport: """
        """)

        try await check(swiftBridge: """
        @BridgeToKotlin
        let i: Int32 = 1
        """, kotlin: """
        internal val i: Int = 1
        """, swiftBridgeSupport: """
        """)

        try await check(swiftBridge: """
        @BridgeToKotlin
        let d = 5.0
        """, kotlin: """
        internal val d = 5.0
        """, swiftBridgeSupport: """
        """)

        try await check(swiftBridge: """
        @BridgeToKotlin
        let d: Double = 5
        """, kotlin: """
        internal val d: Double = 5.0
        """, swiftBridgeSupport: """
        """)

        try await check(swiftBridge: """
        @BridgeToKotlin
        let d: Double? = nil
        """, kotlin: """
        internal val d: Double? = null
        """, swiftBridgeSupport: """
        """)

        try await check(swiftBridge: """
        @BridgeToKotlin
        let d: Double? = 5
        """, kotlin: """
        internal val d: Double? = 5.0
        """, swiftBridgeSupport: """
        """)

        try await check(swiftBridge: """
        @BridgeToKotlin
        let s = "Hello"
        """, kotlin: """
        internal val s = "Hello"
        """, swiftBridgeSupport: """
        """)
    }

    func testPublicLetSupportedLiteral() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        public let b = true
        """, kotlin: """
        val b = true
        """, swiftBridgeSupport: """
        """)
    }

    func testLetUnsupportedLiteral() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        let f: Float = 1
        """, kotlin: """
        internal val f: Float
            get() = Swift_f()
        private external fun Swift_f(): Float
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f")
        func BridgeKt_Swift_f(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Float {
            return f
        }
        """)

        try await check(swiftBridge: """
        @BridgeToKotlin
        let i: Int64 = 1
        """, kotlin: """
        internal val i: Long
            get() = Swift_i()
        private external fun Swift_i(): Long
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int64 {
            return i
        }
        """)

        try await check(swiftBridge: """
        @BridgeToKotlin
        let s = "ab\\(1 + 1)c"
        """, kotlin: """
        internal val s: String
            get() = Swift_s()
        private external fun Swift_s(): String
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1s")
        func BridgeKt_Swift_s(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaString {
            return s.toJavaObject()!
        }
        """)
    }

    func testLetNonLiteral() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        let i = 1 + 1
        """, kotlin: """
        internal val i: Int
            get() = Swift_i()
        private external fun Swift_i(): Int
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int32 {
            return Int32(i)
        }
        """)

        try await check(swiftBridge: """
        @BridgeToKotlin
        let i: Int32 = 1 + 1
        """, kotlin: """
        internal val i: Int
            get() = Swift_i()
        private external fun Swift_i(): Int
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int32 {
            return i
        }
        """)

        try await check(swiftBridge: """
        @BridgeToKotlin
        let s = "ab" + "c"
        """, kotlin: """
        internal val s: String
            get() = Swift_s()
        private external fun Swift_s(): String
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1s")
        func BridgeKt_Swift_s(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaString {
            return s.toJavaObject()!
        }
        """)
    }

    func testStoredVar() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        var i = 1
        """, kotlin: """
        internal var i: Int
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
        """)

        try await check(swiftBridge: """
        @BridgeToKotlin
        var s = ""
        """, kotlin: """
        internal var s: String
            get() = Swift_s()
            set(newValue) {
                Swift_s_set(newValue)
            }
        private external fun Swift_s(): String
        private external fun Swift_s_set(value: String)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1s")
        func BridgeKt_Swift_s(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaString {
            return s.toJavaObject()!
        }
        @_cdecl("Java_BridgeKt_Swift_1s_1set")
        func BridgeKt_Swift_s_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaString) {
            s = String.fromJavaObject(value)
        }
        """)
    }

    func testPublicVar() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
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
        """)
    }

    func testPrivateVar() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToKotlin
        private let i = 1
        """, isSwiftBridge: true)

        try await checkProducesMessage(swift: """
        @BridgeToKotlin
        fileprivate let i = 1
        """, isSwiftBridge: true)
    }

    func testPrivateSetVar() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        private(set) var i = 1
        """, kotlin: """
        internal val i: Int
            get() = Swift_i()
        private external fun Swift_i(): Int
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int32 {
            return Int32(i)
        }
        """)

        try await check(swiftBridge: """
        @BridgeToKotlin
        private(set) var d: Double {
            get {
                return 1.0
            }
            set {
                print("set")
            }
        }
        """, kotlin: """
        internal val d: Double
            get() = Swift_d()
        private external fun Swift_d(): Double
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1d")
        func BridgeKt_Swift_d(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Double {
            return d
        }
        """)
    }

    func testUnicodeNameVar() async throws {
        // TODO
    }

    func testWillSetDidSet() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        var s = "" {
            willSet {
                print("willSet")
            }
            didSet {
                print("didSet")
            }
        }
        """, kotlin: """
        internal var s: String
            get() = Swift_s()
            set(newValue) {
                Swift_s_set(newValue)
            }
        private external fun Swift_s(): String
        private external fun Swift_s_set(value: String)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1s")
        func BridgeKt_Swift_s(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaString {
            return s.toJavaObject()!
        }
        @_cdecl("Java_BridgeKt_Swift_1s_1set")
        func BridgeKt_Swift_s_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaString) {
            s = String.fromJavaObject(value)
        }
        """)
    }

    func testComputedVar() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        var i: Int64 {
            get {
                return 1
            }
            set {
            }
        }
        """, kotlin: """
        internal var i: Long
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
        """)
    }

    func testArrayVar() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        var a = [1, 2, 3]
        """, kotlin: """
        import skip.lib.Array

        internal var a: Array<Int>
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
            return a.toJavaObject()!
        }
        @_cdecl("Java_BridgeKt_Swift_1a_1set")
        func BridgeKt_Swift_a_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer) {
            a = [Int].fromJavaObject(value)
        }
        """)
    }

    func testKeywordVar() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
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
            return object.toJavaObject()!
        }
        """)
    }

    func testThrowsVar() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToKotlin
        var i: Int {
            get throws {
                return 0
            }
        }
        """, isSwiftBridge: true)
    }

    func testAsyncVar() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToKotlin
        var i: Int {
            get async {
                return 0
            }
        }
        """, isSwiftBridge: true)
    }

    func testOptionalVar() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        var i: Int? = 1
        """, kotlin: """
        internal var i: Int?
            get() = Swift_i()
            set(newValue) {
                Swift_i_set(newValue)
            }
        private external fun Swift_i(): Int?
        private external fun Swift_i_set(value: Int?)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer? {
            return i.toJavaObject()
        }
        @_cdecl("Java_BridgeKt_Swift_1i_1set")
        func BridgeKt_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer?) {
            i = Int?.fromJavaObject(value)
        }
        """)
    }

    func testUnwrappedOptionalVar() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToKotlin
        var s: String!
        """, isSwiftBridge: true)
    }

    func testLazyVar() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToKotlin
        lazy var s: String = createString()
        """, isSwiftBridge: true)
    }

    func testTranspiledBridgedTypeVar() async throws {
        try await check(swift: """
        @BridgeToSwift
        class C {
        }
        """, swiftBridge: """
        @BridgeToKotlin
        var c = C()
        """, kotlins: ["""
        internal var c: C
            get() = Swift_c()
            set(newValue) {
                Swift_c_set(newValue)
            }
        private external fun Swift_c(): C
        private external fun Swift_c_set(value: C)
        """, """
        internal open class C {
        }
        """], swiftBridgeSupports: ["""
        @_cdecl("Java_BridgeKt_Swift_1c")
        func BridgeKt_Swift_c(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer {
            return c.toJavaObject()!
        }
        @_cdecl("Java_BridgeKt_Swift_1c_1set")
        func BridgeKt_Swift_c_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer) {
            c = C.fromJavaObject(value)
        }
        """, """
        class C: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "C")
            let Java_peer: JObject
            required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            init() {
                Java_peer = jniContext {
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [])
                    return JObject(ptr)
                }
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "()V")!
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        """])
    }

    func testOptionalTranspiledBridgedTypeVar() async throws {
        try await check(swift: """
        @BridgeToSwift
        class C {
        }
        """, swiftBridge: """
        @BridgeToKotlin
        var c: C? = C()
        """, kotlins: ["""
        internal var c: C?
            get() = Swift_c()
            set(newValue) {
                Swift_c_set(newValue)
            }
        private external fun Swift_c(): C?
        private external fun Swift_c_set(value: C?)
        """, """
        internal open class C {
        }
        """], swiftBridgeSupports: ["""
        @_cdecl("Java_BridgeKt_Swift_1c")
        func BridgeKt_Swift_c(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer? {
            return c.toJavaObject()
        }
        @_cdecl("Java_BridgeKt_Swift_1c_1set")
        func BridgeKt_Swift_c_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer?) {
            c = C?.fromJavaObject(value)
        }
        """, """
        class C: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "C")
            let Java_peer: JObject
            required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            init() {
                Java_peer = jniContext {
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [])
                    return JObject(ptr)
                }
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "()V")!
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        """])
    }

    func testCompiledBridgedTypeVar() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        class C {
        }
        @BridgeToKotlin
        var c = C()
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer
        
            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()
        }
        internal var c: C
            get() = Swift_c()
            set(newValue) {
                Swift_c_set(newValue)
            }
        private external fun Swift_c(): C
        private external fun Swift_c_set(value: C)
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
        @_cdecl("Java_BridgeKt_Swift_1c")
        func BridgeKt_Swift_c(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer {
            return c.toJavaObject()!
        }
        @_cdecl("Java_BridgeKt_Swift_1c_1set")
        func BridgeKt_Swift_c_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer) {
            c = C.fromJavaObject(value)
        }
        """)
    }

    func testOptionalCompiledBridgedTypeVar() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        class C {
        }
        @BridgeToKotlin
        var c: C? = C()
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer
        
            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()
        }
        internal var c: C?
            get() = Swift_c()
            set(newValue) {
                Swift_c_set(newValue)
            }
        private external fun Swift_c(): C?
        private external fun Swift_c_set(value: C?)
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
        @_cdecl("Java_BridgeKt_Swift_1c")
        func BridgeKt_Swift_c(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer? {
            return c.toJavaObject()
        }
        @_cdecl("Java_BridgeKt_Swift_1c_1set")
        func BridgeKt_Swift_c_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer?) {
            c = C?.fromJavaObject(value)
        }
        """)
    }

    func testUnbridgableTypeVar() async throws {
        try await checkProducesMessage(swift: """
        class C {
        }
        @BridgeToKotlin
        var c: C = C()
        """, isSwiftBridge: true)
    }

    func testClosureTypeVar() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        var c: (Int) -> String = { _ in "" }
        """, kotlin: """
        internal var c: (Int) -> String
            get() = Swift_c()
            set(newValue) {
                Swift_c_set(newValue)
            }
        private external fun Swift_c(): (Int) -> String
        private external fun Swift_c_set(value: (Int) -> String)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1c")
        func BridgeKt_Swift_c(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer {
            return SwiftClosure1.javaObject(for: c)!
        }
        @_cdecl("Java_BridgeKt_Swift_1c_1set")
        func BridgeKt_Swift_c_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer) {
            c = SwiftClosure1.closure(forJavaObject: value)!
        }
        """)
    }

    func testVoidClosureTypeVar() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        var c: () -> Void = { }
        """, kotlin: """
        internal var c: () -> Unit
            get() = Swift_c()
            set(newValue) {
                Swift_c_set(newValue)
            }
        private external fun Swift_c(): () -> Unit
        private external fun Swift_c_set(value: () -> Unit)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1c")
        func BridgeKt_Swift_c(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer {
            return SwiftClosure0.javaObject(for: c)!
        }
        @_cdecl("Java_BridgeKt_Swift_1c_1set")
        func BridgeKt_Swift_c_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer) {
            c = SwiftClosure0.closure(forJavaObject: value)!
        }
        """)
    }

    func testFunction() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        func f(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        """, kotlin: """
        internal fun f(i: Int, s: String): Int = Swift_f_0(i, s)
        private external fun Swift_f_0(i: Int, s: String): Int
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32, _ p_1: JavaString) -> Int32 {
            let p_0_swift = Int(p_0)
            let p_1_swift = String.fromJavaObject(p_1)
            let f_return_swift = f(i: p_0_swift, s: p_1_swift)
            return Int32(f_return_swift)
        }
        """)
    }

    func testPublicFunction() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
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
            let p_1_swift = String.fromJavaObject(p_1)
            let f_return_swift = f(i: p_0_swift, s: p_1_swift)
            return Int32(f_return_swift)
        }
        """)
    }

    func testPrivateFunction() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToKotlin
        private func f() { }
        """, isSwiftBridge: true)

        try await checkProducesMessage(swift: """
        @BridgeToKotlin
        fileprivate func f() { }
        """, isSwiftBridge: true)
    }

    func testThrowsFunction() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        func f() throws -> Int {
            return 1
        }
        """, kotlin: """
        internal fun f(): Int = Swift_f_0()!!
        private external fun Swift_f_0(): Int?
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer? {
            do {
                let f_return_swift = try f()
                return f_return_swift.toJavaObject()
            } catch {
                JavaThrowError(error, env: Java_env)
                return nil
            }
        }
        """)
    }

    func testThrowsVoidFunction() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        func f(i: Int) throws {
        }
        """, kotlin: """
        internal fun f(i: Int): Unit = Swift_f_0(i)
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
        """)
    }

    func testFunctionParameterLabel() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        func f(_ i: Int) {
        }
        """, kotlin: """
        internal fun f(i: Int): Unit = Swift_f_0(i)
        private external fun Swift_f_0(i: Int)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32) {
            let p_0_swift = Int(p_0)
            f(p_0_swift)
        }
        """)
    }

    func testFunctionParameterDefaultValue() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        func f(i: Int = 0) -> Int {
            return i
        }
        """, kotlin: """
        internal fun f(i: Int = 0): Int = Swift_f_0(i)
        private external fun Swift_f_0(i: Int): Int
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32) -> Int32 {
            let p_0_swift = Int(p_0)
            let f_return_swift = f(i: p_0_swift)
            return Int32(f_return_swift)
        }
        """)
    }

    func testFunctionParameterLabelOverload() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        func f(i: Int) -> Int {
            return i
        }
        @BridgeToKotlin
        func f(value: Int) -> Int {
            return value
        }
        """, kotlin: """
        internal fun f(i: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null): Int = Swift_f_0(i)
        private external fun Swift_f_0(i: Int): Int
        internal fun f(value: Int): Int = Swift_f_1(value)
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
        """)
    }

    func testKeywordFunction() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        func object(object: Int) {
        }
        """, kotlin: """
        internal fun object_(object_: Int): Unit = Swift_object_0(object_)
        private external fun Swift_object_0(object_: Int)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1object_10")
        func BridgeKt_Swift_object_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: Int32) {
            let p_0_swift = Int(p_0)
            object(object: p_0_swift)
        }
        """)
    }

    func testOptionalFunction() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        func f(i: Int?) -> Int? {
            return nil
        }
        """, kotlin: """
        internal fun f(i: Int?): Int? = Swift_f_0(i)
        private external fun Swift_f_0(i: Int?): Int?
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaObjectPointer?) -> JavaObjectPointer? {
            let p_0_swift = Int?.fromJavaObject(p_0)
            let f_return_swift = f(i: p_0_swift)
            return f_return_swift.toJavaObject()
        }
        """)
    }

    func testBridgedObjectFunction() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        class C {
        }
        @BridgeToKotlin
        func f(c: C) -> C {
        }
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()
        }
        internal fun f(c: C): C = Swift_f_0(c)
        private external fun Swift_f_0(c: C): C
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
        @_cdecl("Java_BridgeKt_Swift_1f_10")
        func BridgeKt_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ p_0: JavaObjectPointer) -> JavaObjectPointer {
            let p_0_swift = C.fromJavaObject(p_0)
            let f_return_swift = f(c: p_0_swift)
            return f_return_swift.toJavaObject()!
        }
        """)
    }

    func testVariadicFunction() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToKotlin
        func f(i: Int...) { }
        """, isSwiftBridge: true)
    }

    func testAsyncFunction() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        func f(i: Int) async -> Int {
            return i
        }
        """, kotlin: """
        internal suspend fun f(i: Int): Int = Async.run {
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
            let f_callback_swift = SwiftClosure1.closure(forJavaObject: f_callback)! as (Int) -> Void
            Task {
                let f_return_swift = await f(i: p_0_swift)
                f_callback_swift(f_return_swift)
            }
        }
        """)
    }

    func testMainActorAsyncFunction() async throws {
        try await check(swiftBridge: """
        @MainActor @BridgeToKotlin
        func f(i: Int) async -> Int {
            return i
        }
        """, kotlin: """
        internal suspend fun f(i: Int): Int = MainActor.run {
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
            let f_callback_swift = SwiftClosure1.closure(forJavaObject: f_callback)! as (Int) -> Void
            Task {
                let f_return_swift = await f(i: p_0_swift)
                f_callback_swift(f_return_swift)
            }
        }
        """)
    }

    func testAsyncVoidFunction() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        func f() async {
        }
        """, kotlin: """
        internal suspend fun f(): Unit = Async.run {
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
            let f_callback_swift = SwiftClosure0.closure(forJavaObject: f_callback)! as () -> Void
            Task {
                await f()
                f_callback_swift()
            }
        }
        """)
    }

    func testAsyncThrowsFunction() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        func f() async throws -> Int {
            return 1
        }
        """, kotlin: """
        internal suspend fun f(): Int = Async.run {
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
            let f_callback_swift = SwiftClosure2.closure(forJavaObject: f_callback)! as (Int?, JavaObjectPointer?) -> Void
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
        """)
    }

    func testAsyncThrowsVoidFunction() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        func f(i: Int) async throws {
        }
        """, kotlin: """
        internal suspend fun f(i: Int): Unit = Async.run {
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
            let f_callback_swift = SwiftClosure1.closure(forJavaObject: f_callback)! as (JavaObjectPointer?) -> Void
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
        """)
    }

    func testClass() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        class C {
            var i = 1
        }
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer
        
            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            internal open var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Int)
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
        """)
    }

    func testOpenClass() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        open class C {
            open var i = 1
        }
        """, kotlin: """
        open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            open var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Int)

            companion object: CompanionClass() {
            }
            open class CompanionClass {
            }
        }
        """, swiftBridgeSupport: """
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
        """)
    }

    func testInnerClass() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToKotlin
        class D {
            @BridgeToKotlin
            class C {
            }
        }
        """, isSwiftBridge: true)
    }

    func testPrivateClass() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToKotlin
        private class C {
        }
        """, isSwiftBridge: true)
    }

    func testPrivateConstructor() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        class C {
            private init(i: Int) {
            }
        }
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
        }
        @_cdecl("Java_C_Swift_1release")
        func C_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            Swift_peer.release(as: C.self)
        }
        """)
    }

    func testConstructor() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        class C {
            init(i: Int) {
            }
        }
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer
        
            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            internal constructor(i: Int) {
                Swift_peer = Swift_constructor_0(i)
            }
            private external fun Swift_constructor_0(i: Int): skip.bridge.SwiftObjectPointer
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
        """)
    }

    func testThrowsConstructor() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        class C {
            init(i: Int) throws {
            }
        }
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            internal constructor(i: Int) {
                Swift_peer = Swift_constructor_0(i)!!
            }
            private external fun Swift_constructor_0(i: Int): skip.bridge.SwiftObjectPointer
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(JLskip/bridge/SwiftPeerMarker;)V")!
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
        """)
    }

    func testOptionalConstructor() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToKotlin
        class C {
            init?(i: Int) {
                return nil
            }
        }
        """, isSwiftBridge: true)
    }

    func testDestructor() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        class C {
            deinit {
            }
        }
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
        """)
    }

    func testMemberConstant() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        class C {
            let i = 0
        }
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            internal val i = 0
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
        """)
    }

    func testMemberVar() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        class C {
            var i = 0
        }
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            internal open var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Int)
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
        """)
    }

    func testMemberFunction() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        class C {
            func add(a: Int, b: Int) -> Int {
                return a + b
            }
        }
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()
        
            internal open fun add(a: Int, b: Int): Int = Swift_add_0(Swift_peer, a, b)
            private external fun Swift_add_0(Swift_peer: skip.bridge.SwiftObjectPointer, a: Int, b: Int): Int
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
        """)
    }

    func testAsyncMemberFunction() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        class C {
            func add() async -> Int {
                return 1
            }
        }
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            internal open suspend fun add(): Int = Async.run {
                kotlin.coroutines.suspendCoroutine { f_continuation ->
                    Swift_callback_add_0(Swift_peer) { f_return ->
                        f_continuation.resumeWith(kotlin.Result.success(f_return))
                    }
                }
            }
            private external fun Swift_callback_add_0(Swift_peer: skip.bridge.SwiftObjectPointer, f_callback: (Int) -> Unit)
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
            let f_callback_swift = SwiftClosure1.closure(forJavaObject: f_callback)! as (Int) -> Void
            let peer_swift: C = Swift_peer.pointee()!
            Task {
                let f_return_swift = await peer_swift.add()
                f_callback_swift(f_return_swift)
            }
        }
        """)
    }

    func testStaticConstant() async throws {
        try await check(swiftBridge: """
        // SKIP @BridgeToKotlin
        class C {
            static let i = 0
        }
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            companion object {

                internal val i = 0
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
        """)
    }

    func testStaticVar() async throws {
        try await check(swiftBridge: """
        // SKIP @BridgeToKotlin
        class C {
            static var i = 0
        }
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer
        
            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            companion object {

                internal var i: Int
                    get() = Swift_Companion_i()
                    set(newValue) {
                        Swift_Companion_i_set(newValue)
                    }
                private external fun Swift_Companion_i(): Int
                private external fun Swift_Companion_i_set(value: Int)
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
        """)
    }

    func testStaticFunction() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        class C {
            static func add(a: Int, b: Int) -> Int {
                return a + b
            }
        }
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            companion object {

                internal fun add(a: Int, b: Int): Int = Swift_Companion_add_0(a, b)
                private external fun Swift_Companion_add_0(a: Int, b: Int): Int
            }
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
        """)
    }

    func testUnbridgedMember() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        class C {
            @BridgeIgnored
            var i = 1
        }
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
        """)
    }

    func testCommonProtocols() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        class C: Equatable, Hashable, Comparable {
            var i = 1
            static func ==(lhs: C, rhs: C) -> Bool {
                return lhs.i == rhs.i
            }
            func hash(into hasher: inout Hasher) {
                hasher.combine(i)
            }
            static func <(lhs: C, rhs: C) -> Bool {
                return lhs.i < rhs.i
            }
        }
        """, kotlin: """
        internal open class C: Comparable<C>, skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer

            internal open var i: Int
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
            internal open fun hash(into: InOut<Hasher>) {
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
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
            let lhs_swift = C.fromJavaObject(lhs)
            let rhs_swift = C.fromJavaObject(rhs)
            return lhs_swift == rhs_swift
        }
        @_cdecl("Java_C_Swift_1hashvalue")
        func C_Swift_hashvalue(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int64 {
            let peer_swift: C = Swift_peer.pointee()!
            return Int64(peer_swift.hashValue)
        }
        @_cdecl("Java_C_Swift_1islessthan")
        func C_Swift_islessthan(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ lhs: JavaObjectPointer, _ rhs: JavaObjectPointer) -> Bool {
            let lhs_swift = C.fromJavaObject(lhs)
            let rhs_swift = C.fromJavaObject(rhs)
            return lhs_swift < rhs_swift
        }
        """)
    }

    func testCodable() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        class C: Codable {
            var i = 1
        
            private enum CK: CodingKey {
                case i
            }

            func encode(to encoder: Encoder) {
            }

            init(from decoder: Decoder) {
            }
        }
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer
        
            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            internal open var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Int)
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
        """)
    }

    func testSubclass() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToKotlin
        class Base {
        }
        @BridgeToKotlin
        class Sub: Base {
        }
        """, isSwiftBridge: true)
    }

    func testStruct() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        struct S {
            var i = 1
            init(s: String) {
                self.i = Int(s)!
            }
            func f() -> Int {
                return i
            }
        }
        """, kotlin: """
        internal class S: MutableStruct, skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

            constructor(Swift_peer: skip.bridge.SwiftObjectPointer, marker: skip.bridge.SwiftPeerMarker?) {
                this.Swift_peer = Swift_peer
            }

            fun finalize() {
                Swift_release(Swift_peer)
                Swift_peer = skip.bridge.SwiftObjectNil
            }
            private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            internal var i: Int
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
            internal constructor(s: String) {
                Swift_peer = Swift_constructor_0(s)
            }
            private external fun Swift_constructor_0(s: String): skip.bridge.SwiftObjectPointer
            internal fun f(): Int = Swift_f_1(Swift_peer)
            private external fun Swift_f_1(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private constructor(copy: MutableStruct) {
                Swift_peer = Swift_constructor_2(copy)
            }
            private external fun Swift_constructor_2(copy: MutableStruct): skip.bridge.SwiftObjectPointer

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(this as MutableStruct)
        }
        """, swiftBridgeSupport: """
        extension S: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "S")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                let box: SwiftValueTypeBox<Self> = ptr.pointee()!
                return box.value
            }
            func toJavaObject() -> JavaObjectPointer? {
                let box = SwiftValueTypeBox(self)
                let Swift_peer = SwiftObjectPointer.pointer(to: box, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
            let p_0_swift = String.fromJavaObject(p_0)
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
            let p_0_swift = S.fromJavaObject(p_0)
            let f_return_swift = SwiftValueTypeBox(p_0_swift)
            return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)
        }
        """)
    }

    func testProtocolConformance() async throws {
        try await check(swiftBridge: """
        protocol Unbridged {
            func a()
        }
        @BridgeToKotlin
        protocol Base: Equatable, Hashable {
            func a()
        }
        @BridgeToKotlin
        protocol P: Base, Unbridged {
            func f() -> Int
        }
        @BridgeToKotlin
        class C: P {
            func a() {
            }
            func f() {
                return 1
            }
        }
        """, kotlin: """
        internal interface Base {
            fun a()
        }
        internal interface P: Base {
            fun f(): Int
        }
        internal open class C: P, skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            override fun a(): Unit = Swift_a_0(Swift_peer)
            private external fun Swift_a_0(Swift_peer: skip.bridge.SwiftObjectPointer)
            override fun f(): Unit = Swift_f_1(Swift_peer)
            private external fun Swift_f_1(Swift_peer: skip.bridge.SwiftObjectPointer)
        }
        """, swiftBridgeSupport: """
        final class Base_BridgeImpl: Base, BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "Base")
            let Java_peer: JObject
            required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            func a() {
                jniContext {
                    try! Java_peer.call(method: Self.Java_a_methodID, args: [])
                }
            }
            private static let Java_a_methodID = Java_class.getMethodID(name: "a", sig: "()V")!
            static func ==(lhs: Base_BridgeImpl, rhs: Base_BridgeImpl) -> Bool {
                return jniContext {
                    let lhs_java = lhs.toJavaObject()!
                    let rhs_java = rhs.toJavaObject()!
                    return try! Bool.call(Java_isequal_methodID, on: lhs_java, args: [rhs_java.toJavaParameter()])
                }
            }
            private static let Java_isequal_methodID = Java_class.getMethodID(name: "equals", sig: "(Ljava/lang/Object;)Z")!
            func hash(into hasher: inout Hasher) {
                let hashCode: Int32 = jniContext {
                    return try! Java_peer.call(method: Self.Java_hashCode_methodID, args: [])
                }
                hasher.combine(hashCode)
            }
            private static let Java_hashCode_methodID = Java_class.getMethodID(name: "hashCode", sig: "()I")!
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        final class P_BridgeImpl: P, BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "P")
            let Java_peer: JObject
            required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            func f() -> Int {
                return jniContext {
                    let f_return_java: Int32 = try! Java_peer.call(method: Self.Java_f_methodID, args: [])
                    return Int(f_return_java)
                }
            }
            private static let Java_f_methodID = Java_class.getMethodID(name: "f", sig: "()I")!
            func a() {
                jniContext {
                    try! Java_peer.call(method: Self.Java_a_methodID, args: [])
                }
            }
            private static let Java_a_methodID = Java_class.getMethodID(name: "a", sig: "()V")!
            static func ==(lhs: P_BridgeImpl, rhs: P_BridgeImpl) -> Bool {
                return jniContext {
                    let lhs_java = lhs.toJavaObject()!
                    let rhs_java = rhs.toJavaObject()!
                    return try! Bool.call(Java_isequal_methodID, on: lhs_java, args: [rhs_java.toJavaParameter()])
                }
            }
            private static let Java_isequal_methodID = Java_class.getMethodID(name: "equals", sig: "(Ljava/lang/Object;)Z")!
            func hash(into hasher: inout Hasher) {
                let hashCode: Int32 = jniContext {
                    return try! Java_peer.call(method: Self.Java_hashCode_methodID, args: [])
                }
                hasher.combine(hashCode)
            }
            private static let Java_hashCode_methodID = Java_class.getMethodID(name: "hashCode", sig: "()I")!
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
        """)
    }

    func testProtocolTypeMembers() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin
        protocol P {
        }
        @BridgeToKotlin
        class C {
            var p: (any P)?
            func f(p: any P) -> (any P)? {
                return nil
            }
        }
        """, kotlin: """
        internal interface P {
        }
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            internal open var p: P?
                get() = Swift_p(Swift_peer).sref({ this.p = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    Swift_p_set(Swift_peer, newValue)
                }
            private external fun Swift_p(Swift_peer: skip.bridge.SwiftObjectPointer): P?
            private external fun Swift_p_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: P?)
            internal open fun f(p: P): P? = Swift_f_0(Swift_peer, p)
            private external fun Swift_f_0(Swift_peer: skip.bridge.SwiftObjectPointer, p: P): P?
        }
        """, swiftBridgeSupport: """
        final class P_BridgeImpl: P, BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "P")
            let Java_peer: JObject
            required init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }
        }
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
            return ((peer_swift.p as? JConvertible)?.toJavaObject())
        }
        @_cdecl("Java_C_Swift_1p_1set")
        func C_Swift_p_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: JavaObjectPointer?) {
            let peer_swift: C = Swift_peer.pointee()!
            peer_swift.p = P_BridgeImpl?.fromJavaObject(value)
        }
        @_cdecl("Java_C_Swift_1f_10")
        func C_Swift_f_0(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ p_0: JavaObjectPointer) -> JavaObjectPointer? {
            let p_0_swift = P_BridgeImpl.fromJavaObject(p_0)
            let peer_swift: C = Swift_peer.pointee()!
            let f_return_swift = peer_swift.f(p: p_0_swift)
            return ((f_return_swift as? JConvertible)?.toJavaObject())
        }
        """)
    }

    func testEnum() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToKotlin
        enum E {
            case a, b
        }
        """, isSwiftBridge: true)
    }

    func testEnumWithAssociatedValue() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToKotlin
        enum E {
            case a(Int), b
        }
        """, isSwiftBridge: true)
    }

    func testClassWithExtension() async throws {
        // TODO
//        try await check(swiftBridge: """
//        @BridgeToKotlin
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

    func testObservable() async throws {
        try await check(swiftBridge: """
        @BridgeToKotlin @Observable
        class C {
            var i = 1
        }
        """, kotlin: """
        internal open class C: skip.bridge.SwiftPeerBridged {
            var Swift_peer: skip.bridge.SwiftObjectPointer

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

            override fun Swift_bridgedPeer(): skip.bridge.SwiftObjectPointer = Swift_peer

            override fun equals(other: Any?): Boolean {
                if (other !is skip.bridge.SwiftPeerBridged) return false
                return Swift_peer == other.Swift_bridgedPeer()
            }

            override fun hashCode(): Int = Swift_peer.hashCode()

            internal open var i: Int
                get() = Swift_i(Swift_peer)
                set(newValue) {
                    Swift_i_set(Swift_peer, newValue)
                }
            private external fun Swift_i(Swift_peer: skip.bridge.SwiftObjectPointer): Int
            private external fun Swift_i_set(Swift_peer: skip.bridge.SwiftObjectPointer, value: Int)
        }
        """, swiftBridgeSupport: """
        extension C: BridgedToKotlin {
            private static let Java_class = try! JClass(name: "C")
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                let ptr = SwiftObjectPointer.peer(of: obj!)
                return ptr.pointee()!
            }
            func toJavaObject() -> JavaObjectPointer? {
                let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)
                return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])
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
        """, appendToSource: """
        import struct SkipBridge.Observation
        """)
    }
}
