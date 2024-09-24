import XCTest

final class TranspiledBridgingTests: XCTestCase {
    func testPrivate() async throws {
        try await checkProducesMessage(swift: """
        // SKIP @bridge
        private let i = 1
        """)
        
        try await checkProducesMessage(swift: """
        // SKIP @bridge
        fileprivate let i = 1
        """)
    }
    
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
        public let b = true
        """, kotlin: """
        val b = true
        """, swiftBridgeSupport: """
        public let b = true
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

    func testLetUnsupportedLiteral() async throws {
        try await check(swift: """
        // SKIP @bridge
        let s = "ab\\(1 + 1)c"
        """, kotlin: """
        internal val s = "ab${1 + 1}c"
        """, swiftBridgeSupport: """
        private let SourceKt_fileClass = try! JClass(name: "SourceKt")
        var s: String {
            get {
                let value_java: String = try! SourceKt_fileClass.getStatic(field: s_fieldID)
                return value_java
            }
        }
        private let s_fieldID = SourceKt_fileClass.getStaticFieldID(name: "s", sig: "Ljava/lang/String;")!
        """)
    }

    func testStoredVar() async throws {
        try await check(swift: """
        // SKIP @bridge
        var i = 1
        """, kotlin: """
        internal var i = 1
        """, swiftBridgeSupport: """
        private let SourceKt_fileClass = try! JClass(name: "SourceKt")
        var i: Int {
            get {
                let value_java: Int32 = try! SourceKt_fileClass.getStatic(field: i_fieldID)
                return Int(value_java)
            }
            set {
                let value_java = Int32(newValue)
                SourceKt_fileClass.setStatic(field: i_fieldID, value: value_java)
            }
        }
        private let i_fieldID = SourceKt_fileClass.getStaticFieldID(name: "i", sig: "I")!
        """)
    }
}
