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

// MARK: - Declarations

// TODO: Attributes, modifiers, generics, where clause
struct ClassDeclaration: Statement {
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

    var type: StatementType { .classDeclaration }
    let syntax: Syntax?
    let file: Source.File?
    let range: Source.Range?
    let extras: StatementExtras?
    let message: Message?

    static func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard let statement = ClassDeclaration(syntax: syntax, extras: extras, in: syntaxTree) else {
            return nil
        }
        return [statement]
    }

    private init?(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) {
        guard let classDecl = syntax.as(ClassDeclSyntax.self) else {
            return nil
        }
        self.syntax = syntax
        self.file = syntaxTree.source.file
        self.range = syntax.range(in: syntaxTree.source)
        self.extras = extras
        self.name = classDecl.identifier.text
        let (inherits, message) = classDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        self.inherits = inherits
        self.message = message
        self.members = syntaxTree.process(syntaxListContainer: classDecl.members)
    }

    var children: [Statement] {
        return members
    }

    var prettyPrintChildren: [PrettyPrintTree] {
        var children = [PrettyPrintTree(root: name)]
        if !inherits.isEmpty {
            children.append(PrettyPrintTree(root: "inherits", children: inherits.map { PrettyPrintTree(root: $0.description) }))
        }
        return children
    }
}

// TODO: Attributes, modifiers, generics, where clause
struct ExtensionDeclaration: Statement {
    let extends: TypeSignature
    let inherits: [TypeSignature]
    let members: [Statement]

    init(extends: TypeSignature, inherits: [TypeSignature] = [], members: [Statement] = []) {
        self.syntax = nil
        self.file = nil
        self.range = nil
        self.extras = nil
        self.message = nil
        self.extends = extends
        self.inherits = inherits
        self.members = members
    }

    var type: StatementType { .extensionDeclaration }
    let syntax: Syntax?
    let file: Source.File?
    let range: Source.Range?
    let extras: StatementExtras?
    let message: Message?

    static func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard let statement = ExtensionDeclaration(syntax: syntax, extras: extras, in: syntaxTree) else {
            return nil
        }
        return [statement]
    }

    private init?(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) {
        guard let extensionDecl = syntax.as(ExtensionDeclSyntax.self), let extends = TypeSignature.for(syntax: extensionDecl.extendedType) else {
            return nil
        }
        self.syntax = syntax
        self.file = syntaxTree.source.file
        self.range = syntax.range(in: syntaxTree.source)
        self.extras = extras
        self.extends = extends
        let (inherits, message) = extensionDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        self.inherits = inherits
        self.message = message
        self.members = syntaxTree.process(syntaxListContainer: extensionDecl.members)
    }

    var children: [Statement] {
        return members
    }

    var prettyPrintChildren: [PrettyPrintTree] {
        var children = [PrettyPrintTree(root: extends.description)]
        if !inherits.isEmpty {
            children.append(PrettyPrintTree(root: "inherits", children: inherits.map { PrettyPrintTree(root: $0.description) }))
        }
        return children
    }
}

struct FunctionDeclaration: Statement {
//    let symbol: String
//    let statements: [Statement]
//
//    init(symbol: String, statements: [Statement]) {
//        self.syntax = nil
//        self.file = nil
//        self.range = nil
//        self.extras = nil
//        self.symbol = symbol
//        self.statements = statements
//    }

    var type: StatementType { .functionDeclaration }
    let syntax: Syntax?
    let file: Source.File?
    let range: Source.Range?
    let extras: StatementExtras?

