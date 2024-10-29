import XCTest

final class BridgeToSwiftTests: XCTestCase {
    func testWrongBridgeType() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToKotlin var i = 1
        """)
        
        try await checkProducesMessage(swift: """
        // SKIP @BridgeToKotlin
        var i = 1
        """)
    }

    func testLetSupportedLiteral() async throws {
        try await check(swift: """
        @BridgeToSwift
        let b = true
        """, kotlin: """
        internal val b = true
        """, swiftBridgeSupport: """
        let b = true
        """)

        try await check(swift: """
        @BridgeToSwift
        let i = 1
        """, kotlin: """
        internal val i = 1
        """, swiftBridgeSupport: """
        let i: Int = 1
        """)
        
        try await check(swift: """
        @BridgeToSwift
        let i: Int32 = 1
        """, kotlin: """
        internal val i: Int = 1
        """, swiftBridgeSupport: """
        let i: Int32 = 1
        """)
        
        try await check(swift: """
        @BridgeToSwift
        let d = 5.0
        """, kotlin: """
        internal val d = 5.0
        """, swiftBridgeSupport: """
        let d: Double = 5.0
        """)
        
        try await check(swift: """
        @BridgeToSwift
        let d: Double = 5
        """, kotlin: """
        internal val d: Double = 5.0
        """, swiftBridgeSupport: """
        let d: Double = 5
        """)
        
        try await check(swift: """
        @BridgeToSwift
        let d: Double? = nil
        """, kotlin: """
        internal val d: Double? = null
        """, swiftBridgeSupport: """
        let d: Double? = nil
        """)
        
        try await check(swift: """
        @BridgeToSwift
        let d: Double? = 5
        """, kotlin: """
        internal val d: Double? = 5.0
        """, swiftBridgeSupport: """
        let d: Double? = 5
        """)

        try await check(swift: """
        @BridgeToSwift
        let f = Float(1)
        """, kotlin: """
        internal val f = 1f
        """, swiftBridgeSupport: """
        let f: Float = 1
        """)

        try await check(swift: """
        @BridgeToSwift
        let s = "Hello"
        """, kotlin: """
        internal val s = "Hello"
        """, swiftBridgeSupport: """
        let s = "Hello"
        """)

        try await check(swift: """
        @BridgeToSwift
        let l = Int64(1)
        """, kotlin: """
        internal val l = 1L
        """, swiftBridgeSupport: """
        let l: Int64 = 1
        """)
    }

    func testPublicLetSupportedLiteral() async throws {
        try await check(swift: """
        @BridgeToSwift
        public let b = true
        """, kotlin: """
        val b = true
        """, swiftBridgeSupport: """
        public let b = true
        """)
    }

    func testLetUnsupportedLiteral() async throws {
        try await check(swift: """
        @BridgeToSwift
        let s = "ab\\(1 + 1)c"
        """, kotlin: """
        internal val s = "ab${1 + 1}c"
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        var s: String {
            get {
                return jniContext {
                    let value_java: String = try! Java_SourceKt.callStatic(method: Java_get_s_methodID, args: [])
                    return value_java
                }
            }
        }
        private let Java_get_s_methodID = Java_SourceKt.getStaticMethodID(name: "getS", sig: "()Ljava/lang/String;")!
        """)

        try await check(swift: """
        @BridgeToSwift
        let b: Bool? = true
        """, kotlin: """
        internal val b: Boolean? = true
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        var b: Bool? {
            get {
                return jniContext {
                    let value_java: JavaObjectPointer? = try! Java_SourceKt.callStatic(method: Java_get_b_methodID, args: [])
                    return Bool?.fromJavaObject(value_java)
                }
            }
        }
        private let Java_get_b_methodID = Java_SourceKt.getStaticMethodID(name: "getB", sig: "()Ljava/lang/Boolean;")!
        """)
    }

    func testLetNonLiteral() async throws {
        try await check(swift: """
        @BridgeToSwift
        let i = 1 + 1
        """, kotlin: """
        internal val i = 1 + 1
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        var i: Int {
            get {
                return jniContext {
                    let value_java: Int32 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, args: [])
                    return Int(value_java)
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()I")!
        """)

        try await check(swift: """
        @BridgeToSwift
        let i = Int64(1 + 1)
        """, kotlin: """
        internal val i = Long(1 + 1)
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        var i: Int64 {
            get {
                return jniContext {
                    let value_java: Int64 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, args: [])
                    return value_java
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()J")!
        """)
    }

    func testStoredVar() async throws {
        try await check(swift: """
        @BridgeToSwift
        var i = 1
        """, kotlin: """
        internal var i = 1
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        var i: Int {
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
        """)
    }

    func testPublicVar() async throws {
        try await check(swift: """
        @BridgeToSwift
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
        """)
    }

    func testPrivateVar() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToSwift
        private let i = 1
        """)

        try await checkProducesMessage(swift: """
        @BridgeToSwift
        fileprivate let i = 1
        """)
    }

    func testPrivateSetVar() async throws {
        try await check(swift: """
        @BridgeToSwift
        private(set) var i = 1
        """, kotlin: """
        internal var i = 1
            private set
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        var i: Int {
            get {
                return jniContext {
                    let value_java: Int32 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, args: [])
                    return Int(value_java)
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()I")!
        """)

        try await check(swift: """
        @BridgeToSwift
        private(set) var d: Double {
            get {
                return 1.0
            }
            set {
                print("set")
            }
        }
        """, kotlin: """
        internal var d: Double
            get() = 1.0
            private set(newValue) {
                print("set")
            }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        var d: Double {
            get {
                return jniContext {
                    let value_java: Double = try! Java_SourceKt.callStatic(method: Java_get_d_methodID, args: [])
                    return value_java
                }
            }
        }
        private let Java_get_d_methodID = Java_SourceKt.getStaticMethodID(name: "getD", sig: "()D")!
        """)
    }

    func testWillSetDidSet() async throws {
        try await check(swift: """
        @BridgeToSwift
        private(set) var i: Int32 = 1 {
            willSet {
                print("willSet")
            }
            didSet {
                print("didSet")
            }
        }
        """, kotlin: """
        internal var i: Int = 1
            private set(newValue) {
                print("willSet")
                field = newValue
                print("didSet")
            }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        var i: Int32 {
            get {
                return jniContext {
                    let value_java: Int32 = try! Java_SourceKt.callStatic(method: Java_get_i_methodID, args: [])
                    return value_java
                }
            }
        }
        private let Java_get_i_methodID = Java_SourceKt.getStaticMethodID(name: "getI", sig: "()I")!
        """)
    }

    func testComputedVar() async throws {
        try await check(swift: """
        @BridgeToSwift
        var i: Int64 {
            get {
                return 1
            }
            set {
            }
        }
        """, kotlin: """
        internal var i: Long
            get() = 1
            set(newValue) {
            }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        var i: Int64 {
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
        """)
    }

    func testKeywordVar() async throws {
        try await check(swift: """
        @BridgeToSwift
        public var object: String {
            get {
                return ""
            }
        }
        """, kotlin: """
        val object_: String
            get() = ""
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var object: String {
            get {
                return jniContext {
                    let value_java: String = try! Java_SourceKt.callStatic(method: Java_get_object__methodID, args: [])
                    return value_java
                }
            }
        }
        private let Java_get_object__methodID = Java_SourceKt.getStaticMethodID(name: "getObject_", sig: "()Ljava/lang/String;")!
        """)
    }

    func testThrowsVar() async throws {
        // TODO
    }

    func testAsyncVar() async throws {
        // TODO
    }

    func testOptionalVar() async throws {
        try await check(swift: """
        @BridgeToSwift
        var i: Int? = 1
        """, kotlin: """
        internal var i: Int? = 1
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        var i: Int? {
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
        """)
    }

    func testUnwrappedOptionalVar() async throws {
        // TODO
    }

    func testLazyVar() async throws {
        // TODO
    }

    func testTranspiledBridgedTypeVar() async throws {
        try await check(swift: """
        @BridgeToSwift
        class C {
        }
        @BridgeToSwift
        var c = C()
        """, kotlin: """
        internal open class C {
        }
        internal var c = C()
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
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
        var c: C {
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
        """)
    }

    func testOptionalTranspiledBridgedTypeVar() async throws {
        try await check(swift: """
        @BridgeToSwift
        class C {
        }
        @BridgeToSwift
        var c: C? = C()
        """, kotlin: """
        internal open class C {
        }
        internal var c: C? = C()
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
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
        var c: C? {
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
        """)
    }

    func testCompiledBridgedTypeVar() async throws {
        try await check(swift: """
        @BridgeToSwift
        var c = C()
        """, swiftBridge: """
        @BridgeToKotlin
        class C {
        }
        """, kotlins: ["""
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
        }
        """, """
        internal var c = C()
        """], swiftBridgeSupports: ["""
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
        """, """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        var c: C {
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
        """])
    }

    func testUnbridgableTypeVar() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToSwift
        var c: C = C()
        """)

        try await checkProducesMessage(swift: """
        class C {
        }
        @BridgeToSwift
        var c = C()
        """)
    }

    func testClosureTypeVar() async throws {
        try await check(swift: """
        @BridgeToSwift
        var c: (Int) -> String = { _ in "" }
        """, kotlin: """
        internal var c: (Int) -> String = { _ -> "" }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        var c: (Int) -> String {
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
        """)
    }

    func testVoidClosureTypeVar() async throws {
        try await check(swift: """
        @BridgeToSwift
        var c: () -> Void = { }
        """, kotlin: """
        internal var c: () -> Unit = { ->  }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        var c: () -> Void {
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
        """)
    }

    func testFunction() async throws {
        try await check(swift: """
        @BridgeToSwift
        func f(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        """, kotlin: """
        internal fun f(i: Int, s: String): Int = i + (Int(s) ?: 0)
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        func f(i: Int, s: String) -> Int {
            return jniContext {
                let i_java = Int32(i).toJavaParameter()
                let s_java = s.toJavaParameter()
                let f_return_java: Int32 = try! Java_SourceKt.callStatic(method: Java_f_methodID, args: [i_java, s_java])
                return Int(f_return_java)
            }
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(ILjava/lang/String;)I")!
        """)
    }

    func testPublicFunction() async throws {
        try await check(swift: """
        @BridgeToSwift
        public func f(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        """, kotlin: """
        fun f(i: Int, s: String): Int = i + (Int(s) ?: 0)
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f(i: Int, s: String) -> Int {
            return jniContext {
                let i_java = Int32(i).toJavaParameter()
                let s_java = s.toJavaParameter()
                let f_return_java: Int32 = try! Java_SourceKt.callStatic(method: Java_f_methodID, args: [i_java, s_java])
                return Int(f_return_java)
            }
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(ILjava/lang/String;)I")!
        """)
    }

    func testPrivateFunction() async throws {
        try await checkProducesMessage(swift: """
        @BridgeToSwift
        private func f() { }
        """)

        try await checkProducesMessage(swift: """
        @BridgeToSwift
        fileprivate func f() { }
        """)
    }

    func testThrowsFunction() async throws {
        try await check(swift: """
        @BridgeToSwift
        func f() throws {
        }
        """, kotlin: """
        internal fun f() = Unit
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        func f() throws {
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
        """)
    }

    func testFunctionParameterLabel() async throws {
        try await check(swift: """
        @BridgeToSwift
        func nolabel(_ i: Int) {
        }
        """, kotlin: """
        internal fun nolabel(i: Int) = Unit
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        func nolabel(_ i: Int) {
            jniContext {
                let i_java = Int32(i).toJavaParameter()
                try! Java_SourceKt.callStatic(method: Java_nolabel_methodID, args: [i_java])
            }
        }
        private let Java_nolabel_methodID = Java_SourceKt.getStaticMethodID(name: "nolabel", sig: "(I)V")!
        """)

        // TODO: Combos of internal and external labels
    }

    func testFunctionParameterDefaultValue() async throws {
        // TODO
    }

    func testFunctionParameterTypeOverload() async throws {
        // TODO
    }

    func testFunctionParameterLabelOverload() async throws {
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

    func testVariadicFunction() async throws {
        // TODO
    }

    func testAsyncFunction() async throws {
        try await check(swift: """
        @BridgeToSwift
        func f(i: Int) async -> Int {
            return i
        }
        """, kotlin: """
        internal suspend fun f(i: Int): Int = Async.run l@{
            return@l i
        }
        internal fun callback_f(i: Int, f_return_callback: (Int) -> Unit) {
            Task {
                f_return_callback(f(i = i))
            }
        }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        func f(i: Int) async -> Int {
            return await withCheckedContinuation { f_continuation in
                let f_return_callback: (Int) -> Void = { f_return in
                    f_continuation.resume(returning: f_return)
                }
                jniContext {
                    let f_return_callback_java = SwiftClosure1.javaObject(for: f_return_callback).toJavaParameter()
                    let i_java = Int32(i).toJavaParameter()
                    try! Java_SourceKt.callStatic(method: Java_f_methodID, args: [i_java, f_return_callback_java])
                }
            }
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "callback_f", sig: "(ILkotlin/jvm/functions/Function1;)V")!
        """)

        // TODO: @MainActor, custom actors
    }

    func testAsyncVoidFunction() async throws {
        try await check(swift: """
        @BridgeToSwift
        func f() async {
        }
        """, kotlin: """
        internal suspend fun f(): Unit = Unit
        internal fun callback_f(f_return_callback: () -> Unit) {
            Task {
                f()
                f_return_callback()
            }
        }
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        func f() async {
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
        """)
    }

    func testAsyncThrowsFunction() async throws {
        try await check(swift: """
        @BridgeToSwift
        func f() async throws -> Int {
            return 1
        }
        """, kotlin: """
        internal suspend fun f(): Int = Async.run l@{
            return@l 1
        }
        internal fun callback_f(f_return_callback: (Int?, Throwable?) -> Unit) {
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
        func f() async throws -> Int {
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
        """)
    }

    func testAsyncThrowsVoidFunction() async throws {
        try await check(swift: """
        @BridgeToSwift
        func f(i: Int) async throws {
        }
        """, kotlin: """
        internal suspend fun f(i: Int): Unit = Unit
        internal fun callback_f(i: Int, f_return_callback: (Throwable?) -> Unit) {
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
        func f(i: Int) async throws {
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
                    let i_java = Int32(i).toJavaParameter()
                    try! Java_SourceKt.callStatic(method: Java_f_methodID, args: [i_java, f_return_callback_java])
                }
            }
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "callback_f", sig: "(ILkotlin/jvm/functions/Function1;)V")!
        """)
    }

    func testClass() async throws {
        try await check(swift: """
        @BridgeToSwift
        class C {
            var i = 1
        }
        """, kotlin: """
        internal open class C {
            internal open var i = 1
        }
        """, swiftBridgeSupport: """
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

            var i: Int {
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
        """)
    }

    func testPublicClass() async throws {
        // TODO
    }

    func testPrivateClass() async throws {
        // TODO
    }

    func testInnerClass() async throws {
        // TODO: Include ensuring that outer class is also bridged
    }

    func testPrivateConstructor() async throws {
        // TODO: How do we differentiate between a private constructor and no constructors?
    }

    func testConstructor() async throws {
        try await check(swift: """
        @BridgeToSwift
        class C {
            init(i: Int) {
            }
        }
        """, kotlin: """
        internal open class C {
            internal constructor(i: Int) {
            }
        }
        """, swiftBridgeSupport: """
        class C: BridgedFromKotlin {
            private static let Java_class = try! JClass(name: "C")
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

            init(i: Int) {
                Java_peer = jniContext {
                    let i_java = Int32(i).toJavaParameter()
                    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [i_java])
                    return JObject(ptr)
                }
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(I)V")!
        }
        """)
    }

    func testThrowsConstructor() async throws {
        // TODO
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
        // TODO
    }

    func testAsyncMemberFunction() async throws {
        try await check(swift: """
        @BridgeToSwift
        class C {
            func add() async -> Int {
                return 1
            }
        }
        """, kotlin: """
        internal open class C {
            internal open suspend fun add(): Int = Async.run l@{
                return@l 1
            }
            internal fun callback_add(f_return_callback: (Int) -> Unit) {
                Task {
                    f_return_callback(add())
                }
            }
        }
        """, swiftBridgeSupport: """
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

            func add() async -> Int {
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
        """)
    }

    func testStaticConstant() async throws {
        try await check(swift: """
        @BridgeToSwift
        class C {
            static let i = 0
        }
        """, kotlin: """
        internal open class C {

            companion object {
                internal val i = 0
            }
        }
        """, swiftBridgeSupport: """
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

            static let i: Int = 0
        }
        """)
    }

    func testStaticVar() async throws {
        try await check(swift: """
        @BridgeToSwift
        class C {
            static var i = 0
        }
        """, kotlin: """
        internal open class C {

            companion object {
                internal var i = 0
            }
        }
        """, swiftBridgeSupport: """
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
            private static let Java_Companion_class = try! JClass(name: "C$Companion")
            private static let Java_Companion = JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: "Companion", sig: "LC$Companion;")!))
            static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {
                return .init(Java_ptr: obj!)
            }
            func toJavaObject() -> JavaObjectPointer? {
                return Java_peer.safePointer()
            }

            static var i: Int {
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
        """)
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
