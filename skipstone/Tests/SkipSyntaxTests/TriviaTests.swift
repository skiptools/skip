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
                copy.s = s + s
                return copy
            }

            // Func comment
            internal open fun f2() = Unit
        }
        """)

        try await check(swift: """
        class S {
            func f() {
                // Comment on single-statement function
                print("foo")
            }
        }
        """, kotlin: """
        internal open class S {
            internal open fun f() {
                // Comment on single-statement function
                print("foo")
            }
        }
        """)
    }

    func testReplaceDirective() async throws {
        try await check(swift: """
        // SKIP REPLACE:
        // fun f() {
        //     print("replaced")
        // }
        func f() {
            print("original")
        }
        print("here")
        """, kotlin: """
        fun f() {
            print("replaced")
        }
        print("here")
        """)
    }

    func testInsertDirective() async throws {
        try await check(swift: """
        func f() {
        }

        // SKIP INSERT:
        // fun insert() {
        //     print("inserted")
        // }

        func g() {
            print("original")
        }
        """, kotlin: """
        internal fun f() = Unit

        fun insert() {
            print("inserted")
        }

        internal fun g() = print("original")
        """)
    }

    func testDeclareDirective() async throws {
        try await check(swift: """
        // SKIP DECLARE:
        // open fun myf()
        func f() {
            print("body")
        }
        """, kotlin: """
        open fun myf() = print("body")
        """)

        try await check(swift: """
        // SKIP DECLARE:
        // open class C: D()
        class C {
            // SKIP DECLARE: var i: Int = 0
            i = 0
        }
        """, kotlin: """
        open class C: D() {
            var i: Int = 0
        }
        """)
    }
}
