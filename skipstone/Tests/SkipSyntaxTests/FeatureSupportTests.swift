@testable import SkipSyntax
import XCTest

/// A test case that verifies that transpilation are *not* working as hoped.
final class FeatureSupportTests: XCTestCase {
    func testTypealiasToSelf() async throws {
        throw XCTSkip("stack overflow")

        // this shouldn't be expected to work, but it should raise a good error rather than:
        // stack overflow in #7 0x00000001235e2898 in closure #1 in CodebaseInfo.Context.typeInfos(for:) at Sources/SkipSyntax/CodebaseInfo.swift:145

        try await check(swift: """
        typealias A = A

        class A {
        }

        class B : A {
        }
        """, kotlin: """
        typealias A = A

        internal open class A {
        }

        internal open class B: A() {
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
        try await check(swiftCode: {
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
            return "\(fibonacci(11))"
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
            return "${fibonacci(11)}"
            """)
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

//    func testNestedSimpleEnumInFunction() async throws {
//        // error: modifier 'enum' is not applicable to 'local class'
//        try await check(swift: """
//        class Foo {
//            public func someFunction() {
//                enum NestedEnum {
//                    case case1, case2, case3
//                }
//            }
//        }
//        """, kotlin: """
//        internal open class Foo {
//            open fun someFunction() {
//                internal enum class NestedEnum {
//                    case1,
//                    case2,
//                    case3;
//                }
//            }
//        }
//        """)
//    }
//
//    func testNestedComplexEnumInFunction() async throws {
//        // error: modifier 'sealed' is not applicable to 'local class'
//        try await check(swift: """
//        class Foo {
//            public func someFunction() {
//                enum ComplexEnum {
//                    case case1(String)
//                    case case2(Int)
//                    case case3(Bool)
//                }
//            }
//        }
//        """, kotlin: """
//        internal open class Foo {
//            open fun someFunction() {
//                internal sealed class ComplexEnum {
//                    class case1case(val associated0: String): ComplexEnum() {
//                    }
//                    class case2case(val associated0: Int): ComplexEnum() {
//                    }
//                    class case3case(val associated0: Boolean): ComplexEnum() {
//                    }
//
//                    companion object {
//                        fun case1(associated0: String): ComplexEnum {
//                            return case1case(associated0)
//                        }
//                        fun case2(associated0: Int): ComplexEnum {
//                            return case2case(associated0)
//                        }
//                        fun case3(associated0: Boolean): ComplexEnum {
//                            return case3case(associated0)
//                        }
//                    }
//                }
//            }
//        }
//        """)
//    }
}














