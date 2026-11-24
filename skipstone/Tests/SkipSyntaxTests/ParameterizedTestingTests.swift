import XCTest
@testable import SkipSyntax

final class ParameterizedTestingTests: XCTestCase {
    func testArgumentCollectionsUseParameterRunner() async throws {
        try await check(swift: """
        import Testing
        struct NumberTests {
            static let values = [1, 2, 3]
            @Test(arguments: Self.values)
            func positive(value: Int) {
                #expect(value > 0)
            }
        }
        """, kotlin: "", fixup: { output in
            XCTAssertTrue(output.contains("SkipParameterizedTestRunner::class"))
            XCTAssertTrue(output.contains("SkipTestArgumentsProvider"))
            XCTAssertTrue(output.contains("NumberTests.__skipArguments_positive"))
            XCTAssertTrue(output.contains("arguments[0] as Int"))
            XCTAssertTrue(output.contains("Array<Int>(Companion.values)"), output)
            return ""
        })
    }

    func testTupleAndCartesianArguments() async throws {
        try await check(swift: """
        import Testing
        struct TupleTests {
            @Test(arguments: [(1, "a"), (2, "b")])
            func pair(number: Int, text: String) {}
            @Test(arguments: 1...3, [true, false])
            func product(number: Int, flag: Bool) {}
        }
        """, kotlin: "", fixup: { output in
            XCTAssertTrue(output.contains("arguments[1] as String"))
            XCTAssertTrue(output.contains("arguments[1] as Boolean"))
            XCTAssertTrue(output.contains("for (first in firstArguments"), output)
            XCTAssertTrue(output.contains("for (second in secondArguments"), output)
            return ""
        })
    }

    func testFreestandingAsyncArguments() async throws {
        try await check(swift: """
        import Testing
        @Test(arguments: [1, 2])
        func asynchronous(value: Int) async throws {
            #expect(value > 0)
        }
        """, kotlin: "", fixup: { output in
            XCTAssertTrue(output.contains("class AsynchronousTests"))
            XCTAssertTrue(output.contains("runTest { withContext(Dispatchers.Main)"))
            XCTAssertTrue(output.contains("arguments[0] as Int"))
            return ""
        })
    }

    func testUnsupportedArgumentArityProducesDiagnostic() async throws {
        try await checkProducesMessage(swift: """
        import Testing
        struct Invalid {
            @Test(arguments: [1], [2])
            func invalid(value: Int) {}
        }
        """)
    }
}
