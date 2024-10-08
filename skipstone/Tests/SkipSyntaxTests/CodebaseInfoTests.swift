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

        XCTAssertEqual(.function([.init(label: "p", type: .string)], .int, APIFlags(), nil), context.matchIdentifier(name: "f", inConstrained: .named("TestStruct", []))?.signature)

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
        XCTAssertEqual([.function([.init(type: .int)], .int, APIFlags(), nil)], context.matchSubscript(inConstrained: .array(.int), arguments: [LabeledValue(label: nil, value: ArgumentValue(type: .int))]).map(\.signature))
        XCTAssertEqual([.function([.init(type: .string)], .optional(.int), APIFlags(), nil)], context.matchSubscript(inConstrained: .dictionary(.string, .int), arguments: [LabeledValue(label: nil, value: ArgumentValue(type: .string))]).map(\.signature))
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

        XCTAssertEqual([.function([], .void, APIFlags(), nil)], context.matchFunction(name: "voidF", inConstrained: .named("TestClass", []), arguments: []).map(\.signature))

        XCTAssertEqual([.function([.init(type: .int), .init(label: "p2", type: .string, hasDefaultValue: true)], .int, APIFlags(), nil)], context.matchFunction(name: "baseF", inConstrained: .named("TestClass", []), arguments: [LabeledValue(label: nil, value: ArgumentValue(type: .none)), LabeledValue(label: "p2", value: ArgumentValue(type: .none))]).map(\.signature))
        XCTAssertEqual([.function([.init(type: .int)], .int, APIFlags(), nil)], context.matchFunction(name: "baseF", inConstrained: .named("TestClass", []), arguments: [LabeledValue(label: nil, value: ArgumentValue(type: .none))]).map(\.signature))
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

        XCTAssertEqual([.function([.init(label: "p1", type: .int), .init(label: "tc1", type: .function([.init(type: .string)], .int, APIFlags(), nil))], .string, APIFlags(), nil)], context.matchFunction(name: "trailingClosureF1", inConstrained: .named("TestClass", []), arguments: [LabeledValue(label: "p1", value: ArgumentValue(type: .none)), LabeledValue(label: "tc1", value: ArgumentValue(type: .none))]).map(\.signature))

        let f2Type: TypeSignature = .function([.init(label: "p1", type: .string, hasDefaultValue: true), .init(label: "tc1", type: .function([.init(type: .string), .init(type: .string)], .int, APIFlags(), nil), hasDefaultValue: true), .init(label: "tc2", type: .function([], .void, APIFlags(), nil), hasDefaultValue: true)], .void, APIFlags(), nil)
        XCTAssertEqual([f2Type], context.matchFunction(name: "trailingClosureF2", inConstrained: .named("TestClass", []), arguments: [LabeledValue(label: "p1", value: ArgumentValue(type: .none)), LabeledValue(label: "tc1", value: ArgumentValue(type: .none)), LabeledValue(label: "tc2", value: ArgumentValue(type: .none))]).map(\.signature))
        XCTAssertEqual([f2Type], context.matchFunction(name: "trailingClosureF2", inConstrained: .named("TestClass", []), arguments: [LabeledValue(label: "p1", value: ArgumentValue(type: .none)), LabeledValue(label: nil, value: ArgumentValue(type: .none, isFirstTrailingClosure: true)), LabeledValue(label: "tc2", value: ArgumentValue(type: .none))]).map(\.signature))
        XCTAssertEqual([.function([], .void, APIFlags(), nil)], context.matchFunction(name: "trailingClosureF2", inConstrained: .named("TestClass", []), arguments: []).map(\.signature))

        let f3Type: TypeSignature = .function([.init(type: .optional(.dictionary(.int, .string)), hasDefaultValue: true), .init(label: "tc1", type: .function([], .array(.int), APIFlags(), nil))], .function([.init(type: .named("TestEnum", []))], .int, APIFlags(), nil), APIFlags(), nil)
        XCTAssertEqual([f3Type], context.matchFunction(name: "trailingClosureF3", inConstrained: .named("TestClass", []), arguments: [LabeledValue(label: nil, value: ArgumentValue(type: .none)), LabeledValue(label: "tc1", value: ArgumentValue(type: .none))]).map(\.signature))
        XCTAssertEqual([f3Type], context.matchFunction(name: "trailingClosureF3", inConstrained: .named("TestClass", []), arguments: [LabeledValue(label: nil, value: ArgumentValue(type: .none)), LabeledValue(label: nil, value: ArgumentValue(type: .none, isFirstTrailingClosure: true))]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "tc1", type: .function([], .array(.int), APIFlags(), nil))], .function([.init(type: .named("TestEnum", []))], .int, APIFlags(), nil), APIFlags(), nil)], context.matchFunction(name: "trailingClosureF3", inConstrained: .named("TestClass", []), arguments: [LabeledValue(label: nil, value: ArgumentValue(type: .function([], .none, APIFlags(), nil), isFirstTrailingClosure: true))]).map(\.signature))
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

        XCTAssertEqual([.function([.init(label: "p", type: .int32)], .int32, APIFlags(), nil)], context.matchFunction(name: "f", arguments: [.init(label: "p", value: ArgumentValue(type: .int))]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "p", type: .float)], .float, APIFlags(), nil)], context.matchFunction(name: "f", arguments: [.init(label: "p", value: ArgumentValue(type: .double))]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "p", type: .string)], .string, APIFlags(), nil)], context.matchFunction(name: "f", arguments: [.init(label: "p", value: ArgumentValue(type: .string))]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "p", type: .any)], .any, APIFlags(), nil)], context.matchFunction(name: "f", arguments: [.init(label: "p", value: ArgumentValue(type: .array(.int)))]).map(\.signature))
        XCTAssertEqual(4, context.matchFunction(name: "f", arguments: [.init(label: "p", value: ArgumentValue(type: .none))]).count)
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

        XCTAssertEqual([.function([.init(label: "p", type: .named("P", []))], .void, APIFlags(), nil)], context.matchFunction(name: "f", arguments: [.init(label: "p", value: ArgumentValue(type: .named("P", [])))]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "p", type: .named("P", []))], .void, APIFlags(), nil)], context.matchFunction(name: "f", arguments: [.init(label: "p", value: ArgumentValue(type: .named("A", [])))]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "p", type: .named("B", []))], .void, APIFlags(), nil)], context.matchFunction(name: "f", arguments: [.init(label: "p", value: ArgumentValue(type: .named("B", [])))]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "p", type: .any)], .void, APIFlags(), nil)], context.matchFunction(name: "f", arguments: [.init(label: "p", value: ArgumentValue(type: .named("D", [])))]).map(\.signature))
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

        XCTAssertEqual([.function([.init(label: "v", type: .int, hasDefaultValue: true)], .named("TestStruct", []), APIFlags(), nil)], context.matchFunction(name: "TestStruct", arguments: [LabeledValue(label: "v", value: ArgumentValue(type: .none))]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "v", type: .int, hasDefaultValue: true), .init(label: "o", type: .optional(.int), hasDefaultValue: true)], .named("TestStruct", []), APIFlags(), nil)], context.matchFunction(name: "TestStruct", arguments: [LabeledValue(label: "v", value: ArgumentValue(type: .none)), LabeledValue(label: "o", value: ArgumentValue(type: .none))]).map(\.signature))
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

        XCTAssertEqual([.function([.init(type: .int)], enumAssociatedValueSignature, APIFlags(), nil)], context.matchFunction(name: "case2", inConstrained: .metaType(enumAssociatedValueSignature), arguments: [LabeledValue(value: ArgumentValue(type: .int))]).map(\.signature))
        XCTAssertEqual([.function([.init(label: "d", type: .double), .init(label: "s", type: .string)], enumAssociatedValueSignature, APIFlags(), nil)], context.matchFunction(name: "case3", inConstrained: .metaType(enumAssociatedValueSignature), arguments: [LabeledValue(label: "d", value: ArgumentValue(type: .double)), LabeledValue(label: "s", value: ArgumentValue(type: .string))]).map(\.signature))
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
        XCTAssertEqual([.function([], tupleSignature, APIFlags(), nil)], context.matchFunction(name: "tupleReturn", inConstrained: .named("TestClass", []), arguments: []).map(\.signature))
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

    func testDecodeModuleExport() throws {
        let encoded = """
        {"m":"SkipUnit","e":[],"f":[],"a":[],"t":[],"v":[],"stable":[]}
        """
        let export = try JSONDecoder().decode(CodebaseInfo.ModuleExport.self, from: encoded.utf8Data)
        XCTAssertEqual("SkipUnit", export.moduleName)
    }

    func testCodebaseInfoAndTranspilationSymbolStability() async throws {
        let directoryName = "codebaseinfotest"

        let srcFile1 = try tmpFile(named: "Source1.swift", tmpDirectoryName: directoryName, contents: """
        public var v1 = 1
        public var v2 = 1

        public func f2() {}
        public func f1() {}

        private var pv = 1
        private func pf() {}

        public enum E1 {
            case a, b, c
        }
        public enum E2 {
            case d, e, f
        }

        public class C1 {
            public var v1 = 1
            public var v2 = 1
            public func f1() {}
            public func f2() {}

            private var pv = 1
            private func pf() {}

            public class Inner1 {
                public var i1 = 1
                public var i2 = 1
                public func if1() {}
                public func if2() {}
            }
            public public class Inner2 {
                public var i3 = 1
                public var i4 = 1
                public func if3() {}
                public func if4() {}
            }
        }
        public class C2 {
            public var v4 = 1
            public var v3 = 1
            public func f4() {}
            public func f3() {}
        }

        public protocol P1 {
            func p3() {}
            func p4() {}
            var p1: Int { get }
            var p2: Int { get }
        }
        public protocol P2 {
            var p3: Int { get }
            var p4: Int { get }
            func p5() {}
            func p6() {}
        }

        extension C1 {
            public var v5 = 1
            public var v6 = 1
            public func f5() {}
            public func f6() {}
        }
        extension C2 {
            public func f8() {}
            public func f7() {}
            public var v8 = 1
            public var v7 = 1
        }
        """)

        let srcFile2 = try tmpFile(named: "Source2.swift", tmpDirectoryName: directoryName, contents: """
        import Source2Import

        public var v2_1 = 1
        public var v2_2 = 1

        public func f2_2() {}
        public func f2_1() {}

        public enum E2_1 {
            case a_2, b_2, c_2
        }
        public enum E2_2 {
            case d_2, e_2, f_2
        }

        public class C2_1 {
            public var v2_1 = 1
            public var v2_2 = 1
            public func f2_1() {}
            public func f2_2() {}

            public class Inner2_1 {
                public var i2_1 = 1
                public var i2_2 = 1
                public func i2_f1() {}
                public func i2_f2() {}
            }
            public class Inner2_2 {
                public var i2_3 = 1
                public var i2_4 = 1
                public func if2_3() {}
                public func if2_4() {}
            }
        }
        public class C2_2 {
            public var v2_4 = 1
            public var v2_3 = 1
            public func f2_4() {}
            public func f2_3() {}
        }

        public protocol P2_1 {
            func p2_3() {}
            func p2_4() {}
            var p2_1: Int { get }
            var p2_2: Int { get }
        }
        public protocol P2_2 {
            var p2_3: Int { get }
            var p2_4: Int { get }
            func p2_5() {}
            func p2_6() {}
        }

        extension C1 {
            public var v1_1 = 1
            public var v1_2 = 1
        }

        extension C2_1 {
            public var v2_5 = 1
            public var v2_6 = 1
            public func f2_5() {}
            public func f2_6() {}
        }
        extension C2_2 {
            public func f2_8() {}
            public func f2_7() {}
            public var v2_8 = 1
            public var v2_7 = 1
        }
        """)

        let srcFile3 = try tmpFile(named: "Source3.swift", tmpDirectoryName: directoryName, contents: """
        import Source3Import

        public var v3_1 = 1
        public var v3_2 = 1

        public func f3_2() {}
        public func f3_1() {}

        public enum E3_1 {
            case a_3, b_3, c_3
        }
        public enum E3_2 {
            case d_3, e_3, f_3
        }

        public class C3_1 {
            public var v3_1 = 1
            public var v3_2 = 1
            public func f3_1() {}
            public func f3_2() {}

            public class Inner3_1 {
                public var i3_1 = 1
                public var i3_2 = 1
                public func i3_f1() {}
                public func i3_f2() {}
            }
            public class Inner3_2 {
                public var i3_3 = 1
                public var i3_4 = 1
                public func if3_3() {}
                public func if3_4() {}
            }
        }
        public class C3_2 {
            public var v3_4 = 1
            public var v3_3 = 1
            public func f3_4() {}
            public func f3_3() {}
        }

        public protocol P3_1 {
            func p3_3() {}
            func p3_4() {}
            var p3_1: Int { get }
            var p3_2: Int { get }
        }
        public protocol P3_2 {
            var p3_3: Int { get }
            var p3_4: Int { get }
            func p3_5() {}
            func p3_6() {}
        }

        extension C1 {
            public var v1_3 = 1
            public var v1_4 = 1
        }

        extension C3_1 {
            public var v3_5 = 1
            public var v3_6 = 1
            public func f3_5() {}
            public func f3_6() {}
        }
        extension C3_2 {
            public func f3_8() {}
            public func f3_7() {}
            public var v3_8 = 1
            public var v3_7 = 1
        }
        """)

        let codebaseInfo = CodebaseInfo()
        let srcFiles: [URL]
        if Int.random(in: 0...1) == 0 {
            srcFiles = [srcFile1, srcFile2, srcFile3]
        } else {
            srcFiles = [srcFile3, srcFile2, srcFile1]
        }
        let transpiler = Transpiler(packageName: "tmp.test", transpileFiles: srcFiles.map { Source.FilePath(path: $0.path) }, codebaseInfo: codebaseInfo, transformers: builtinKotlinTransformers())
        var transpilations: [String] = []
        try await transpiler.transpile(handler: { transpilations.append($0.output.content) })

        transpilations.sort()
        let output = transpilations.joined(separator: "\n")
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), outputStabilitySnapshot.trimmingCharacters(in: .whitespacesAndNewlines))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let jsonData = try encoder.encode(CodebaseInfo.ModuleExport(of: codebaseInfo))
        let jsonString = String(data: jsonData, encoding: .utf8)

        XCTAssertEqual(jsonString, symbolStabilitySnapshot)

        let decoder = JSONDecoder()
        let decodedExport = try decoder.decode(CodebaseInfo.ModuleExport.self, from: jsonData)
        decodedExport.prepareForUse()
        XCTAssertGreaterThan(decodedExport.rootTypes.count, 0)
        XCTAssertNotNil(decodedExport.rootTypes.first?.sourceFile)
    }
}

