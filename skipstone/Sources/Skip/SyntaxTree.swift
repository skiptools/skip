import SwiftParser
import SwiftSyntax

/// Representation of the Swift syntax tree.
public struct SyntaxTree {
    let source: Source
    let syntax: SourceFileSyntax
    let preprocessorSymbols: Set<String>
    var statements: [Statement] = []

    public init(source: Source, preprocessorSymbols: Set<String> = []) {
        self.source = source
        self.preprocessorSymbols = preprocessorSymbols
        self.syntax = Parser.parse(source: source.content)
        self.statements = process(syntaxListContainer: syntax)
    }

    public var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintTree(root: source.file.name, children: statements.map { $0.prettyPrintTree })
    }

    public var messages: [Message] {
        return statements.flatMap { $0.messages }
    }

    func process<ListContainer: SyntaxListContainer>(syntaxListContainer: ListContainer) -> [Statement] {
        return process(syntaxList: syntaxListContainer.syntaxList)
    }

    func process<List: SyntaxList>(syntaxList: List) -> [Statement] {
        return syntaxList.flatMap { StatementFactory.for(syntax: $0.content, in: self) }
    }
}
