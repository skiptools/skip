@testable import SkipSyntax
import XCTest

final class OperatorTests: XCTestCase {
    func testMath() async throws {
        let supportingSwift = """
        extension Int {
            static var myZero: Int {
                return 0
            }
        }
        extension Double {
            static var myZero: Double {
                return 0.0
            }
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        func op(a: Int, b: Int) -> Bool {
            return a + b * 2 == .myZero
        }
        """, kotlin: """
        internal fun op(a: Int, b: Int): Boolean = a + b * 2 == Int.myZero
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        func op(a: Double, b: Double) -> Bool {
            return a * b + 2 == .myZero
        }
        """, kotlin: """
        internal fun op(a: Double, b: Double): Boolean = a * b + 2 == Double.myZero
        """)
    }

    func testRange() async throws {
        let supportingSwift = """
        extension Int {
            static var myZero: Int {
                return 0
            }
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
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

        try await check(supportingSwift: supportingSwift, swift: """
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

        try await check(supportingSwift: supportingSwift, swift: """
        for i in ..<10 {
            let b = i == .myZero
            print(b)
        }
        """, kotlin: """
        for (i in Int.min until 10) {
            val b = i == Int.myZero
            print(b)
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        for i in 10... {
            let b = i == .myZero
            print(b)
        }
        """, kotlin: """
        for (i in 10 .. Int.max) {
            val b = i == Int.myZero
            print(b)
        }
        """)
    }

    func testCast() async throws {
        let supportingSwift = """
        extension Int {
            static var myZero: Int {
                return 0
            }
        }
        extension Bool {
            static var myTrue: Bool {
                return true
            }
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        let i = x as? Int
        let b = i == .myZero
        """, kotlin: """
        internal val i = x as? Int
        internal val b = i == Int.myZero
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        let i = x as! Int
        let b = i == .myZero
        """, kotlin: """
        internal val i = x as Int
        internal val b = i == Int.myZero
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        let b = x is Int
        print(b == .myTrue)
        """, kotlin: """
        internal val b = x is Int
        print(b == Boolean.myTrue)
        """)
    }

    func testNilCoalescing() async throws {
        try await check(supportingSwift: """
        extension Int {
            static var myZero: Int {
                return 0
            }
        }
        """, swift: """
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

    func testForceUnwrap() async throws {
        let supportingSwift = """
        extension Int {
            static var myZero: Int {
                return 0
            }
        }
        class OperatorTestsOptionalHost {
            var i = 0
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        {
            let host: OperatorTestsOptionalHost? = nil
            let i = host!.i + 1
            let b = host!.i == .myZero
        }
        """, kotlin: """
        {
            val host: OperatorTestsOptionalHost? = null
            val i = host!!.i + 1
            val b = host!!.i == Int.myZero
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        {
            let a: [Int]? = nil
            let b = a![0] == .myZero
        }
        """, kotlin: """
        {
            val a: Array<Int>? = null
            val b = a!![0] == Int.myZero
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        {
            let a: [OperatorTestsOptionalHost?] = []
            let b = a[0]!.i == .myZero
        }
        """, kotlin: """
        {
            val a: Array<OperatorTestsOptionalHost?> = arrayOf()
            val b = a[0]!!.i == Int.myZero
        }
        """)
    }

    func testForceOptionalChaining() async throws {
        let supportingSwift = """
        extension Int {
            static var myZero: Int {
                return 0
            }
        }
        class OperatorTestsOptionalHost {
            var i = 0
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        {
            let host: OperatorTestsOptionalHost? = nil
            let b = host?.i == .myZero
        }
        """, kotlin: """
        {
            val host: OperatorTestsOptionalHost? = null
            val b = host?.i == Int.myZero
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        {
            let a: [Int]? = nil
            let b = a?[0] == .myZero
        }
        """, kotlin: """
        {
            val a: Array<Int>? = null
            val b = a?.get(0) == Int.myZero
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        {
            let a: [OperatorTestsOptionalHost?] = []
            let b = a[0]?.i == .myZero
        }
        """, kotlin: """
        {
            val a: Array<OperatorTestsOptionalHost?> = arrayOf()
            val b = a[0]?.i == Int.myZero
        }
        """)
    }

    func testTernary() async throws {
        try await check(supportingSwift: """
        extension Int {
            static var myZero: Int {
                return 0
            }
        }
        """, swift: """
        func f(i: Int) -> Boolean {
            let even = i % 2 == 0 ? i : i + 1
            return even == .myZero
        }
        """, kotlin: """
        internal fun f(i: Int): Boolean {
            val even = if (i % 2 == 0) i else i + 1
            return even == Int.myZero
        }
        """)

        try await check(swift: """
        func isEven(i: Int) -> Boolean {
            return i % 2 == 0 ? true : false
        }
        """, kotlin: """
        internal fun isEven(i: Int): Boolean = if (i % 2 == 0) true else false
        """)
    }
}
