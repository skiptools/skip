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

    func testEnumAssociatedCases() async throws {
        // e: :14:43 Return type of 'equals' is not a subtype of the return type of the overridden member 'public open fun equals(other: Any?): kotlin.Boolean defined in skip.foundation.JSON'
        // e: :15:43 The boolean literal does not conform to the expected type JSON.Boolean
        // e: :16:20 Type mismatch: inferred type is kotlin.Boolean but skip.foundation.JSON.Boolean was expected
        // e: :16:32 'equals' must return kotlin.Boolean but returns skip.foundation.JSON.Boolean
        // e: :26:43 Return type of 'equals' is not a subtype of the return type of the overridden member 'public open fun equals(other: Any?): kotlin.Boolean defined in skip.foundation.JSON'
        // e: :27:42 The boolean literal does not conform to the expected type JSON.Boolean
        // e: :28:20 Type mismatch: inferred type is kotlin.Boolean but skip.foundation.JSON.Boolean was expected
        // e: :38:43 Return type of 'equals' is not a subtype of the return type of the overridden member 'public open fun equals(other: Any?): kotlin.Boolean defined in skip.foundation.JSON'
        // e: :39:42 The boolean literal does not conform to the expected type JSON.Boolean
        // e: :40:20 Type mismatch: inferred type is kotlin.Boolean but skip.foundation.JSON.Boolean was expected
        // e: :40:32 'equals' must return kotlin.Boolean but returns skip.foundation.JSON.Boolean
        // e: :48:39 No type arguments expected for class Array
        // e: :50:43 Return type of 'equals' is not a subtype of the return type of the overridden member 'public open fun equals(other: Any?): kotlin.Boolean defined in skip.foundation.JSON'
        // e: :51:41 The boolean literal does not conform to the expected type JSON.Boolean
        // e: :52:20 Type mismatch: inferred type is kotlin.Boolean but skip.foundation.JSON.Boolean was expected
        // e: :62:43 Return type of 'equals' is not a subtype of the return type of the overridden member 'public open fun equals(other: Any?): kotlin.Boolean defined in skip.foundation.JSON'
        // e: :63:43 The boolean literal does not conform to the expected type JSON.Boolean
        // e: :64:20 Type mismatch: inferred type is kotlin.Boolean but skip.foundation.JSON.Boolean was expected
        // e::84:37 No type arguments expected for class Array

        try await check(compiler:nil, swiftCode: {
            enum JSON : Hashable {
                case null
                case boolean(Bool)
                case number(Double)
                case string(String)
                case array([JSON])
                case object([String : JSON])
            }
            return ""
        }, kotlin: """
            sealed class JSON {
                class Null_: JSON() {
                }
                class Boolean(val associated0: Boolean): JSON() {
            
                    override fun equals(other: Any?): Boolean {
                        if (other !is Boolean) return false
                        return associated0 == other.associated0
                    }
                    override fun hashCode(): Int {
                        var result = 1
                        result = Hasher.combine(result, associated0)
                        return result
                    }
                }
                class Number(val associated0: Double): JSON() {
            
                    override fun equals(other: Any?): Boolean {
                        if (other !is Number) return false
                        return associated0 == other.associated0
                    }
                    override fun hashCode(): Int {
                        var result = 1
                        result = Hasher.combine(result, associated0)
                        return result
                    }
                }
                class String(val associated0: String): JSON() {
            
                    override fun equals(other: Any?): Boolean {
                        if (other !is String) return false
                        return associated0 == other.associated0
                    }
                    override fun hashCode(): Int {
                        var result = 1
                        result = Hasher.combine(result, associated0)
                        return result
                    }
                }
                class Array(val associated0: Array<JSON>): JSON() {
            
                    override fun equals(other: Any?): Boolean {
                        if (other !is Array) return false
                        return associated0 == other.associated0
                    }
                    override fun hashCode(): Int {
                        var result = 1
                        result = Hasher.combine(result, associated0)
                        return result
                    }
                }
                class Object_(val associated0: Dictionary<String, JSON>): JSON() {
            
                    override fun equals(other: Any?): Boolean {
                        if (other !is Object_) return false
                        return associated0 == other.associated0
                    }
                    override fun hashCode(): Int {
                        var result = 1
                        result = Hasher.combine(result, associated0)
                        return result
                    }
                }
            
                companion object {
                    val null_: JSON = Null_()
                    fun boolean(associated0: Boolean): JSON {
                        return Boolean(associated0)
                    }
                    fun number(associated0: Double): JSON {
                        return Number(associated0)
                    }
                    fun string(associated0: String): JSON {
                        return String(associated0)
                    }
                    fun array(associated0: Array<JSON>): JSON {
                        return Array(associated0)
                    }
                    fun object_(associated0: Dictionary<String, JSON>): JSON {
                        return Object_(associated0)
                    }
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
            fun f(number: Int): String {
                return "${number}"
            }
            fun f(string: String): Int {
                return string.length
            }
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














