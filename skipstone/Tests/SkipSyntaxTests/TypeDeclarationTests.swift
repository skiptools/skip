@testable import SkipSyntax
import XCTest

final class TypeDeclarationTests: XCTestCase {
    func testClass() async throws {
        try await check(swift: """
        class A {
        }
        """, kotlin: """
        internal open class A {

            companion object {
            }
        }
        """)
    }

    func testNestedClass() async throws {
        try await check(swift: """
        class A {
            class B {
            }

            var b: B
        }
        """, kotlin: """
        internal open class A {
            internal open class B {

                companion object {
                }
            }

            internal var b: A.B

            companion object {
            }
        }
        """)
    }

    func testImmutableStruct() async throws {
        try await check(swift: """
        struct A {
            let i: Int

            init(i: Int) {
                self.i = i
            }
        }
        """, kotlin: """
        internal class A {
            internal val i: Int

            internal constructor(i: Int) {
                this.i = i
            }

            companion object {
            }
        }
        """)
    }

    func testMutableStruct() async throws {
        try await check(swift: """
        struct A {
            internal var i: Int

            init(i: Int) {
                self.i = i
            }
        }
        """, kotlin: """
        internal class A: MutableStruct {
            internal var i: Int

            internal constructor(i: Int) {
                this.i = i
            }

            private constructor(copy: MutableStruct) {
                val copy = copy as A
                this.i = copy.i
            }

            override var supdate: ((Any) -> Unit)? = null

            override fun scopy(): MutableStruct {
                return A(this as MutableStruct)
            }

            companion object {
            }
        }
        """)
    }

    func testTypealias() async throws {
        try await check(swift: """
        private typealias IArray = Array<Bool>
        """, kotlin: """
        private typealias IArray = Array<Boolean>
        """)
    }

    func testGenerics() async throws {
        XCTExpectFailure()
        XCTFail("TODO: Generics in classes, structs, extensions, typealiases. Generic where clauses, etc")
    }
}
