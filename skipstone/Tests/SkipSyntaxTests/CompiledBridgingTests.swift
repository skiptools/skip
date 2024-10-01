import XCTest

final class CompiledBridgingTests: XCTestCase {
    func testLetSupportedLiteral() async throws {
        try await check(swiftBridge: """
        // SKIP @bridge
        let b = true
        """, kotlin: """
        internal val b = true
        """, swiftBridgeSupport: """
        """)

        try await check(swiftBridge: """
        // SKIP @bridge
        let i = 1
        """, kotlin: """
        internal val i = 1
        """, swiftBridgeSupport: """
        """)

        try await check(swiftBridge: """
        // SKIP @bridge
        let i: Int32 = 1
        """, kotlin: """
        internal val i: Int = 1
        """, swiftBridgeSupport: """
        """)

        try await check(swiftBridge: """
        // SKIP @bridge
        let d = 5.0
        """, kotlin: """
        internal val d = 5.0
        """, swiftBridgeSupport: """
        """)

        try await check(swiftBridge: """
        // SKIP @bridge
        let d: Double = 5
        """, kotlin: """
        internal val d: Double = 5.0
        """, swiftBridgeSupport: """
        """)

        try await check(swiftBridge: """
        // SKIP @bridge
        let d: Double? = nil
        """, kotlin: """
        internal val d: Double? = null
        """, swiftBridgeSupport: """
        """)

        try await check(swiftBridge: """
        // SKIP @bridge
        let d: Double? = 5
        """, kotlin: """
        internal val d: Double? = 5.0
        """, swiftBridgeSupport: """
        """)

        try await check(swiftBridge: """
        // SKIP @bridge
        let s = "Hello"
        """, kotlin: """
        internal val s = "Hello"
        """, swiftBridgeSupport: """
        """)
    }

    func testPublicLetSupportedLiteral() async throws {
        try await check(swiftBridge: """
        // SKIP @bridge
        public let b = true
        """, kotlin: """
        val b = true
        """, swiftBridgeSupport: """
        """)
    }

    func testLetUnsupportedLiteral() async throws {
        try await check(swiftBridge: """
        // SKIP @bridge
        let f: Float = 1
        """, kotlin: """
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        internal val f: Float
            get() {
                val value_swift = Swift_f()
                return value_swift
            }
        private external fun Swift_f(): Float
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f")
        func BridgeKt_Swift_f(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Float {
            let value_swift = f
            return value_swift
        }
        """)

        try await check(swiftBridge: """
        // SKIP @bridge
        let i: Int64 = 1
        """, kotlin: """
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        internal val i: Long
            get() {
                val value_swift = Swift_i()
                return value_swift
            }
        private external fun Swift_i(): Long
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int64 {
            let value_swift = i
            return value_swift
        }
        """)

        try await check(swiftBridge: """
        // SKIP @bridge
        let s = "ab\\(1 + 1)c"
        """, kotlin: """
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        internal val s: String
            get() {
                val value_swift = Swift_s()
                return value_swift
            }
        private external fun Swift_s(): String
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1s")
        func BridgeKt_Swift_s(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaString {
            let value_swift = s
            return value_swift.toJavaObject()!
        }
        """)
    }

    func testLetNonLiteral() async throws {
        try await check(swiftBridge: """
        // SKIP @bridge
        let i = 1 + 1
        """, kotlin: """
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        internal val i: Int
            get() {
                val value_swift = Swift_i()
                return value_swift.toInt()
            }
        private external fun Swift_i(): Long
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int64 {
            let value_swift = i
            return Int64(value_swift)
        }
        """)

        try await check(swiftBridge: """
        // SKIP @bridge
        let i: Int32 = 1 + 1
        """, kotlin: """
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        internal val i: Int
            get() {
                val value_swift = Swift_i()
                return value_swift
            }
        private external fun Swift_i(): Int
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int32 {
            let value_swift = i
            return value_swift
        }
        """)

        try await check(swiftBridge: """
        // SKIP @bridge
        let s = "ab" + "c"
        """, kotlin: """
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        internal val s: String
            get() {
                val value_swift = Swift_s()
                return value_swift
            }
        private external fun Swift_s(): String
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1s")
        func BridgeKt_Swift_s(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaString {
            let value_swift = s
            return value_swift.toJavaObject()!
        }
        """)
    }

