import SwiftSyntax

/// An expression in the Swift syntax tree.
class Expression: SyntaxNode {
    let type: ExpressionType

    init(type: ExpressionType, syntax: Syntax? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.type = type
        super.init(nodeName: String(describing: type), syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    /// Attempt to construct expressions of this type from the given syntax.
    ///
    /// - Throws: `Message` when unable to decode a compatible syntax.
    class func decode(syntax: Syntax, in syntaxTree: SyntaxTree) throws -> Expression? {
        return nil
    }
}

/// Supported Swift expression types.
enum ExpressionType: CaseIterable {
    case booleanLiteral
    case numericLiteral
    case stringLiteral

    /// An expression representing raw Swift code.
    case raw

    /// The Swift data type that represents this expression type.
    var representingType: Expression.Type? {
        switch self {
        case .booleanLiteral:
            return BooleanLiteral.self
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
    static func decode(syntax: Syntax, in syntaxTree: SyntaxTree) -> Expression? {
        do {
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
