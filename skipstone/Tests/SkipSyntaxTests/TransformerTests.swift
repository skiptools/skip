import XCTest

final class TransformerTests: XCTestCase {
    func testUnitTestTransformer() async throws {
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
            @Test
            internal open fun testSomeTest() = Unit

            @Test
            internal open fun testSomeOtherTest() = Unit

            companion object {

                internal fun testDoNotTestStatic() = Unit
            }
        }
        """)
    }

    func testAsyncUnitTestTransformer() async throws {
        try await check(swift: """
        import XCTest

        class TestCase: XCTestCase {
            func testAsync() async throws {
                XCTAssertTrue(someCheck())
            }
        }
        """, kotlin: """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.test.*

        import skip.unit.*

        internal open class TestCase: XCTestCase {

            @OptIn(ExperimentalCoroutinesApi::class)
            @Test
            internal fun runtestAsync() {
                val dispatcher = StandardTestDispatcher()
                Dispatchers.setMain(dispatcher)
                try {
                    runTest { withContext(Dispatchers.Main) { testAsync() } }
                } finally {
                    Dispatchers.resetMain()
                }
            }
            internal open suspend fun testAsync(): Unit = Async.run {
                XCTAssertTrue(someCheck())
            }
        }
        """)
    }

    func testModuleBundleTransformer() async throws {
        try await check(swift: """
        import Foundation
        func f() {
            let path = Bundle.module.path()
        }
        """, kotlin: """
        import skip.foundation.*
        internal fun f() {
            val path = Bundle.module.path()
        }
        """, packageSupportKotlin: """
        internal val skip.foundation.Bundle.Companion.module: skip.foundation.Bundle
            get() = skip.foundation.Bundle(_ModuleBundleLocator::class)
        internal class _ModuleBundleLocator {}
        """)

        try await check(swift: """
        import Foundation
        func f() {
            let path = Foundation.Bundle.module.path()
        }
        """, kotlin: """
        import skip.foundation.*
        internal fun f() {
            val path = Foundation.Bundle.module.path()
        }
        """, packageSupportKotlin: """
        internal val skip.foundation.Bundle.Companion.module: skip.foundation.Bundle
            get() = skip.foundation.Bundle(_ModuleBundleLocator::class)
        internal class _ModuleBundleLocator {}
        """)

        try await check(swift: """
        import Foundation
        func f() {
            let path = Local.Bundle.module.path()
        }
        """, kotlin: """
        import skip.foundation.*
        internal fun f() {
            val path = Local.Bundle.module.path()
        }
        """, packageSupportKotlin: """
        """)
    }
}
