@testable import SkipSyntax
import XCTest

final class DoCatchTests: XCTestCase {
    func testDoWithoutCatch() async throws {
        try await check(swift: """
        do {
            action1()
            action2()
        }
        """, kotlin: """
        run {
            action1()
            action2()
        }
        """)

        try await check(swift: """
        do {
            action1()
            defer { finalAction() }
            action2()
        }
        """, kotlin: """
        var deferaction_0: (() -> Unit)? = null
        try {
            action1()
            deferaction_0 = {
                finalAction()
            }
            action2()
        } finally {
            deferaction_0?.invoke()
        }
        """)
    }

    func testCatchAll() async throws {
        try await check(expectFailure: true, symbols: symbols, swift: """
        do {
            action1()
            action2()
            throw DoCatchTestsErrorStruct()
        } catch {
            print("Caught error: \\(error)")
        }
        """, kotlin: """
        try {
            action1()
            action2()
            throw DoCatchTestsErrorStruct()
        } catch (error: Throwable) {
            print("Caught error: $error")
        }
        """)
    }

    func testCatchWithDefer() async throws {
        try await check(expectFailure: true, symbols: symbols, swift: """
        do {
            action1()
            defer { finalAction() }
            action2()
        } catch {
            print("Caught error: \\(error)")
        }
        """, kotlin: """
        var deferaction_0: (() -> Unit)? = null
        try {
            action1()
            deferaction_0 = {
                finalAction()
            }
            action2()
            throw DoCatchTestsErrorStruct()
        } catch (error: Throwable) {
            print("Caught error: $error")
        } finally {
            deferaction_0?.invoke()
        }
        """)
    }

    func testMutatingFunctionCombinesTryCatch() async throws {

    }

    private func action1() {
    }
    private func action2() {
    }
    private func finalAction() {
    }
}

private struct DoCatchTestsErrorStruct: Error {
    var message = ""
}
