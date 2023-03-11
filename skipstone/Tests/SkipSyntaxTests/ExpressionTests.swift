@testable import SkipSyntax
import XCTest

final class ExpressionTests: XCTestCase {
    func testSelf() async throws {
        try await check(swift: """
        class C {
            static func staticf() -> Int {
                return 10
            }
        
            func f() -> Int {
                return Self.staticf()
            }
        }
        """, kotlin: """
        internal open class C {
        
            internal open fun f(): Int {
                return Companion.staticf()
            }
        
            companion object {
                internal fun staticf(): Int {
                    return 10
                }
            }
        }
        """)

        try await check(swift: """
        class C {
            func instancef() -> Int {
                return 10
            }

            func f() -> Int {
                return self.instancef()
            }
        }
        """, kotlin: """
        internal open class C {
            internal open fun instancef(): Int {
                return 10
            }

            internal open fun f(): Int {
                return this.instancef()
            }
        }
        """)
    }

    func testWildcardVariable() async throws {
        try await check(swift: """
        func f() -> Int {
            let _ = f()
        }
        """, kotlin: """
        internal fun f(): Int {
            f()
        }
        """)
    }
}
