import SwiftSyntax

/// An expression in the Swift syntax tree.
class Expression: SyntaxNode {
    let type: ExpressionType

    init(type: ExpressionType, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
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

/// An expression that represents a possible API call.
protocol APICallExpression {
    /// Additional information about the API call represented by this expression.
    ///
    /// Use `nil` the API call could not be determined.
    var apiMatch: APIMatch? { get set }
}

/// An expression that creates binding variables.
protocol BindingExpression {
    var bindings: [String: TypeSignature] { get }
    func bindAsVar()
}

/// An expression that may represent a member access.
protocol MemberAccessExpression {
    /// If this member access chain begins with an unqualified access, return it.
    var unqualifiedRootMemberAccess: MemberAccess? { get }
}

/// Raw source code.
final class RawExpression: Expression {
    let sourceCode: String

    init(sourceCode: String, message: Message? = nil, syntax: SyntaxProtocol? = nil, range: Source.Range? = nil, in syntaxTree: SyntaxTree? = nil) {
        self.sourceCode = sourceCode
        var range = range
        if range == nil, let source = syntaxTree?.source {
            range = syntax?.range(in: source)
        }
        super.init(type: .raw, syntax: syntax, sourceFile: syntaxTree?.source.file, sourceRange: range)
        if let message {
            self.messages = [message]
        }
    }

    init(syntax: SyntaxProtocol, message: Message? = nil, in syntaxTree: SyntaxTree) {
        self.sourceCode = syntax.description
        let source = syntaxTree.source
        let range = syntax.range(in: source)
        super.init(type: .raw, syntax: syntax, sourceFile: source.file, sourceRange: range)
        if let message {
            self.messages = [message]
        } else {
            self.messages = [.unsupportedSyntax(syntax, source: source)]
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
