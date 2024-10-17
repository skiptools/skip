import Foundation
import SwiftParser
import SwiftSyntax

/// Manages the transpilation process.
public struct Transpiler {
    private let packageName: String?
    private let transpileFiles: [Source.FilePath]
    private let bridgeFiles: [Source.FilePath]
    private let codebaseInfo: CodebaseInfo
    public var preprocessorSymbols: Set<String>
    public var transformers: [KotlinTransformer]

    /// Supply files to transpile.
    public init(packageName: String? = nil, transpileFiles: [Source.FilePath], bridgeFiles: [Source.FilePath] = [], codebaseInfo: CodebaseInfo, preprocessorSymbols: Set<String> = [], transformers: [KotlinTransformer] = []) {
        self.packageName = packageName
        self.transpileFiles = transpileFiles
        self.bridgeFiles = bridgeFiles
        self.codebaseInfo = codebaseInfo
        self.preprocessorSymbols = preprocessorSymbols
        self.transformers = transformers
    }

    /// Perform transpilation, feeding results to the given handler.
    public func transpile(handler: (Transpilation) async throws -> Void) async throws {
        guard !transpileFiles.isEmpty || !bridgeFiles.isEmpty else {
            return
        }

        // First create syntax trees used to populate codebase info
        codebaseInfo.kotlin = KotlinCodebaseInfo(packageName: packageName)
        var sources: [Source] = []
        var bridgeSources: [Source] = []
        try await withThrowingTaskGroup(of: SyntaxTree?.self) { group in
            for transpileFile in transpileFiles {
                group.addTask {
                    return try SyntaxTree(source: Source(file: transpileFile), preprocessorSymbols: preprocessorSymbols)
                }
            }
            for bridgeFile in bridgeFiles {
                group.addTask {
                    let bridgeSource = try Source(file: bridgeFile)
                    // Most compiled files do not contain bridging code
                    guard bridgeSource.content.contains("@BridgeTo") || bridgeSource.content.contains("@bridgeTo") else {
                        return nil
                    }
                    return SyntaxTree(source: bridgeSource, isBridgeFile: true, preprocessorSymbols: preprocessorSymbols)
                }
            }
            for try await syntaxTree in group {
                guard let syntaxTree else {
                    continue
                }
                codebaseInfo.gather(from: syntaxTree)
                transformers.forEach { $0.gather(from: syntaxTree) }
                if syntaxTree.isBridgeFile {
                    bridgeSources.append(syntaxTree.source)
                } else if !syntaxTree.isSymbolFile {
                    sources.append(syntaxTree.source)
                }
            }
        }

        codebaseInfo.prepareForUse()
        transformers.forEach { $0.prepareForUse(codebaseInfo: codebaseInfo) }

        // Next perform transpilation with populated info
        try await withThrowingTaskGroup(of: [Transpilation].self) { group in
            for source in sources {
                group.addTask {
                    let start = Date().timeIntervalSinceReferenceDate
                    let syntaxTree = SyntaxTree(source: source, preprocessorSymbols: preprocessorSymbols, codebaseInfo: codebaseInfo)
                    let translator = KotlinTranslator(syntaxTree: syntaxTree)
                    return translator.transpile(codebaseInfo: codebaseInfo, transformers: transformers, startTime: start)
                }
            }
            for bridgeSource in bridgeSources {
                group.addTask {
                    let start = Date().timeIntervalSinceReferenceDate
                    let syntaxTree = SyntaxTree(source: bridgeSource, isBridgeFile: true, preprocessorSymbols: preprocessorSymbols, codebaseInfo: codebaseInfo)
                    let translator = KotlinTranslator(syntaxTree: syntaxTree)
                    return translator.transpile(codebaseInfo: codebaseInfo, transformers: transformers, startTime: start)
                }
            }
            for try await transpilations in group {
                for transpilation in transpilations {
                    try await handler(transpilation)
                }
            }
        }

        // Finally create an additional source files for any package-level code.
        // Suffix the generated file with "Tests" to avoid clashes with the primary modules `PackageSupportKt` class (https://github.com/skiptools/skip/issues/66)
        let isTestModule = codebaseInfo.moduleName?.hasSuffix("Tests") == true
        if let packageSupportTranspilation = KotlinTranslator.transpilePackageSupport(sourceFile: (transpileFiles.first ?? bridgeFiles.first!).kotlinPackageSupport(tests: isTestModule), codebaseInfo: codebaseInfo, transformers: transformers) {
            try await handler(packageSupportTranspilation)
        }
    }
}
