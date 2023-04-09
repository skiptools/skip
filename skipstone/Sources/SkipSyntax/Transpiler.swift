import Foundation
import SwiftParser
import SwiftSyntax

/// Manages the transpilation process.
public struct Transpiler {
    private let packageName: String?
    private let sourceFiles: [Source.FilePath]
    private let codebaseInfo: CodebaseInfo
    public var preprocessorSymbols: Set<String>
    public var transformers: [KotlinTransformer]

    /// Supply files to transpile.
    public init(packageName: String? = nil, sourceFiles: [Source.FilePath], codebaseInfo: CodebaseInfo, preprocessorSymbols: Set<String> = [], transformers: [KotlinTransformer] = []) {
        self.packageName = packageName
        self.sourceFiles = sourceFiles
        self.codebaseInfo = codebaseInfo
        self.preprocessorSymbols = preprocessorSymbols
        self.transformers = transformers
    }

    /// Perform transpilation, feeding results to the given handler.
    public func transpile(handler: (Transpilation) throws -> Void) async throws {
        // First create syntax trees used to populate codebase info
        codebaseInfo.kotlin = KotlinCodebaseInfo(packageName: packageName, transformers: transformers)
        try await withThrowingTaskGroup(of: SyntaxTree.self) { group in
            for sourceFile in sourceFiles {
                group.addTask {
                    return try SyntaxTree(source: Source(file: sourceFile), preprocessorSymbols: preprocessorSymbols)
                }
            }
            for try await syntaxTree in group {
                codebaseInfo.gather(from: syntaxTree)
            }
            codebaseInfo.prepareForUse()
        }
        // Next perform transpilation with populated info
        try await withThrowingTaskGroup(of: Transpilation.self) { group in
            for sourceFile in sourceFiles {
                group.addTask {
                    let start = Date().timeIntervalSinceReferenceDate
                    let syntaxTree = try SyntaxTree(source: Source(file: sourceFile), preprocessorSymbols: preprocessorSymbols, codebaseInfo: codebaseInfo)
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
