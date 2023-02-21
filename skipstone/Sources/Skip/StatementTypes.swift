import SwiftSyntax

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
            return FunctionDeclaration.self
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

/// `#if SYMBOL ... #endif`
///
/// - Note: We never instantiate this class. It is only used ot extract the statements from an `#if`.
class IfDefined: Statement {
    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        guard syntax.kind == .ifConfigDecl, let ifConfigDecl = syntax.as(IfConfigDeclSyntax.self) else {
            return nil
        }

        // Look for a clause that matches a defined symbol, or an 'else'
        var clause: IfConfigClauseSyntax? = nil
        for ifConfigClause in ifConfigDecl.clauses {
            let clauseSymbol = ifConfigClause.condition?.description ?? ""
            guard clauseSymbol == "SKIP" || syntaxTree.preprocessorSymbols.contains(clauseSymbol) || ifConfigClause.poundKeyword.text == "#else" else {
                continue
            }
            clause = ifConfigClause
            break
        }
        return try extractStatements(from: clause, in: syntaxTree)
    }

    private static func extractStatements(from clause: IfConfigClauseSyntax?, in syntaxTree: SyntaxTree) throws -> [Statement] {
        guard let elements = clause?.elements else {
            return []
        }
        switch elements {
        case .statements(let syntax):
            return StatementDecoder.decode(syntaxList: syntax, in: syntaxTree)
        case .switchCases(let syntax):
            return [RawStatement(syntax: syntax, in: syntaxTree)]
        case .decls(let syntax):
            return StatementDecoder.decode(syntaxList: syntax, in: syntaxTree)
        case .postfixExpression(let syntax):
            throw Message.unsupportedSyntax(syntax, source: syntaxTree.source)
        case .attributes(let syntax):
            throw Message.unsupportedSyntax(syntax, source: syntaxTree.source)
        }
    }
}

class Return: ExpressionStatement {
    init(expression: Expression? = nil, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        super.init(type: .return, expression: expression, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        guard syntax.kind == .returnStmt, let returnStmnt = syntax.as(ReturnStmtSyntax.self) else {
            return nil
        }

        var expression: Expression? = nil
        if let expressionSyntax = returnStmnt.expression {
            expression = ExpressionDecoder.decode(syntax: expressionSyntax, in: syntaxTree)
        }
        let statement = Return(expression: expression, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)
        return [statement]
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        expression?.inferTypes(context: context, expecting: expecting.or(context.expectedReturn))
        return context
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: "return")] + super.prettyPrintAttributes
    }
}


// MARK: - Declarations

// TODO: Generics
/// `extension Type { ... }`
class ExtensionDeclaration: TypeDeclaration {
    let extends: TypeSignature

    init(extends: TypeSignature, inherits: [TypeSignature] = [], attributes: Attributes? = nil, modifiers: Modifiers? = nil, members: [Statement] = [], syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.extends = extends
        super.init(type: .extensionDeclaration, name: extends.description, qualifiedName: extends.description, inherits: inherits, attributes: attributes, modifiers: modifiers, members: members, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard syntax.kind == .extensionDecl, let extensionDecl = syntax.as(ExtensionDeclSyntax.self) else {
            return nil
        }
        let extends = TypeSignature.for(syntax: extensionDecl.extendedType)
        guard extends != .none else {
            return nil
        }
        let (inherits, messages) = extensionDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], [])
        let attributes = Attributes.for(syntax: extensionDecl.attributes)
        let modifiers = Modifiers.for(syntax: extensionDecl.modifiers)
        let members = StatementDecoder.decode(syntaxListContainer: extensionDecl.members, in: syntaxTree)
        let statement = ExtensionDeclaration(extends: extends, inherits: inherits, attributes: attributes, modifiers: modifiers, members: members, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)
        statement.messages = messages
        return [statement]
    }
}

// TODO: Generics
/// `func f() { ... }`
class FunctionDeclaration: Statement {
    let name: String
    let isOptionalInit: Bool
    private(set) var returnType: TypeSignature
    private(set) var parameters: [Parameter<Expression>]
    let isAsync: Bool
    let isThrows: Bool
    let attributes: Attributes
    private(set) var modifiers: Modifiers
    let body: CodeBlock<Statement>?

