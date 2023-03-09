@testable import SkipSyntax
import XCTest

final class ConditionalTests: XCTestCase {
    func testIfCondition() async throws {
        try await check(swift: """
        if i == 1 {
            print("yes")
        }
        """, kotlin: """
        if (i == 1) {
            print("yes")
        }
        """)
        
        try await check(swift: """
        if !(i == 1) {
            print("yes")
        }
        """, kotlin: """
        if (!(i == 1)) {
            print("yes")
        }
        """)
    }

    func testCompoundIfCondition() async throws {
        try await check(swift: """
        if i > 1 && i < 100 {
            print("yes")
        }
        """, kotlin: """
        if (i > 1 && i < 100) {
            print("yes")
        }
        """)

        try await check(swift: """
        if (i < 0 || i > 1) && i < 100 {
            print("yes")
        }
        """, kotlin: """
        if ((i < 0 || i > 1) && i < 100) {
            print("yes")
        }
        """)

        try await check(swift: """
        if i < 0 || (i > 1 && i < 100) {
            print("yes")
        }
        """, kotlin: """
        if (i < 0 || (i > 1 && i < 100)) {
            print("yes")
        }
        """)
    }

    func testMultipleIfConditions() async throws {
        try await check(swift: """
        if boolValue, i < 100 {
            print("yes")
        }
        """, kotlin: """
        if (boolValue && (i < 100)) {
            print("yes")
        }
        """)
    }

    func testElse() async throws {
        try await check(swift: """
        if i < 100 {
            print("yes")
        } else {
            print("no")
        }
        """, kotlin: """
        if (i < 100) {
            print("yes")
        } else {
            print("no")
        }
        """)
    }

    func testElseIf() async throws {
        try await check(swift: """
        if i < 0 {
            print("negative")
        } else if i > 0 {
            print("positive")
        } else {
            print("zero")
        }
        """, kotlin: """
        if (i < 0) {
            print("negative")
        } else if (i > 0) {
            print("positive")
        } else {
            print("zero")
        }
        """)
    }

    func testOptionalBinding() async throws {
        try await check(swift: """
        var i: Int?
        if let i {
            print(i)
        }
        """, kotlin: """
        internal var i: Int? = null
        if (i != null) {
            print(i)
        }
        """)

        try await check(swift: """
        var i: Int?
        if let i = i {
            print(i)
        }
        """, kotlin: """
        internal var i: Int? = null
        if (i != null) {
            print(i)
        }
        """)

        try await check(swift: """
        var i: Int?
        if let x = i {
            print(x)
        }
        """, kotlin: """
        internal var i: Int? = null
        i?.let { x ->
            print(x)
        }
        """)
    }

    func testMutableStructOptionalBinding() async throws {
        // Translate let into a simple null check because the value can't change
        try await check(swift: """
        if let i {
            print(i)
        }
        """, kotlin: """
        if (i != null) {
            print(i.sref())
        }
        """)

        // Translate var into a new reference because we don't want to mutate the original value
        try await check(swift: """
        if var i {
            i.mutate()
        }
        """, kotlin: """
        i.sref()?.let { i ->
            var i = i
            i.mutate()
        }
        """)
    }

    func testOptionalBindingElse() async throws {
        try await check(swift: """
        var i: Int?
        if let i {
            print(i)
        } else {
            print("nil")
        }
        """, kotlin: """
        internal var i: Int? = null
        if (i != null) {
            print(i)
        } else {
            print("nil")
        }
        """)

        try await check(swift: """
        var i: Int?
        if let x = i {
            print(x)
        } else {
            print("nil")
        }
        """, kotlin: """
        internal var i: Int? = null
        var letexec_0 = false
        i?.let { x ->
            letexec_0 = true
            print(x)
        }
        if (!letexec_0) {
            print("nil")
        }
        """)
    }

    func testOptionalBindingElseIf() async throws {
        try await check(swift: """
        var i: Int?
        if x > 0 {
            print("positive")
        } else if let i {
            print(i)
        } else if let x = i {
            print(x)
        } else {
            print("nil")
        }
        """, kotlin: """
        internal var i: Int? = null
        if (x > 0) {
            print("positive")
        } else if (i != null) {
            print(i)
        } else {
            var letexec_0 = false
            i?.let { x ->
                letexec_0 = true
                print(x)
            }
            if (!letexec_0) {
                print("nil")
            }
        }
        """)

        try await check(swift: """
        var i: Int?
        if var i {
            print(i)
        } else if x > 0 {
            print("positive")
        } else if let y = i {
            print(y)
        }
        """, kotlin: """
        internal var i: Int? = null
        var letexec_0 = false
        i?.let { i ->
            var i = i
            letexec_0 = true
            print(i)
        }
        if (!letexec_0) {
            if (x > 0) {
                print("positive")
            } else {
                i?.let { y ->
                    print(y)
                }
            }
        }
        """)

        try await check(swift: """
        var i: Int?
        if var i {
            print(i)
        } else if let x = i {
            print(x)
        } else {
            print("nil")
        }
        """, kotlin: """
        internal var i: Int? = null
        var letexec_0 = false
        i?.let { i ->
            var i = i
            letexec_0 = true
            print(i)
        }
        if (!letexec_0) {
            var letexec_1 = false
            i?.let { x ->
                letexec_1 = true
                print(x)
            }
            if (!letexec_1) {
                print("nil")
            }
        }
        """)
    }

