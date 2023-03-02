@testable import SkipSyntax
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
        123_000_000
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

    func testArrayLiteral() async throws {
        try await check(swift: """
        {
            let a = [1, 2, 3]
        }
        """, kotlin: """
        {
            val a = arrayOf(1, 2, 3)
        }
        """)

        try await check(swift: """
        {
            let a: [Int] = [x, y, z]
        }
        """, kotlin: """
        {
            val a: Array<Int> = arrayOf(x, y, z)
        }
        """)

        try await check(swift: """
        {
            let a = [Int]()
        }
        """, kotlin: """
        {
            val a = Array<Int>()
        }
        """)
    }

    func testDictionaryLiteral() async throws {
        try await check(swift: """
        {
            let d = [1: "a", 2: "b", 3: "c"]
        }
        """, kotlin: """
        {
            val d = dictionaryOf(Pair(1, "a"), Pair(2, "b"), Pair(3, "c"))
        }
        """)

        try await check(swift: """
        {
            let d: [Int: String] = [x: a, y: b, z: c]
        }
        """, kotlin: """
        {
            val d: Dictionary<Int, String> = dictionaryOf(Pair(x, a), Pair(y, b), Pair(z, c))
        }
        """)

        try await check(swift: """
        {
            let d = [Int: String]()
        }
        """, kotlin: """
        {
            val d = Dictionary<Int, String>()
        }
        """)
    }
}
