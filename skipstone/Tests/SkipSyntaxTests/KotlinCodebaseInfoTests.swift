// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

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

        XCTAssertEqual(true, context.mayBeMutableStruct(type: .named("MyOptionSet", [])))
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

    func testPackageNameOverrides() throws {
        defer { KotlinTranslator.packageNameOverrides = [:] }

        // Set up a dependent module with a custom package name
        let depSwift = "public class DepClass { }"
        let depFile = try tmpFile(named: "Source_DepModule.swift", contents: depSwift)
        let depSource = Source(file: Source.FilePath(path: depFile.path), content: depSwift)
        let depTree = SyntaxTree(source: depSource)
        let depInfo = CodebaseInfo(moduleName: "DepModule")
        depInfo.kotlin = KotlinCodebaseInfo(packageName: "com.example.dep")
        depInfo.gather(from: depTree)
        depInfo.prepareForUse()
        let depExport = CodebaseInfo.ModuleExport(of: depInfo)

        // Verify the export captured the custom package name
        XCTAssertEqual("com.example.dep", depExport.packageName)

        // Set up the main module with a custom package name and the dependent module
        let codebaseInfo = CodebaseInfo(moduleName: "MainModule")
        codebaseInfo.kotlin = KotlinCodebaseInfo(packageName: "com.example.main")
        codebaseInfo.dependentModules = [depExport]
        codebaseInfo.prepareForUse()

        // Verify overrides are populated for both current and dependent modules
        XCTAssertEqual("com.example.main", KotlinTranslator.packageNameOverrides["MainModule"])
        XCTAssertEqual("com.example.dep", KotlinTranslator.packageNameOverrides["DepModule"])

        // Verify packageName(forModule:) uses overrides
        XCTAssertEqual("com.example.main", KotlinTranslator.packageName(forModule: "MainModule"))
        XCTAssertEqual("com.example.dep", KotlinTranslator.packageName(forModule: "DepModule"))

        // Verify non-overridden modules still use algorithmic names
        XCTAssertEqual("other.module", KotlinTranslator.packageName(forModule: "OtherModule"))
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

struct MyOptionSet: OptionSet, RawRepresentable {
    let rawValue: Int
    static let someValue = MyOptionSet(rawValue: 1)
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