    static func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard let statement = FunctionDeclaration(syntax: syntax, extras: extras, in: syntaxTree) else {
            return nil
        }
        return [statement]
    }

    private init?(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) {
//        guard let functionDecl = syntax.as(FunctionDeclSyntax.self) else {
//            return nil
//        }
        return nil
//        self.syntax = syntax
//        self.file = syntaxTree.source.file
//        self.range = syntax.range(in: syntaxTree.source)
//        self.extras = extras
//
//        // Look for a clause that matches a defined symbol, or an 'else'
//        for clause in ifConfigDecl.clauses {
//            let symbol = clause.condition?.description ?? ""
//            guard symbol == "SKIP" || syntaxTree.preprocessorSymbols.contains(symbol) || clause.poundKeyword.text == "#else" else {
//                continue
//            }
//            self.symbol = symbol.isEmpty ? "#else" : symbol
//            self.statements = Self.extractStatements(from: clause, in: syntaxTree)
//            return
//        }
//        // Didn't find a match
//        self.symbol = ifConfigDecl.clauses.first?.condition?.description ?? ""
//        self.statements = []
    }

//    let prefix = functionLikeDeclaration.prefix
//
//    let parameters: MutableList<FunctionParameter> =
//    try convertParameters(functionLikeDeclaration.parameterList)
//
//    let inputType = "(" + parameters
//        .map { $0.typeName + ($0.isVariadic ? "..." : "") }
//        .joined(separator: ", ") +
//    ")"
//
//    let returnType: String
//    if let returnTypeSyntax = functionLikeDeclaration.returnType {
//        returnType = try convertType(returnTypeSyntax)
//    }
//    else {
//        returnType = "Void"
//    }
//
//    let functionType = inputType + " -> " + returnType
//
//    let statements: MutableList<Statement>
//    if let statementsSyntax = functionLikeDeclaration.statements {
//        statements = try convertBlock(statementsSyntax)
//    }
//    else {
//        statements = []
//    }
//
//    let accessAndAnnotations =
//    getAccessAndAnnotations(fromModifiers: functionLikeDeclaration.modifierList)
//
//    // Get annotations from `gryphon annotation` comments
//    let annotationComments = getLeadingComments(
//        forSyntax: functionLikeDeclaration.asSyntax,
//        withKey: .annotation)
//    let manualAnnotations = annotationComments.compactMap { $0.value }
//    let annotations = accessAndAnnotations.annotations
//    annotations.append(contentsOf: manualAnnotations)
//
//    let isOpen: Bool
//    if annotations.remove("final") {
//        isOpen = false
//    }
//    else if let access = accessAndAnnotations.access, access == "open" {
//        isOpen = true
//    }
//    else {
//        isOpen = !context.defaultsToFinal
//    }
//
//    let generics: MutableList<String>
//    if let genericsSyntax = functionLikeDeclaration.generics {
//        generics = MutableList(genericsSyntax.map { $0.name.text })
//    }
//    else {
//        generics = []
//    }
//
//    let isMutating = annotations.remove("mutating")
//
//    let isPure = !getLeadingComments(
//        forSyntax: functionLikeDeclaration.asSyntax,
//        withKey: .pure).isEmpty
//    if let range = functionLikeDeclaration.getRange(inFile: self.sourceFile),
//       let translationComment = self.sourceFile.getTranslationCommentFromLine(range.start.line),
//       translationComment.key == .pure
//    {
//        Compiler.handleWarning(
//            message: "Deprecated: the \"gryphon pure\" comment should be before " +
//            "this function. " +
//            "Fix it: move \"// gryphon pure\" to the line above this one.",
//            syntax: functionLikeDeclaration.asSyntax,
//            ast: functionLikeDeclaration.toPrintableTree(),
//            sourceFile: self.sourceFile,
//            sourceFileRange: range)
//    }
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
        let (inherits, message) = protocolDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], nil)
        self.inherits = inherits
        self.message = message
        self.members = syntaxTree.process(syntaxListContainer: protocolDecl.members)
    }

    var children: [Statement] {
        return members
    }

    var prettyPrintChildren: [PrettyPrintTree] {
        var children = [PrettyPrintTree(root: name)]
        if !inherits.isEmpty {
            children.append(PrettyPrintTree(root: "inherits", children: inherits.map { PrettyPrintTree(root: $0.description) }))
        }
        return children
    }
}

struct VariableDeclaration: Statement {
    var type: StatementType { .variableDeclaration }
    let syntax: Syntax?
    let file: Source.File?
    let range: Source.Range?
    let extras: StatementExtras?

    static func decode(syntax: Syntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
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
