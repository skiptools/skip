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
        try await check(symbols: symbols, swift: """
        var i: Int?
        if let x = i {
            print(x)
        }
        """, kotlin: """
        internal var i: Int?
        val x = i
        if (x != null) {
            print(x)
        }
        """)

        try await check(symbols: symbols, swift: """
        var i: Int?
        if var x = i {
            print(x)
        }
        """, kotlin: """
        internal var i: Int?
        var x = i
        if (x != null) {
            print(x)
        }
        """)

        try await check(symbols: symbols, swift: """
        var i: Int?
        if let i {
            print(i)
        }
        """, kotlin: """
        internal var i: Int?
        val i = i
        if (i != null) {
            print(i)
        }
        """)

        try await check(symbols: symbols, swift: """
        var i: Int?
        if var i {
            print(i)
        }
        """, kotlin: """
        internal var i: Int?
        var i = i
        if (i != null) {
            print(i)
        }
        """)

        try await check(symbols: symbols, swift: """
        var i: Int?
        var j: String?
        var k: Int?
        if let i, i > 5, let x = j, x == "x" || x == "y" {
            print(i)
        } else if boolValue, let x = k {
            print(x)
        }
        """, kotlin: """
        internal var i: Int?
        internal var j: String?
        internal var k: Int?
        val i = i
        val x = j
        val x = k
        if ((i != null) && (i > 5) && (x != null) && (x == "x" || x == "y")) {
            print(i)
        } else if (boolValue && (x != null)) {
            print(x)
        }
        """)
    }

    func testSharedMutableValueOptionalBinding() async throws {
        try await check(symbols: symbols, swift: """
        if let x = i {
            print(x)
        }
        """, kotlin: """
        val x = i.valref()
        if (x != null) {
            print(x.valref())
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
}
