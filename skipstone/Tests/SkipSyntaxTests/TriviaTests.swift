@testable import SkipSyntax
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
        internal class S {
            internal var s: String // EOL comment

            internal var i: Int
            internal fun f(): S {
                // Copy
                var copy = this.valref()
                // Double
                copy.s = (s + s).valref()
                return copy.valref()
            }

            // Func comment
            internal fun f2() {
            }

            internal constructor(s: String, i: Int) {
                this.s = s
                this.i = i
            }

            companion object {
            }
        }
        """)
    }
}