    func testStoredVar() async throws {
        try await check(swiftBridge: """
        // SKIP @bridge
        var i = 1
        """, kotlin: """
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        internal var i: Int
            get() {
                val value_swift = Swift_i()
                return value_swift.toInt()
            }
            set(newValue) {
                val newValue_swift = newValue.toLong()
                Swift_i_set(newValue_swift)
            }
        private external fun Swift_i(): Long
        private external fun Swift_i_set(value: Long)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int64 {
            let value_swift = i
            return Int64(value_swift)
        }
        @_cdecl("Java_BridgeKt_Swift_1i_1set")
        func BridgeKt_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: Int64) {
            let value_swift = Int(value)
            i = value_swift
        }
        """)

        try await check(swiftBridge: """
        // SKIP @bridge
        var s = ""
        """, kotlin: """
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        internal var s: String
            get() {
                val value_swift = Swift_s()
                return value_swift
            }
            set(newValue) {
                val newValue_swift = newValue
                Swift_s_set(newValue_swift)
            }
        private external fun Swift_s(): String
        private external fun Swift_s_set(value: String)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1s")
        func BridgeKt_Swift_s(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaString {
            let value_swift = s
            return value_swift.toJavaObject()!
        }
        @_cdecl("Java_BridgeKt_Swift_1s_1set")
        func BridgeKt_Swift_s_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaString) {
            let value_swift = try! String.fromJavaObject(value)
            s = value_swift
        }
        """)
    }

    func testPublicVar() async throws {
        try await check(swiftBridge: """
        // SKIP @bridge
        public var i = 1
        """, kotlin: """
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        var i: Int
            get() {
                val value_swift = Swift_i()
                return value_swift.toInt()
            }
            set(newValue) {
                val newValue_swift = newValue.toLong()
                Swift_i_set(newValue_swift)
            }
        private external fun Swift_i(): Long
        private external fun Swift_i_set(value: Long)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int64 {
            let value_swift = i
            return Int64(value_swift)
        }
        @_cdecl("Java_BridgeKt_Swift_1i_1set")
        func BridgeKt_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: Int64) {
            let value_swift = Int(value)
            i = value_swift
        }
        """)
    }

    func testPrivateVar() async throws {
        try await checkProducesMessage(swift: """
        // SKIP @bridge
        private let i = 1
        """, isSwiftBridge: true)

        try await checkProducesMessage(swift: """
        // SKIP @bridge
        fileprivate let i = 1
        """, isSwiftBridge: true)
    }

    func testPrivateSetVar() async throws {
        try await check(swiftBridge: """
        // SKIP @bridge
        private(set) var i = 1
        """, kotlin: """
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        internal val i: Int
            get() {
                val value_swift = Swift_i()
                return value_swift.toInt()
            }
        private external fun Swift_i(): Long
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1i")
        func BridgeKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int64 {
            let value_swift = i
            return Int64(value_swift)
        }
        """)

        try await check(swiftBridge: """
        // SKIP @bridge
        private(set) var d: Double {
            get {
                return 1.0
            }
            set {
                print("set")
            }
        }
        """, kotlin: """
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        internal val d: Double
            get() {
                val value_swift = Swift_d()
                return value_swift
            }
        private external fun Swift_d(): Double
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1d")
        func BridgeKt_Swift_d(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Double {
            let value_swift = d
            return value_swift
        }
        """)
    }

    func testUnicodeNameVar() async throws {
        // TODO
    }