    init(type: StatementType, name: String, isOptionalInit: Bool = false, returnType: TypeSignature = .void, parameters: [Parameter<Expression>], isAsync: Bool = false, isThrows: Bool = false, attributes: Attributes? = nil, modifiers: Modifiers? = nil, body: CodeBlock<Statement>? = nil, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.name = name
        self.isOptionalInit = isOptionalInit
        self.returnType = returnType
        self.parameters = parameters
        self.isAsync = isAsync
        self.isThrows = isThrows
        self.attributes = attributes ?? Attributes()
        self.modifiers = modifiers ?? Modifiers()
        self.body = body
        super.init(type: type, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        if syntax.kind == .functionDecl, let functionDecl = syntax.as(FunctionDeclSyntax.self) {
            return [decodeFunctionDeclaration(functionDecl, extras: extras, in: syntaxTree)]
        } else if syntax.kind == .initializerDecl, let initializerDecl = syntax.as(InitializerDeclSyntax.self) {
            return [decodeInitializerDeclaration(initializerDecl, extras: extras, in: syntaxTree)]
        } else {
            return nil
        }
    }

    private static func decodeFunctionDeclaration(_ functionDecl: FunctionDeclSyntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> FunctionDeclaration {
        let name = functionDecl.identifier.text
        let (returnType, parameters, messages) = functionDecl.signature.typeSignatures(in: syntaxTree)
        let isAsync = functionDecl.signature.asyncOrReasyncKeyword?.text == "async" || functionDecl.signature.throwsOrRethrowsKeyword?.text == "async"
        let isThrows = functionDecl.signature.asyncOrReasyncKeyword?.text == "throws" || functionDecl.signature.throwsOrRethrowsKeyword?.text == "throws"
        let attributes = Attributes.for(syntax: functionDecl.attributes)
        let modifiers = Modifiers.for(syntax: functionDecl.modifiers)
        var body: CodeBlock<Statement>? = nil
        if let bodySyntax = functionDecl.body {
            body = CodeBlock(statements: StatementDecoder.decode(syntaxListContainer: bodySyntax, in: syntaxTree))
        }
        let statement = FunctionDeclaration(type: .functionDeclaration, name: name, returnType: returnType, parameters: parameters, isAsync: isAsync, isThrows: isThrows, attributes: attributes, modifiers: modifiers, body: body, syntax: functionDecl, sourceFile: syntaxTree.source.file, sourceRange: functionDecl.range(in: syntaxTree.source), extras: extras)
        statement.messages = messages
        return statement
    }

    private static func decodeInitializerDeclaration(_ initializerDecl: InitializerDeclSyntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> FunctionDeclaration {
        let isOptionalInit = initializerDecl.optionalMark != nil
        let (_, parameters, messages) = initializerDecl.signature.typeSignatures(in: syntaxTree)
        let isAsync = initializerDecl.signature.asyncOrReasyncKeyword?.text == "async" || initializerDecl.signature.throwsOrRethrowsKeyword?.text == "async"
        let isThrows = initializerDecl.signature.asyncOrReasyncKeyword?.text == "throws" || initializerDecl.signature.throwsOrRethrowsKeyword?.text == "throws"
        let attributes = Attributes.for(syntax: initializerDecl.attributes)
        let modifiers = Modifiers.for(syntax: initializerDecl.modifiers)
        var body: CodeBlock<Statement>? = nil
        if let bodySyntax = initializerDecl.body {
            body = CodeBlock(statements: StatementDecoder.decode(syntaxListContainer: bodySyntax, in: syntaxTree))
        }
        let statement = FunctionDeclaration(type: .initDeclaration, name: "init", isOptionalInit: isOptionalInit, returnType: .void, parameters: parameters, isAsync: isAsync, isThrows: isThrows, attributes: attributes, modifiers: modifiers, body: body, syntax: initializerDecl, sourceFile: syntaxTree.source.file, sourceRange: initializerDecl.range(in: syntaxTree.source), extras: extras)
        statement.messages = messages
        return statement
    }

    override func resolveAttributes() {
        returnType = returnType.qualified(in: self)
        parameters = parameters.map { $0.qualifiedType(in: self) }
        // Functions in protocols or extensions inherit the visibility of the protocol or extension
        if modifiers.visibility == .default, let owningTypeDeclaration = parent as? TypeDeclaration, (owningTypeDeclaration.type == .protocolDeclaration || owningTypeDeclaration.type == .extensionDeclaration) {
            modifiers.visibility = owningTypeDeclaration.modifiers.visibility
        }
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        parameters.forEach { $0.defaultValue?.inferTypes(context: context, expecting: $0.declaredType) }
        if let statements = body?.statements {
            var bodyContext = context.pushing(self)
            statements.forEach { bodyContext = $0.inferTypes(context: bodyContext, expecting: .none) }
        }
        return context
    }

    override var children: [SyntaxNode] {
        return parameters.compactMap { $0.defaultValue } + (body?.statements ?? [])
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var attrs = [PrettyPrintTree(root: name)]
        if returnType != .none {
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
        if !attributes.isEmpty {
            attrs.append(attributes.prettyPrintTree)
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

    init(modulePath: [String], syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.modulePath = modulePath
        super.init(type: .importDeclaration, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard syntax.kind == .importDecl, let importDecl = syntax.as(ImportDeclSyntax.self) else {
            return nil
        }
        let modulePath = importDecl.path.map { $0.name.text }
        let statement = ImportDeclaration(modulePath: modulePath, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)
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
    let attributes: Attributes
    let modifiers: Modifiers
    let members: [Statement]
    var qualifiedName: String {
        return _qualifiedName ?? name
    }
    private var _qualifiedName: String?
    var signature: TypeSignature {
        return TypeSignature.for(name: qualifiedName, genericTypes: [])
    }

    init(type: StatementType, name: String, qualifiedName: String? = nil, inherits: [TypeSignature] = [], attributes: Attributes? = nil, modifiers: Modifiers? = nil, members: [Statement] = [], syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.name = name
        _qualifiedName = qualifiedName
        self.inherits = inherits
        self.attributes = attributes ?? Attributes()
        self.modifiers = modifiers ?? Modifiers()
        self.members = members
        super.init(type: type, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        if syntax.kind == .classDecl, let classDecl = syntax.as(ClassDeclSyntax.self) {
            return [decodeClassDeclaration(classDecl, extras: extras, in: syntaxTree)]
        } else if syntax.kind == .structDecl, let structDecl = syntax.as(StructDeclSyntax.self) {
            return [decodeStructDeclaration(structDecl, extras: extras, in: syntaxTree)]
        } else if syntax.kind == .protocolDecl, let protocolDecl = syntax.as(ProtocolDeclSyntax.self) {
            return [decodeProtocolDeclaration(protocolDecl, extras: extras, in: syntaxTree)]
        } else if syntax.kind == .enumDecl, let enumDecl = syntax.as(EnumDeclSyntax.self) {
            return [decodeEnumDeclaration(enumDecl, extras: extras, in: syntaxTree)]
        }
        return nil
    }

    private static func decodeClassDeclaration(_ classDecl: ClassDeclSyntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> TypeDeclaration {
        let name = classDecl.identifier.text
        let (inherits, messages) = classDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        let attributes = Attributes.for(syntax: classDecl.attributes)
        let modifiers = Modifiers.for(syntax: classDecl.modifiers)
        let members = StatementDecoder.decode(syntaxListContainer: classDecl.members, in: syntaxTree)
        let statement = TypeDeclaration(type: .classDeclaration, name: name, inherits: inherits, attributes: attributes, modifiers: modifiers, members: members, syntax: classDecl, sourceFile: syntaxTree.source.file, sourceRange: classDecl.range(in: syntaxTree.source), extras: extras)
        statement.messages = messages ?? []
        return statement
    }

    private static func decodeStructDeclaration(_ structDecl: StructDeclSyntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> TypeDeclaration {
        let name = structDecl.identifier.text
        let (inherits, messages) = structDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        let attributes = Attributes.for(syntax: structDecl.attributes)
        let modifiers = Modifiers.for(syntax: structDecl.modifiers)
        let members = StatementDecoder.decode(syntaxListContainer: structDecl.members, in: syntaxTree)
        let statement = TypeDeclaration(type: .structDeclaration, name: name, inherits: inherits, attributes: attributes, modifiers: modifiers, members: members, syntax: structDecl, sourceFile: syntaxTree.source.file, sourceRange: structDecl.range(in: syntaxTree.source), extras: extras)
        statement.messages = messages ?? []
        return statement
    }

    private static func decodeProtocolDeclaration(_ protocolDecl: ProtocolDeclSyntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> TypeDeclaration {
        let name = protocolDecl.identifier.text
        let (inherits, messages) = protocolDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        let attributes = Attributes.for(syntax: protocolDecl.attributes)
        let modifiers = Modifiers.for(syntax: protocolDecl.modifiers)
        let members = StatementDecoder.decode(syntaxListContainer: protocolDecl.members, in: syntaxTree)
        let statement = TypeDeclaration(type: .protocolDeclaration, name: name, inherits: inherits, attributes: attributes, modifiers: modifiers, members: members, syntax: protocolDecl, sourceFile: syntaxTree.source.file, sourceRange: protocolDecl.range(in: syntaxTree.source), extras: extras)
        statement.messages = messages ?? []
        return statement
    }

    private static func decodeEnumDeclaration(_ enumDecl: EnumDeclSyntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> TypeDeclaration {
        let name = enumDecl.identifier.text
        let (inherits, messages) = enumDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        let attributes = Attributes.for(syntax: enumDecl.attributes)
        let modifiers = Modifiers.for(syntax: enumDecl.modifiers)
        let members = StatementDecoder.decode(syntaxListContainer: enumDecl.members, in: syntaxTree)
        let statement = TypeDeclaration(type: .enumDeclaration, name: name, inherits: inherits, attributes: attributes, modifiers: modifiers, members: members, syntax: enumDecl, sourceFile: syntaxTree.source.file, sourceRange: enumDecl.range(in: syntaxTree.source), extras: extras)
        statement.messages = messages ?? []
        return statement
    }

    override func resolveAttributes() {
        if _qualifiedName == nil {
            _qualifiedName = qualifyDeclaredTypeName(name)
        }
        inherits = inherits.map { $0.qualified(in: self) }
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        let memberContext = context.pushing(self)
        members.forEach { $0.inferTypes(context: memberContext, expecting: .none) }
        return context
    }

    override var children: [SyntaxNode] {
        return members
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var attrs = [PrettyPrintTree(root: name)]
        if !inherits.isEmpty {
            attrs.append(PrettyPrintTree(root: "inherits", children: inherits.map { PrettyPrintTree(root: $0.description) }))
        }
        if !attributes.isEmpty {
            attrs.append(attributes.prettyPrintTree)
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
    private(set) var declaredType: TypeSignature
    let isLet: Bool
    let isAsync: Bool
    let isThrows: Bool
    var attributes: Attributes
    private(set) var modifiers: Modifiers
    let value: Expression?
    let getter: Accessor<Statement>?
    let setter: Accessor<Statement>?
    let willSet: Accessor<Statement>?
    let didSet: Accessor<Statement>?

    init(name: String, declaredType: TypeSignature = .none, isLet: Bool = false, isAsync: Bool = false, isThrows: Bool = false, attributes: Attributes? = nil, modifiers: Modifiers? = nil, value: Expression?, getter: Accessor<Statement>? = nil, setter: Accessor<Statement>? = nil, willSet: Accessor<Statement>? = nil, didSet: Accessor<Statement>? = nil, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.name = name
        self.declaredType = declaredType
        self.isLet = isLet
        self.isAsync = isAsync
        self.isThrows = isThrows
        self.attributes = attributes ?? Attributes()
        self.modifiers = modifiers ?? Modifiers()
        self.value = value
        self.getter = getter
        self.setter = setter
        self.willSet = willSet
        self.didSet = didSet
        super.init(type: .variableDeclaration, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        guard syntax.kind == .variableDecl, let variableDecl = syntax.as(VariableDeclSyntax.self) else {
            return nil
        }

        let isLet = variableDecl.letOrVarKeyword.text == "let"
        let attributes = Attributes.for(syntax: variableDecl.attributes)
        let modifiers = Modifiers.for(syntax: variableDecl.modifiers)
        var statements: [Statement] = []
        for (index, syntax) in variableDecl.bindings.enumerated() {
            let bindingExtras = index == 0 ? extras : nil
            let statement = try decode(syntax: syntax, isLet: isLet, attributes: attributes, modifiers: modifiers, extras: bindingExtras, in: syntaxTree)
            statements.append(statement)
        }
        return statements
    }

    private static func decode(syntax: PatternBindingSyntax, isLet: Bool, attributes: Attributes? = nil, modifiers: Modifiers?, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> Statement {
        var declaredType: TypeSignature = .none
        if let typeSyntax = syntax.typeAnnotation?.type {
            declaredType = TypeSignature.for(syntax: typeSyntax)
        }
        var value: Expression? = nil
        if let valueSyntax = syntax.initializer?.value {
            value = ExpressionDecoder.decode(syntax: valueSyntax, in: syntaxTree)
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
                    var body: CodeBlock<Statement>? = nil
                    if let bodySyntax = accessorSyntax.body {
                        let statements = StatementDecoder.decode(syntaxListContainer: bodySyntax, in: syntaxTree)
                        body = CodeBlock(statements: statements)
                    }

                    switch accessorSyntax.accessorKind.text {
                    case "get":
                        getter = Accessor(body: body)
                    case "set":
                        let parameterName = accessorSyntax.parameter?.name.text
                        setter = Accessor(parameterName: parameterName, body: body)
                    case "willSet":
                        willSet = Accessor(body: body)
                    case "didSet":
                        didSet = Accessor(body: body)
                    default:
                        messages.append(.unsupportedSyntax(accessor, source: syntaxTree.source, sourceRange: accessor.range(in: syntaxTree.source)))
                    }
                }
            case .getter(let codeBlockSyntax):
                let statements = StatementDecoder.decode(syntaxListContainer: codeBlockSyntax, in: syntaxTree)
                getter = Accessor(body: CodeBlock(statements: statements))
            }
        }

        // TODO: Support patterns other than a simple identifier
        let patternSyntax = syntax.pattern
        switch patternSyntax.kind {
        case .expressionPattern:
            throw Message.unsupportedSyntax(patternSyntax, source: syntaxTree.source)
        case .identifierPattern:
            let name = patternSyntax.as(IdentifierPatternSyntax.self)!.identifier.text
            let declaration = VariableDeclaration(name: name, declaredType: declaredType, isLet: isLet, isAsync: isAsync, isThrows: isThrows, attributes: attributes, modifiers: modifiers, value: value, getter: getter, setter: setter, willSet: willSet, didSet: didSet, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)
            declaration.messages = messages
            return declaration
        case .isTypePattern:
            throw Message.unsupportedSyntax(patternSyntax, source: syntaxTree.source)
        case .missingPattern:
            throw Message.unsupportedSyntax(patternSyntax, source: syntaxTree.source)
        case .tuplePattern:
            throw Message.unsupportedSyntax(patternSyntax, source: syntaxTree.source)
        case .valueBindingPattern:
            throw Message.unsupportedSyntax(patternSyntax, source: syntaxTree.source)
        case .wildcardPattern:
            throw Message.unsupportedSyntax(patternSyntax, source: syntaxTree.source)
        default:
            throw Message.unsupportedSyntax(patternSyntax, source: syntaxTree.source)
        }
    }

    override func resolveAttributes() {
        declaredType = declaredType.qualified(in: self)
        // Variables in protocols or extensions inherit the visibility of the protocol or extension
        if modifiers.visibility == .default, let owningTypeDeclaration = parent as? TypeDeclaration, (owningTypeDeclaration.type == .protocolDeclaration || owningTypeDeclaration.type == .extensionDeclaration) {
            modifiers.visibility = owningTypeDeclaration.modifiers.visibility
        }
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        value?.inferTypes(context: context, expecting: declaredType)
        let inferredType = declaredType.or(value?.inferredType ?? .none)
        if let statements = getter?.body?.statements {
            var bodyContext = context.expectingReturn(inferredType)
            statements.forEach { bodyContext = $0.inferTypes(context: bodyContext, expecting: .none) }
        }
        if let statements = setter?.body?.statements {
            var bodyContext = context.addingIdentifier(setter?.parameterName ?? "newValue", type: inferredType)
            statements.forEach { bodyContext = $0.inferTypes(context: bodyContext, expecting: .none) }
        }
        if let statements = willSet?.body?.statements {
            var bodyContext = context.addingIdentifier(willSet?.parameterName ?? "newValue", type: inferredType)
            statements.forEach { bodyContext = $0.inferTypes(context: bodyContext, expecting: .none) }
        }
        if let statements = didSet?.body?.statements {
            var bodyContext = context.addingIdentifier(didSet?.parameterName ?? "oldValue", type: inferredType)
            statements.forEach { bodyContext = $0.inferTypes(context: bodyContext, expecting: .none) }
        }
        if parent == nil || parent is TypeDeclaration {
            return context
        } else {
            // Local variable in code block
            return context.addingIdentifier(name, type: inferredType)
        }
    }

    override var children: [SyntaxNode] {
        var children: [SyntaxNode] = []
        if let value {
            children.append(value)
        }
        if let statements = getter?.body?.statements {
            children += statements
        }
        if let statements = setter?.body?.statements {
            children += statements
        }
        if let statements = willSet?.body?.statements {
            children += statements
        }
        if let statements = didSet?.body?.statements {
            children += statements
        }
        return children
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var attrs = [PrettyPrintTree(root: name)]
        if declaredType != .none {
            attrs.append(PrettyPrintTree(root: declaredType.description))
        }
        if isAsync {
            attrs.append(PrettyPrintTree(root: "async"))
        }
        if isThrows {
            attrs.append(PrettyPrintTree(root: "throws"))
        }
        if !attributes.isEmpty {
            attrs.append(attributes.prettyPrintTree)
        }
        if !modifiers.isEmpty {
            attrs.append(modifiers.prettyPrintTree)
        }
        return attrs
    }
}
