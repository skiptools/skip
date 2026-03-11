// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

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

        @org.junit.runner.RunWith(androidx.test.ext.junit.runners.AndroidJUnit4::class)
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

        @org.junit.runner.RunWith(androidx.test.ext.junit.runners.AndroidJUnit4::class)
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

    // MARK: - Swift Testing Transformer Tests

    func testSwiftTestingBasic() async throws {
        try await check(swift: """
        import Testing

        struct MyTests {
            @Test func addition() {
                #expect(1 + 1 == 2)
            }
        }
        """, kotlin: """
        import skip.unit.*

        @org.junit.runner.RunWith(androidx.test.ext.junit.runners.AndroidJUnit4::class)
        internal class MyTests: XCTestCase {
            @Test
            internal fun addition(): Unit = expectEqual(1 + 1, 2)
        }
        """)
    }

    func testSwiftTestingExpectTrue() async throws {
        try await check(swift: """
        import Testing

        struct MyTests {
            @Test func boolCheck() {
                let x = true
                #expect(x)
            }
        }
        """, kotlin: """
        import skip.unit.*

        @org.junit.runner.RunWith(androidx.test.ext.junit.runners.AndroidJUnit4::class)
        internal class MyTests: XCTestCase {
            @Test
            internal fun boolCheck() {
                val x = true
                expectTrue(x)
            }
        }
        """)
    }

    func testSwiftTestingExpectNotEqual() async throws {
        try await check(swift: """
        import Testing

        struct MyTests {
            @Test func inequality() {
                #expect(1 != 2)
            }
        }
        """, kotlin: """
        import skip.unit.*

        @org.junit.runner.RunWith(androidx.test.ext.junit.runners.AndroidJUnit4::class)
        internal class MyTests: XCTestCase {
            @Test
            internal fun inequality(): Unit = expectNotEqual(1, 2)
        }
        """)
    }

    func testSwiftTestingRequire() async throws {
        try await check(swift: """
        import Testing

        struct MyTests {
            @Test func unwrap() throws {
                let x: Int? = 42
                let y = try #require(x)
            }
        }
        """, kotlin: """
        import skip.unit.*

        @org.junit.runner.RunWith(androidx.test.ext.junit.runners.AndroidJUnit4::class)
        internal class MyTests: XCTestCase {
            @Test
            internal fun unwrap() {
                val x: Int? = 42
                val y = requireNotNil(x)
            }
        }
        """)
    }

    func testSwiftTestingMultipleFunctions() async throws {
        try await check(swift: """
        import Testing

        struct MathTests {
            @Test func addition() {
                #expect(2 + 2 == 4)
            }

            @Test func subtraction() {
                #expect(5 - 3 == 2)
            }

            func helperNotATest() -> Int {
                return 42
            }
        }
        """, kotlin: """
        import skip.unit.*

        @org.junit.runner.RunWith(androidx.test.ext.junit.runners.AndroidJUnit4::class)
        internal class MathTests: XCTestCase {
            @Test
            internal fun addition(): Unit = expectEqual(2 + 2, 4)

            @Test
            internal fun subtraction(): Unit = expectEqual(5 - 3, 2)

            internal fun helperNotATest(): Int = 42
        }
        """)
    }

    func testSwiftTestingComparisons() async throws {
        try await check(swift: """
        import Testing

        struct CompTests {
            @Test func comparisons() {
                #expect(5 > 3)
                #expect(3 < 5)
                #expect(5 >= 5)
                #expect(3 <= 5)
            }
        }
        """, kotlin: """
        import skip.unit.*

        @org.junit.runner.RunWith(androidx.test.ext.junit.runners.AndroidJUnit4::class)
        internal class CompTests: XCTestCase {
            @Test
            internal fun comparisons() {
                expectGreaterThan(5, 3)
                expectLessThan(3, 5)
                expectGreaterThanOrEqual(5, 5)
                expectLessThanOrEqual(3, 5)
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
        """, kotlinPackageSupport: """
        internal val skip.foundation.Bundle.Companion.module: skip.foundation.Bundle
            get() = _moduleBundle
        private val _moduleBundle: skip.foundation.Bundle by lazy {
            skip.foundation.Bundle(_ModuleBundleLocator::class)
        }
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
        """, kotlinPackageSupport: """
        internal val skip.foundation.Bundle.Companion.module: skip.foundation.Bundle
            get() = _moduleBundle
        private val _moduleBundle: skip.foundation.Bundle by lazy {
            skip.foundation.Bundle(_ModuleBundleLocator::class)
        }
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
        """, kotlinPackageSupport: """
        """)
    }
}
