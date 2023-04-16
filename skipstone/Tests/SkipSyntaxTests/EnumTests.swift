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
        internal enum class E(val rawValue: Int, unusedp: Nothing? = null): RawRepresentable {
            a(0),
            b(1),
            c(100),
            d(101);
        }

        internal fun E(rawValue: Int): E? {
            return when (rawValue) {
                0 -> {
                    E.a
                }
                1 -> {
                    E.b
                }
                100 -> {
                    E.c
                }
                101 -> {
                    E.d
                }
                else -> {
                    null
                }
            }
        }
        """)

        try await check(swift: """
        enum E: String {
            case a
            case b = "B"
            case c
        }
        """, kotlin: """
        internal enum class E(val rawValue: String, unusedp: Nothing? = null): RawRepresentable {
            a("a"),
            b("B"),
            c("c");
        }

        internal fun E(rawValue: String): E? {
            return when (rawValue) {
                "a" -> {
                    E.a
                }
                "B" -> {
                    E.b
                }
                "c" -> {
                    E.c
                }
                else -> {
                    null
                }
            }
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
        internal enum class E(val rawValue: Int, unusedp: Nothing? = null): RawRepresentable {
            a(0),
            b(1);

            internal fun plusOne(): Int {
                return rawValue + 1
            }
        }

        internal fun E(rawValue: Int): E? {
            return when (rawValue) {
                0 -> {
                    E.a
                }
                1 -> {
                    E.b
                }
                else -> {
                    null
                }
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
        internal enum class E(val rawValue: Int, unusedp: Nothing? = null): RawRepresentable {
            a(0),

            b(1);

            internal fun plusOne(): Int {
                return rawValue + 1
            }
        }

        internal fun E(rawValue: Int): E? {
            return when (rawValue) {
                0 -> {
                    E.a
                }
                1 -> {
                    E.b
                }
                else -> {
                    null
                }
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
            class A: E() {
            }
            class B(val associated0: Int, val associated1: String): E() {
            }

            companion object {
                val a: E = A()
                fun b(associated0: Int = 1, associated1: String): E {
                    return B(associated0, associated1)
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
            class A: E() {
            }
            class B(val associated0: Int, val associated1: String): E() {
                val i = associated0
            }

            companion object {
                val a: E = A()
                fun b(i: Int = 1, associated1: String): E {
                    return B(i, associated1)
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
            class A: E<Nothing>() {
            }
            class B<T>(val associated0: Int, val associated1: T): E<T>() where T: Any {
            }

            companion object {
                val a: E<Nothing> = A()
                fun <T> b(associated0: Int = 1, associated1: T): E<T> where T: Any {
                    return B(associated0, associated1)
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
            class A<T>(val associated0: T): E<T, Nothing>() where T: Any {
            }
            class B<U>(val associated0: U): E<Nothing, U>() where U: Any {
            }

            companion object {
                fun <T> a(associated0: T): E<T, Nothing> where T: Any {
                    return A(associated0)
                }
                fun <U> b(associated0: U): E<Nothing, U> where U: Any {
                    return B(associated0)
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
            class A<T, U>(val associated0: T, val associated1: U): E<T, U>() where T: Any, U: Any {

                override fun equals(other: Any?): Boolean {
                    if (other !is A<*, *>) return false
                    return associated0 == other.associated0 && associated1 == other.associated1
                }
                override fun hashCode(): Int {
                    var result = 1
                    result = Hasher.combine(result, associated0)
                    result = Hasher.combine(result, associated1)
                    return result
                }
            }
            class B<U>(val associated0: U, val associated1: String): E<Nothing, U>() where U: Any {

                override fun equals(other: Any?): Boolean {
                    if (other !is B<*>) return false
                    return associated0 == other.associated0 && associated1 == other.associated1
                }
                override fun hashCode(): Int {
                    var result = 1
                    result = Hasher.combine(result, associated0)
                    result = Hasher.combine(result, associated1)
                    return result
                }
            }
            class C: E<Nothing, Nothing>() {
            }

            companion object {
                fun <T, U> a(associated0: T, associated1: U): E<T, U> where T: Any, U: Any {
                    return A(associated0, associated1)
                }
                fun <U> b(associated0: U, associated1: String): E<Nothing, U> where U: Any {
                    return B(associated0, associated1)
                }
                val c: E<Nothing, Nothing> = C()
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
            class One: E() {
            }
            class Two: E() {
            }

            override fun compareTo(other: E): Int {
                if (this == other) return 0
                fun islessthan(lhs: E, rhs: E): Boolean {
                    return lhs == E.one && rhs == E.two
                }
                return if (islessthan(this, other)) -1 else 1
            }

            companion object {
                val one: E = One()
                val two: E = Two()
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
            class One: E() {
            }
            class Two(val associated0: String): E() {

                override fun equals(other: Any?): Boolean {
                    if (other !is Two) return false
                    return associated0 == other.associated0
                }
            }
            override fun compareTo(other: E): Int {
                if (this == other) return 0
                fun islessthan(lhs: E, rhs: E): Boolean {
                    if (lhs == E.one && rhs != E.one) {
                        return true
                    }
                    if (lhs is E.Two) {
                        val ls = lhs.associated0
                        if (rhs is E.Two) {
                            val rs = rhs.associated0
                            return ls < rs
                        }
                    }
                    return false
                }
                return if (islessthan(this, other)) -1 else 1
            }

            companion object {
                val one: E = One()
                fun two(associated0: String): E {
                    return Two(associated0)
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

    func testCustomConstructor() async throws {
        try await check(swift: """
        enum E: Int, RawRepresentable {
            case one
            case two

            init?(rawValue: Int) {
                switch rawValue {
                case 1:
                    self = .one
                case 2:
                    self = .two
                default:
                    return nil
                }
            }
        }
        """, kotlin: """
        internal enum class E(val rawValue: Int, unusedp: Nothing? = null): RawRepresentable {
            one(0),
            two(1);
        }

        internal fun E(rawValue: Int): E? {
            when (rawValue) {
                1 -> {
                    return E.one
                }
                2 -> {
                    return E.two
                }
                else -> {
                    return null
                }
            }
        }
        """)

        try await check(swift: """
        enum E {
            case one
            case other(Int)

            init(value: Int) {
                self = value == 1 ? .one : .other(value)
            }
        }
        """, kotlin: """
        internal sealed class E {
            class One: E() {
            }
            class Other(val associated0: Int): E() {
            }

            companion object {
                val one: E = One()
                fun other(associated0: Int): E {
                    return Other(associated0)
                }
            }
        }

        internal fun E(value: Int): E {
            return if (value == 1) E.one else E.other(value)
        }
        """)
    }

    func testCaseIterable() async throws {
        // Tests don't have access to SkipLib protocols
        let supportingSwift = "protocol CaseIterable {}"

        try await check(supportingSwift: supportingSwift, swift: """
        enum E: CaseIterable {
            case one
            case two
            case three
        }
        """, kotlin: """
        internal enum class E: CaseIterable {
            one,
            two,
            three;

            companion object {
                val allCases: Array<E>
                    get() {
                        return arrayOf(one, two, three)
                    }
            }
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        enum E {
            case one
            case two
            case three
        }
        extension E: CaseIterable {
            static var allCases: [E] {
                return [.one, .two, .three]
            }
        }
        """, kotlin: """
        internal enum class E: CaseIterable {
            one,
            two,
            three;

            companion object {
                internal val allCases: Array<E>
                    get() {
                        return arrayOf(E.one, E.two, E.three)
                    }
            }
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        enum E: CaseIterable, Error {
            case one
            case two
        }
        """, kotlin: """
        internal sealed class E: Throwable(), CaseIterable, Error {
            class One: E() {

                override fun equals(other: Any?): Boolean {
                    if (other !is One) return false
                    return true
                }
                override fun hashCode(): Int {
                    return "One".hashCode()
                }
            }
            class Two: E() {

                override fun equals(other: Any?): Boolean {
                    if (other !is Two) return false
                    return true
                }
                override fun hashCode(): Int {
                    return "Two".hashCode()
                }
            }

            companion object {
                fun one(): E {
                    return One()
                }
                fun two(): E {
                    return Two()
                }

                val allCases: Array<E>
                    get() {
                        return arrayOf(one(), two())
                    }
            }
        }
        """)
    }

    func testCaseIterableTypeInference() async throws {
        // Make CaseIterable part of supportSwift because we don't have access to SkipLib in tests
        try await check(supportingSwift: """
        protocol CaseIterable {
            // SKIP NOWARN
            static var allCases: [Self] { get }
        }
        enum E: CaseIterable {
            case one
            case two
            case three
        }
        """, swift: """
        func f() {
            for e in E.allCases {
                if e == .two {
                    print("TWO")
                }
            }
        }
        """, kotlin: """
        internal fun f() {
            for (e in E.allCases.sref()) {
                if (e == E.two) {
                    print("TWO")
                }
            }
        }
        """)
    }
}
