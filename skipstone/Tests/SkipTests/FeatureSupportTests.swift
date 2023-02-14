@testable import Skip
import XCTest

/// A test case that verifies that transpilation are *not* working as hoped.
final class FeatureSupportTests: XCTestCase {
    func testDefaultArgs() async throws {
        // double equals sign in function: doSomething(a: String = = "abc")
        try await check(expectFailure: true, swift: """
        struct Foo {
            public func doSomething(a: String = "abc") -> String {
                return a
            }
        }
        """, kotlin: """
        internal data class Foo {
            public fun doSomething(a: String = "abc"
        ): String {
                return a
            }

            companion object {
            }
        }
        """)
    }

    func testNilToNull() async throws {
        // "nil" should be translated to null
        try await check(expectFailure: false, swift: """
        struct Foo {
            public func doSomething() -> String? {
                nil
            }
        }
        """, kotlin: """
        internal data class Foo {
            public fun doSomething(): String? {
                null
            }

            companion object {
            }
        }
        """)
    }

    func testReturnNil() async throws {
        // "return nil" should be translated to "return null"
        try await check(expectFailure: false, swift: """
        struct Foo {
            public func doSomething() -> String? {
                return nil
            }
        }
        """, kotlin: """
        internal data class Foo {
            public fun doSomething(): String? {
                return null
            }

            companion object {
            }
        }
        """)
    }

    func testEnums() async throws {
        // enums should be converted to classes
        try await check(expectFailure: true, swift: """
        enum Foo { case cat, dog, robot }
        """, kotlin: """
        enum class Foo { cat, dog, robot }
        """)
    }

    func testClosures() async throws {
        // closure $0 should be converted to `it`
        try await check(expectFailure: true, swift: """
        [1,2,3].map({ $0 })
        """, kotlin: """
        arrayOf(1, 2, 3).map({ it })
        """)
    }

    func testTupleToPairConversion() async throws {
        // tuples should turn into pairs
        try await check(expectFailure: true, swift: """
        [(1, 0),(2, 0),(3, 1)].map({ $0 + $1 })
        """, kotlin: """
        listOf(Pair(1, 0), Pair(2, 0), Pair(3, 1)).map { it.first + it.second }
        """)
    }

    func testMultipleClosureArguments() async throws {
        // tuples should turn into pairs
        try await check(expectFailure: true, swift: """
        ["a": 1, "b": 2.0].map({ $1 })
        """, kotlin: """
        mapOf("a" to 1, "b" to 2.0).map { (_0, _1) -> _1 }
        """)
    }
}
