import Foundation
import SwiftParser
import SwiftSyntax

/// Manages the transpilation process.
public struct Transpiler {
    public let sourceFiles: [Source.File]

    /// Supply files to transpile. Only `.swift` files will be processed.
    public init(sourceFiles: [Source.File]) {
        self.sourceFiles = sourceFiles
    }

    /// Perform transpilation, feeding results to the given handler.
    public func transpile(handler: (Transpilation) throws -> Void) async throws {
        let codebaseInfo = CodebaseInfo()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for sourceFile in sourceFiles {
                group.addTask {
                    let syntaxTree = try SyntaxTree(source: Source(file: sourceFile))
                    try codebaseInfo.gather(from: syntaxTree)
                }
            }
            try await group.waitForAll()
        }

        let transpilations = try await withThrowingTaskGroup(of: Transpilation.self) { group in
            let translator = KotlinTranslator(codebaseInfo: codebaseInfo)
            for sourceFile in sourceFiles {
                group.addTask {
                    let syntaxTree = try SyntaxTree(source: Source(file: sourceFile))
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
