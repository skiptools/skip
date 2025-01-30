import Foundation
import SwiftParser
import SwiftSyntax

/// Manages the transpilation process.
public struct Transpiler {
    private let packageName: String?
    private let transpileFiles: [Source.FilePath]
    private let bridgeFiles: [Source.FilePath]
    private let autoBridge: AutoBridge
    private let isBridgeGatherEnabled: Bool
    private let codebaseInfo: CodebaseInfo
    public var preprocessorSymbols: Set<String>
    public var transformers: [KotlinTransformer]

    /// Supply files to transpile.
    public init(packageName: String? = nil, transpileFiles: [Source.FilePath], bridgeFiles: [Source.FilePath] = [], autoBridge: AutoBridge = .none, isBridgeGatherEnabled: Bool = false, codebaseInfo: CodebaseInfo, preprocessorSymbols: Set<String> = [], transformers: [KotlinTransformer] = []) {
        self.packageName = packageName
        self.transpileFiles = transpileFiles
        self.bridgeFiles = bridgeFiles
        self.autoBridge = autoBridge
        self.isBridgeGatherEnabled = isBridgeGatherEnabled
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
        try await withThrowingTaskGroup(of: (syntaxTree: SyntaxTree, gatherOnly: Bool)?.self) { group in
            for transpileFile in transpileFiles {
                group.addTask {
                    let syntaxTree = try SyntaxTree(source: Source(file: transpileFile), autoBridge: autoBridge, preprocessorSymbols: preprocessorSymbols)
                    return (syntaxTree, syntaxTree.isSymbolFile)
                }
            }
            for bridgeFile in bridgeFiles {
                group.addTask {
                    let bridgeSource = try Source(file: bridgeFile)
                    // We may be able to skip parsing most bridge files if they don't contain bridgable code. Note that
                    // we may get errors from unsupported Swift if we're doing a full decode here, but they won't
                    // bubble up to the user because these trees are only used to gather information, and we re-parse
                    // for only bridging below
                    var shouldBridge = bridgeSource.content.contains("@bridge") || bridgeSource.content.contains("SkipFuseUI")
                    if autoBridge == .public {
                        shouldBridge = shouldBridge || bridgeSource.content.contains("public") || bridgeSource.content.contains("open")
                    }
                    let bridgeDecodeLevel: DecodeLevel = isBridgeGatherEnabled ? .full : shouldBridge ? .api : .none
                    if bridgeDecodeLevel == .none {
                        return nil
                    } else {
                        let syntaxTree = SyntaxTree(source: bridgeSource, isBridgeFile: true, autoBridge: autoBridge, decodeLevel: bridgeDecodeLevel, preprocessorSymbols: preprocessorSymbols)
                        return (syntaxTree, !shouldBridge)
                    }
                }
            }
            for try await result in group {
                guard let result else {
                    continue
                }
                // Allow transformers to gather first so that they can add information to trees
                transformers.forEach { $0.gather(from: result.syntaxTree) }
                codebaseInfo.gather(from: result.syntaxTree)
                if !result.gatherOnly {
                    if result.syntaxTree.isBridgeFile {
                        bridgeSources.append(result.syntaxTree.source)
                    } else {
                        sources.append(result.syntaxTree.source)
                    }
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
                    let syntaxTree = SyntaxTree(source: source, autoBridge: autoBridge, preprocessorSymbols: preprocessorSymbols, codebaseInfo: codebaseInfo)
                    let translator = KotlinTranslator(syntaxTree: syntaxTree)
                    return translator.transpile(codebaseInfo: codebaseInfo, transformers: transformers, startTime: start)
                }
            }
            for bridgeSource in bridgeSources {
                group.addTask {
                    let start = Date().timeIntervalSinceReferenceDate
                    let syntaxTree = SyntaxTree(source: bridgeSource, isBridgeFile: true, autoBridge: autoBridge, decodeLevel: .api, preprocessorSymbols: preprocessorSymbols, codebaseInfo: codebaseInfo)
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

        // Finally create additional source files for any package-level code.
        // Suffix the generated transpilation files with "Tests" to avoid clashes with the primary
        // module's `PackageSupportKt` class (https://github.com/skiptools/skip/issues/66)
        let isTestModule = codebaseInfo.moduleName?.hasSuffix("Tests") == true
        let packageSupportFile = (transpileFiles.first ?? bridgeFiles.first!).kotlinPackageSupport(tests: isTestModule)
        let packageSupportTranspilations = KotlinTranslator.transpilePackageSupport(sourceFile: packageSupportFile, codebaseInfo: codebaseInfo, transformers: transformers)
        for transpilation in packageSupportTranspilations {
            try await handler(transpilation)
        }
    }
}
