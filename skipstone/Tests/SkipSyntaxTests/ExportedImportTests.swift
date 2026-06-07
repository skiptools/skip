// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
@testable import SkipSyntax
import XCTest

/// Tests for `@_exported import` umbrella re-export support.
///
/// When a Swift module marks an import as `@_exported`, types from the imported module are
/// visible to code that imports the umbrella module without naming the underlying one. The
/// transpiler needs to emit the matching Kotlin imports so that the same is true for the
/// transpiled output.
final class ExportedImportTests: XCTestCase {
    /// `CodebaseInfo` records the names of modules re-exported via `@_exported import` so that
    /// dependent modules can pick them up at translation time.
    func testCodebaseInfoRecordsExportedModuleNames() throws {
        let inner = try moduleExport(named: "Inner")
        let info = try codebaseInfo(moduleName: "Umbrella", dependentModules: [inner], swift: """
        @_exported import Inner
        import Other

        public class Wrapped {}
        """)

        XCTAssertEqual(["Inner"], info.exportedModuleNames)
    }

    /// Multiple `@_exported import` declarations stack up, while plain imports do not.
    func testCodebaseInfoRecordsMultipleExportedModuleNames() throws {
        let innerA = try moduleExport(named: "InnerA")
        let innerB = try moduleExport(named: "InnerB")
        let info = try codebaseInfo(moduleName: "Umbrella", dependentModules: [innerA, innerB], swift: """
        @_exported import InnerA
        @_exported import InnerB
        import Other

        public class Wrapped {}
        """)

        XCTAssertEqual(["InnerA", "InnerB"], info.exportedModuleNames)
    }

    /// A duplicated `@_exported import` of the same module is only recorded once.
    func testCodebaseInfoDeduplicatesExportedModuleNames() throws {
        let inner = try moduleExport(named: "Inner")
        let info = CodebaseInfo(moduleName: "Umbrella")
        info.dependentModules = [inner]
        info.gather(from: try syntaxTree(forSwift: """
        @_exported import Inner

        public class FirstFile {}
        """, named: "First"))
        info.gather(from: try syntaxTree(forSwift: """
        @_exported import Inner

        public class SecondFile {}
        """, named: "Second"))
        info.prepareForUse()

        XCTAssertEqual(["Inner"], info.exportedModuleNames)
    }

    /// `@_exported import` of a module that Skip does not transpile (no `ModuleExport`, not in
    /// the built-in name map) must NOT be recorded — otherwise the transpiler would later emit
    /// a Kotlin import for a package that does not exist on the JVM. This case matches
    /// `@_exported import SwiftJNI` in `SkipBridge`, where `SwiftJNI` is a native-only Swift
    /// module without a Kotlin counterpart.
    func testCodebaseInfoIgnoresNonSkipExportedModuleNames() throws {
        let info = try codebaseInfo(moduleName: "SkipBridge", dependentModules: [], swift: """
        @_exported import SwiftJNI

        public class Wrapped {}
        """)

        XCTAssertEqual([], info.exportedModuleNames)
    }

    /// `@_exported import` targets that are Swift frameworks with a built-in mapping to a Skip
    /// module (e.g. `Foundation` → `SkipFoundation`) are recorded so that the transpiler can
    /// propagate them through the existing import translation.
    func testCodebaseInfoRecordsMappedFrameworkExportedModuleNames() throws {
        let info = try codebaseInfo(moduleName: "Umbrella", dependentModules: [], swift: """
        @_exported import Foundation

        public class Wrapped {}
        """)

        XCTAssertEqual(["Foundation"], info.exportedModuleNames)
    }

