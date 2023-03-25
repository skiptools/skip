@testable import SkipSyntax
import XCTest

final class CodebaseInfoTests: XCTestCase {
    var context: CodebaseInfo.Context!

    override func setUp() async throws {
        let srcFile = try tmpFile(named: "Source.swift", contents: swift)
        let source = Source(file: Source.FilePath(path: srcFile.path), content: swift)
        let syntaxTree = SyntaxTree(source: source)

        let codebaseInfo = CodebaseInfo(moduleName: "Test")
        codebaseInfo.gather(from: syntaxTree)
        codebaseInfo.prepareForUse()
        context = codebaseInfo.context(importedModuleNames: [], sourceFile: source.file)
    }

    func testIdentifierType() async throws {
        XCTAssertEqual(.string, context.identifierSignature(of: "codebaseInfoTestsVar"))
        XCTAssertEqual(.array(.int), context.identifierSignature(of: "codebaseInfoTestsArrayVar"))
        XCTAssertEqual(.dictionary(.string, .int), context.identifierSignature(of: "codebaseInfoTestsDictionaryVar"))
        XCTAssertEqual(.dictionary(.string, .dictionary(.string, .int)), context.identifierSignature(of: "codebaseInfoTestsDictionaryOfDictionariesVar"))
        //~~~ Generated constructor
//        XCTAssertEqual(.named("CodebaseInfoTestsClass", []), context.identifierSignature(of: "codebaseInfoTestsNamedVar"))
    }

    func testMemberType() async throws {
        //~~~ Fallback symbols
//        XCTAssertEqual(.int, context.identifierSignature(of: "count", in: .array(.int)))

        XCTAssertEqual(.int, context.identifierSignature(of: "letVar", in: .named("CodebaseInfoTestsStruct", [])))
        XCTAssertEqual(.int, context.identifierSignature(of: "computedVar", in: .named("CodebaseInfoTestsStruct", [])))

        XCTAssertEqual(.function([.init(label: "p", type: .string)], .int), context.identifierSignature(of: "f", in: .named("CodebaseInfoTestsStruct", [])))

        XCTAssertEqual(.string, context.identifierSignature(of: "1", in: .tuple(["i", "s"], [.int, .string])))
        XCTAssertEqual(.string, context.identifierSignature(of: "s", in: .tuple(["i", "s"], [.int, .string])))
    }

    func testMemberNestedType() async throws {
        XCTAssertEqual(.int, context.identifierSignature(of: "n", in: .named("CodebaseInfoTestsClass.NestedClass", [])))
        XCTAssertEqual(.int, context.identifierSignature(of: "n", in: .member(.named("CodebaseInfoTestsClass", []), .named("NestedClass", []))))
    }

    func testSubscript() async throws {
        XCTAssertEqual([.function([.init(type: .int)], .int)], context.subscriptSignature(in: .array(.int), arguments: [LabeledValue<TypeSignature>(label: nil, value: .int)]))
        XCTAssertEqual([.function([.init(type: .string)], .int)], context.subscriptSignature(in: .dictionary(.string, .int), arguments: [LabeledValue<TypeSignature>(label: nil, value: .int)]))
    }

