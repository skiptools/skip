import XCTest

final class EnumTests: XCTestCase {
    func testEmptyEnum() async throws {
        try await check(swift: """
        enum E {
            static let x = 1
        }
        """, kotlin: """
        internal enum class E {
            ;

            companion object {
                internal val x = 1
            }
        }
        """)
    }

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
        internal enum class E(override val rawValue: Int, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): RawRepresentable<Int> {
            a(0),
            b(1),
            c(100),
            d(101);
        }

        internal fun E(rawValue: Int): E? {
            return when (rawValue) {
                0 -> E.a
                1 -> E.b
                100 -> E.c
                101 -> E.d
                else -> null
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
        internal enum class E(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): RawRepresentable<String> {
            a("a"),
            b("B"),
            c("c");
        }

        internal fun E(rawValue: String): E? {
            return when (rawValue) {
                "a" -> E.a
                "B" -> E.b
                "c" -> E.c
                else -> null
            }
        }
        """)
    }

    func testExtendsCastRequiredTypes() async throws {
        try await check(swift: """
        enum E : UInt32 {
            case a = 10
            case b = 20
        }
        """, kotlin: """
        internal enum class E(override val rawValue: UInt, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): RawRepresentable<UInt> {
            a(UInt(10)),
            b(UInt(20));
        }

        internal fun E(rawValue: UInt): E? {
            return when (rawValue) {
                UInt(10) -> E.a
                UInt(20) -> E.b
                else -> null
            }
        }
        """)

        try await check(swift: """
        enum E : Float {
            case a = 10
            case b = 20
        }
        """, kotlin: """
        internal enum class E(override val rawValue: Float, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): RawRepresentable<Float> {
            a(Float(10)),
            b(Float(20));
        }

        internal fun E(rawValue: Float): E? {
            return when (rawValue) {
                Float(10) -> E.a
                Float(20) -> E.b
                else -> null
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
        internal enum class E(override val rawValue: Int, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): RawRepresentable<Int> {
            a(0),
            b(1);

            internal fun plusOne(): Int = rawValue + 1
        }

        internal fun E(rawValue: Int): E? {
            return when (rawValue) {
                0 -> E.a
                1 -> E.b
                else -> null
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
        internal enum class E(override val rawValue: Int, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): RawRepresentable<Int> {
            a(0),

            b(1);

            internal fun plusOne(): Int = rawValue + 1
        }

        internal fun E(rawValue: Int): E? {
            return when (rawValue) {
                0 -> E.a
                1 -> E.b
                else -> null
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
            class ACase: E() {
            }
            class BCase(val associated0: Int, val associated1: String): E() {
            }

            companion object {
                val a: E = ACase()
                fun b(associated0: Int = 1, associated1: String): E = BCase(associated0, associated1)
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
            class ACase: E() {
            }
            class BCase(val associated0: Int, val associated1: String): E() {
                val i = associated0
            }

            companion object {
                val a: E = ACase()
                fun b(i: Int = 1, associated1: String): E = BCase(i, associated1)
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
        internal sealed class E<out T> {
            class ACase: E<Nothing>() {
            }
            class BCase<T>(val associated0: Int, val associated1: T): E<T>() {
            }

            companion object {
                val a: E<Nothing> = ACase()
                fun <T> b(associated0: Int = 1, associated1: T): E<T> = BCase(associated0, associated1)
            }
        }
        """)

        try await check(swift: """
        enum E<T, U: Equatable> {
            case a(T)
            case b(U)
        }
        """, kotlin: """
        internal sealed class E<out T, out U> {
            class ACase<T>(val associated0: T): E<T, Nothing>() {
            }
            class BCase<U>(val associated0: U): E<Nothing, U>() {
            }

            companion object {
                fun <T> a(associated0: T): E<T, Nothing> = ACase(associated0)
                fun <U> b(associated0: U): E<Nothing, U> = BCase(associated0)
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
        internal sealed class E<out T, out U> {
            class ACase<T, U>(val associated0: T, val associated1: U): E<T, U>() {
                override fun equals(other: Any?): Boolean {
                    if (other !is ACase<*, *>) return false
                    return associated0 == other.associated0 && associated1 == other.associated1
                }
                override fun hashCode(): Int {
                    var result = 1
                    result = Hasher.combine(result, associated0)
                    result = Hasher.combine(result, associated1)
                    return result
                }
            }
            class BCase<U>(val associated0: U, val associated1: String): E<Nothing, U>() {
                override fun equals(other: Any?): Boolean {
                    if (other !is BCase<*>) return false
                    return associated0 == other.associated0 && associated1 == other.associated1
                }
                override fun hashCode(): Int {
                    var result = 1
                    result = Hasher.combine(result, associated0)
                    result = Hasher.combine(result, associated1)
                    return result
                }
            }
            class CCase: E<Nothing, Nothing>() {
            }

            companion object {
                fun <T, U> a(associated0: T, associated1: U): E<T, U> = ACase(associated0, associated1)
                fun <U> b(associated0: U, associated1: String): E<Nothing, U> = BCase(associated0, associated1)
                val c: E<Nothing, Nothing> = CCase()
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
        func f(e: E) {
            switch e {
            case .one:
                print("one")
            case .two:
                print("two")
            }
        }
        """, kotlin: """
        internal enum class E: Comparable<E> {
            one,
            two;
        }
        internal fun f(e: E) {
            when (e) {
                E.one -> print("one")
                E.two -> print("two")
            }
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
        func f(e: E) {
            switch e {
            case .one:
                print("one")
            case .two:
                print("two")
            }
        }
        """, kotlin: """
        internal sealed class E: Comparable<E> {
            class OneCase: E() {
            }
            class TwoCase: E() {
            }

            override fun compareTo(other: E): Int {
                if (this == other) return 0
                fun islessthan(lhs: E, rhs: E): Boolean {
                    return lhs == E.one && rhs == E.two
                }
                return if (islessthan(this, other)) -1 else 1
            }

            companion object {
                val one: E = OneCase()
                val two: E = TwoCase()
            }
        }
        internal fun f(e: E) {
            when (e) {
                is E.OneCase -> print("one")
                is E.TwoCase -> print("two")
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
            class OneCase: E() {
            }
            class TwoCase(val associated0: String): E() {
                override fun equals(other: Any?): Boolean {
                    if (other !is TwoCase) return false
                    return associated0 == other.associated0
                }
            }

            override fun compareTo(other: E): Int {
                if (this == other) return 0
                fun islessthan(lhs: E, rhs: E): Boolean {
                    if (lhs == E.one && rhs != E.one) {
                        return true
                    }
                    if (lhs is E.TwoCase) {
                        val ls = lhs.associated0
                        if (rhs is E.TwoCase) {
                            val rs = rhs.associated0
                            return ls < rs
                        }
                    }
                    return false
                }
                return if (islessthan(this, other)) -1 else 1
            }

            companion object {
                val one: E = OneCase()
                fun two(associated0: String): E = TwoCase(associated0)
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
        enum E: RawRepresentable {
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

        func f(param: Int) -> E {
            return E(rawValue: param) ?? .one
        }
        func g(param: Int) -> E {
            return E(rawValue: param)!
        }
        """, kotlin: """
        internal enum class E: RawRepresentable<Int> {
            one,
            two;
        }

        internal fun E(rawValue: Int): E? {
            when (rawValue) {
                1 -> return E.one
                2 -> return E.two
                else -> return null
            }
        }

        internal fun f(param: Int): E = E(rawValue = param) ?: E.one
        internal fun g(param: Int): E = E(rawValue = param)!!
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
            class OneCase: E() {
            }
            class OtherCase(val associated0: Int): E() {
            }

            companion object {
                val one: E = OneCase()
                fun other(associated0: Int): E = OtherCase(associated0)
            }
        }

        internal fun E(value: Int): E = if (value == 1) E.one else E.other(value)
        """)
    }

    func testCaseIterable() async throws {
        // Tests don't have access to SkipLib protocols
        let supportingSwift = """
        protocol CaseIterable {
            static var allCases: [Self] { get }
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        enum E: CaseIterable {
            case one
            case two
            case three
        }
        """, kotlin: """
        import skip.lib.Array

        internal enum class E: CaseIterable {
            one,
            two,
            three;

            companion object: CaseIterableCompanion<E> {
                override val allCases: Array<E>
                    get() = arrayOf(one, two, three)
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
        import skip.lib.Array

        internal enum class E: CaseIterable {
            one,
            two,
            three;

            companion object: CaseIterableCompanion<E> {

                override val allCases: Array<E>
                    get() = arrayOf(E.one, E.two, E.three)
            }
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        enum E: CaseIterable, Error {
            case one
            case two
        }
        """, kotlin: """
        import skip.lib.Array

        internal sealed class E: Exception(), CaseIterable, Error {
            class OneCase: E() {
                override fun equals(other: Any?): Boolean = other is OneCase
                override fun hashCode(): Int = "OneCase".hashCode()
            }
            class TwoCase: E() {
                override fun equals(other: Any?): Boolean = other is TwoCase
                override fun hashCode(): Int = "TwoCase".hashCode()
            }

            companion object: CaseIterableCompanion<E> {
                val one: E
                    get() = OneCase()
                val two: E
                    get() = TwoCase()

                override val allCases: Array<E>
                    get() = arrayOf(one, two)
            }
        }
        """)
    }

    func testCaseIterableTypeInference() async throws {
        // Make CaseIterable part of supportSwift because we don't have access to SkipLib in tests
        try await check(supportingSwift: """
        protocol CaseIterable {
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

    func testSynthesizedRawValueType() async throws {
        try await check(supportingSwift: """
        extension String {
            static let empty = ""
        }
        enum E: String {
            case x
        }
        """, swift: """
        let b = E.x.rawValue == .empty
        """, kotlin: """
        internal val b = E.x.rawValue == String.empty
        """)
    }

    func testDisallowedCaseNames() async throws {
        try await check(swift: """
        enum E: String, CaseIterable {
            case name
        }

        func f(e: E) {
            switch e {
            case .name:
                print("name")
            }
            if case .name = e {
                print("name")
            }
            f(e: .name)
        }
        """, kotlin: """
        internal enum class E(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CaseIterable, RawRepresentable<String> {
            name_("name");
        }

        internal fun E(rawValue: String): E? {
            return when (rawValue) {
                "name" -> E.name_
                else -> null
            }
        }

        internal fun f(e: E) {
            when (e) {
                E.name_ -> print("name")
            }
            if (e == E.name_) {
                print("name")
            }
            f(e = E.name_)
        }
        """)

        try await check(swift: """
        enum E {
            case name(String)
        }

        func f(e: E) {
            switch e {
            case .name(let name):
                print(name)
            }
            if case .name(let name) = e {
                print(name)
            }
            f(e: .name("x"))
        }
        """, kotlin: """
        internal sealed class E {
            class NameCase(val associated0: String): E() {
            }

            companion object {
                fun name(associated0: String): E = NameCase(associated0)
            }
        }

        internal fun f(e: E) {
            when (e) {
                is E.NameCase -> {
                    val name = e.associated0
                    print(name)
                }
            }
            if (e is E.NameCase) {
                val name = e.associated0
                print(name)
            }
            f(e = E.name("x"))
        }
        """)
    }

    func testDisallowedPropertyNames() async throws {
        try await checkProducesMessage(swift: """
        enum E {
            case a, b
        
            var name: String {
                "name"
            }
        }
        """)

        try await check(swift: """
        enum E {
            case a(Int), b
        
            var name: String {
                "name"
            }
        }
        """, kotlin: """
        internal sealed class E {
            class ACase(val associated0: Int): E() {
            }
            class BCase: E() {
            }

            internal val name: String
                get() = "name"

            companion object {
                fun a(associated0: Int): E = ACase(associated0)
                val b: E = BCase()
            }
        }
        """)
    }
}
