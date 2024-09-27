import XCTest

final class TranspiledBridgingTests: XCTestCase {
    func testLetSupportedLiteral() async throws {
        try await check(swift: """
        // SKIP @bridge
        let b = true
        """, kotlin: """
        internal val b = true
        """, swiftBridgeSupport: """
        let b = true
        """)

        try await check(swift: """
        // SKIP @bridge
        let i = 1
        """, kotlin: """
        internal val i = 1
        """, swiftBridgeSupport: """
        let i: Int = 1
        """)
        
        try await check(swift: """
        // SKIP @bridge
        let i: Int32 = 1
        """, kotlin: """
        internal val i: Int = 1
        """, swiftBridgeSupport: """
        let i: Int32 = 1
        """)
        
        try await check(swift: """
        // SKIP @bridge
        let d = 5.0
        """, kotlin: """
        internal val d = 5.0
        """, swiftBridgeSupport: """
        let d: Double = 5.0
        """)
        
        try await check(swift: """
        // SKIP @bridge
        let d: Double = 5
        """, kotlin: """
        internal val d: Double = 5.0
        """, swiftBridgeSupport: """
        let d: Double = 5
        """)
        
        try await check(swift: """
        // SKIP @bridge
        let d: Double? = nil
        """, kotlin: """
        internal val d: Double? = null
        """, swiftBridgeSupport: """
        let d: Double? = nil
        """)
        
        try await check(swift: """
        // SKIP @bridge
        let d: Double? = 5
        """, kotlin: """
        internal val d: Double? = 5.0
        """, swiftBridgeSupport: """
        let d: Double? = 5
        """)

        try await check(swift: """
        // SKIP @bridge
        let f = Float(1)
        """, kotlin: """
        internal val f = 1f
        """, swiftBridgeSupport: """
        let f: Float = 1
        """)

        try await check(swift: """
        // SKIP @bridge
        let s = "Hello"
        """, kotlin: """
        internal val s = "Hello"
        """, swiftBridgeSupport: """
        let s = "Hello"
        """)

        try await check(swift: """
        // SKIP @bridge
        let l = Int64(1)
        """, kotlin: """
        internal val l = 1L
        """, swiftBridgeSupport: """
        let l: Int64 = 1
        """)
    }

    func testPublicLetSupportedLiteral() async throws {
        try await check(swift: """
        // SKIP @bridge
        public let b = true
        """, kotlin: """
        val b = true
        """, swiftBridgeSupport: """
        public let b = true
        """)
    }

    func testLetUnsupportedLiteral() async throws {
        try await check(swift: """
        // SKIP @bridge
        let s = "ab\\(1 + 1)c"
        """, kotlin: """
        internal val s = "ab${1 + 1}c"
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        var s: String {
            get {
                let value_java: String = try! Java_SourceKt.getStatic(field: Java_s_fieldID)
                return value_java
            }
        }
        private let Java_s_fieldID = Java_SourceKt.getStaticFieldID(name: "s", sig: "Ljava/lang/String;")!
        """)
    }

    func testLetNonLiteral() async throws {
        try await check(swift: """
        // SKIP @bridge
        let i = 1 + 1
        """, kotlin: """
        internal val i = 1 + 1
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        var i: Int {
            get {
                let value_java: Int32 = try! Java_SourceKt.getStatic(field: Java_i_fieldID)
                return Int(value_java)
            }
        }
        private let Java_i_fieldID = Java_SourceKt.getStaticFieldID(name: "i", sig: "I")!
        """)

        try await check(swift: """
        // SKIP @bridge
        let i = Int64(1 + 1)
        """, kotlin: """
        internal val i = Long(1 + 1)
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        var i: Int64 {
            get {
                let value_java: Int64 = try! Java_SourceKt.getStatic(field: Java_i_fieldID)
                return value_java
            }
        }
        private let Java_i_fieldID = Java_SourceKt.getStaticFieldID(name: "i", sig: "J")!
        """)
    }