    func testWillSetDidSet() async throws {
        try await check(swiftBridge: """
        // SKIP @bridge
        var s = "" {
            willSet {
                print("willSet")
            }
            didSet {
                print("didSet")
            }
        }
        """, kotlin: """
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        internal var s: String
            get() {
                val value_swift = Swift_s()
                return value_swift
            }
            set(newValue) {
                val newValue_swift = newValue
                Swift_s_set(newValue_swift)
            }
        private external fun Swift_s(): String
        private external fun Swift_s_set(value: String)
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1s")
        func BridgeKt_Swift_s(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaString {
            let value_swift = s
            return value_swift.toJavaObject()!
        }
        @_cdecl("Java_BridgeKt_Swift_1s_1set")
        func BridgeKt_Swift_s_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaString) {
            let value_swift = try! String.fromJavaObject(value)
            s = value_swift
        }
        """)
    }

    func testComputedVar() async throws {
        // TODO
    }

    func testKeywordVar() async throws {
        // TODO
    }

    func testThrowsVar() async throws {
        // TODO
    }

    func testAsyncVar() async throws {
        // TODO
    }

    func testOptionalVar() async throws {
        // TODO
    }

    func testUnwrappedOptionalVar() async throws {
        // TODO
    }

    func testLazyVar() async throws {
        // TODO
    }

    func testTranspiledBridgedTypeVar() async throws {
        try await check(swift: """
        // SKIP @bridge
        class C {
        }
        """, swiftBridge: """
        // SKIP @bridge
        var c = C()
        """, kotlins: ["""
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        internal var c: C
            get() {
                val value_swift = Swift_c()
                return value_swift
            }
            set(newValue) {
                val newValue_swift = newValue
                Swift_c_set(newValue_swift)
            }
        private external fun Swift_c(): C
        private external fun Swift_c_set(value: C)
        """, """
        internal open class C {
        }
        """], swiftBridgeSupports: ["""
        @_cdecl("Java_BridgeKt_Swift_1c")
        func BridgeKt_Swift_c(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaObjectPointer {
            let value_swift = c
            return value_swift.Java_peer.ptr
        }
        @_cdecl("Java_BridgeKt_Swift_1c_1set")
        func BridgeKt_Swift_c_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaObjectPointer) {
            let value_swift = C(Java_ptr: value)
            c = value_swift
        }
        """, """
        class C {
            private static let Java_class = try! JClass(name: "C")
            let Java_peer: JObject

            init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }

            init() {
                let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, [])
                Java_peer = JObject(ptr)
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "()V")!
        }
        """])
    }

    func testCompiledBridgedTypeVar() async throws {
        // TODO
    }

    func testUnbridgableTypeVar() async throws {
        // TODO
    }

    func testFunction() async throws {
        try await check(swiftBridge: """
        // SKIP @bridge
        func f(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        """, kotlin: """
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        internal fun f(i: Int, s: String): Int {
            val i_swift = i.toLong()
            val s_swift = s
            val f_return_swift = Swift_f(i_swift, s_swift)
            return f_return_swift.toInt()
        }
        private external fun Swift_f(i: Long, s: String): Long
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f")
        func BridgeKt_Swift_f(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ i: Int64, _ s: JavaString) -> Int64 {
            let i_swift = Int(i)
            let s_swift = try! String.fromJavaObject(s)
            let f_return_swift = f(i: i_swift, s: s_swift)
            return Int64(f_return_swift)
        }
        """)
    }

    func testPublicFunction() async throws {
        try await check(swiftBridge: """
        // SKIP @bridge
        public func f(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        """, kotlin: """
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        fun f(i: Int, s: String): Int {
            val i_swift = i.toLong()
            val s_swift = s
            val f_return_swift = Swift_f(i_swift, s_swift)
            return f_return_swift.toInt()
        }
        private external fun Swift_f(i: Long, s: String): Long
        """, swiftBridgeSupport: """
        @_cdecl("Java_BridgeKt_Swift_1f")
        func BridgeKt_Swift_f(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ i: Int64, _ s: JavaString) -> Int64 {
            let i_swift = Int(i)
            let s_swift = try! String.fromJavaObject(s)
            let f_return_swift = f(i: i_swift, s: s_swift)
            return Int64(f_return_swift)
        }
        """)
    }

