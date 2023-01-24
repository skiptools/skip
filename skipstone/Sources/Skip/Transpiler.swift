import Foundation
import SwiftParser
import SwiftSyntax

/// Manages the transpilation process.
public struct Transpiler {
    public let sourceFiles: [SourceFile]

    /// Supply files to transpile. Only `.swift` files will be processed.
    public init(sourceFiles: [SourceFile]) {
        self.sourceFiles = sourceFiles
    }

    /// Perform transpilation, feeding results to the given handler.
    public func transpile(handler: (Transpilation) throws -> Void) async throws {
        let syntaxTrees = try await withThrowingTaskGroup(of: SyntaxTree.self) { group in
            for sourceFile in sourceFiles {
                group.addTask {
                    return try SyntaxTree(sourceFile: sourceFile)
                }
            }
            var syntaxTrees: [SyntaxTree] = []
            for try await syntaxTree in group {
                syntaxTrees.append(syntaxTree)
            }
            return syntaxTrees
        }

        let codebaseInfo = try await Task {
            return try CodebaseInfo(syntaxTrees: syntaxTrees)
        }.value

        let transpilations = try await withThrowingTaskGroup(of: Transpilation.self) { group in
            let translator = KotlinTranslator(codebaseInfo: codebaseInfo)
            for syntaxTree in syntaxTrees {
                group.addTask {
                    return try translator.translate(syntaxTree)
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
