import Foundation
import SwiftParser
import SwiftSyntax

/// Manages the transpilation process.
public struct Transpiler {
    private let sourceFiles: [Source.File]
    private let packageName: String?
    private let symbols: Symbols?
    public var preprocessorSymbols: Set<String> = []

    /// Supply files to transpile.
    public init(sourceFiles: [Source.File], packageName: String? = nil, symbols: Symbols? = nil) {
        self.sourceFiles = sourceFiles
        self.packageName = packageName
        self.symbols = symbols
    }

    /// Perform transpilation, feeding results to the given handler.
    public func transpile(handler: (Transpilation) throws -> Void) async throws {
        let codebaseInfo = KotlinCodebaseInfo(packageName: packageName, symbols: symbols)
        try await withThrowingTaskGroup(of: SyntaxTree.self) { group in
            for sourceFile in sourceFiles {
                group.addTask {
                    return try SyntaxTree(source: Source(file: sourceFile), preprocessorSymbols: preprocessorSymbols, symbols: symbols)
                }
            }
            for try await syntaxTree in group {
                codebaseInfo.gather(from: syntaxTree)
            }
            codebaseInfo.finalize()
        }
        try await withThrowingTaskGroup(of: Transpilation.self) { group in
            for sourceFile in sourceFiles {
                group.addTask {
                    let syntaxTree = try SyntaxTree(source: Source(file: sourceFile), preprocessorSymbols: preprocessorSymbols, symbols: symbols)
                    let translator = KotlinTranslator(syntaxTree: syntaxTree)
                    return translator.transpile(codebaseInfo: codebaseInfo)
                }
            }
            for try await transpilation in group {
                try handler(transpilation)
            }
        }
    }
}
