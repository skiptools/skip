@testable import Skip
import SkipBuild
import SymbolKit
import XCTest

final class SymbolsTests: XCTestCase {
    func testHasMutableValueType() async throws {
        let context = try await symbols.context()
        XCTAssertNil(context.isMutableValueType(qualifiedName: "NonExistantTypeName"))

        XCTAssertEqual(false, context.isMutableValueType(qualifiedName: "SymbolsTestsClass"))
        XCTAssertEqual(false, context.isMutableValueType(qualifiedName: "SymbolsTestsEnum"))
        XCTAssertEqual(false, context.isMutableValueType(qualifiedName: "SymbolsTestsImmutableStruct"))

        XCTAssertEqual(true, context.isMutableValueType(qualifiedName: "SymbolsTestsMutableVarStruct"))
        XCTAssertEqual(true, context.isMutableValueType(qualifiedName: "SymbolsTestsMutableComputedVarStruct"))
        XCTAssertEqual(true, context.isMutableValueType(qualifiedName: "SymbolsTestsMutableFuncStruct"))

        XCTAssertEqual(true, context.isMutableValueType(qualifiedName: "SymbolsTestsNonAnyObjectRestrictedProtocol"))
        XCTAssertEqual(false, context.isMutableValueType(qualifiedName: "SymbolsTestsAnyObjectRestrictedProtocol"))
        XCTAssertEqual(false, context.isMutableValueType(qualifiedName: "SymbolsTestsTransitiveAnyObjectRestrictedProtocol"))
    }

    func testIdentifierType() async throws {
        let context = try await symbols.context()
        XCTAssertEqual(.string, context.type(of: "symbolsTestsVar"))
        XCTAssertEqual(.array(.int), context.type(of: "symbolsTestsArrayVar"))
        XCTAssertEqual(.dictionary(.string, .int), context.type(of: "symbolsTestsDictionaryVar"))
        XCTAssertEqual(.named("SymbolsTestsClass", []), context.type(of: "symbolsTestsNamedVar"))
    }

    func testMemberType() async throws {
        let context = try await symbols.context()
        XCTAssertEqual(.int, context.type(of: "count", in: .array(.int)))

        XCTAssertEqual(.int, context.type(of: "letVar", in: .named("SymbolsTestsImmutableStruct", [])))
        XCTAssertEqual(.int, context.type(of: "computedVar", in: .named("SymbolsTestsImmutableStruct", [])))

        XCTAssertEqual(.named("SymbolsTestsEnum", []), context.type(of: "case1", in: .named("SymbolsTestsEnum", [])))

        XCTAssertEqual(.function([.string], .int), context.type(of: "f", in: .named("SymbolsTestsImmutableStruct", [])))

        XCTAssertEqual(.string, context.type(of: "1", in: .tuple(["i", "s"], [.int, .string])))
        XCTAssertEqual(.string, context.type(of: "s", in: .tuple(["i", "s"], [.int, .string])))
    }

    func testSubscript() async throws {
        let context = try await symbols.context()
        XCTAssertEqual([.function([.int], .int)], context.subscriptSignature(in: .array(.int), arguments: [LabeledValue<TypeSignature>(label: nil, value: .int)]))
        XCTAssertEqual([.function([.string], .int)], context.subscriptSignature(in: .dictionary(.string, .int), arguments: [LabeledValue<TypeSignature>(label: nil, value: .int)]))
    }

    func testFunction() async throws {
        let context = try await symbols.context()
        XCTAssertEqual([.function([], .void)], context.functionSignature(of: "voidF", in: .named("SymbolsTestsClass", []), arguments: []))

        XCTAssertEqual([.function([.int, .string], .int)], context.functionSignature(of: "baseF", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: "p2", value: .none)]))
        XCTAssertEqual([.function([.int], .int)], context.functionSignature(of: "baseF", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none)]))
    }

    func testTrailingClosures() async throws {
        let context = try await symbols.context()
        XCTAssertEqual([.function([.int, .function([.string], .int)], .string)], context.functionSignature(of: "trailingClosureF1", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: "p1", value: .none), LabeledValue<TypeSignature>(label: "tc1", value: .none)]))

        let f2Type: TypeSignature = .function([.string, .function([.string, .string], .int), .function([], .void)], .void)
        XCTAssertEqual([f2Type], context.functionSignature(of: "trailingClosureF2", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: "p1", value: .none), LabeledValue<TypeSignature>(label: "tc1", value: .none), LabeledValue<TypeSignature>(label: "tc2", value: .none)]))
        XCTAssertEqual([f2Type], context.functionSignature(of: "trailingClosureF2", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: "p1", value: .none), LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: "tc2", value: .none)]))
        XCTAssertEqual([.function([], .void)], context.functionSignature(of: "trailingClosureF2", in: .named("SymbolsTestsClass", []), arguments: []))

        let f3Type: TypeSignature = .function([.optional(.dictionary(.int, .string)), .function([], .array(.int))], .function([.named("SymbolsTestsEnum", [])], .int))
        XCTAssertEqual([f3Type], context.functionSignature(of: "trailingClosureF3", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: "tc1", value: .none)]))
        XCTAssertEqual([f3Type], context.functionSignature(of: "trailingClosureF3", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: nil, value: .none)]))
        XCTAssertEqual([.function([.function([], .array(.int))], .function([.named("SymbolsTestsEnum", [])], .int))], context.functionSignature(of: "trailingClosureF3", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .function([], .none))]))
    }

    func testConstructor() async throws {
        let context = try await symbols.context()
        XCTAssertEqual([.function([.int], .named("SymbolsTestsMutableVarStruct", []))], context.functionSignature(of: "SymbolsTestsMutableVarStruct", arguments: [LabeledValue<TypeSignature>(label: "v", value: .none)]))
    }

    func testSuperclassConstructor() {
        XCTExpectFailure()
        XCTFail("TODO: Test custom superclass constructors called on a subclass")
    }

    func testCustomSubscript() {
        XCTExpectFailure()
        XCTFail("TODO: Test custom subscript operators")
    }

    func testTuples() {
        XCTExpectFailure()
        XCTFail("TODO: Test tuple symbols, including tuples as parameter and return types")
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
    func voidF() {
    }

    func trailingClosureF1(p1: Int, tc1: @escaping (String) -> Int) -> String {
        return ""
    }

    func trailingClosureF2(p1: String = "\\\",[(Int)]", tc1: (String, String) -> Int = { _, _ in 0 }, tc2: () -> Void = {}) {
    }

    func trailingClosureF3(_ p1: [Int: String]? = [1: "1"], tc1: () -> [Int]) -> (SymbolsTestsEnum) -> Int {
        return { _ in 0 }
    }
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
