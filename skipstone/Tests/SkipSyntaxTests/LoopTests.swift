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
        {
            var i: Int?
            while let i, i < 5 {
                doSomething()
            }
        }
        """, kotlin: """
        {
            var i: Int? = null
            while ((i != null) && (i < 5)) {
                doSomething()
            }
        }
        """)

        try await check(swift: """
        {
            var i: Int?
            while let i = i, i < 5 {
                doSomething()
            }
        }
        """, kotlin: """
        {
            var i: Int? = null
            while ((i != null) && (i < 5)) {
                doSomething()
            }
        }
        """)
    }

    func testWhileTranslatedGuard() async throws {
        try await check(supportingSwift: """
        func f() -> Int? {
            return 0
        }
        """, swift: """
        {
            while let x = f(), x < 5 {
                doSomething()
            }
        }
        """, kotlin: """
        {
            while (true) {
                val x_0 = f()
                if ((x_0 == null) || (x_0 >= 5)) {
                    break
                }
                doSomething()
            }
        }
        """)

        try await check(supportingSwift: """
        func f() -> Int? {
            return 0
        }
        """, swift: """
        func test() {
            while let i = f() {
                print(i)
            }
            let i = 1
            print(i)
        }
        """, kotlin: """
        internal fun test() {
            while (true) {
                val i_0 = f()
                if (i_0 == null) {
                    break
                }
                print(i_0)
            }
            val i = 1
            print(i)
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

    func testWhileCase() async throws {
        try await check(supportingSwift: """
        enum E {
            case case1
            case case2(Int, String)
        }
        """, swift: """
        let e: E
        while case .case2(let i, _) = e {
            print(i)
        }
        """, kotlin: """
        internal val e: E
        while (e is E.Case2Case) {
            val i = e.associated0
            print(i)
        }
        """)
    }

    func testWhileCaseTranslatedToGuard() async throws {
        try await check(supportingSwift: """
        enum E {
            case case1
            case case2(Int, String)
        }
        func f() -> E {
            return .case1
        }
        """, swift: """
        let x = 0
        while x > 1, case .case2(let i, _) = f() {
            print(i)
        }
        """, kotlin: """
        internal val x = 0
        while (true) {
            if (x <= 1) {
                break
            }
            val matchtarget_0 = f()
            if (matchtarget_0 !is E.Case2Case) {
                break
            }
            val i_0 = matchtarget_0.associated0
            print(i_0)
        }
        """)
    }

    func testForLoop() async throws {
        try await check(swift: """
        for i in [1, 2, 3] {
            print(i)
        }
        """, kotlin: """
        import skip.lib.Array

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
        import skip.lib.Array

        {
            val a = arrayOf(1, 2, 3)
            for (i in a.sref()) {
                print(i)
            }
        }
        """)

        try await check(swift: """
        {
            let d = [1: "a", 2: "b", 3: "c"]
            for (key, value) in d {
                print(key)
                print(value)
            }
        }
        """, kotlin: """
        {
            val d = dictionaryOf(Tuple2(1, "a"), Tuple2(2, "b"), Tuple2(3, "c"))
            for ((key, value) in d.sref()) {
                print(key)
                print(value)
            }
        }
        """)

        try await check(swift: """
        {
            for i in [a, b, c] {
                print(i.sref())
            }
        }
        """, kotlin: """
        import skip.lib.Array

        {
            for (i in arrayOf(a, b, c)) {
                print(i.sref())
            }
        }
        """)

        try await check(swift: """
        for (i, s) in [(1, "a"), (2, "b"), (3, "c")] {
            print(i)
            print(s)
        }
        """, kotlin: """
        import skip.lib.Array

        for ((i, s) in arrayOf(Tuple2(1, "a"), Tuple2(2, "b"), Tuple2(3, "c"))) {
            print(i)
            print(s)
        }
        """)
    }

    func testForLoopWildcard() async throws {
        try await check(swift: """
        for _ in 1...100 {
            doSomething()
        }
        """, kotlin: """
        for (unusedbinding in 1..100) {
            doSomething()
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
        import skip.lib.Array

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
        import skip.lib.Array

        for (i in arrayOf(1, 2, 3)) {
            if (i % 2 != 0) {
                continue
            }
            print(i)
        }
        """)
    }

    func testForLoopCase() async throws {
        try await check(swift: """
        {
            let a: [Int?] = [1, nil, 3]
            for case var i? in a {
                i += 1
                print(i)
            }
        }
        """, kotlin: """
        import skip.lib.Array

        {
            val a: Array<Int?> = arrayOf(1, null, 3)
            for (i_0 in a.sref()) {
                var i = i_0
                if (i == null) {
                    continue
                }
                i += 1
                print(i)
            }
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
        import skip.lib.Array

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
        import skip.lib.Array

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
        import skip.lib.Array

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
        import skip.lib.Array
        
        loop@
        for (i in arrayOf(1, 2, 3)) {
            if (i % 2 == 0) {
                continue@loop
            }
            print(i)
        }
        """)
    }

    func testForLoopMutateSequence() {
        var a = [1, 2, 3]
        var result: [Int] = []
        for i in a {
            result.append(i)
            a.append(i)
            if result.count > 10 {
                break
            }
        }
        XCTAssertEqual([1, 2, 3], result)
    }
}
