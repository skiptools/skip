import Foundation
import SwiftParser
import SwiftSyntax

/// Representation of the syntax tree.
struct SyntaxTree {
    let sourceFile: SourceFile
    let syntax: SourceFileSyntax

    init(sourceFile: SourceFile) throws {
        self.sourceFile = sourceFile
        self.syntax = try Parser.parse(source: sourceFile.content)
    }
}
