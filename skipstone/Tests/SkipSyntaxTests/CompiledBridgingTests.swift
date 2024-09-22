import XCTest

final class CompiledBridgingTests: XCTestCase {
    func testLetLiteral() async throws {
        try await check(swift: """
        // SKIP @bridge
        let i = 1
        """, isSwiftBridge: true, kotlin: """
        internal val i = 1
        """, swiftBridgeSupport: """
        """)

        try await check(swift: """
        // SKIP @bridge
        let i: Int? = nil
        """, isSwiftBridge: true, kotlin: """
        internal val i: Int? = null
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

    func testLetNonLiteral() async throws {
        try await check(swift: """
        // SKIP @bridge
        let i = 1 + 1
        """, isSwiftBridge: true, kotlin: """
        internal val i: Int
            get() {
                val ret_swift = Swift_i()
                return ret_swift.toInt()
            }
        private external fun Swift_i(): Long
        """, swiftBridgeSupport: """
        import SkipJNI
        
        @_cdecl("Java_SourceKt_Swift_1i")
        func SourceKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int64 {
            return i
        }
        """)
    }
}
