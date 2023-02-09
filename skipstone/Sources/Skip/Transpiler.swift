import Foundation
import SwiftParser
import SwiftSyntax

/// Manages the transpilation process.
public struct Transpiler {
    private let sourceFiles: [Source.File]
    private let packageName: String?
    private let symbolInfo: SymbolInfo?
    public var preprocessorSymbols: Set<String> = []

    /// Supply files to transpile.
    public init(sourceFiles: [Source.File], packageName: String? = nil, symbolInfo: SymbolInfo? = nil) {
        self.sourceFiles = sourceFiles
        self.packageName = packageName
        self.symbolInfo = symbolInfo
    }

    /// Perform transpilation, feeding results to the given handler.
    public func transpile(handler: (Transpilation) throws -> Void) async throws {
        let codebaseInfo = KotlinCodebaseInfo(packageName: packageName, symbolInfo: symbolInfo)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for sourceFile in sourceFiles {
                group.addTask {
                    let syntaxTree = try SyntaxTree(source: Source(file: sourceFile), preprocessorSymbols: preprocessorSymbols, symbolInfo: symbolInfo)
                    codebaseInfo.gather(from: syntaxTree)
                }
            }
            try await group.waitForAll()
        }

        let transpilations = try await withThrowingTaskGroup(of: Transpilation.self) { group in
            for sourceFile in sourceFiles {
                group.addTask {
                    let syntaxTree = try SyntaxTree(source: Source(file: sourceFile), preprocessorSymbols: preprocessorSymbols)
                    let translator = KotlinTranslator(syntaxTree: syntaxTree)
                    return translator.transpile(codebaseInfo: codebaseInfo)
                }
            }
            var transpilations: [Transpilation] = []
            for try await transpilation in group {
                transpilations.append(transpilation)
            }
            return transpilations
        }

        try transpilations.forEach { try handler($0) }
    }
}
