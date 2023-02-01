import SwiftSyntax

/// `#if SYMBOL ... #endif`
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

    init(syntax: Syntax, extras: StatementExtras? = nil, in syntaxTree: SyntaxTree) {
        self.sourceCode = syntax.sourceCode(in: syntaxTree.source)
        let source = syntaxTree.source
        let range = syntax.range(in: source)
        super.init(type: .raw, syntax: syntax, file: source.file, range: range, extras: extras)
        self.statementMessages = [.unsupportedSyntax(source: source, range: range)]
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
/// `extension Type { ... }`
class ExtensionDeclaration: TypeDeclaration {
    let extends: TypeSignature

    init(extends: TypeSignature, inherits: [TypeSignature] = [], modifiers: Modifiers? = nil, members: [Statement] = [], syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.extends = extends
        super.init(type: .extensionDeclaration, name: extends.description, qualifiedName: extends.description, inherits: inherits, modifiers: modifiers, members: members, syntax: syntax, file: file, range: range, extras: extras)
    }

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard syntax.kind == .extensionDecl, let extensionDecl = syntax.as(ExtensionDeclSyntax.self), let extends = TypeSignature.for(syntax: extensionDecl.extendedType) else {
            return nil
        }
        let (inherits, messages) = extensionDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        let modifiers = Modifiers.for(syntax: extensionDecl.modifiers)
        let members = StatementDecoder.decode(syntaxListContainer: extensionDecl.members, in: syntaxTree)
        let statement = ExtensionDeclaration(extends: extends, inherits: inherits, modifiers: modifiers, members: members, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
        statement.statementMessages = messages ?? []
        return [statement]
    }
}

// TODO: Generics
/// `func f() { ... }`
class FunctionDeclaration: Statement {
    let name: String
    private(set) var returnType: TypeSignature?
    private(set) var parameters: [Parameter<Statement>]
    let isAsync: Bool
    let isThrows: Bool
    private(set) var modifiers: Modifiers
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
        let (returnType, parameters, messages) = functionDecl.signature.typeSignatures(in: syntaxTree)
        let isAsync = functionDecl.signature.asyncOrReasyncKeyword?.text == "async" || functionDecl.signature.throwsOrRethrowsKeyword?.text == "async"
        let isThrows = functionDecl.signature.asyncOrReasyncKeyword?.text == "throws" || functionDecl.signature.throwsOrRethrowsKeyword?.text == "throws"
        let modifiers = Modifiers.for(syntax: functionDecl.modifiers)
        var body: CodeBlock<Statement>? = nil
        if let bodySyntax = functionDecl.body {
            body = CodeBlock(statements: StatementDecoder.decode(syntaxListContainer: bodySyntax, in: syntaxTree))
        }
        let statement = FunctionDeclaration(name: name, returnType: returnType, parameters: parameters, isAsync: isAsync, isThrows: isThrows, modifiers: modifiers, body: body, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
        statement.statementMessages = messages
        return [statement]
    }

    override func resolve() {
        if let returnType {
            self.returnType = returnType.qualified(in: self)
        }
        parameters = parameters.map { $0.qualifiedType(in: self) }
        // Functions in protocols or extensions inherit the visibility of the protocol or extension
        if modifiers.visibility == .default, let owningTypeDeclaration, (owningTypeDeclaration.type == .protocolDeclaration || owningTypeDeclaration.type == .extensionDeclaration) {
            modifiers.visibility = owningTypeDeclaration.modifiers.visibility
        }
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
        if isAsync {
            attrs.append(PrettyPrintTree(root: "async"))
        }
        if isThrows {
            attrs.append(PrettyPrintTree(root: "throws"))
        }
        if !modifiers.isEmpty {
            attrs.append(modifiers.prettyPrintTree)
        }
        return attrs
    }
}

/// `import Module`
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
/// `class/struct/enum Type { ... }`
class TypeDeclaration: Statement {
    let name: String
    private(set) var inherits: [TypeSignature]
    let modifiers: Modifiers
    let members: [Statement]
    var qualifiedName: String {
        return _qualifiedName ?? name
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
        let (inherits, messages) = classDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        let modifiers = Modifiers.for(syntax: classDecl.modifiers)
        let members = StatementDecoder.decode(syntaxListContainer: classDecl.members, in: syntaxTree)
        let statement = TypeDeclaration(type: .classDeclaration, name: name, inherits: inherits, modifiers: modifiers, members: members, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
        statement.statementMessages = messages ?? []
        return statement
    }

    private static func decodeStructDeclaration(_ structDecl: StructDeclSyntax, syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> TypeDeclaration {
        let name = structDecl.identifier.text
        let (inherits, messages) = structDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        let modifiers = Modifiers.for(syntax: structDecl.modifiers)
        let members = StatementDecoder.decode(syntaxListContainer: structDecl.members, in: syntaxTree)
        let statement = TypeDeclaration(type: .structDeclaration, name: name, inherits: inherits, modifiers: modifiers, members: members, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
        statement.statementMessages = messages ?? []
        return statement
    }

    private static func decodeProtocolDeclaration(_ protocolDecl: ProtocolDeclSyntax, syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> TypeDeclaration {
        let name = protocolDecl.identifier.text
        let (inherits, messages) = protocolDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        let modifiers = Modifiers.for(syntax: protocolDecl.modifiers)
        let members = StatementDecoder.decode(syntaxListContainer: protocolDecl.members, in: syntaxTree)
        let statement = TypeDeclaration(type: .protocolDeclaration, name: name, inherits: inherits, modifiers: modifiers, members: members, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
        statement.statementMessages = messages ?? []
        return statement
    }

    private static func decodeEnumDeclaration(_ enumDecl: EnumDeclSyntax, syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> TypeDeclaration {
        let name = enumDecl.identifier.text
        let (inherits, messages) = enumDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        let modifiers = Modifiers.for(syntax: enumDecl.modifiers)
        let members = StatementDecoder.decode(syntaxListContainer: enumDecl.members, in: syntaxTree)
        let statement = TypeDeclaration(type: .enumDeclaration, name: name, inherits: inherits, modifiers: modifiers, members: members, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
        statement.statementMessages = messages ?? []
        return statement
    }

    override func resolve() {
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

// TODO: Property wrappers?, generics, patterns (tuple deconstruction, etc)
/// `let/var v ...`
class VariableDeclaration: Statement {
    let name: String
    private(set) var declaredType: TypeSignature?
    let isLet: Bool
    let isAsync: Bool
    let isThrows: Bool
    private(set) var modifiers: Modifiers
    let value: Statement?
    let getter: Accessor<Statement>?
    let setter: Accessor<Statement>?
    let willSet: Accessor<Statement>?
    let didSet: Accessor<Statement>?

    init(name: String, declaredType: TypeSignature?, isLet: Bool = false, isAsync: Bool = false, isThrows: Bool = false, modifiers: Modifiers? = nil, value: Statement?, getter: Accessor<Statement>? = nil, setter: Accessor<Statement>? = nil, willSet: Accessor<Statement>? = nil, didSet: Accessor<Statement>? = nil, syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.name = name
        self.declaredType = declaredType
        self.isLet = isLet
        self.isAsync = isAsync
        self.isThrows = isThrows
        self.modifiers = modifiers ?? Modifiers()
        self.value = value
        self.getter = getter
        self.setter = setter
        self.willSet = willSet
        self.didSet = didSet
        super.init(type: .variableDeclaration, syntax: syntax, file: file, range: range, extras: extras)
    }

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard syntax.kind == .variableDecl, let variableDecl = syntax.as(VariableDeclSyntax.self) else {
            return nil
        }

        let isLet = variableDecl.letOrVarKeyword.text == "let"
        let modifiers = Modifiers.for(syntax: variableDecl.modifiers)
        var statements: [Statement] = []
        for entry in variableDecl.bindings.enumerated() {
            let bindingExtras = entry.offset == 0 ? extras : nil
            let statement = decode(syntax: entry.element, isLet: isLet, modifiers: modifiers, extras: bindingExtras, in: syntaxTree)
            statements.append(statement)
        }
        return statements
    }

    private static func decode(syntax: PatternBindingSyntax, isLet: Bool, modifiers: Modifiers?, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> Statement {
        var declaredType: TypeSignature? = nil
        if let typeSyntax = syntax.typeAnnotation?.type {
            declaredType = TypeSignature.for(syntax: typeSyntax)
        }
        var value: Statement? = nil
        if let valueSyntax = syntax.initializer?.value {
            value = StatementDecoder.decode(syntax: Syntax(valueSyntax), in: syntaxTree).first
        }

        var getter: Accessor<Statement>? = nil
        var setter: Accessor<Statement>? = nil
        var willSet: Accessor<Statement>? = nil
        var didSet: Accessor<Statement>? = nil
        var isAsync = false
        var isThrows = false
        var messages: [Message] = []
        if let accessor = syntax.accessor {
            switch accessor {
            case .accessors(let accessorListSyntax):
                for accessorSyntax in accessorListSyntax.accessors {
                    if accessorSyntax.throwsKeyword?.text == "throws" || accessorSyntax.asyncKeyword?.text == "throws" {
                        isThrows = true
                    }
                    if accessorSyntax.throwsKeyword?.text == "async" || accessorSyntax.asyncKeyword?.text == "async" {
                        isAsync = true
                    }
                    var statements: [Statement]? = nil
                    if let body = accessorSyntax.body {
                        statements = StatementDecoder.decode(syntaxListContainer: body, in: syntaxTree)
                    }

                    switch accessorSyntax.accessorKind.text {
                    case "get":
                        getter = Accessor(statements: statements)
                    case "set":
                        let parameterName = accessorSyntax.parameter?.name.text
                        setter = Accessor(parameterName: parameterName, statements: statements)
                    case "willSet":
                        willSet = Accessor(statements: statements)
                    case "didSet":
                        didSet = Accessor(statements: statements)
                    default:
                        messages.append(.unsupportedSyntax(source: syntaxTree.source, range: syntax.range(in: syntaxTree.source)))
                    }
                }
            case .getter(let codeBlockSyntax):
                getter = Accessor(statements: StatementDecoder.decode(syntaxListContainer: codeBlockSyntax, in: syntaxTree))
            }
        }

        // TODO: Support patterns other than a simple identifier
        switch syntax.pattern.kind {
        case .expressionPattern:
            return RawStatement(syntax: Syntax(syntax), in: syntaxTree)
        case .identifierPattern:
            let name = syntax.pattern.as(IdentifierPatternSyntax.self)!.identifier.text
            let declaration = VariableDeclaration(name: name, declaredType: declaredType, isLet: isLet, isAsync: isAsync, isThrows: isThrows, modifiers: modifiers, value: value, getter: getter, setter: setter, willSet: willSet, didSet: didSet, syntax: Syntax(syntax), file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
            declaration.statementMessages = messages
            return declaration
        case .isTypePattern:
            return RawStatement(syntax: Syntax(syntax), in: syntaxTree)
        case .missingPattern:
            return RawStatement(syntax: Syntax(syntax), in: syntaxTree)
        case .tuplePattern:
            return RawStatement(syntax: Syntax(syntax), in: syntaxTree)
        case .valueBindingPattern:
            return RawStatement(syntax: Syntax(syntax), in: syntaxTree)
        case .wildcardPattern:
            return RawStatement(syntax: Syntax(syntax), in: syntaxTree)
        default:
            return RawStatement(syntax: Syntax(syntax), in: syntaxTree)
        }
    }

    override func resolve() {
        if let declaredType {
            self.declaredType = declaredType.qualified(in: self)
        }
        // Variables in protocols or extensions inherit the visibility of the protocol or extension
        if modifiers.visibility == .default, let owningTypeDeclaration, (owningTypeDeclaration.type == .protocolDeclaration || owningTypeDeclaration.type == .extensionDeclaration) {
            modifiers.visibility = owningTypeDeclaration.modifiers.visibility
        }
    }

    override var children: [Statement] {
        var children: [Statement] = []
        if let value {
            children.append(value)
        }
        if let statements = getter?.statements {
            children += statements
        }
        if let statements = setter?.statements {
            children += statements
        }
        if let statements = willSet?.statements {
            children += statements
        }
        if let statements = didSet?.statements {
            children += statements
        }
        return children
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var attrs = [PrettyPrintTree(root: name)]
        if let declaredType {
            attrs.append(PrettyPrintTree(root: declaredType.description))
        }
        if isAsync {
            attrs.append(PrettyPrintTree(root: "async"))
        }
        if isThrows {
            attrs.append(PrettyPrintTree(root: "throws"))
        }
        if !modifiers.isEmpty {
            attrs.append(modifiers.prettyPrintTree)
        }
        return attrs
    }
}