    /// A `ModuleExport` round-trip through JSON preserves `exportedModuleNames`.
    func testModuleExportRoundTrip() throws {
        let inner = try moduleExport(named: "Inner")
        let info = try codebaseInfo(moduleName: "Umbrella", dependentModules: [inner], swift: """
        @_exported import Inner
        """)
        let original = CodebaseInfo.ModuleExport(of: info)
        XCTAssertEqual(["Inner"], original.exportedModuleNames ?? [])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodebaseInfo.ModuleExport.self, from: data)
        XCTAssertEqual(["Inner"], decoded.exportedModuleNames ?? [])
    }

    /// A `ModuleExport` whose source JSON predates the `x` (exportedModuleNames) key — i.e. one
    /// produced by an older skipstone version — decodes cleanly, with `exportedModuleNames` set
    /// to `nil` via the synthesized optional decoder. Other long-standing keys are present.
    func testModuleExportBackwardsCompatibleDecoding() throws {
        // Mirror the shape of a real older skipcode.json: all of the original keys present, the new
        // `x` key absent. This is the only difference between old and new encodings that we need to
        // tolerate, since older skipstone always emitted the original keys.
        let legacyJSON = #"{"m":"Legacy","p":"legacy","t":[],"a":[],"v":[],"f":[],"e":[],"stable":[]}"#
        let data = Data(legacyJSON.utf8)
        let decoded = try JSONDecoder().decode(CodebaseInfo.ModuleExport.self, from: data)
        XCTAssertEqual("Legacy", decoded.moduleName)
        XCTAssertEqual("legacy", decoded.packageName)
        XCTAssertNil(decoded.exportedModuleNames)
    }

    /// A `ModuleExport` with no `@_exported import`s stores `nil` and the synthesized encoder
    /// omits the `x` key, matching skipcode.json files produced by older skipstone versions.
    func testModuleExportEncodingOmitsEmptyExportedModuleNames() throws {
        let info = try codebaseInfo(moduleName: "Plain", swift: """
        public class A {}
        """)
        let export = CodebaseInfo.ModuleExport(of: info)
        XCTAssertNil(export.exportedModuleNames)

        let data = try JSONEncoder().encode(export)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("\"x\""), "Expected the 'x' (exportedModuleNames) key to be omitted when empty; got: \(json)")
    }

    /// Importing an umbrella module that re-exports another module in Swift should produce
    /// Kotlin imports for both the umbrella package and the re-exported package.
    func testTranspiledImportPullsInExportedModule() async throws {
        let inner = try CodebaseInfo.ModuleExport(of: codebaseInfo(moduleName: "Inner", swift: """
        public class InnerType {
            public init() {}
            public func value() -> Int { return 0 }
        }
        """))
        let umbrella = try CodebaseInfo.ModuleExport(of: codebaseInfo(moduleName: "Umbrella", dependentModules: [inner], swift: """
        @_exported import Inner

        public class UmbrellaType {
            public init() {}
        }
        """))

        try await check(dependentModules: [inner, umbrella], swift: """
        import Umbrella

        func f() -> Int {
            return InnerType().value()
        }
        """, kotlin: """
        import umbrella.module.*
        import inner.module.*

        internal fun f(): Int = InnerType().value()
        """)
    }

    /// `@_exported` propagation walks through chains: if A re-exports B and B re-exports C,
    /// then `import A` should pull in B and C.
    func testTranspiledImportPullsInTransitivelyExportedModules() async throws {
        let inner = try CodebaseInfo.ModuleExport(of: codebaseInfo(moduleName: "Inner", swift: """
        public class InnerType {
            public init() {}
            public func value() -> Int { return 0 }
        }
        """))
        let middle = try CodebaseInfo.ModuleExport(of: codebaseInfo(moduleName: "Middle", dependentModules: [inner], swift: """
        @_exported import Inner

        public class MiddleType { public init() {} }
        """))
        let umbrella = try CodebaseInfo.ModuleExport(of: codebaseInfo(moduleName: "Umbrella", dependentModules: [middle, inner], swift: """
        @_exported import Middle

        public class UmbrellaType { public init() {} }
        """))

        try await check(dependentModules: [inner, middle, umbrella], swift: """
        import Umbrella

        func f() -> Int {
            return InnerType().value()
        }
        """, kotlin: """
        import umbrella.module.*
        import middle.module.*
        import inner.module.*

        internal fun f(): Int = InnerType().value()
        """)
    }

    /// A plain (non-`@_exported`) `import` should not be propagated when the importer is used elsewhere.
    func testPlainImportIsNotPropagated() async throws {
        let inner = try CodebaseInfo.ModuleExport(of: codebaseInfo(moduleName: "Inner", swift: """
        public class InnerType { public init() {} }
        """))
        let umbrella = try CodebaseInfo.ModuleExport(of: codebaseInfo(moduleName: "Umbrella", swift: """
        import Inner

        public class UmbrellaType { public init() {} }
        """))

        try await check(dependentModules: [inner, umbrella], swift: """
        import Umbrella

        func f() -> UmbrellaType {
            return UmbrellaType()
        }
        """, kotlin: """
        import umbrella.module.*

        internal fun f(): UmbrellaType = UmbrellaType()
        """)
    }

    // MARK: - Helpers

    private func codebaseInfo(moduleName: String, dependentModules: [CodebaseInfo.ModuleExport] = [], swift: String) throws -> CodebaseInfo {
        let codebaseInfo = CodebaseInfo(moduleName: moduleName)
        codebaseInfo.dependentModules = dependentModules
        codebaseInfo.gather(from: try syntaxTree(forSwift: swift, named: moduleName))
        codebaseInfo.prepareForUse()
        return codebaseInfo
    }

    /// Build a minimal `ModuleExport` for a Skip module with no API, sufficient to register the name
    /// in `CodebaseInfo.dependentModules` for `@_exported` filtering.
    private func moduleExport(named name: String) throws -> CodebaseInfo.ModuleExport {
        return CodebaseInfo.ModuleExport(of: try codebaseInfo(moduleName: name, swift: ""))
    }

    private func syntaxTree(forSwift swift: String, named name: String) throws -> SyntaxTree {
        let srcFile = try tmpFile(named: "Source_\(name).swift", contents: swift)
        let source = Source(file: Source.FilePath(path: srcFile.path), content: swift)
        return SyntaxTree(source: source)
    }
}
