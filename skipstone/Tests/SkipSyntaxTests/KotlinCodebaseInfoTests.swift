@testable import SkipSyntax
import XCTest

final class KotlinCodebaseInfoTests: XCTestCase {
    private func setUpContext() async throws -> CodebaseInfo.Context {
        let srcFile = try tmpFile(named: "Source.swift", contents: swift)
        let source = Source(file: Source.FilePath(path: srcFile.path), content: swift)
        let syntaxTree = SyntaxTree(source: source)

        let codebaseInfo = CodebaseInfo()
        codebaseInfo.kotlin = KotlinCodebaseInfo()
        codebaseInfo.gather(from: syntaxTree)
        codebaseInfo.prepareForUse()
        return codebaseInfo.context(importedModuleNames: [], sourceFile: source.file)
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
        XCTAssertEqual(false, context.isSealedClassesEnum(type: .named("NonExistantTypeName", [])).0)

        XCTAssertEqual(false, context.isSealedClassesEnum(type: .named("TestsEnum", [])).0)
        XCTAssertEqual(true, context.isSealedClassesEnum(type: .named("TestsEnumWithAssociatedValues", [])).0)
    }

    func testProtocolTypeHasMember() async throws {
        let context = try await setUpContext()
        XCTAssertEqual(false, context.isKotlinUnconstrainedInterfaceMember(name: "protocolVar", parameters: nil, isStatic: false, in: .named("NonExistantTypeName", [])))

        XCTAssertEqual(false, context.isKotlinUnconstrainedInterfaceMember(name: "baseProtocolVar", parameters: nil, isStatic: false, in: .named("TestsNonAnyObjectRestrictedProtocol", [])))
        XCTAssertEqual(true, context.isKotlinUnconstrainedInterfaceMember(name: "baseProtocolVar", parameters: nil, isStatic: false, in: .named("TestsAnyObjectRestrictedProtocol", [])))

        let functionParameters: [TypeSignature.Parameter] = [.init(label: "i", type: .int)]
        XCTAssertEqual(false, context.isKotlinUnconstrainedInterfaceMember(name: "baseProtocolFunc", parameters: functionParameters, isStatic: false, in: .named("TestsNonAnyObjectRestrictedProtocol", [])))
        XCTAssertEqual(true, context.isKotlinUnconstrainedInterfaceMember(name: "baseProtocolFunc", parameters: functionParameters, isStatic: false, in: .named("TestsAnyObjectRestrictedProtocol", [])))
        XCTAssertEqual(false, context.isKotlinUnconstrainedInterfaceMember(name: "baseProtocolFunc", parameters: [.init(label: "j", type: .int)], isStatic: false, in: .named("TestsAnyObjectRestrictedProtocol", [])))

        XCTAssertEqual(true, context.isKotlinUnconstrainedInterfaceMember(name: "baseProtocolVar", parameters: nil, isStatic: false, in: .named("TestsTransitiveAnyObjectRestrictedProtocol", [])))
        XCTAssertEqual(true, context.isKotlinUnconstrainedInterfaceMember(name: "baseProtocolFunc", parameters: functionParameters, isStatic: false, in: .named("TestsTransitiveAnyObjectRestrictedProtocol", [])))

        XCTAssertEqual(true, context.isKotlinUnconstrainedInterfaceMember(name: "baseProtocolVar", parameters: nil, isStatic: false, in: .named("TestsProtocolImpl", [])))
        XCTAssertEqual(true, context.isKotlinUnconstrainedInterfaceMember(name: "baseProtocolFunc", parameters: functionParameters, isStatic: false, in: .named("TestsProtocolImpl", [])))
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
