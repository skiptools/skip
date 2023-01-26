import SwiftSyntax

/// A node in the Swift syntax tree.
protocol Statement {
    var type: StatementType { get }
    var syntax: Syntax? { get }
    var file: Source.File? { get }
    var range: Source.Range? { get }
    var extras: StatementExtras? { get }
    var children: [Statement] { get }

    /// Attempt to construct this statement type from the given syntax.
    init?(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree)

    /// Pretty-printable tree rooted on this syntax statement.
    var prettyPrintTree: PrettyPrintTree { get }

    /// Any message about this statement.
    var message: Message? { get }

    /// Recursive traversal of all messages from the tree rooted on this syntax statement.
    var messages: [Message] { get }
}

extension Statement {
    var syntax: Syntax? {
        return nil
    }

    var file: Source.File? {
        return nil
    }

    var range: Source.Range? {
        return nil
    }

    var extras: StatementExtras? {
        return nil
    }

    var children: [Statement] {
        return []
    }

    var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintTree(root: String(describing: type), children: prettyPrintChildren + children.map { $0.prettyPrintTree })
    }

    var prettyPrintChildren: [PrettyPrintTree] {
        return []
    }

    var message: Message? {
        return nil
    }

    var messages: [Message] {
        var messages: [Message] = []
        if let message, extras?.directives.contains(.nowarn) != true {
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
            return ProtocolDeclaration.self
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
    static func `for`(syntax: Syntax, in syntaxTree: SyntaxTree) -> [Statement] {
        let extras = StatementExtras.process(syntax: syntax)
        var statements: [Statement] = []
        if let extras {
            let (extraStatements, replace) = extras.statements(syntax: syntax, in: syntaxTree)
            guard !replace else {
                return extraStatements
            }
            statements = extraStatements
        }

        for statementType in StatementType.allCases {
            if let representingType = statementType.representingType, let statement = representingType.init(syntax: syntax, extras: extras, in: syntaxTree) {
                statements.append(statement)
                return statements
            }
        }
        statements.append(RawStatement(syntax: syntax, extras: extras, in: syntaxTree)!)
        return statements
    }
}

struct ImportDeclaration: Statement {
    let modulePath: [String]

    init(modulePath: [String]) {
        self.syntax = nil
        self.file = nil
        self.range = nil
        self.extras = nil
        self.modulePath = modulePath
    }

    var type: StatementType { .importDeclaration }
    let syntax: Syntax?
    let file: Source.File?
    let range: Source.Range?
    let extras: StatementExtras?

    init?(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) {
        guard let importDecl = syntax.as(ImportDeclSyntax.self) else {
            return nil
        }
        self.syntax = syntax
        self.file = syntaxTree.source.file
        self.range = syntax.range(in: syntaxTree.source)
        self.extras = extras
        self.modulePath = importDecl.path.map { $0.name.text }
    }

    var prettyPrintChildren: [PrettyPrintTree] {
        return [PrettyPrintTree(root: modulePath.joined(separator: "."))]
    }
}

// TODO: Attributes, modifiers, generics, where clause
struct ProtocolDeclaration: Statement {
    let name: String
    let inherits: [TypeSignature]
    let members: [Statement]

    init(name: String, inherits: [TypeSignature] = [], members: [Statement] = []) {
        self.syntax = nil
        self.file = nil
        self.range = nil
        self.extras = nil
        self.message = nil
        self.name = name
        self.inherits = inherits
        self.members = members
    }

    var type: StatementType { .protocolDeclaration }
    let syntax: Syntax?
    let file: Source.File?
    let range: Source.Range?
    let extras: StatementExtras?
    let message: Message?

    init?(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) {
        guard let protocolDecl = syntax.as(ProtocolDeclSyntax.self) else {
            return nil
        }
        self.syntax = syntax
        self.file = syntaxTree.source.file
        self.range = syntax.range(in: syntaxTree.source)
        self.extras = extras
        self.name = protocolDecl.identifier.text
        var inherits: [TypeSignature] = []
        var message: Message? = nil
        if let inheritedTypeCollection = protocolDecl.inheritanceClause?.inheritedTypeCollection {
            for typeSyntax in inheritedTypeCollection {
                if let typeSignature = TypeSignature.for(syntax: typeSyntax.typeName) {
                    inherits.append(typeSignature)
                } else if message == nil {
                    message = .unsupportedTypeSignature(source: syntaxTree.source, range: typeSyntax.range(in: syntaxTree.source))
                }
            }
        }
        self.inherits = inherits
        self.message = message
        self.members = syntaxTree.process(syntaxListContainer: protocolDecl.members)
    }

    var children: [Statement] {
        return members
    }

    var prettyPrintChildren: [PrettyPrintTree] {
        return [PrettyPrintTree(root: name)]
    }
}

struct RawStatement: Statement {
    let sourceCode: String
    var message: Message?

    init(sourceCode: String, message: Message? = nil, syntax: Syntax? = nil, extras: StatementExtras? = nil, in syntaxTree: SyntaxTree? = nil) {
        self.syntax = syntax
        self.file = syntaxTree?.source.file
        if let syntaxTree {
            range = syntax?.range(in: syntaxTree.source)
        } else {
            range = nil
        }
        self.extras = extras
        self.sourceCode = sourceCode
        self.message = message
    }

    var type: StatementType { .raw }
    let syntax: Syntax?
    let file: Source.File?
    let range: Source.Range?
    let extras: StatementExtras?

    init?(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) {
        self.syntax = syntax
        self.file = syntaxTree.source.file
        self.range = syntax.range(in: syntaxTree.source)
        self.extras = extras
        self.sourceCode = syntax.sourceCode(in: syntaxTree.source)
        self.message = .unsupportedSyntax(source: syntaxTree.source, range: range)
    }

    var prettyPrintChildren: [PrettyPrintTree] {
        return [PrettyPrintTree(root: sourceCode)]
    }
}

struct MessageStatement: Statement {
    var type: StatementType { .message }
    let message: Message?

    init(message: Message) {
        self.message = message
    }

    init?(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) {
        return nil
    }
}
