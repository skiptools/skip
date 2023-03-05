@testable import SkipSyntax
import XCTest

final class ExpressionTests: XCTestCase {
    func testTypeSelf() async throws {
        try await check(swift: """
        class C {
            static func sf() -> Int {
                return 10
            }
        
            func f() -> Int {
                return Self.sf()
            }
        }
        """, kotlin: """
        internal open class C {
        
            internal open fun f(): Int {
                return Companion.sf()
            }
        
            companion object {
                internal fun sf(): Int {
                    return 10
                }
            }
        }
        """)
    }
}
