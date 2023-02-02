import SwiftSyntax

/// An expression in the Swift syntax tree.
///
/// Expressions are generally immutable after `resolve` is called with the parent and statement set, allowing each expression to finalize
/// itself with any contextual information.
class Expression: PrettyPrintable {
    let type: ExpressionType
    let syntax: Syntax?
    let file: Source.File?
    let range: Source.Range?

    init(type: ExpressionType, syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil) {
        self.type = type
        self.syntax = syntax
        self.file = file
        self.range = range
    }

    /// Attempt to construct expressions of this type from the given syntax.
    ///
    /// - Throws: `Message` when unable to decode a compatible syntax.
    class func decode(syntax: Syntax, in syntaxTree: SyntaxTree) throws -> Expression? {
        return nil
    }

    weak var statement: Statement? = nil
    weak var parent: Expression? = nil
    var children: [Expression] {
        return []
    }

    /// Resolve any information that relies on our parent and statement being set.
    func resolve() {
    }

    /// Pretty print child trees for this expression's attributes, excluding `children`.
    var prettyPrintAttributes: [PrettyPrintTree] {
        return []
    }

    /// Pretty-printable tree rooted on this syntax expression.
    final var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintTree(root: String(describing: type), children: prettyPrintAttributes + children.map { $0.prettyPrintTree })
    }

    /// Any message about this expression.
    var expressionMessages: [Message] = []

    /// Recursive traversal of all messages from the tree rooted on this syntax expression.
    final var messages: [Message] {
        return expressionMessages + children.flatMap { $0.messages }
    }
}

/// Supported Swift expression types.
enum ExpressionType: CaseIterable {
    case booleanLiteral
    case floatingPointLiteral
    case integerLiteral
    case stringLiteral

    /// An expression representing raw Swift code.
    case raw

    /// The Swift data type that represents this expression type.
    var representingType: Expression.Type? {
        switch self {
        case .booleanLiteral:
            return BooleanLiteral.self
        case .floatingPointLiteral:
            return NumericLiteral.self
        case .integerLiteral:
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

    init(sourceCode: String, message: Message? = nil, syntax: Syntax? = nil, in syntaxTree: SyntaxTree? = nil) {
        self.sourceCode = sourceCode
        var range: Source.Range? = nil
        if let source = syntaxTree?.source {
            range = syntax?.range(in: source)
        }
        super.init(type: .raw, syntax: syntax, file: syntaxTree?.source.file, range: range)
        if let message {
            self.expressionMessages = [message]
        }
    }

    init(syntax: Syntax, message: Message? = nil, in syntaxTree: SyntaxTree) {
        self.sourceCode = syntax.sourceCode(in: syntaxTree.source)
        let source = syntaxTree.source
        let range = syntax.range(in: source)
        super.init(type: .raw, syntax: syntax, file: source.file, range: range)
        if let message {
            self.expressionMessages = [message]
        } else {
            self.expressionMessages = [.unsupportedSyntax(syntax: syntax, source: source, range: range)]
        }
    }

    override class func decode(syntax: Syntax, in syntaxTree: SyntaxTree) -> Expression? {
        return nil
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: sourceCode)]
    }
}
