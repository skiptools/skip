@testable import SkipSyntax
import XCTest

fileprivate extension String {
    /// Parity with Kotlin's `String.length`
    var length: Int { count }
}

/// A test case that verifies that transpilation are *not* working as hoped.
final class FeatureSupportTests: XCTestCase {
    func testWhileLetWithDictionaryEntries() async throws {
        // these won't compile because they rely on SkipLib
        // but they highlight the issue: the dictionary entries enumeration won't compile because it is checking for null for each of the individual tuple entries rather than the whole tuple itself

        // Array iteration works
        try await check(expectMessages: true, compiler: nil, swiftCode: {
            let array: [Int] = [1, 2, 3]
            var iterator = array.makeIterator()
            while let next = iterator.next() {
                print(next)
            }
            return ""
        }, kotlin: """
            val array: Array<Int> = arrayOf(1, 2, 3)
                get() = field
            var iterator = array.makeIterator()
                get() = field.sref({ iterator = it })
                set(newValue) {
                    field = newValue
                }
            while (true) {
                val next_0 = iterator.next()
                if (next_0 == null) {
                    break
                }
                print(next_0)
            }
            return ""
            """)


        // Dictionary while iteration doesn't compile: we shouldn't check for (key_0 == null || value_0 == null), but instead check for whether the entries tuple itself is null
        try await check(expectMessages: true, compiler: nil, swiftCode: {
            let dict: Dictionary<String, Int> = ["x":1,"y":2,"z":3]
            var iterator = dict.makeIterator()
            while let (key, value) = iterator.next() {
                print("\(key)=\(value)")
            }
            return ""
        }, kotlin: """
            val dict: Dictionary<String, Int> = dictionaryOf(Tuple2("x", 1), Tuple2("y", 2), Tuple2("z", 3))
                get() = field
            var iterator = dict.makeIterator()
                get() = field.sref({ iterator = it })
                set(newValue) {
                    field = newValue
                }
            while (true) {
                val (key_0, value_0) = iterator.next()
                if (key_0 == null || value_0 == null) {
                    break
                }
                print("${key_0}=${value_0}")
            }
            return ""
            """)
    }

    func testReifiedTypes() async throws {
        // Could we turn every function that takes a generic into an inline function with reified type parameters? This would let us check for instances of generic types in a way that is impossible with Java's erased generics. E.g., checking `if let strings = object as? Array<String> { … }` is fairly common and doesn't have any good equivlaent in pure Java.

        // So this function doesn't compile:
        // fun <T> nameOf(value: T): String { return "${T::class.java}" }
        // without `reified`: cannot use 'T' as reified type parameter. Use a class instead.
        // without `inline`: only type parameters of inline functions can be reified
        //
        // but with reified types it could look like:
        // inline fun <reified T> nameOf(value: T): String { return "${T::class.java}" }

        // DoubleString
        try await check(expectFailure: true, swiftCode: {
            // SKIP REPLACE: inline fun <reified T> nameOf(value: T): String { return "${T::class.java}" }
            func nameOf<T>(_ value: T) -> String { "\(T.self)" }
            return nameOf(1.0) + nameOf("ABC")
        }, kotlin: """
            inline fun <reified T> nameOf(value: T): String { return "${T::class.java}" }
            return (nameOf(1.0) + nameOf("ABC")).replace("class java.lang.", "")
            """)
    }

    func testCaseStatementsIgnoreIfSkip() async throws {
        // It is very useful to be able to handle individual case statements separately in a Skip, but we don't seem to support #if SKIP statements around case statements:
        // error: Skip does not support this Swift syntax [missingExpr]
        throw XCTSkip("transpiler warnings")

        try await check(swiftCode: {
            let x = { 1 }()
            switch x {
            case 0: return "zero"
            #if SKIP
            case 1: return "one"
            #endif
            default: return "other"
            }
        }, kotlin: """
            var x = 0
            x += 1
            when (x) {
                0 -> {
                    return "zero"
                    
                }
                else -> return "other"
            }
            """)
    }

    func testCheckSwiftCompiledSource() async throws {
        try await check(swiftCode: {
            return "\(1 + 2)"
        }, kotlin: """
            return "${1 + 2}"
            """)
    }

