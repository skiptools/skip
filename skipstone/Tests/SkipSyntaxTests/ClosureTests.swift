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
        call llabel@{ _ ->
            return@llabel 1
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
            val x = linvoke(1) llabel@{
                if (it % 2 == 0) {
                    return@llabel "YES"
                } else {
                    return@llabel "NO"
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

    func testUseInvokeForOptionalClosure() async throws {
        try await check(swift: """
        {
            let c: ((String) -> Int)? = nil
            let i = c?("s")
        }
        """, kotlin: """
        {
            val c: ((String) -> Int)? = null
            val i = c?.invoke("s")
        }
        """)
    }

    func testPassFunctionForClosure() async throws {
        try await check(swift: """
        class C {
            func visitor(i: Int) {
            }

            func visit(with: (Int) -> Void) {
            }

            func f() {
                visit(with: self.visitor)
            }

            func g() {
                visit(with: visitor)
            }
        }
        """, kotlin: """
        internal open class C {
            internal open fun visitor(i: Int) {
            }

            internal open fun visit(with: (Int) -> Unit) {
            }
        
            internal open fun f() {
                visit(with = this::visitor)
            }

            internal open fun g() {
                visit(with = ::visitor)
            }
        }
        """)
    }
}
