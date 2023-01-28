import SwiftParser
import SwiftSyntax

/// Representation of the Swift syntax tree.
public class SyntaxTree {
    let source: Source
    let syntax: SourceFileSyntax
    let preprocessorSymbols: Set<String>
    var statements: [Statement] = []

    public init(source: Source, preprocessorSymbols: Set<String> = []) {
        self.source = source
        self.preprocessorSymbols = preprocessorSymbols
        self.syntax = Parser.parse(source: source.content)
        self.statements = process(syntaxListContainer: syntax, parent: nil)
    }

    public var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintTree(root: source.file.name, children: statements.map { $0.prettyPrintTree })
    }

    public var messages: [Message] {
        return statements.flatMap { $0.messages }
    }

    func process<ListContainer: SyntaxListContainer>(syntaxListContainer: ListContainer, parent: Statement?) -> [Statement] {
        return process(syntaxList: syntaxListContainer.syntaxList, parent: parent)
    }

    func process<List: SyntaxList>(syntaxList: List, parent: Statement?) -> [Statement] {
        return syntaxList.flatMap { StatementFactory.for(syntax: $0.content, in: self, parent: parent) }
    }
}
