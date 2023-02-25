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

    func testSingleOptionalBinding() async throws {
        try await check(swift: """
        var i: Int?
        if let x = i {
            print(x)
        }
        """, kotlin: """
        internal var i: Int? = null
        val x_0 = i
        if (x_0 != null) {
            print(x_0)
        }
        """)

        try await check(swift: """
        var i: Int?
        if var x = i {
            print(x)
        }
        """, kotlin: """
        internal var i: Int? = null
        var x_0 = i
        if (x_0 != null) {
            print(x_0)
        }
        """)

        try await check(swift: """
        var i: Int?
        if let i {
            print(i)
        } else {
            print(i == nil)
        }
        """, kotlin: """
        internal var i: Int? = null
        val i_0 = i
        if (i_0 != null) {
            print(i_0)
        } else {
            print(i == null)
        }
        """)

        try await check(swift: """
        var i: Int?
        if var i {
            print(i)
        } else {
            print(i == nil)
        }
        """, kotlin: """
        internal var i: Int? = null
        var i_0 = i
        if (i_0 != null) {
            print(i_0)
        } else {
            print(i == null)
        }
        """)
    }

    func testMultipleOptionalBindings() async throws {
        try await check(swift: """
        var i: Int?
        var j: String?
        var k: Int?
        if let i, i > 5, let x = j, x == "x" || x == "y" {
            print(i)
        } else if boolValue, let x = k {
            print(i)
            print(x)
        }
        print(i)
        """, kotlin: """
        internal var i: Int? = null
        internal var j: String? = null
        internal var k: Int? = null
        val i_0 = i
        val x_1 = j
        val x_2 = k
        if ((i_0 != null) && (i_0 > 5) && (x_1 != null) && (x_1 == "x" || x_1 == "y")) {
            print(i_0)
        } else if (boolValue && (x_2 != null)) {
            print(i)
            print(x_2)
        }
        print(i)
        """)
    }

    func testOptionalBindingUsingPreviousOptionalBinding() async throws {
        try await check(symbols: symbols, swift: """
        var c: ConditionalTestsClass?
        if let x = c, let related = x.related {
            print(related)
        }
        """, kotlin: """
        internal var c: ConditionalTestsClass? = null
        val x_0 = c
        val related_1 = if (x_0 != null) x_0.related else null
        if ((x_0 != null) && (related_1 != null)) {
            print(related_1)
        }
        """)
    }

    func testSharedMutableValueOptionalBinding() async throws {
        try await check(symbols: symbols, swift: """
        if let x = i {
            print(x)
        }
        """, kotlin: """
        val x_0 = i.valref()
        if (x_0 != null) {
            print(x_0.valref())
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

    func testGuardLet() async throws {
        try await check(swift: """
        var i: Int?
        guard let i else {
            print(i)
            return
        }
        print(i + 1)
        """, kotlin: """
        internal var i: Int? = null
        val i_0 = i
        if (i_0 == null) {
            print(i)
            return
        }
        print(i_0 + 1)
        """)
    }

    func testGuardLetTypeInference() async throws {
        // We should understand the binding to 'related' and that it is not a shared value type
        try await check(symbols: symbols, swift: """
        var c: ConditionalTestsClass?
        guard let c, let related = c.related else {
            return
        }
        print(related)
        """, kotlin: """
        internal var c: ConditionalTestsClass? = null
        val c_0 = c
        val related_1 = if (c_0 != null) c_0.related else null
        if ((c_0 == null) || (related_1 == null)) {
            return
        }
        print(related_1)
        """)
    }
}

private class ConditionalTestsClass {
    var related: ConditionalTestsClass?
}
