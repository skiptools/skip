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

// TODO: Attributes, modifiers, generics, where clause
class ClassDeclaration: Statement {
    let name: String
    let inherits: [TypeSignature]
    let members: [Statement]

    init(name: String, inherits: [TypeSignature] = [], members: [Statement] = [], syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.name = name
        self.inherits = inherits
        self.members = members
        super.init(type: .classDeclaration, syntax: syntax, file: file, range: range, extras: extras)
    }

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard syntax.kind == .classDecl, let classDecl = syntax.as(ClassDeclSyntax.self) else {
            return nil
        }
        let name = classDecl.identifier.text
        let (inherits, message) = classDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        let members = StatementDecoder.decode(syntaxListContainer: classDecl.members, in: syntaxTree)
        let statement = ClassDeclaration(name: name, inherits: inherits, members: members, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
        statement.message = message
        return [statement]
    }

    override var children: [Statement] {
        return members
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var attrs = [PrettyPrintTree(root: name)]
        if !inherits.isEmpty {
            attrs.append(PrettyPrintTree(root: "inherits", children: inherits.map { PrettyPrintTree(root: $0.description) }))
        }
        return attrs
    }
}

// TODO: Attributes, modifiers, generics, where clause
class ExtensionDeclaration: Statement {
    let extends: TypeSignature
    let inherits: [TypeSignature]
    let members: [Statement]

    init(extends: TypeSignature, inherits: [TypeSignature] = [], members: [Statement] = [], syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.extends = extends
        self.inherits = inherits
        self.members = members
        super.init(type: .extensionDeclaration, syntax: syntax, file: file, range: range, extras: extras)
    }

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard syntax.kind == .extensionDecl, let extensionDecl = syntax.as(ExtensionDeclSyntax.self), let extends = TypeSignature.for(syntax: extensionDecl.extendedType) else {
            return nil
        }
        let (inherits, message) = extensionDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        let members = StatementDecoder.decode(syntaxListContainer: extensionDecl.members, in: syntaxTree)
        let statement = ExtensionDeclaration(extends: extends, inherits: inherits, members: members, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
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
        return attrs
    }
}

// TODO: Body, attributes, modifiers, async, throws, generics, where
class FunctionDeclaration: Statement {
    let name: String
    let returnType: TypeSignature?
    let parameters: [Parameter<Statement>]
    let body: CodeBlock<Statement>?