    func testPrivateFunction() async throws {
        try await checkProducesMessage(swift: """
        // SKIP @bridge
        private func f() { }
        """, isSwiftBridge: true)

        try await checkProducesMessage(swift: """
        // SKIP @bridge
        fileprivate func f() { }
        """, isSwiftBridge: true)
    }

    func testFunctionParameterLabel() async throws {
        // TODO: Combos of internal and external labels
    }

    func testFunctionParameterDefaultValue() async throws {
        // TODO
    }

    func testFunctionParameterTypeOverload() async throws {
        // TODO
    }

    func testFunctionLabelOverload() async throws {
        // TODO
    }

    func testKeywordFunction() async throws {
        // TODO: name and internal, external parameter name keywords
    }

    func testOptionalFunction() async throws {
        // TODO: Parameter and return optionals
    }

    func testBridgedObjectFunction() async throws {
        // TODO: Parameter and return bridged types
    }

    func testUnbridgableObjectFunction() async throws {
        // TODO: Parameter and return bridged types
    }

    func testVariadicFunction() async throws {
        // TODO
    }

    func testClass() async throws {
        try await check(swiftBridge: """
        // SKIP @bridge
        class C {
            var i = 1
        }
        """, kotlin: """
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        internal open class C {
            var Swift_peer: SwiftObjectPointer

            constructor(Swift_peer: SwiftObjectPointer) {
                this.Swift_peer = Swift_ptrref(Swift_peer)
            }
            private external fun Swift_ptrref(Swift_peer: SwiftObjectPointer): SwiftObjectPointer

            fun finalize() {
                Swift_ptrderef(Swift_peer)
                Swift_peer = SwiftObjectNil
            }
            private external fun Swift_ptrderef(Swift_peer: SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): SwiftObjectPointer

            internal open var i: Int
                get() {
                    val value_swift = Swift_i(Swift_peer)
                    return value_swift.toInt()
                }
                set(newValue) {
                    val newValue_swift = newValue.toLong()
                    Swift_i_set(Swift_peer, newValue_swift)
                }
            private external fun Swift_i(Swift_peer: SwiftObjectPointer): Long
            private external fun Swift_i_set(Swift_peer: SwiftObjectPointer, value: Long)
        }
        """, swiftBridgeSupport: """
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.forSwift(f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1ptrref")
        func C_Swift_ptrref(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> SwiftObjectPointer {
            return refSwift(Swift_peer, type: C.self)
        }
        @_cdecl("Java_C_Swift_1ptrderef")
        func C_Swift_ptrderef(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            derefSwift(Swift_peer, type: C.self)
        }
        @_cdecl("Java_C_Swift_1i")
        func C_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> Int64 {
            let peer_swift: C = Swift_peer.toSwift()
            let value_swift = peer_swift.i
            return Int64(value_swift)
        }
        @_cdecl("Java_C_Swift_1i_1set")
        func C_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ value: Int64) {
            let value_swift = Int(value)
            let peer_swift: C = Swift_peer.toSwift()
            peer_swift.i = value_swift
        }
        """)
    }

    func testPublicClass() async throws {
        // TODO
    }

    func testInnerClass() async throws {
        // TODO: Include ensuring that outer class is also bridged
    }

    func testPrivateClass() async throws {
        // TODO
    }

    func testPrivateConstructor() async throws {
        // TODO: How do we differentiate between a private constructor and no constructors?
    }

