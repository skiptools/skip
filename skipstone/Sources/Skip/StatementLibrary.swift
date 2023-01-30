import SwiftSyntax

class IfDefined: Statement {
    let symbol: String
    let statements: [Statement]

    init(symbol: String, statements: [Statement] = [], syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.symbol = symbol
        self.statements = statements
        super.init(type: .ifDefined, syntax: syntax, file: file, range: range, extras: extras)
    }

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard syntax.kind == .ifConfigDecl, let ifConfigDecl = syntax.as(IfConfigDeclSyntax.self) else {
            return nil
        }

        // Look for a clause that matches a defined symbol, or an 'else'
        var symbol: String? = nil
        var clause: IfConfigClauseSyntax? = nil
        for ifConfigClause in ifConfigDecl.clauses {
            let clauseSymbol = ifConfigClause.condition?.description ?? ""
            guard clauseSymbol == "SKIP" || syntaxTree.preprocessorSymbols.contains(clauseSymbol) || ifConfigClause.poundKeyword.text == "#else" else {
                continue
            }
            symbol = clauseSymbol.isEmpty ? "#else" : clauseSymbol
            clause = ifConfigClause
            break
        }

        let resolvedSymbol = symbol ?? ifConfigDecl.clauses.first?.condition?.description ?? ""
        let statements = extractStatements(from: clause, in: syntaxTree)
        let statement = IfDefined(symbol: resolvedSymbol, statements: statements, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
        return [statement]
    }

    private static func extractStatements(from clause: IfConfigClauseSyntax?, in syntaxTree: SyntaxTree) -> [Statement] {
        guard let elements = clause?.elements else {
            return []
        }
        switch elements {
        case .statements(let syntax):
            return StatementDecoder.decode(syntaxList: syntax, in: syntaxTree)
        case .switchCases(let syntax):
            return [RawStatement(syntax: Syntax(syntax), in: syntaxTree)]
        case .decls(let syntax):
            return StatementDecoder.decode(syntaxList: syntax, in: syntaxTree)
        case .postfixExpression(let syntax):
            return [RawStatement(syntax: Syntax(syntax), in: syntaxTree)]
        case .attributes(let syntax):
            return [RawStatement(syntax: Syntax(syntax), in: syntaxTree)]
        }
    }

    override var children: [Statement] {
        return statements
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: symbol)]
    }
}

class MessageStatement: Statement {
    init(message: Message) {
        super.init(type: .message)
        self.message = message
    }

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        return nil
    }
}

class RawStatement: Statement {
    let sourceCode: String

    init(sourceCode: String, message: Message? = nil, syntax: Syntax? = nil, extras: StatementExtras? = nil, in syntaxTree: SyntaxTree? = nil) {
        self.sourceCode = sourceCode
        var range: Source.Range? = nil
        if let source = syntaxTree?.source {
            range = syntax?.range(in: source)
        }
        super.init(type: .raw, syntax: syntax, file: syntaxTree?.source.file, range: range, extras: extras)
        self.message = message
    }

    init(syntax: Syntax, extras: StatementExtras? = nil, in syntaxTree: SyntaxTree) {
        self.sourceCode = syntax.sourceCode(in: syntaxTree.source)
        let source = syntaxTree.source
        let range = syntax.range(in: source)
        super.init(type: .raw, syntax: syntax, file: source.file, range: range, extras: extras)
        self.message = .unsupportedSyntax(source: source, range: range)
    }

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        return nil
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: sourceCode)]
    }
}

// MARK: - Declarations

// TODO: Generics
class ExtensionDeclaration: Statement {
    let extends: TypeSignature
    let inherits: [TypeSignature]
    let modifiers: Modifiers
    let members: [Statement]

    init(extends: TypeSignature, inherits: [TypeSignature] = [], modifiers: Modifiers? = nil, members: [Statement] = [], syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.extends = extends
        self.inherits = inherits
        self.modifiers = modifiers ?? Modifiers()
        self.members = members
        super.init(type: .extensionDeclaration, syntax: syntax, file: file, range: range, extras: extras)
    }

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard syntax.kind == .extensionDecl, let extensionDecl = syntax.as(ExtensionDeclSyntax.self), let extends = TypeSignature.for(syntax: extensionDecl.extendedType) else {
            return nil
        }
        let (inherits, message) = extensionDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        let modifiers = Modifiers.for(syntax: extensionDecl.modifiers)
        let members = StatementDecoder.decode(syntaxListContainer: extensionDecl.members, in: syntaxTree)
        let statement = ExtensionDeclaration(extends: extends, inherits: inherits, modifiers: modifiers, members: members, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
        statement.message = message
        return [statement]
    }

