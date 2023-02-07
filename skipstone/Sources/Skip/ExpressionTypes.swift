import SwiftSyntax

/// Supported Swift expression types.
enum ExpressionType: CaseIterable {
    case arrayLiteral
    case binaryOperator
    case booleanLiteral
    case functionCall
    case identifier
    case memberAccess
    case numericLiteral
    case stringLiteral

    /// An expression representing raw Swift code.
    case raw

    /// The Swift data type that represents this expression type.
    var representingType: Expression.Type? {
        switch self {
        case .arrayLiteral:
            return ArrayLiteral.self
        case .binaryOperator:
            return BinaryOperator.self
        case .booleanLiteral:
            return BooleanLiteral.self
        case .functionCall:
            return FunctionCall.self
        case .identifier:
            return Identifier.self
        case .memberAccess:
            return MemberAccess.self
        case .numericLiteral:
            return NumericLiteral.self
        case .stringLiteral:
            return StringLiteral.self

        case .raw:
            return RawExpression.self
        }
    }
}

/// `[...]`
class ArrayLiteral: Expression {
    let elements: [Expression]

    init(elements: [Expression], syntax: SyntaxProtocol?, sourceFile: Source.File?, sourceRange: Source.Range? = nil) {
        self.elements = elements
        super.init(type: .arrayLiteral, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .arrayExpr, let arrayExpr = syntax.as(ArrayExprSyntax.self) else {
            return nil
        }
        let elements = arrayExpr.elements.map {
            ExpressionDecoder.decode(syntax: $0.expression, in: syntaxTree)
        }
        return ArrayLiteral(elements: elements, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override var children: [SyntaxNode] {
        return elements
    }
}

/// `+, -, *, ...`
class BinaryOperator: Expression {
    let op: Operator
    let lhs: Expression
    let rhs: Expression

    init(op: Operator, lhs: Expression, rhs: Expression, syntax: SyntaxProtocol?, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.op = op
        self.lhs = lhs
        self.rhs = rhs
        super.init(type: .binaryOperator, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decodeSequenceOperator(syntax: SyntaxProtocol, sequence: SyntaxProtocol, elements: [ExprSyntax], index: Int, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .binaryOperatorExpr, let binaryOperatorExpr = syntax.as(BinaryOperatorExprSyntax.self) else {
            return nil
        }
        let op = Operator.with(symbol: binaryOperatorExpr.operatorToken.text)
        let lhs = try ExpressionDecoder.decodeSequence(sequence: sequence, elements: Array(elements[..<index]), in: syntaxTree)
        let rhs = try ExpressionDecoder.decodeSequence(sequence: sequence, elements: Array(elements[(index + 1)...]), in: syntaxTree)
        return BinaryOperator(op: op, lhs: lhs, rhs: rhs, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override var children: [SyntaxNode] {
        return [lhs, rhs]
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: op.symbol)]
    }
}

/// `true, false`
class BooleanLiteral: Expression {
    let literal: Bool

    init(literal: Bool, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.literal = literal
        super.init(type: .booleanLiteral, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) -> Expression? {
        guard syntax.kind == .booleanLiteralExpr, let booleanLiteralExpr = syntax.as(BooleanLiteralExprSyntax.self) else {
            return nil
        }
        let literal = booleanLiteralExpr.booleanLiteral.text == "true"
        return BooleanLiteral(literal: literal, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: String(describing: literal))]
    }
}

/// `function(...)`
class FunctionCall: Expression {
    let function: Expression
    let arguments: [LabeledExpression<Expression>]

    init(function: Expression, arguments: [LabeledExpression<Expression>], syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.function = function
        self.arguments = arguments
        super.init(type: .functionCall, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .functionCallExpr, let functionCallExpr = syntax.as(FunctionCallExprSyntax.self) else {
            return nil
        }
        let function = ExpressionDecoder.decode(syntax: functionCallExpr.calledExpression, in: syntaxTree)
        var labeledExpressions = functionCallExpr.argumentList.map {
            let label = $0.label?.text
            let expression = ExpressionDecoder.decode(syntax: $0.expression, in: syntaxTree)
            return LabeledExpression(label: label, expression: expression)
        }
        if let trailingClosure = functionCallExpr.trailingClosure {
            let expression = ExpressionDecoder.decode(syntax: trailingClosure, in: syntaxTree)
            labeledExpressions.append(LabeledExpression(expression: expression))
        }
        if let multipleTrailingClosures = functionCallExpr.additionalTrailingClosures {
            labeledExpressions += multipleTrailingClosures.map {
                let label = $0.label.text
                let expression = ExpressionDecoder.decode(syntax: $0.closure, in: syntaxTree)
                return LabeledExpression(label: label, expression: expression)
            }
        }
        return FunctionCall(function: function, arguments: labeledExpressions)
    }

    override var children: [SyntaxNode] {
        return [function] + arguments.map { $0.expression }
    }
}

/// `x`
class Identifier: Expression {
    let name: String

    init(name: String, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.name = name
        super.init(type: .identifier, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .identifierExpr, let identifierExpr = syntax.as(IdentifierExprSyntax.self) else {
            return nil
        }
        let name = identifierExpr.identifier.text
        return Identifier(name: name, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: name)]
    }
}

/// `person.name`
class MemberAccess: Expression {
    let base: Expression?
    let member: String

    init(base: Expression?, member: String, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.base = base
        self.member = member
        super.init(type: .memberAccess, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .memberAccessExpr, let memberAccessExpr = syntax.as(MemberAccessExprSyntax.self) else {
            return nil
        }
        var base: Expression? = nil
        if let baseSyntax = memberAccessExpr.base {
            base = ExpressionDecoder.decode(syntax: baseSyntax, in: syntaxTree)
        }
        let member = memberAccessExpr.name.text
        return MemberAccess(base: base, member: member, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override var children: [SyntaxNode] {
        return base == nil ? [] : [base!]
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: member)]
    }
}

/// `1, 1.0`
class NumericLiteral: Expression {
    let literal: String
    let isFloatingPoint: Bool

    init(literal: String, isFloatingPoint: Bool, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.literal = literal
        self.isFloatingPoint = isFloatingPoint
        super.init(type: .numericLiteral, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) -> Expression? {
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
        return NumericLiteral(literal: literal, isFloatingPoint: isFloatingPoint, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: literal)]
    }
}

/// `"..."`
class StringLiteral: Expression {
    let segments: [StringLiteralSegment<Expression>]
    let isMultiline: Bool

    init(segments: [StringLiteralSegment<Expression>], isMultiline: Bool = false, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.segments = segments
        self.isMultiline = isMultiline
        super.init(type: .stringLiteral, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) -> Expression? {
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
                let expression = ExpressionDecoder.decode(syntax: expressionSyntax, in: syntaxTree)
                segments.append(.expression(expression))
            }
        }
        return StringLiteral(segments: segments, isMultiline: isMultiline, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override var children: [SyntaxNode] {
        return segments.compactMap {
            switch $0 {
            case .expression(let expression):
                return expression
            case .string:
                return nil
            }
        }
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var expressionIndex = 0
        let segmentsDescription = segments.map { (segment) -> String in
            switch segment {
            case .expression:
                expressionIndex += 1
                return "\\(\(expressionIndex - 1))"
            case .string(let string):
                return string
            }
        }.joined(separator: "")
        let quotes = isMultiline ? "\"\"\"" : "\""
        return [PrettyPrintTree(root: "\(quotes)\(segmentsDescription)\(quotes)")]
    }
}
