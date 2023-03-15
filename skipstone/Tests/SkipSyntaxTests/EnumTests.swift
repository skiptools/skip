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
            class a: E() {
            }
            class b(val associated0: Int = 1, val associated1: String): E() {
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
            class a: E() {
            }
            class b(i: Int = 1, val associated1: String): E() {
                val associated0 = i
            }
        }
        """)
    }

    // TODO: Automatic Equatable for enums without associated values converted to sealed classes... other enums too?
}
