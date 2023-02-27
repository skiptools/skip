@testable import SkipSyntax
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
        var i: Int?
        while let i, i < 5 {
            doSomething()
        }
        """, kotlin: """
        internal var i: Int? = null
        while ((i != null) && (i < 5)) {
            doSomething()
        }
        """)

        try await check(swift: """
        var i: Int?
        while let i = i, i < 5 {
            doSomething()
        }
        """, kotlin: """
        internal var i: Int? = null
        while ((i != null) && (i < 5)) {
            doSomething()
        }
        """)
    }
}