    func testNamedParameterOverridesOuterDefinition() async throws {
        // the "a" part of the "a b: String" parameter is unused in Swift, but it acts as being locally declared in Kotlin and thus overrides the outer definition of "a".
        // These two functions thus return different values: "xy" vs. "yy"
        // There might not be an easy solution to this (and will cause confusing errors when the outer "a" and inner "a" are different types), so we may just need Skippy to disallow such name clashes.
        try await check(compiler: nil, swiftCode: {
            let a = "x"
            func f(a b: String) -> String {
                a + b
            }
            return f(a: "y")
        }, kotlin: """
            val a = "x"
            fun f(a: String): String {
                val b = a
                return a + b
            }
            return f(a = "y")
            """)
    }

    func testUnicodeCombiningCharacters() async throws {
        // "cafe" appending "COMBINING ACUTE ACCENT, U+0301" should still have `.count` of 4.
        // This will be tricky to get right, since Swift's count is built-in, but to get equivalent
        // behavior we'd need to use java.text.BreakIterator or java.text.StringCharacterIterator
        // to get the correct character count. We could, perhaps, have a `count`
        // implementation that does an initial check for combining characters, and if any are
        // detected, use the slow-track method for getting the count.
        try await check(expectFailure: true, compiler: nil, swiftCode: {
            var word = "cafe"
            word += "\u{301}"
            return "\(word.count)"
        }, kotlin: """
            var word = "cafe"
            word += "\\u0301"
            return "${word.count}"
            """)
    }

    /// Trying to reproduce `UUID(uuidString: "Invalid UUID")` in `TestUUID.swift` throwing a `NullReturnException`.
    /// But this works fine…
    func testInferredNilConstructor() async throws {
        try await check(swift: """
        class Foo {
            init?() {
                return nil
            }
        }

        let foo = Foo()
        assert(foo == nil)
        """, kotlin: """
        internal open class Foo {
            internal constructor() {
                throw NullReturnException()
            }
        }

        internal val foo = (try { Foo() } catch (_: NullReturnException) { null })
        assert(foo == null)
        """)
    }

    func testEnumRawValueKeywords() async throws {
        // The case match label is wrong for KeywordsEnum.null
        try await check(compiler: nil, swiftCode: {
            enum KeywordsEnum : Int {
                case null
                case string
                case boolean
                case object
                case `case`

                var index: Int {
                    switch self {
                    case .null:
                        return 0
                    case .string:
                        return 1
                    case .boolean:
                        return 2
                    case .object:
                        return 3
                    case .case:
                        return 4
                    }
                }
            }
            return ""
        }, kotlin: """
            enum class KeywordsEnum(override val rawValue: Int, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): RawRepresentable<Int> {
                null_(0),
                string(1),
                boolean(2),
                object_(3),
                case(4);
                val index: Int
                    get() {
                        when (this) {
                            KeywordsEnum.null_ -> return 0
                            KeywordsEnum.string -> return 1
                            KeywordsEnum.boolean -> return 2
                            KeywordsEnum.object_ -> return 3
                            KeywordsEnum.case -> return 4
                        }
                    }
            }
            
            fun KeywordsEnum(rawValue: Int): KeywordsEnum? {
                return when (rawValue) {
                    0 -> KeywordsEnum.null
                    1 -> KeywordsEnum.string
                    2 -> KeywordsEnum.boolean
                    3 -> KeywordsEnum.object
                    4 -> KeywordsEnum.`case`
                    else -> null
                }
            }
            return ""
            """)
    }


    func testEnumKeywords() async throws {
        // Postfix-underscored (e.g. "Object_") keyword name-derived case classes are do not use the escaped version when checking cases
        try await check(swiftCode: {
            enum KeywordsEnum {
                case null
                case string(String)
                case boolean(Bool)
                case object(Any)
                case `case`

                var index: Int {
                    switch self {
                    case .null:
                        return 0
                    case .string(_):
                        return 1
                    case .boolean(_):
                        return 2
                    case .object(_):
                        return 3
                    case .case:
                        return 4
                    }
                }
            }
            return ""
        }, kotlin: """
            sealed class KeywordsEnum {
                class NullCase: KeywordsEnum() {
                }
                class StringCase(val associated0: String): KeywordsEnum() {
                }
                class BooleanCase(val associated0: Boolean): KeywordsEnum() {
                }
                class ObjectCase(val associated0: Any): KeywordsEnum() {
                }
                class CaseCase: KeywordsEnum() {
                }
                val index: Int
                    get() {
                        when (this) {
                            is KeywordsEnum.NullCase -> return 0
                            is KeywordsEnum.StringCase -> return 1
                            is KeywordsEnum.BooleanCase -> return 2
                            is KeywordsEnum.ObjectCase -> return 3
                            is KeywordsEnum.CaseCase -> return 4
                        }
                    }
            
                companion object {
                    val null_: KeywordsEnum = NullCase()
                    fun string(associated0: String): KeywordsEnum = StringCase(associated0)
                    fun boolean(associated0: Boolean): KeywordsEnum = BooleanCase(associated0)
                    fun object_(associated0: Any): KeywordsEnum = ObjectCase(associated0)
                    val case: KeywordsEnum = CaseCase()
                }
            }
            return ""
            """)
    }

