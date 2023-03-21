import Foundation
import SwiftParser
import SwiftSyntax

/// Manages the transpilation process.
public struct Transpiler {
    private let sourceFiles: [Source.File]
    private let packageName: String?
    private let symbols: Symbols?
    public var preprocessorSymbols: Set<String>
    public var plugins: [KotlinPlugin]

    /// Supply files to transpile.
    public init(sourceFiles: [Source.File], packageName: String? = nil, symbols: Symbols? = nil, preprocessorSymbols: Set<String> = [], plugins: [KotlinPlugin] = []) {
        self.sourceFiles = sourceFiles
        self.packageName = packageName
        self.symbols = symbols
        self.preprocessorSymbols = preprocessorSymbols
        self.plugins = plugins
    }

    /// Perform transpilation, feeding results to the given handler.
    public func transpile(handler: (Transpilation) throws -> Void) async throws {
        let codebaseInfo = KotlinCodebaseInfo(packageName: packageName, symbols: symbols, plugins: plugins)
        try await withThrowingTaskGroup(of: SyntaxTree.self) { group in
            for sourceFile in sourceFiles {
                group.addTask {
                    return try SyntaxTree(source: Source(file: sourceFile), preprocessorSymbols: preprocessorSymbols, symbols: symbols)
                }
            }
            for try await syntaxTree in group {
                codebaseInfo.gather(from: syntaxTree)
            }
            codebaseInfo.didGather()
        }
        try await withThrowingTaskGroup(of: Transpilation.self) { group in
            for sourceFile in sourceFiles {
                group.addTask {
                    let start = Date().timeIntervalSinceReferenceDate
                    let syntaxTree = try SyntaxTree(source: Source(file: sourceFile), preprocessorSymbols: preprocessorSymbols, symbols: symbols)
                    let translator = KotlinTranslator(syntaxTree: syntaxTree)
                    return translator.transpile(codebaseInfo: codebaseInfo, startTime: start)
                }
            }
            for try await transpilation in group {
                try handler(transpilation)
            }
        }
    }
}
