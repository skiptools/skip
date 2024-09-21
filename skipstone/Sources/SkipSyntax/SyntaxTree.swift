@_spi(ExperimentalLanguageFeatures) import SwiftParser
import SwiftSyntax

/// Representation of the Swift syntax tree.
public final class SyntaxTree: PrettyPrintable {
    let source: Source
    let syntax: SourceFileSyntax
    let preprocessorSymbols: Set<String>
    let root: CodeBlock = CodeBlock(statements: [])

    /// - Note: `unavailableAPI` is not used when `codebaseInfo` is available
    public convenience init(source: Source, preprocessorSymbols: Set<String> = [], codebaseInfo: CodebaseInfo? = nil, unavailableAPI: UnavailableAPI? = nil) {
        self.init(source: source, isBridgeFile: false, preprocessorSymbols: preprocessorSymbols, codebaseInfo: codebaseInfo, unavailableAPI: unavailableAPI)
    }

    public convenience init?(bridgeSource: Source, preprocessorSymbols: Set<String> = [], codebaseInfo: CodebaseInfo? = nil, unavailableAPI: UnavailableAPI? = nil) {
        // Most compiled files do not contain bridging code
        guard bridgeSource.content.contains("@bridge") else {
            return nil
        }
        self.init(source: bridgeSource, isBridgeFile: true, preprocessorSymbols: preprocessorSymbols, codebaseInfo: codebaseInfo, unavailableAPI: unavailableAPI)
    }

    private init(source: Source, isBridgeFile: Bool, preprocessorSymbols: Set<String> = [], codebaseInfo: CodebaseInfo? = nil, unavailableAPI: UnavailableAPI? = nil) {
        self.source = source
        self.isBridgeFile = isBridgeFile
        self.preprocessorSymbols = preprocessorSymbols
        var parser = Parser(source.content, experimentalFeatures: [.sendingArgsAndResults])
        self.syntax = SourceFileSyntax.parse(from: &parser)
        self.root.statements = StatementDecoder.decode(syntaxListContainer: syntax, in: self)

        let importedModuleNames = root.statements.importedModulePaths.compactMap(\.moduleName)
        let codebaseContext = codebaseInfo?.context(importedModuleNames: importedModuleNames, sourceFile: source.file)
        let typeResolutionContext = TypeResolutionContext(codebaseInfo: codebaseContext)
        root.resolveSubtreeAttributes(in: self, context: typeResolutionContext)

        let typeInferenceContext = TypeInferenceContext(codebaseInfo: codebaseContext, unavailableAPI: unavailableAPI, source: source)
        let _ = root.inferTypes(context: typeInferenceContext, expecting: .none)
    }

    /// Whether this syntax tree content is used to provide the transpiler with Swift symbols and is not a transpilation target.
    public var isSymbolFile: Bool {
        return root.statements.contains(where: { $0.extras?.isSymbolFile == true })
    }

    /// Whether this syntax tree content is used to process Swift bridging code and is not a transpilation target.
    public let isBridgeFile: Bool

    public var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintTree(root: source.file.name, children: [root.prettyPrintTree])
    }

    public var messages: [Message] {
        guard !isSymbolFile else {
            return []
        }
        return root.subtreeMessages
    }
}
