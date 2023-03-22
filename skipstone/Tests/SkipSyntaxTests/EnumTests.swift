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
        internal enum class E(val rawValue: Int) {
            a(0),
            b(1),
            c(100),
            d(101);
        }
        """)

        try await check(swift: """
        enum E: String {
            case a
            case b = "B"
            case c
        }
        """, kotlin: """
        internal enum class E(val rawValue: String) {
            a("a"),
            b("B"),
            c("c");
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
        internal enum class E(val rawValue: Int) {
            a(0),
            b(1);

            internal fun plusOne(): Int {
                return rawValue + 1
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
        internal enum class E(val rawValue: Int) {
            a(0),

            b(1);

            internal fun plusOne(): Int {
                return rawValue + 1
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
            class acase: E() {
            }
            class bcase(val associated0: Int, val associated1: String): E() {
            }

            companion object {
                val a: E = acase()
                fun b(associated0: Int = 1, associated1: String): E {
                    return bcase(associated0, associated1)
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
            class acase: E() {
            }
            class bcase(val associated0: Int, val associated1: String): E() {
                val i = associated0
            }

            companion object {
                val a: E = acase()
                fun b(i: Int = 1, associated1: String): E {
                    return bcase(i, associated1)
                }
            }
        }
        """)
    }

    func testEnumUse() async throws {
        try await check(symbols: symbols, swift: """
        func f() {
            enumTestsEnumFunc(e: .a)
            enumTestsEnumFunc(e: .b)
        }
        """, kotlin: """
        internal fun f() {
            enumTestsEnumFunc(e = EnumTestsEnum.a)
            enumTestsEnumFunc(e = EnumTestsEnum.b)
        }
        """)

        try await check(symbols: symbols, swift: """
        func f() {
            enumTestsAssociatedValueEnumFunc(e: .a(100))
            enumTestsAssociatedValueEnumFunc(e: .b)
        }
        """, kotlin: """
        internal fun f() {
            enumTestsAssociatedValueEnumFunc(e = EnumTestsAssociatedValueEnum.a(100))
            enumTestsAssociatedValueEnumFunc(e = EnumTestsAssociatedValueEnum.b)
        }
        """)
    }

    // TODO: Automatic Equatable for enums without associated values converted to sealed classes... other enums too?
}

enum EnumTestsEnum {
    case a
    case b
}
func enumTestsEnumFunc(e: EnumTestsEnum) {
}

enum EnumTestsAssociatedValueEnum {
    case a(Int)
    case b
}
func enumTestsAssociatedValueEnumFunc(e: EnumTestsAssociatedValueEnum) {
}
