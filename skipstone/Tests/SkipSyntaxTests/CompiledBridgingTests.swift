import XCTest

final class CompiledBridgingTests: XCTestCase {
    func testPrivate() async throws {
        try await checkProducesMessage(swift: """
        // SKIP @bridge
        private let i = 1
        """, isSwiftBridge: true)

        try await checkProducesMessage(swift: """
        // SKIP @bridge
        fileprivate let i = 1
        """, isSwiftBridge: true)
    }

    func testLetSupportedLiteral() async throws {
        try await check(swift: """
        // SKIP @bridge
        let b = true
        """, isSwiftBridge: true, kotlin: """
        internal val b = true
        """, swiftBridgeSupport: """
        """)

        try await check(swift: """
        // SKIP @bridge
        let i = 1
        """, isSwiftBridge: true, kotlin: """
        internal val i = 1
        """, swiftBridgeSupport: """
        """)

        try await check(swift: """
        // SKIP @bridge
        let i: Int32 = 1
        """, isSwiftBridge: true, kotlin: """
        internal val i: Int = 1
        """, swiftBridgeSupport: """
        """)

        try await check(swift: """
        // SKIP @bridge
        let d = 5.0
        """, isSwiftBridge: true, kotlin: """
        internal val d = 5.0
        """, swiftBridgeSupport: """
        """)

        try await check(swift: """
        // SKIP @bridge
        let d: Double = 5
        """, isSwiftBridge: true, kotlin: """
        internal val d: Double = 5.0
        """, swiftBridgeSupport: """
        """)

        try await check(swift: """
        // SKIP @bridge
        let d: Double? = nil
        """, isSwiftBridge: true, kotlin: """
        internal val d: Double? = null
        """, swiftBridgeSupport: """
        """)

        try await check(swift: """
        // SKIP @bridge
        let d: Double? = 5
        """, isSwiftBridge: true, kotlin: """
        internal val d: Double? = 5.0
        """, swiftBridgeSupport: """
        """)

        try await check(swift: """
        // SKIP @bridge
        let s = "Hello"
        """, isSwiftBridge: true, kotlin: """
        internal val s = "Hello"
        """, swiftBridgeSupport: """
        """)
    }

    func testLetUnsupportedLiteral() async throws {
        try await check(swift: """
        // SKIP @bridge
        let f: Float = 1
        """, isSwiftBridge: true, kotlin: """
        internal val f: Float
            get() {
                val value_swift = Swift_f()
                return value_swift
            }
        private external fun Swift_f(): Float
        """, swiftBridgeSupport: """
        import SkipJNI

        @_cdecl("Java_SourceKt_Swift_1f")
        func SourceKt_Swift_f(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Float {
            let value_swift = f
            return value_swift
        }
        """)

        try await check(swift: """
        // SKIP @bridge
        let i: Int64 = 1
        """, isSwiftBridge: true, kotlin: """
        internal val i: Long
            get() {
                val value_swift = Swift_i()
                return value_swift
            }
        private external fun Swift_i(): Long
        """, swiftBridgeSupport: """
        import SkipJNI

        @_cdecl("Java_SourceKt_Swift_1i")
        func SourceKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int64 {
            let value_swift = i
            return value_swift
        }
        """)
    }

    func testLetNonLiteral() async throws {
        try await check(swift: """
        // SKIP @bridge
        let i = 1 + 1
        """, isSwiftBridge: true, kotlin: """
        internal val i: Int
            get() {
                val value_swift = Swift_i()
                return value_swift.toInt()
            }
        private external fun Swift_i(): Long
        """, swiftBridgeSupport: """
        import SkipJNI
        
        @_cdecl("Java_SourceKt_Swift_1i")
        func SourceKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int64 {
            let value_swift = i
            return value_swift
        }
        """)

        try await check(swift: """
        // SKIP @bridge
        let i: Int32 = 1 + 1
        """, isSwiftBridge: true, kotlin: """
        internal val i: Int
            get() {
                val value_swift = Swift_i()
                return value_swift
            }
        private external fun Swift_i(): Int
        """, swiftBridgeSupport: """
        import SkipJNI

        @_cdecl("Java_SourceKt_Swift_1i")
        func SourceKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int32 {
            let value_swift = i
            return value_swift
        }
        """)

        try await check(swift: """
        // SKIP @bridge
        let s = "ab" + "c"
        """, isSwiftBridge: true, kotlin: """
        internal val s: String
            get() {
                val value_swift = Swift_s()
                return value_swift
            }
        private external fun Swift_s(): String
        """, swiftBridgeSupport: """
        import SkipJNI

        @_cdecl("Java_SourceKt_Swift_1s")
        func SourceKt_Swift_s(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaString {
            let value_swift = s
            return value_swift.toJavaObject()!
        }
        """)
    }

    func testStoredVar() async throws {
        try await check(swift: """
        // SKIP @bridge
        var i = 1
        """, isSwiftBridge: true, kotlin: """
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
        import SkipJNI

        @_cdecl("Java_SourceKt_Swift_1i")
        func SourceKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int64 {
            let value_swift = i
            return value_swift
        }
        @_cdecl("Java_SourceKt_Swift_1i_1set")
        func SourceKt_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: Int64) {
            let value_swift = value
            i = value_swift
        }
        """)

        try await check(swift: """
        // SKIP @bridge
        var s = "" {
            willSet {
                print("willSet")
            }
            didSet {
                print("didSet")
            }
        }
        """, isSwiftBridge: true, kotlin: """
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
        import SkipJNI

        @_cdecl("Java_SourceKt_Swift_1s")
        func SourceKt_Swift_s(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> JavaString {
            let value_swift = s
            return value_swift.toJavaObject()!
        }
        @_cdecl("Java_SourceKt_Swift_1s_1set")
        func SourceKt_Swift_s_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: JavaString) {
            let value_swift = try! String.fromJavaObject(value)
            s = value_swift
        }
        """)
    }
}
