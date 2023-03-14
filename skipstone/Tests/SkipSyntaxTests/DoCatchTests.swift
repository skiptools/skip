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
        try await check(symbols: symbols, swift: """
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

    func testCatchIs() async throws {
        try await check(symbols: symbols, swift: """
        do {
            action1()
            action2()
        } catch is DoCatchTestsErrorStruct {
            print("Caught error: \\(error)")
        } catch {
        }
        """, kotlin: """
        try {
            action1()
            action2()
        } catch (error: DoCatchTestsErrorStruct) {
            print("Caught error: $error")
        } catch (error: Throwable) {
        }
        """)
    }

    func testCatchLetAs() async throws {
        try await check(symbols: symbols, swift: """
        do {
            action1()
            action2()
        } catch let e as DoCatchTestsErrorStruct {
            print("Caught error: \\(e)")
        } catch {
        }
        """, kotlin: """
        try {
            action1()
            action2()
        } catch (e: DoCatchTestsErrorStruct) {
            print("Caught error: $e")
        } catch (error: Throwable) {
        }
        """)

        try await check(symbols: symbols, swift: """
        do {
            action1()
            action2()
        } catch let error as DoCatchTestsErrorStruct {
            print("Caught error: \\(error)")
        }
        """, kotlin: """
        try {
            action1()
            action2()
        } catch (error: DoCatchTestsErrorStruct) {
            print("Caught error: $error")
        }
        """)

        try await check(symbols: symbols, swift: """
        do {
            action1()
            action2()
        } catch var error as DoCatchTestsErrorStruct {
            print("Caught error: \\(error)")
        }
        """, kotlin: """
        try {
            action1()
            action2()
        } catch (error: DoCatchTestsErrorStruct) {
            var error = error
            print("Caught error: $error")
        }
        """)
    }

    func testEnum() async throws {
        try await check(symbols: symbols, swift: """
        do {
            action1()
            action2()
        } catch DoCatchTestsErrorEnum.case1 {
            print("case1")
        } catch DoCatchTestsErrorEnum.case2 {
            print("case2")
        }
        """, kotlin: """
        try {
            action1()
            action2()
        } catch (error: DoCatchTestsErrorEnum.case1) {
            print("case1")
        } catch (error: DoCatchTestsErrorEnum.case2) {
            print("case2")
        }
        """)
    }

    func testAssociatedValueEnum() async throws {
        try await check(symbols: symbols, swift: """
        do {
            action1()
            action2()
        } catch DoCatchTestsErrorAssociatedValueEnum.case1(let code) {
            print("Caught error: \\(code)")
        } catch DoCatchTestsErrorAssociatedValueEnum.case2(_, var message) {
            print("Caught error: \\(message)")
        }
        """, kotlin: """
        try {
            action1()
            action2()
        } catch (error: DoCatchTestsErrorAssociatedValueEnum.case1) {
            val code = error.associated0
            print("Caught error: $code")
        } catch (error: DoCatchTestsErrorAssociatedValueEnum.case2) {
            var message = error.associated1
            print("Caught error: $message")
        }
        """)
    }

    func testMultipleMatches() async throws {
        try await check(symbols: symbols, swift: """
        do {
            action1()
            action2()
        } catch is DoCatchTestsErrorStruct, DoCatchTestsErrorAssociatedValueEnum.case1 {
            print("Caught error")
        } catch let DoCatchTestsErrorAssociatedValueEnum.case2(code, message) {
            print("Caught error: \\(code): \\(message)")
        }
        """, kotlin: """
        try {
            action1()
            action2()
        } catch (error: DoCatchTestsErrorStruct) {
            print("Caught error")
        } catch (error: DoCatchTestsErrorAssociatedValueEnum.case1) {
            print("Caught error")
        } catch (error: DoCatchTestsErrorAssociatedValueEnum.case2) {
            val code = error.associated0
            val message = error.associated1
            print("Caught error: $code: $message")
        }
        """)
    }

    func testCatchWithDefer() async throws {
        try await check(symbols: symbols, swift: """
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
        } catch (error: Throwable) {
            print("Caught error: $error")
        } finally {
            deferaction_0?.invoke()
        }
        """)
    }

    func testMutatingFunctionCombinesTryCatch() async throws {
        try await check(symbols: symbols, swift: """
        struct S {
            var i = 0
            mutating func inc() {
                do {
                    i += 1
                } catch {
                    print("Caught error \\(error)")
                }
            }
            mutating func decinc() {
                i -= 1
                do {
                    i += 1
                } catch {
                    print("Caught error \\(error)")
                }
            }
        }
        """, kotlin: """
        internal class S: MutableStruct {
            internal var i = 0
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }
            internal fun inc() {
                willmutate()
                try {
                    i += 1
                } catch (error: Throwable) {
                    print("Caught error $error")
                } finally {
                    didmutate()
                }
            }
            internal fun decinc() {
                willmutate()
                try {
                    i -= 1
                    try {
                        i += 1
                    } catch (error: Throwable) {
                        print("Caught error $error")
                    }
                } finally {
                    didmutate()
                }
            }

            constructor(i: Int = 0) {
                this.i = i
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct {
                return S(i)
            }
        }
        """)
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
private enum DoCatchTestsErrorEnum: Error {
    case case1
    case case2
}
private enum DoCatchTestsErrorAssociatedValueEnum: Error {
    case case1(Int)
    case case2(Int, String)
}
