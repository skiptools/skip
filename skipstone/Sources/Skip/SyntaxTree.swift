import SwiftParser
import SwiftSyntax

/// Representation of the Swift syntax tree.
public class SyntaxTree: PrettyPrintable {
    let source: Source
    let syntax: SourceFileSyntax
    let preprocessorSymbols: Set<String>
    private(set) var root: CodeBlockStatement = CodeBlockStatement(statements: [])

    public init(source: Source, preprocessorSymbols: Set<String> = [], symbols: Symbols? = nil) {
        self.source = source
        self.preprocessorSymbols = preprocessorSymbols
        self.syntax = Parser.parse(source: source.content)
        self.root = CodeBlockStatement(statements: StatementDecoder.decode(syntaxListContainer: syntax, in: self))

        // Resolve nodes breadth first so that a child can use information from its parent's siblings
        var resolveQueue: [SyntaxNode] = [root]
        while !resolveQueue.isEmpty {
            let node = resolveQueue.removeFirst()
            node.resolveAttributes()
            node.children.forEach { $0.parent = node }
            resolveQueue += node.children
        }

        let context = TypeInferenceContext(symbols: symbols, sourceFile: source.file, statements: root.statements)
        let _ = root.inferTypes(context: context, expecting: .none)
    }

    public var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintTree(root: source.file.name, children: [root.prettyPrintTree])
    }

    public var messages: [Message] {
        return root.subtreeMessages
    }
}
