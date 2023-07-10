import SwiftSyntax

/// Supported Swift statement types.
///
/// - Note: `Codable` for use in `CodebaseInfo`.
enum StatementType: CaseIterable, Codable {
    case `break`
    case `continue`
    case `defer`
    case doCatch
    case empty
    case `fallthrough`
    case forLoop
    case `guard`
    case ifDefined
    case labeled
    case `return`
    case `throw`
    case whileLoop

    case actorDeclaration
    case classDeclaration
    case deinitDeclaration
    case enumCaseDeclaration
    case enumDeclaration
    case extensionDeclaration
    case functionDeclaration
    case importDeclaration
    case initDeclaration
    case protocolDeclaration
    case structDeclaration
    case subscriptDeclaration
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
            return Break.self
        case .codeBlock:
            return CodeBlock.self
        case .continue:
            return Continue.self
        case .defer:
            return Defer.self
        case .doCatch:
            return DoCatch.self
        case .empty:
            return Empty.self
        case .fallthrough:
            return Fallthrough.self
        case .forLoop:
            return ForLoop.self
        case .guard:
            return Guard.self
        case .ifDefined:
            return IfDefined.self
        case .labeled:
            return LabeledStatement.self
        case .return:
            return Return.self
        case .throw:
            return Throw.self
        case .whileLoop:
            return WhileLoop.self

        case .actorDeclaration:
            return TypeDeclaration.self
        case .classDeclaration:
            return TypeDeclaration.self
        case .deinitDeclaration:
            return FunctionDeclaration.self
        case .enumCaseDeclaration:
            return EnumCaseDeclaration.self
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
        case .subscriptDeclaration:
            return SubscriptDeclaration.self
        case .typealiasDeclaration:
            return TypealiasDeclaration.self
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

/// `break`
class Break: Statement {
    let label: String?

    init(label: String? = nil, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.label = label
        super.init(type: .break, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        guard syntax.kind == .breakStmt, let breakStmnt = syntax.as(BreakStmtSyntax.self) else {
            return nil
        }
        let label = breakStmnt.label?.text
        return [Break(label: label, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)]
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return label == nil ? [] : [PrettyPrintTree(root: label!)]
    }
}

/// A synthetic statement type used to represent a code block of statements.
class CodeBlock: Statement {
    var statements: [Statement]

    init(statements: [Statement]) {
        self.statements = statements
        super.init(type: .codeBlock)
    }

