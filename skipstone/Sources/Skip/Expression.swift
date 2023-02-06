import SwiftSyntax

/// An expression in the Swift syntax tree.
class Expression: SyntaxNode {
    let type: ExpressionType

    init(type: ExpressionType, syntax: Syntax? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.type = type
        super.init(nodeName: String(describing: type), syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    /// Attempt to construct an expression of this type from the given syntax.
    ///
    /// - Throws: `Message` when unable to decode a compatible syntax.
    class func decode(syntax: Syntax, in syntaxTree: SyntaxTree) throws -> Expression? {
        return nil
    }

    /// Attempt to construct an expression of this operator type from the given syntax found in a sequence.
    ///
    /// - Throws: `Message` when unable to decode a compatible syntax.
    /// - Seealso: `ExpressionDecoder.decodeSequence`
    class func decodeSequenceOperator(syntax: Syntax, sequence: Syntax, elements: [ExprSyntax], index: Int, in syntaxTree: SyntaxTree) throws -> Expression? {
        return nil
    }
}

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

/// Decode expressions from syntax.
struct ExpressionDecoder {
    static func decodeIfExpression(syntax: Syntax, in syntaxTree: SyntaxTree) -> Expression? {
        do {
            if syntax.kind == .sequenceExpr, let sequenceExpr = syntax.as(SequenceExprSyntax.self) {
                return try decodeSequence(sequence: syntax, elements: Array(sequenceExpr.elements), in: syntaxTree)
            }
            for expressionType in ExpressionType.allCases {
                if let representingType = expressionType.representingType, let expression = try representingType.decode(syntax: syntax, in: syntaxTree) {
                    return expression
                }
            }
        } catch {
            return RawExpression(syntax: syntax, message: error as? Message, in: syntaxTree)
        }
        return nil
    }

    static func decode(syntax: Syntax, in syntaxTree: SyntaxTree) -> Expression {
        guard let expression = decodeIfExpression(syntax: syntax, in: syntaxTree) else {
            return RawExpression(syntax: syntax, message: .unsupportedSyntax(syntax, source: syntaxTree.source), in: syntaxTree)
        }
        return expression
    }

    static func decodeSequence(sequence: Syntax, elements: [ExprSyntax], in syntaxTree: SyntaxTree) throws -> Expression {
        guard !elements.isEmpty else {
            throw Message.unsupportedSyntax(sequence, source: syntaxTree.source)
        }
        if elements.count == 1 {
            return decode(syntax: Syntax(elements[0]), in: syntaxTree)
        }
        guard let lowestPrecedenceIndex = indexOfLowestPrecedenceOperator(in: elements) else {
            throw Message.unsupportedSyntax(sequence, source: syntaxTree.source)
        }
        let operatorElement = elements[lowestPrecedenceIndex]
        for expressionType in ExpressionType.allCases {
            if let representingType = expressionType.representingType, let expression = try representingType.decodeSequenceOperator(syntax: Syntax(operatorElement), sequence: sequence, elements: elements, index: lowestPrecedenceIndex, in: syntaxTree) {
                return expression
            }
        }
        throw Message.unsupportedSyntax(sequence, source: syntaxTree.source)
    }

    /// Return the index of the lowest precedence operator expression in the given list. This allows us to segment the list and recurse on each segment, forming an
    /// expression tree that will get translated in precedence order.
    private static func indexOfLowestPrecedenceOperator(in expressionSyntaxes: [ExprSyntax]) -> Int? {
        var minOperator: Operator? = nil
        var minIndex: Int? = nil
        for (index, syntax) in expressionSyntaxes.enumerated() {
            var op: Operator? = nil
            switch syntax.kind {
            case .assignmentExpr:
                op = Operator.with(symbol: "=")
            case .binaryOperatorExpr:
                guard let binaryOperatorExpr = syntax.as(BinaryOperatorExprSyntax.self) else {
                    break
                }
                op = Operator.with(symbol: binaryOperatorExpr.operatorToken.text)
            case .ternaryExpr:
                fallthrough
            case .unresolvedTernaryExpr:
                op = Operator.with(symbol: "?:")
            case .asExpr:
                fallthrough
            case .unresolvedAsExpr:
                op = Operator.with(symbol: "as")
            case .isExpr:
                fallthrough
            case .unresolvedIsExpr:
                op = Operator.with(symbol: "is")
            default:
                break
            }
            guard let op else {
                continue
            }
            guard minOperator != nil else {
                minOperator = op
                minIndex = index
                continue
            }
            // Select the current operator to segment the expression list on if it has lower precedence OR has equal precedence
            // but is left associative, keeping the previous expressions evaluating first
            if op.precedence < minOperator!.precedence || (op.precedence == minOperator!.precedence && op.associativity == .left) {
                minOperator = op
                minIndex = index
            }
        }
        return minIndex
    }
}

/// Raw source code.
class RawExpression: Expression {
    let sourceCode: String

    init(sourceCode: String, message: Message? = nil, syntax: Syntax? = nil, range: Source.Range?, in syntaxTree: SyntaxTree? = nil) {
        self.sourceCode = sourceCode
        var range: Source.Range? = nil
        if let source = syntaxTree?.source {
            range = syntax?.range(in: source)
        }
        super.init(type: .raw, syntax: syntax, sourceFile: syntaxTree?.source.file, sourceRange: range)
        if let message {
            self.messages = [message]
        }
    }

    init(syntax: Syntax, message: Message? = nil, in syntaxTree: SyntaxTree) {
        self.sourceCode = syntax.sourceCode(in: syntaxTree.source)
        let source = syntaxTree.source
        let range = syntax.range(in: source)
        super.init(type: .raw, syntax: syntax, sourceFile: source.file, sourceRange: range)
        if let message {
            self.messages = [message]
        } else {
            self.messages = [.unsupportedSyntax(syntax, source: source, sourceRange: range)]
        }
    }

    override class func decode(syntax: Syntax, in syntaxTree: SyntaxTree) -> Expression? {
        return nil
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: sourceCode)]
    }
}