    func testMultipleOptionalBindings() async throws {
        try await check(swift: """
        var i: Int?
        var j: String?
        var k: Int?
        if var i, i > 5, let x = j, x == "x" || x == "y" {
            print(i)
        } else if boolValue, let x = k {
            print(x)
        }
        """, kotlin: """
        internal var i: Int? = null
        internal var j: String? = null
        internal var k: Int? = null
        var letexec_0 = false
        i?.let { i ->
            var i = i
            if (i > 5) {
                j?.let { x ->
                    if (x == "x" || x == "y") {
                        letexec_0 = true
                        print(i)
                    }
                }
            }
        }
        if (!letexec_0) {
            if (boolValue) {
                k?.let { x ->
                    print(x)
                }
            }
        }
        """)
    }

    func testOptionalBindingUsingPreviousOptionalBinding() async throws {
        try await check(symbols: symbols, swift: """
        var c: ConditionalTestsClass?
        if let x = c, let related = x.related, let doublerelated = related.related {
            print(doublerelated)
        }
        """, kotlin: """
        internal var c: ConditionalTestsClass? = null
        c?.let { x ->
            x.related?.let { related ->
                related.related?.let { doublerelated ->
                    print(doublerelated)
                }
            }
        }
        """)
    }

    func testAddUnreachableErrorIfReturnRequired() async throws {
        try await check(swift: """
        func f(i: Int?) -> Int {
            if let x = i {
                return x
            } else {
                return 0
            }
        }
        """, kotlin: """
        internal fun f(i: Int?): Int {
            var letexec_0 = false
            i?.let { x ->
                letexec_0 = true
                return x
            }
            if (!letexec_0) {
                return 0
            }
            error("Unreachable")
        }
        """)

        // No error added if the block ends in 'return'
        try await check(swift: """
        func f(i: Int?) -> Int {
            if let x = i {
                return x
            } else {
                print("null")
            }
            return 0
        }
        """, kotlin: """
        internal fun f(i: Int?): Int {
            var letexec_0 = false
            i?.let { x ->
                letexec_0 = true
                return x
            }
            if (!letexec_0) {
                print("null")
            }
            return 0
        }
        """)

        // No error added for 'if' that retains its 'else'
        try await check(swift: """
        func f(i: Int?) -> Int {
            if let i {
                return i
            } else {
                return 0
            }
        }
        """, kotlin: """
        internal fun f(i: Int?): Int {
            if (i != null) {
                return i
            } else {
                return 0
            }
        }
        """)

        try await check(swift: """
        func f(i: Int?) -> Int {
            let r = {
                if let x = i {
                    return x
                } else {
                    return 0
                }
            }()
            return r
        }
        """, kotlin: """
        internal fun f(i: Int?): Int {
            val r = linvoke llabel@{
                var letexec_0 = false
                i?.let { x ->
                    letexec_0 = true
                    return@llabel x
                }
                if (!letexec_0) {
                    return@llabel 0
                }
                error("Unreachable")
            }
            return r
        }
        """)

        // No error added if no value returned
        try await check(swift: """
        func f(i: Int?) -> Int {
            {
                if let x = i {
                    print(x)
                } else {
                    print(0)
                }
            }()
            return 100
        }
        """, kotlin: """
        internal fun f(i: Int?): Int {
            {
                var letexec_0 = false
                i?.let { x ->
                    letexec_0 = true
                    print(x)
                }
                if (!letexec_0) {
                    print(0)
                }
            }()
            return 100
        }
        """)
    }

    func testIfCase() async throws {
        try await check(symbols: symbols, swift: """
        func f(e: ConditionalTestsEnum) {
            if case .case1 = e {
                print("A")
            }
        }
        """, kotlin: """
        internal fun f(e: ConditionalTestsEnum) {
            if (e == ConditionalTestsEnum.case1) {
                print("A")
            }
        }
        """)

        try await check(symbols: symbols, swift: """
        func f(e: ConditionalTestsAssociatedValueEnum) {
            if case .case2(_, let s) = e {
                let str = s // No .sref() expected
                print(str)
            }
        }
        """, kotlin: """
        internal fun f(e: ConditionalTestsAssociatedValueEnum) {
            if (e is ConditionalTestsAssociatedValueEnum.case2) {
                val s = e.associated1
                val str = s
                print(str)
            }
        }
        """)
    }

