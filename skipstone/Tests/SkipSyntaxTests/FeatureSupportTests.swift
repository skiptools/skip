@testable import SkipSyntax
import XCTest

/// A test case that verifies that transpilation are *not* working as hoped.
final class FeatureSupportTests: XCTestCase {

    func testInferCaseVariable() async throws {
        // error: modifier 'internal' is not applicable to 'local function'
        try await check(swift: """
        enum SomeEnum {
            case case1
            case case2
        }
        func enumStuff() {
            var x = SomeEnum.case1
            x = .case2
        }
        """, kotlin: """
        internal enum class SomeEnum {
            case1,
            case2;
        }
        internal fun enumStuff() {
            var x = SomeEnum.case1
            x = SomeEnum.case2
        }
        """)
    }

    func testNestedClassInFunction() async throws {
        // error: modifier 'internal' is not applicable to 'local class'
        try await check(swift: """
        class Foo {
            public func someFunction() {
                class NestedClass {
                }
            }
        }
        """, kotlin: """
        internal open class Foo {
            open fun someFunction() {
                internal open class NestedClass {
                }
            }
        }
        """)
    }

    func testNestedDoubleClassInFunction() async throws {
        // error: modifier 'internal' is not applicable to 'local class'
        // error: class is not allowed here
        try await check(swift: """
        class Foo {
            public func someFunction() {
                class NestedClass {
                    func someOtherFunction() {
                        class NestedClass2 {
                            class NestedClass3 {
                                func yetAnotherFunction() -> String {
                                    return "XXX"
                                }
                            }
                        }
                    }
                }
            }
        }
        """, kotlin: """
        internal open class Foo {
            open fun someFunction() {
                internal open class NestedClass {
                    internal open fun someOtherFunction() {
                        internal open class NestedClass2 {
                            internal open class NestedClass3 {
                                internal open fun yetAnotherFunction(): String {
                                    return "XXX"
                                }
                            }
                        }
                    }
                }
            }
        }
        """)
    }

    func testNestedStructInFunction() async throws {
        // error: modifier 'internal' is not applicable to 'local class'
        try await check(swift: """
        class Foo {
            public func someFunction() {
                struct NestedStruct {
                }
            }
        }
        """, kotlin: """
        internal open class Foo {
            open fun someFunction() {
                internal class NestedStruct {
                }
            }
        }
        """)
    }

    func testNestedSimpleEnumInFunction() async throws {
        // error: modifier 'enum' is not applicable to 'local class'
        try await check(swift: """
        class Foo {
            public func someFunction() {
                enum NestedEnum {
                    case case1, case2, case3
                }
            }
        }
        """, kotlin: """
        internal open class Foo {
            open fun someFunction() {
                internal enum class NestedEnum {
                    case1,
                    case2,
                    case3;
                }
            }
        }
        """)
    }

    func testNestedComplexEnumInFunction() async throws {
        // error: modifier 'sealed' is not applicable to 'local class'
        try await check(swift: """
        class Foo {
            public func someFunction() {
                enum ComplexEnum {
                    case case1(String)
                    case case2(Int)
                    case case3(Bool)
                }
            }
        }
        """, kotlin: """
        internal open class Foo {
            open fun someFunction() {
                internal sealed class ComplexEnum {
                    class case1case(val associated0: String): ComplexEnum() {
                    }
                    class case2case(val associated0: Int): ComplexEnum() {
                    }
                    class case3case(val associated0: Boolean): ComplexEnum() {
                    }

                    companion object {
                        fun case1(associated0: String): ComplexEnum {
                            return case1case(associated0)
                        }
                        fun case2(associated0: Int): ComplexEnum {
                            return case2case(associated0)
                        }
                        fun case3(associated0: Boolean): ComplexEnum {
                            return case3case(associated0)
                        }
                    }
                }
            }
        }
        """)
    }
}
