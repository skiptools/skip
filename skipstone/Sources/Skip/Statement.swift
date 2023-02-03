import SwiftSyntax

/// A statement in the Swift syntax tree.
class Statement: SyntaxNode {
    let type: StatementType
    let extras: StatementExtras?

    init(type: StatementType, syntax: Syntax? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.type = type
        self.extras = extras
        super.init(nodeName: String(describing: type), syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    /// Attempt to construct statements of this type from the given syntax.
    ///
    /// - Throws: `Message` when unable to decode a compatible syntax.
    class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        return nil
    }

    final override var subtreeMessages: [Message] {
        let messages: [Message] = extras?.suppressMessages == true ? [] : messages
        return messages + children.flatMap { $0.subtreeMessages }
    }
}

/// Supported Swift statement types.
enum StatementType: CaseIterable {
    case assignment
    case `break`
    case `catch`
    case comment
    case `continue`
    case `defer`
    case `do`
    case error
    case `for`
    case `if`
    case ifDefined
    case `return`
    case `switch`
    case `throw`
    case `while`

    case classDeclaration
    case enumDeclaration
    case extensionDeclaration
    case functionDeclaration
    case importDeclaration
    case initDeclaration
    case protocolDeclaration
    case structDeclaration
    case typealiasDeclaration
    case variableDeclaration

    /// A statement hosting an `Expression`.
    case expression
    /// A statement representing raw Swift code.
    case raw
    /// A statement that only exists to add a message to the syntax tree.
    case message

    /// The Swift data type that represents this statement type.
    var representingType: Statement.Type? {
        switch self {
        case .assignment:
            return nil
        case .break:
            return nil
        case .catch:
            return nil
        case .comment:
            return nil
        case .continue:
            return nil
        case .defer:
            return nil
        case .do:
            return nil
        case .error:
            return nil
        case .for:
            return nil
        case .if:
            return nil
        case .ifDefined:
            return IfDefined.self
        case .return:
            return Return.self
        case .switch:
            return nil
        case .throw:
            return nil
        case .while:
            return nil

        case .classDeclaration:
            return TypeDeclaration.self
        case .enumDeclaration:
            return TypeDeclaration.self
        case .extensionDeclaration:
            return ExtensionDeclaration.self
        case .functionDeclaration:
            return FunctionDeclaration.self
        case .importDeclaration:
            return ImportDeclaration.self
        case .initDeclaration:
            return nil
        case .protocolDeclaration:
            return TypeDeclaration.self
        case .structDeclaration:
            return TypeDeclaration.self
        case .typealiasDeclaration:
            return nil
        case .variableDeclaration:
            return VariableDeclaration.self

        case .expression:
            return ExpressionStatement.self
        case .message:
            return MessageStatement.self
        case .raw:
            return RawStatement.self
        }
    }
}

/// Decode statements from syntax.
struct StatementDecoder {
    static func decode(syntax: Syntax, in syntaxTree: SyntaxTree) -> [Statement] {
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

/// A general statement hosting an `Expression`.
///
/// - Seealso: ``Expression``
class ExpressionStatement: Statement {
    let expression: Expression?

    init(type: StatementType = .expression, expression: Expression? = nil, syntax: Syntax? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.expression = expression
        super.init(type: type, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        guard let expression = ExpressionDecoder.decode(syntax: syntax, in: syntaxTree) else {
            return nil
        }
        return [ExpressionStatement(expression: expression, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)]
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

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        return nil
    }
}

/// Raw source code.
class RawStatement: Statement {
    let sourceCode: String

    init(sourceCode: String, syntax: Syntax? = nil, message: Message? = nil, extras: StatementExtras? = nil, in syntaxTree: SyntaxTree? = nil) {
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

    init(syntax: Syntax, message: Message? = nil, extras: StatementExtras? = nil, in syntaxTree: SyntaxTree) {
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

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        return nil
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: sourceCode)]
    }
}
