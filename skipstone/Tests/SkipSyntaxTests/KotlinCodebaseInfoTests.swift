@testable import SkipSyntax
import XCTest

final class KotlinCodebaseInfoTests: XCTestCase {
    private func setUpContext() async throws -> KotlinCodebaseInfo.Context {
        let srcFile = try tmpFile(named: "Source.swift", contents: swift)
        let source = Source(file: Source.FilePath(path: srcFile.path), content: swift)
        let syntaxTree = SyntaxTree(source: source)

        let codebaseInfo = CodebaseInfo()
        let kotlinCodebaseInfo = KotlinCodebaseInfo(codebaseInfo: codebaseInfo)
        kotlinCodebaseInfo.gather(from: syntaxTree)
        kotlinCodebaseInfo.prepareForUse()
        return kotlinCodebaseInfo.context(importedModuleNames: [], sourceFile: source.file)
    }

    func testIsMutableStructType() async throws {
        let context = try await setUpContext()
        XCTAssertEqual(true, context.mayBeMutableStruct(type: .named("NonExistantTypeName", [])))

        XCTAssertEqual(false, context.mayBeMutableStruct(type: .named("TestsClass", [])))
        XCTAssertEqual(false, context.mayBeMutableStruct(type: .named("TestsEnum", [])))
        XCTAssertEqual(false, context.mayBeMutableStruct(type: .named("TestsImmutableStruct", [])))

        XCTAssertEqual(true, context.mayBeMutableStruct(type: .named("TestsMutableVarStruct", [])))
        XCTAssertEqual(true, context.mayBeMutableStruct(type: .named("TestsMutableComputedVarStruct", [])))
        XCTAssertEqual(true, context.mayBeMutableStruct(type: .named("TestsMutableFuncStruct", [])))

        XCTAssertEqual(true, context.mayBeMutableStruct(type: .named("TestsNonAnyObjectRestrictedProtocol", [])))
        XCTAssertEqual(false, context.mayBeMutableStruct(type: .named("TestsAnyObjectRestrictedProtocol", [])))
        XCTAssertEqual(false, context.mayBeMutableStruct(type: .named("TestsTransitiveAnyObjectRestrictedProtocol", [])))
    }

    func testEnumHasAssociatedValues() async throws {
        let context = try await setUpContext()
        XCTAssertEqual(false, context.isSealedClassesEnum(type: .named("NonExistantTypeName", [])))

        XCTAssertEqual(false, context.isSealedClassesEnum(type: .named("TestsEnum", [])))
        XCTAssertEqual(true, context.isSealedClassesEnum(type: .named("TestsEnumWithAssociatedValues", [])))
    }

    func testProtocolTypeHasMember() async throws {
        let context = try await setUpContext()
        XCTAssertEqual(false, context.isProtocolMember(name: "protocolVar", type: nil, isStatic: false, in: .named("NonExistantTypeName", [])))

        XCTAssertEqual(false, context.isProtocolMember(name: "baseProtocolVar", type: nil, isStatic: false, in: .named("TestsNonAnyObjectRestrictedProtocol", [])))
        XCTAssertEqual(true, context.isProtocolMember(name: "baseProtocolVar", type: nil, isStatic: false, in: .named("TestsAnyObjectRestrictedProtocol", [])))
        XCTAssertEqual(true, context.isProtocolMember(name: "baseProtocolVar", type: .int, isStatic: false, in: .named("TestsAnyObjectRestrictedProtocol", [])))
        XCTAssertEqual(false, context.isProtocolMember(name: "baseProtocolVar", type: .string, isStatic: false, in: .named("TestsAnyObjectRestrictedProtocol", [])))

        let functionType: TypeSignature = .function([.init(label: "i", type: .int)], .string)
        XCTAssertEqual(false, context.isProtocolMember(name: "baseProtocolFunc", type: functionType, isStatic: false, in: .named("TestsNonAnyObjectRestrictedProtocol", [])))
        XCTAssertEqual(true, context.isProtocolMember(name: "baseProtocolFunc", type: functionType, isStatic: false, in: .named("TestsAnyObjectRestrictedProtocol", [])))
        XCTAssertEqual(false, context.isProtocolMember(name: "baseProtocolFunc", type: .function([.init(label: "i", type: .string)], .string), isStatic: false, in: .named("TestsAnyObjectRestrictedProtocol", [])))

        XCTAssertEqual(true, context.isProtocolMember(name: "baseProtocolVar", type: nil, isStatic: false, in: .named("TestsTransitiveAnyObjectRestrictedProtocol", [])))
        XCTAssertEqual(true, context.isProtocolMember(name: "baseProtocolFunc", type: functionType, isStatic: false, in: .named("TestsTransitiveAnyObjectRestrictedProtocol", [])))

        XCTAssertEqual(true, context.isProtocolMember(name: "baseProtocolVar", type: nil, isStatic: false, in: .named("TestsProtocolImpl", [])))
        XCTAssertEqual(true, context.isProtocolMember(name: "baseProtocolFunc", type: functionType, isStatic: false, in: .named("TestsProtocolImpl", [])))
    }
}

private let swift = """
class TestsClass {
}

enum TestsEnum: Int {
    case case1
    case case2 = 100
}
enum TestsEnumWithAssociatedValues {
    case case1
    case case2(Int)
}

struct TestsImmutableStruct {
    let letVar = 1
}

struct TestsMutableVarStruct {
    var v = 1
}

struct TestsMutableComputedVarStruct {
    var computedVar: Int {
        get {
            return 1
        }
        set {
        }
    }
}

struct TestsMutableFuncStruct {
    mutating func f() -> Int {
        return 1
    }
}

protocol TestsNonAnyObjectRestrictedProtocol: Codable {}
protocol TestsAnyObjectRestrictedProtocol: AnyObject {
    var baseProtocolVar: Int { get }
    func baseProtocolFunc(i: Int) -> String
}
protocol TestsTransitiveAnyObjectRestrictedProtocol: TestsAnyObjectRestrictedProtocol {
}
class TestsProtocolImpl: TestsTransitiveAnyObjectRestrictedProtocol {
    var baseProtocolVar = 1
    func baseProtocolFunc(i: Int) -> String {
        return ""
    }
}
"""
