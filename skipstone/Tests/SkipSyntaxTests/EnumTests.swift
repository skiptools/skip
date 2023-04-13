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
        internal enum class E {
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
        internal enum class E(val rawValue: Int) {
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
        internal enum class E(val rawValue: String) {
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
        internal enum class E(val rawValue: Int) {
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
        internal enum class E(val rawValue: Int) {
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

    func testGenericEnum() async throws {
        try await check(swift: """
        enum E<T> {
            case a
            case b(Int = 1, T)
        }
        """, kotlin: """
        internal sealed class E<out T> where T: Any {
            class acase: E<Nothing>() {
            }
            class bcase<T>(val associated0: Int, val associated1: T): E<T>() where T: Any {
            }

            companion object {
                val a: E<Nothing> = acase()
                fun <T> b(associated0: Int = 1, associated1: T): E<T> where T: Any {
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
        internal sealed class E<out T, out U> where T: Any, U: Any {
            class acase<T>(val associated0: T): E<T, Nothing>() where T: Any {
            }
            class bcase<U>(val associated0: U): E<Nothing, U>() where U: Any {
            }

            companion object {
                fun <T> a(associated0: T): E<T, Nothing> where T: Any {
                    return acase(associated0)
                }
                fun <U> b(associated0: U): E<Nothing, U> where U: Any {
                    return bcase(associated0)
                }
            }
        }
        """)
    }

    func testAssociatedValueEnumSynthesizedEqualsHash() async throws {
        try await check(swift: """
        enum E<T, U>: Hashable {
            case a(T, U)
            case b(U, String)
            case c
        }
        """, kotlin: """
        internal sealed class E<out T, out U> where T: Any, U: Any {
            class acase<T, U>(val associated0: T, val associated1: U): E<T, U>() where T: Any, U: Any {

                override fun equals(other: Any?): Boolean {
                    if (other !is acase<*, *>) return false
                    return associated0 == other.associated0 && associated1 == other.associated1
                }
                override fun hashCode(): Int {
                    var result = 1
                    result = Hasher.combine(result, associated0)
                    result = Hasher.combine(result, associated1)
                    return result
                }
            }
            class bcase<U>(val associated0: U, val associated1: String): E<Nothing, U>() where U: Any {

                override fun equals(other: Any?): Boolean {
                    if (other !is bcase<*>) return false
                    return associated0 == other.associated0 && associated1 == other.associated1
                }
                override fun hashCode(): Int {
                    var result = 1
                    result = Hasher.combine(result, associated0)
                    result = Hasher.combine(result, associated1)
                    return result
                }
            }
            class ccase: E<Nothing, Nothing>() {
            }

            companion object {
                fun <T, U> a(associated0: T, associated1: U): E<T, U> where T: Any, U: Any {
                    return acase(associated0, associated1)
                }
                fun <U> b(associated0: U, associated1: String): E<Nothing, U> where U: Any {
                    return bcase(associated0, associated1)
                }
                val c: E<Nothing, Nothing> = ccase()
            }
        }
        """)
    }

    func testEnumComparable() async throws {
        try await check(swift: """
        enum E: Comparable {
            case one
            case two
        }
        """, kotlin: """
        internal enum class E: Comparable<E> {
            one,
            two;
        }
        """)

        try await check(swift: """
        enum E: Comparable {
            case one
            case two

            static func < (lhs: E, rhs: E) -> Bool {
                return lhs == .one && rhs == .two
            }
        }
        """, kotlin: """
        internal sealed class E: Comparable<E> {
            class onecase: E() {
            }
            class twocase: E() {
            }

            override fun compareTo(other: E): Int {
                if (this == other) return 0
                fun islessthan(lhs: E, rhs: E): Boolean {
                    return lhs == E.one && rhs == E.two
                }
                return if (islessthan(this, other)) -1 else 1
            }

            companion object {
                val one: E = onecase()
                val two: E = twocase()
            }
        }
        """)

        try await check(swift: """
        enum E {
            case one
            case two(String)
        }

        extension E: Comparable {
            static func < (lhs: E, rhs: E) -> Bool {
                if lhs == .one && rhs != .one {
                    return true
                }
                if case .two(let ls) = lhs, case .two(let rs) = rhs {
                    return ls < rs
                }
                return false
            }
        }
        """, kotlin: """
        internal sealed class E: Comparable<E> {
            class onecase: E() {
            }
            class twocase(val associated0: String): E() {

                override fun equals(other: Any?): Boolean {
                    if (other !is twocase) return false
                    return associated0 == other.associated0
                }
            }
            override fun compareTo(other: E): Int {
                if (this == other) return 0
                fun islessthan(lhs: E, rhs: E): Boolean {
                    if (lhs == E.one && rhs != E.one) {
                        return true
                    }
                    if (lhs is E.twocase) {
                        val ls = lhs.associated0
                        if (rhs is E.twocase) {
                            val rs = rhs.associated0
                            return ls < rs
                        }
                    }
                    return false
                }
                return if (islessthan(this, other)) -1 else 1
            }

            companion object {
                val one: E = onecase()
                fun two(associated0: String): E {
                    return twocase(associated0)
                }
            }
        }
        """)

        try await checkProducesMessage(swift: """
        enum E: Comparable {
            case one
            case two(String)
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