    override var children: [Statement] {
        return members
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var attrs = [PrettyPrintTree(root: extends.description)]
        if !inherits.isEmpty {
            attrs.append(PrettyPrintTree(root: "inherits", children: inherits.map { PrettyPrintTree(root: $0.description) }))
        }
        if !modifiers.isEmpty {
            attrs.append(modifiers.prettyPrintTree)
        }
        return attrs
    }
}

// TODO: Generics
class FunctionDeclaration: Statement {
    let name: String
    private(set) var returnType: TypeSignature?
    private(set) var parameters: [Parameter<Statement>]
    let isAsync: Bool
    let isThrows: Bool
    let modifiers: Modifiers
    let body: CodeBlock<Statement>?

    init(name: String, returnType: TypeSignature?, parameters: [Parameter<Statement>], isAsync: Bool = false, isThrows: Bool = false, modifiers: Modifiers? = nil, body: CodeBlock<Statement>? = nil, syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.name = name
        self.returnType = returnType
        self.parameters = parameters
        self.isAsync = isAsync
        self.isThrows = isThrows
        self.modifiers = modifiers ?? Modifiers()
        self.body = body
        super.init(type: .functionDeclaration, syntax: syntax, file: file, range: range, extras: extras)
    }

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard syntax.kind == .functionDecl, let functionDecl = syntax.as(FunctionDeclSyntax.self) else {
            return nil
        }
        let name = functionDecl.identifier.text
        let (returnType, parameters, message) = functionDecl.signature.typeSignatures(in: syntaxTree)
        let isAsync = functionDecl.signature.asyncOrReasyncKeyword?.text == "async" || functionDecl.signature.throwsOrRethrowsKeyword?.text == "async"
        let isThrows = functionDecl.signature.asyncOrReasyncKeyword?.text == "throws" || functionDecl.signature.throwsOrRethrowsKeyword?.text == "throws"
        let modifiers = Modifiers.for(syntax: functionDecl.modifiers)
        var body: CodeBlock<Statement>? = nil
        if let bodySyntax = functionDecl.body {
            body = CodeBlock(statements: StatementDecoder.decode(syntaxListContainer: bodySyntax, in: syntaxTree))
        }
        let statement = FunctionDeclaration(name: name, returnType: returnType, parameters: parameters, isAsync: isAsync, isThrows: isThrows, modifiers: modifiers, body: body, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
        statement.message = message
        return [statement]
    }

    override func resolveSelf() {
        if let returnType {
            self.returnType = returnType.qualified(in: self)
        }
        parameters = parameters.map { $0.qualifiedType(in: self) }
    }

    override var children: [Statement] {
        return parameters.compactMap { $0.defaultValue } + (body?.statements ?? [])
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var attrs = [PrettyPrintTree(root: name)]
        if let returnType {
            attrs.append(PrettyPrintTree(root: returnType.description))
        }
        if !parameters.isEmpty {
            attrs.append(PrettyPrintTree(root: "parameters", children: parameters.map { $0.prettyPrintTree }))
        }
        if !modifiers.isEmpty {
            attrs.append(modifiers.prettyPrintTree)
        }
        return attrs
    }
}

class ImportDeclaration: Statement {
    let modulePath: [String]

    init(modulePath: [String], syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.modulePath = modulePath
        super.init(type: .importDeclaration, syntax: syntax, file: file, range: range, extras: extras)
    }

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard syntax.kind == .importDecl, let importDecl = syntax.as(ImportDeclSyntax.self) else {
            return nil
        }
        let modulePath = importDecl.path.map { $0.name.text }
        let statement = ImportDeclaration(modulePath: modulePath, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
        return [statement]
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: modulePath.joined(separator: "."))]
    }
}

// TODO: Generics
class TypeDeclaration: Statement {
    let name: String
    private(set) var inherits: [TypeSignature]
    let modifiers: Modifiers
    let members: [Statement]

