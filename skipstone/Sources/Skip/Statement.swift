import SwiftSyntax

/// A node in the Swift syntax tree.
protocol Statement {
    var type: StatementType { get }
    var syntax: Syntax? { get }
    var range: Source.Range? { get }

    /// Pretty-printable tree rooted on this syntax statement.
    var prettyPrintTree: PrettyPrintTree { get }

    /// Attempt to construct this statement type from the given syntax.
    init?(syntax: Syntax, source: Source)
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

    /// A statement that only exists in the target language.
    case targetLanguage

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
        case .targetLanguage:
            return nil
        }
    }
}

struct StatementFactory {
    func `for`(syntax: Syntax, in source: Source) -> Statement? {
        for statementType in StatementType.allCases {
            if let representingType = statementType.representingType, let statement = representingType.init(syntax: syntax, source: source) {
                return statement
            }
        }
        return nil
    }
}

struct ImportDeclaration: Statement {
    var type: StatementType { .importDeclaration }
    let syntax: Syntax?
    let range: Source.Range?
    let moduleName: String

    init(moduleName: String) {
        self.syntax = nil
        self.range = nil
        self.moduleName = moduleName
    }

    init?(syntax: Syntax, source: Source) {
        guard let importDecl = syntax.as(ImportDeclSyntax.self) else {
            return nil
        }
        self.syntax = syntax
        self.range = source.range(of: syntax)
        self.moduleName = importDecl.path.sourceCode(in: source)
    }

    var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintTree(root: String(describing: self.type), children: [
            PrettyPrintTree(root: moduleName)
        ])
    }
}
