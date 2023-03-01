@testable import SkipSyntax
import XCTest

final class LoopTests: XCTestCase {
    func testWhileLoop() async throws {
        try await check(swift: """
        while isTrue() {
            doSomething()
        }
        """, kotlin: """
        while (isTrue()) {
            doSomething()
        }
        """)

        try await check(swift: """
        while x < 5 || (x > 100 && x < 500) {
            doSomething()
        }
        """, kotlin: """
        while (x < 5 || (x > 100 && x < 500)) {
            doSomething()
        }
        """)

        try await check(swift: """
        while isTrue(), x < 5 {
            doSomething()
        }
        """, kotlin: """
        while (isTrue() && (x < 5)) {
            doSomething()
        }
        """)

        try await check(swift: """
        var i: Int?
        while let i, i < 5 {
            doSomething()
        }
        """, kotlin: """
        internal var i: Int? = null
        while ((i != null) && (i < 5)) {
            doSomething()
        }
        """)

        try await check(swift: """
        var i: Int?
        while let i = i, i < 5 {
            doSomething()
        }
        """, kotlin: """
        internal var i: Int? = null
        while ((i != null) && (i < 5)) {
            doSomething()
        }
        """)
    }

    func testRepeatWhileLoop() async throws {
        try await check(swift: """
        repeat {
            doSomething()
        } while isTrue()
        """, kotlin: """
        do {
            doSomething()
        } while (isTrue())
        """)

        try await check(swift: """
        repeat {
            doSomething()
        } while x < 5 || (x > 100 && x < 500)
        """, kotlin: """
        do {
            doSomething()
        } while (x < 5 || (x > 100 && x < 500))
        """)
    }

    func testForLoop() async throws {
        try await check(swift: """
        for i in [1, 2, 3] {
            print(i)
        }
        """, kotlin: """
        for (i in arrayOf(1, 2, 3)) {
            print(i)
        }
        """)

        try await check(swift: """
        {
            let a = [1, 2, 3]
            for i in a {
                print(i)
            }
        }
        """, kotlin: """
        {
            val a = arrayOf(1, 2, 3)
            for (i in a.valref()) {
                print(i)
            }
        }
        """)

        try await check(swift: """
        {
            for i in [a, b, c] {
                print(i.valref())
            }
        }
        """, kotlin: """
        {
            for (i in arrayOf(a.valref(), b.valref(), c.valref())) {
                print(i.valref())
            }
        }
        """)

        try await check(swift: """
        for (i, s) in [(1, "a"), (2, "b"), (3, "c")] {
            print(i)
            print(s)
        }
        """, kotlin: """
        for ((i, s) in arrayOf(Pair(1, "a"), Pair(2, "b"), Pair(3, "c"))) {
            print(i)
            print(s)
        }
        """)
    }

    func testForLoopVarBinding() async throws {
        try await check(swift: """
        for var i in [1, 2, 3] {
            i += 1
            print(i)
        }
        """, kotlin: """
        for (i_0 in arrayOf(1, 2, 3)) {
            var i = i_0
            i += 1
            print(i)
        }
        """)
    }

    func testForLoopWhereGuard() async throws {
        try await check(swift: """
        for i in [1, 2, 3] where i % 2 == 0 {
            print(i)
        }
        """, kotlin: """
        for (i in arrayOf(1, 2, 3)) {
            if (i % 2 != 0) {
                continue
            }
            print(i)
        }
        """)
    }

    func testBreak() async throws {
        try await check(swift: """
        for i in [1, 2, 3] {
            if i % 2 == 0 {
                break
            }
            print(i)
        }
        """, kotlin: """
        for (i in arrayOf(1, 2, 3)) {
            if (i % 2 == 0) {
                break
            }
            print(i)
        }
        """)

        try await check(swift: """
        loop: for i in [1, 2, 3] {
            if i % 2 == 0 {
                break loop
            }
            print(i)
        }
        """, kotlin: """
        loop@
        for (i in arrayOf(1, 2, 3)) {
            if (i % 2 == 0) {
                break@loop
            }
            print(i)
        }
        """)
    }

    func testContinue() async throws {
        try await check(swift: """
        for i in [1, 2, 3] {
            if i % 2 == 0 {
                continue
            }
            print(i)
        }
        """, kotlin: """
        for (i in arrayOf(1, 2, 3)) {
            if (i % 2 == 0) {
                continue
            }
            print(i)
        }
        """)

        try await check(swift: """
        loop: for i in [1, 2, 3] {
            if i % 2 == 0 {
                continue loop
            }
            print(i)
        }
        """, kotlin: """
        loop@
        for (i in arrayOf(1, 2, 3)) {
            if (i % 2 == 0) {
                continue@loop
            }
            print(i)
        }
        """)
    }
}
