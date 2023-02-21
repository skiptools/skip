@testable import Skip
import XCTest

final class ConstructorTests: XCTestCase {
    func testBaseClassNoConstructor() async throws {
        try await check(swift: """
        class A {
        }

        class B: A {
        }

        class C: A {
            init() {
            }
        }

        class D: A {
            init() {
                super.init()
            }
        }
        """, kotlin: """
        internal open class A {

            companion object {
            }
        }

        internal open class B: A() {

            companion object {
            }
        }

        internal open class C: A() {
            internal constructor() {
            }

            companion object {
            }
        }

        internal open class D: A {
            internal constructor(): super() {
            }

            companion object {
            }
        }
        """)
    }

    func testBaseClassConstructorNoParameters() async throws {
        try await check(swift: """
        class A {
            init() {
            }
        }

        class B: A {
        }

        class C: A {
            override init() {
            }
        }

        class D: A {
            init(i: Int) {
            }
        }

        class E: A {
            init(i: Int) {
                super.init()
            }
        }
        """, kotlin: """
        internal open class A {
            internal constructor() {
            }

            companion object {
            }
        }

        internal open class B: A {
            internal constructor(): super() {
            }

            companion object {
            }
        }

        internal open class C: A() {
            internal constructor() {
            }

            companion object {
            }
        }

        internal open class D: A() {
            internal constructor(i: Int) {
            }

            companion object {
            }
        }

        internal open class E: A {
            internal constructor(i: Int): super() {
            }

            companion object {
            }
        }
        """)
    }

    func testBaseClassConstructorWithParameters() async throws {
        try await check(swift: """
        class A {
            let i: Int
            let s: String

            init(i: Int, s: String) {
                self.i = i
                self.s = s
            }

            convenience init(both: Int) {
                self.init(i: both, s: "\\(both)")
            }
        }
        """, kotlin: """
        internal open class A {
            internal val i: Int
            internal val s: String

            internal constructor(i: Int, s: String) {
                this.i = i
                this.s = s
            }

            internal constructor(both: Int): this(i = both, s = "${both}") {
            }

            companion object {
            }
        }
        """)
    }
}
