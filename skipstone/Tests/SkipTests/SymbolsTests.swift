@testable import Skip
import SkipBuild
import SymbolKit
import XCTest

final class SymbolsTests: XCTestCase {
    let symbolCache = SymbolCache()
    var symbols: Symbols!

    override func setUp() async throws {
        let collector = GraphCollector(extensionGraphAssociationStrategy: .extendingGraph)
        for entry in try await symbolCache.symbols(for: "SkipKotlin", accessLevel: "public") {
            collector.mergeSymbolGraph(entry.value, at: entry.key)
        }
        for entry in try await symbolCache.symbols(for: "SkipTests", accessLevel: "private") {
            collector.mergeSymbolGraph(entry.value, at: entry.key)
        }
        let (unifiedGraphs, _) = collector.finishLoading()
        symbols = Symbols(moduleName: "SkipTests", graphs: unifiedGraphs)
    }

    func testHasMutableValueType() {
        XCTAssertNil(symbols.containsMutableValueType(name: "NonExistantTypeName"))

        XCTAssertEqual(false, symbols.containsMutableValueType(name: "SymbolsTestsClass"))
        XCTAssertEqual(false, symbols.containsMutableValueType(name: "SymbolsTestsEnum"))
        XCTAssertEqual(false, symbols.containsMutableValueType(name: "SymbolsTestsImmutableStruct"))

        XCTAssertEqual(true, symbols.containsMutableValueType(name: "SymbolsTestsMutableVarStruct"))
        XCTAssertEqual(true, symbols.containsMutableValueType(name: "SymbolsTestsMutableComputedVarStruct"))
        XCTAssertEqual(true, symbols.containsMutableValueType(name: "SymbolsTestsMutableFuncStruct"))

        XCTAssertEqual(true, symbols.containsMutableValueType(name: "SymbolsTestsNonAnyObjectRestrictedProtocol"))
        XCTAssertEqual(false, symbols.containsMutableValueType(name: "SymbolsTestsAnyObjectRestrictedProtocol"))
        XCTAssertEqual(false, symbols.containsMutableValueType(name: "SymbolsTestsTransitiveAnyObjectRestrictedProtocol"))
    }

    func testIdentifierType() {
        let context = symbols.context()
        XCTAssertEqual(.string, context.type(of: "symbolsTestsVar"))
        XCTAssertEqual(.array(.int), context.type(of: "symbolsTestsArrayVar"))
        XCTAssertEqual(.dictionary(.string, .int), context.type(of: "symbolsTestsDictionaryVar"))
        XCTAssertEqual(.named("SymbolsTestsClass", []), context.type(of: "symbolsTestsNamedVar"))
    }

    func testMemberType() {
        let context = symbols.context()
        XCTAssertEqual(.int, context.type(of: "count", in: .array(.int)))

        XCTAssertEqual(.int, context.type(of: "letVar", in: .named("SymbolsTestsImmutableStruct", [])))
        XCTAssertEqual(.int, context.type(of: "computedVar", in: .named("SymbolsTestsImmutableStruct", [])))

        XCTAssertEqual(.named("SymbolsTestsEnum", []), context.type(of: "case1", in: .named("SymbolsTestsEnum", [])))

        XCTAssertEqual(.function([.string], .int), context.type(of: "f", in: .named("SymbolsTestsImmutableStruct", [])))

        XCTAssertEqual(.string, context.type(of: "1", in: .tuple(["i", "s"], [.int, .string])))
        XCTAssertEqual(.string, context.type(of: "s", in: .tuple(["i", "s"], [.int, .string])))
    }

    func testSubscript() {
        let context = symbols.context()
        XCTAssertEqual([.function([.int], .int)], context.subscriptSignature(in: .array(.int), arguments: [LabeledValue<TypeSignature>(label: nil, value: .int)]))
        XCTAssertEqual([.function([.string], .int)], context.subscriptSignature(in: .dictionary(.string, .int), arguments: [LabeledValue<TypeSignature>(label: nil, value: .int)]))
    }

    func testFunction() {
        let context = symbols.context()
        XCTAssertEqual([.function([.int, .string], .int)], context.functionSignature(of: "baseF", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: "p2", value: .none)]))
        XCTAssertEqual([.function([.int], .int)], context.functionSignature(of: "baseF", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none)]))
    }

    func testTrailingClosures() {
        XCTExpectFailure()
        XCTFail("TODO: Test functions with trailing closures")
    }

    func testCustomSubscript() {
        XCTExpectFailure()
        XCTFail("TODO: Test custom subscript operators")
    }

    func testNestedTypes() {
        XCTExpectFailure()
        XCTFail("TODO: Test nested type symbols")
    }

    func testGenerics() {
        XCTExpectFailure()
        XCTFail("TODO: Test generics symbols, including standard type declarations like Dictionary<String, Int>")
    }
}

private var symbolsTestsVar = "string"
private var symbolsTestsArrayVar = [1]
private var symbolsTestsDictionaryVar: [String: Int] = [:]
private var symbolsTestsNamedVar = SymbolsTestsClass()

class SymbolsTestsBaseClass {
    func baseF(_ p1: Int, p2: String = "") -> Int {
        return 1
    }
}

class SymbolsTestsClass: SymbolsTestsBaseClass {
}

enum SymbolsTestsEnum {
    case case1
    case case2
}

struct SymbolsTestsImmutableStruct {
    let letVar = 1
    var computedVar: Int {
        return 1
    }
    func f(p: String) -> Int {
        return 1
    }
}

struct SymbolsTestsMutableVarStruct {
    var v = 1
}

struct SymbolsTestsMutableComputedVarStruct {
    var computedVar: Int {
        get {
            return 1
        }
        set {
        }
    }
}

struct SymbolsTestsMutableFuncStruct {
    mutating func f() -> Int {
        return 1
    }
}

protocol SymbolsTestsNonAnyObjectRestrictedProtocol: Codable {}
protocol SymbolsTestsAnyObjectRestrictedProtocol: AnyObject {}
protocol SymbolsTestsTransitiveAnyObjectRestrictedProtocol: SymbolsTestsAnyObjectRestrictedProtocol {}