    func testInitNumberLiterals() async throws {
        // Kotlin doesn't seem to allow initializing non-Ints with literals without being explicit

        // see the very end of SkipFoundation/…/TestNSNumberBridging.swift for examples of number literals initializers we might want to support

        // error: the integer literal does not conform to the expected type Double
        try await check(expectFailure: true, compiler: nil, swiftCode: {
            var x: Int8
            var y: UInt32
            var z: Double

            x = 1
            y = 2
            z = 3
            _ = x
            _ = y
            _ = z
            return ""
        }, kotlin: """
            var x: Byte
            var y: UInt
            var z: Double
            x = 1
            y = 2
            z = 3
            x
            y
            z
            return ""
            """)
    }

    func testArrayOfDoubles() async throws {
        // error: type mismatch: inferred type is IntegerLiteralType[Int,Long,Byte,Short] but Double was expected
        try await check(compiler: nil, swiftCode: {
            let doubles: Array<Double> = [1,2,3,4]
            return "\(doubles)"
        }, kotlin: """
            val doubles: Array<Double> = arrayOf(1, 2, 3, 4)
                get() = field
            return "${doubles}"
            """)
    }

    func testNestedSimpleEnumInFunction() async throws {
        // error: Skip does not support type declarations within functions. Consider making this an independent type
        // error: modifier 'enum' is not applicable to 'local class'
        try await check(expectFailure: true, swift: """
        class Foo {
            public func someFunction() {
                enum NestedEnum {
                    case case1, case2, case3
                }
            }
        }
        """, kotlin: """
        """)
    }

    /// 1.406 seconds
    func testInferPerf15() async throws {
        try await check(swiftCode: {
            func f(_ number: Int) -> String { "\(number)" }
            func f(_ string: String) -> Int { string.length }
            let x = f(f(f(f(f(f(f(f(f(f(f(f(f(f(f(88888888)))))))))))))))
            return x
        }, kotlin: """
            fun f(number: Int): String = "${number}"
            fun f(string: String): Int = string.length
            val x = f(f(f(f(f(f(f(f(f(f(f(f(f(f(f(88888888)))))))))))))))
            return x
            """)
    }

    func testCheckSwiftEnum() async throws {
        try await check(swiftCode: {
            enum EnumType {
                case a,
                     b,
                     c
            }
            return nil
        }, kotlin: """
            enum class EnumType {
                a,
                b,
                c;
            }
            return null
            """)
    }

    func testCheckSwiftFib() async throws {
        try await fibCheck(n: 2, expectFailure: false)
        try await fibCheck(n: 40, expectFailure: false)

        // 32-bit int overflow behavior
        // XCTAssertEqual failed: ("12586269025") is not equal to ("-298632863")
        //try await fibCheck(n: 50, expectFailure: true) // needs KOTLINC env variable set
    }

    func fibCheck(n fibIndex: Int, expectFailure: Bool) async throws {
        try await check(expectFailure: expectFailure, swiftCode: {
            func fibonacci(_ n: Int) -> Int {
                if n <= 1 {
                    return n
                }
                var a = 0, b = 1
                for _ in 2...n {
                    let c = a + b
                    a = b
                    b = c
                }
                return b
            }
            return "\(fibonacci(fibIndex))"
        }, kotlin: """
            fun fibonacci(n: Int): Int {
                if (n <= 1) {
                    return n
                }
                var a = 0
                var b = 1
                for (unusedbinding in 2..n) {
                    val c = a + b
                    a = b
                    b = c
                }
                return b
            }
            return "${fibonacci(\(fibIndex))}"
            """,
        fixup: { $0.replacingOccurrences(of: "fibIndex", with: "\(fibIndex)") }) // needed for source code comparison
    }


    func testCheckUnicodeString() async throws {
        // interestingly, the special case check fails on Linux
        #if !os(Linux)
        try await check(expectFailure: true, swiftCode: {
            let currencySpacing = "\u{00A0}"
            return "\(currencySpacing)"
        }, kotlin: """
            val currencySpacing = " "
            return "${currencySpacing}"
            """)
        #endif
    }
}