let outputStabilitySnapshot = """
package tmp.test

import skip.lib.*

import source2.import.*

var v2_1 = 1
var v2_2 = 1

fun f2_2() = Unit
fun f2_1() = Unit

enum class E2_1 {
    a_2,
    b_2,
    c_2;

    companion object {
    }
}
enum class E2_2 {
    d_2,
    e_2,
    f_2;

    companion object {
    }
}

open class C2_1 {
    open var v2_1 = 1
    open var v2_2 = 1
    open fun f2_1() = Unit
    open fun f2_2() = Unit

    open class Inner2_1 {
        open var i2_1 = 1
        open var i2_2 = 1
        open fun i2_f1() = Unit
        open fun i2_f2() = Unit

        companion object: CompanionClass() {
        }
        open class CompanionClass {
        }
    }
    open class Inner2_2 {
        open var i2_3 = 1
        open var i2_4 = 1
        open fun if2_3() = Unit
        open fun if2_4() = Unit

        companion object: CompanionClass() {
        }
        open class CompanionClass {
        }
    }

    open var v2_5 = 1
    open var v2_6 = 1
    open fun f2_5() = Unit
    open fun f2_6() = Unit

    companion object: CompanionClass() {
    }
    open class CompanionClass {
    }
}
open class C2_2 {
    open var v2_4 = 1
    open var v2_3 = 1
    open fun f2_4() = Unit
    open fun f2_3() = Unit

    open fun f2_8() = Unit
    open fun f2_7() = Unit
    open var v2_8 = 1
    open var v2_7 = 1

    companion object: CompanionClass() {
    }
    open class CompanionClass {
    }
}

interface P2_1 {
    fun p2_3() = Unit
    fun p2_4() = Unit
    val p2_1: Int
    val p2_2: Int
}
interface P2_2 {
    val p2_3: Int
    val p2_4: Int
    fun p2_5() = Unit
    fun p2_6() = Unit
}

package tmp.test

import skip.lib.*

import source2.import.*
import source3.import.*
var v1 = 1
var v2 = 1

fun f2() = Unit
fun f1() = Unit

private var pv = 1
private fun pf() = Unit

enum class E1 {
    a,
    b,
    c;

    companion object {
    }
}
enum class E2 {
    d,
    e,
    f;

    companion object {
    }
}

open class C1 {
    open var v1 = 1
    open var v2 = 1
    open fun f1() = Unit
    open fun f2() = Unit

    private var pv = 1
    private fun pf() = Unit

    open class Inner1 {
        open var i1 = 1
        open var i2 = 1
        open fun if1() = Unit
        open fun if2() = Unit

        companion object: CompanionClass() {
        }
        open class CompanionClass {
        }
    }
    open class Inner2 {
        open var i3 = 1
        open var i4 = 1
        open fun if3() = Unit
        open fun if4() = Unit

        companion object: CompanionClass() {
        }
        open class CompanionClass {
        }
    }

    open var v5 = 1
    open var v6 = 1
    open fun f5() = Unit
    open fun f6() = Unit

    open var v1_1 = 1
    open var v1_2 = 1

    open var v1_3 = 1
    open var v1_4 = 1

    companion object: CompanionClass() {
    }
    open class CompanionClass {
    }
}
open class C2 {
    open var v4 = 1
    open var v3 = 1
    open fun f4() = Unit
    open fun f3() = Unit

    open fun f8() = Unit
    open fun f7() = Unit
    open var v8 = 1
    open var v7 = 1

    companion object: CompanionClass() {
    }
    open class CompanionClass {
    }
}

interface P1 {
    fun p3() = Unit
    fun p4() = Unit
    val p1: Int
    val p2: Int
}
interface P2 {
    val p3: Int
    val p4: Int
    fun p5() = Unit
    fun p6() = Unit
}

package tmp.test

import skip.lib.*

import source3.import.*

var v3_1 = 1
var v3_2 = 1

fun f3_2() = Unit
fun f3_1() = Unit

enum class E3_1 {
    a_3,
    b_3,
    c_3;

    companion object {
    }
}
enum class E3_2 {
    d_3,
    e_3,
    f_3;

    companion object {
    }
}

open class C3_1 {
    open var v3_1 = 1
    open var v3_2 = 1
    open fun f3_1() = Unit
    open fun f3_2() = Unit

    open class Inner3_1 {
        open var i3_1 = 1
        open var i3_2 = 1
        open fun i3_f1() = Unit
        open fun i3_f2() = Unit

        companion object: CompanionClass() {
        }
        open class CompanionClass {
        }
    }
    open class Inner3_2 {
        open var i3_3 = 1
        open var i3_4 = 1
        open fun if3_3() = Unit
        open fun if3_4() = Unit

        companion object: CompanionClass() {
        }
        open class CompanionClass {
        }
    }

    open var v3_5 = 1
    open var v3_6 = 1
    open fun f3_5() = Unit
    open fun f3_6() = Unit

    companion object: CompanionClass() {
    }
    open class CompanionClass {
    }
}
open class C3_2 {
    open var v3_4 = 1
    open var v3_3 = 1
    open fun f3_4() = Unit
    open fun f3_3() = Unit

    open fun f3_8() = Unit
    open fun f3_7() = Unit
    open var v3_8 = 1
    open var v3_7 = 1

    companion object: CompanionClass() {
    }
    open class CompanionClass {
    }
}

interface P3_1 {
    fun p3_3() = Unit
    fun p3_4() = Unit
    val p3_1: Int
    val p3_2: Int
}
interface P3_2 {
    val p3_3: Int
    val p3_4: Int
    fun p3_5() = Unit
    fun p3_6() = Unit
}
"""

