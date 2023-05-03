@testable import SkipSyntax
import XCTest

fileprivate extension String {
    /// Parity with Kotlin's `String.length`
    var length: Int { count }
}

/// A test case that verifies that transpilation are *not* working as hoped.
final class FeatureSupportTests: XCTestCase {

    func testCheckSwiftCompiledSource() async throws {
        try await check(swiftCode: {
            return "\(1 + 2)"
        }, kotlin: """
            return "${1 + 2}"
            """)
    }

    func testEnumKeyworkNames() async throws {
        // Postfix-underscored (e.g. "Object_") keyword name-derived case classes are do not use the escaped version when checking cases

        // compile error: unresolved reference: NullCase if (this is KeywordsEnum.NullCase)
        // compile error: unresolved reference: ObjectCase if (this is KeywordsEnum.ObjectCase)
        try await check(compiler: nil, swiftCode: {
            enum KeywordsEnum {
                case null
                case string(String)
                case boolean(Bool)
                case object(Any)
                case `case`

                var isNull: Bool {
                    if case .null = self {
                        return true
                    } else {
                        return false
                    }
                }

                func objectValue() -> Any? {
                    if case .object(let any) = self {
                        return any
                    } else {
                        return nil
                    }
                }

                func stringValue() -> String? {
                    if case .string(let str) = self {
                        return str
                    } else {
                        return nil
                    }
                }

                func booleanValue() -> Bool? {
                    if case .boolean(let b) = self {
                        return b
                    } else {
                        return nil
                    }
                }
            }
            return ""
        }, kotlin: """
            sealed class KeywordsEnum {
                class Null_Case: KeywordsEnum() {
                }
                class StringCase(val associated0: String): KeywordsEnum() {
                }
                class BooleanCase(val associated0: Boolean): KeywordsEnum() {
                }
                class Object_Case(val associated0: Any): KeywordsEnum() {
                }
                class CaseCase: KeywordsEnum() {
                }
                val isNull: Boolean
                    get() {
                        if (this is KeywordsEnum.NullCase) {
                            return true
                        } else {
                            return false
                        }
                    }
                fun objectValue(): Any? {
                    if (this is KeywordsEnum.ObjectCase) {
                        val any = this.associated0
                        return any
                    } else {
                        return null
                    }
                }
                fun stringValue(): String? {
                    if (this is KeywordsEnum.StringCase) {
                        val str = this.associated0
                        return str
                    } else {
                        return null
                    }
                }
                fun booleanValue(): Boolean? {
                    if (this is KeywordsEnum.BooleanCase) {
                        val b = this.associated0
                        return b
                    } else {
                        return null
                    }
                }
            
                companion object {
                    val null_: KeywordsEnum = Null_Case()
                    fun string(associated0: String): KeywordsEnum {
                        return StringCase(associated0)
                    }
                    fun boolean(associated0: Boolean): KeywordsEnum {
                        return BooleanCase(associated0)
                    }
                    fun object_(associated0: Any): KeywordsEnum {
                        return Object_Case(associated0)
                    }
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
                get() {
                    return field
                }
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
            enum class UnsignedEnum(override val rawValue: UInt, unusedp: Nothing? = null): RawRepresentable<UInt> {
                ten(10),
                twenty(20);
            }

            fun UnsignedEnum(rawValue: UInt): UnsignedEnum? {
                return when (rawValue) {
                    10 -> {
                        UnsignedEnum.ten
                    }
                    20 -> {
                        UnsignedEnum.twenty
                    }
                    else -> {
                        null
                    }
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
                for (unusedbinding in 2 .. n) {
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

















