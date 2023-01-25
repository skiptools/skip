import SwiftSyntax

/// A node in the Swift syntax tree.
protocol Statement {
    var type: StatementType { get }
    var syntax: Syntax? { get }
    var range: Source.Range? { get }
    var children: [Statement] { get }

    /// Attempt to construct this statement type from the given syntax.
    init?(syntax: Syntax, source: Source)

    /// Pretty-printable tree rooted on this syntax statement.
    var prettyPrintTree: PrettyPrintTree { get }

    /// Messages about this statement and its children.
    var messages: [Message] { get }
}

extension Statement {
    var syntax: Syntax? {
        return nil
    }

    var range: Source.Range? {
        return nil
    }

    var children: [Statement] {
        return []
    }

    var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintTree(root: String(describing: type), children: prettyPrintChildren)
    }

    var prettyPrintChildren: [PrettyPrintTree] {
        return children.map { $0.prettyPrintTree }
    }

    var messages: [Message] {
        return messagesChildren
    }

    var messagesChildren: [Message] {
        return children.flatMap { $0.messages }
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
        case .return:
            return nil
        case .switch:
            return nil
        case .throw:
            return nil
        case .while:
            return nil
        case .classDeclaration:
            return nil
        case .enumDeclaration:
            return nil
        case .extensionDeclaration:
            return nil
        case .functionDeclaration:
            return nil
        case .importDeclaration:
            return ImportDeclaration.self
        case .initDeclaration:
            return nil
        case .protocolDeclaration:
            return nil
        case .structDeclaration:
            return nil
        case .typealiasDeclaration:
            return nil
        case .variableDeclaration:
            return nil

        case .raw:
            return RawStatement.self
        case .message:
            return MessageStatement.self
        }
    }
}

/// Create statements from syntax.
struct StatementFactory {
    static func `for`(syntax: Syntax, in source: Source) -> Statement {
        for statementType in StatementType.allCases {
            if let representingType = statementType.representingType, let statement = representingType.init(syntax: syntax, source: source) {
                return statement
            }
        }
        return RawStatement(syntax: syntax, source: source)!
    }
}

struct ImportDeclaration: Statement {
    let moduleName: String

    init(moduleName: String) {
        self.syntax = nil
        self.range = nil
        self.moduleName = moduleName
    }

    var type: StatementType { .importDeclaration }
    let syntax: Syntax?
    let range: Source.Range?

    init?(syntax: Syntax, source: Source) {
        guard let importDecl = syntax.as(ImportDeclSyntax.self) else {
            return nil
        }
        self.syntax = syntax
        self.range = syntax.range(in: source)
        self.moduleName = importDecl.path.sourceCode(in: source)
    }

    var prettyPrintChildren: [PrettyPrintTree] {
        return [PrettyPrintTree(root: moduleName)]
    }
}

struct RawStatement: Statement {
    let sourceCode: String

    init(sourceCode: String) {
        self.syntax = nil
        self.range = nil
        self.sourceCode = sourceCode
        self.messages = []
    }

    var type: StatementType { .raw }
    let syntax: Syntax?
    let range: Source.Range?
    let messages: [Message]

    init?(syntax: Syntax, source: Source) {
        self.syntax = syntax
        self.range = syntax.range(in: source)
        self.sourceCode = syntax.sourceCode(in: source)
        self.messages = [Message(severity: .warning, message: "Unsupported Swift syntax", source: source, range: range)]
    }

    var prettyPrintChildren: [PrettyPrintTree] {
        return [PrettyPrintTree(root: sourceCode)]
    }
}

struct MessageStatement: Statement {
    var type: StatementType { .message }
    let messages: [Message]

    init(message: Message) {
        self.messages = [message]
    }

    init?(syntax: Syntax, source: Source) {
        return nil
    }
}
