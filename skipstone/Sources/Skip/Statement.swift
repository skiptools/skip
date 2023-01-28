import SwiftSyntax

/// A node in the Swift syntax tree.
class Statement {
    struct Context {
        let syntaxTree: SyntaxTree
        var parent: Statement?

        func reparented(_ parent: Statement?) -> Context {
            return Context(syntaxTree: syntaxTree, parent: parent)
        }
    }

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
    class func decode(syntax: Syntax, extras: StatementExtras?, context: Context) -> [Statement]? {
        return nil
    }

    weak var parent: Statement?
    var children: [Statement] = [] {
        willSet {
            children.forEach { $0.parent = nil }
        }
        didSet {
            children.forEach { $0.parent = self }
        }
    }

    /// Any pretty print child trees aside from this node's child statements.
    var prettyPrintChildren: [PrettyPrintTree] {
        return []
    }

    /// Pretty-printable tree rooted on this syntax statement.
    var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintTree(root: String(describing: type), children: prettyPrintChildren + children.map { $0.prettyPrintTree })
    }

    /// Any message about this statement.
    var message: Message?

    /// Recursive traversal of all messages from the tree rooted on this syntax statement.
    var messages: [Message] {
        var messages: [Message] = []
        if let message, extras?.suppressMessage != true {
            messages.append(message)
        }
        return messages + children.flatMap { $0.messages }
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
            return nil
        case .for:
            return nil
        case .if:
            return nil
        case .ifDefined:
            return IfDefined.self
        case .return:
            return nil
        case .switch:
            return nil
        case .throw:
            return nil
        case .while:
            return nil

        case .classDeclaration:
            return ClassDeclaration.self
        case .enumDeclaration:
            return nil
        case .extensionDeclaration:
            return ExtensionDeclaration.self
        case .functionDeclaration:
            return FunctionDeclaration.self
        case .importDeclaration:
            return ImportDeclaration.self
        case .initDeclaration:
            return nil
        case .protocolDeclaration:
            return ProtocolDeclaration.self
        case .structDeclaration:
            return nil
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

/// Create statements from syntax.
struct StatementFactory {
    static func `for`(syntax: Syntax, context: Statement.Context) -> [Statement] {
        let extras = StatementExtras.process(syntax: syntax)
        var statements: [Statement] = []
        if let extras {
            let (extraStatements, replace) = extras.statements(syntax: syntax, context: context)
            guard !replace else {
                return extraStatements
            }
            statements = extraStatements
        }

        for statementType in StatementType.allCases {
            if let representingType = statementType.representingType, let decodedStatements = representingType.decode(syntax: syntax, extras: extras, context: context) {
                statements += decodedStatements
                return statements
            }
        }

        // Unsupported
        statements.append(RawStatement(syntax: syntax, extras: extras, context: context))
        return statements
    }
}
