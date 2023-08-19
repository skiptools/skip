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

        XCTAssertEqual(.string, context.matchIdentifier(name: "stringVar")?.signature)
        XCTAssertEqual(.array(.int), context.matchIdentifier(name: "arrayVar")?.signature)
        XCTAssertEqual(.dictionary(.string, .int), context.matchIdentifier(name: "dictionaryVar")?.signature)
        XCTAssertEqual(.dictionary(.string, .dictionary(.string, .int)), context.matchIdentifier(name: "dictionaryOfDictionariesVar")?.signature)
        XCTAssertEqual(.named("TestClass", []), context.matchIdentifier(name: "namedVar")?.signature)
        XCTAssertEqual(.member(.named("TestClass", []), .named("Nested", [])), context.matchIdentifier(name: "nestedVar")?.signature)
        XCTAssertEqual(.metaType(.named("TestClass", [])), context.matchIdentifier(name: "TestClass")?.signature)
        XCTAssertEqual(.metaType(.member(.named("TestClass", []), .named("Nested", []))), context.matchIdentifier(name: "TestClass.Nested")?.signature)
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

        XCTAssertEqual(.int, context.matchIdentifier(name: "letVar", inConstrained: .named("TestStruct", []))?.signature)
        XCTAssertEqual(.int, context.matchIdentifier(name: "computedVar", inConstrained: .named("TestStruct", []))?.signature)

        XCTAssertEqual(.function([.init(label: "p", type: .string)], .int, [], nil), context.matchIdentifier(name: "f", inConstrained: .named("TestStruct", []))?.signature)

        XCTAssertEqual(.string, context.matchIdentifier(name: "1", inConstrained: .tuple(["i", "s"], [.int, .string]))?.signature)
        XCTAssertEqual(.string, context.matchIdentifier(name: "s", inConstrained: .tuple(["i", "s"], [.int, .string]))?.signature)
    }

    func testVariableTypeResolution() async throws {
        let context = try await setUpContext(swift: """
        struct TestStruct1 {
            static let v = TestStruct2.v2
            static let v2 = 100
        }
        struct TestStruct2 {
            static let v2 = TestStruct1.v2
        }
        """)

        XCTAssertEqual(.int, context.matchIdentifier(name: "v", inConstrained: .metaType(.named("TestStruct1", [])))?.signature)
        XCTAssertEqual(.int, context.matchIdentifier(name: "v2", inConstrained: .metaType(.named("TestStruct1", [])))?.signature)
        XCTAssertEqual(.int, context.matchIdentifier(name: "v2", inConstrained: .metaType(.named("TestStruct2", [])))?.signature)
    }

    func testFailedVariableTypeResolutionProducesMessage() async throws {
        try await checkProducesMessage(swift: """
        struct TestStruct {
            static let v = TestStruct2.v
        }
        """)
    }

    func testMemberNestedType() async throws {
        let context = try await setUpContext(swift: """
        class TestClass {
            class Nested {
                var n = 1
            }
        }
        """)

        XCTAssertEqual(.int, context.matchIdentifier(name: "n", inConstrained: .named("TestClass.Nested", []))?.signature)
        XCTAssertEqual(.int, context.matchIdentifier(name: "n", inConstrained: .member(.named("TestClass", []), .named("Nested", [])))?.signature)
    }

    func testSubscript() async throws {
        let context = try await setUpContext(swift: "")
        XCTAssertEqual([.function([.init(type: .int)], .int, [], nil)], context.matchSubscript(inConstrained: .array(.int), arguments: [LabeledValue<TypeSignature>(label: nil, value: .int)]).map(\.signature))
        XCTAssertEqual([.function([.init(type: .string)], .optional(.int), [], nil)], context.matchSubscript(inConstrained: .dictionary(.string, .int), arguments: [LabeledValue<TypeSignature>(label: nil, value: .string)]).map(\.signature))
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

        XCTAssertEqual([.function([], .void, [], nil)], context.matchFunction(name: "voidF", inConstrained: .named("TestClass", []), arguments: []).map(\.signature))

        XCTAssertEqual([.function([.init(type: .int), .init(label: "p2", type: .string, hasDefaultValue: true)], .int, [], nil)], context.matchFunction(name: "baseF", inConstrained: .named("TestClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: "p2", value: .none)]).map(\.signature))
        XCTAssertEqual([.function([.init(type: .int)], .int, [], nil)], context.matchFunction(name: "baseF", inConstrained: .named("TestClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none)]).map(\.signature))
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

        XCTAssertEqual([.function([.init(label: "p1", type: .int), .init(label: "tc1", type: .function([.init(type: .string)], .int, [], nil))], .string, [], nil)], context.matchFunction(name: "trailingClosureF1", inConstrained: .named("TestClass", []), arguments: [LabeledValue<TypeSignature>(label: "p1", value: .none), LabeledValue<TypeSignature>(label: "tc1", value: .none)]).map(\.signature))

        let f2Type: TypeSignature = .function([.init(label: "p1", type: .string, hasDefaultValue: true), .init(label: "tc1", type: .function([.init(type: .string), .init(type: .string)], .int, [], nil), hasDefaultValue: true), .init(label: "tc2", type: .function([], .void, [], nil), hasDefaultValue: true)], .void, [], nil)
        XCTAssertEqual([f2Type], context.matchFunction(name: "trailingClosureF2", inConstrained: .named("TestClass", []), arguments: [LabeledValue<TypeSignature>(label: "p1", value: .none), LabeledValue<TypeSignature>(label: "tc1", value: .none), LabeledValue<TypeSignature>(label: "tc2", value: .none)]).map(\.signature))
        XCTAssertEqual([f2Type], context.matchFunction(name: "trailingClosureF2", inConstrained: .named("TestClass", []), arguments: [LabeledValue<TypeSignature>(label: "p1", value: .none), LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: "tc2", value: .none)]).map(\.signature))
        XCTAssertEqual([.function([], .void, [], nil)], context.matchFunction(name: "trailingClosureF2", inConstrained: .named("TestClass", []), arguments: []).map(\.signature))

        let f3Type: TypeSignature = .function([.init(type: .optional(.dictionary(.int, .string)), hasDefaultValue: true), .init(label: "tc1", type: .function([], .array(.int), [], nil))], .function([.init(type: .named("TestEnum", []))], .int, [], nil), [], nil)
        XCTAssertEqual([f3Type], context.matchFunction(name: "trailingClosureF3", inConstrained: .named("TestClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: "tc1", value: .none)]).map(\.signature))
        XCTAssertEqual([f3Type], context.matchFunction(name: "trailingClosureF3", inConstrained: .named("TestClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .none), LabeledValue<TypeSignature>(label: nil, value: .none)]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "tc1", type: .function([], .array(.int), [], nil))], .function([.init(type: .named("TestEnum", []))], .int, [], nil), [], nil)], context.matchFunction(name: "trailingClosureF3", inConstrained: .named("TestClass", []), arguments: [LabeledValue<TypeSignature>(label: nil, value: .function([], .none, [], nil))]).map(\.signature))
    }

    func testFunctionOverload() async throws {
        let context = try await setUpContext(swift: """
        func f(p: Int32) -> Int32 {
            return 0
        }
        func f(p: Float) -> Float {
            return 0
        }
        func f(p: String) -> String {
            return s
        }
        func f(p: Any) -> Any {
            return 1
        }
        """)

        XCTAssertEqual([.function([.init(label: "p", type: .int32)], .int32, [], nil)], context.matchFunction(name: "f", arguments: [.init(label: "p", value: .int)]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "p", type: .float)], .float, [], nil)], context.matchFunction(name: "f", arguments: [.init(label: "p", value: .double)]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "p", type: .string)], .string, [], nil)], context.matchFunction(name: "f", arguments: [.init(label: "p", value: .string)]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "p", type: .any)], .any, [], nil)], context.matchFunction(name: "f", arguments: [.init(label: "p", value: .array(.int))]).map(\.signature))
        XCTAssertEqual(4, context.matchFunction(name: "f", arguments: [.init(label: "p", value: .none)]).count)
    }

    func testInheritanceFunctionOverload() async throws {
        let context = try await setUpContext(swift: """
        protocol P {}
        class A: P {}
        class B: A {}
        class C: B {}
        class D {}

        func f(p: B) {
        }
        func f(p: P) {
        }
        func f(p: Any) {
        }
        """)

        XCTAssertEqual([.function([.init(label: "p", type: .named("P", []))], .void, [], nil)], context.matchFunction(name: "f", arguments: [.init(label: "p", value: .named("P", []))]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "p", type: .named("P", []))], .void, [], nil)], context.matchFunction(name: "f", arguments: [.init(label: "p", value: .named("A", []))]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "p", type: .named("B", []))], .void, [], nil)], context.matchFunction(name: "f", arguments: [.init(label: "p", value: .named("B", []))]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "p", type: .any)], .void, [], nil)], context.matchFunction(name: "f", arguments: [.init(label: "p", value: .named("D", []))]).map(\.signature))
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

        XCTAssertEqual([.function([.init(label: "v", type: .int, hasDefaultValue: true)], .named("TestStruct", []), [], nil)], context.matchFunction(name: "TestStruct", arguments: [LabeledValue<TypeSignature>(label: "v", value: .none)]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "v", type: .int, hasDefaultValue: true), .init(label: "o", type: .optional(.int), hasDefaultValue: true)], .named("TestStruct", []), [], nil)], context.matchFunction(name: "TestStruct", arguments: [LabeledValue<TypeSignature>(label: "v", value: .none), LabeledValue<TypeSignature>(label: "o", value: .none)]).map(\.signature))
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
        XCTAssertEqual(enumSignature, context.matchIdentifier(name: "case1", inConstrained: .metaType(enumSignature))?.signature)
        XCTAssertEqual([], context.associatedValueSignatures(of: "case1", inConstrained: .metaType(enumSignature)))

        let enumAssociatedValueSignature: TypeSignature = .named("AssociatedValueEnum", [])
        XCTAssertEqual(enumAssociatedValueSignature, context.matchIdentifier(name: "case2", inConstrained: .metaType(enumAssociatedValueSignature))?.signature)
        XCTAssertEqual([], context.associatedValueSignatures(of: "case1", inConstrained: .metaType(enumAssociatedValueSignature)))
        XCTAssertEqual([.init(type: .int)], context.associatedValueSignatures(of: "case2", inConstrained: .metaType(enumAssociatedValueSignature)))
        XCTAssertEqual([.init(label: "d", type: .double), .init(label: "s", type: .string)], context.associatedValueSignatures(of: "case3", inConstrained: .metaType(enumAssociatedValueSignature)))

        XCTAssertEqual([.function([.init(type: .int)], enumAssociatedValueSignature, [], nil)], context.matchFunction(name: "case2", inConstrained: .metaType(enumAssociatedValueSignature), arguments: [LabeledValue<TypeSignature>(value: .int)]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "d", type: .double), .init(label: "s", type: .string)], enumAssociatedValueSignature, [], nil)], context.matchFunction(name: "case3", inConstrained: .metaType(enumAssociatedValueSignature), arguments: [LabeledValue<TypeSignature>(label: "d", value: .double), LabeledValue<TypeSignature>(label: "s", value: .string)]).map(\.signature))
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
        XCTAssertEqual([.function([], tupleSignature, [], nil)], context.matchFunction(name: "tupleReturn", inConstrained: .named("TestClass", []), arguments: []).map(\.signature))
    }

    func testTypealiasResolution() async throws {
        let context = try await setUpContext(swift: """
        class TestClass {
        }
        typealias TestAlias = TestClass
        """)

        let typeInfos = context.typeInfos(forNamed: .named("TestAlias", []))
        XCTAssertEqual(1, typeInfos.count)
        XCTAssertEqual("TestClass", typeInfos.first?.name)
    }

    func testDecodeCodebaseInfo() throws {
        let encoded = """
        {"moduleName":"SkipUnit","rootExtensions":[],"rootFunctions":[],"rootTypealiases":[],"rootTypes":[],"rootVariables":[]}
        """
        let info = try JSONDecoder().decode(CodebaseInfo.self, from: encoded.utf8Data)
        XCTAssertEqual("SkipUnit", info.moduleName)
    }
}
