@testable import SkipSyntax
import XCTest

final class TypeInferenceTests: XCTestCase {
    func testEnumCase() async throws {
        let supportingSwift = """
        enum E {
            case case1
            case case2
        }
        // Ensure we're not just guessing when we see e.g. .case1
        enum DuplicateE {
            case case1
            case case2
        }

        func eParamFunc(_ value: E) {
        }

        func eReturnFunc() -> E {
            return .case1
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        let e: E = .case1
        """, kotlin: """
        internal val e: E = E.case1
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        eParamFunc(.case2)
        """, kotlin: """
        eParamFunc(E.case2)
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        eReturnFunc() == .case2
        """, kotlin: """
        eReturnFunc() == E.case2
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        func enumReturn() -> E {
            return .case1
        }
        """, kotlin: """
        internal fun enumReturn(): E {
            return E.case1
        }
        """)
    }

    func testStaticMemberOfSameType() async throws {
        let supportingSwift = """
        class C {
            static let instance = C()

            func classReturnMemberFunc() -> C {
                return .instance
            }
        }

        // Ensure we're not just guessing when we see e.g. .instance
        class DuplicateC {
            static let instance = DuplicateC()
        }

        func cParamFunc(_ value: C) {
        }
        """
        
        try await check(supportingSwift: supportingSwift, swift: """
        let i: C = .instance
        """, kotlin: """
        internal val i: C = C.instance
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        cParamFunc(.instance)
        """, kotlin: """
        cParamFunc(C.instance)
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        func classReturn() -> C {
            return .instance
        }
        """, kotlin: """
        internal fun classReturn(): C {
            return C.instance
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        class C2 {
            func classReturnMemberFunc() -> C {
                return .instance
            }
            func f() -> Bool {
                return classReturnMemberFunc() == .instance
            }
        }
        """, kotlin: """
        internal open class C2 {
            internal open fun classReturnMemberFunc(): C {
                return C.instance
            }
            internal open fun f(): Boolean {
                return classReturnMemberFunc() == C.instance
            }
        }
        """)
    }

    func testLocalParameterType() async throws {
        try await check(supportingSwift: """
        class C {
            static let instance = C()
        }
        """, swift: """
        func f(cls: C) -> Bool {
            let c = cls
            return c == .instance
        }
        """, kotlin: """
        internal fun f(cls: C): Boolean {
            val c = cls
            return c == C.instance
        }
        """)
    }

    func testDictionaries() async throws {
        try await check(supportingSwift: """
        class DictionaryHolder {
            var dictionaryOfDictionaries: [String: [String: Int]] = [:]
        }
        """, swift: """
        {
            let holder = DictionaryHolder()
            holder.dictionaryOfDictionaries["a"] = ["a": 1, "b": 2, "c": 3]
            let b = holder.dictionaryOfDictionaries["a"]!["b"] == .myZero
        }
        """, kotlin: """
        {
            val holder = DictionaryHolder()
            holder.dictionaryOfDictionaries["a"] = dictionaryOf(Pair("a", 1), Pair("b", 2), Pair("c", 3))
            val b = holder.dictionaryOfDictionaries["a"]!!["b"] == Int.myZero
        }
        """)
    }

    func testInit() async throws {
        try await check(supportingSwift: """
        class C {
            var v = 1
            init(v: Int = 1) {
                self.v = v
            }
        }
        func cParamFunc(_ value: C) {
        }
        """, swift: """
        {
            let c: C = .init(v: 100)
            cParamFunc(.init(v: 101))
        }
        """, kotlin: """
        {
            val c: C = C(v = 100)
            cParamFunc(C(v = 101))
        }
        """)
    }

    func testStaticVsInstanceContext() async throws {
        try await check(supportingSwift: """
        enum E {
            case case1
            case case2
        }
        enum DuplicateE {
            case case1
            case case2
        }
        """, swift: """
        class C {
            static func returnEnum() -> E {
                return .case1
            }
            func returnEnum() -> DuplicateE {
                return .case1
            }

            static func staticContext() -> Bool {
                return returnEnum() == .case1
            }
            func instanceContext() -> Bool {
                return returnEnum() == .case1
            }
        }
        """, kotlin: """
        internal open class C {
            internal open fun returnEnum(): DuplicateE {
                return DuplicateE.case1
            }
            internal open fun instanceContext(): Boolean {
                return returnEnum() == DuplicateE.case1
            }

            companion object {
                internal fun returnEnum(): E {
                    return E.case1
                }

                internal fun staticContext(): Boolean {
                    return returnEnum() == E.case1
                }
            }
        }
        """)
    }

    func testStaticMember() async throws {
        try await check(supportingSwift: """
        enum E {
            case case1
            case case2
        }
        enum DuplicateE {
            case case1
            case case2
        }
        class C {
            static func returnEnum() -> E {
                return .case1
            }
            func returnEnum() -> DuplicateE {
                return .case1
            }
        }
        """, swift: """
        {
            let b = C.returnEnum() == .case1
        }
        """, kotlin: """
        {
            val b = C.returnEnum() == E.case1
        }
        """)
    }

    func testGenerics() throws {
        throw XCTSkip("Test all aspects of using generic paramters")
    }

    func testGenericsUpperBounds() throws {
        throw XCTSkip("Test that we use the upper bounds on generics")
    }

    func testGenericsWhereEqualExtension() throws {
        throw XCTSkip("Test that we incorporate generics where clauses on extensions")
    }

    func testTypealias() throws {
        throw XCTSkip("TODO: Test that we can match typealiases to types")
    }

    func testTypeDeclaredWithinFunction() throws {
        throw XCTSkip("TODO: Test declaring a type within a function. This includes making sure our plugins process in-function types correctly")
    }

    func testNestedTypes() throws {
        throw XCTSkip("TODO: Test nested type symbols")
    }

    func testScoredMatching() throws {
        throw XCTSkip("TODO: We should score parameter matches for functions. Exact matches, inheritance matches for named types, fall back to looking for matching symbols when we don't know the type and using TypeSignature.isCompatible to match")
    }
}
