import SwiftParser
import SwiftSyntax

/// Representation of the Swift syntax tree.
public class SyntaxTree: PrettyPrintable {
    let source: Source
    let syntax: SourceFileSyntax
    let preprocessorSymbols: Set<String>
    var statements: [Statement] = []

    public init(source: Source, preprocessorSymbols: Set<String> = []) {
        self.source = source
        self.preprocessorSymbols = preprocessorSymbols
        self.syntax = Parser.parse(source: source.content)
        self.statements = StatementDecoder.decode(syntaxListContainer: syntax, in: self)

        // Resolve statements breadth first so that a child can use information from its parent's siblings
        var resolveQueue: [SyntaxNode] = statements
        while !resolveQueue.isEmpty {
            let statement = resolveQueue.removeFirst()
            statement.resolve()
            statement.children.forEach { $0.parent = statement }
            resolveQueue += statement.children
        }
    }

    public var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintTree(root: source.file.name, children: statements.map { $0.prettyPrintTree })
    }

    public var messages: [Message] {
        return statements.flatMap { $0.subtreeMessages }
    }
}