    init(name: String, returnType: TypeSignature?, parameters: [Parameter<Statement>], body: CodeBlock<Statement>? = nil, syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.name = name
        self.returnType = returnType
        self.parameters = parameters
        self.body = body
        super.init(type: .functionDeclaration, syntax: syntax, file: file, range: range, extras: extras)
        
    }

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard syntax.kind == .functionDecl, let functionDecl = syntax.as(FunctionDeclSyntax.self) else {
            return nil
        }
        let name = functionDecl.identifier.text
        let (returnType, parameters, message) = functionDecl.signature.typeSignatures(in: syntaxTree)
        var body: CodeBlock<Statement>? = nil
        if let bodySyntax = functionDecl.body {
            body = CodeBlock(statements: StatementDecoder.decode(syntaxListContainer: bodySyntax, in: syntaxTree))
        }
        let statement = FunctionDeclaration(name: name, returnType: returnType, parameters: parameters, body: body, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
        statement.message = message
        return [statement]
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

// TODO: Attributes, modifiers, generics, where clause
class ProtocolDeclaration: Statement {
    let name: String
    let inherits: [TypeSignature]
    let members: [Statement]

    init(name: String, inherits: [TypeSignature] = [], members: [Statement] = [], syntax: Syntax? = nil, file: Source.File? = nil, range: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.name = name
        self.inherits = inherits
        self.members = members
        super.init(type: .protocolDeclaration, syntax: syntax, file: file, range: range, extras: extras)
    }

    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard syntax.kind == .protocolDecl, let protocolDecl = syntax.as(ProtocolDeclSyntax.self) else {
            return nil
        }
        let name = protocolDecl.identifier.text
        let (inherits, message) = protocolDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        let members = StatementDecoder.decode(syntaxListContainer: protocolDecl.members, in: syntaxTree)
        let statement = ProtocolDeclaration(name: name, inherits: inherits, members: members, syntax: syntax, file: syntaxTree.source.file, range: syntax.range(in: syntaxTree.source), extras: extras)
        statement.message = message
        return [statement]
    }

    override var children: [Statement] {
        return members
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var children = [PrettyPrintTree(root: name)]
        if !inherits.isEmpty {
            children.append(PrettyPrintTree(root: "inherits", children: inherits.map { PrettyPrintTree(root: $0.description) }))
        }
        return children
    }
}

class VariableDeclaration: Statement {
    override class func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
//        guard let variableDecl = syntax as? VariableDeclSyntax else {
//            return nil
//        }
        return nil

//        var statements: [Statement] = []
//        for patternBinding in variableDecl.bindings {
//
//        }
//
//
//        let isLet = (variableDeclaration.letOrVarKeyword.text == "let")
//
//        let result: MutableList<VariableDeclaration> = []
//        let errors: MutableList<Statement> = []
//
//        let patternBindingList: PatternBindingListSyntax = variableDeclaration.bindings
//        for patternBinding in patternBindingList {
//            let pattern: PatternSyntax = patternBinding.pattern
//
//            // If we can find the variable's name
//            if let identifier = pattern.getText() {
//
//                let expression: Expression?
//                if let exprSyntax = patternBinding.initializer?.value {
//                    expression = try convertExpression(exprSyntax)
//                }
//                else {
//                    expression = nil
//                }
//
//                // If it's a `let _ = foo`
//                guard identifier != "_" else {
//                    if let expression = expression {
//                        return [ExpressionStatement(
//                            syntax: Syntax(variableDeclaration),
//                            range: variableDeclaration.getRange(inFile: self.sourceFile),
//                            expression: expression), ]
//                    }
//                    else {
//                        return []
//                    }
//                }
//
//                let annotatedType: String?
//                if let typeAnnotation = patternBinding.typeAnnotation?.type {
//                    let typeName = try convertType(typeAnnotation)
//
//                    if let expressionType = expression?.swiftType,
//                       expressionType.hasPrefix("\(typeName)<")
//                    {
//                        // If the variable is annotated as `let a: A` but `A` is generic and the
//                        // expression is of type `A<T>`, use the expression's type instead
//                        annotatedType = expressionType
//                    }
//                    else {
//                        annotatedType = typeName
//                    }
//                }
//                else  {
//                    annotatedType = expression?.swiftType
//                }
//
//                // Look for getters and setters
//                var errorHappened = false
//                var getter: FunctionDeclaration?
//                var setter: FunctionDeclaration?
//                if let maybeCodeBlock = patternBinding.children.first(where:
//                                                                        { $0.is(CodeBlockSyntax.self) }),
//                   let codeBlock = maybeCodeBlock.as(CodeBlockSyntax.self)
//                {
//                    // If there's an implicit getter (e.g. `var a: Int { return 0 }`)
//                    let range = codeBlock.getRange(inFile: self.sourceFile)
//                    let statements = try convertBlock(codeBlock)
//
//                    guard let typeName = annotatedType else {
//                        let error = try errorStatement(
//                            forASTNode: Syntax(codeBlock),
//                            withMessage: "Expected variables with getters to have an explicit type")
//                        getter = FunctionDeclaration(
//                            syntax: Syntax(codeBlock),
//                            range: range,
//                            prefix: "get",
//                            parameters: [], returnType: "", functionType: "", genericTypes: [],
//                            isOpen: false, isStatic: false, isMutating: false,
//                            isPure: false, isJustProtocolInterface: false, extendsType: nil,
//                            statements: [error],
//                            access: nil, annotations: [])
//                        errorHappened = true
//                        break
//                    }
//
//                    getter = FunctionDeclaration(
//                        syntax: Syntax(codeBlock),
//                        range: codeBlock.getRange(inFile: self.sourceFile),
//                        prefix: "get",
//                        parameters: [],
//                        returnType: typeName,
//                        functionType: "() -> \(typeName)",
//                        genericTypes: [],
//                        isOpen: false,
//                        isStatic: false,
//                        isMutating: false,
//                        isPure: false,
//                        isJustProtocolInterface: false,
//                        extendsType: nil,
//                        statements: statements,
//                        access: nil,
//                        annotations: [])
//                }
//                else if let maybeAccesor = patternBinding.accessor,
//                        let accessorBlock = maybeAccesor.as(AccessorBlockSyntax.self)
//                {
//                    // If there's an explicit getter or setter (e.g. `get { return 0 }`)
//
//                    for accessor in accessorBlock.accessors {
//                        let range = accessor.getRange(inFile: self.sourceFile)
//                        let prefix = accessor.accessorKind.text
//
//                        // If there the accessor has a body (if not, assume it's a protocol's
//                        // `{ get }`).
//                        if let maybeCodeBlock = accessor.children.first(where:
//                                                                            { $0.is(CodeBlockSyntax.self) }),
//                           let codeBlock = maybeCodeBlock.as(CodeBlockSyntax.self)
//                        {
//                            let statements = try convertBlock(codeBlock)
//
//                            guard let typeName = annotatedType else {
//                                let error = try errorStatement(
//                                    forASTNode: Syntax(codeBlock),
//                                    withMessage: "Expected variables with getters or setters to " +
//                                    "have an explicit type")
//                                getter = FunctionDeclaration(
//                                    syntax: Syntax(accessor),
//                                    range: range,
//                                    prefix: prefix,
//                                    parameters: [], returnType: "", functionType: "",
//                                    genericTypes: [], isOpen: false,
//                                    isStatic: false, isMutating: false, isPure: false,
//                                    isJustProtocolInterface: false, extendsType: nil,
//                                    statements: [error],
//                                    access: nil, annotations: [])
//                                errorHappened = true
//                                break
//                            }
//
//                            let parameters: MutableList<FunctionParameter>
//                            if prefix == "get" {
//                                parameters = []
//                            }
//                            else {
//                                parameters = [FunctionParameter(
//                                    label: "newValue",
//                                    apiLabel: nil,
//                                    typeName: typeName,
//                                    value: nil), ]
//                            }
//
//                            let returnType: String
//                            let functionType: String
//                            if prefix == "get" {
//                                returnType = typeName
//                                functionType = "() -> \(typeName)"
//                            }
//                            else {
//                                returnType = "()"
//                                functionType = "(\(typeName)) -> ()"
//                            }
//
//                            let functionDeclaration = FunctionDeclaration(
//                                syntax: Syntax(accessor),
//                                range: range,
//                                prefix: prefix,
//                                parameters: parameters,
//                                returnType: returnType,
//                                functionType: functionType,
//                                genericTypes: [],
//                                isOpen: false,
//                                isStatic: false,
//                                isMutating: false,
//                                isPure: false,
//                                isJustProtocolInterface: false,
//                                extendsType: nil,
//                                statements: statements,
//                                access: nil,
//                                annotations: [])
//
//                            if accessor.accessorKind.text == "get" {
//                                getter = functionDeclaration
//                            }
//                            else {
//                                setter = functionDeclaration
//                            }
//                        }
//                        else {
//                            let functionDeclaration = FunctionDeclaration(
//                                syntax: Syntax(accessor),
//                                range: range,
//                                prefix: prefix,
//                                parameters: [],
//                                returnType: "",
//                                functionType: "",
//                                genericTypes: [],
//                                isOpen: false,
//                                isStatic: false,
//                                isMutating: false,
//                                isPure: false,
//                                isJustProtocolInterface: false,
//                                extendsType: nil,
//                                statements: [],
//                                access: nil,
//                                annotations: [])
//
//                            if accessor.accessorKind.text == "get" {
//                                getter = functionDeclaration
//                            }
//                            else {
//                                setter = functionDeclaration
//                            }
//                        }
//                    }
//                }
//
//                if errorHappened {
//                    continue
//                }
//
//                let accessAndAnnotations =
//                getAccessAndAnnotations(fromModifiers: variableDeclaration.modifiers)
//
//                let isStatic = accessAndAnnotations.annotations.remove("static")
//
//                // Get annotations from `gryphon annotation` comments
//                let annotationComments = getLeadingComments(
//                    forSyntax: Syntax(variableDeclaration),
//                    withKey: .annotation)
//                let manualAnnotations = annotationComments.compactMap { $0.value }
//                let annotations = accessAndAnnotations.annotations
//                annotations.append(contentsOf: manualAnnotations)
//
//                let isOpen: Bool
//                if annotations.remove("final") {
//                    isOpen = false
//                }
//                else if let access = accessAndAnnotations.access, access == "open" {
//                    isOpen = true
//                }
//                else if isLet {
//                    // Only var's can be open in Swift
//                    isOpen = false
//                }
//                else {
//                    isOpen = !context.defaultsToFinal
//                }
//
//                result.append(VariableDeclaration(
//                    syntax: Syntax(variableDeclaration),
//                    range: variableDeclaration.getRange(inFile: self.sourceFile),
//                    identifier: identifier,
//                    typeAnnotation: annotatedType,
//                    expression: expression,
//                    getter: getter,
//                    setter: setter,
//                    access: accessAndAnnotations.access,
//                    isOpen: isOpen,
//                    isLet: isLet,
//                    isStatic: isStatic,
//                    extendsType: nil,
//                    annotations: annotations))
//            }
//            else {
//                try errors.append(
//                    errorStatement(
//                        forASTNode: Syntax(patternBinding),
//                        withMessage: "Failed to convert variable declaration: unknown pattern " +
//                        "binding"))
//            }
//        }
//
//        // Propagate the type annotations: `let x, y: Double` becomes `val x; val y: Double`, but it
//        // needs to be `val x: Double; val y: Double`.
//        if result.count > 1, let lastTypeAnnotation = result.last?.typeAnnotation {
//            for declaration in result {
//                declaration.typeAnnotation = declaration.typeAnnotation ?? lastTypeAnnotation
//            }
//        }
//
//        let resultStatements = result.forceCast(to: MutableList<Statement>.self)
//        resultStatements.append(contentsOf: errors)
//        return resultStatements
    }
}
