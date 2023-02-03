import SwiftSyntax

/// `true, false`
class BooleanLiteral: Expression {
    let literal: Bool

    init(literal: Bool, syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil) {
        self.literal = literal
        super.init(type: .booleanLiteral, syntax: syntax, file: file, range: range)
    }

    override class func decode(syntax: Syntax, in syntaxTree: SyntaxTree) -> Expression? {
        guard syntax.kind == .booleanLiteralExpr, let booleanLiteralExpr = syntax.as(BooleanLiteralExprSyntax.self) else {
            return nil
        }
        let literal = booleanLiteralExpr.booleanLiteral.text == "true"
        return BooleanLiteral(literal: literal, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source))
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: String(describing: literal))]
    }
}

/// `1, 1.0`
class NumericLiteral: Expression {
    let literal: String
    let isFloatingPoint: Bool

    init(literal: String, isFloatingPoint: Bool, syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil) {
        self.literal = literal
        self.isFloatingPoint = isFloatingPoint
        super.init(type: .numericLiteral, syntax: syntax, file: file, range: range)
    }

    override class func decode(syntax: Syntax, in syntaxTree: SyntaxTree) -> Expression? {
        let literal: String
        let isFloatingPoint: Bool
        if syntax.kind == .floatLiteralExpr, let floatLiteralExpr = syntax.as(FloatLiteralExprSyntax.self) {
            literal = floatLiteralExpr.floatingDigits.text
            isFloatingPoint = true
        } else if syntax.kind == .integerLiteralExpr, let integerLiteralExpr = syntax.as(IntegerLiteralExprSyntax.self) {
            literal = integerLiteralExpr.digits.text
            isFloatingPoint = false
        } else {
            return nil
        }
        return NumericLiteral(literal: literal, isFloatingPoint: isFloatingPoint, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source))
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: literal)]
    }
}

/// `"..."`
class StringLiteral: Expression {
    let segments: [StringLiteralSegment<Expression>]
    let isMultiline: Bool

    init(segments: [StringLiteralSegment<Expression>], isMultiline: Bool = false, syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil) {
        self.segments = segments
        self.isMultiline = isMultiline
        super.init(type: .stringLiteral, syntax: syntax, file: file, range: range)
    }

    override class func decode(syntax: Syntax, in syntaxTree: SyntaxTree) -> Expression? {
        guard syntax.kind == .stringLiteralExpr, let stringLiteralExpr = syntax.as(StringLiteralExprSyntax.self) else {
            return nil
        }
        let isMultiline = stringLiteralExpr.openQuote.tokenKind == .multilineStringQuote
        var segments: [StringLiteralSegment<Expression>] = []
        for segmentSyntax in stringLiteralExpr.segments {
            switch segmentSyntax {
            case .stringSegment(let stringSyntax):
                segments.append(.string(stringSyntax.content.text))
            case .expressionSegment(let expressionSyntax):
                guard let expressionSyntax = expressionSyntax.expressions.first?.expression else {
                    break
                }
                guard let expression = ExpressionDecoder.decode(syntax: Syntax(expressionSyntax), in: syntaxTree) else {
                    return nil
                }
                segments.append(.expression(expression))
            }
        }
        return StringLiteral(segments: segments, isMultiline: isMultiline, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source))
    }
}
