import SwiftParser
import SwiftSyntax

/// Representation of the Swift syntax tree.
public class SyntaxTree: PrettyPrintable {
    let source: Source
    let syntax: SourceFileSyntax
    let preprocessorSymbols: Set<String>
    var statements: [Statement] = []

    public init(source: Source, preprocessorSymbols: Set<String> = [], symbolInfo: SymbolInfo? = nil) {
        self.source = source
        self.preprocessorSymbols = preprocessorSymbols
        self.syntax = Parser.parse(source: source.content)
        self.statements = StatementDecoder.decode(syntaxListContainer: syntax, in: self)

        // Resolve nodes breadth first so that a child can use information from its parent's siblings
        var resolveQueue: [SyntaxNode] = statements
        while !resolveQueue.isEmpty {
            let node = resolveQueue.removeFirst()
            node.resolveAttributes()
            node.children.forEach { $0.parent = node }
            resolveQueue += node.children
        }

        let context = TypeInferenceContext(symbolInfo: symbolInfo, sourceFile: source.file, statements: statements)
        statements.forEach { $0.inferTypes(context: context, expecting: .none) }
    }

    public var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintTree(root: source.file.name, children: statements.map { $0.prettyPrintTree })
    }

    public var messages: [Message] {
        return statements.flatMap { $0.subtreeMessages }
    }
}

