import SwiftSyntax

struct IfDefined: Statement {
    let symbol: String
    let statements: [Statement]

    init(symbol: String, statements: [Statement]) {
        self.syntax = nil
        self.file = nil
        self.range = nil
        self.extras = nil
        self.symbol = symbol
        self.statements = statements
    }

    var type: StatementType { .ifDefined }
    let syntax: Syntax?
    let file: Source.File?
    let range: Source.Range?
    let extras: StatementExtras?

    static func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard let statement = IfDefined(syntax: syntax, extras: extras, in: syntaxTree) else {
            return nil
        }
        return [statement]
    }

    private init?(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) {
        guard let ifConfigDecl = syntax.as(IfConfigDeclSyntax.self) else {
            return nil
        }

        self.syntax = syntax
        self.file = syntaxTree.source.file
        self.range = syntax.range(in: syntaxTree.source)
        self.extras = extras

        // Look for a clause that matches a defined symbol, or an 'else'
        for clause in ifConfigDecl.clauses {
            let symbol = clause.condition?.description ?? ""
            guard symbol == "SKIP" || syntaxTree.preprocessorSymbols.contains(symbol) || clause.poundKeyword.text == "#else" else {
                continue
            }
            self.symbol = symbol.isEmpty ? "#else" : symbol
            self.statements = Self.extractStatements(from: clause, in: syntaxTree)
            return
        }
        // Didn't find a match
        self.symbol = ifConfigDecl.clauses.first?.condition?.description ?? ""
        self.statements = []
    }

    private static func extractStatements(from clause: IfConfigClauseSyntax, in syntaxTree: SyntaxTree) -> [Statement] {
        guard let elements = clause.elements else {
            return []
        }
        switch elements {
        case .statements(let syntax):
            return syntaxTree.process(syntaxList: syntax)
        case .switchCases(let syntax):
            return [RawStatement(syntax: Syntax(syntax), extras: nil, in: syntaxTree)]
        case .decls(let syntax):
            return syntaxTree.process(syntaxList: syntax)
        case .postfixExpression(let syntax):
            return [RawStatement(syntax: Syntax(syntax), extras: nil, in: syntaxTree)]
        case .attributes(let syntax):
            return [RawStatement(syntax: Syntax(syntax), extras: nil, in: syntaxTree)]
        }
    }

    var children: [Statement] {
        return statements
    }

    var prettyPrintChildren: [PrettyPrintTree] {
        return [PrettyPrintTree(root: symbol)]
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

    static func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard let statement = ImportDeclaration(syntax: syntax, extras: extras, in: syntaxTree) else {
            return nil
        }
        return [statement]
    }

    private init?(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) {
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

struct MessageStatement: Statement {
    var type: StatementType { .message }
    let message: Message?

    init(message: Message) {
        self.message = message
    }

    static func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        return nil
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

    static func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard let statement = ProtocolDeclaration(syntax: syntax, extras: extras, in: syntaxTree) else {
            return nil
        }
        return [statement]
    }

    private init?(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) {
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

    init(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) {
        self.syntax = syntax
        self.file = syntaxTree.source.file
        self.range = syntax.range(in: syntaxTree.source)
        self.extras = extras
        self.sourceCode = syntax.sourceCode(in: syntaxTree.source)
        self.message = .unsupportedSyntax(source: syntaxTree.source, range: range)
    }

    var type: StatementType { .raw }
    let syntax: Syntax?
    let file: Source.File?
    let range: Source.Range?
    let extras: StatementExtras?

    static func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        return nil
    }

    var prettyPrintChildren: [PrettyPrintTree] {
        return [PrettyPrintTree(root: sourceCode)]
    }
}

struct VariableDeclaration: Statement {
    var type: StatementType { .variableDeclaration }
    let syntax: Syntax?
    let file: Source.File?
    let range: Source.Range?
    let extras: StatementExtras?

    static func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        return nil
    }
}
