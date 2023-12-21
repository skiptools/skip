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
    public func transpile(handler: (Transpilation) async throws -> Void) async throws {
        guard !sourceFiles.isEmpty else {
            return
        }

        // First create syntax trees used to populate codebase info
        codebaseInfo.kotlin = KotlinCodebaseInfo(packageName: packageName)
        var symbolFiles: Set<Source.FilePath> = []
        try await withThrowingTaskGroup(of: SyntaxTree.self) { group in
            for sourceFile in sourceFiles {
                group.addTask {
                    return try SyntaxTree(source: Source(file: sourceFile), preprocessorSymbols: preprocessorSymbols)
                }
            }
            for try await syntaxTree in group {
                codebaseInfo.gather(from: syntaxTree)
                transformers.forEach { $0.gather(from: syntaxTree) }
                if syntaxTree.isSymbolFile {
                    symbolFiles.insert(syntaxTree.source.file)
                }
            }
            codebaseInfo.prepareForUse()
            transformers.forEach { $0.prepareForUse(codebaseInfo: codebaseInfo) }
        }
        // Next perform transpilation with populated info
        try await withThrowingTaskGroup(of: Transpilation.self) { group in
            for sourceFile in sourceFiles where !symbolFiles.contains(sourceFile) {
                group.addTask {
                    let start = Date().timeIntervalSinceReferenceDate
                    let syntaxTree = try SyntaxTree(source: Source(file: sourceFile), preprocessorSymbols: preprocessorSymbols, codebaseInfo: codebaseInfo)
                    let translator = KotlinTranslator(syntaxTree: syntaxTree)
                    return translator.transpile(codebaseInfo: codebaseInfo, transformers: transformers, startTime: start)
                }
            }
            for try await transpilation in group {
                try await handler(transpilation)
            }
        }

        // Suffix the generated file with "Tests" to avoid clashes with the primary modules `PackageSupportKt` class (https://github.com/skiptools/skip/issues/66)
        let isTestModule = codebaseInfo.moduleName?.hasSuffix("Tests") == true

        // Finally create an additional source file for any package-level code
        if let packageSupportTranspilation = KotlinTranslator.transpilePackageSupport(sourceFile: sourceFiles[0].kotlinPackageSupport(tests: isTestModule), codebaseInfo: codebaseInfo, transformers: transformers) {
            try await handler(packageSupportTranspilation)
        }
    }
}
