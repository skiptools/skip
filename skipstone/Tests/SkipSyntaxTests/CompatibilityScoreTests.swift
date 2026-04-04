// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

@testable import SkipSyntax
import XCTest

final class CompatibilityScoreTests: XCTestCase {
    var context: CodebaseInfo.Context!

    override func setUp() async throws {
        try await super.setUp()
        context = try await setUpContext(swift: "")
    }

    private func setUpContext(swift: String) async throws -> CodebaseInfo.Context {
        let srcFile = try tmpFile(named: "Source.swift", contents: swift)
        let source = Source(file: Source.FilePath(path: srcFile.path), content: swift)
        let syntaxTree = SyntaxTree(source: source)

        let codebaseInfo = CodebaseInfo()
        codebaseInfo.gather(from: syntaxTree)
        codebaseInfo.prepareForUse()
        return codebaseInfo.context(importedModuleNames: [], sourceFile: source.file)
    }

    func testExactTypeScore() async throws {
        XCTAssertEqual(TypeSignature.int.compatibilityScore(target: .int, codebaseInfo: context), 2.0)
    }

    func testStringLiteralExactScore() async throws {
        XCTAssertEqual(TypeSignature.string.compatibilityScore(target: .string, codebaseInfo: context, isLiteral: true), 1.95)
    }

    func testAnyTargetScore() async throws {
        XCTAssertEqual(TypeSignature.int.compatibilityScore(target: .any, codebaseInfo: context), 1.0)
    }

    func testIntToFloatingPointScore() async throws {
        XCTAssertEqual(TypeSignature.int.compatibilityScore(target: .double, codebaseInfo: context), 1.0)
    }

    func testNumericToNumericScore() async throws {
        XCTAssertEqual(TypeSignature.int.compatibilityScore(target: .int32, codebaseInfo: context), 1.5)
    }

    func testNoneMatchesExactlyScore() async throws {
        XCTAssertEqual(TypeSignature.none.compatibilityScore(target: .none, codebaseInfo: context), 2.0)
    }

    func testEquatableNamedScore() async throws {
        XCTAssertEqual(TypeSignature.bool.compatibilityScore(target: .named("Equatable", []), codebaseInfo: context), 1.9)
    }

    func testSendableNamedScore() async throws {
        XCTAssertEqual(TypeSignature.bool.compatibilityScore(target: .named("Sendable", []), codebaseInfo: context), 1.9)
    }

    func testEquatableSendableCompositionScore() async throws {
        let target: TypeSignature = .composition([.named("Equatable", []), .named("Sendable", [])])
        XCTAssertEqual(TypeSignature.bool.compatibilityScore(target: target, codebaseInfo: context), 1.9)
    }

    func testArray() async throws {
        XCTAssertEqual(TypeSignature.array(.int).compatibilityScore(target: .array(.int), codebaseInfo: context), 2.0)
        XCTAssertEqual(TypeSignature.array(.int).compatibilityScore(target: .set(.int), codebaseInfo: context), 2.0)
        XCTAssertNil(TypeSignature.array(.int).compatibilityScore(target: .array(.string), codebaseInfo: context))
        XCTAssertNil(TypeSignature.array(.int).compatibilityScore(target: .dictionary(.string, .int), codebaseInfo: context))
    }

    func testCharacter() async throws {
        XCTAssertEqual(TypeSignature.character.compatibilityScore(target: .character, codebaseInfo: context), 2.0)
        XCTAssertEqual(TypeSignature.character.compatibilityScore(target: .string, codebaseInfo: context), 1.0)
        XCTAssertNil(TypeSignature.character.compatibilityScore(target: .int, codebaseInfo: context))
    }

    func testDictionary() async throws {
        XCTAssertEqual(TypeSignature.dictionary(.string, .int32).compatibilityScore(target: .dictionary(.string, .int32), codebaseInfo: context), 2.0)
        XCTAssertEqual(TypeSignature.dictionary(.string, .int).compatibilityScore(target: .dictionary(.string, .int32), codebaseInfo: context), 1.875)
        XCTAssertNil(TypeSignature.dictionary(.string, .int).compatibilityScore(target: .dictionary(.int, .int), codebaseInfo: context))
        XCTAssertNil(TypeSignature.dictionary(.string, .int).compatibilityScore(target: .array(.int), codebaseInfo: context))
    }

    func testDoubleFloat() async throws {
        XCTAssertEqual(TypeSignature.double.compatibilityScore(target: .float, codebaseInfo: context), 1.5)
        XCTAssertNil(TypeSignature.double.compatibilityScore(target: .string, codebaseInfo: context))
    }

    func testIntFamily() async throws {
        XCTAssertEqual(TypeSignature.int.compatibilityScore(target: .double, codebaseInfo: context), 1.0)
        XCTAssertNil(TypeSignature.int.compatibilityScore(target: .string, codebaseInfo: context))
    }

    func testFunction() async throws {
        let source: TypeSignature = .function([.init(type: .int)], .void, APIFlags(), nil)
        let target: TypeSignature = .function([.init(type: .double)], .void, APIFlags(), nil)
        XCTAssertEqual(source.compatibilityScore(target: target, codebaseInfo: context), 1.5)
        let mismatchedFunction: TypeSignature = .function([.init(type: .double), .init(type: .double)], .void, APIFlags(), nil)
        XCTAssertEqual(source.compatibilityScore(target: mismatchedFunction, codebaseInfo: context), 1.0)
        XCTAssertNil(source.compatibilityScore(target: .string, codebaseInfo: context))
    }

