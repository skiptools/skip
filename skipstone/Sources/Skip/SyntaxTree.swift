import SwiftParser
import SwiftSyntax

/// Representation of the Swift syntax tree.
struct SyntaxTree {
    let source: Source
    let syntax: SourceFileSyntax
    var statements: [Statement] = []

    init(source: Source) {
        self.source = source
        self.syntax = Parser.parse(source: source.content)
        self.statements = process(syntaxListContainer: syntax)
    }

    var messages: [Message] {
        return statements.flatMap { $0.messages }
    }

    func process<ListContainer: SyntaxListContainer>(syntaxListContainer: ListContainer) -> [Statement] {
        return process(syntaxList: syntaxListContainer.syntaxList)
    }

    func process<List: SyntaxList>(syntaxList: List) -> [Statement] {
        return syntaxList.flatMap { StatementFactory.for(syntax: $0.content, in: self) }
    }
}
