@testable import SkipSyntax
import XCTest

final class TupleTests: XCTestCase {
    func testDeclarations() async throws {
        try await check(swift: """
        var unit = ()
        """, kotlin: """
        internal var unit = Unit
        """)

        try await check(swift: """
        var pair: (Int, String) = (1, "s")
        """, kotlin: """
        internal var pair: Pair<Int, String> = Pair(1, "s")
        """)

        try await check(swift: """
        var triple: (Int, String, Double) = (1, "s", 0.5)
        """, kotlin: """
        internal var triple: Triple<Int, String, Double> = Triple(1, "s", 0.5)
        """)

        try await check(swift: """
        func f() -> (Int, String) {
            return (1, "s")
        }
        """, kotlin: """
        internal fun f(): Pair<Int, String> {
            return Pair(1, "s")
        }
        """)

        try await check(swift: """
        func f() -> (A, B) {
            return (A(), B())
        }
        """, kotlin: """
        internal fun f(): Pair<A, B> {
            return Pair(A(), B())
        }
        """)
    }

    func testDestructuring() async throws {
        try await check(swift: """
        {
            let (a, b) = (1, 2)
            print(a)
            print(b)
        }
        """, kotlin: """
        {
            val (a, b) = Pair(1, 2)
            print(a)
            print(b)
        }
        """)

        try await check(swift: """
        {
            let t = (1, 2)
            let (a, b) = t
            print(a)
            print(b)
        }
        """, kotlin: """
        {
            val t = Pair(1, 2)
            val (a, b) = t
            print(a)
            print(b)
        }
        """)

        // Unknown type may be mutable shared value
        try await check(swift: """
        {
            let (a, b) = (x, y)
            print(a)
            print(b)
        }
        """, kotlin: """
        {
            val (a, b) = Pair(x.valref(), y.valref())
            print(a.valref())
            print(b.valref())
        }
        """)

        try await check(swift: """
        {
            let (a, b) = t
            print(a)
            print(b)
        }
        """, kotlin: """
        {
            val (a, b) = t.valref()
            print(a.valref())
            print(b.valref())
        }
        """)
    }

    func testDestructuredOptionalBinding() async throws {
        try await check(swift: """
        var t: (Int, String)?
        if let (i, s) = t {
            print(i)
            print(s)
        }
        """, kotlin: """
        internal var t: Pair<Int, String>? = null
        if (true) {
            val (i, s) = t
            if (i != null && s != null) {
                print(i)
                print(s)
            }
        }
        """)

        // Unknown element types may be shared mutable values
        try await check(swift: """
        if let (i, s) = t {
            print(i)
            print(s)
        }
        """, kotlin: """
        if (true) {
            val (i, s) = t.valref()
            if (i != null && s != null) {
                print(i.valref())
                print(s.valref())
            }
        }
        """)
    }
}
