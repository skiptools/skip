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
        internal class A: ValueSemantics {

            override var valupdate: ((Any) -> Unit)? = null

            override fun valcopy(): ValueSemantics {
                return A()
            }

            companion object {
            }
        }
        """)
    }
}
