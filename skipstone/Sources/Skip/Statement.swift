import SwiftSyntax

/// A statement in the Swift syntax tree.
///
/// Statements are generally immutable after `resolve` is called with the parent statement set, allowing each statement to finalize
/// itself with any contextual information.
class Statement: PrettyPrintable {
    let type: StatementType
    let syntax: Syntax?
    let file: Source.File?
    let range: Source.Range?
    let extras: StatementExtras?

    init(type: StatementType, syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.type = type
        self.syntax = syntax
        self.file = file
        self.range = range
        self.extras = extras
    }

    /// Attempt to construct statements of this type from the given syntax.
    ///
    /// - Throws: `Message` when unable to decode a compatible syntax.
    class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        return nil
    }

    weak var parent: Statement? = nil
    var children: [Statement] {
        return []
    }

    /// Resolve any information that relies on our parent statement being set.
    func resolve() {
    }

    /// Pretty print child trees for this statement's attributes, excluding `children`.
    var prettyPrintAttributes: [PrettyPrintTree] {
        return []
    }

    /// Pretty-printable tree rooted on this syntax statement.
    final var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintTree(root: String(describing: type), children: prettyPrintAttributes + children.map { $0.prettyPrintTree })
    }

    /// Any message about this statement.
    var statementMessages: [Message] = []

    /// Recursive traversal of all messages from the tree rooted on this syntax statement.
    final var messages: [Message] {
        let messages: [Message] = extras?.suppressMessages == true ? [] : statementMessages
        return messages + children.flatMap { $0.messages }
    }

    /// Find the nearest type declaration by traversing up the statement tree.
    final var owningTypeDeclaration: TypeDeclaration? {
        var current: Statement? = self
        while current != nil {
            if let typeDeclaration = current as? TypeDeclaration {
                return typeDeclaration
            }
            current = current?.parent
        }
        return nil
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
    case expression
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
        case .expression:
            return ExpressionStatement.self
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

        case .raw:
            return RawStatement.self
        case .message:
            return MessageStatement.self
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

    /// Traverse up the statement tree to fully qualify a type name used in a statement.
    static func qualifyReferencedTypeName(_ typeName: String, in statement: Statement?) -> String {
        // Look for a qualified name whose last token(s) are the given type name
        let suffix = ".\(typeName)"
        var current = statement
        while current != nil {
            // Find the next declared type up the statement chain
            guard let owningType = current?.owningTypeDeclaration else {
                break
            }
            // Look for any direct child of that type with a matching qualified name
            if let referencedType = owningType.children.first(where: { ($0 as? TypeDeclaration)?.qualifiedName.hasSuffix(suffix) == true }) {
                return (referencedType as! TypeDeclaration).qualifiedName
            }
            // Move up to the next owning type and repeat
            current = owningType.parent
        }
        return typeName
    }

    /// Traverse up the statement tree to fully qualify a type name declared by a class, struct, etc.
    static func qualifyDeclaredTypeName(_ typeName: String, declaration: Statement) -> String {
        if let typeDeclaration = declaration.parent?.owningTypeDeclaration {
            return "\(typeDeclaration.qualifiedName).\(typeName)"
        }
        return typeName
    }
}

/// Attach a warning or error to the tree.
class MessageStatement: Statement {
    init(message: Message) {
        super.init(type: .message)
        self.statementMessages = [message]
    }

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        return nil
    }
}

/// Raw source code.
class RawStatement: Statement {
    let sourceCode: String

    init(sourceCode: String, message: Message? = nil, syntax: Syntax? = nil, extras: StatementExtras? = nil, in syntaxTree: SyntaxTree? = nil) {
        self.sourceCode = sourceCode
        var range: Source.Range? = nil
        if let source = syntaxTree?.source {
            range = syntax?.range(in: source)
        }
        super.init(type: .raw, syntax: syntax, file: syntaxTree?.source.file, range: range, extras: extras)
        if let message {
            self.statementMessages = [message]
        }
    }

    init(syntax: Syntax, message: Message? = nil, extras: StatementExtras? = nil, in syntaxTree: SyntaxTree) {
        self.sourceCode = syntax.sourceCode(in: syntaxTree.source)
        let source = syntaxTree.source
        let range = syntax.range(in: source)
        super.init(type: .raw, syntax: syntax, file: source.file, range: range, extras: extras)
        if let message {
            self.statementMessages = [message]
        } else {
            self.statementMessages = [.unsupportedSyntax(syntax: syntax, source: source, range: range)]
        }
    }

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        return nil
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: sourceCode)]
    }
}

/// A general statement hosting an `Expression`.
///
/// - Seealso: ``Expression``
class ExpressionStatement: Statement {
    let expression: Expression?

    init(type: StatementType = .expression, expression: Expression? = nil, syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.expression = expression
        super.init(type: type, syntax: syntax, file: file, range: range, extras: extras)
    }

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        guard let expression = ExpressionDecoder.decode(syntax: syntax, in: syntaxTree) else {
            return nil
        }
        return [ExpressionStatement(expression: expression, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)]
    }

    override func resolve() {
        guard let expression else {
            return
        }

        // Resolve expressions breadth first so that a child can use information from its parent's siblings
        var resolveQueue = [expression]
        while !resolveQueue.isEmpty {
            let expression = resolveQueue.removeFirst()
            expression.statement = self
            expression.resolve()
            expression.children.forEach { $0.parent = expression }
            resolveQueue += expression.children
        }
        statementMessages += expression.messages
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        guard let expression else {
            return []
        }
        return [expression.prettyPrintTree]
    }
}
