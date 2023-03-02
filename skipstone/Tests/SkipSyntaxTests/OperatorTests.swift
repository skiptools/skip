@testable import SkipSyntax
import XCTest

final class OperatorTests: XCTestCase {
    func testMath() async throws {
        try await check(symbols: symbols, swift: """
        func op(a: Int, b: Int) -> Bool {
            return a + b * 2 == .myZero
        }
        """, kotlin: """
        internal fun op(a: Int, b: Int): Boolean {
            return a + b * 2 == Int.myZero
        }
        """)

        try await check(symbols: symbols, swift: """
        func op(a: Double, b: Double) -> Bool {
            return a * b + 2 == .myZero
        }
        """, kotlin: """
        internal fun op(a: Double, b: Double): Boolean {
            return a * b + 2 == Double.myZero
        }
        """)
    }

    func testRange() async throws {
        try await check(symbols: symbols, swift: """
        for i in 0...10 {
            let b = i == .myZero
            print(b)
        }
        """, kotlin: """
        for (i in 0 .. 10) {
            val b = i == Int.myZero
            print(b)
        }
        """)

        try await check(symbols: symbols, swift: """
        for i in 0..<10 {
            let b = i == .myZero
            print(b)
        }
        """, kotlin: """
        for (i in 0 until 10) {
            val b = i == Int.myZero
            print(b)
        }
        """)
    }

    func testCast() async throws {
        try await check(symbols: symbols, swift: """
        let i = x as? Int
        let b = i == .myZero
        """, kotlin: """
        internal val i = x as? Int
        internal val b = i == Int.myZero
        """)

        try await check(symbols: symbols, swift: """
        let i = x as! Int
        let b = i == .myZero
        """, kotlin: """
        internal val i = x as Int
        internal val b = i == Int.myZero
        """)

        try await check(symbols: symbols, swift: """
        let b = x is Int
        print(b == .myTrue)
        """, kotlin: """
        internal val b = x is Int
        print(b == Boolean.myTrue)
        """)
    }

    func testNilCoalescing() async throws {
        try await check(symbols: symbols, swift: """
        func f(i: Int?) -> Bool {
            let r = i ?? 0
            return r == .myZero
        }
        """, kotlin: """
        internal fun f(i: Int?): Boolean {
            val r = i ?: 0
            return r == Int.myZero
        }
        """)
    }
}

private extension Bool {
    static var myTrue: Bool {
        return true
    }
}

private extension Int {
    static var myZero: Int {
        return 0
    }
}

private extension Double {
    static var myZero: Double {
        return 0.0
    }
}
