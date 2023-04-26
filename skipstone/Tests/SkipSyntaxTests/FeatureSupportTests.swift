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

    func testCheckUnicodeString() async throws {
        try await check(expectFailure: true, swiftCode: {
            let currencySpacing = "\u{00A0}"
            return "\(currencySpacing)"
        }, kotlin: """
            val currencySpacing = " "
            return "${currencySpacing}"
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

    func testCheckDisambiguateFunc() async throws {
        // failed - Transpilation produced unexpected messages: Source.swift: warning: Skip is unable to disambiguate this function call. Consider differentiating your functions with unique parameter labels

        // Source.kts:7:7: error: overload resolution ambiguity:
        // public final fun doSomething(): Int defined in Source
        // public final fun doSomething(): String defined in Source
        // print(doSomething() as String)

        // try await check(compiler: nil, swiftCode: {
        //      func doSomething() -> String {
        //          "ZZZ"
        //      }
        //      func doSomething() -> Int {
        //          1
        //      }
        //      return doSomething() as String
        //  }, kotlin: """
        //      fun doSomething(): String {
        //          return "ZZZ"
        //      }
        //      fun doSomething(): Int {
        //          return 1
        //      }
        //      return doSomething() as String
        //      """)
    }

    func testInferCaseVariable() async throws {
        try await check(swiftCode: {
            enum SomeEnum {
                case case1
                case case2
            }
            func enumStuff() -> String {
                var x = SomeEnum.case1
                x = .case2
                return "\(x)"
            }
            return enumStuff()
        }, kotlin: """
            enum class SomeEnum {
                case1,
                case2;
            }
            fun enumStuff(): String {
                var x = SomeEnum.case1
                x = SomeEnum.case2
                return "${x}"
            }
            return enumStuff()
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
}









