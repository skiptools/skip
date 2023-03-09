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
    }

    func testReturnSharedMutableStruct() async throws {
        // Newly-constructed instances do not need sref call
        try await check(swift: """
        func f() -> (A, B) {
            return (A(), B())
        }
        """, kotlin: """
        internal fun f(): Pair<A, B> {
            return Pair(A(), B())
        }
        """)

        try await check(swift: """
        func f(a: A, b: B) -> (A, B) {
            return (a, b)
        }
        """, kotlin: """
        internal fun f(a: A, b: B): Pair<A, B> {
            return Pair(a.sref(), b.sref())
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

        try await check(swift: """
        {
            let t = (1, 2)
            let (a, _) = t
            print(a)
        }
        """, kotlin: """
        {
            val t = Pair(1, 2)
            val (a, _) = t
            print(a)
        }
        """)
    }

    func testDestructuringSharedMutableStruct() async throws {
        try await check(swift: """
        {
            let (a, b) = (x, y)
            print(a)
            print(b)
        }
        """, kotlin: """
        {
            val (a, b) = Pair(x.sref(), y.sref())
            print(a.sref())
            print(b.sref())
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
            val (a, b) = t.sref()
            print(a.sref())
            print(b.sref())
        }
        """)
    }

    func testDestructuringOptionalBinding() async throws {
        try await check(swift: """
        var t: (Int, String)?
        if let (i, s) = t {
            print(i)
            print(s)
        }
        """, kotlin: """
        internal var t: Pair<Int, String>? = null
        t?.let { (i, s) ->
            print(i)
            print(s)
        }
        """)

        try await check(swift: """
        var t: (Int, String)?
        if let (_, s) = t {
            print(s)
        }
        """, kotlin: """
        internal var t: Pair<Int, String>? = null
        t?.let { (_, s) ->
            print(s)
        }
        """)
    }

    func testDestructuringOptionalBindingSharedMutableStruct() async throws {
        try await check(swift: """
        if let (i, s) = t {
            print(i)
            print(s)
        }
        """, kotlin: """
        t.sref()?.let { (i, s) ->
            print(i.sref())
            print(s.sref())
        }
        """)
    }

    func testMemberAccess() async throws {
        try await check(swift: """
        {
            let t = (1, "s", 0.5)
            let i = t.0
            let s = t.1
            let d = t.2
        }
        """, kotlin: """
        {
            val t = Triple(1, "s", 0.5)
            val i = t.first
            val s = t.second
            val d = t.third
        }
        """)
    }

    func testMemberAccessSharedMutableStruct() async throws {
        try await check(swift: """
        {
            let i = t.0
            let s = t.1
            let d = t.2
        }
        """, kotlin: """
        {
            val i = t.first.sref()
            val s = t.second.sref()
            val d = t.third.sref()
        }
        """)
    }
}
