import SwiftSyntax

/// Supported Swift statement types.
enum StatementType: CaseIterable {
    case `break`
    case `catch`
    case `continue`
    case `defer`
    case `do`
    case `for`
    case `guard`
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

    // Special statements
    case codeBlock
    case expression
    case raw
    case message

    /// The Swift data type that represents this statement type.
    var representingType: Statement.Type? {
        switch self {
        case .break:
            return nil
        case .catch:
            return nil
        case .codeBlock:
            return CodeBlock.self
        case .continue:
            return nil
        case .defer:
            return nil
        case .do:
            return nil
        case .for:
            return nil
        case .guard:
            return Guard.self
        case .if:
            return If.self
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

/// A synthetic statement type used to represent a code block of statements.
class CodeBlock: Statement {
    let statements: [Statement]

    init(statements: [Statement]) {
        self.statements = statements
        super.init(type: .codeBlock)
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        var blockContext = context
        statements.forEach { blockContext = $0.inferTypes(context: blockContext, expecting: .none) }
        return context
    }

    override var children: [SyntaxNode] {
        return statements
    }
}

/// `guard ...`
class Guard: Statement {
    let conditions: [Expression]
    let body: CodeBlock

    init(conditions: [Expression], body: CodeBlock, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.conditions = conditions
        self.body = body
        super.init(type: .guard, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        guard syntax.kind == .guardStmt, let guardStmnt = syntax.as(GuardStmtSyntax.self) else {
            return nil
        }
        
        let conditions = try guardStmnt.conditions.map { try ExpressionDecoder.decodeCondition($0, in: syntaxTree) }
        let statements = StatementDecoder.decode(syntaxListContainer: guardStmnt.body, in: syntaxTree)
        let body = CodeBlock(statements: statements)
        return [Guard(conditions: conditions, body: body, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)]
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        var conditionsContext = context
        conditions.forEach { conditionsContext = $0.inferTypes(context: conditionsContext, expecting: .bool) }
        let optionalBindings = conditions.reduce(into: [String: TypeSignature]()) { result, condition in
            if let optionalBinding = condition as? OptionalBinding {
                result[optionalBinding.name] = optionalBinding.variableType
            }
        }
        let bodyContext = context.pushingBlock(identifiers: optionalBindings)
        let _ = body.inferTypes(context: bodyContext, expecting: .none)
        return context
    }

    override var children: [SyntaxNode] {
        return conditions + [body]
    }
}

/// `if ...`
class If: Statement {
    let conditions: [Expression]
    let body: CodeBlock
    let elseBody: CodeBlock?

    init(conditions: [Expression], body: CodeBlock, elseBody: CodeBlock? = nil, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.conditions = conditions
        self.body = body
        self.elseBody = elseBody
        super.init(type: .if, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        let ifStmnt: IfExprSyntax
        if syntax.kind == .ifExpr, let ifExprSyntax = syntax.as(IfExprSyntax.self) {
            ifStmnt = ifExprSyntax
        } else {
            guard syntax.kind == .expressionStmt, let stmntSyntax = syntax.as(ExpressionStmtSyntax.self) else {
                return nil
            }
            guard stmntSyntax.expression.kind == .ifExpr, let ifExprSyntax = stmntSyntax.expression.as(IfExprSyntax.self) else {
                return nil
            }
            ifStmnt = ifExprSyntax
        }

        let conditions = try ifStmnt.conditions.map { try ExpressionDecoder.decodeCondition($0, in: syntaxTree) }
        let statements = StatementDecoder.decode(syntaxListContainer: ifStmnt.body, in: syntaxTree)
        let body = CodeBlock(statements: statements)
        var elseBody: CodeBlock? = nil
        if let elseSyntax = ifStmnt.elseBody {
            let statements: [Statement]
            switch elseSyntax {
            case .ifExpr(let syntax):
                statements = StatementDecoder.decode(syntax: syntax, in: syntaxTree)
            case .codeBlock(let syntax):
                statements = StatementDecoder.decode(syntaxListContainer: syntax, in: syntaxTree)
            }
            elseBody = CodeBlock(statements: statements)
        }
        return [If(conditions: conditions, body: body, elseBody: elseBody, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)]
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        var conditionsContext = context
        conditions.forEach { conditionsContext = $0.inferTypes(context: conditionsContext, expecting: .bool) }
        let optionalBindings = conditions.reduce(into: [String: TypeSignature]()) { result, condition in
            if let optionalBinding = condition as? OptionalBinding {
                result[optionalBinding.name] = optionalBinding.variableType
            }
        }
        let bodyContext = context.pushingBlock(identifiers: optionalBindings)
        let _ = body.inferTypes(context: bodyContext, expecting: .none)
        if let elseBody {
            let _ = elseBody.inferTypes(context: context, expecting: .none)
        }
        return context
    }

    override var children: [SyntaxNode] {
        var children: [SyntaxNode] = conditions
        children.append(body)
        if let elseBody {
            children.append(elseBody)
        }
        return children
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
    let body: CodeBlock?

    init(type: StatementType, name: String, isOptionalInit: Bool = false, returnType: TypeSignature = .void, parameters: [Parameter<Expression>], isAsync: Bool = false, isThrows: Bool = false, attributes: Attributes? = nil, modifiers: Modifiers? = nil, body: CodeBlock? = nil, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
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
        let isAsync = functionDecl.signature.effectSpecifiers?.asyncSpecifier?.text == "async" || functionDecl.signature.effectSpecifiers?.throwsSpecifier?.text == "async"
        let isThrows = functionDecl.signature.effectSpecifiers?.asyncSpecifier?.text == "throws" || functionDecl.signature.effectSpecifiers?.throwsSpecifier?.text == "throws"
        let attributes = Attributes.for(syntax: functionDecl.attributes)
        let modifiers = Modifiers.for(syntax: functionDecl.modifiers)
        var body: CodeBlock? = nil
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
        let isAsync = initializerDecl.signature.effectSpecifiers?.asyncSpecifier?.text == "async" || initializerDecl.signature.effectSpecifiers?.throwsSpecifier?.text == "async"
        let isThrows = initializerDecl.signature.effectSpecifiers?.asyncSpecifier?.text == "throws" || initializerDecl.signature.effectSpecifiers?.throwsSpecifier?.text == "throws"
        let attributes = Attributes.for(syntax: initializerDecl.attributes)
        let modifiers = Modifiers.for(syntax: initializerDecl.modifiers)
        var body: CodeBlock? = nil
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
        if modifiers.visibility == .default {
            if let owningTypeDeclaration = parent as? TypeDeclaration, (owningTypeDeclaration.type == .protocolDeclaration || owningTypeDeclaration.type == .extensionDeclaration) {
                modifiers.visibility = owningTypeDeclaration.modifiers.visibility
            } else {
                modifiers.visibility = .internal
            }
        }
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        parameters.forEach { $0.defaultValue?.inferTypes(context: context, expecting: $0.declaredType) }
        if let body {
            let bodyContext = context.pushing(self)
            let _ = body.inferTypes(context: bodyContext, expecting: .none)
        }
        return context
    }

    override var children: [SyntaxNode] {
        var children: [SyntaxNode] = parameters.compactMap { $0.defaultValue }
        if let body {
            children.append(body)
        }
        return children
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
/// `class/struct/enum/protocol Type { ... }`
class TypeDeclaration: Statement {
    let name: String
    private(set) var inherits: [TypeSignature]
    let attributes: Attributes
    private(set) var modifiers: Modifiers
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
        if modifiers.visibility == .default {
            modifiers.visibility = .internal
        }
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
    let getter: Accessor<CodeBlock>?
    let setter: Accessor<CodeBlock>?
    let willSet: Accessor<CodeBlock>?
    let didSet: Accessor<CodeBlock>?
    var variableType: TypeSignature {
        return declaredType.or(value?.inferredType ?? .none)
    }

    init(name: String, declaredType: TypeSignature = .none, isLet: Bool = false, isAsync: Bool = false, isThrows: Bool = false, attributes: Attributes? = nil, modifiers: Modifiers? = nil, value: Expression?, getter: Accessor<CodeBlock>? = nil, setter: Accessor<CodeBlock>? = nil, willSet: Accessor<CodeBlock>? = nil, didSet: Accessor<CodeBlock>? = nil, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
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

        let isLet = variableDecl.bindingKeyword.text == "let"
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

        var getter: Accessor<CodeBlock>? = nil
        var setter: Accessor<CodeBlock>? = nil
        var willSet: Accessor<CodeBlock>? = nil
        var didSet: Accessor<CodeBlock>? = nil
        var isAsync = false
        var isThrows = false
        var messages: [Message] = []
        if let accessor = syntax.accessor {
            switch accessor {
            case .accessors(let accessorListSyntax):
                for accessorSyntax in accessorListSyntax.accessors {
                    if accessorSyntax.effectSpecifiers?.throwsSpecifier?.text == "throws" || accessorSyntax.effectSpecifiers?.asyncSpecifier?.text == "throws" {
                        isThrows = true
                    }
                    if accessorSyntax.effectSpecifiers?.throwsSpecifier?.text == "async" || accessorSyntax.effectSpecifiers?.asyncSpecifier?.text == "async" {
                        isAsync = true
                    }
                    var body: CodeBlock? = nil
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
        if modifiers.visibility == .default {
            if let owningTypeDeclaration = parent as? TypeDeclaration, (owningTypeDeclaration.type == .protocolDeclaration || owningTypeDeclaration.type == .extensionDeclaration) {
                modifiers.visibility = owningTypeDeclaration.modifiers.visibility
            } else {
                modifiers.visibility = .internal
            }
        }
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        value?.inferTypes(context: context, expecting: declaredType)
        let variableType = variableType
        if let body = getter?.body {
            let bodyContext = context.expectingReturn(variableType)
            let _ = body.inferTypes(context: bodyContext, expecting: .none)
        }
        if let body = setter?.body {
            let bodyContext = context.addingIdentifier(setter?.parameterName ?? "newValue", type: variableType)
            let _ = body.inferTypes(context: bodyContext, expecting: .none)
        }
        if let body = willSet?.body {
            let bodyContext = context.addingIdentifier(willSet?.parameterName ?? "newValue", type: variableType)
            let _ = body.inferTypes(context: bodyContext, expecting: .none)
        }
        if let body = didSet?.body {
            let bodyContext = context.addingIdentifier(didSet?.parameterName ?? "oldValue", type: variableType)
            let _ = body.inferTypes(context: bodyContext, expecting: .none)
        }
        if parent is TypeDeclaration {
            return context
        } else {
            // Local variable in code block
            return context.addingIdentifier(name, type: variableType)
        }
    }

    override var children: [SyntaxNode] {
        var children: [SyntaxNode] = []
        if let value {
            children.append(value)
        }
        if let body = getter?.body {
            children.append(body)
        }
        if let body = setter?.body {
            children.append(body)
        }
        if let body = willSet?.body {
            children.append(body)
        }
        if let body = didSet?.body {
            children.append(body)
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
