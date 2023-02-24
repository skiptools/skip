import SwiftSyntax

/// An expression in the Swift syntax tree.
class Expression: SyntaxNode {
    let type: ExpressionType

    init(type: ExpressionType, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.type = type
        super.init(nodeName: String(describing: type), syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    /// Attempt to construct an expression of this type from the given syntax.
    ///
    /// - Throws: `Message` when unable to decode a compatible syntax.
    class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        return nil
    }

    /// Attempt to construct an expression of this operator type from the given syntax found in a sequence.
    ///
    /// - Throws: `Message` when unable to decode a compatible syntax.
    /// - Seealso: `ExpressionDecoder.decodeSequence`
    class func decodeSequenceOperator(syntax: SyntaxProtocol, sequence: SyntaxProtocol, elements: [ExprSyntax], index: Int, in syntaxTree: SyntaxTree) throws -> Expression? {
        return nil
    }
}

/// Decode expressions from syntax.
struct ExpressionDecoder {
    static func decodeIfExpression(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) -> Expression? {
        do {
            if syntax.kind == .sequenceExpr, let sequenceExpr = syntax.as(SequenceExprSyntax.self) {
                return try decodeSequence(syntax, elements: Array(sequenceExpr.elements), in: syntaxTree)
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

    static func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) -> Expression {
        guard let expression = decodeIfExpression(syntax: syntax, in: syntaxTree) else {
            return RawExpression(syntax: syntax, message: .unsupportedSyntax(syntax, source: syntaxTree.source), in: syntaxTree)
        }
        return expression
    }

    static func decodeSequence(_ sequence: SyntaxProtocol, elements: [ExprSyntax], in syntaxTree: SyntaxTree) throws -> Expression {
        guard !elements.isEmpty else {
            throw Message.unsupportedSyntax(sequence, source: syntaxTree.source)
        }
        if elements.count == 1 {
            return decode(syntax: elements[0], in: syntaxTree)
        }
        guard let lowestPrecedenceIndex = indexOfLowestPrecedenceOperator(in: elements) else {
            throw Message.unsupportedSyntax(sequence, source: syntaxTree.source)
        }
        let operatorElement = elements[lowestPrecedenceIndex]
        for expressionType in ExpressionType.allCases {
            if let representingType = expressionType.representingType, let expression = try representingType.decodeSequenceOperator(syntax: operatorElement, sequence: sequence, elements: elements, index: lowestPrecedenceIndex, in: syntaxTree) {
                return expression
            }
        }
        throw Message.unsupportedSyntax(sequence, source: syntaxTree.source)
    }

    static func decodeCondition(_ condition: ConditionElementSyntax, in syntaxTree: SyntaxTree) throws -> Expression {
        // TODO: Support these conditions
        switch condition.condition {
        case .availability(let syntax):
            throw Message.unsupportedSyntax(syntax, source: syntaxTree.source)
        case .expression(let syntax):
            return decode(syntax: syntax, in: syntaxTree)
        case .matchingPattern(let syntax):
            throw Message.unsupportedSyntax(syntax, source: syntaxTree.source)
        case .optionalBinding(let syntax):
            return decode(syntax: syntax, in: syntaxTree)
        }
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
            if op.precedence.rawValue < minOperator!.precedence.rawValue || (op.precedence == minOperator!.precedence && op.associativity == .left) {
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

    init(sourceCode: String, message: Message? = nil, syntax: SyntaxProtocol? = nil, range: Source.Range?, in syntaxTree: SyntaxTree? = nil) {
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

    init(syntax: SyntaxProtocol, message: Message? = nil, in syntaxTree: SyntaxTree) {
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

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) -> Expression? {
        return nil
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        expectedType = expecting
        return context
    }

    private var expectedType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return expectedType
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: sourceCode)]
    }
}
