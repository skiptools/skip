import SwiftParser
import SwiftSyntax

/// Representation of the Swift syntax tree.
public class SyntaxTree: PrettyPrintable {
    let source: Source
    let syntax: SourceFileSyntax
    let preprocessorSymbols: Set<String>
    let root: CodeBlock = CodeBlock(statements: [])

    /// - Note: `unavailableAPI` is not used when `codebaseInfo` is available
    public init(source: Source, preprocessorSymbols: Set<String> = [], codebaseInfo: CodebaseInfo? = nil, unavailableAPI: UnavailableAPI? = nil) {
        self.source = source
        self.preprocessorSymbols = preprocessorSymbols
        self.syntax = Parser.parse(source: source.content)
        self.root.statements = StatementDecoder.decode(syntaxListContainer: syntax, in: self)

        // Resolve nodes breadth first so that a child can use information from its parent's siblings
        let importedModuleNames = root.statements.importedModuleNames
        let moduleContext = ModuleContext(codebaseInfo: codebaseInfo, importedModuleNames: importedModuleNames, sourceFile: source.file)
        var resolveQueue: [SyntaxNode] = [root]
        while !resolveQueue.isEmpty {
            let node = resolveQueue.removeFirst()
            node.resolveAttributes(in: self, context: moduleContext)
            node.children.forEach { $0.parent = node }
            resolveQueue += node.children
        }

        let codebaseContext = codebaseInfo?.context(importedModuleNames: importedModuleNames, source: source)
        let typeContext = TypeInferenceContext(codebaseInfo: codebaseContext, unavailableAPI: unavailableAPI, source: source)
        let _ = root.inferTypes(context: typeContext, expecting: .none)
    }

    public var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintTree(root: source.file.name, children: [root.prettyPrintTree])
    }

    public var messages: [Message] {
        return root.subtreeMessages
    }
}
