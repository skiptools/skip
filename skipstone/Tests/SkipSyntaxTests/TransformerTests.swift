@testable import SkipSyntax
import XCTest

final class TransformerTests: XCTestCase {
    func testTestTransformer() async throws {
        try await check(swift: """
        import XCTest

        class TestCase: XCTestCase {
            func testSomeTest() throws {
            }

            func testSomeOtherTest() throws {
            }

            static func testDoNotTestStatic() throws {
            }
        }
        """, kotlin: """
        import skip.unit.*

        internal open class TestCase: XCTestCase {
            @Test internal open fun testSomeTest() = Unit

            @Test internal open fun testSomeOtherTest() = Unit

            companion object {

                internal fun testDoNotTestStatic() = Unit
            }
        }
        """)
    }

    func testConcurrencyTransformerTaskValue() async throws {
        try await check(swift: """
        func f() async {
            let task: Task = Task {}
            let value = await task.value
        }
        """, kotlin: """
        internal suspend fun f() {
            val task: Task = Task {  }
            val value = task.value()
        }
        """)
    }
}
