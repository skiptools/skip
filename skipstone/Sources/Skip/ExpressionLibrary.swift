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

    init(type: ExpressionType, literal: String, syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil) {
        self.literal = literal
        super.init(type: type, syntax: syntax, file: file, range: range)
    }

    override class func decode(syntax: Syntax, in syntaxTree: SyntaxTree) -> Expression? {
        let type: ExpressionType
        let literal: String
        if syntax.kind == .floatLiteralExpr, let floatLiteralExpr = syntax.as(FloatLiteralExprSyntax.self) {
            type = .floatingPointLiteral
            literal = floatLiteralExpr.floatingDigits.text
        } else if syntax.kind == .integerLiteralExpr, let integerLiteralExpr = syntax.as(IntegerLiteralExprSyntax.self) {
            type = .integerLiteral
            literal = integerLiteralExpr.digits.text
        } else {
            return nil
        }
        return NumericLiteral(type: type, literal: literal, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source))
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: literal)]
    }
}

/// `"..."`
class StringLiteral: Expression {
    enum Segment {
        case string(String)
        case expression(Expression)
    }
    let segments: [Segment]
    let isMultiline: Bool

    init(segments: [Segment], isMultiline: Bool = false, syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil) {
        self.segments = segments
        self.isMultiline = isMultiline
        super.init(type: .stringLiteral, syntax: syntax, file: file, range: range)
    }

    override class func decode(syntax: Syntax, in syntaxTree: SyntaxTree) -> Expression? {
        guard syntax.kind == .stringLiteralExpr, let stringLiteralExpr = syntax.as(StringLiteralExprSyntax.self) else {
            return nil
        }
        let isMultiline = stringLiteralExpr.openQuote.tokenKind == .multilineStringQuote
        var segments: [Segment] = []
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
