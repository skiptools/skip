import SwiftParser
import SwiftSyntax

/// Representation of the syntax tree.
class SyntaxTree {
    let source: Source
    let syntax: SourceFileSyntax
    var messages: [Message] = []
    var statements: [Statement] = []

    init(source: Source) throws {
        self.source = source
        self.syntax = Parser.parse(source: source.content)
//        self.statements = process(syntaxList: syntax.statements)
    }

//    private func process(syntaxList: CodeBlockItemListSyntax) -> [Statement] {
//        var statements: [Statement] = []
//        for syntax in syntaxList {
//            if let statement = StatementFactory.for(syntax.item) {
//                statements.append(statement)
//            }
//            if let declaration = syntax.as(DeclSyntax.self) {
//                try result.append(contentsOf: convertDeclaration(declaration))
//            } else if let statement = item.as(StmtSyntax.self) {
//                try result.append(contentsOf: convertStatement(statement))
//            }
//            else if let expression = item.as(ExprSyntax.self) {
//                if shouldConvertToStatement(expression) {
//                    try result.append(convertExpressionToStatement(expression))
//                }
//                else {
//                    try result.append(ExpressionStatement(
//                        syntax: item,
//                        range: expression.getRange(inFile: self.sourceFile),
//                        expression: convertExpression(expression)))
//                }
//            }
//            else {
//                try result.append(errorStatement(
//                    forASTNode: Syntax(statement),
//                    withMessage: "Unknown top-level statement"))
//            }
//        }
//    }
}
