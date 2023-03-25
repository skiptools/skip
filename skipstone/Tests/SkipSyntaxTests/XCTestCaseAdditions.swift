import SkipBuild
@testable import SkipSyntax
import SymbolKit
import XCTest

extension XCTestCase {
    /// Whether to use the locally cached symbols for SkipLib syntax testing
    static let shouldUseLocalSymbols: Bool = true

    var symbols: Symbols {
        get async throws {
            #if os(Linux)
            // FIXME: symbol generation not currently working on linux, so those tests will be disabled
            throw XCTSkip("symbols not available on Linux")
            #endif
            if let symbols = Self.symbols {
                return symbols
            }

            let collector = GraphCollector(extensionGraphAssociationStrategy: .extendingGraph)

            if Self.shouldUseLocalSymbols == true {
                // this would only work if we built SkipLib first
                //let skipLibSymbols = try await SkipSystem.extractSymbols(moduleNames: ["SkipLib"], accessLevel: "public")
                let skipLibSymbolsURL = try XCTUnwrap(Bundle.module.url(forResource: "SkipLib.symbols.json", withExtension: nil, subdirectory: "symbols"))
                let skipLibSymbols = try SymbolGraph(fromJSON: Data(contentsOf: skipLibSymbolsURL))
                collector.mergeSymbolGraph(skipLibSymbols, at: skipLibSymbolsURL)

                let symbolGraph = try await SkipSystem.extractSymbols(moduleNames: ["SkipSyntaxTests"], accessLevel: "private")
                if symbolGraph.isEmpty {
                    XCTFail("unable to load dynamic symbol graph")

                    // fall back to using the caches (and potentially out-of-date) symbols
                    //let skipSyntaxTestsSymbolsURL = try XCTUnwrap(Bundle.module.url(forResource: "SkipSyntaxTests.symbols.json", withExtension: nil, subdirectory: "symbols"))
                    //let skipSyntaxTestsSymbols = try SymbolGraph(fromJSON: Data(contentsOf: skipSyntaxTestsSymbolsURL))
                } else {
                    for (skipSyntaxTestsSymbolsURL, skipSyntaxTestsSymbols) in symbolGraph {
                        collector.mergeSymbolGraph(skipSyntaxTestsSymbols, at: skipSyntaxTestsSymbolsURL)
                    }
                }

            } else {
                let symbolCache = SymbolCache()

                for entry in try await symbolCache.symbols(for: "SkipLib", accessLevel: "public") {
                    collector.mergeSymbolGraph(entry.value, at: entry.key)
                }
                for entry in try await symbolCache.symbols(for: "SkipSyntaxTests", accessLevel: "private") {
                    collector.mergeSymbolGraph(entry.value, at: entry.key)
                }
            }

            let (unifiedGraphs, _) = collector.finishLoading()
            let symbols = Symbols(moduleName: "SkipSyntaxTests", graphs: unifiedGraphs)
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

        #if os(Linux)
        // FIXME: symbol generation not currently working on linux, so tests that use symbols are disabled
        if symbols == nil {
            throw XCTSkip("symbol-reliant tests not yet working on Linux")
        }
        #endif

        let srcFile = try tmpFile(named: "Source.swift", contents: swift)
        let tp = Transpiler(sourceFiles: [Source.FilePath(path: srcFile.path)], symbols: symbols)
        try await tp.transpile { transpilation in
            let content = trimmedContent(transpilation: transpilation)
            let messagesString = transpilation.messages.map(\.description).joined(separator: ",")
            if !transpilation.messages.isEmpty && !expectFailure {
                XCTFail("Transpilation produced unexpected messages: \(messagesString)")
            }
            if expectFailure {
                XCTExpectFailure()
            }
            XCTAssertEqual(kotlin.trimmingCharacters(in: .whitespacesAndNewlines), content.trimmingCharacters(in: .whitespacesAndNewlines), messagesString, file: file, line: line)
        }
    }

    /// Checks that the given Swift generates a message when transpiled.
    public func checkProducesMessage(symbols: Symbols? = nil, swift: String, file: StaticString = #file, line: UInt = #line) async throws {
        let srcFile = try tmpFile(named: "Source.swift", contents: swift)
        let tp = Transpiler(sourceFiles: [Source.FilePath(path: srcFile.path)], symbols: symbols)
        try await tp.transpile { transpilation in
            XCTAssertTrue(!transpilation.messages.isEmpty, trimmedContent(transpilation: transpilation))
            transpilation.messages.forEach { print("Received expected message: \($0)") }
        }
    }

    private func trimmedContent(transpilation: Transpilation) -> String {
        let content = transpilation.output.content
        let autoImportPrefix = "import skip.lib."
        return content.split(separator: "\n", omittingEmptySubsequences: false).filter({ !$0.hasPrefix(autoImportPrefix) }).joined(separator: "\n")
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
