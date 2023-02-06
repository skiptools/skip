@testable import Skip
import XCTest

final class TriviaTests: XCTestCase {
    func testTriviaPreservation() async throws {
        try await check(swift: """
        // Header comment

        // Class comment
        // Spanning two lines
        struct S {
            var s: String // EOL comment

            var i: Int
            func f() -> S {
                // Copy
                var copy = self
                // Double
                copy.s = s + s
                return copy
            }

            // Func comment
            func f2() {
            }
        }
        """, kotlin: """
        // Header comment

        // Class comment
        // Spanning two lines
        internal data class S {
            internal var s: String // EOL comment

            internal var i: Long
            internal fun f(): S {
                // Copy
                var copy = this
                // Double
                copy.s = s + s
                return copy
            }

            // Func comment
            internal fun f2(): Unit {
            }

            companion object {
            }
        }
        """)
    }
}
