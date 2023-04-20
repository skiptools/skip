@testable import SkipSyntax
import XCTest

/// A test case that verifies that transpilation are *not* working as hoped.
final class FeatureSupportTests: XCTestCase {

    func testCheckSwiftCompiledSource() async throws {
        try await check(swiftCode: {
            return "\(1 + 2)"
        }, kotlin: """
            return "${1 + 2}"
            """)
    }

    func testTranspilePrimeCheck() async throws {
        try await check(swiftCode: {
            func isPrime(_ number: Int) -> Bool {
                guard number > 1 else {
                    return false
                }
                for i in 2..<number {
                    if number % i == 0 {
                        return false
                    }
                }
                return true
            }
            return isPrime(100019) ? "YES" : "NO"
        }, kotlin: """
            fun isPrime(number: Int): Boolean {
                if (number <= 1) {
                    return false
                }
                for (i in 2 until number) {
                    if (number % i == 0) {
                        return false
                    }
                }
                return true
            }
            return if (isPrime(100019)) "YES" else "NO"
            """)
    }

    func testCheckSwiftCompiledTypes() async throws {

        try await check(swiftCode: {
            struct Foo {
            }
            return nil
        }, kotlin: """
            class Foo {
            }
            return null
            """)

        try await check(swiftCode: {
            struct Foo {
            }
            return nil
        }, kotlin: """
            class Foo {
            }
            return null
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