    func testFunction() async throws {
        XCTAssertEqual([.function([], .void)], context.functionSignature(of: "voidF", in: .named("CodebaseInfoTestsClass", []), arguments: []))

        XCTAssertEqual([.function([.init(type: .int), .init(label: "p2", type: .string, hasDefaultValue: true)], .int)], context.functionSignature(of: "baseF", in: .named("CodebaseInfoTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: "p2", value: .none)]))
        XCTAssertEqual([.function([.init(type: .int)], .int)], context.functionSignature(of: "baseF", in: .named("CodebaseInfoTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none)]))
    }

    func testTrailingClosures() async throws {
        XCTAssertEqual([.function([.init(label: "p1", type: .int), .init(label: "tc1", type: .function([.init(type: .string)], .int))], .string)], context.functionSignature(of: "trailingClosureF1", in: .named("CodebaseInfoTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: "p1", value: .none), LabeledValue<TypeSignature>(label: "tc1", value: .none)]))

        let f2Type: TypeSignature = .function([.init(label: "p1", type: .string, hasDefaultValue: true), .init(label: "tc1", type: .function([.init(type: .string), .init(type: .string)], .int), hasDefaultValue: true), .init(label: "tc2", type: .function([], .void), hasDefaultValue: true)], .void)
        XCTAssertEqual([f2Type], context.functionSignature(of: "trailingClosureF2", in: .named("CodebaseInfoTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: "p1", value: .none), LabeledValue<TypeSignature>(label: "tc1", value: .none), LabeledValue<TypeSignature>(label: "tc2", value: .none)]))
        XCTAssertEqual([f2Type], context.functionSignature(of: "trailingClosureF2", in: .named("CodebaseInfoTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: "p1", value: .none), LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: "tc2", value: .none)]))
        XCTAssertEqual([.function([], .void)], context.functionSignature(of: "trailingClosureF2", in: .named("CodebaseInfoTestsClass", []), arguments: []))

        let f3Type: TypeSignature = .function([.init(type: .optional(.dictionary(.int, .string)), hasDefaultValue: true), .init(label: "tc1", type: .function([], .array(.int)))], .function([.init(type: .named("CodebaseInfoTestsEnum", []))], .int))
        XCTAssertEqual([f3Type], context.functionSignature(of: "trailingClosureF3", in: .named("CodebaseInfoTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: "tc1", value: .none)]))
        XCTAssertEqual([f3Type], context.functionSignature(of: "trailingClosureF3", in: .named("CodebaseInfoTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: nil, value: .none)]))
        XCTAssertEqual([.function([.init(label: "tc1", type: .function([], .array(.int)))], .function([.init(type: .named("CodebaseInfoTestsEnum", []))], .int))], context.functionSignature(of: "trailingClosureF3", in: .named("CodebaseInfoTestsClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .function([], .none))]))
    }

    func testConstructor() async throws {
        //~~~ Generated constructor
//        XCTAssertEqual([.function([.init(label: "v", type: .int, hasDefaultValue: true)], .named("CodebaseInfoTestsStruct", []))], context.functionSignature(of: "CodebaseInfoTestsStruct", arguments: [LabeledValue<TypeSignature>(label: "v", value: .none)]))
    }

    func testEnums() async throws {
        let enumSignature: TypeSignature = .named("CodebaseInfoTestsEnum", [])
        XCTAssertEqual(enumSignature, context.identifierSignature(of: "case1", in: .metaType(enumSignature)))
        XCTAssertEqual([], context.associatedValueSignatures(of: "case1", in: .metaType(enumSignature)))

        let enumAssociatedValueSignature: TypeSignature = .named("CodebaseInfoTestsAssociatedValueEnum", [])
        XCTAssertEqual(enumAssociatedValueSignature, context.identifierSignature(of: "case2", in: .metaType(enumAssociatedValueSignature)))
        XCTAssertEqual([], context.associatedValueSignatures(of: "case1", in: .metaType(enumAssociatedValueSignature)))
        XCTAssertEqual([.init(type: .int)], context.associatedValueSignatures(of: "case2", in: .metaType(enumAssociatedValueSignature)))
        XCTAssertEqual([.init(label: "d", type: .double), .init(label: "s", type: .string)], context.associatedValueSignatures(of: "case3", in: .metaType(enumAssociatedValueSignature)))

        XCTAssertEqual([.function([.init(type: .int)], enumAssociatedValueSignature)], context.functionSignature(of: "case2", in: .metaType(enumAssociatedValueSignature), arguments: [LabeledValue<TypeSignature>(value: .int)]))
        XCTAssertEqual([.function([.init(label: "d", type: .double), .init(label: "s", type: .string)], enumAssociatedValueSignature)], context.functionSignature(of: "case3", in: .metaType(enumAssociatedValueSignature), arguments: [LabeledValue<TypeSignature>(label: "d", value: .double), LabeledValue<TypeSignature>(label: "s", value: .string)]))
    }

    func testTuples() async throws {
        let tupleSignature: TypeSignature = .tuple([nil, nil], [.named("CodebaseInfoTestsEnum", []), .int])
        XCTAssertEqual([.function([], tupleSignature)], context.functionSignature(of: "tupleReturn", in: .named("CodebaseInfoTestsClass", []), arguments: []))
    }

    func testSuperclassConstructor() throws {
        throw XCTSkip("TODO: Test custom superclass constructors called on a subclass")
    }

    func testCustomSubscript() throws {
        throw XCTSkip("TODO: Test custom subscript operators")
    }

    func testNestedTypes() throws {
        throw XCTSkip("TODO: Test nested type symbols")
    }

    func testGenerics() throws {
        throw XCTSkip("TODO: Test generics symbols, including standard type declarations like Dictionary<String, Int>")
    }
}

private let swift = """
private var codebaseInfoTestsVar = "string"
private var codebaseInfoTestsArrayVar = [1]
private var codebaseInfoTestsDictionaryVar: [String: Int] = [:]
private var codebaseInfoTestsDictionaryOfDictionariesVar: [String: [String: Int]] = [:]
private var codebaseInfoTestsNamedVar = CodebaseInfoTestsClass()

class CodebaseInfoTestsBaseClass {
    func baseF(_ p1: Int, p2: String = "") -> Int {
        return 1
    }
}

class CodebaseInfoTestsClass: CodebaseInfoTestsBaseClass {
    func voidF() {
    }

    func trailingClosureF1(p1: Int, tc1: @escaping (String) -> Int) -> String {
        return ""
    }

    func trailingClosureF2(p1: String = "", tc1: (String, String) -> Int = { _, _ in 0 }, tc2: () -> Void = {}) {
    }

    func trailingClosureF3(_ p1: [Int: String]? = [1: "1"], tc1: () -> [Int]) -> (CodebaseInfoTestsEnum) -> Int {
        return { _ in 0 }
    }

    func tupleReturn() -> (CodebaseInfoTestsEnum, Int) {
        return (.case1, 0)
    }

    class NestedClass {
        var n = 1
    }
}

enum CodebaseInfoTestsEnum: Int {
    case case1
    case case2 = 100
}
enum CodebaseInfoTestsAssociatedValueEnum {
    case case1
    case case2(Int)
    case case3(d: Double, s: String)
}

struct CodebaseInfoTestsStruct {
    let letVar = 1
    var v = 1
    var computedVar: Int {
        return 1
    }
    func f(p: String) -> Int {
        return 1
    }
}
"""
