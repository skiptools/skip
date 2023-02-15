@testable import Skip
import SkipBuild
import SymbolKit
import XCTest

extension XCTestCase {
    var symbols: Symbols {
        get async throws {
            if let symbols = Self.symbols {
                return symbols
            }

            let symbolCache = SymbolCache()
            let collector = GraphCollector(extensionGraphAssociationStrategy: .extendingGraph)
            for entry in try await symbolCache.symbols(for: "SkipKotlin", accessLevel: "public") {
                collector.mergeSymbolGraph(entry.value, at: entry.key)
            }
            for entry in try await symbolCache.symbols(for: "SkipTests", accessLevel: "private") {
                collector.mergeSymbolGraph(entry.value, at: entry.key)
            }
            let (unifiedGraphs, _) = collector.finishLoading()
            let symbols = Symbols(moduleName: "SkipTests", graphs: unifiedGraphs)
            Self.symbols = symbols
            return symbols
        }
    }
    private static var symbols: Symbols?

    /// Checks that the given Swift compiles to the specified Kotlin.
    public func check(expectFailure: Bool = false, symbols: Symbols? = nil, swift: String, kotlin: String? = nil, file: StaticString = #file, line: UInt = #line) async throws {
        guard let kotlin else {
            return
        }

        let srcFile = try tmpFile(named: "Source.swift", contents: swift)
        let tp = Transpiler(sourceFiles: [Source.File(path: srcFile.path)], symbols: symbols)
        try await tp.transpile { transpilation in
            //print("transpilation:", transpilation.output)
            var content = transpilation.output.content
            let autoImportPrefix = "import skip.kotlin."
            content = content.split(separator: "\n", omittingEmptySubsequences: false).filter({ !$0.hasPrefix(autoImportPrefix) }).joined(separator: "\n")
            if expectFailure {
                XCTExpectFailure()
            }
            XCTAssertEqual(kotlin.trimmingCharacters(in: .whitespacesAndNewlines), content.trimmingCharacters(in: .whitespacesAndNewlines), file: file, line: line)
        }
    }

    /// Creates a temporary file with the given name and optional contents.
    public func tmpFile(named fileName: String, contents: String? = nil) throws -> URL {
        let tmpDir = URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tmpFile = URL(fileURLWithPath: fileName, isDirectory: false, relativeTo: tmpDir)
        if let contents = contents {
            try contents.write(to: tmpFile, atomically: true, encoding: .utf8)
        }
        return tmpFile
    }
}
