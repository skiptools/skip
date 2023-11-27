import XCTest

final class ExternalFunctionTests: XCTestCase {
    func testExternalFunctions() async throws {
        try await check(swift: """
        public final class NativeType {
            // SKIP EXTERN
            public func external_function() -> Int {
                return 1
            }
        }
        """, kotlin: """
        class NativeType {
            external fun external_function(): Int

            companion object {
            }
        }
        """)
    }
}
