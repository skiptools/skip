@testable import SkipSyntax
import XCTest

fileprivate extension String {
    /// Parity with Kotlin's `String.length`
    var length: Int { count }
}

/// A test case that verifies that transpilation are *not* working as hoped.
final class FeatureSupportTests: XCTestCase {
    func testOptionalDelegatingInit() async throws {
        // decimalWithoutDelegatingInit works, but
        // decimalWithDelegatingInit is broken
        try await check(compiler: nil, swiftCode: {
            struct WholeNumber {
                let number: Int
                init(number: Int) {
                    self.number = number
                }

                init?(decimalWithoutDelegatingInit decimal: Double) {
                    guard decimal == Double(Int(decimal)) else {
                        return nil
                    }
                    self.number = Int(decimal)
                }

                init?(decimalWithDelegatingInit decimal: Double) {
                    guard decimal == Double(Int(decimal)) else {
                        return nil
                    }
                    self.init(number: Int(decimal))
                }
            }
            return ""
        }, kotlin: """
        class WholeNumber {
            val number: Int
            constructor(number: Int) {
                this.number = number
            }
            constructor(decimalWithoutDelegatingInit: Double) {
                val decimal = decimalWithoutDelegatingInit
                if (decimal != Double(Int(decimal))) {
                    throw NullReturnException()
                }
                this.number = Int(decimal)
            }
            constructor(decimalWithDelegatingInit: Double, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null): this(number = Int(decimal)) {
                val decimal = decimalWithDelegatingInit
                if (decimal != Double(Int(decimal))) {
                    throw NullReturnException()
                }
            }
        }
        return ""
        """)
    }

    func testWhileOptionalBinding() async throws {
        // currently bindings in if loops are disallowed:
        // error: Kotlin does not support optional bindings in loop conditions. Consider using an if statement before or within your loop

        // we might be able to support it by transpiling:
        // `while let actual = optional { … }`
        // as:
        // `while true { if let actual = optional { … } else { break } }`
        try await check(expectFailure: true, swiftCode: {
            func positive(number: Int) -> Int? {
                number > 0 ? number : nil
            }

            var index = 10
            var sum = 0

            while let number = positive(number: index) {
                sum += number
                index -= 1
            }
            return "\(sum)"
        }, kotlin: """
            fun positive(number: Int): Int? = if (number > 0) number else null
            var index = 10
            var sum = 0
            while (true) {
                var letexec_0 = false
                positive(number = index)?.let { number ->
                    letexec_0 = true
                    sum += number
                    index -= 1
                }
                if (!letexec_0) {
                    break
                }
            }
            return "${sum}"
            """)
    }

    func testGuaranteedLetAssignment() async throws {
        // Kotlin doesn't seem to be able to handle a guaranteed let assignment
        // Source.kts:3:5: error: captured member values initialization is forbidden due to possible reassignment

        // perhaps we could transpile `let str: String` as `var str: String!` to work around this, or else just end with a `fatalError("unreachable")`

        // the `if ({ true }())` construct is merely to avoid Swift compiler warnings about the else statement never being excuted

        try await check(compiler: nil, swiftCode: {
            let str: String
            if ({ true }()) {
                str = "x"
            } else {
                str = "y"
            }

            return str
        }, kotlin: """
            val str: String
            if (({ true }())) {
                str = "x"
            } else {
                str = "y"
            }
            return str
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

    /// Trying to reproduce `UUID(uuidString: "Invalid UUID")` in `TestUUID.swift` throwing a `NullReturnException`.
    /// But this works fine…
    func testInferredNilConstructor() async throws {
        try await check(compiler: nil, swiftCode: {
            class Foo {
                init?() {
                    return nil
                }
            }

            let foo = Foo()
            assert(foo == nil)
            return ""
        }, kotlin: """
            open class Foo {
                constructor() {
                    throw NullReturnException()
                }
            }
            val foo = (try { Foo() } catch (_: NullReturnException) { null })
            assert(foo == null)
            return ""
            """)
    }

    func testNoComments() async throws {
        try await check(swiftCode: {
            let x = "1" + "X"
            return x /* TRAILING */
        }, kotlin: """
            val x = "1" + "X"
            return x /* TRAILING */
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
        try await check(compiler: nil, swiftCode: {
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

    func testUnsignedEnumConstants() async throws {
        // compile error: conversion of signed constants to unsigned ones is prohibited ten(10), twenty(20)
        try await check(compiler: nil, swiftCode: {
            enum UnsignedEnum : UInt32, Equatable {
                case ten = 10
                case twenty = 20
            }
            return ""
        }, kotlin: """
            enum class UnsignedEnum(override val rawValue: UInt, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): RawRepresentable<UInt> {
                ten(10),
                twenty(20);
            }

            fun UnsignedEnum(rawValue: UInt): UnsignedEnum? {
                return when (rawValue) {
                    10 -> UnsignedEnum.ten
                    20 -> UnsignedEnum.twenty
                    else -> null
                }
            }
            return ""
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



















































