@testable import SkipSyntax
import XCTest

final class ClosureTests: XCTestCase {
    func testNoParameters() async throws {
        try await check(swift: """
        call {
            print("f")
        }
        """, kotlin: """
        call {
            print("f")
        }
        """)

        try await check(swift: """
        call(100) {
            print("f")
        }
        """, kotlin: """
        call(100) {
            print("f")
        }
        """)

        try await check(swift: """
        call(100, { print("f") })
        """, kotlin: """
        call(100) {
            print("f")
        }
        """)
    }

    func testExplicitSingleParameter() async throws {
        try await check(swift: """
        call { x in
            print(x)
        }
        """, kotlin: """
        call { x ->
            print(x.sref())
        }
        """)

        try await check(swift: """
        call { (x: Int) in
            print(x)
        }
        """, kotlin: """
        call { x: Int ->
            print(x)
        }
        """)
    }

    func testExplicitMultipleParameters() async throws {
        try await check(swift: """
        call { x, y in
            print(x)
        }
        """, kotlin: """
        call { x, y ->
            print(x.sref())
        }
        """)

        try await check(swift: """
        call { (x: Int, y: String) in
            print(x)
        }
        """, kotlin: """
        call { x: Int, y: String ->
            print(x)
        }
        """)
    }

    func testExplicitReturnType() async throws {
        // Without explicit return
        try await check(swift: """
        call { (x: Int, y: String) -> Int in
            1
        }
        """, kotlin: """
        call(fun(x: Int, y: String): Int {
            return 1
        })
        """)

        // With explicit return
        try await check(swift: """
        call { (x: Int, y: String) -> Int in
            return 1
        }
        """, kotlin: """
        call(fun(x: Int, y: String): Int {
            return 1
        })
        """)
    }

    func testReturnLabel() async throws {
        try await check(swift: """
        call { _ in
            return 1
        }
        """, kotlin: """
        call r_0@{ _ ->
            return@r_0 1
        }
        """)
    }

    func testImmediatelyExecuted() async throws {
        try await check(swift: """
        {
            let x = { 1 }()
        }
        """, kotlin: """
        {
            val x = {
                1
            }()
        }
        """)

        try await check(swift: """
        {
            let x = { (i: Int) in i }(1)
        }
        """, kotlin: """
        {
            val x = { i: Int ->
                i
            }(1)
        }
        """)

        try await check(swift: """
        {
            let x = {
                if $0 % 2 == 0 {
                    return "YES"
                } else {
                    return "NO"
                }
            }(1)
        }
        """, kotlin: """
        {
            val x = r_0(1) r_0@{
                if (it % 2 == 0) {
                    return@r_0 "YES"
                } else {
                    return@r_0 "NO"
                }
            }
        }
        """)
    }

    func testImplicitSingleParameter() async throws {
        try await check(swift: """
        call { $0 + 1 }
        """, kotlin: """
        call {
            it + 1
        }
        """)
    }

    func testImplicitMultipleParameters() async throws {
        try await check(swift: """
        call { $0 + $1 + $2 }
        """, kotlin: """
        call { it, it_1, it_2 ->
            it + it_1 + it_2
        }
        """)
    }
}
