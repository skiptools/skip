@testable import Skip
import XCTest

final class LiteralTests: XCTestCase {
    func testIntLiteral() async throws {
        try await check(swift: """
        123
        """, kotlin: """
        123
        """)

        try await check(swift: """
        -123
        """, kotlin: """
        -123
        """)

        try await check(swift: """
        123_000_000
        """, kotlin: """
        123000000
        """)
    }

    func testStringLiteral() async throws {
        try await check(swift: """
        "abc"
        """, kotlin: """
        "abc"
        """)

        try await check(swift: """
        "1 + 1 = \\(1 + 1)"
        """, kotlin: """
        "1 + 1 = ${1 + 1}"
        """)

        try await check(swift: """
        "i = \\(i)"
        """, kotlin: """
        "i = $i"
        """)

        try await check(swift: """
        "It costs $x"
        """, kotlin: """
        "It costs \\$x"
        """)
    }
}