    func testConstructor() async throws {
        try await check(swiftBridge: """
        // SKIP @bridge
        class C {
            init(i: Int) {
            }
        }
        """, kotlin: """
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        internal open class C {
            var Swift_peer: SwiftObjectPointer

            constructor(Swift_peer: SwiftObjectPointer) {
                this.Swift_peer = Swift_ptrref(Swift_peer)
            }
            private external fun Swift_ptrref(Swift_peer: SwiftObjectPointer): SwiftObjectPointer

            fun finalize() {
                Swift_ptrderef(Swift_peer)
                Swift_peer = SwiftObjectNil
            }
            private external fun Swift_ptrderef(Swift_peer: SwiftObjectPointer)

            internal constructor(i: Int) {
                val i_swift = i.toLong()
                Swift_peer = Swift_constructor(i_swift)
            }
            private external fun Swift_constructor(i: Long): SwiftObjectPointer
        }
        """, swiftBridgeSupport: """
        @_cdecl("Java_C_Swift_1ptrref")
        func C_Swift_ptrref(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> SwiftObjectPointer {
            return refSwift(Swift_peer, type: C.self)
        }
        @_cdecl("Java_C_Swift_1ptrderef")
        func C_Swift_ptrderef(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            derefSwift(Swift_peer, type: C.self)
        }
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ i: Int64) -> SwiftObjectPointer {
            let i_swift = Int(i)
            let f_return_swift = C(i: i_swift)
            return SwiftObjectPointer.forSwift(f_return_swift, retain: true)
        }
        """)
    }

    func testDestructor() async throws {
        // TODO
    }

    func testMemberConstant() async throws {
        // TODO
    }

    func testMemberVar() async throws {
        // TODO
    }

    func testMemberFunction() async throws {
        try await check(swiftBridge: """
        // SKIP @bridge
        class C {
            func add(a: Int, b: Int) -> Int {
                return a + b
            }
        }
        """, kotlin: """
        import skip.bridge.SwiftObjectNil
        import skip.bridge.SwiftObjectPointer

        internal open class C {
            var Swift_peer: SwiftObjectPointer

            constructor(Swift_peer: SwiftObjectPointer) {
                this.Swift_peer = Swift_ptrref(Swift_peer)
            }
            private external fun Swift_ptrref(Swift_peer: SwiftObjectPointer): SwiftObjectPointer

            fun finalize() {
                Swift_ptrderef(Swift_peer)
                Swift_peer = SwiftObjectNil
            }
            private external fun Swift_ptrderef(Swift_peer: SwiftObjectPointer)

            constructor() {
                Swift_peer = Swift_constructor()
            }
            private external fun Swift_constructor(): SwiftObjectPointer

            internal open fun add(a: Int, b: Int): Int {
                val a_swift = a.toLong()
                val b_swift = b.toLong()
                val f_return_swift = Swift_add(Swift_peer, a_swift, b_swift)
                return f_return_swift.toInt()
            }
            private external fun Swift_add(Swift_peer: SwiftObjectPointer, a: Long, b: Long): Long
        }
        """, swiftBridgeSupport: """
        @_cdecl("Java_C_Swift_1constructor")
        func C_Swift_constructor(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> SwiftObjectPointer {
            let f_return_swift = C()
            return SwiftObjectPointer.forSwift(f_return_swift, retain: true)
        }
        @_cdecl("Java_C_Swift_1ptrref")
        func C_Swift_ptrref(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) -> SwiftObjectPointer {
            return refSwift(Swift_peer, type: C.self)
        }
        @_cdecl("Java_C_Swift_1ptrderef")
        func C_Swift_ptrderef(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer) {
            derefSwift(Swift_peer, type: C.self)
        }
        @_cdecl("Java_C_Swift_1add")
        func C_Swift_add(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_peer: SwiftObjectPointer, _ a: Int64, _ b: Int64) -> Int64 {
            let a_swift = Int(a)
            let b_swift = Int(b)
            let peer_swift: C = Swift_peer.toSwift()
            let f_return_swift = peer_swift.add(a: a_swift, b: b_swift)
            return Int64(f_return_swift)
        }
        """)
    }

    func testStaticVar() async throws {
        // TODO
    }

    func testStaticFunction() async throws {
        // TODO
    }

    func testUnbridgedMember() async throws {
        // TODO
    }

    func testBridgedMemberInUnbridgedClass() async throws {
        // TODO
    }

    func testCommonProtocols() async throws {
        // TODO: Handling of Equatable, Hashable, Codable, etc
    }

    func testSubclass() async throws {
        // TODO: Include superclass override property, inherited superclass constructors (param default values may be a problem?)
    }

    func testClassInit() async throws {
        // TODO
    }

    func testClassDeinit() async throws {
        // TODO
    }
}
