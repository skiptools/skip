@testable import Skip
import SkipBuild
import SymbolKit
import XCTest

final class SymbolsTests: XCTestCase {
    let symbolCache = SymbolCache()
    var symbols: Symbols!

    override func setUp() async throws {
        let collector = GraphCollector(extensionGraphAssociationStrategy: .extendingGraph)
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

    func testNestedTypes() {
        XCTExpectFailure()
        XCTFail("TODO: Test nested type symbols")
    }

    func testGenerics() {
        XCTExpectFailure()
        XCTFail("TODO: Test generics symbols")
    }
}

class SymbolsTestsClass {
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
    func f() -> Int {
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