    var qualifiedName: String {
        get {
            return _qualifiedName ?? name
        }
        set {
            _qualifiedName = newValue
        }
    }
    private var _qualifiedName: String?

    init(type: StatementType, name: String, qualifiedName: String? = nil, inherits: [TypeSignature] = [], modifiers: Modifiers? = nil, members: [Statement] = [], syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.name = name
        _qualifiedName = qualifiedName
        self.inherits = inherits
        self.modifiers = modifiers ?? Modifiers()
        self.members = members
        super.init(type: type, syntax: syntax, file: file, range: range, extras: extras)
    }

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        if syntax.kind == .classDecl, let classDecl = syntax.as(ClassDeclSyntax.self) {
            return [decodeClassDeclaration(classDecl, syntax: syntax, extras: extras, in: syntaxTree)]
        } else if syntax.kind == .structDecl, let structDecl = syntax.as(StructDeclSyntax.self) {
            return [decodeStructDeclaration(structDecl, syntax: syntax, extras: extras, in: syntaxTree)]
        } else if syntax.kind == .protocolDecl, let protocolDecl = syntax.as(ProtocolDeclSyntax.self) {
            return [decodeProtocolDeclaration(protocolDecl, syntax: syntax, extras: extras, in: syntaxTree)]
        } else if syntax.kind == .enumDecl, let enumDecl = syntax.as(EnumDeclSyntax.self) {
            return [decodeEnumDeclaration(enumDecl, syntax: syntax, extras: extras, in: syntaxTree)]
        }
        return nil
    }

    private static func decodeClassDeclaration(_ classDecl: ClassDeclSyntax, syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> TypeDeclaration {
        let name = classDecl.identifier.text
        let (inherits, message) = classDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        let modifiers = Modifiers.for(syntax: classDecl.modifiers)
        let members = StatementDecoder.decode(syntaxListContainer: classDecl.members, in: syntaxTree)
        let statement = TypeDeclaration(type: .classDeclaration, name: name, inherits: inherits, modifiers: modifiers, members: members, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
        statement.message = message
        return statement
    }

    private static func decodeStructDeclaration(_ structDecl: StructDeclSyntax, syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> TypeDeclaration {
        let name = structDecl.identifier.text
        let (inherits, message) = structDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        let modifiers = Modifiers.for(syntax: structDecl.modifiers)
        let members = StatementDecoder.decode(syntaxListContainer: structDecl.members, in: syntaxTree)
        let statement = TypeDeclaration(type: .structDeclaration, name: name, inherits: inherits, modifiers: modifiers, members: members, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
        statement.message = message
        return statement
    }

    private static func decodeProtocolDeclaration(_ protocolDecl: ProtocolDeclSyntax, syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> TypeDeclaration {
        let name = protocolDecl.identifier.text
        let (inherits, message) = protocolDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        let modifiers = Modifiers.for(syntax: protocolDecl.modifiers)
        let members = StatementDecoder.decode(syntaxListContainer: protocolDecl.members, in: syntaxTree)
        let statement = TypeDeclaration(type: .protocolDeclaration, name: name, inherits: inherits, modifiers: modifiers, members: members, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
        statement.message = message
        return statement
    }

    private static func decodeEnumDeclaration(_ enumDecl: EnumDeclSyntax, syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> TypeDeclaration {
        let name = enumDecl.identifier.text
        let (inherits, message) = enumDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        let modifiers = Modifiers.for(syntax: enumDecl.modifiers)
        let members = StatementDecoder.decode(syntaxListContainer: enumDecl.members, in: syntaxTree)
        let statement = TypeDeclaration(type: .enumDeclaration, name: name, inherits: inherits, modifiers: modifiers, members: members, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
        statement.message = message
        return statement
    }

    override func resolveSelf() {
        if _qualifiedName == nil {
            _qualifiedName = StatementDecoder.qualifyDeclaredTypeName(name, declaration: self)
        }
        inherits = inherits.map { $0.qualified(in: self) }
    }

    override var children: [Statement] {
        return members
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var attrs = [PrettyPrintTree(root: name)]
        if !inherits.isEmpty {
            attrs.append(PrettyPrintTree(root: "inherits", children: inherits.map { PrettyPrintTree(root: $0.description) }))
        }
        if !modifiers.isEmpty {
            attrs.append(modifiers.prettyPrintTree)
        }
        return attrs
    }
}
