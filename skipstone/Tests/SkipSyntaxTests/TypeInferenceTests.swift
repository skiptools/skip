@testable import SkipSyntax
import XCTest

final class TypeInferenceTests: XCTestCase {
    func testEnumCase() async throws {
        try await check(symbols: symbols, swift: """
        let e: TypeInferenceTestsEnum = .case1
        """, kotlin: """
        internal val e: TypeInferenceTestsEnum = TypeInferenceTestsEnum.case1
        """)

        try await check(symbols: symbols, swift: """
        typeInferenceTestsEnumParamFunc(.case2)
        """, kotlin: """
        typeInferenceTestsEnumParamFunc(TypeInferenceTestsEnum.case2)
        """)

        try await check(symbols: symbols, swift: """
        typeInferenceTestsEnumReturnFunc() == .case2
        """, kotlin: """
        typeInferenceTestsEnumReturnFunc() == TypeInferenceTestsEnum.case2
        """)

        try await check(symbols: symbols, swift: """
        func enumReturn() -> TypeInferenceTestsEnum {
            return .case1
        }
        """, kotlin: """
        internal fun enumReturn(): TypeInferenceTestsEnum {
            return TypeInferenceTestsEnum.case1
        }
        """)
    }

    func testStaticMemberOfSameType() async throws {
        try await check(symbols: symbols, swift: """
        let i: TypeInferenceTestsClass = .instance
        """, kotlin: """
        internal val i: TypeInferenceTestsClass = TypeInferenceTestsClass.instance
        """)

        try await check(symbols: symbols, swift: """
        typeInferenceTestsClassParamFunc(.instance)
        """, kotlin: """
        typeInferenceTestsClassParamFunc(TypeInferenceTestsClass.instance)
        """)

        try await check(symbols: symbols, swift: """
        func classReturn() -> TypeInferenceTestsClass {
            return .instance
        }
        """, kotlin: """
        internal fun classReturn(): TypeInferenceTestsClass {
            return TypeInferenceTestsClass.instance
        }
        """)

        // Our type inference relies on symbols, so we can't introduce new classes
        // within the test code itself. Use extensions instead
        try await check(symbols: symbols, swift: """
        extension TypeInferenceTestsClass2 {
            func f() -> Bool {
                return classReturnMemberFunc() == .instance
            }
        }
        """, kotlin: """
        internal fun TypeInferenceTestsClass2.f(): Boolean {
            return classReturnMemberFunc() == TypeInferenceTestsClass.instance
        }
        """)
    }

    func testBuiltinTypeExtension() async throws {
        try await check(symbols: symbols, swift: """
        func isCountZero() -> Bool {
            let count = typeInferenceTestsArrayReturnFunc().count
            return count == .myZero
        }
        """, kotlin: """
        internal fun isCountZero(): Boolean {
            val count = typeInferenceTestsArrayReturnFunc().count
            return count == Int.myZero
        }
        """)
    }

    func testLocalParameterType() async throws {
        try await check(symbols: symbols, swift: """
        func f(cls: TypeInferenceTestsClass) -> Bool {
            let c = cls
            return c == .instance
        }
        """, kotlin: """
        internal fun f(cls: TypeInferenceTestsClass): Boolean {
            val c = cls
            return c == TypeInferenceTestsClass.instance
        }
        """)
    }

    func testDictionaries() async throws {
        try await check(symbols: symbols, swift: """
        {
            let holder = DictionaryHolder()
            holder.dictionaryOfDictionaries["a"] = ["a": 1, "b": 2, "c": 3]
            let b = holder.dictionaryOfDictionaries.count == .myZero
            let b2 = holder.dictionaryOfDictionaries["a"]!["b"] == .myZero
        }
        """, kotlin: """
        {
            val holder = DictionaryHolder()
            holder.dictionaryOfDictionaries["a"] = dictionaryOf(Pair("a", 1), Pair("b", 2), Pair("c", 3))
            val b = holder.dictionaryOfDictionaries.count == Int.myZero
            val b2 = holder.dictionaryOfDictionaries["a"]!!["b"] == Int.myZero
        }
        """)
    }

    func testInit() async throws {
        XCTExpectFailure()
        XCTFail("TODO: Test using .init to call constructors")
    }

    func testNestedTypes() {
        XCTExpectFailure()
        XCTFail("TODO: Test nested type symbols")
    }

    func testBestGuessMatching() {
        XCTExpectFailure()
        XCTFail("TODO: We should fall back to looking for matching symbols when we don't know the type and using TypeSignature.isCompatible to match")
    }

    func testStaticVsInstanceContext() {
        XCTExpectFailure()
        XCTFail("TODO: Test member references in static vs instance contexts. Test duplicate static and instance members")
    }
}

enum TypeInferenceTestsEnum {
    case case1
    case case2
}
// Ensure we're not just guessing when we see e.g. .case1
enum TypeInferenceTestsDuplicateEnum {
    case case1
    case case2
}

func typeInferenceTestsEnumParamFunc(_ value: TypeInferenceTestsEnum) {
}

func typeInferenceTestsEnumReturnFunc() -> TypeInferenceTestsEnum {
    return .case1
}

class TypeInferenceTestsClass {
    static let instance = TypeInferenceTestsClass()

    var v = 1

    init(v: Int = 1) {
        self.v = v
    }

    func classReturnMemberFunc() -> TypeInferenceTestsClass {
        return .instance
    }
}
// Ensure we're not just guessing when we see e.g. .instance
class TypeInferenceTestsDuplicateClass {
    static let instance = TypeInferenceTestsDuplicateClass()
}

class TypeInferenceTestsClass2 {
    func classReturnMemberFunc() -> TypeInferenceTestsClass {
        return .instance
    }
}

func typeInferenceTestsClassParamFunc(_ value: TypeInferenceTestsClass) {
}

func typeInferenceTestsArrayReturnFunc() -> [String] {
    return []
}

private extension Int {
    static var myZero: Int {
        return 0
    }
}

private class DictionaryHolder {
    var dictionary: [String: Int] = [:] {
        didSet {
            dictionarySetCount += 1
        }
    }
    var dictionarySetCount = 0

    var dictionaryOfDictionaries: [String: [String: Int]] = [:] {
        didSet {
            dictionarySetCount += 1
        }
    }
}
