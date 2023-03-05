@testable import SkipSyntax
import XCTest

final class MemberDeclarationTests: XCTestCase {
    func testOptionalVariableInitialization() async throws {
        try await check(swift: """
        class A {
            var i: Int?
            var j: Int? = nil
            var k = 10
        }
        """, kotlin: """
        internal open class A {
            internal var i: Int? = null
            internal var j: Int? = null
            internal var k = 10

            companion object {
            }
        }
        """)
    }

    func testStaticMembers() async throws {
        try await check(swift: """
        class A {
            static let staticLet = 1
            static var staticVar = 10

            static func staticFunc() -> Int {
                return 20
            }

            var i = 1
        }
        """, kotlin: """
        internal open class A {

            internal var i = 1

            companion object {
                internal val staticLet = 1
                internal var staticVar = 10

                internal fun staticFunc(): Int {
                    return 20
                }
            }
        }
        """)
    }

    func testComputedVariableGetSet() async throws {
        try await check(swift: """
        class A {
            var i: Int {
                return 10
            }
            var j: Int {
                get {
                    return 10
                }
                set {
                    print(newValue)
                }
            }
        }
        """, kotlin: """
        internal open class A {
            internal open val i: Int
                get() {
                    return 10
                }
            internal open var j: Int
                get() {
                    return 10
                }
                set(newValue) {
                    print(newValue)
                }

            companion object {
            }
        }
        """)

        // Custom set label
        try await check(swift: """
        class A {
            var i: Int {
                get {
                    return 10
                }
                set(value) {
                    print(value)
                }
            }
        }
        """, kotlin: """
        internal open class A {
            internal open var i: Int
                get() {
                    return 10
                }
                set(newValue) {
                    val value = newValue
                    print(value)
                }

            companion object {
            }
        }
        """)
    }

    func testVariableWillDidSet() async throws {
        try await check(swift: """
        class A {
            var i = 1 {
                willSet {
                    print(newValue)
                }
            }
            var j = 2 {
                didSet {
                    print(j == 2)
                }
            }
        }
        """, kotlin: """
        internal open class A {
            internal var i = 1
                set(newValue) {
                    print(newValue)
                    field = newValue
                }
            internal var j = 2
                set(newValue) {
                    val oldValue = field
                    field = newValue
                    print(j == 2)
                }

            companion object {
            }
        }
        """)

        // Custom willSet label
        try await check(swift: """
        class A {
            var i = 1 {
                willSet(value) {
                    print(value)
                }
            }
        }
        """, kotlin: """
        internal open class A {
            internal var i = 1
                set(newValue) {
                    val value = newValue
                    print(value)
                    field = newValue
                }

            companion object {
            }
        }
        """)
    }
}
