// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

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

    func testForLoopRange() async throws {
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
        for (i in 0..10) {
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
        for (i in 0..<10) {
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
        for (i in Int.min..<10) {
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
        for (i in 10..Int.max) {
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

    func testGenericCastBehavior() async throws  {
        let a: Any = [1, 2, 3]
        XCTAssertTrue(a is [Int])
        XCTAssertTrue(a is [Any])

        struct S<T> {
        }
        let s: Any = S<Int>()
        XCTAssertTrue(s is S<Int>)
        XCTAssertFalse(s is S<Any>) // OK... but why does the Array case above pass?
    }

    func testGenericCast() async throws {
        try await check(expectMessages: true, swift: """
        func f(o: Any) -> Bool {
            return o is [Int]
        }
        """, kotlin: """
        import skip.lib.Array

        internal fun f(o: Any): Boolean = o is Array<*>
        """)

        try await check(expectMessages: true, swift: """
        func f(o: Any) -> Bool {
            return o is Array<Int>
        }
        """, kotlin: """
        import skip.lib.Array

        internal fun f(o: Any): Boolean = o is Array<*>
        """)

        try await check(expectMessages: true, swift: """
        func f<T>(o: [T]) -> Bool {
            return o is Array<Int>
        }
        """, kotlin: """
        import skip.lib.Array

        internal fun <T> f(o: Array<T>): Boolean = o is Array<*>
        """)

        try await check(expectMessages: true, swift: """
        func f<T>(o: [T]) -> Bool {
            return o is Collection<T>
        }
        """, kotlin: """
        import skip.lib.Array
        import skip.lib.Collection

        internal fun <T> f(o: Array<T>): Boolean = o is Collection<*>
        """)

        try await check(expectMessages: true, swift: """
        struct S<T> {}
        func f(o: Any) -> Bool {
            return o is S<Int>
        }
        """, kotlin: """
        internal class S<T> {
        }
        internal fun f(o: Any): Boolean = o is S<*>
        """)

        try await check(swift: """
        func f(o: Any) -> [Int] {
            return o as! [Int]
        }
        """, kotlin: """
        import skip.lib.Array

        internal fun f(o: Any): Array<Int> = (o as Array<Int>).sref()
        """)

        try await check(expectMessages: true, swift: """
        func f(o: Any) -> [Int]? {
            return o as? [Int]
        }
        """, kotlin: """
        import skip.lib.Array

        internal fun f(o: Any): Array<Int>? = (o as? Array<Int>).sref()
        """)
    }

    func testCastAddsMissingGenerics() async throws {
        try await check(supportingSwift: """
        protocol P {
            associatedtype ID
            var id: ID { get }
        }
        """, swift: """
        func f(p: Any) {
            let id = (p as? P).id
        }
        """, kotlin: """
        internal fun f(p: Any) {
            val id = (p as? P<*>).id.sref()
        }
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
        { ->
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
        import skip.lib.Array

        { ->
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
        import skip.lib.Array

        { ->
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
        { ->
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
        import skip.lib.Array

        { ->
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
        import skip.lib.Array

        { ->
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

    func testSlice() async throws {
        // Note that without symbols we don't understand slice types
        try await check(supportingSwift: """
        """, swift: """
        func slice() {
            let a = [0, 1, 2, 3, 4]
            let s1 = a[1...3]
            let s2 = a[1..<3]
            let s3 = a[1...]
            let s4 = a[...3]
            let s5 = a[..<3]
        }
        """, kotlin: """
        import skip.lib.Array
        
        internal fun slice() {
            val a = arrayOf(0, 1, 2, 3, 4)
            val s1 = a[1..3]
            val s2 = a[1..<3]
            val s3 = a[1..Int.max]
            val s4 = a[Int.min..3]
            val s5 = a[Int.min..<3]
        }
        """)
    }

    func testBitwiseOperators() async throws {
        try await check(swift: """
        func f(i: Int) -> Int {
            var r = i
            r = r | 100
            r = r & 100
            r = ~r
            r = r << 1
            r = r >> 2
            return r
        }
        """, kotlin: """
        internal fun f(i: Int): Int {
            var r = i
            r = r or 100
            r = r and 100
            r = r.inv()
            r = r shl 1
            r = r shr 2
            return r
        }
        """)

        try await checkProducesMessage(swift: """
        func f(i: Int) -> Int {
            var r = i
            r |= 100
            return r
        }
        """)
    }

    func testReified() async throws {
        try await check(swift: """
        @inline(__always) func nameOf<T>(_ value: T) -> String {
            if T.self == String.self {
                return "String"
            } else if T.self == Int.self {
                return "Int"
            } else {
                return "Other"
            }
        }
        """, kotlin: """
        internal inline fun <reified T> nameOf(value: T): String {
            if (T::class == String::class) {
                return "String"
            } else if (T::class == Int::class) {
                return "Int"
            } else {
                return "Other"
            }
        }
        """)
    }
}
