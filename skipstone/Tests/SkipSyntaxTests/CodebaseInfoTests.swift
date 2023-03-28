@testable import SkipSyntax
import XCTest

final class CodebaseInfoTests: XCTestCase {
    private func setUpContext(swift: String) async throws -> CodebaseInfo.Context {
        let srcFile = try tmpFile(named: "Source.swift", contents: swift)
        let source = Source(file: Source.FilePath(path: srcFile.path), content: swift)
        let syntaxTree = SyntaxTree(source: source)

        let codebaseInfo = CodebaseInfo()
        codebaseInfo.gather(from: syntaxTree)
        codebaseInfo.prepareForUse()
        return codebaseInfo.context(importedModuleNames: [], sourceFile: source.file)
    }

    func testIdentifierType() async throws {
        let context = try await setUpContext(swift: """
        var stringVar = "string"
        var arrayVar = [1]
        var dictionaryVar: [String: Int] = [:]
        var dictionaryOfDictionariesVar: [String: [String: Int]] = [:]
        var namedVar = TestClass()
        var nestedVar = TestClass.Nested()
        class TestClass() {
            class Nested {
            }
        }
        """)

        XCTAssertEqual(.string, context.identifierSignature(of: "stringVar"))
        XCTAssertEqual(.array(.int), context.identifierSignature(of: "arrayVar"))
        XCTAssertEqual(.dictionary(.string, .int), context.identifierSignature(of: "dictionaryVar"))
        XCTAssertEqual(.dictionary(.string, .dictionary(.string, .int)), context.identifierSignature(of: "dictionaryOfDictionariesVar"))
        XCTAssertEqual(.named("TestClass", []), context.identifierSignature(of: "namedVar"))
        XCTAssertEqual(.member(.named("TestClass", []), .named("Nested", [])), context.identifierSignature(of: "nestedVar"))
        XCTAssertEqual(.metaType(.named("TestClass", [])), context.identifierSignature(of: "TestClass"))
        XCTAssertEqual(.metaType(.member(.named("TestClass", []), .named("Nested", []))), context.identifierSignature(of: "TestClass.Nested"))
    }

    func testMemberType() async throws {
        let context = try await setUpContext(swift: """
        struct TestStruct {
            let letVar = 1
            var v = 1
            var computedVar: Int {
                return 1
            }
            func f(p: String) -> Int {
                return 1
            }
        }
        """)

        XCTAssertEqual(.int, context.identifierSignature(of: "letVar", in: .named("TestStruct", [])))
        XCTAssertEqual(.int, context.identifierSignature(of: "computedVar", in: .named("TestStruct", [])))

        XCTAssertEqual(.function([.init(label: "p", type: .string)], .int), context.identifierSignature(of: "f", in: .named("TestStruct", [])))

        XCTAssertEqual(.string, context.identifierSignature(of: "1", in: .tuple(["i", "s"], [.int, .string])))
        XCTAssertEqual(.string, context.identifierSignature(of: "s", in: .tuple(["i", "s"], [.int, .string])))
    }

    func testMemberNestedType() async throws {
        let context = try await setUpContext(swift: """
        class TestClass {
            class Nested {
                var n = 1
            }
        }
        """)

        XCTAssertEqual(.int, context.identifierSignature(of: "n", in: .named("TestClass.Nested", [])))
        XCTAssertEqual(.int, context.identifierSignature(of: "n", in: .member(.named("TestClass", []), .named("Nested", []))))
    }

    func testSubscript() async throws {
        let context = try await setUpContext(swift: "")
        XCTAssertEqual([.function([.init(type: .int)], .int)], context.subscriptSignature(in: .array(.int), arguments: [LabeledValue<TypeSignature>(label: nil, value: .int)]))
        XCTAssertEqual([.function([.init(type: .string)], .int)], context.subscriptSignature(in: .dictionary(.string, .int), arguments: [LabeledValue<TypeSignature>(label: nil, value: .int)]))
    }