    func testGuardCondition() async throws {
        try await check(swift: """
        guard i == 1 else {
            return
        }
        """, kotlin: """
        if (i != 1) {
            return
        }
        """)

        try await check(swift: """
        guard !(i == 1) else {
            return
        }
        """, kotlin: """
        if ((i == 1)) {
            return
        }
        """)
    }

    func testCompoundGuardCondition() async throws {
        try await check(swift: """
        guard i > 1 && i < 100 else {
            return
        }
        """, kotlin: """
        if (i <= 1 || i >= 100) {
            return
        }
        """)

        try await check(swift: """
        guard (i < 0 || i > 1) && i < 100 else {
            return
        }
        """, kotlin: """
        if ((i >= 0 && i <= 1) || i >= 100) {
            return
        }
        """)

        try await check(swift: """
        guard i < 0 || (i > 1 && i < 100) else {
            return
        }
        """, kotlin: """
        if (i >= 0 && (i <= 1 || i >= 100)) {
            return
        }
        """)
    }

    func testMultipleGuardConditions() async throws {
        try await check(swift: """
        guard boolValue, i <= 100 else {
            return
        }
        """, kotlin: """
        if (!boolValue || (i > 100)) {
            return
        }
        """)
    }

    func testGuardOptionalBinding() async throws {
        try await check(swift: """
        var i: Int?
        guard let i else {
            print(i)
            return
        }
        print(i + 1)
        """, kotlin: """
        internal var i: Int? = null
        if (i == null) {
            print(i)
            return
        }
        print(i + 1)
        """)

        try await check(swift: """
        var i: Int?
        guard let i = i else {
            print(i)
            return
        }
        print(i + 1)
        """, kotlin: """
        internal var i: Int? = null
        if (i == null) {
            print(i)
            return
        }
        print(i + 1)
        """)

        try await check(swift: """
        var i: Int?
        guard var i = i else {
            print(i)
            return
        }
        print(i + 1)
        """, kotlin: """
        internal var i: Int? = null
        var i_0 = i
        if (i_0 == null) {
            print(i)
            return
        }
        print(i_0 + 1)
        """)
    }

    func testGuardMutableStructOptionalBinding() async throws {
        try await check(swift: """
        guard let i else {
            print(i)
            return
        }
        print(i)
        """, kotlin: """
        if (i == null) {
            print(i.sref())
            return
        }
        print(i.sref())
        """)

        try await check(swift: """
        guard let x = i else {
            print(i)
            return
        }
        print(x)
        """, kotlin: """
        val x_0 = i.sref()
        if (x_0 == null) {
            print(i.sref())
            return
        }
        print(x_0.sref())
        """)
    }

    func testGuardOptionalBindingUsingPreviousOptionalBinding() async throws {
        try await check(symbols: symbols, swift: """
        var c: ConditionalTestsClass?
        guard var c, c > 5, let related = c.related, let doublerelated = related.related else {
            doSomethingWith(c)
            return
        }
        print(doublerelated)
        """, kotlin: """
        internal var c: ConditionalTestsClass? = null
        var c_0 = c
        if ((c_0 == null) || (c_0 <= 5)) {
            doSomethingWith(c)
            return
        }
        val related_0 = c_0.related
        if (related_0 == null) {
            doSomethingWith(c)
            return
        }
        val doublerelated_0 = related_0.related
        if (doublerelated_0 == null) {
            doSomethingWith(c)
            return
        }
        print(doublerelated_0)
        """)
    }

    func testGuardsWithSameNamedOptionalBindings() async throws {
        try await check(swift: """
        var i: Int?
        guard var i else {
            print(i)
            return
        }
        print(i)
        guard var i = x else {
            print(i)
            return
        }
        print(i)
        """, kotlin: """
        internal var i: Int? = null
        var i_0 = i
        if (i_0 == null) {
            print(i)
            return
        }
        print(i_0)
        var i_1 = x.sref()
        if (i_1 == null) {
            print(i_0)
            return
        }
        print(i_1.sref())
        """)
    }
}

private class ConditionalTestsClass {
    var related: ConditionalTestsClass?
}

private enum ConditionalTestsEnum {
    case case1
    case case2
}
private enum ConditionalTestsAssociatedValueEnum {
    case case1
    case case2(Int, String)
}
