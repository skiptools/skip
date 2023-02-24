@testable import SkipSyntax
import XCTest

final class SymbolsTests: XCTestCase {
    func testIdentifierType() async throws {
        let context = try await symbols.context()
        XCTAssertEqual(.string, context.identifierSignature(of: "symbolsTestsVar"))
        XCTAssertEqual(.array(.int), context.identifierSignature(of: "symbolsTestsArrayVar"))
        XCTAssertEqual(.dictionary(.string, .int), context.identifierSignature(of: "symbolsTestsDictionaryVar"))
        XCTAssertEqual(.named("SymbolsTestsClass", []), context.identifierSignature(of: "symbolsTestsNamedVar"))
    }

    func testMemberType() async throws {
        let context = try await symbols.context()
        XCTAssertEqual(.int, context.identifierSignature(of: "count", in: .array(.int)))

        XCTAssertEqual(.int, context.identifierSignature(of: "letVar", in: .named("SymbolsTestsStruct", [])))
        XCTAssertEqual(.int, context.identifierSignature(of: "computedVar", in: .named("SymbolsTestsStruct", [])))

        XCTAssertEqual(.named("SymbolsTestsEnum", []), context.identifierSignature(of: "case1", in: .named("SymbolsTestsEnum", [])))

        XCTAssertEqual(.function([.init(label: "p", type: .string)], .int), context.identifierSignature(of: "f", in: .named("SymbolsTestsStruct", [])))

        XCTAssertEqual(.string, context.identifierSignature(of: "1", in: .tuple(["i", "s"], [.int, .string])))
        XCTAssertEqual(.string, context.identifierSignature(of: "s", in: .tuple(["i", "s"], [.int, .string])))
    }

    func testMemberNestedType() async throws {
        let context = try await symbols.context()
        XCTAssertEqual(.int, context.identifierSignature(of: "n", in: .named("SymbolsTestsClass.NestedClass", [])))
        XCTAssertEqual(.int, context.identifierSignature(of: "n", in: .member(.named("SymbolsTestsClass", []), .named("NestedClass", []))))
    }

    func testSubscript() async throws {
        let context = try await symbols.context()
        XCTAssertEqual([.function([.init(type: .int)], .int)], context.subscriptSignature(in: .array(.int), arguments: [LabeledValue<TypeSignature>(label: nil, value: .int)]))
        XCTAssertEqual([.function([.init(type: .string)], .int)], context.subscriptSignature(in: .dictionary(.string, .int), arguments: [LabeledValue<TypeSignature>(label: nil, value: .int)]))
    }

    func testFunction() async throws {
        let context = try await symbols.context()
        XCTAssertEqual([.function([], .void)], context.functionSignature(of: "voidF", in: .named("SymbolsTestsClass", []), arguments: []))

        XCTAssertEqual([.function([.init(type: .int), .init(label: "p2", type: .string, hasDefaultValue: true)], .int)], context.functionSignature(of: "baseF", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: "p2", value: .none)]))
        XCTAssertEqual([.function([.init(type: .int)], .int)], context.functionSignature(of: "baseF", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none)]))
    }

    func testTrailingClosures() async throws {
        let context = try await symbols.context()
        XCTAssertEqual([.function([.init(label: "p1", type: .int), .init(label: "tc1", type: .function([.init(type: .string)], .int))], .string)], context.functionSignature(of: "trailingClosureF1", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: "p1", value: .none), LabeledValue<TypeSignature>(label: "tc1", value: .none)]))

        let f2Type: TypeSignature = .function([.init(label: "p1", type: .string, hasDefaultValue: true), .init(label: "tc1", type: .function([.init(type: .string), .init(type: .string)], .int), hasDefaultValue: true), .init(label: "tc2", type: .function([], .void), hasDefaultValue: true)], .void)
        XCTAssertEqual([f2Type], context.functionSignature(of: "trailingClosureF2", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: "p1", value: .none), LabeledValue<TypeSignature>(label: "tc1", value: .none), LabeledValue<TypeSignature>(label: "tc2", value: .none)]))
        XCTAssertEqual([f2Type], context.functionSignature(of: "trailingClosureF2", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: "p1", value: .none), LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: "tc2", value: .none)]))
        XCTAssertEqual([.function([], .void)], context.functionSignature(of: "trailingClosureF2", in: .named("SymbolsTestsClass", []), arguments: []))

        let f3Type: TypeSignature = .function([.init(type: .optional(.dictionary(.int, .string)), hasDefaultValue: true), .init(label: "tc1", type: .function([], .array(.int)))], .function([.init(type: .named("SymbolsTestsEnum", []))], .int))
        XCTAssertEqual([f3Type], context.functionSignature(of: "trailingClosureF3", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: "tc1", value: .none)]))
        XCTAssertEqual([f3Type], context.functionSignature(of: "trailingClosureF3", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: nil, value: .none)]))
        XCTAssertEqual([.function([.init(label: "tc1", type: .function([], .array(.int)))], .function([.init(type: .named("SymbolsTestsEnum", []))], .int))], context.functionSignature(of: "trailingClosureF3", in: .named("SymbolsTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .function([], .none))]))
    }

    func testConstructor() async throws {
        let context = try await symbols.context()
        XCTAssertEqual([.function([.init(label: "v", type: .int, hasDefaultValue: true)], .named("SymbolsTestsStruct", []))], context.functionSignature(of: "SymbolsTestsStruct", arguments: [LabeledValue<TypeSignature>(label: "v", value: .none)]))
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

    class NestedClass {
        var n = 1
    }
}

enum SymbolsTestsEnum {
    case case1
    case case2
}

struct SymbolsTestsStruct {
    let letVar = 1
    var v = 1
    var computedVar: Int {
        return 1
    }
    func f(p: String) -> Int {
        return 1
    }
}
