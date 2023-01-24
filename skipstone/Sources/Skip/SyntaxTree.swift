import SwiftParser
import SwiftSyntax

/// Representation of the syntax tree.
struct SyntaxTree {
    let source: Source
    let syntax: SourceFileSyntax

    init(source: Source) throws {
        self.source = source
        self.syntax = Parser.parse(source: source.content)
    }
}
