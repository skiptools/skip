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

    func testStruct() async throws {
        try await check(swift: """
        struct A {
        }
        """, kotlin: """
        internal class A: MutableStruct {

            override var supdate: ((Any) -> Unit)? = null

            override fun scopy(): MutableStruct {
                return A()
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
