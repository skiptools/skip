// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

@_spi(ExperimentalLanguageFeatures) import SwiftParser
import SwiftSyntax

/// Representation of the Swift syntax tree.
public final class SyntaxTree: PrettyPrintable {
    let source: Source
    let preprocessorSymbols: Set<String>
    let root: CodeBlock = CodeBlock(statements: [])

    /// - Note: `unavailableAPI` is not used when `codebaseInfo` is available
    public init(source: Source, isBridgeFile: Bool = false, autoBridge: AutoBridge = .default, decodeLevel: DecodeLevel = .full, preprocessorSymbols: Set<String> = [], codebaseInfo: CodebaseInfo? = nil, unavailableAPI: UnavailableAPI? = nil) {
        self.source = source
        self.isBridgeFile = isBridgeFile
        self.autoBridge = autoBridge
        self.decodeLevel = decodeLevel
        self.preprocessorSymbols = preprocessorSymbols
        var parser = Parser(source.content, experimentalFeatures: [])
        let syntax = SourceFileSyntax.parse(from: &parser)
        self.root.statements = StatementDecoder.decode(syntaxListContainer: syntax, context: DecodeContext(), in: self)

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

    /// Whether this is a file to bridge to Kotlin rather than one to transpile.
    public let isBridgeFile: Bool

    /// What API in this file to auto-bridge.
    public let autoBridge: AutoBridge

    /// The decode level to use when processing this file.
    public let decodeLevel: DecodeLevel

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