    func testFunction() async throws {
        let context = try await setUpContext(swift: """
        class TestBaseClass {
            func baseF(_ p1: Int, p2: String = "") -> Int {
                return 1
            }
        }
        class TestClass: TestBaseClass {
            func voidF() {
            }
        }
        """)

        XCTAssertEqual([.function([], .void)], context.functionSignature(of: "voidF", in: .named("TestClass", []), arguments: []))

        XCTAssertEqual([.function([.init(type: .int), .init(label: "p2", type: .string, hasDefaultValue: true)], .int)], context.functionSignature(of: "baseF", in: .named("TestClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: "p2", value: .none)]))
        XCTAssertEqual([.function([.init(type: .int)], .int)], context.functionSignature(of: "baseF", in: .named("TestClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none)]))
    }

    func testTrailingClosures() async throws {
        let context = try await setUpContext(swift: """
        class TestClass {
            func trailingClosureF1(p1: Int, tc1: @escaping (String) -> Int) -> String {
                return ""
            }

            func trailingClosureF2(p1: String = "", tc1: (String, String) -> Int = { _, _ in 0 }, tc2: () -> Void = {}) {
            }

            func trailingClosureF3(_ p1: [Int: String]? = [1: "1"], tc1: () -> [Int]) -> (TestEnum) -> Int {
                return { _ in 0 }
            }
        }
        enum TestEnum: Int {
            case case1
            case case2 = 100
        }
        """)

        XCTAssertEqual([.function([.init(label: "p1", type: .int), .init(label: "tc1", type: .function([.init(type: .string)], .int))], .string)], context.functionSignature(of: "trailingClosureF1", in: .named("TestClass", []), arguments: [LabeledValue<TypeSignature>(label: "p1", value: .none), LabeledValue<TypeSignature>(label: "tc1", value: .none)]))

        let f2Type: TypeSignature = .function([.init(label: "p1", type: .string, hasDefaultValue: true), .init(label: "tc1", type: .function([.init(type: .string), .init(type: .string)], .int), hasDefaultValue: true), .init(label: "tc2", type: .function([], .void), hasDefaultValue: true)], .void)
        XCTAssertEqual([f2Type], context.functionSignature(of: "trailingClosureF2", in: .named("TestClass", []), arguments: [LabeledValue<TypeSignature>(label: "p1", value: .none), LabeledValue<TypeSignature>(label: "tc1", value: .none), LabeledValue<TypeSignature>(label: "tc2", value: .none)]))
        XCTAssertEqual([f2Type], context.functionSignature(of: "trailingClosureF2", in: .named("TestClass", []), arguments: [LabeledValue<TypeSignature>(label: "p1", value: .none), LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: "tc2", value: .none)]))
        XCTAssertEqual([.function([], .void)], context.functionSignature(of: "trailingClosureF2", in: .named("TestClass", []), arguments: []))

        let f3Type: TypeSignature = .function([.init(type: .optional(.dictionary(.int, .string)), hasDefaultValue: true), .init(label: "tc1", type: .function([], .array(.int)))], .function([.init(type: .named("TestEnum", []))], .int))
        XCTAssertEqual([f3Type], context.functionSignature(of: "trailingClosureF3", in: .named("TestClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: "tc1", value: .none)]))
        XCTAssertEqual([f3Type], context.functionSignature(of: "trailingClosureF3", in: .named("TestClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: nil, value: .none)]))
        XCTAssertEqual([.function([.init(label: "tc1", type: .function([], .array(.int)))], .function([.init(type: .named("TestEnum", []))], .int))], context.functionSignature(of: "trailingClosureF3", in: .named("TestClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .function([], .none))]))
    }

    func testConstructor() async throws {
        let context = try await setUpContext(swift: """
        struct TestStruct {
            let letVar = 1
            var v = 1
            var o: Int?
            var computedVar: Int {
                return 1
            }
            func f(p: String) -> Int {
                return 1
            }
        }
        """)

        XCTAssertEqual([.function([.init(label: "v", type: .int, hasDefaultValue: true)], .named("TestStruct", []))], context.functionSignature(of: "TestStruct", arguments: [LabeledValue<TypeSignature>(label: "v", value: .none)]))
        XCTAssertEqual([.function([.init(label: "v", type: .int, hasDefaultValue: true), .init(label: "o", type: .optional(.int), hasDefaultValue: true)], .named("TestStruct", []))], context.functionSignature(of: "TestStruct", arguments: [LabeledValue<TypeSignature>(label: "v", value: .none), LabeledValue<TypeSignature>(label: "o", value: .none)]))
    }

    func testEnums() async throws {
        let context = try await setUpContext(swift: """
        enum TestEnum: Int {
            case case1
            case case2 = 100
        }
        enum AssociatedValueEnum {
            case case1
            case case2(Int)
            case case3(d: Double, s: String)
        }
        """)

        let enumSignature: TypeSignature = .named("TestEnum", [])
        XCTAssertEqual(enumSignature, context.identifierSignature(of: "case1", in: .metaType(enumSignature)))
        XCTAssertEqual([], context.associatedValueSignatures(of: "case1", in: .metaType(enumSignature)))

        let enumAssociatedValueSignature: TypeSignature = .named("AssociatedValueEnum", [])
        XCTAssertEqual(enumAssociatedValueSignature, context.identifierSignature(of: "case2", in: .metaType(enumAssociatedValueSignature)))
        XCTAssertEqual([], context.associatedValueSignatures(of: "case1", in: .metaType(enumAssociatedValueSignature)))
        XCTAssertEqual([.init(type: .int)], context.associatedValueSignatures(of: "case2", in: .metaType(enumAssociatedValueSignature)))
        XCTAssertEqual([.init(label: "d", type: .double), .init(label: "s", type: .string)], context.associatedValueSignatures(of: "case3", in: .metaType(enumAssociatedValueSignature)))

        XCTAssertEqual([.function([.init(type: .int)], enumAssociatedValueSignature)], context.functionSignature(of: "case2", in: .metaType(enumAssociatedValueSignature), arguments: [LabeledValue<TypeSignature>(value: .int)]))
        XCTAssertEqual([.function([.init(label: "d", type: .double), .init(label: "s", type: .string)], enumAssociatedValueSignature)], context.functionSignature(of: "case3", in: .metaType(enumAssociatedValueSignature), arguments: [LabeledValue<TypeSignature>(label: "d", value: .double), LabeledValue<TypeSignature>(label: "s", value: .string)]))
    }

    func testTuples() async throws {
        let context = try await setUpContext(swift: """
        class TestClass {
            func tupleReturn() -> (TestEnum, Int) {
                return (.case1, 0)
            }
        }
        enum TestEnum: Int {
            case case1
            case case2 = 100
        }
        """)

        let tupleSignature: TypeSignature = .tuple([nil, nil], [.named("TestEnum", []), .int])
        XCTAssertEqual([.function([], tupleSignature)], context.functionSignature(of: "tupleReturn", in: .named("TestClass", []), arguments: []))
    }

    func testInheritedConstructors() throws {
        throw XCTSkip("TODO: Test custom superclass constructors called on a subclass and general constructor inheritance")
    }

    func testCustomSubscript() throws {
        throw XCTSkip("TODO: Test custom subscript operators")
    }

    func testGenerics() throws {
        throw XCTSkip("TODO: Test generics symbols, including standard type declarations like Dictionary<String, Int>")
    }
}
