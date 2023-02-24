import SwiftSyntax

/// A statement in the Swift syntax tree.
class Statement: SyntaxNode {
    let type: StatementType
    let extras: StatementExtras?

    init(type: StatementType, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.type = type
        self.extras = extras
        super.init(nodeName: String(describing: type), syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    /// Attempt to construct statements of this type from the given syntax.
    ///
    /// - Throws: `Message` when unable to decode a compatible syntax.
    class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        return nil
    }

    /// Visit this statement and its children depth first, performing the given action.
    ///
    /// - Parameters:
    ///   - Parameter perform: The action to perform.
    /// - Warning: This method does not traverse through `Expressions` to find additional statements (e.g. in closures).
    func visitStatements(perform: (Statement) -> VisitResult<Statement>) {
        if case .recurse(let onLeave) = perform(self) {
            for child in children {
                if let statement = child as? Statement {
                    statement.visitStatements(perform: perform)
                }
            }
            if let onLeave {
                onLeave(self)
            }
        }
    }

    final override var subtreeMessages: [Message] {
        let messages: [Message] = extras?.suppressMessages == true ? [] : messages
        return messages + children.flatMap { $0.subtreeMessages }
    }
}

/// Decode statements from syntax.
struct StatementDecoder {
    static func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) -> [Statement] {
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
                if let representingType = statementType.representingType, let decodedStatements = try representingType.decode(syntax: syntax, extras: extras, in: syntaxTree) {
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

    static func decode<ListContainer: SyntaxListContainer>(syntaxListContainer: ListContainer, in syntaxTree: SyntaxTree) -> [Statement] {
        return decode(syntaxList: syntaxListContainer.syntaxList, in: syntaxTree)
    }

    static func decode<List: SyntaxList>(syntaxList: List, in syntaxTree: SyntaxTree) -> [Statement] {
        return syntaxList.flatMap { decode(syntax: $0.content, in: syntaxTree) }
    }
}

/// A synthetic statement type used to represent a code block of statements.
class CodeBlockStatement: Statement {
    let statements: [Statement]

    init(statements: [Statement]) {
        self.statements = statements
        super.init(type: .codeBlock)
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        var blockContext = context
        statements.forEach { blockContext = $0.inferTypes(context: blockContext, expecting: .none) }
        return context
    }

    override var children: [SyntaxNode] {
        return statements
    }
}

/// A general statement hosting an `Expression`.
///
/// - Seealso: ``Expression``
class ExpressionStatement: Statement {
    let expression: Expression?

    init(type: StatementType = .expression, expression: Expression? = nil, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.expression = expression
        super.init(type: type, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        guard let expression = ExpressionDecoder.decodeIfExpression(syntax: syntax, in: syntaxTree) else {
            return nil
        }
        return [ExpressionStatement(expression: expression, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)]
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        return expression?.inferTypes(context: context, expecting: expecting) ?? context
    }

    override var inferredType: TypeSignature {
        return expression?.inferredType ?? .none
    }

    override var children: [SyntaxNode] {
        return expression == nil ? [] : [expression!]
    }
}

/// Attach a warning or error to the tree.
class MessageStatement: Statement {
    init(message: Message) {
        super.init(type: .message)
        self.messages = [message]
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        return nil
    }
}

/// Raw source code.
class RawStatement: Statement {
    let sourceCode: String

    init(sourceCode: String, syntax: SyntaxProtocol? = nil, message: Message? = nil, extras: StatementExtras? = nil, in syntaxTree: SyntaxTree? = nil) {
        self.sourceCode = sourceCode
        var range: Source.Range? = nil
        if let source = syntaxTree?.source {
            range = syntax?.range(in: source)
        }
        super.init(type: .raw, syntax: syntax, sourceFile: syntaxTree?.source.file, sourceRange: range, extras: extras)
        if let message {
            self.messages = [message]
        }
    }

    init(syntax: SyntaxProtocol, message: Message? = nil, extras: StatementExtras? = nil, in syntaxTree: SyntaxTree) {
        self.sourceCode = syntax.sourceCode(in: syntaxTree.source)
        let source = syntaxTree.source
        let range = syntax.range(in: source)
        super.init(type: .raw, syntax: syntax, sourceFile: source.file, sourceRange: range, extras: extras)
        if let message {
            self.messages = [message]
        } else {
            self.messages = [.unsupportedSyntax(syntax, source: source, sourceRange: range)]
        }
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        expectedType = expecting
        return context
    }

    private var expectedType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return expectedType
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        return nil
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: sourceCode)]
    }
}