    func testMemberNamed() async throws {
        context = try await setUpContext(swift: """
        protocol P {}
        class A: P {}
        class D {}
        """)
        XCTAssertEqual(TypeSignature.named("A", []).compatibilityScore(target: .named("P", []), codebaseInfo: context), 1.9)
        XCTAssertNil(TypeSignature.named("A", []).compatibilityScore(target: .named("D", []), codebaseInfo: context))
        XCTAssertNil(TypeSignature.named("D", []).compatibilityScore(target: .named("P", []), codebaseInfo: context))
    }

    func testMetaType() async throws {
        XCTAssertEqual(TypeSignature.metaType(.int).compatibilityScore(target: .metaType(.double), codebaseInfo: context), 1.0)
        XCTAssertNil(TypeSignature.metaType(.int).compatibilityScore(target: .metaType(.string), codebaseInfo: context))
        XCTAssertNil(TypeSignature.metaType(.int).compatibilityScore(target: .int, codebaseInfo: context))
    }

    func testNone() async throws {
        XCTAssertEqual(TypeSignature.none.compatibilityScore(target: .none, codebaseInfo: context), 2.0)
        XCTAssertEqual(TypeSignature.none.compatibilityScore(target: .int, codebaseInfo: context), 0.0)
    }

    func testOptional() async throws {
        XCTAssertEqual(TypeSignature.optional(.int).compatibilityScore(target: .optional(.int), codebaseInfo: context), 2.0)
        XCTAssertNil(TypeSignature.optional(.int).compatibilityScore(target: .optional(.string), codebaseInfo: context))
        XCTAssertNil(TypeSignature.optional(.int).compatibilityScore(target: .int, codebaseInfo: context))
    }

    func testRange() async throws {
        XCTAssertEqual(TypeSignature.range(.int).compatibilityScore(target: .range(.int32), codebaseInfo: context), 1.75)
        XCTAssertNil(TypeSignature.range(.int).compatibilityScore(target: .range(.string), codebaseInfo: context))
        XCTAssertNil(TypeSignature.range(.int).compatibilityScore(target: .set(.int), codebaseInfo: context))
    }

    func testSet() async throws {
        XCTAssertEqual(TypeSignature.set(.int).compatibilityScore(target: .set(.int32), codebaseInfo: context), 1.75)
        XCTAssertNil(TypeSignature.set(.int).compatibilityScore(target: .set(.string), codebaseInfo: context))
        XCTAssertNil(TypeSignature.set(.int).compatibilityScore(target: .dictionary(.string, .int), codebaseInfo: context))
    }

    func testString() async throws {
        XCTAssertEqual(TypeSignature.string.compatibilityScore(target: .character, codebaseInfo: context), 1.0)
        XCTAssertNil(TypeSignature.string.compatibilityScore(target: .int, codebaseInfo: context))
    }

    func testTuple() async throws {
        let source: TypeSignature = .tuple(["a", "b"], [.int, .string])
        let compatibleTarget: TypeSignature = .tuple(["x", "y"], [.int32, .string])
        let sameTopLevelMismatchedTarget: TypeSignature = .tuple(["x", "y"], [.int32, .int])
        let incompatibleTarget: TypeSignature = .tuple(["x"], [.int32])
        XCTAssertEqual(source.compatibilityScore(target: compatibleTarget, codebaseInfo: context) ?? 0.0, 1.833, accuracy: 0.001)
        XCTAssertNil(source.compatibilityScore(target: sameTopLevelMismatchedTarget, codebaseInfo: context))
        XCTAssertNil(source.compatibilityScore(target: incompatibleTarget, codebaseInfo: context))
    }

    func testUnwrappedOptional() async throws {
        XCTAssertEqual(TypeSignature.unwrappedOptional(.int).compatibilityScore(target: .double, codebaseInfo: context), 1.0)
        XCTAssertNil(TypeSignature.unwrappedOptional(.int).compatibilityScore(target: .string, codebaseInfo: context))
    }

    func testVoid() async throws {
        XCTAssertEqual(TypeSignature.void.compatibilityScore(target: .none, codebaseInfo: context), 1.0)
        XCTAssertNil(TypeSignature.void.compatibilityScore(target: .int, codebaseInfo: context))
    }

    func testDefaultBranch() async throws {
        XCTAssertEqual(TypeSignature.any.compatibilityScore(target: .anyObject, codebaseInfo: context), 1.0)
        XCTAssertNil(TypeSignature.any.compatibilityScore(target: .int, codebaseInfo: context))
    }

    func testInheritanceWithoutComposition() async throws {
        context = try await setUpContext(swift: """
        protocol P {}
        class A: P {}
        class D {}
        """)
        XCTAssertEqual(TypeSignature.named("A", []).compatibilityScore(target: .named("P", []), codebaseInfo: context), 1.9)
        XCTAssertNil(TypeSignature.named("D", []).compatibilityScore(target: .named("P", []), codebaseInfo: context))
    }

    func testInheritanceWithComposition() async throws {
        context = try await setUpContext(swift: """
        protocol P: Sendable {}
        class A: P {}
        protocol Q {}
        """)
        let positiveTarget: TypeSignature = .composition([.named("Equatable", []), .named("P", [])])
        let negativeTarget: TypeSignature = .composition([.named("Equatable", []), .named("Q", [])])
        XCTAssertEqual(TypeSignature.named("A", []).compatibilityScore(target: positiveTarget, codebaseInfo: context), 1.9)
        XCTAssertNil(TypeSignature.named("A", []).compatibilityScore(target: negativeTarget, codebaseInfo: context))
    }
}
