import SwiftSyntax

/// Decode statements from syntax.
struct  StatementDecoder {
    static func decode(syntax: SyntaxProtocol, context: DecodeContext, in syntaxTree: SyntaxTree) -> [Statement] {
        let extras = StatementExtras.decode(syntax: syntax)
        var statements: [Statement] = []
        if let extras {
            let (extraStatements, replace) = extras.statements(syntax: syntax, in: syntaxTree)
            guard !replace else {
                return extraStatements
            }
            statements = extraStatements
        }

        var message: Message? = nil
        do {
            for statementType in StatementType.allCases {
                if let representingType = statementType.representingType, let decodedStatements = try representingType.decode(syntax: syntax, extras: extras, context: context, in: syntaxTree) {
                    statements += decodedStatements
                    return statements
                }
            }
        } catch {
            message = error as? Message
        }
        // Unsupported
        statements.append(RawStatement(syntax: syntax, message: message, extras: extras, in: syntaxTree))
        return statements
    }

    static func decode<ListContainer: SyntaxListContainer>(syntaxListContainer: ListContainer, context: DecodeContext, in syntaxTree: SyntaxTree) -> [Statement] {
        var statements = decode(syntaxList: syntaxListContainer.syntaxList, context: context, in: syntaxTree)
        let endSyntax = syntaxListContainer.endOfListSyntax
        if let extras = StatementExtras.decode(syntax: endSyntax) {
            let (extraStatements, _) = extras.statements(syntax: endSyntax, in: syntaxTree)
            statements += extraStatements
            statements.append(Empty(syntax: endSyntax, extras: extras, in: syntaxTree))
        }
        return statements
    }

    static func decode<List: SyntaxList>(syntaxList: List, context: DecodeContext, in syntaxTree: SyntaxTree) -> [Statement] {
        return syntaxList.flatMap { decode(syntax: $0.content, context: context, in: syntaxTree) }
    }
}

/// Decoding context.
struct DecodeContext {
    var memberOf: (type: StatementType, modifiers: Modifiers)?
}

/// Levels of decoding.
public enum DecodeLevel {
    case none
    case api
    case full
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
                op = Operator.with(symbol: binaryOperatorExpr.operator.text)
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