let symbolStabilitySnapshot = """
{\"a\":[],\"e\":[{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f5\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f6\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v5\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v6\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"C1\",\"s\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"sid\":0,\"t\":{\"extensionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"internal\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f8\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f7\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v8\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v7\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"C2\",\"s\":{\"named\":{\"_0\":\"C2\",\"_1\":[]}},\"sid\":0,\"t\":{\"extensionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"internal\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v1_1\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v1_2\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"C1\",\"s\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"sid\":1,\"t\":{\"extensionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"internal\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f2_5\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f2_6\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v2_5\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v2_6\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"C2_1\",\"s\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"sid\":1,\"t\":{\"extensionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"internal\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f2_8\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f2_7\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_2\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v2_8\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_2\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v2_7\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"C2_2\",\"s\":{\"named\":{\"_0\":\"C2_2\",\"_1\":[]}},\"sid\":1,\"t\":{\"extensionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"internal\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v1_3\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v1_4\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"C1\",\"s\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"sid\":2,\"t\":{\"extensionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"internal\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f3_5\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f3_6\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v3_5\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v3_6\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"C3_1\",\"s\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"sid\":2,\"t\":{\"extensionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"internal\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f3_8\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f3_7\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_2\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v3_8\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_2\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v3_7\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"C3_2\",\"s\":{\"named\":{\"_0\":\"C3_2\",\"_1\":[]}},\"sid\":2,\"t\":{\"extensionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"internal\":{}}}}],\"f\":[{\"a\":{\"a\":[]},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f2\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f1\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f2_2\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f2_1\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f3_2\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f3_1\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"stable\":[\"/tmp/SkipSyntaxTests/codebaseinfotest/Source1.swift\",\"/tmp/SkipSyntaxTests/codebaseinfotest/Source2.swift\",\"/tmp/SkipSyntaxTests/codebaseinfotest/Source3.swift\"],\"t\":[{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E1\",\"_1\":[]}},\"n\":\"a\",\"s\":{\"named\":{\"_0\":\"E1\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E1\",\"_1\":[]}},\"n\":\"b\",\"s\":{\"named\":{\"_0\":\"E1\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E1\",\"_1\":[]}},\"n\":\"c\",\"s\":{\"named\":{\"_0\":\"E1\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"mf\":[],\"ms\":[],\"mt\":[],\"mv\":[],\"n\":\"E1\",\"s\":{\"named\":{\"_0\":\"E1\",\"_1\":[]}},\"sid\":0,\"t\":{\"enumDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E2\",\"_1\":[]}},\"n\":\"d\",\"s\":{\"named\":{\"_0\":\"E2\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E2\",\"_1\":[]}},\"n\":\"e\",\"s\":{\"named\":{\"_0\":\"E2\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E2\",\"_1\":[]}},\"n\":\"f\",\"s\":{\"named\":{\"_0\":\"E2\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"mf\":[],\"ms\":[],\"mt\":[],\"mv\":[],\"n\":\"E2\",\"s\":{\"named\":{\"_0\":\"E2\",\"_1\":[]}},\"sid\":0,\"t\":{\"enumDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f1\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f2\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":true,\"mut\":false,\"n\":\"init\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"initDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner1\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"if1\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner1\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"if2\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner1\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":true,\"mut\":false,\"n\":\"init\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner1\",\"_1\":[]}}}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"initDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner1\",\"_1\":[]}}}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"i1\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner1\",\"_1\":[]}}}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"i2\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"Inner1\",\"s\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner1\",\"_1\":[]}}}},\"sid\":0,\"t\":{\"classDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"if3\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"if4\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":true,\"mut\":false,\"n\":\"init\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2\",\"_1\":[]}}}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"initDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2\",\"_1\":[]}}}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"i3\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2\",\"_1\":[]}}}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"i4\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"Inner2\",\"s\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2\",\"_1\":[]}}}},\"sid\":0,\"t\":{\"classDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v1\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v2\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"C1\",\"s\":{\"named\":{\"_0\":\"C1\",\"_1\":[]}},\"sid\":0,\"t\":{\"classDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f4\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f3\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":true,\"mut\":false,\"n\":\"init\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"named\":{\"_0\":\"C2\",\"_1\":[]}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"initDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v4\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v3\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"C2\",\"s\":{\"named\":{\"_0\":\"C2\",\"_1\":[]}},\"sid\":0,\"t\":{\"classDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"p3\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"p4\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P1\",\"_1\":[]}},\"f\":{\"o\":128,\"t\":{\"none\":{}}},\"gen\":false,\"init\":false,\"n\":\"p1\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":false,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P1\",\"_1\":[]}},\"f\":{\"o\":128,\"t\":{\"none\":{}}},\"gen\":false,\"init\":false,\"n\":\"p2\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":false,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"P1\",\"s\":{\"named\":{\"_0\":\"P1\",\"_1\":[]}},\"sid\":0,\"t\":{\"protocolDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"p5\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"p6\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":0,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P2\",\"_1\":[]}},\"f\":{\"o\":128,\"t\":{\"none\":{}}},\"gen\":false,\"init\":false,\"n\":\"p3\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":false,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P2\",\"_1\":[]}},\"f\":{\"o\":128,\"t\":{\"none\":{}}},\"gen\":false,\"init\":false,\"n\":\"p4\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":false,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"P2\",\"s\":{\"named\":{\"_0\":\"P2\",\"_1\":[]}},\"sid\":0,\"t\":{\"protocolDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E2_1\",\"_1\":[]}},\"n\":\"a_2\",\"s\":{\"named\":{\"_0\":\"E2_1\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E2_1\",\"_1\":[]}},\"n\":\"b_2\",\"s\":{\"named\":{\"_0\":\"E2_1\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E2_1\",\"_1\":[]}},\"n\":\"c_2\",\"s\":{\"named\":{\"_0\":\"E2_1\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"mf\":[],\"ms\":[],\"mt\":[],\"mv\":[],\"n\":\"E2_1\",\"s\":{\"named\":{\"_0\":\"E2_1\",\"_1\":[]}},\"sid\":1,\"t\":{\"enumDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E2_2\",\"_1\":[]}},\"n\":\"d_2\",\"s\":{\"named\":{\"_0\":\"E2_2\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E2_2\",\"_1\":[]}},\"n\":\"e_2\",\"s\":{\"named\":{\"_0\":\"E2_2\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E2_2\",\"_1\":[]}},\"n\":\"f_2\",\"s\":{\"named\":{\"_0\":\"E2_2\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"mf\":[],\"ms\":[],\"mt\":[],\"mv\":[],\"n\":\"E2_2\",\"s\":{\"named\":{\"_0\":\"E2_2\",\"_1\":[]}},\"sid\":1,\"t\":{\"enumDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f2_1\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f2_2\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":true,\"mut\":false,\"n\":\"init\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"initDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2_1\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"i2_f1\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2_1\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"i2_f2\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2_1\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":true,\"mut\":false,\"n\":\"init\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2_1\",\"_1\":[]}}}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"initDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2_1\",\"_1\":[]}}}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"i2_1\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2_1\",\"_1\":[]}}}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"i2_2\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"Inner2_1\",\"s\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2_1\",\"_1\":[]}}}},\"sid\":1,\"t\":{\"classDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2_2\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"if2_3\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2_2\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"if2_4\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2_2\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":true,\"mut\":false,\"n\":\"init\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2_2\",\"_1\":[]}}}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"initDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2_2\",\"_1\":[]}}}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"i2_3\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2_2\",\"_1\":[]}}}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"i2_4\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"Inner2_2\",\"s\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner2_2\",\"_1\":[]}}}},\"sid\":1,\"t\":{\"classDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v2_1\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v2_2\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"C2_1\",\"s\":{\"named\":{\"_0\":\"C2_1\",\"_1\":[]}},\"sid\":1,\"t\":{\"classDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f2_4\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f2_3\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":true,\"mut\":false,\"n\":\"init\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"named\":{\"_0\":\"C2_2\",\"_1\":[]}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"initDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_2\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v2_4\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C2_2\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v2_3\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"C2_2\",\"s\":{\"named\":{\"_0\":\"C2_2\",\"_1\":[]}},\"sid\":1,\"t\":{\"classDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P2_1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"p2_3\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P2_1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"p2_4\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P2_1\",\"_1\":[]}},\"f\":{\"o\":128,\"t\":{\"none\":{}}},\"gen\":false,\"init\":false,\"n\":\"p2_1\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":false,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P2_1\",\"_1\":[]}},\"f\":{\"o\":128,\"t\":{\"none\":{}}},\"gen\":false,\"init\":false,\"n\":\"p2_2\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":false,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"P2_1\",\"s\":{\"named\":{\"_0\":\"P2_1\",\"_1\":[]}},\"sid\":1,\"t\":{\"protocolDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P2_2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"p2_5\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P2_2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"p2_6\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":1,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P2_2\",\"_1\":[]}},\"f\":{\"o\":128,\"t\":{\"none\":{}}},\"gen\":false,\"init\":false,\"n\":\"p2_3\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":false,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P2_2\",\"_1\":[]}},\"f\":{\"o\":128,\"t\":{\"none\":{}}},\"gen\":false,\"init\":false,\"n\":\"p2_4\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":false,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"P2_2\",\"s\":{\"named\":{\"_0\":\"P2_2\",\"_1\":[]}},\"sid\":1,\"t\":{\"protocolDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E3_1\",\"_1\":[]}},\"n\":\"a_3\",\"s\":{\"named\":{\"_0\":\"E3_1\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E3_1\",\"_1\":[]}},\"n\":\"b_3\",\"s\":{\"named\":{\"_0\":\"E3_1\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E3_1\",\"_1\":[]}},\"n\":\"c_3\",\"s\":{\"named\":{\"_0\":\"E3_1\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"mf\":[],\"ms\":[],\"mt\":[],\"mv\":[],\"n\":\"E3_1\",\"s\":{\"named\":{\"_0\":\"E3_1\",\"_1\":[]}},\"sid\":2,\"t\":{\"enumDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E3_2\",\"_1\":[]}},\"n\":\"d_3\",\"s\":{\"named\":{\"_0\":\"E3_2\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E3_2\",\"_1\":[]}},\"n\":\"e_3\",\"s\":{\"named\":{\"_0\":\"E3_2\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"E3_2\",\"_1\":[]}},\"n\":\"f_3\",\"s\":{\"named\":{\"_0\":\"E3_2\",\"_1\":[]}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"mf\":[],\"ms\":[],\"mt\":[],\"mv\":[],\"n\":\"E3_2\",\"s\":{\"named\":{\"_0\":\"E3_2\",\"_1\":[]}},\"sid\":2,\"t\":{\"enumDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f3_1\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f3_2\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":true,\"mut\":false,\"n\":\"init\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"initDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner3_1\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"i3_f1\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner3_1\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"i3_f2\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner3_1\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":true,\"mut\":false,\"n\":\"init\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner3_1\",\"_1\":[]}}}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"initDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner3_1\",\"_1\":[]}}}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"i3_1\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner3_1\",\"_1\":[]}}}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"i3_2\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"Inner3_1\",\"s\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner3_1\",\"_1\":[]}}}},\"sid\":2,\"t\":{\"classDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner3_2\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"if3_3\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner3_2\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"if3_4\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner3_2\",\"_1\":[]}}}},\"g\":{\"e\":[]},\"gen\":true,\"mut\":false,\"n\":\"init\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner3_2\",\"_1\":[]}}}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"initDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner3_2\",\"_1\":[]}}}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"i3_3\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner3_2\",\"_1\":[]}}}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"i3_4\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"Inner3_2\",\"s\":{\"member\":{\"_0\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"_1\":{\"named\":{\"_0\":\"Inner3_2\",\"_1\":[]}}}},\"sid\":2,\"t\":{\"classDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v3_1\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v3_2\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"C3_1\",\"s\":{\"named\":{\"_0\":\"C3_1\",\"_1\":[]}},\"sid\":2,\"t\":{\"classDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f3_4\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"f3_3\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":true,\"mut\":false,\"n\":\"init\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"named\":{\"_0\":\"C3_2\",\"_1\":[]}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"initDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_2\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v3_4\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"C3_2\",\"_1\":[]}},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v3_3\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"C3_2\",\"s\":{\"named\":{\"_0\":\"C3_2\",\"_1\":[]}},\"sid\":2,\"t\":{\"classDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P3_1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"p3_3\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P3_1\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"p3_4\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P3_1\",\"_1\":[]}},\"f\":{\"o\":128,\"t\":{\"none\":{}}},\"gen\":false,\"init\":false,\"n\":\"p3_1\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":false,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P3_1\",\"_1\":[]}},\"f\":{\"o\":128,\"t\":{\"none\":{}}},\"gen\":false,\"init\":false,\"n\":\"p3_2\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":false,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"P3_1\",\"s\":{\"named\":{\"_0\":\"P3_1\",\"_1\":[]}},\"sid\":2,\"t\":{\"protocolDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":0,\"t\":{\"none\":{}}},\"g\":{\"e\":[]},\"i\":[],\"ma\":[],\"mc\":[],\"mf\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P3_2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"p3_5\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P3_2\",\"_1\":[]}},\"g\":{\"e\":[]},\"gen\":false,\"mut\":false,\"n\":\"p3_6\",\"s\":{\"function\":{\"_0\":[],\"_1\":{\"void\":{}},\"_2\":{\"o\":0,\"t\":{\"none\":{}}}}},\"sid\":2,\"t\":{\"functionDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"ms\":[],\"mt\":[],\"mv\":[{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P3_2\",\"_1\":[]}},\"f\":{\"o\":128,\"t\":{\"none\":{}}},\"gen\":false,\"init\":false,\"n\":\"p3_3\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":false,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"d\":{\"named\":{\"_0\":\"P3_2\",\"_1\":[]}},\"f\":{\"o\":128,\"t\":{\"none\":{}}},\"gen\":false,\"init\":false,\"n\":\"p3_4\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":false,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"n\":\"P3_2\",\"s\":{\"named\":{\"_0\":\"P3_2\",\"_1\":[]}},\"sid\":2,\"t\":{\"protocolDeclaration\":{}},\"v\":{\"available\":{}},\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}],\"v\":[{\"a\":{\"a\":[]},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v1\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v2\",\"s\":{\"int\":{}},\"sid\":0,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v2_1\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v2_2\",\"s\":{\"int\":{}},\"sid\":1,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v3_1\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}},{\"a\":{\"a\":[]},\"f\":{\"o\":32,\"t\":{\"none\":{}}},\"gen\":false,\"init\":true,\"n\":\"v3_2\",\"s\":{\"int\":{}},\"sid\":2,\"v\":{\"available\":{}},\"val\":true,\"z\":{\"f\":false,\"l\":false,\"m\":false,\"n\":false,\"o\":false,\"s\":false,\"sv\":{\"default\":{}},\"v\":{\"public\":{}}}}]}
"""