    /// Return the inferred type of the return statements in the block.
    var returnType: TypeSignature {
        guard !statements.isEmpty else {
            return .none
        }
        var returnType: TypeSignature = .none
        var isOptional = false
        var foundReturn = false
        visit { node in
            if node is Closure || node is FunctionDeclaration {
                return .skip
            }
            if let expression = (node as? Return)?.expression {
                foundReturn = true
                if expression.type == .nilLiteral {
                    isOptional = true
                } else {
                    returnType = returnType.or(expression.inferredType)
                }
            }
            return .recurse(nil)
        }
        if !foundReturn {
            returnType = statements.last!.inferredType
        }
        return returnType.asOptional(isOptional || returnType.isOptional)
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

/// `continue`
class Continue: Statement {
    let label: String?

    init(label: String? = nil, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.label = label
        super.init(type: .continue, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        guard syntax.kind == .continueStmt, let continueStmnt = syntax.as(ContinueStmtSyntax.self) else {
            return nil
        }
        let label = continueStmnt.label?.text
        return [Continue(label: label, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)]
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return label == nil ? [] : [PrettyPrintTree(root: label!)]
    }
}

/// `defer { ... }`
class Defer: Statement {
    let body: CodeBlock

    init(body: CodeBlock, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.body = body
        super.init(type: .defer, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        guard syntax.kind == .deferStmt, let deferStmt = syntax.as(DeferStmtSyntax.self) else {
            return nil
        }
        let statements = StatementDecoder.decode(syntaxListContainer: deferStmt.body, in: syntaxTree)
        let body = CodeBlock(statements: statements)
        return [Defer(body: body, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)]
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        return body.inferTypes(context: context, expecting: .none)
    }

    override var children: [SyntaxNode] {
        return [body]
    }
}

/// `do { ... } [catch...]`
class DoCatch: Statement {
    let body: CodeBlock
    let catches: [SwitchCase]

    init(body: CodeBlock, catches: [SwitchCase], syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.body = body
        self.catches = catches
        super.init(type: .doCatch, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        guard syntax.kind == .doStmt, let doStmnt = syntax.as(DoStmtSyntax.self) else {
            return nil
        }
        let statements = StatementDecoder.decode(syntaxListContainer: doStmnt.body, in: syntaxTree)
        let body = CodeBlock(statements: statements)
        var catches: [SwitchCase] = []
        var messages: [Message] = []
        if let catchClauses = doStmnt.catchClauses {
            for catchClause in catchClauses {
                if let switchCase = ExpressionDecoder.decode(syntax: catchClause, in: syntaxTree) as? SwitchCase {
                    catches.append(switchCase)
                } else {
                    messages.append(.unsupportedSyntax(catchClauses, source: syntaxTree.source))
                }
            }
        }
        let statement = DoCatch(body: body, catches: catches, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)
        statement.messages = messages
        return [statement]
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        let _ = body.inferTypes(context: context, expecting: .none)
        let errorType: TypeSignature = .named("Error", [])
        catches.forEach { let _ = $0.inferTypes(context: context, expecting: errorType) }
        return context
    }

    override var children: [SyntaxNode] {
        return [body] + catches
    }
}

/// Empty statement typically used to hold trivia.
class Empty: Statement {
    init(syntax: SyntaxProtocol, extras: StatementExtras, in syntaxTree: SyntaxTree) {
        super.init(type: .empty, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)
    }

    init(extras: StatementExtras) {
        super.init(type: .empty, extras: extras)
    }
}

/// `fallthrough`
class Fallthrough: Statement {
    init(syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        super.init(type: .fallthrough, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        guard syntax.kind == .fallthroughStmt else {
            return nil
        }
        return [Fallthrough(syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)]
    }
}

/// `for ... in ... { ... }`
class ForLoop: Statement {
    let identifierPatterns: [IdentifierPattern]
    let declaredType: TypeSignature
    let isTry: Bool
    let isAwait: Bool
    let isNonNilMatch: Bool
    let sequence: Expression
    let whereGuard: Expression?
    let body: CodeBlock

    init(identifierPatterns: [IdentifierPattern], declaredType: TypeSignature = .none, isTry: Bool = false, isAwait: Bool = false, isNonNilMatch: Bool = false, sequence: Expression, whereGuard: Expression? = nil, body: CodeBlock, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.identifierPatterns = identifierPatterns
        self.declaredType = declaredType
        self.isTry = isTry
        self.isAwait = isAwait
        self.isNonNilMatch = isNonNilMatch
        self.sequence = sequence
        self.whereGuard = whereGuard
        self.body = body
        super.init(type: .forLoop, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        guard syntax.kind == .forInStmt, let forInStmnt = syntax.as(ForInStmtSyntax.self) else {
            return nil
        }

        let identifierPatterns: [IdentifierPattern]?
        let isNonNilMatch: Bool
        if forInStmnt.caseKeyword != nil {
            let casePattern = CasePattern(syntax: forInStmnt.pattern, in: syntaxTree)
            identifierPatterns = (casePattern.value as? Binding)?.identifierPatterns
            isNonNilMatch = casePattern.isNonNilMatch
        } else {
            identifierPatterns = forInStmnt.pattern.identifierPatterns(in: syntaxTree)
            isNonNilMatch = false
        }
        guard let identifierPatterns else {
            throw Message.unsupportedSyntax(forInStmnt.pattern, source: syntaxTree.source)
        }
        var declaredType: TypeSignature = .none
        if let typeSyntax = forInStmnt.typeAnnotation?.type {
            declaredType = TypeSignature.for(syntax: typeSyntax)
        }
        let isTry = forInStmnt.tryKeyword != nil
        let isAwait = forInStmnt.awaitKeyword != nil
        let sequence = ExpressionDecoder.decode(syntax: forInStmnt.sequenceExpr, in: syntaxTree)
        var whereGuard: Expression? = nil
        if let whereSyntax = forInStmnt.whereClause?.guardResult {
            whereGuard = ExpressionDecoder.decode(syntax: whereSyntax, in: syntaxTree)
        }
        let statements = StatementDecoder.decode(syntaxListContainer: forInStmnt.body, in: syntaxTree)
        let body = CodeBlock(statements: statements)
        return [ForLoop(identifierPatterns: identifierPatterns, declaredType: declaredType, isTry: isTry, isAwait: isAwait, isNonNilMatch: isNonNilMatch, sequence: sequence, whereGuard: whereGuard, body: body, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)]
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        let _ = sequence.inferTypes(context: context, expecting: declaredType == .none ? .none : .array(declaredType))
        var elementTypes = sequence.inferredType.elementType.tupleTypes(count: identifierPatterns.count)
        if isNonNilMatch {
            elementTypes = elementTypes.map { $0.asOptional(false) }
        }
        let bodyContext = context.addingIdentifiers(identifierPatterns.map(\.name), types: elementTypes)
        whereGuard?.inferTypes(context: bodyContext, expecting: .bool)
        let _ = body.inferTypes(context: bodyContext, expecting: .none)
        return context
    }

    override var children: [SyntaxNode] {
        var children: [SyntaxNode] = [sequence]
        if let whereGuard {
            children.append(whereGuard)
        }
        children.append(body)
        return children
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: identifierPatterns.map { $0.name ?? "_" }.joined(separator: ", "))]
    }
}

/// `guard ...`
class Guard: Statement {
    let conditions: [Expression]
    let body: CodeBlock

    init(conditions: [Expression], body: CodeBlock, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.conditions = conditions
        self.body = body
        super.init(type: .guard, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        guard syntax.kind == .guardStmt, let guardStmnt = syntax.as(GuardStmtSyntax.self) else {
            return nil
        }
        
        let conditions = guardStmnt.conditions.map { ExpressionDecoder.decode(syntax: $0.condition, in: syntaxTree) }
        let statements = StatementDecoder.decode(syntaxListContainer: guardStmnt.body, in: syntaxTree)
        let body = CodeBlock(statements: statements)
        return [Guard(conditions: conditions, body: body, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)]
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        var conditionsContext = context
        for condition in conditions {
            conditionsContext = condition.inferTypes(context: conditionsContext, expecting: .bool)
            if let bindingExpression = condition as? BindingExpression {
                conditionsContext = conditionsContext.addingIdentifiers(bindingExpression.bindings)
            }
        }
        let _ = body.inferTypes(context: context, expecting: .none)
        return conditionsContext
    }

    override var children: [SyntaxNode] {
        return conditions + [body]
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

        let clause = extractClause(from: ifConfigDecl, in: syntaxTree)
        var statements = try extractStatements(from: clause, in: syntaxTree)
        guard let extras else {
            return statements
        }

        // Preserve #if leading and trailng trivia
        if !extras.leadingTrivia.isEmpty {
            let leadingExtras = StatementExtras(directives: extras.directives, leadingTrivia: extras.leadingTrivia, trailingTrivia: [])
            statements.insert(Empty(extras: leadingExtras), at: 0)
        }
        if !extras.trailingTrivia.isEmpty {
            let trailingExtras = StatementExtras(directives: [], leadingTrivia: [], trailingTrivia: extras.trailingTrivia)
            statements.append(Empty(extras: trailingExtras))
        }
        return statements
    }

    /// Decode an `#if` surrounding a set of switch cases.
    static func decodeCaseList(syntax: IfConfigDeclSyntax, in syntaxTree: SyntaxTree) -> ([SwitchCase], [Message]) {
        guard let elements = extractClause(from: syntax, in: syntaxTree)?.elements else {
            return ([], [])
        }
        guard case .switchCases(let caseList) = elements else {
            return ([], [Message.ifDeclPlacement(syntax, source: syntaxTree.source)])
        }
        return Switch.decodeCaseList(syntax: caseList, in: syntaxTree)
    }

    private static func extractClause(from syntax: IfConfigDeclSyntax, in syntaxTree: SyntaxTree) -> IfConfigClauseSyntax? {
        // Look for a clause that matches a defined symbol, or an 'else'
        for ifConfigClause in syntax.clauses {
            if ifConfigClause.poundKeyword.text == "#else" {
                // If we reach an else, all previous clauses must have been false
                return ifConfigClause
            }

            let clauseSymbol = ifConfigClause.condition?.description ?? ""
            let (isSupported, isTrue) = processConditions(symbol: clauseSymbol, preprocessorSymbols: syntaxTree.preprocessorSymbols)
            if !isSupported {
                syntaxTree.root.messages.append(.preprocessorTooComplex(ifConfigClause, source: syntaxTree.source))
                break
            }
            if isTrue {
                return ifConfigClause
            }
        }
        return nil
    }

    private static func processConditions(symbol: String, preprocessorSymbols: Set<String>) -> (isSupported: Bool, isTrue: Bool) {
        let symbols = symbol.split(separator: " ", omittingEmptySubsequences: true)
        var hasTrue: Bool? = nil
        var hasFalse: Bool? = nil
        var hasSymbol = false
        var hasAnd = false
        var hasOr = false
        var hasParens = false
        for var symbol in symbols {
            if symbol == "&&" {
                hasAnd = true
            } else if symbol == "||" {
                hasOr = true
            } else {
                let isNot = symbol.hasPrefix("!")
                if isNot {
                    symbol = symbol.dropFirst()
                } else if symbol.hasPrefix("(") {
                    hasParens = true
                    symbol = symbol.dropFirst()
                } else if symbol.hasSuffix(")") && !symbol.contains("(") {
                    hasParens = true
                    symbol = symbol.dropLast()
                }
                let isSymbol = symbol == "SKIP" || symbol == "os(Android)" || preprocessorSymbols.contains(String(symbol))
                let isTrue = (isSymbol && !isNot) || (!isSymbol && isNot)
                hasSymbol = hasSymbol || isSymbol
                hasTrue = hasTrue == true || isTrue
                hasFalse = hasFalse == true || !isTrue
            }
        }
        if !hasSymbol {
            // Don't process Skip-less preprocessor directives at all
            return (true, false)
        } else if hasParens || (hasAnd && hasOr) {
            // Unsupported
            return (false, false)
        } else if hasAnd {
            return (true, hasFalse != true)
        } else if hasOr {
            return (true, hasTrue == true)
        } else {
            return (true, hasTrue == true)
        }
    }

    private static func extractStatements(from clause: IfConfigClauseSyntax?, in syntaxTree: SyntaxTree) throws -> [Statement] {
        guard let elements = clause?.elements else {
            return []
        }
        switch elements {
        case .statements(let syntax):
            return StatementDecoder.decode(syntaxList: syntax, in: syntaxTree)
        case .switchCases(let syntax):
            throw Message.ifDeclPlacement(syntax, source: syntaxTree.source)
        case .decls(let syntax):
            return StatementDecoder.decode(syntaxList: syntax, in: syntaxTree)
        case .postfixExpression(let syntax):
            throw Message.ifDeclPlacement(syntax, source: syntaxTree.source)
        case .attributes(let syntax):
            throw Message.ifDeclPlacement(syntax, source: syntaxTree.source)
        }
    }
}

/// `label: for/while/etc`
class LabeledStatement: Statement {
    let label: String
    let target: Statement

    init(label: String, target: Statement, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.label = label
        self.target = target
        super.init(type: .labeled, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        guard syntax.kind == .labeledStmt, let labeledStmnt = syntax.as(LabeledStmtSyntax.self) else {
            return nil
        }

        let label = labeledStmnt.label.text
        guard let target = StatementDecoder.decode(syntax: labeledStmnt.statement, in: syntaxTree).first else {
            throw Message.unsupportedSyntax(labeledStmnt.statement, source: syntaxTree.source)
        }
        return [LabeledStatement(label: label, target: target, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))]
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        return target.inferTypes(context: context, expecting: expecting)
    }

    override var inferredType: TypeSignature {
        return target.inferredType
    }

    override var children: [SyntaxNode] {
        return [target]
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: label)]
    }
}

/// `return ...`
class Return: ExpressionStatement {
    init(expression: Expression? = nil, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
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
        return ["return"] + super.prettyPrintAttributes
    }
}

/// `throw ...`
class Throw: Statement {
    let error: Expression

    init(error: Expression, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.error = error
        super.init(type: .throw, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        guard syntax.kind == .throwStmt, let throwStmt = syntax.as(ThrowStmtSyntax.self) else {
            return nil
        }
        let error = ExpressionDecoder.decode(syntax: throwStmt.expression, in: syntaxTree)
        return [Throw(error: error, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)]
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        let _ = error.inferTypes(context: context, expecting: .none)
        return context
    }

    override var children: [SyntaxNode] {
        return [error]
    }
}

/// `while(conditions) { ... }`
class WhileLoop: Statement {
    let conditions: [Expression]
    let body: CodeBlock
    let isRepeatWhile: Bool

    init(conditions: [Expression], body: CodeBlock, isRepeatWhile: Bool = false, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.conditions = conditions
        self.body = body
        self.isRepeatWhile = isRepeatWhile
        super.init(type: .whileLoop, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        if syntax.kind == .whileStmt, let whileStmnt = syntax.as(WhileStmtSyntax.self) {
            return try [decodeWhile(statement: whileStmnt, extras: extras, in: syntaxTree)]
        } else if syntax.kind == .repeatWhileStmt, let repeatWhileStmnt = syntax.as(RepeatWhileStmtSyntax.self) {
            return [decodeRepeatWhile(statement: repeatWhileStmnt, extras: extras, in: syntaxTree)]
        } else {
            return nil
        }
    }

    private static func decodeWhile(statement: WhileStmtSyntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> WhileLoop {
        let conditions = statement.conditions.map { ExpressionDecoder.decode(syntax: $0.condition, in: syntaxTree) }
        let statements = StatementDecoder.decode(syntaxListContainer: statement.body, in: syntaxTree)
        let body = CodeBlock(statements: statements)
        return WhileLoop(conditions: conditions, body: body, syntax: statement, sourceFile: syntaxTree.source.file, sourceRange: statement.range(in: syntaxTree.source), extras: extras)
    }

    private static func decodeRepeatWhile(statement: RepeatWhileStmtSyntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> WhileLoop {
        let condition = ExpressionDecoder.decode(syntax: statement.condition, in: syntaxTree)
        let statements = StatementDecoder.decode(syntaxListContainer: statement.body, in: syntaxTree)
        let body = CodeBlock(statements: statements)
        return WhileLoop(conditions: [condition], body: body, isRepeatWhile: true, syntax: statement, sourceFile: syntaxTree.source.file, sourceRange: statement.range(in: syntaxTree.source), extras: extras)
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        var conditionsContext = context
        var bindings: [String: TypeSignature] = [:]
        for condition in conditions {
            conditionsContext = condition.inferTypes(context: conditionsContext, expecting: .bool)
            if let bindingExpression = condition as? BindingExpression {
                let conditionBindings = bindingExpression.bindings
                conditionsContext = conditionsContext.addingIdentifiers(conditionBindings)
                bindings.merge(conditionBindings) { _, new in new }
            }
        }
        // Condition bindings are available to body in a while loop, but not in a repeat while loop
        if isRepeatWhile {
            let _ = body.inferTypes(context: context, expecting: .none)
        } else {
            let bodyContext = context.pushingBlock(identifiers: bindings)
            let _ = body.inferTypes(context: bodyContext, expecting: .none)
        }
        return context
    }

    override var children: [SyntaxNode] {
        return conditions + [body]
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return isRepeatWhile ? ["repeat"] : []
    }
}

// MARK: - Declarations

/// `case x(Int)`
class EnumCaseDeclaration: Statement {
    let name: String
    private(set) var associatedValues: [Parameter<Expression>]
    let rawValue: Expression?
    let attributes: Attributes
    private(set) var modifiers: Modifiers
    var signature: TypeSignature {
        guard let owningTypeDeclaration else {
            return .none
        }
        guard !associatedValues.isEmpty else {
            return owningTypeDeclaration.signature
        }
        let parameters = associatedValues.map {
            TypeSignature.Parameter(label: $0.externalLabel, type: $0.declaredType, isInOut: $0.isInOut, isVariadic: $0.isVariadic, hasDefaultValue: $0.defaultValue != nil)
        }
        return .function(parameters, owningTypeDeclaration.signature)
    }

    init(name: String, associatedValues: [Parameter<Expression>], rawValue: Expression? = nil, attributes: Attributes = Attributes(), modifiers: Modifiers = Modifiers(), syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.name = name
        self.associatedValues = associatedValues
        self.rawValue = rawValue
        self.attributes = attributes
        self.modifiers = modifiers
        super.init(type: .enumCaseDeclaration, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard syntax.kind == .enumCaseDecl, let enumCaseDecl = syntax.as(EnumCaseDeclSyntax.self) else {
            return nil
        }
        let attributes = Attributes.for(syntax: enumCaseDecl.attributes, in: syntaxTree)
        let modifiers = Modifiers.for(syntax: enumCaseDecl.modifiers)
        return enumCaseDecl.elements.enumerated().map { (index, element) in
            let name = element.identifier.text
            let (associatedValues, messages) = element.associatedValue?.parameters(in: syntaxTree) ?? ([], [])
            let rawValue = element.rawValue.map { ExpressionDecoder.decode(syntax: $0.value, in: syntaxTree) }
            let statement = EnumCaseDeclaration(name: name, associatedValues: associatedValues, rawValue: rawValue, attributes: attributes, modifiers: modifiers, syntax: element, sourceFile: syntaxTree.source.file, sourceRange: element.range(in: syntaxTree.source), extras: index == 0 ? extras : nil)
            statement.messages = messages
            return statement
        }
    }

    override func resolveAttributes(in syntaxTree: SyntaxTree, context: TypeResolutionContext) {
        // Enum case declarations inherit the visibility of the enum
        if modifiers.visibility == .default {
            if let owningTypeDeclaration = parent as? TypeDeclaration {
                modifiers.visibility = owningTypeDeclaration.modifiers.visibility
            } else {
                modifiers.visibility = .internal
            }
        }
        associatedValues = associatedValues.map { $0.resolvedType(in: self, context: context) }
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        associatedValues.forEach { $0.defaultValue?.inferTypes(context: context, expecting: $0.declaredType) }
        return context
    }

    override var children: [SyntaxNode] {
        var children = associatedValues.compactMap { $0.defaultValue }
        if let rawValue {
            children.append(rawValue)
        }
        return children
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var attrs = [PrettyPrintTree(root: name)]
        if !associatedValues.isEmpty {
            attrs.append(PrettyPrintTree(root: "associatedValues", children: associatedValues.map { $0.prettyPrintTree }))
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

/// `extension Type { ... }`
class ExtensionDeclaration: TypeDeclaration {
    let extends: TypeSignature

    init(extends: TypeSignature, inherits: [TypeSignature] = [], attributes: Attributes = Attributes(), modifiers: Modifiers = Modifiers(), generics: Generics = Generics(), members: [Statement] = [], syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.extends = extends
        let name: String
        if extends.baseType != .none {
            name = extends.memberType.name
        } else {
            name = extends.name
        }
        super.init(type: .extensionDeclaration, name: name, signature: extends, inherits: inherits, attributes: attributes, modifiers: modifiers, generics: generics, members: members, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard syntax.kind == .extensionDecl, let extensionDecl = syntax.as(ExtensionDeclSyntax.self) else {
            return nil
        }
        let extends = TypeSignature.for(syntax: extensionDecl.extendedType)
        guard extends != .none else {
            return nil
        }
        let (inherits, inheritsMessages) = extensionDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], [])
        let attributes = Attributes.for(syntax: extensionDecl.attributes, in: syntaxTree)
        let modifiers = Modifiers.for(syntax: extensionDecl.modifiers)
        let (generics, genericsMessages) = Generics.for(syntax: nil, where: extensionDecl.genericWhereClause, in: syntaxTree)
        let members = StatementDecoder.decode(syntaxListContainer: extensionDecl.memberBlock, in: syntaxTree)
        let statement = ExtensionDeclaration(extends: extends, inherits: inherits, attributes: attributes, modifiers: modifiers, generics: generics, members: members, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)
        statement.messages = inheritsMessages + genericsMessages
        return [statement]
    }
}

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
    private(set) var generics: Generics
    let body: CodeBlock?
    var functionType: TypeSignature {
        return .function(parameters.map(\.signature), returnType)
    }

    init(type: StatementType, name: String, isOptionalInit: Bool = false, returnType: TypeSignature = .void, parameters: [Parameter<Expression>] = [], isAsync: Bool = false, isThrows: Bool = false, attributes: Attributes = Attributes(), modifiers: Modifiers = Modifiers(), generics: Generics = Generics(), body: CodeBlock? = nil, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.name = name
        self.isOptionalInit = isOptionalInit
        self.returnType = returnType.or(.void)
        self.parameters = parameters
        self.isAsync = isAsync
        self.isThrows = isThrows
        self.attributes = attributes
        self.modifiers = modifiers
        self.generics = generics
        self.body = body
        super.init(type: type, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        if syntax.kind == .functionDecl, let functionDecl = syntax.as(FunctionDeclSyntax.self) {
            return [decodeFunctionDeclaration(functionDecl, extras: extras, in: syntaxTree)]
        } else if syntax.kind == .initializerDecl, let initializerDecl = syntax.as(InitializerDeclSyntax.self) {
            return [decodeInitializerDeclaration(initializerDecl, extras: extras, in: syntaxTree)]
        } else if syntax.kind == .deinitializerDecl, let deinitializerDecl = syntax.as(DeinitializerDeclSyntax.self) {
            return [decodeDeinitializerDeclaration(deinitializerDecl, extras: extras, in: syntaxTree)]
        } else {
            return nil
        }
    }

    private static func decodeFunctionDeclaration(_ functionDecl: FunctionDeclSyntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> FunctionDeclaration {
        let name = functionDecl.identifier.text
        let (returnType, parameters, signatureMessges) = functionDecl.signature.typeSignatures(in: syntaxTree)
        let isAsync = functionDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = functionDecl.signature.effectSpecifiers?.throwsSpecifier != nil
        let attributes = Attributes.for(syntax: functionDecl.attributes, in: syntaxTree)
        let modifiers = Modifiers.for(syntax: functionDecl.modifiers)
        let (generics, genericsMessages) = Generics.for(syntax: functionDecl.genericParameterClause, where: functionDecl.genericWhereClause, in: syntaxTree)
        var body: CodeBlock? = nil
        if let bodySyntax = functionDecl.body {
            body = CodeBlock(statements: StatementDecoder.decode(syntaxListContainer: bodySyntax, in: syntaxTree))
        }
        let statement = FunctionDeclaration(type: .functionDeclaration, name: name, returnType: returnType, parameters: parameters, isAsync: isAsync, isThrows: isThrows, attributes: attributes, modifiers: modifiers, generics: generics, body: body, syntax: functionDecl, sourceFile: syntaxTree.source.file, sourceRange: functionDecl.range(in: syntaxTree.source), extras: extras)
        statement.messages = signatureMessges + genericsMessages
        return statement
    }

    private static func decodeInitializerDeclaration(_ initializerDecl: InitializerDeclSyntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> FunctionDeclaration {
        let isOptionalInit = initializerDecl.optionalMark != nil
        let (_, parameters, signatureMessages) = initializerDecl.signature.typeSignatures(in: syntaxTree)
        let isAsync = initializerDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = initializerDecl.signature.effectSpecifiers?.throwsSpecifier != nil
        let attributes = Attributes.for(syntax: initializerDecl.attributes, in: syntaxTree)
        let modifiers = Modifiers.for(syntax: initializerDecl.modifiers)
        let (generics, genericsMessages) = Generics.for(syntax: initializerDecl.genericParameterClause, where: initializerDecl.genericWhereClause, in: syntaxTree)
        var body: CodeBlock? = nil
        if let bodySyntax = initializerDecl.body {
            body = CodeBlock(statements: StatementDecoder.decode(syntaxListContainer: bodySyntax, in: syntaxTree))
        }
        let statement = FunctionDeclaration(type: .initDeclaration, name: "init", isOptionalInit: isOptionalInit, returnType: .void, parameters: parameters, isAsync: isAsync, isThrows: isThrows, attributes: attributes, modifiers: modifiers, generics: generics, body: body, syntax: initializerDecl, sourceFile: syntaxTree.source.file, sourceRange: initializerDecl.range(in: syntaxTree.source), extras: extras)
        statement.messages = signatureMessages + genericsMessages
        return statement
    }

    private static func decodeDeinitializerDeclaration(_ deinitializerDecl: DeinitializerDeclSyntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> FunctionDeclaration {
        let attributes = Attributes.for(syntax: deinitializerDecl.attributes, in: syntaxTree)
        let modifiers = Modifiers.for(syntax: deinitializerDecl.modifiers)
        var body: CodeBlock? = nil
        if let bodySyntax = deinitializerDecl.body {
            body = CodeBlock(statements: StatementDecoder.decode(syntaxListContainer: bodySyntax, in: syntaxTree))
        }
        let statement = FunctionDeclaration(type: .deinitDeclaration, name: "deinit", returnType: .void, attributes: attributes, modifiers: modifiers, body: body, syntax: deinitializerDecl, sourceFile: syntaxTree.source.file, sourceRange: deinitializerDecl.range(in: syntaxTree.source), extras: extras)
        return statement
    }

    override func resolveAttributes(in syntaxTree: SyntaxTree, context: TypeResolutionContext) {
        if type == .initDeclaration, let owningTypeDeclaration {
            returnType = owningTypeDeclaration.signature.asOptional(isOptionalInit)
        } else {
            returnType = returnType.resolved(in: self, context: context)
        }
        parameters = parameters.map { $0.resolvedType(in: self, context: context) }
        // Functions in protocols or extensions inherit the visibility of the protocol or extension
        if modifiers.visibility == .default {
            if let owningTypeDeclaration = parent as? TypeDeclaration, (owningTypeDeclaration.type == .protocolDeclaration || owningTypeDeclaration.type == .extensionDeclaration) {
                modifiers.visibility = owningTypeDeclaration.modifiers.visibility
            } else {
                modifiers.visibility = .internal
            }
        }
        generics = generics.resolved(in: self, context: context)
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        parameters.forEach { $0.defaultValue?.inferTypes(context: context, expecting: $0.declaredType) }
        if let body {
            let bodyContext = context.pushing(self)
            let _ = body.inferTypes(context: bodyContext, expecting: .none)
        }
        if parent?.owningFunctionDeclaration != nil {
            // Add identifier if local function
            return context.addingLocalFunction(self)
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
            attrs.append("async")
        }
        if isThrows {
            attrs.append("throws")
        }
        if !attributes.isEmpty {
            attrs.append(attributes.prettyPrintTree)
        }
        if !modifiers.isEmpty {
            attrs.append(modifiers.prettyPrintTree)
        }
        if !generics.isEmpty {
            attrs.append(generics.prettyPrintTree)
        }
        return attrs
    }
}

/// `import Module`
class ImportDeclaration: Statement {
    let modulePath: [String]

    init(modulePath: [String], syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
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

/// `subscript() { ... }`
class SubscriptDeclaration: Statement {
    private(set) var elementType: TypeSignature
    private(set) var parameters: [Parameter<Expression>]
    let isAsync: Bool
    let isThrows: Bool
    let attributes: Attributes
    private(set) var modifiers: Modifiers
    private(set) var generics: Generics
    let getter: Accessor<CodeBlock>?
    let setter: Accessor<CodeBlock>?
    var getterType: TypeSignature {
        return .function(parameters.map(\.signature), elementType)
    }
    var setterType: TypeSignature {
        return .function(parameters.map(\.signature), .void)
    }

    init(elementType: TypeSignature, parameters: [Parameter<Expression>], isAsync: Bool = false, isThrows: Bool = false, attributes: Attributes = Attributes(), modifiers: Modifiers = Modifiers(), generics: Generics = Generics(), getter: Accessor<CodeBlock>? = nil, setter: Accessor<CodeBlock>? = nil, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.elementType = elementType
        self.parameters = parameters
        self.isAsync = isAsync
        self.isThrows = isThrows
        self.attributes = attributes
        self.modifiers = modifiers
        self.generics = generics
        self.getter = getter
        self.setter = setter
        super.init(type: .subscriptDeclaration, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard syntax.kind == .subscriptDecl, let subscriptDecl = syntax.as(SubscriptDeclSyntax.self) else {
            return nil
        }
        let elementType = TypeSignature.for(syntax: subscriptDecl.result.returnType)
        let (parameters, parametersMessages) = subscriptDecl.indices.parameters(in: syntaxTree)
        let attributes = Attributes.for(syntax: subscriptDecl.attributes, in: syntaxTree)
        let modifiers = Modifiers.for(syntax: subscriptDecl.modifiers)
        let (generics, genericsMessages) = Generics.for(syntax: subscriptDecl.genericParameterClause, where: subscriptDecl.genericWhereClause, in: syntaxTree)
        var accessors = Accessors()
        if let accessor = subscriptDecl.accessor {
            switch accessor {
            case .accessors(let syntax):
                accessors = syntax.accessors(in: syntaxTree)
            case .getter(let syntax):
                let statements = StatementDecoder.decode(syntaxListContainer: syntax, in: syntaxTree)
                accessors.getter = Accessor(body: CodeBlock(statements: statements))
            }
        }
        let statement = SubscriptDeclaration(elementType: elementType, parameters: parameters, isAsync: accessors.isAsync, isThrows: accessors.isThrows, attributes: attributes, modifiers: modifiers, generics: generics, getter: accessors.getter, setter: accessors.setter, sourceFile: syntaxTree.source.file, sourceRange: subscriptDecl.range(in: syntaxTree.source), extras: extras)
        statement.messages = accessors.messages + parametersMessages + genericsMessages
        return [statement]
    }

    override func resolveAttributes(in syntaxTree: SyntaxTree, context: TypeResolutionContext) {
        elementType = elementType.resolved(in: self, context: context)
        parameters = parameters.map { $0.resolvedType(in: self, context: context) }
        // Functions in protocols or extensions inherit the visibility of the protocol or extension
        if modifiers.visibility == .default {
            if let owningTypeDeclaration = parent as? TypeDeclaration, (owningTypeDeclaration.type == .protocolDeclaration || owningTypeDeclaration.type == .extensionDeclaration) {
                modifiers.visibility = owningTypeDeclaration.modifiers.visibility
            } else {
                modifiers.visibility = .internal
            }
        }
        generics = generics.resolved(in: self, context: context)
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        parameters.forEach { $0.defaultValue?.inferTypes(context: context, expecting: $0.declaredType) }
        if let body = getter?.body {
            let bodyContext = context.expectingReturn(elementType)
            let _ = body.inferTypes(context: bodyContext, expecting: .none)
        }
        if let body = setter?.body {
            let bodyContext = context.addingIdentifier(setter?.parameterName ?? "newValue", type: elementType)
            let _ = body.inferTypes(context: bodyContext, expecting: .none)
        }
        return context
    }

    override var children: [SyntaxNode] {
        var children: [SyntaxNode] = []
        if let body = getter?.body {
            children.append(body)
        }
        if let body = setter?.body {
            children.append(body)
        }
        return children
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var attrs: [PrettyPrintTree] = []
        if elementType != .none {
            attrs.append(PrettyPrintTree(root: elementType.description))
        }
        if isAsync {
            attrs.append("async")
        }
        if isThrows {
            attrs.append("throws")
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

/// `typealias ...`
class TypealiasDeclaration: Statement {
    let name: String
    let attributes: Attributes
    private(set) var modifiers: Modifiers
    private(set) var generics: Generics
    private(set) var aliasedType: TypeSignature
    var signature: TypeSignature {
        return _signature ?? .named(name, generics.entries.map(\.namedType))
    }
    private var _signature: TypeSignature?

    init(name: String, attributes: Attributes = Attributes(), modifiers: Modifiers = Modifiers(), generics: Generics = Generics(), aliasedType: TypeSignature, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.name = name
        self.attributes = attributes
        self.modifiers = modifiers
        self.generics = generics
        self.aliasedType = aliasedType
        super.init(type: .typealiasDeclaration, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> [Statement]? {
        guard syntax.kind == .typealiasDecl, let typealiasDecl = syntax.as(TypealiasDeclSyntax.self) else {
            return nil
        }
        let name = typealiasDecl.identifier.text
        let attributes = Attributes.for(syntax: typealiasDecl.attributes, in: syntaxTree)
        let modifiers = Modifiers.for(syntax: typealiasDecl.modifiers)
        let (generics, messages) = Generics.for(syntax: typealiasDecl.genericParameterClause, where: typealiasDecl.genericWhereClause, in: syntaxTree)
        let aliasedType = TypeSignature.for(syntax: typealiasDecl.initializer.value)
        let statement = TypealiasDeclaration(name: name, attributes: attributes, modifiers: modifiers, generics: generics, aliasedType: aliasedType, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)
        statement.messages = messages
        return [statement]
    }

    override func resolveAttributes(in syntaxTree: SyntaxTree, context: TypeResolutionContext) {
        if _signature == nil {
            _signature = qualifyDeclaredType(signature)
        }
        generics = generics.resolved(in: self, context: context)
        aliasedType = aliasedType.resolved(in: self, context: context)
        // Aliases in protocols or extensions inherit the visibility of the protocol or extension
        if modifiers.visibility == .default {
            if let owningTypeDeclaration = parent as? TypeDeclaration, (owningTypeDeclaration.type == .protocolDeclaration || owningTypeDeclaration.type == .extensionDeclaration) {
                modifiers.visibility = owningTypeDeclaration.modifiers.visibility
            } else {
                modifiers.visibility = .internal
            }
        }
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var attrs = [PrettyPrintTree(root: name)]
        if !modifiers.isEmpty {
            attrs.append(modifiers.prettyPrintTree)
        }
        if !generics.isEmpty {
            attrs.append(generics.prettyPrintTree)
        }
        attrs.append(PrettyPrintTree(root: aliasedType.description))
        return attrs
    }
}

/// `class/struct/enum/protocol Type { ... }`
class TypeDeclaration: Statement {
    let name: String
    private(set) var inherits: [TypeSignature]
    let attributes: Attributes
    private(set) var modifiers: Modifiers
    private(set) var generics: Generics
    let members: [Statement]
    var signature: TypeSignature {
        return _signature ?? TypeSignature.for(name: name, genericTypes: generics.entries.map(\.namedType))
    }
    private var _signature: TypeSignature?

    init(type: StatementType, name: String, signature: TypeSignature? = nil, inherits: [TypeSignature] = [], attributes: Attributes = Attributes(), modifiers: Modifiers = Modifiers(), generics: Generics = Generics(), members: [Statement] = [], syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.name = name
        _signature = signature
        self.inherits = inherits
        self.attributes = attributes
        self.modifiers = modifiers
        self.generics = generics
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
        } else if syntax.kind == .actorDecl, let actorDecl = syntax.as(ActorDeclSyntax.self) {
            return [decodeActorDeclaration(actorDecl, extras: extras, in: syntaxTree)]
        }
        return nil
    }

    private static func decodeClassDeclaration(_ classDecl: ClassDeclSyntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> TypeDeclaration {
        let name = classDecl.identifier.text
        let (inherits, inheritsMessages) = classDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], [])
        let attributes = Attributes.for(syntax: classDecl.attributes, in: syntaxTree)
        let modifiers = Modifiers.for(syntax: classDecl.modifiers)
        let (generics, genericsMessages) = Generics.for(syntax: classDecl.genericParameterClause, where: classDecl.genericWhereClause, in: syntaxTree)
        let members = StatementDecoder.decode(syntaxListContainer: classDecl.memberBlock, in: syntaxTree)
        let statement = TypeDeclaration(type: .classDeclaration, name: name, inherits: inherits, attributes: attributes, modifiers: modifiers, generics: generics, members: members, syntax: classDecl, sourceFile: syntaxTree.source.file, sourceRange: classDecl.range(in: syntaxTree.source), extras: extras)
        statement.messages = inheritsMessages + genericsMessages
        return statement
    }

    private static func decodeStructDeclaration(_ structDecl: StructDeclSyntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> TypeDeclaration {
        let name = structDecl.identifier.text
        let (inherits, inheritsMessages) = structDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], [])
        let attributes = Attributes.for(syntax: structDecl.attributes, in: syntaxTree)
        let modifiers = Modifiers.for(syntax: structDecl.modifiers)
        let (generics, genericsMessages) = Generics.for(syntax: structDecl.genericParameterClause, where: structDecl.genericWhereClause, in: syntaxTree)
        let members = StatementDecoder.decode(syntaxListContainer: structDecl.memberBlock, in: syntaxTree)
        let statement = TypeDeclaration(type: .structDeclaration, name: name, inherits: inherits, attributes: attributes, modifiers: modifiers, generics: generics, members: members, syntax: structDecl, sourceFile: syntaxTree.source.file, sourceRange: structDecl.range(in: syntaxTree.source), extras: extras)
        statement.messages = inheritsMessages + genericsMessages
        return statement
    }

    private static func decodeProtocolDeclaration(_ protocolDecl: ProtocolDeclSyntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> TypeDeclaration {
        let name = protocolDecl.identifier.text
        let (inherits, inheritsMessages) = protocolDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], [])
        let attributes = Attributes.for(syntax: protocolDecl.attributes, in: syntaxTree)
        let modifiers = Modifiers.for(syntax: protocolDecl.modifiers)
        let associatedTypeDecls = protocolDecl.memberBlock.members.compactMap { $0.decl.kind == .associatedtypeDecl ? $0.decl.as(AssociatedtypeDeclSyntax.self) : nil }
        let memberDecls = protocolDecl.memberBlock.members.compactMap { $0.decl.kind != .associatedtypeDecl ? $0.decl : nil }
        let (generics, genericsMessages) = Generics.for(syntax: nil, associatedTypeSyntax: associatedTypeDecls, where: protocolDecl.genericWhereClause, in: syntaxTree)
        let members = memberDecls.flatMap { StatementDecoder.decode(syntax: $0, in: syntaxTree) }
        let statement = TypeDeclaration(type: .protocolDeclaration, name: name, inherits: inherits, attributes: attributes, modifiers: modifiers, generics: generics, members: members, syntax: protocolDecl, sourceFile: syntaxTree.source.file, sourceRange: protocolDecl.range(in: syntaxTree.source), extras: extras)
        statement.messages = inheritsMessages + genericsMessages
        return statement
    }

    private static func decodeEnumDeclaration(_ enumDecl: EnumDeclSyntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> TypeDeclaration {
        let name = enumDecl.identifier.text
        let (inherits, inheritsMessages) = enumDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], [])
        let attributes = Attributes.for(syntax: enumDecl.attributes, in: syntaxTree)
        let modifiers = Modifiers.for(syntax: enumDecl.modifiers)
        let (generics, genericsMessages) = Generics.for(syntax: enumDecl.genericParameterClause, where: enumDecl.genericWhereClause, in: syntaxTree)
        let members = StatementDecoder.decode(syntaxListContainer: enumDecl.memberBlock, in: syntaxTree)
        let statement = TypeDeclaration(type: .enumDeclaration, name: name, inherits: inherits, attributes: attributes, modifiers: modifiers, generics: generics, members: members, syntax: enumDecl, sourceFile: syntaxTree.source.file, sourceRange: enumDecl.range(in: syntaxTree.source), extras: extras)
        statement.messages = inheritsMessages + genericsMessages
        return statement
    }

    private static func decodeActorDeclaration(_ actorDecl: ActorDeclSyntax, extras: StatementExtras?, in syntaxTree: SyntaxTree) -> TypeDeclaration {
        let name = actorDecl.identifier.text
        let (inherits, inheritsMessages) = actorDecl.inheritanceClause?.inheritedTypeCollection.typeSignatures(in: syntaxTree) ?? ([], [])
        let attributes = Attributes.for(syntax: actorDecl.attributes, in: syntaxTree)
        let modifiers = Modifiers.for(syntax: actorDecl.modifiers)
        let (generics, genericsMessages) = Generics.for(syntax: actorDecl.genericParameterClause, where: actorDecl.genericWhereClause, in: syntaxTree)
        let members = StatementDecoder.decode(syntaxListContainer: actorDecl.memberBlock, in: syntaxTree)
        let statement = TypeDeclaration(type: .actorDeclaration, name: name, inherits: inherits, attributes: attributes, modifiers: modifiers, generics: generics, members: members, syntax: actorDecl, sourceFile: syntaxTree.source.file, sourceRange: actorDecl.range(in: syntaxTree.source), extras: extras)
        statement.messages = inheritsMessages + genericsMessages
        return statement
    }

    override func resolveAttributes(in syntaxTree: SyntaxTree, context: TypeResolutionContext) {
        if parent?.owningFunctionDeclaration != nil {
            messages.append(.localTypesNotSupported(self, source: syntaxTree.source))
        }
        if _signature == nil {
            _signature = qualifyDeclaredType(signature)
        }
        inherits = inherits.map { $0.resolved(in: self, context: context) }
        if modifiers.visibility == .default {
            modifiers.visibility = .internal
        }
        generics = generics.resolved(in: self, context: context)
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
        if !generics.isEmpty {
            attrs.append(generics.prettyPrintTree)
        }
        return attrs
    }
}

/// `let/var v ...`
class VariableDeclaration: Statement {
    let names: [String?]
    var propertyName: String {
        return (names.first ?? "") ?? ""
    }
    var propertyType: TypeSignature {
        return variableTypes.first ?? .none
    }
    private(set) var declaredType: TypeSignature
    private(set) var constrainedDeclaredType: TypeSignature
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
    var variableTypes: [TypeSignature] {
        return declaredType.or(value?.inferredType ?? .none).tupleTypes(count: names.count)
    }

    init(names: [String?], declaredType: TypeSignature = .none, isLet: Bool = false, isAsync: Bool = false, isThrows: Bool = false, attributes: Attributes = Attributes(), modifiers: Modifiers = Modifiers(), value: Expression?, getter: Accessor<CodeBlock>? = nil, setter: Accessor<CodeBlock>? = nil, willSet: Accessor<CodeBlock>? = nil, didSet: Accessor<CodeBlock>? = nil, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.names = names
        self.declaredType = declaredType
        self.constrainedDeclaredType = declaredType
        self.isLet = isLet
        self.isAsync = isAsync
        self.isThrows = isThrows
        self.attributes = attributes
        self.modifiers = modifiers
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

        let isLet = variableDecl.bindingSpecifier.text == "let"
        let attributes = Attributes.for(syntax: variableDecl.attributes, in: syntaxTree)
        let modifiers = Modifiers.for(syntax: variableDecl.modifiers)
        var statements: [Statement] = []
        for (index, syntax) in variableDecl.bindings.enumerated() {
            let bindingExtras = index == 0 ? extras : nil
            let statement = try decode(syntax: syntax, isLet: isLet, attributes: attributes, modifiers: modifiers, extras: bindingExtras, in: syntaxTree)
            statements.append(statement)
        }
        return statements
    }

    private static func decode(syntax: PatternBindingSyntax, isLet: Bool, attributes: Attributes, modifiers: Modifiers, extras: StatementExtras?, in syntaxTree: SyntaxTree) throws -> Statement {
        var declaredType: TypeSignature = .none
        if let typeSyntax = syntax.typeAnnotation?.type {
            declaredType = TypeSignature.for(syntax: typeSyntax)
        }
        var value: Expression? = nil
        if let valueSyntax = syntax.initializer?.value {
            value = ExpressionDecoder.decode(syntax: valueSyntax, in: syntaxTree)
        }

        var accessors: Accessors = Accessors()
        if let accessor = syntax.accessor {
            switch accessor {
            case .accessors(let accessorBlockSyntax):
                accessors = accessorBlockSyntax.accessors(in: syntaxTree)
            case .getter(let codeBlockSyntax):
                let statements = StatementDecoder.decode(syntaxListContainer: codeBlockSyntax, in: syntaxTree)
                accessors.getter = Accessor(body: CodeBlock(statements: statements))
            }
        }

        guard let names = syntax.pattern.identifierPatterns(in: syntaxTree)?.map(\.name) else {
            throw Message.unsupportedSyntax(syntax.pattern, source: syntaxTree.source)
        }
        let declaration = VariableDeclaration(names: names, declaredType: declaredType, isLet: isLet, isAsync: accessors.isAsync, isThrows: accessors.isThrows, attributes: attributes, modifiers: modifiers, value: value, getter: accessors.getter, setter: accessors.setter, willSet: accessors.willSet, didSet: accessors.didSet, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)
        declaration.messages = accessors.messages
        return declaration
    }

    override func resolveAttributes(in syntaxTree: SyntaxTree, context: TypeResolutionContext) {
        declaredType = declaredType.resolved(in: self, context: context)
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
        constrainedDeclaredType = declaredType.constrainedTypeWithGenerics(context.generics)
        value?.inferTypes(context: context, expecting: declaredType)
        let type = TypeSignature.for(labels: names, types: variableTypes)
        if let body = getter?.body {
            let bodyContext = context.expectingReturn(type)
            let _ = body.inferTypes(context: bodyContext, expecting: .none)
        }
        if let body = setter?.body {
            let bodyContext = context.addingIdentifier(setter?.parameterName ?? "newValue", type: type)
            let _ = body.inferTypes(context: bodyContext, expecting: .none)
        }
        if let body = willSet?.body {
            let bodyContext = context.addingIdentifier(willSet?.parameterName ?? "newValue", type: type)
            let _ = body.inferTypes(context: bodyContext, expecting: .none)
        }
        if let body = didSet?.body {
            let bodyContext = context.addingIdentifier(didSet?.parameterName ?? "oldValue", type: type)
            let _ = body.inferTypes(context: bodyContext, expecting: .none)
        }
        if parent is TypeDeclaration {
            return context
        } else {
            // Local variable in code block
            return context.addingIdentifiers(names, types: variableTypes)
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
        var attrs = [PrettyPrintTree(root: names.map { $0 ?? "_" }.joined(separator: ", "))]
        if declaredType != .none {
            attrs.append(PrettyPrintTree(root: declaredType.description))
        }
        if isAsync {
            attrs.append("async")
        }
        if isThrows {
            attrs.append("throws")
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
