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
            internal open var s: String // EOL comment

            internal open var i: Int
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

    func testMultilineTriviaPreservation() async throws {
        try await check(swift: """
        /*
         Header comment

         Class comment
         Spanning two lines
         */
        class S {
            var s: String /* EOL comment */

            var i: Int
            func f() -> S {
                /*
                 Copy */
                var copy = self
                /* Double
                 */
                copy.s = s + s
                return copy
            }

            /*
             Func comment
            */
            func f2() {
            }
        }
        """, kotlin: """
        /*
        Header comment

        Class comment
        Spanning two lines
        */
        internal open class S {
            internal open var s: String /* EOL comment */

            internal open var i: Int
            internal open fun f(): S {
                /*
                Copy */
                var copy = this
                /* Double
                */
                copy.s = s + s
                return copy
            }

            /*
            Func comment
            */
            internal open fun f2() = Unit
        }
        """)
    }

    func testTrailingTriviaPreservation() async throws {
        try await check(swift: """
        let x = "1" + "X" // comment 1
        // comment 2
        """, kotlin: """
        internal val x = "1" + "X" // comment 1
        // comment 2
        """)

        try await check(swift: """
        class C {
            func f() {
                if x == 0 {
                    return -1
                    // comment 1
                }
                return x
                // comment 2
            }
            // comment 3
        }
        // comment 4
        """, kotlin: """
        internal open class C {
            internal open fun f() {
                if (x == 0) {
                    return -1
                    // comment 1
                }
                return x
                // comment 2
            }
            // comment 3
        }
        // comment 4
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

        try await check(swift: """
        /* SKIP REPLACE:
        fun f() {
            print("replaced")
        }
        */
        func f() {
            print("original")
        }
        print("here")
        /* SKIP REPLACE: print("kotlin") */
        print("swift")
        """, kotlin: """
        fun f() {
            print("replaced")
        }
        print("here")
        print("kotlin")
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

    func testIfDefinedInsertDirective() async throws {
        try await check(swift: """
        #if SKIP
        func doSomething() {}
        // SKIP INSERT:
        // fun doSomethingElse() = Unit
        #endif
        """, kotlin: """
        internal fun doSomething() = Unit
        fun doSomethingElse() = Unit
        """)

        try await check(swift: """
        #if SKIP
        func doSomething() {}
        // SKIP INSERT:
        // fun doSomethingElse() = Unit
        #else
        #endif
        """, kotlin: """
        internal fun doSomething() = Unit
        fun doSomethingElse() = Unit
        """)
    }

    func testTrailingInsertDirective() async throws {
        try await check(swift: """
        func f() {
            print("Here")
            // SKIP INSERT: print("From Kotlin!")
        }
        """, kotlin: """
        internal fun f() {
            print("Here")
            print("From Kotlin!")
        }
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

    func testSingleLineStatementTrivia() async throws {
        try await check(swift: """
        func f(): Int {
            return 100
        }
        func g(): Int {
            return 100 // Comment
        }
        func h(): Int {
            // Comment
            return 100
        }

        func closure(c: () -> Unit) {
        }
        func i() {
            c({
                // Comment
                f()
            })
        }
        func j() {
            c({
                f() // Comment
            })
        }
        func k() {
            c({ f() })
        }
        """, kotlin: """
        internal fun f() = 100
        internal fun g() = 100 // Comment
        internal fun h() {
            // Comment
            return 100
        }

        internal fun closure(c: () -> Unit) = Unit
        internal fun i() {
            c {
                // Comment
                f()
            }
        }
        internal fun j() {
            c {
                f() // Comment
            }
        }
        internal fun k() {
            c { f() }
        }
        """)
    }

    func testMultlineCommentDepth() async throws {
        try await check(swift: """
        /**
         Comment line
            /*
            Embedded comment
            */
         More comments /* Inline */
         Last line
        */
        func f() {
        }
        """, kotlin: """
        /**
        Comment line
        /*
        Embedded comment
        */
        More comments /* Inline */
        Last line
        */
        internal fun f() = Unit
        """)
    }

    func testIfDefinedComments() async throws {
        try await check(swift: """
        // Leading comment
        #if SKIP
        // Inner comment
        doSomething()
        #else
        // Else comment
        doSomethingElse()
        #endif
        // Trailing comment
        """, kotlin: """
        // Leading comment
        // Inner comment
        doSomething()
        // Trailing comment
        """)

        try await check(swift: """
        // Leading comment
        #if !SKIP
        // Inner comment
        doSomething()
        #endif
        // Trailing comment
        """, kotlin: """
        // Leading comment
        // Trailing comment
        """)
    }
}