    func testStoredVar() async throws {
        try await check(swift: """
        // SKIP @bridge
        var i = 1
        """, kotlin: """
        internal var i = 1
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        var i: Int {
            get {
                let value_java: Int32 = try! Java_SourceKt.getStatic(field: Java_i_fieldID)
                return Int(value_java)
            }
            set {
                let value_java = Int32(newValue)
                Java_SourceKt.setStatic(field: Java_i_fieldID, value: value_java)
            }
        }
        private let Java_i_fieldID = Java_SourceKt.getStaticFieldID(name: "i", sig: "I")!
        """)
    }

    func testPublicVar() async throws {
        try await check(swift: """
        // SKIP @bridge
        public var i = 1
        """, kotlin: """
        var i = 1
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public var i: Int {
            get {
                let value_java: Int32 = try! Java_SourceKt.getStatic(field: Java_i_fieldID)
                return Int(value_java)
            }
            set {
                let value_java = Int32(newValue)
                Java_SourceKt.setStatic(field: Java_i_fieldID, value: value_java)
            }
        }
        private let Java_i_fieldID = Java_SourceKt.getStaticFieldID(name: "i", sig: "I")!
        """)
    }

    func testPrivateVar() async throws {
        try await checkProducesMessage(swift: """
        // SKIP @bridge
        private let i = 1
        """)

        try await checkProducesMessage(swift: """
        // SKIP @bridge
        fileprivate let i = 1
        """)
    }

    func testPrivateSetVar() async throws {
        // TODO
    }

    func testWillSetDidSet() async throws {
        // TODO
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

    func testBridgedTypeVar() async throws {
        // TODO
    }

    func testFunction() async throws {
        try await check(swift: """
        // SKIP @bridge
        func f(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        """, kotlin: """
        internal fun f(i: Int, s: String): Int = i + (Int(s) ?: 0)
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        func f(i: Int, s: String) -> Int {
            let i_java = Int32(i).toJavaParameter()
            let s_java = s.toJavaParameter()
            let f_return_java: Int32 = try! Java_SourceKt.callStatic(method: Java_f_methodID, [i_java, s_java])
            return Int(f_return_java)
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(ILjava/lang/String;)I")!
        """)
    }

    func testPublicFunction() async throws {
        try await check(swift: """
        // SKIP @bridge
        public func f(i: Int, s: String) -> Int {
            return i + (Int(s) ?? 0)
        }
        """, kotlin: """
        fun f(i: Int, s: String): Int = i + (Int(s) ?: 0)
        """, swiftBridgeSupport: """
        private let Java_SourceKt = try! JClass(name: "SourceKt")
        public func f(i: Int, s: String) -> Int {
            let i_java = Int32(i).toJavaParameter()
            let s_java = s.toJavaParameter()
            let f_return_java: Int32 = try! Java_SourceKt.callStatic(method: Java_f_methodID, [i_java, s_java])
            return Int(f_return_java)
        }
        private let Java_f_methodID = Java_SourceKt.getStaticMethodID(name: "f", sig: "(ILjava/lang/String;)I")!
        """)
    }

    func testPrivateFunction() async throws {
        try await checkProducesMessage(swift: """
        // SKIP @bridge
        private func f() { }
        """)

        try await checkProducesMessage(swift: """
        // SKIP @bridge
        fileprivate func f() { }
        """)
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

    func testClass() async throws {
        try await check(swift: """
        // SKIP @bridge
        class C {
            var i = 1
        }
        """, kotlin: """
        internal open class C {
            internal open var i = 1
        }
        """, swiftBridgeSupport: """
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

            var i: Int {
                get {
                    let value_java: Int32 = try! Java_peer.get(field: Self.Java_i_fieldID)
                    return Int(value_java)
                }
                set {
                    let value_java = Int32(newValue)
                    Java_peer.set(field: Self.Java_i_fieldID, value: value_java)
                }
            }
            private static let Java_i_fieldID = Java_class.getFieldID(name: "i", sig: "I")!
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
        // SKIP @bridge
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
        class C {
            private static let Java_class = try! JClass(name: "C")
            let Java_peer: JObject

            init(Java_ptr: JavaObjectPointer) {
                Java_peer = JObject(Java_ptr)
            }

            init(i: Int) {
                let i_java = Int32(i).toJavaParameter()
                let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, [i_java])
                Java_peer = JObject(ptr)
            }
            private static let Java_constructor_methodID = Java_class.getMethodID(name: "<init>", sig: "(I)V")!
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
        // TODO
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
