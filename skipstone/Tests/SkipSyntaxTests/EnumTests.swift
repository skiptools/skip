@testable import SkipSyntax
import XCTest

final class EnumTests: XCTestCase {
    func testBasic() async throws {
        try await check(swift: """
        enum E {
            case a
            case b
        }
        """, kotlin: """
        internal enum class E: Hashable {
            a,
            b;
        }
        """)
    }

    func testExtends() async throws {
        try await check(swift: """
        enum E: Int {
            case a
            case b
            case c = 100
            case d
        }
        """, kotlin: """
        internal enum class E(val rawValue: Int): Hashable {
            a(0),
            b(1),
            c(100),
            d(101);
        }
        """)

        try await check(swift: """
        enum E: String {
            case a
            case b = "B"
            case c
        }
        """, kotlin: """
        internal enum class E(val rawValue: String): Hashable {
            a("a"),
            b("B"),
            c("c");
        }
        """)
    }

    func testFunction() async throws {
        try await check(swift: """
        enum E: Int {
            case a
            case b

            func plusOne() -> Int {
                return rawValue + 1
            }
        }
        """, kotlin: """
        internal enum class E(val rawValue: Int): Hashable {
            a(0),
            b(1);

            internal fun plusOne(): Int {
                return rawValue + 1
            }
        }
        """)

        try await check(swift: """
        enum E: Int {
            case a

            func plusOne() -> Int {
                return rawValue + 1
            }

            case b
        }
        """, kotlin: """
        internal enum class E(val rawValue: Int): Hashable {
            a(0),

            b(1);

            internal fun plusOne(): Int {
                return rawValue + 1
            }
        }
        """)
    }

    func testAssociatedValue() async throws {
        try await check(swift: """
        enum E {
            case a
            case b(Int = 1, String)
        }
        """, kotlin: """
        internal sealed class E {
            class acase: E() {
            }
            class bcase(val associated0: Int, val associated1: String): E() {
            }

            companion object {
                val a: E = acase()
                fun b(associated0: Int = 1, associated1: String): E {
                    return bcase(associated0, associated1)
                }
            }
        }
        """)
    }

    func testLabeledAssociatedValue() async throws {
        try await check(swift: """
        enum E {
            case a
            case b(i: Int = 1, String)
        }
        """, kotlin: """
        internal sealed class E {
            class acase: E() {
            }
            class bcase(val associated0: Int, val associated1: String): E() {
                val i = associated0
            }

            companion object {
                val a: E = acase()
                fun b(i: Int = 1, associated1: String): E {
                    return bcase(i, associated1)
                }
            }
        }
        """)
    }

    //~~~ also need to test switches, synthesized equals and hashcode
    func testGenericEnum() async throws {
        try await check(swift: """
        enum E<T> {
            case a
            case b(Int = 1, T)
        }
        """, kotlin: """
        internal sealed class E<out T> {
            class acase: E<Nothing>() {
            }
            class bcase<T>(val associated0: Int, val associated1: T): E<T>() {
            }

            companion object {
                val a: E<Nothing> = acase()
                fun <T> b(associated0: Int = 1, associated1: T): E<T> {
                    return bcase(associated0, associated1)
                }
            }
        }
        """)

        try await check(swift: """
        enum E<T, U: Equatable> {
            case a(T)
            case b(U)
        }
        """, kotlin: """
        internal sealed class E<out T, out U> where U: Equatable {
            class acase<T>(val associated0: T): E<T, Nothing>() {
            }
            class bcase<U>(val associated0: U): E<Nothing, U>() where U: Equatable {
            }

            companion object {
                fun <T> a(associated0: T): E<T, Nothing> {
                    return acase(associated0)
                }
                fun <U> b(associated0: U): E<Nothing, U> where U: Equatable {
                    return bcase(associated0)
                }
            }
        }
        """)
    }

    func testEnumUse() async throws {
        try await check(supportingSwift: """
        enum E {
            case a
            case b
        }
        func efunc(e: E) {
        }
        """, swift: """
        efunc(e: .a)
        efunc(e: .b)
        """, kotlin: """
        efunc(e = E.a)
        efunc(e = E.b)
        """)

        try await check(supportingSwift: """
        enum E {
            case a(Int)
            case b
        }
        func efunc(e: E) {
        }
        """, swift: """
        efunc(e: .a(100))
        efunc(e: .b)
        """, kotlin: """
        efunc(e = E.a(100))
        efunc(e = E.b)
        """)
    }
}
