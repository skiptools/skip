@testable import SkipSyntax
import XCTest

final class TriviaTests: XCTestCase {
    func testTriviaPreservation() async throws {
        try await check(swift: """
        // Header comment

        // Class comment
        // Spanning two lines
        class S {
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
        internal open class S {
            internal var s: String // EOL comment

            internal var i: Int
            internal open fun f(): S {
                // Copy
                var copy = this
                // Double
                copy.s = (s + s).valref()
                return copy
            }

            // Func comment
            internal open fun f2() {
            }

            companion object {
            }
        }
        """)
    }
}
