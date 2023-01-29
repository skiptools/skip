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
        self.statements.forEach { $0.resolve(parent: nil) }
    }

    public var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintTree(root: source.file.name, children: statements.map { $0.prettyPrintTree })
    }

    public var messages: [Message] {
        return statements.flatMap { $0.messages }
    }
}
