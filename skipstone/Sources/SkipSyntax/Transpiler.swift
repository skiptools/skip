import Foundation
import SwiftParser
import SwiftSyntax

/// Manages the transpilation process.
public struct Transpiler {
    private let packageName: String?
    private let sourceFiles: [Source.FilePath]
    private let codebaseInfo: CodebaseInfo
    private let symbols: SymbolsType?
    public var preprocessorSymbols: Set<String>
    public var plugins: [KotlinPlugin]

    /// Supply files to transpile.
    public init(packageName: String? = nil, sourceFiles: [Source.FilePath], codebaseInfo: CodebaseInfo, symbols: SymbolsType? = nil, preprocessorSymbols: Set<String> = [], plugins: [KotlinPlugin] = []) {
        self.packageName = packageName
        self.sourceFiles = sourceFiles
        self.codebaseInfo = codebaseInfo
        self.symbols = symbols
        self.preprocessorSymbols = preprocessorSymbols
        self.plugins = plugins
    }

    /// Perform transpilation, feeding results to the given handler.
    public func transpile(handler: (Transpilation) throws -> Void) async throws {
        // First create syntax trees used to populate codebase info
        let kotlinCodebaseInfo = KotlinCodebaseInfo(packageName: packageName, codebaseInfo: codebaseInfo, symbols: symbols, plugins: plugins)
        try await withThrowingTaskGroup(of: SyntaxTree.self) { group in
            for sourceFile in sourceFiles {
                group.addTask {
                    return try SyntaxTree(source: Source(file: sourceFile), preprocessorSymbols: preprocessorSymbols)
                }
            }
            for try await syntaxTree in group {
                kotlinCodebaseInfo.gather(from: syntaxTree)
            }
            kotlinCodebaseInfo.prepareForUse()
        }
        // Next perform transpilation with populated info
        try await withThrowingTaskGroup(of: Transpilation.self) { group in
            for sourceFile in sourceFiles {
                group.addTask {
                    let start = Date().timeIntervalSinceReferenceDate
                    let syntaxTree = try SyntaxTree(source: Source(file: sourceFile), preprocessorSymbols: preprocessorSymbols, codebaseInfo: codebaseInfo, symbols: symbols)
                    let translator = KotlinTranslator(syntaxTree: syntaxTree)
                    return translator.transpile(codebaseInfo: kotlinCodebaseInfo, startTime: start)
                }
            }
            for try await transpilation in group {
                try handler(transpilation)
            }
        }
    }
}
