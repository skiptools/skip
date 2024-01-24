/// Types of Kotlin statements.
enum KotlinStatementType {
    case `break`
    case codeBlock
    case `continue`
    case `defer`
    case empty
    case expression
    case forLoop
    case labeledStatement
    case `return`
    case run
    case `throw`
    case tryCatch
    case whileLoop

    case classDeclaration
    case constructorDeclaration
    case enumCaseDeclaration
    case extensionDeclaration
    case finalizerDeclaration
    case functionDeclaration
    case importDeclaration
    case interfaceDeclaration
    case typealiasDeclaration
    case variableDeclaration

    // Special statements
    case raw
    case message
}

class KotlinBreak: KotlinStatement, KotlinSingleStatementAppendable {
    var label: String?

    init(statement: Break) {
        self.label = statement.label
        super.init(type: .break, statement: statement)
    }

    init() {
        super.init(type: .break)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation)
        appendAsSingleStatement(to: output, indentation: indentation, mode: .closure)
        output.append("\n")
    }

    func isSingleStatementAppendable(mode: KotlinSingleStatementAppendMode) -> Bool {
        return mode != .function
    }

    func appendAsSingleStatement(to output: OutputGenerator, indentation: Indentation, mode: KotlinSingleStatementAppendMode) {
        output.append("break")
        if let label {
            output.append("@\(label)")
        }
    }
}

class KotlinCodeBlock: KotlinStatement, KotlinSingleStatementAppendable {
    var statements: [KotlinStatement]

    /// The number of defer statements in this block.
    var deferCount = 0
    /// Uniquify variables used to track defer actions.
    var deferVariableSuffix = 0

    /// Any catch clauses.
    var catches: [KotlinCase] = []

    /// A finally statement to execute for this block.
    var syntheticFinally: String? {
        // Avoid unnecessarily nested try/catch/finally blocks by passing down catch and finally conditions
        get {
            if let tryCatch {
                return tryCatch.body.syntheticFinally
            } else {
                return _syntheticFinally
            }
        }
        set {
            if let tryCatch {
                tryCatch.body.syntheticFinally = newValue
            } else {
                _syntheticFinally = newValue
            }
        }
    }
    private var _syntheticFinally: String?
    private var tryCatch: KotlinTryCatch? {
        return statements.count == 1 ? statements.first as? KotlinTryCatch : nil
    }

    /// Whether this code block will be output as a try/catch/finally.
    var isTryCatch: Bool {
        return deferCount > 0 || !catches.isEmpty || _syntheticFinally != nil
    }

    static func translate(statement: CodeBlock, translator: KotlinTranslator) -> KotlinCodeBlock {
        let kstatements = statement.statements.flatMap { translator.translateStatement($0) }
        let kcodeBlock = KotlinCodeBlock(statements: kstatements)
        let kdefers = kstatements.compactMap { $0 as? KotlinDefer }
        kcodeBlock.deferCount = kdefers.count
        kdefers.forEach { $0.codeBlock = kcodeBlock }
        return kcodeBlock
    }

    init(statements: [KotlinStatement] = []) {
        self.statements = statements
        super.init(type: .codeBlock)
    }

    /// Perform any necessary updates to the return statements in this block.
    ///
    /// - Returns: Whether any return statements were found.
    @discardableResult func updateWithExpectedReturn(_ expectedReturn: KotlinExpectedReturn) -> Bool {
        var label: String?
        var assignToSelf = false
        var sref = false
        var throwIfNull = false
        var returnRequired = false
        var returnValue: KotlinExpression? = nil
        var onUpdate: (() -> String)? = nil
        switch expectedReturn {
        case .no:
            // Don't shortcut and return here because we need to return whether any return statements were found
            break
        case .yes:
            returnRequired = true
        case .assignToSelf:
            assignToSelf = true
        case .labelIfPresent(let l):
            label = l
        case .sref(let update):
            onUpdate = update
            sref = true
            returnRequired = true
        case .throwIfNull:
            throwIfNull = true
        case .value(let value, let asReturn, let valueLabel):
            returnValue = value
            returnRequired = asReturn
            label = valueLabel
        }

        var didFindReturn = false
        visit { node in
            if let statement = node as? KotlinStatement {
                switch statement.type {
                case .expression:
                    if assignToSelf, let binaryOperator = (statement as? KotlinExpressionStatement)?.expression as? KotlinBinaryOperator {
                        if (binaryOperator.lhs as? KotlinIdentifier)?.name == "self" {
                            let returnStatement = KotlinReturn(expression: binaryOperator.rhs)
                            if let parent = statement.parent as? KotlinStatement {
                                parent.insert(statements: [returnStatement], after: statement)
                                parent.remove(statement: statement)
                            } else {
                                statement.messages.append(.internalError(statement))
                            }
                            didFindReturn = true
                        }
                        return .skip
                    }
                case .return:
                    let returnStatement = statement as! KotlinReturn
                    didFindReturn = true
                    if let label {
                        returnStatement.label = label
                    }
                    if throwIfNull, let returnExpression = returnStatement.expression, returnExpression is KotlinNullLiteral {
                        let throwStatement = KotlinRawStatement(sourceCode: "throw NullReturnException()", sourceFile: statement.sourceFile, sourceRange: statement.sourceRange)
                        if let parent = statement.parent as? KotlinStatement {
                            parent.insert(statements: [throwStatement], after: statement)
                            parent.remove(statement: statement)
                        } else {
                            statement.messages.append(.internalError(statement))
                        }
                    } else if sref {
                        returnStatement.expression = returnStatement.expression?.sref(onUpdate: onUpdate)
                    }
                    if let returnValue, returnStatement.expression == nil {
                        let expression: KotlinExpression = returnValue.parent == nil ? returnValue : KotlinSharedExpressionPointer(shared: returnValue)
                        returnStatement.expression = expression
                        expression.parent = returnStatement
                    }
                    return .skip
                case .functionDeclaration:
                    // Skip embedded functions that may have their own returns
                    return .skip
                default:
                    break
                }
                return .recurse(nil)
            } else if node is KotlinClosure {
                // Skip closures that may have their own returns
                return .skip
            } else {
                return .recurse(nil)
            }
        }

        // If we must return a certain value, add a return statement at the end if needed
        if let returnValue {
            if statements.last?.type != .return {
                let expression: KotlinExpression = returnValue.parent == nil ? returnValue : KotlinSharedExpressionPointer(shared: returnValue)
                let statement: KotlinStatement
                if returnRequired {
                    let returnStatement = KotlinReturn(expression: expression)
                    returnStatement.label = label
                    statement = returnStatement
                } else {
                    statement = KotlinExpressionStatement(expression: expression)
                }
                expression.parent = statement
                statements.append(statement)
                statement.parent = self
            }
            return didFindReturn
        }

        // Otherwise if this was an implicit return, replace it with an explicit one if a return is required
        if didFindReturn {
            return true
        }
        guard returnRequired, statements.count == 1, statements[0].type == .expression, let expressionStatement = statements[0] as? KotlinExpressionStatement, var expression = expressionStatement.expression else {
            return false
        }
        // No need to return if throwing a fatal error
        if let functionCall = expression as? KotlinFunctionCall, functionCall.arguments.isEmpty, let functionIdentifier = functionCall.function as? KotlinIdentifier, functionIdentifier.name == "fatalError" {
            return false
        }
        if sref {
            expression = expression.sref(onUpdate: onUpdate)
        }
        let returnStatement = KotlinReturn(expression: expression)
        returnStatement.extras = expressionStatement.extras
        expression.parent = returnStatement
        statements = [returnStatement]
        returnStatement.parent = self
        return true
    }

    /// If this code block is a single return statement, remove the return.
    func updateRemovingSingleStatementReturn() -> Bool {
        guard !isTryCatch && statements.count == 1 else {
            return false
        }
        guard let returnStatement = statements[0] as? KotlinReturn else {
            return false
        }
        if let expression = returnStatement.expression {
            statements = [KotlinExpressionStatement(expression: expression)]
            statements[0].parent = self
            expression.parent = statements[0]
        } else {
            statements = []
        }
        return true
    }

    /// Perform any updates to handle references to the given `inout` parameter.
    func updateWithInOutParameter(name: String, source: Source) {
        visit { node in
            if let identifier = node as? KotlinIdentifier {
                if identifier.name == name {
                    identifier.valueSuffix = ".value"
                }
            } else if let variableDeclaration = node as? KotlinVariableDeclaration {
                if variableDeclaration.names.contains(name) {
                    variableDeclaration.messages.append(.kotlinInOutParameterAssignment(variableDeclaration, source: source))
                }
            }
            return .recurse(nil)
        }
    }

    /// Perform any updates to handle references to the given SwiftUI Binding.
    func updateWithSwiftUIBindingParameter(name: String, source: Source) {
        let bindingName = "$" + name
        visit { node in
            if let identifier = node as? KotlinIdentifier {
                if identifier.name == name {
                    identifier.valueSuffix = ".wrappedValue"
                } else if identifier.name == bindingName {
                    identifier.isSwiftUIBindingParameter = true
                }
            } else if let variableDeclaration = node as? KotlinVariableDeclaration {
                if variableDeclaration.names.contains(name) {
                    variableDeclaration.messages.append(.kotlinBindingParameterAssignment(variableDeclaration, source: source))
                }
            }
            return .recurse(nil)
        }
    }

    /// Perform any updates to handle the given 'async let' declaration.
    ///
    /// - Note: The declaration should be a direct child of this code block.
    func updateWithAsyncLet(declaration: KotlinVariableDeclaration, source: Source) {
        var hasCreatedBinding = false
        statements.forEach {
            $0.visit { node in
                if !hasCreatedBinding {
                    hasCreatedBinding = node === declaration
                    return .skip
                }
                if let identifier = node as? KotlinIdentifier {
                    if identifier.name == declaration.propertyName {
                        identifier.valueSuffix = ".value()"
                    }
                } else if let variableDeclaration = node as? KotlinVariableDeclaration, !variableDeclaration.isAsyncLet {
                    if variableDeclaration.names.contains(declaration.propertyName) {
                        variableDeclaration.messages.append(.kotlinAsyncLetAssignment(variableDeclaration, source: source))
                    }
                }
                return .recurse(nil)
            }
        }
    }

    override var children: [KotlinSyntaxNode] {
        return statements + catches.flatMap { $0.children }
    }

    override func insert(statements: [KotlinStatement], after statement: KotlinStatement?) {
        var index = 0
        if let statement {
            if let statementIndex = self.statements.firstIndex(where: { $0 === statement }) {
                index = statementIndex + 1
            } else {
                super.insert(statements: statements, after: statement)
                return
            }
        }
        self.statements.insert(contentsOf: statements, at: index)
        for statement in statements {
            statement.parent = self
            statement.assignParentReferences()
        }
    }

    override func remove(statement: KotlinStatement) {
        statements = statements.filter { $0 !== statement }
    }

    /// Prevent this code block from using Kotlin's single-statement syntax.
    ///
    /// Useful for formatting or when adding `KotlinRawStatements` with code you know is disallowed in single-statement functions.
    var disallowSingleStatementAppend = false

    func isSingleStatementAppendable(mode: KotlinSingleStatementAppendMode) -> Bool {
        guard !isTryCatch && !disallowSingleStatementAppend && statements.count <= 1 else {
            return false
        }
        var statementCount = 0
        var hasDisallowed = false
        visit {
            if statementCount <= 1 && !hasDisallowed && $0 !== self {
                if let statement = $0 as? KotlinStatement {
                    statementCount += 1
                    // We can't support leading comments because we'll be on the same line as preceding code
                    if statement.extras?.leadingTrivia.isEmpty == false {
                        hasDisallowed = true
                    }
                    // We can't suport trailing comments if there may be trailing code (e.g. closure closing brace)
                    if mode == .closure && statement.extras?.trailingTrivia.isEmpty == false {
                        hasDisallowed = true
                    }
                    if let appendable = statement as? KotlinSingleStatementAppendable {
                        if !appendable.isSingleStatementAppendable(mode: mode) {
                            hasDisallowed = true
                        }
                    } else if let vetoing = statement as? KotlinSingleStatementVetoing {
                        if !vetoing.isSingleStatementAppendable(mode: mode) {
                            hasDisallowed = true
                        }
                    } else {
                        hasDisallowed = true
                    }
                } else if let vetoing = $0 as? KotlinSingleStatementVetoing {
                    if !vetoing.isSingleStatementAppendable(mode: mode) {
                        hasDisallowed = true
                    }
                }
            }
            return statementCount <= 1 && !hasDisallowed ? .recurse(nil) : .skip
        }
        return statementCount <= 1 && !hasDisallowed
    }

    func appendAsSingleStatement(to output: OutputGenerator, indentation: Indentation, mode: KotlinSingleStatementAppendMode) {
        if statements.isEmpty {
            if mode == .function || mode == .case {
                output.append("Unit")
            }
        } else if let appendable = statements[0] as? KotlinSingleStatementAppendable {
            output.append(statements[0], indentation: indentation) {
                appendable.appendAsSingleStatement(to: $0, indentation: indentation, mode: mode)
            }
        } else {
            assert(false)
            output.append(statements[0], indentation: 0)
        }
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if deferCount == 1 {
            output.append(indentation).append("var deferaction_\(deferVariableSuffix): (() -> Unit)? = null\n")
        } else if deferCount > 0 {
            output.append(indentation).append("val deferactions_\(deferVariableSuffix): MutableList<() -> Unit> = mutableListOf()\n")
        }
        var statementIndentation = indentation
        if isTryCatch {
            output.append(indentation).append("try {\n")
            statementIndentation = statementIndentation.inc()
        }

        output.append(statements, indentation: statementIndentation)

        let hasFinally = deferCount > 0 || _syntheticFinally != nil
        for (index, kcatch) in catches.enumerated() {
            appendCatch(kcatch, to: output, indentation: indentation)
            if !hasFinally && index == catches.count - 1 {
                output.append(indentation).append("}\n")
            }
        }

        if hasFinally {
            output.append(indentation).append("} finally {\n")
            if let _syntheticFinally {
                output.append(statementIndentation).append(_syntheticFinally).append("\n")
            }
            if deferCount == 1 {
                output.append(statementIndentation).append("deferaction_\(deferVariableSuffix)?.invoke()\n")
            } else if deferCount > 0 {
                output.append(statementIndentation).append("deferactions_\(deferVariableSuffix).asReversed().forEach { it.invoke() }\n")
            }
            output.append(indentation).append("}\n")
        }
    }

    func appendDefer(_ body: KotlinCodeBlock, to output: OutputGenerator, indentation: Indentation) {
        if deferCount == 1 {
            output.append(indentation).append("deferaction_\(deferVariableSuffix) = {\n")
            output.append(body, indentation: indentation.inc())
            output.append(indentation).append("}\n")
        } else {
            output.append(indentation).append("deferactions_\(deferVariableSuffix).add {\n")
            output.append(body, indentation: indentation.inc())
            output.append(indentation).append("}\n")
        }
    }

    private func appendCatch(_ kcatch: KotlinCase, to output: OutputGenerator, indentation: Indentation) {
        let bodyIndentation = indentation.inc()
        if kcatch.patterns.isEmpty {
            output.append(indentation).append("} catch (error: Throwable) {\n")
            appendCatchBody(kcatch, addingError: "error", to: output, indentation: bodyIndentation)
        } else {
            for pattern in kcatch.patterns {
                output.append(indentation).append("} catch (")
                if let binaryOperator = pattern as? KotlinBinaryOperator, binaryOperator.op.precedence == .cast {
                    output.append(binaryOperator.lhs, indentation: indentation).append(": ").append(binaryOperator.rhs, indentation: indentation)
                } else {
                    // We should have already messaged about this. Output the incorrect code to break compilation
                    output.append(pattern, indentation: indentation)
                }
                output.append(indentation).append(") {\n")
                appendCatchBody(kcatch, to: output, indentation: bodyIndentation)
            }
        }
    }

    private func appendCatchBody(_ kcatch: KotlinCase, addingError: String? = nil, to output: OutputGenerator, indentation: Indentation) {
        // Handle 'catch var error'-type catches where there are no patterns; our default 'error' identifier may be used by the developer
        var errorBindingIndex: Int? = nil
        if let addingError {
            errorBindingIndex = kcatch.caseBindingVariables.firstIndex(where: { $0.names == [addingError] })
            let isLet = errorBindingIndex == nil || kcatch.caseBindingVariables[errorBindingIndex!].isLet
            output.append(indentation).append("@Suppress(\"NAME_SHADOWING\") \(isLet ? "val" : "var") error = error.aserror()\n")
        }
        for (index, bindingVariable) in kcatch.caseBindingVariables.enumerated() {
            guard index != errorBindingIndex else {
                continue
            }
            output.append(indentation)
            bindingVariable.append(to: output, indentation: indentation)
            output.append("\n")
        }
        output.append(kcatch.body, indentation: indentation)
    }
}

class KotlinContinue: KotlinStatement {
    var label: String?

    init(statement: Continue) {
        self.label = statement.label
        super.init(type: .continue, statement: statement)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation).append("continue")
        if let label {
            output.append("@\(label)")
        }
        output.append("\n")
    }
}

class KotlinDefer: KotlinStatement {
    var body: KotlinCodeBlock
    weak var codeBlock: KotlinCodeBlock?

    static func translate(statement: Defer, translator: KotlinTranslator) -> KotlinDefer {
        let kbody = KotlinCodeBlock.translate(statement: statement.body, translator: translator)
        return KotlinDefer(statement: statement, body: kbody)
    }

    private init(statement: Defer, body: KotlinCodeBlock) {
        self.body = body
        super.init(type: .defer, statement: statement)
    }

    override var children: [KotlinSyntaxNode] {
        return [body]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        codeBlock?.appendDefer(body, to: output, indentation: indentation)
    }
}

class KotlinEmpty: KotlinStatement, KotlinMemberDeclaration {
    init(statement: Empty) {
        super.init(type: .empty, statement: statement)
    }

    var extends: (TypeSignature, KotlinCompanionType, Generics)?
    let isStatic = false
    var visibility: Modifiers.Visibility = .private
}

class KotlinForLoop: KotlinStatement {
    var identifierPatterns: [IdentifierPattern]
    var declaredType: TypeSignature = .none
    var sequence: KotlinExpression
    var whereGuard: KotlinExpression?
    var isNonNilMatch = false
    var body: KotlinCodeBlock

    static func translate(statement: ForLoop, translator: KotlinTranslator) -> KotlinForLoop {
        var ksequence = translator.translateExpression(statement.sequence)
        if statement.isAwait {
            ksequence = KotlinAwait(target: ksequence, source: translator.syntaxTree.source)
        }
        let kbody = KotlinCodeBlock.translate(statement: statement.body, translator: translator)
        let kstatement = KotlinForLoop(statement: statement, sequence: ksequence, body: kbody)
        kstatement.declaredType = statement.declaredType.resolvingSelf(in: statement)
        kstatement.isNonNilMatch = statement.isNonNilMatch
        if let whereGuard = statement.whereGuard {
            kstatement.whereGuard = translator.translateExpression(whereGuard)
        }
        return kstatement
    }

    private init(statement: ForLoop, sequence: KotlinExpression, body: KotlinCodeBlock) {
        self.identifierPatterns = statement.identifierPatterns
        self.sequence = sequence
        self.body = body
        super.init(type: .forLoop, statement: statement)
    }

    override var children: [KotlinSyntaxNode] {
        var children: [KotlinSyntaxNode] = [sequence]
        if let whereGuard {
            children.append(whereGuard)
        }
        children.append(body)
        return children
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation).append("for (")
        // Append _0 to any vars so that we can re-declare them with their original names in the loop body
        let identifierNames = identifierPatterns.map {
            return $0.name != nil && $0.isVar ? "\($0.name!)_0" : $0.name
        }
        // Kotlin does not allow a wildcard loop var
        if identifierNames.count == 1 && identifierNames[0] == nil {
            output.append("unusedbinding")
        } else {
            if identifierNames.count > 1 {
                output.append("(")
            }
            output.append(identifierNames.map { $0 ?? "_" }.joined(separator: ", "))
            if identifierNames.count > 1 {
                output.append(")")
            }
        }
        output.append(" in ")
        output.append(sequence.sref(), indentation: indentation)
        output.append(") {\n")

        // Re-declare vars
        let bodyIndentation = indentation.inc()
        for identifierPattern in identifierPatterns {
            guard let name = identifierPattern.name else {
                continue
            }
            if identifierPattern.isVar {
                output.append(bodyIndentation).append("var ").append(name).append(" = ").append("\(name)_0\n")
            }
            if isNonNilMatch {
                output.append(bodyIndentation).append("if (\(name) == null) {\n")
                output.append(bodyIndentation.inc()).append("continue\n")
                output.append(bodyIndentation).append("}\n")
            }
        }

        // Check where condition
        if let whereGuard {
            output.append(bodyIndentation).append("if (")
            output.append(whereGuard.logicalNegated(), indentation: bodyIndentation)
            output.append(") {\n")
            output.append(bodyIndentation.inc()).append("continue\n")
            output.append(bodyIndentation).append("}\n")
        }

        output.append(body, indentation: bodyIndentation)
        output.append(indentation).append("}\n")
    }
}

class KotlinLabeledStatement: KotlinStatement {
    var label: String
    var target: KotlinStatement

    static func translate(statement: LabeledStatement, translator: KotlinTranslator) -> KotlinLabeledStatement {
        let ktarget = translator.translateStatement(statement.target).first ?? KotlinMessageStatement(message: .kotlinUntranslatable(statement, source: translator.syntaxTree.source), statement: statement)
        return KotlinLabeledStatement(statement: statement, target: ktarget)
    }

    private init(statement: LabeledStatement, target: KotlinStatement) {
        self.label = statement.label
        self.target = target
        super.init(type: .labeledStatement, statement: statement)
    }

    override var children: [KotlinSyntaxNode] {
        return [target]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation).append(label).append("@\n")
        output.append(target, indentation: indentation)
    }
}

class KotlinReturn: KotlinExpressionStatement {
    var label: String? = nil

    static func translate(statement: Return, translator: KotlinTranslator) -> KotlinExpressionStatement {
        let kstatement = KotlinReturn(statement: statement)
        if let expression = statement.expression {
            kstatement.expression = translator.translateExpression(expression)
        }
        return kstatement
    }

    override init(expression: KotlinExpression?) {
        super.init(type: .return, sourceFile: expression?.sourceFile, sourceRange: expression?.sourceRange)
        self.expression = expression
    }

    private init(statement: Return) {
        super.init(type: .return, statement: statement)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation)
        appendAsSingleStatement(to: output, indentation: indentation, mode: .closure)
        output.append("\n")
    }

    override func appendAsSingleStatement(to output: OutputGenerator, indentation: Indentation, mode: KotlinSingleStatementAppendMode) {
        if mode == .function {
            if let expression {
                output.append(expression, indentation: indentation)
            } else {
                output.append("Unit")
            }
        } else {
            output.append("return")
            if let label {
                output.append("@\(label)")
            }
            if let expression {
                output.append(" ").append(expression, indentation: indentation)
            }
        }
    }
}

class KotlinThrow: KotlinStatement {
    var error: KotlinExpression
    var errorIsThrowable = false

    static func translate(statement: Throw, translator: KotlinTranslator) -> KotlinThrow {
        let kerror = translator.translateExpression(statement.error)
        let kstatement = KotlinThrow(statement: statement, error: kerror)
        if let errorDeclarationType = translator.codebaseInfo?.declarationType(forNamed: statement.error.inferredType)?.type {
            kstatement.errorIsThrowable = errorDeclarationType != .protocolDeclaration
        }
        return kstatement
    }

    private init(statement: Throw, error: KotlinExpression) {
        self.error = error
        super.init(type: .throw, statement: statement)
    }

    override var children: [KotlinSyntaxNode] {
        return [error]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation).append("throw ")
        if !errorIsThrowable && error.isCompoundExpression {
            output.append("(")
        }
        output.append(error, indentation: indentation)
        if !errorIsThrowable {
            if error.isCompoundExpression {
                output.append(")")
            }
            output.append(" as Throwable")
        }
        output.append("\n")
    }
}

class KotlinTryCatch: KotlinStatement {
    var body: KotlinCodeBlock

    static func translate(statement: DoCatch, translator: KotlinTranslator) -> KotlinTryCatch {
        let matchOn = KotlinIdentifier(name: "error")
        matchOn.isLocalOrSelfIdentifier = true
        var kcatches: [KotlinCase] = []
        var messages: [Message] = []
        var caseTargetVariable: KotlinTargetVariable? = nil
        for catchCase in statement.catches {
            // Every enum that conforms to Error is translated to sealed classes, so we pass isSealedClassesEnum: true
            // here even without knowing the enum class and consulting codebase info
            var (kcatch, catchMessages) = KotlinCase.translate(expression: catchCase, matchingOn: matchOn, isSealedClassesEnum: true, caseTargetVariable: &caseTargetVariable, translator: translator)
            let promotedBindingIdentifier = promotedBindingIdentifier(from: &kcatch)
            for pattern in kcatch.patterns {
                if let binaryOperator = pattern as? KotlinBinaryOperator, binaryOperator.op.precedence == .cast {
                    if let promotedBindingIdentifier {
                        binaryOperator.lhs = KotlinIdentifier(name: promotedBindingIdentifier)
                    }
                } else {
                    messages.append(.kotlinCatchCaseCast(pattern, source: translator.syntaxTree.source))
                }
            }
            kcatches.append(kcatch)
            messages += catchMessages
        }
        let kbody = KotlinCodeBlock.translate(statement: statement.body, translator: translator)
        kbody.catches = kcatches

        let kexpression = KotlinTryCatch(statement: statement, body: kbody)
        kexpression.messages += messages
        return kexpression
    }

    private static func promotedBindingIdentifier(from kcatch: inout KotlinCase) -> String? {
        guard !kcatch.patterns.isEmpty else {
            return nil
        }
        // 'catch let e as Type' will generate a pattern of the form 'error is Type' and a binding 'e = error'. We can simplify
        // to just 'e is Type', which will translate to 'catch (e: Type)'
        guard let caseBindingVariable = kcatch.caseBindingVariables.first, caseBindingVariable.isLet, caseBindingVariable.names.count == 1 else {
            return nil
        }
        guard (caseBindingVariable.value as? KotlinIdentifier)?.name == "error" else {
            return nil
        }
        kcatch.caseBindingVariables = Array(kcatch.caseBindingVariables.dropFirst())
        return caseBindingVariable.names[0]
    }

    private init(statement: DoCatch, body: KotlinCodeBlock) {
        self.body = body
        super.init(type: .tryCatch, statement: statement)
    }

    override var children: [KotlinSyntaxNode] {
        return [body]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if body.isTryCatch {
            output.append(body, indentation: indentation)
        } else {
            output.append(indentation).append("run {\n")
            output.append(body, indentation: indentation.inc())
            output.append(indentation).append("}\n")
        }
    }
}

class KotlinWhileLoop: KotlinStatement {
    var conditions: [KotlinExpression]
    var caseBindingVariables: [KotlinBindingVariable]
    var guardStatement: KotlinStatement?
    var body: KotlinCodeBlock
    var isDoWhile = false

    static func translate(statement: WhileLoop, translator: KotlinTranslator) -> KotlinWhileLoop {
        let kstatement: KotlinWhileLoop
        let kbody = KotlinCodeBlock.translate(statement: statement.body, translator: translator)
        if let (kconditions, caseBindingVariables) = translate(conditions: statement.conditions, translator: translator) {
            kstatement = KotlinWhileLoop(statement: statement, conditions: kconditions, caseBindingVariables: caseBindingVariables, body: kbody)
        } else {
            let guardStatement = KotlinIf.translateAsLoopGuard(statement: statement, translator: translator)
            kstatement = KotlinWhileLoop(statement: statement, guardStatement: guardStatement, body: kbody)
        }
        kstatement.isDoWhile = statement.isRepeatWhile
        return kstatement
    }

    private static func translate(conditions: [Expression], translator: KotlinTranslator) -> ([KotlinExpression], [KotlinBindingVariable])? {
        var kconditions: [KotlinExpression] = []
        var caseBindingVariables: [KotlinBindingVariable] = []
        for condition in conditions {
            if let optionalBinding = condition as? OptionalBinding {
                let kbinding = KotlinOptionalBinding.translate(expression: optionalBinding, translator: translator)
                if kbinding.bindingVariable != nil {
                    return nil
                }
                kconditions.append(kbinding.condition)
            } else if let matchingCase = condition as? MatchingCase {
                let kcase = KotlinMatchingCase.translate(expression: matchingCase, translator: translator)
                if kcase.targetVariable != nil {
                    return nil
                }
                kconditions.append(kcase.condition)
                caseBindingVariables += kcase.bindingVariables
            } else {
                kconditions.append(translator.translateExpression(condition))
            }
        }
        return (kconditions, caseBindingVariables)
    }

    private init(statement: WhileLoop, conditions: [KotlinExpression], caseBindingVariables: [KotlinBindingVariable], body: KotlinCodeBlock) {
        self.conditions = conditions
        self.caseBindingVariables = caseBindingVariables
        self.body = body
        super.init(type: .whileLoop, statement: statement)
    }

    private init(statement: WhileLoop, guardStatement: KotlinStatement, body: KotlinCodeBlock) {
        self.conditions = []
        self.caseBindingVariables = []
        self.guardStatement = guardStatement
        self.body = body
        super.init(type: .whileLoop, statement: statement)
    }

    override var children: [KotlinSyntaxNode] {
        var children: [KotlinSyntaxNode] = conditions
        if let guardStatement {
            children.append(guardStatement)
        }
        children.append(body)
        return children
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        let bodyIndentation = indentation.inc()
        if isDoWhile {
            output.append(indentation).append("do {\n")
            output.append(body, indentation: bodyIndentation)
            if let guardStatement {
                output.append(guardStatement, indentation: bodyIndentation)
            }
            output.append(indentation).append("} while (")
            if guardStatement != nil {
                output.append("true")
            } else {
                conditions.appendAsLogicalConditions(to: output, indentation: indentation)
            }
            output.append(")\n")
        } else {
            output.append(indentation).append("while (")
            if guardStatement != nil {
                output.append("true")
            } else {
                conditions.appendAsLogicalConditions(to: output, indentation: indentation)
            }
            output.append(") {\n")
            for caseBindingVariable in caseBindingVariables {
                output.append(bodyIndentation)
                caseBindingVariable.append(to: output, indentation: bodyIndentation)
                output.append("\n")
            }
            if let guardStatement {
                output.append(guardStatement, indentation: bodyIndentation)
            }
            output.append(body, indentation: bodyIndentation)
            output.append(indentation).append("}\n")
        }
    }
}

// MARK: - Declarations

class KotlinClassDeclaration: KotlinStatement {
    var name: String
    var signature: TypeSignature
    var inherits: [TypeSignature] = []
    var companionType: KotlinCompanionType? = nil
    var companionInherits: [KotlinCompanionType] = []
    var companionInits: [TypeSignature] = []
    var superclassCall: String?
    var annotations: [String] = []
    var attributes = Attributes()
    var modifiers = Modifiers()
    var generics = Generics()
    var declarationType: StatementType
    var members: [KotlinStatement] = []
    var movedExtensionImportModulePaths: [[String]] = []
    var suppressSideEffectsPropertyName: String?
    var enumInheritedRawValueType: TypeSignature {
        guard let inherits = inherits.first else {
            return .none
        }
        return inherits.isNumeric || inherits == .string ? inherits : .none
    }
    var isSealedClassesEnum: Bool {
        get {
            return forceSealedClassesEnum || members.contains { ($0 as? KotlinEnumCaseDeclaration)?.associatedValues.isEmpty == false }
        }
        set {
            forceSealedClassesEnum = newValue
        }
    }
    private var forceSealedClassesEnum = false
    var alwaysCreateNewSealedClassInstances = false
    var isGenerated = false

    static func translate(statement: TypeDeclaration, translator: KotlinTranslator) -> [KotlinStatement] {
        let kstatement = KotlinClassDeclaration(statement: statement)
        kstatement.inherits = statement.inherits
        kstatement.modifiers = statement.modifiers
        kstatement.generics = statement.generics.resolvingSelf(in: statement)
        if let owningTypeDeclaration = statement.parent?.owningTypeDeclaration, !owningTypeDeclaration.generics.isEmpty {
            kstatement.messages.append(.kotlinGenericTypeNested(statement, source: translator.syntaxTree.source))
        }
        kstatement.attributes = kstatement.processAttributes(statement.attributes, from: statement, translator: translator)

        let isFinal = statement.modifiers.isFinal || statement.type == .structDeclaration
        let partitioned = KotlinExtensionDeclaration.partition(members: statement.members, of: kstatement.signature, isFinal: isFinal)
        var extensionMembers = partitioned.extensionMembers
        var kmembers = partitioned.members.flatMap { translator.translateStatement($0) }
        if let codebaseInfo = translator.codebaseInfo {
            if let typeInfo = codebaseInfo.primaryTypeInfo(forNamed: statement.signature) {
                // Type info contains full resolved generics
                kstatement.signature = typeInfo.signature
                kstatement.inherits = typeInfo.inherits
                kstatement.generics = typeInfo.generics.resolvingSelf(in: statement)
            }

            // Move extensions of this type into the type itself rather than use Kotlin extension functions.
            // Kotlin extension functions act like static functions, which can lead to different behavior
            for (extInfo, extDeclaration, extImportModulePaths) in codebaseInfo.moveableExtensions(of: statement.signature, in: translator.syntaxTree) {
                kstatement.inherits += extInfo.inherits
                let partitioned = KotlinExtensionDeclaration.partition(members: extDeclaration.members, of: kstatement.signature, isFinal: isFinal)
                extensionMembers += partitioned.extensionMembers
                let kpartitionedMembers = partitioned.members.flatMap { translator.translateStatement($0) }
                kpartitionedMembers.first?.ensureLeadingNewlines(1)
                kmembers += kpartitionedMembers
                kstatement.movedExtensionImportModulePaths += extImportModulePaths
            }

            kstatement.companionType = codebaseInfo.companionType(of: statement.signature)
            var hasCompanionInherits = false
            kstatement.companionInherits = kstatement.inherits.compactMap {
                switch codebaseInfo.companionType(of: $0) {
                case .none, .object:
                    return nil
                case .class(let signature):
                    hasCompanionInherits = true
                    return .class(signature)
                case .interface(let signature):
                    hasCompanionInherits = true
                    return .interface(signature.constrainedTypeWithGenerics(kstatement.generics))
                }
            }
            // Any companion init has to be inherited, so save the additional work when possible
            if hasCompanionInherits {
                let (companionInits, messages) = codebaseInfo.companionInits(of: statement.signature, for: kstatement, source: translator.syntaxTree.source)
                kstatement.companionInits = companionInits
                kstatement.messages += messages
            }
        }
        kstatement.members = kmembers
        if statement.type == .enumDeclaration {
            kstatement.processEnumCaseDeclarations(messagesSource: translator.syntaxTree.source)
        }

        kstatement.inherits.forEach { $0.appendKotlinMessages(to: kstatement, source: translator.syntaxTree.source) }
        if kstatement.declarationType == .actorDeclaration && !kstatement.inherits.contains(where: { $0.isNamed("Actor", moduleName: "Swift") }) {
            kstatement.inherits.append(.named("Actor", []))
        }

        let kextensionMembers = KotlinExtensionDeclaration.translateExtensionMembers(extensionMembers, of: kstatement.signature, visibility: kstatement.modifiers.visibility, generics: kstatement.generics, declarationType: .classDeclaration, translator: translator)
        kextensionMembers.first?.ensureLeadingNewlines(1)
        return [kstatement] + kextensionMembers
    }

    init(name: String, signature: TypeSignature, declarationType: StatementType, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.name = name
        self.signature = signature
        self.declarationType = declarationType
        super.init(type: .classDeclaration, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(statement: TypeDeclaration) {
        self.name = statement.name
        self.signature = statement.signature
        self.declarationType = statement.type
        super.init(type: .classDeclaration, statement: statement)
    }

    /// Assign raw values and other attributes to enum case members.
    func processEnumCaseDeclarations(messagesSource: Source? = nil) {
        guard declarationType == .enumDeclaration else {
            return
        }

        let caseDeclarations = members.compactMap { $0 as? KotlinEnumCaseDeclaration }
        let rawValueType = enumInheritedRawValueType
        let isSealed = isSealedClassesEnum
        var lastRawValueInt = -1
        for (index, caseDeclaration) in caseDeclarations.enumerated() {
            if rawValueType != .none {
                if rawValueType.isNumeric {
                    if let rawValue = caseDeclaration.rawValue {
                        if let literal = rawValue as? KotlinNumericLiteral, let literalInt = Double(literal.literal).map({ Int($0) }) {
                            lastRawValueInt = literalInt
                        }
                    } else {
                        lastRawValueInt += 1
                        caseDeclaration.rawValue = KotlinNumericLiteral(literal: String(lastRawValueInt))
                    }
                } else if caseDeclaration.rawValue == nil {
                    caseDeclaration.rawValue = KotlinStringLiteral(literal: caseDeclaration.preEscapedName ?? caseDeclaration.name)
                }
            }
            caseDeclaration.isLastDeclaration = index == caseDeclarations.count - 1

            // Note that a transformer may force this enum into a sealed enum later, so we can only warn on the likelihood that
            // this will turn into an enum case and cause an error
            if let messagesSource, !isSealed && KotlinEnumCaseDeclaration.disallowedCaseNames.contains(caseDeclaration.preEscapedName ?? caseDeclaration.name) {
                caseDeclaration.messages.append(.kotlinEnumCaseName(caseDeclaration, source: messagesSource))
            }
        }
    }

    override var children: [KotlinSyntaxNode] {
        return members
    }

    override func insertDependencies(into dependencies: inout KotlinDependencies) {
        inherits.forEach { $0.insertDependencies(into: &dependencies) }
        generics.insertDependencies(into: &dependencies)
    }

    override func insert(statements: [KotlinStatement], after statement: KotlinStatement?) {
        var index = 0
        if let statement {
            if let statementIndex = members.firstIndex(where: { $0 === statement }) {
                index = statementIndex + 1
            } else {
                super.insert(statements: statements, after: statement)
                return
            }
        }
        members.insert(contentsOf: statements, at: index)
        for statement in statements {
            statement.parent = self
            statement.assignParentReferences()
        }
    }

    override func remove(statement: KotlinStatement) {
        members = members.filter { $0 !== statement }
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        let isSealedClassesEnum = isSealedClassesEnum
        if let declaration = extras?.declaration {
            output.append(indentation).append(declaration)
        } else {
            attributes.append(to: output, indentation: indentation)
            annotations.appendLines(to: output, indentation: indentation)
            output.append(indentation)
            switch modifiers.visibility {
            case .default, .internal:
                output.append("internal ")
                if declarationType == .classDeclaration && !modifiers.isFinal {
                    output.append("open ")
                }
            case .open:
                if declarationType == .classDeclaration {
                    output.append("open ")
                }
            case .public:
                if declarationType == .classDeclaration && !modifiers.isFinal {
                    output.append("open ")
                }
            case .private:
                output.append("private ")
                if declarationType == .classDeclaration && !modifiers.isFinal {
                    output.append("open ")
                }
            case .fileprivate:
                output.append(signature.baseType == .none ? "private " : "internal ")
                if declarationType == .classDeclaration && !modifiers.isFinal {
                    output.append("open ")
                }
            }

            if declarationType == .enumDeclaration {
                if isSealedClassesEnum {
                    output.append("sealed class ").append(name)
                } else {
                    output.append("enum class ").append(name)
                }
            } else {
                output.append("class ").append(name)
            }
            generics.append(to: output, indentation: indentation, modifier: isSealedClassesEnum ? "out" : nil)

            var inherits = inherits
            if enumInheritedRawValueType != .none {
                inherits = Array(inherits.dropFirst())
                // Add an unused parameter to disambiguate from the RawRepresentable constructor
                output.append("(override val rawValue: \(enumInheritedRawValueType.kotlin), @Suppress(\"UNUSED_PARAMETER\") unusedp: Nothing? = null)")
            }
            if !inherits.isEmpty {
                output.append(": ")
                if let superclassCall {
                    output.append(superclassCall)
                    inherits = Array(inherits.dropFirst())
                    if !inherits.isEmpty {
                        output.append(", ")
                    }
                }
                output.append(inherits.map({ $0.kotlin }).joined(separator: ", "))
            }
            generics.appendWhere(to: output, indentation: indentation)
        }
        output.append(" {\n")

        var staticMembers: [KotlinStatement] = []
        var enumCases: [KotlinEnumCaseDeclaration] = []
        var nonstaticMembers: [KotlinStatement] = []
        for member in members {
            if (member as? KotlinMemberDeclaration)?.isStatic == true {
                staticMembers.append(member)
            } else if let enumCaseDeclaration = member as? KotlinEnumCaseDeclaration {
                enumCases.append(enumCaseDeclaration)
            } else {
                nonstaticMembers.append(member)
            }
        }

        let memberIndentation = indentation.inc()
        if declarationType == .actorDeclaration {
            output.append(memberIndentation).append("override val isolatedContext = Actor.isolatedContext()\n")
        }
        enumCases.forEach { output.append($0, indentation: memberIndentation) }
        nonstaticMembers.forEach { output.append($0, indentation: memberIndentation) }

        if let suppressSideEffectsPropertyName {
            output.append("\n")
            output.append(memberIndentation).append("private var \(suppressSideEffectsPropertyName) = false\n")
        }

        let needsCompanion = !staticMembers.isEmpty || modifiers.visibility == .public || modifiers.visibility == .open || isSealedClassesEnum
        let effectiveCompanionType: KotlinCompanionType
        if let companionType {
            if case .none = companionType, needsCompanion {
                effectiveCompanionType = .object
            } else {
                effectiveCompanionType = companionType
            }
        } else if needsCompanion {
            effectiveCompanionType = .object
        } else {
            effectiveCompanionType = .none
        }
        appendCompanion(to: output, indentation: memberIndentation, type: effectiveCompanionType, staticMembers: staticMembers, enumCases: enumCases)
        output.append(indentation).append("}\n")
    }

    private func appendCompanion(to output: OutputGenerator, indentation: Indentation, type: KotlinCompanionType, staticMembers: [KotlinStatement], enumCases: [KotlinEnumCaseDeclaration]) {
        if case .none = type {
            return
        }
        output.append("\n")
        output.append(indentation)
        if case .class(let signature) = type {
            output.append("open class ").append(signature.unqualifiedName)
        } else {
            output.append("companion object")
        }
        for i in 0..<companionInherits.count {
            output.append(i == 0 ? ": " : ", ")
            if case .class(let signature) = companionInherits[i] {
                output.append(signature.kotlin).append("()")
            } else if case .interface(let signature) = companionInherits[i] {
                output.append(signature.kotlin)
            }
        }
        output.append(" {\n")
        let memberIndentation = indentation.inc()
        if isSealedClassesEnum {
            enumCases.forEach { $0.appendSealedClassFactory(to: output, forEnum: name, alwaysCreateNewInstances: alwaysCreateNewSealedClassInstances, indentation: memberIndentation) }
            if !staticMembers.isEmpty {
                output.append("\n")
            }
        }
        staticMembers.forEach { output.append($0, indentation: memberIndentation) }
        for i in 0..<companionInits.count {
            if i > 0 || isSealedClassesEnum || !staticMembers.isEmpty {
                output.append("\n")
            }
            let companionInit = companionInits[i]
            output.append(memberIndentation).append("override fun init(")
            appendParameters(of: companionInit, to: output, isFunctionCall: false)
            output.append("): \(signature.kotlin) {\n")
            output.append(memberIndentation.inc()).append("return \(name)(")
            appendParameters(of: companionInit, to: output, isFunctionCall: true)
            output.append(")\n")
            output.append(memberIndentation).append("}\n")
        }
        output.append(indentation).append("}\n")

        if case .class(let signature) = type {
            output.append(indentation).append("companion object: ").append(signature.unqualifiedName).append("()\n")
        }
    }

    private func appendParameters(of functionSignature: TypeSignature, to output: OutputGenerator, isFunctionCall: Bool) {
        let parameters = functionSignature.parameters
        for i in 0..<parameters.count {
            if i > 0 {
                output.append(", ")
            }
            if let label = parameters[i].label {
                output.append(label)
                if isFunctionCall {
                    output.append(" = ").append(label)
                }
            } else {
                output.append("p_\(i)")
            }
            if !isFunctionCall {
                output.append(": ").append(parameters[i].type.kotlin)
            }
        }
    }
}

class KotlinEnumCaseDeclaration: KotlinStatement {
    /// Names that aren't hard reserved words but cause errors as enum cases.
    static let disallowedCaseNames: Set<String> = ["segmented", "name", "ordinal"]

    var name: String
    var preEscapedName: String?
    var generics: Generics = Generics()
    var enumGenerics: Generics = Generics()
    var associatedValues: [Parameter<KotlinExpression>] = []
    var rawValue: KotlinExpression?
    var isLastDeclaration = false
    var members: [KotlinStatement] = []

    /// Return the name of the sealed class we create for the given enum case name in an enum with associated values.
    static func sealedClassName(for caseName: String) -> String {
        // de-quote the keyword if needed
        let cname = caseName.hasPrefix("`") && caseName.hasSuffix("`") ? caseName.dropFirst().dropLast().description : caseName
        // Always append "Case" to avoid conflicts with reserved names, e.g. case boolean -> Boolean
        if let first = cname.first, first.isLowercase {
            return first.uppercased() + cname.dropFirst() + "Case"
        }
        return cname + "Case"
    }

    /// Return the name of the sealed class we create for the given enum case name in an enum with associated values.
    static func sealedClassName(for enumCase: KotlinEnumCaseDeclaration) -> String {
        return sealedClassName(for: enumCase.preEscapedName ?? enumCase.name)
    }

    static func translate(statement: EnumCaseDeclaration, translator: KotlinTranslator) -> KotlinEnumCaseDeclaration {
        let kstatement = KotlinEnumCaseDeclaration(statement: statement)
        kstatement.associatedValues = statement.associatedValues.map { $0.translate(translator: translator) }
        kstatement.associatedValues.forEach { $0.declaredType.appendKotlinMessages(to: kstatement, source: translator.syntaxTree.source) }
        kstatement.rawValue = statement.rawValue.map { translator.translateExpression($0) }
        if let owningTypeDeclaration = statement.owningTypeDeclaration {
            let genericsEntries = owningTypeDeclaration.generics.resolvingSelf(in: statement).entries.map { entry in
                if kstatement.associatedValues.contains(where: { $0.declaredType.referencesType(entry.namedType) }) {
                    return entry
                } else {
                    return Generic(name: entry.name, whereEqual: .named("Nothing", []))
                }
            }
            kstatement.enumGenerics = Generics(entries: genericsEntries)
            kstatement.generics = kstatement.enumGenerics.filterWhereEqual()
        }
        let _ = kstatement.processAttributes(statement.attributes, from: statement, translator: translator)
        return kstatement
    }

    init(name: String, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.name = name
        super.init(type: .enumCaseDeclaration, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(statement: EnumCaseDeclaration) {
        self.name = statement.name
        super.init(type: .enumCaseDeclaration, statement: statement)
    }

    override func insertDependencies(into dependencies: inout KotlinDependencies) {
        generics.insertDependencies(into: &dependencies)
        associatedValues.forEach { $0.insertDependencies(into: &dependencies) }
    }

    override var children: [KotlinSyntaxNode] {
        var children: [KotlinSyntaxNode] = associatedValues.compactMap { $0.defaultValue }
        if let rawValue {
            children.append(rawValue)
        }
        return children + members
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        let owningClassDeclaration = parent as? KotlinClassDeclaration
        output.append(indentation)
        if let declaration = extras?.declaration {
            output.append(declaration)
        } else if let owningClassDeclaration = owningClassDeclaration, owningClassDeclaration.isSealedClassesEnum {
            output.append("class \(Self.sealedClassName(for: self))")
            generics.append(to: output, indentation: indentation)
            if !associatedValues.isEmpty {
                appendAssociatedValueArguments(to: output, asConstructor: true, indentation: indentation)
            }
            output.append(": \(owningClassDeclaration.name)")
            enumGenerics.append(to: output, indentation: indentation)
            if let rawValue {
                output.append("(").append(rawValue, indentation: indentation).append(")")
            } else {
                output.append("()")
            }
            generics.appendWhere(to: output, indentation: indentation)
            output.append(" {\n")
            var hasLabeledVals = false
            for (index, value) in associatedValues.enumerated() {
                if let label = value.externalLabel {
                    hasLabeledVals = true
                    output.append(indentation.inc()).append("val \(label) = associated\(index)\n")
                }
            }
            if !members.isEmpty {
                if hasLabeledVals {
                    output.append("\n")
                }
                members.forEach { output.append($0, indentation: indentation.inc()) }
            }
            output.append(indentation).append("}\n")
        } else {
            output.append(name)
            if let rawValue {
                if let rawValueType = owningClassDeclaration?.enumInheritedRawValueType, rawValueType == .float || rawValueType.isUnsigned {
                    // Explicitly cast to expected type to avoid Kotlin errors
                    output.append("(").append(rawValueType.kotlin).append("(").append(rawValue, indentation: indentation).append("))")
                } else {
                    output.append("(").append(rawValue, indentation: indentation).append(")")
                }
            }
            if isLastDeclaration {
                output.append(";\n")
            } else {
                output.append(",\n")
            }
        }
    }

    func appendSealedClassFactory(to output: OutputGenerator, forEnum: String, alwaysCreateNewInstances: Bool, indentation: Indentation) {
        output.append(indentation)
        if associatedValues.isEmpty {
            output.append("val \(name): \(forEnum)")
            enumGenerics.append(to: output, indentation: indentation)
            if alwaysCreateNewInstances {
                output.append("\n")
                let getterIndentation = indentation.inc()
                output.append(getterIndentation).append("get() = \(Self.sealedClassName(for: self))")
                generics.appendWhere(to: output, indentation: getterIndentation)
                output.append("()\n")
            } else {
                output.append(" = \(Self.sealedClassName(for: self))")
                generics.appendWhere(to: output, indentation: indentation)
                output.append("()\n")
            }
        } else {
            output.append("fun ")
            if !generics.isEmpty {
                generics.append(to: output, indentation: indentation)
                output.append(" ")
            }
            output.append(name)
            appendAssociatedValueArguments(to: output, asConstructor: false, indentation: indentation)
            output.append(": \(forEnum)")
            enumGenerics.append(to: output, indentation: indentation)
            generics.appendWhere(to: output, indentation: indentation)
            output.append(" = ")
            output.append("\(Self.sealedClassName(for: self))(")
            for (index, value) in associatedValues.enumerated() {
                if let label = value.externalLabel {
                    output.append(label)
                } else {
                    output.append("associated\(index)")
                }
                if index != associatedValues.count - 1 {
                    output.append(", ")
                }
            }
            output.append(")\n")
        }
    }

    private func appendAssociatedValueArguments(to output: OutputGenerator, asConstructor: Bool, indentation: Indentation) {
        output.append("(")
        for (index, value) in associatedValues.enumerated() {
            if !asConstructor, let label = value.externalLabel {
                output.append(label).append(": ")
            } else {
                if asConstructor {
                    output.append("val ")
                }
                output.append("associated\(index): ")
            }
            output.append(value.declaredType.or(.any).kotlin)
            if !asConstructor, let defaultValue = value.defaultValue {
                output.append(" = ").append(defaultValue, indentation: indentation)
            }
            if index != associatedValues.count - 1 {
                output.append(", ")
            }
        }
        output.append(")")
    }
}

struct KotlinExtensionDeclaration {
    static func translate(statement: ExtensionDeclaration, translator: KotlinTranslator) -> [KotlinStatement] {
        var kstatements: [KotlinStatement] = []
        let declarationType = translator.codebaseInfo?.declarationType(forNamed: statement.extends)
        if declarationType?.type == .protocolDeclaration {
            for member in statement.members {
                if member.type == .initDeclaration {
                    kstatements.append(KotlinMessageStatement(message: .kotlinExtensionAddConstructorProtocolMember(member, source: translator.syntaxTree.source), statement: member))
                }
            }
        }

        // If the extension can't move into its extended type or is on a type outside this module, use Kotlin extension
        // functions. Otherwise do not translate the extension - instead we'll move its members into the extended type
        let isInSameFile = statement.isInSameFileAsExtendedType
        var placement = KotlinExtensionPlacement()
        placement.canMove = statement.canMoveIntoExtendedType
        placement.visibilityAllowsMove = isInSameFile || statement.visibilityAllowsMoveIntoExtendedType
        placement.isInModule = translator.codebaseInfo == nil ? nil : declarationType?.isInModule == true
        guard !placement.canMove || !placement.visibilityAllowsMove || placement.isInModule != true else {
            if !isInSameFile && mayUseFilePrivateAPI(statement: statement, in: translator.syntaxTree) {
                let message: Message = .kotlinExtensionUsingFileprivateAPI(statement, source: translator.syntaxTree.source)
                return kstatements + [KotlinMessageStatement(message: message, statement: statement)]
            } else {
                return kstatements
            }
        }

        if !statement.inherits.isEmpty, let message = Message.kotlinExtensionAddProtocols(statement, extensionPlacement: placement, source: translator.syntaxTree.source) {
            kstatements.append(KotlinMessageStatement(message: message, statement: statement))
        }
        var extends = statement.extends
        var generics = statement.generics.resolvingSelf(in: statement)
        var visibility = statement.modifiers.visibility
        if let extendedTypeInfo = translator.codebaseInfo?.primaryTypeInfo(forNamed: statement.extends) {
            // Set the extended type to match its primary type and put the complete set of constraints into the generics object
            extends = extendedTypeInfo.signature
            generics = extendedTypeInfo.generics.merge(extension: statement.extends, generics: statement.generics).resolvingSelf(in: statement)
            visibility = extendedTypeInfo.modifiers.visibility
        }
        let kextensionMembers = translateExtensionMembers(statement.members, of: extends, visibility: visibility, generics: generics, declarationType: declarationType?.type, translator: translator, extensionPlacement: placement)
        kextensionMembers.first?.ensureLeadingNewlines(1)
        return kstatements + kextensionMembers
    }

    static func translateExtensionMembers(_ members: [Statement], of extends: TypeSignature, visibility: Modifiers.Visibility, generics: Generics, declarationType: StatementType?, translator: KotlinTranslator, extensionPlacement: KotlinExtensionPlacement? = nil) -> [KotlinStatement] {
        var companionType: KotlinCompanionType? = nil
        var canAddStaticMembers: Bool? = nil
        if let extensionPlacement, !extensionPlacement.canMove {
            canAddStaticMembers = declarationType != .protocolDeclaration || extensionPlacement.isInModule != false || translator.codebaseInfo == nil
            if canAddStaticMembers == false {
                companionType = translator.codebaseInfo?.companionType(of: extends) ?? .object
                if case .interface = companionType {
                    canAddStaticMembers = true
                }
            }
        }

        var kstatements: [KotlinStatement] = []
        for member in members {
            if let extensionPlacement, !extensionPlacement.canMove {
                // Check that an extension that will be implemented as extension functions because it has generic constraints, etc is not
                // attempting to override member functions. Kotlin extension functions can never override members
                if let variableDeclaration = member as? VariableDeclaration {
                    if variableDeclaration.modifiers.isStatic && canAddStaticMembers == false {
                        kstatements.append(KotlinMessageStatement(message: .kotlinExtensionAddStaticProtocolMember(member, source: translator.syntaxTree.source), statement: member))
                    } else if translator.codebaseInfo?.isImplementingKotlinMember(declaration: variableDeclaration, inExtension: extends, withConstrainingGenerics: generics) == true, let message = Message.kotlinExtensionImplementMember(member, extensionPlacement: extensionPlacement, source: translator.syntaxTree.source) {
                        kstatements.append(KotlinMessageStatement(message: message, statement: member))
                    }
                } else if let functionDeclaration = member as? FunctionDeclaration {
                    if functionDeclaration.modifiers.isStatic && canAddStaticMembers == false {
                        kstatements.append(KotlinMessageStatement(message: .kotlinExtensionAddStaticProtocolMember(member, source: translator.syntaxTree.source), statement: member))
                    } else if translator.codebaseInfo?.isImplementingKotlinMember(declaration: functionDeclaration, inExtension: extends, withConstrainingGenerics: generics) == true, let message = Message.kotlinExtensionImplementMember(member, extensionPlacement: extensionPlacement, source: translator.syntaxTree.source) {
                        kstatements.append(KotlinMessageStatement(message: message, statement: member))
                    }
                }
            }
            
            for kmember in translator.translateStatement(member) {
                guard let memberDeclaration = kmember as? KotlinMemberDeclaration else {
                    if let message = Message.kotlinExtensionUnsupportedMember(member, extensionPlacement: extensionPlacement, source: translator.syntaxTree.source) {
                        kstatements.append(KotlinMessageStatement(message: message, statement: member))
                    }
                    continue
                }
                guard kmember.type != .constructorDeclaration else {
                    if let message = Message.kotlinExtensionAddConstructors(member, extensionPlacement: extensionPlacement, source: translator.syntaxTree.source) {
                        kstatements.append(KotlinMessageStatement(message: message, statement: member))
                    }
                    continue
                }

                // Reduce the visibility of the extended member to that of the extended type
                if visibility < memberDeclaration.visibility {
                    memberDeclaration.visibility = visibility
                }

                var extendsGenerics = generics
                if let kfunctionDeclaration = kmember as? KotlinFunctionDeclaration {
                    extendsGenerics = extendsGenerics.merge(overrides: kfunctionDeclaration.generics, addNew: false)
                }
                if companionType == nil {
                    companionType = translator.codebaseInfo?.companionType(of: extends) ?? .object
                }
                memberDeclaration.extends = (extends, memberDeclaration.isStatic ? companionType! : .none, extendsGenerics)
                kstatements.append(kmember)
            }
        }
        return kstatements
    }

    /// Partition a set of class or interface members into those that can move into the class or interface and those that must be implemented as extension members.
    static func partition(members: [Statement], of signature: TypeSignature, isFinal: Bool) -> (members: [Statement], extensionMembers: [Statement]) {
        var extensionMembers: [Statement] = []
        var otherMembers: [Statement] = []
        for member in members {
            var extensionFunction: FunctionDeclaration? = nil
            if let functionDeclaration = member as? FunctionDeclaration, !functionDeclaration.generics.isEmpty {
                // We have to use extension functions for reified generics of a virtual type
                if !isFinal && functionDeclaration.attributes.contains(.inlineAlways) {
                    extensionFunction = functionDeclaration
                } else {
                    // We have to use extension functions when there are any constraints on the owning type's generics
                    for entry in functionDeclaration.generics.entries {
                        if entry.whereEqual != nil || !entry.inherits.isEmpty, signature.generics.contains(where: { $0.isNamed(entry.name) }) {
                            extensionFunction = functionDeclaration
                            break
                        }
                    }
                }
            }
            if let extensionFunction {
                extensionMembers.append(extensionFunction)
            } else {
                otherMembers.append(member)
            }
        }
        return (otherMembers, extensionMembers)
    }

    private static func mayUseFilePrivateAPI(statement: ExtensionDeclaration, in syntaxTree: SyntaxTree) -> Bool {
        var hasFilePrivateAPI = false
        syntaxTree.root.visit { node in
            guard !hasFilePrivateAPI, node !== statement else {
                return .skip
            }
            let modifiers: Modifiers
            let skip: Bool
            if let typeDeclaration = node as? TypeDeclaration {
                modifiers = typeDeclaration.modifiers
                skip = false // Look for nested API
            } else if let variableDeclaration = node as? VariableDeclaration {
                modifiers = variableDeclaration.modifiers
                skip = true
            } else if let functionDeclaration = node as? FunctionDeclaration {
                modifiers = functionDeclaration.modifiers
                skip = true
            } else {
                return .recurse(nil)
            }
            // Anything using fileprivate visibility or any non-member using private visibility is effectively file-private
            hasFilePrivateAPI = modifiers.visibility == .fileprivate || (modifiers.visibility == .private && node.parent?.owningTypeDeclaration == nil)
            return hasFilePrivateAPI || skip ? .skip : .recurse(nil)
        }
        return hasFilePrivateAPI
    }
}

/// - Seealso: ``KotlinConstructorTransformer``
class KotlinFunctionDeclaration: KotlinStatement, KotlinMemberDeclaration {
    var name: String
    var returnType: TypeSignature = .void
    var parameters: [Parameter<KotlinExpression>] = []
    var isOpen = false
    var role: Role = .member
    var isOptionalInit = false
    var annotations: [String] = []
    var modifiers = Modifiers()
    var attributes = Attributes()
    var apiFlags: APIFlags = []
    var isActorIsolated = false
    var generics = Generics()
    var convertedGenerics: Generics? = nil
    var body: KotlinCodeBlock?
    var delegatingConstructorCall: KotlinExpression?
    var mutationFunctionNames: (willMutate: String, didMutate: String)?
    var disambiguatingParameterCount = 0
    var hasAsyncExplicitReturn = false
    var suppressSideEffects = false
    var isGenerated = false
    var functionType: TypeSignature {
        return attributes.apply(toFunction: .function(parameters.map(\.signature), returnType, apiFlags, nil))
    }
    var functionGenerics: Generics {
        get {
            if let convertedGenerics {
                return convertedGenerics
            }
            guard let extendsGenerics = extends?.2, !extendsGenerics.isEmpty else {
                return generics
            }
            guard !generics.isEmpty else {
                return extendsGenerics
            }
            return extendsGenerics.merge(overrides: generics, addNew: true)
        }
    }
    var isEqualImplementation: Bool {
        return name == "==" && modifiers.isStatic && parameters.count == 2
    }
    var isHashImplementation: Bool {
        return name == "hash" && !modifiers.isStatic && parameters.count == 1 && parameters[0].isInOut && parameters[0].declaredType.isNamed("Hasher", moduleName: "Swift", generics: [])
    }
    var isLessThanImplementation: Bool {
        return name == "<" && modifiers.isStatic && parameters.count == 2
    }

    enum Role {
        case local
        case global
        case member
        case `operator`
    }

    // KotlinMemberDeclaration
    var extends: (TypeSignature, KotlinCompanionType, Generics)? {
        didSet {
            if extends != nil {
                isOpen = false
            }
        }
    }
    var isStatic: Bool {
        return modifiers.isStatic && !isEqualImplementation && !isLessThanImplementation
    }
    var visibility: Modifiers.Visibility {
        get {
            return modifiers.visibility
        }
        set {
            modifiers.visibility = newValue
        }
    }
    var isExternal: Bool {
        extras?.isExternal == true
    }

    static func translate(statement: FunctionDeclaration, translator: KotlinTranslator) -> KotlinFunctionDeclaration {
        let kstatement = KotlinFunctionDeclaration(statement: statement)
        kstatement.isOptionalInit = statement.isOptionalInit
        kstatement.modifiers = statement.modifiers
        kstatement.generics = statement.generics.resolvingSelf(in: statement)
        kstatement.returnType = statement.returnType.resolvingSelf(in: statement)
        kstatement.parameters = statement.parameters.map { $0.resolvingSelf(in: statement).translate(translator: translator) }
        kstatement.attributes = kstatement.processAttributes(statement.attributes, from: statement, translator: translator)
        kstatement.apiFlags = statement.functionType.apiFlags
        kstatement.isActorIsolated = statement.asyncBehavior == .actor

        if !translateMemberInfo(declaration: kstatement, from: statement, modifiers: statement.modifiers, translator: translator) {
            if statement.parent?.owningFunctionDeclaration != nil {
                kstatement.role = .local
            } else if statement.isGlobal {
                kstatement.role = .global
            }
        }
        translateBody(declaration: kstatement, from: statement, body: statement.body, returnType: statement.returnType, asyncBehavior: statement.asyncBehavior, translator: translator)

        // Warnings and fixups
        if let firstCharacter = kstatement.name.first, firstCharacter != "_" && firstCharacter != "$" && firstCharacter != "`" && !firstCharacter.isLetter && !firstCharacter.isNumber && !kstatement.isEqualImplementation && !kstatement.isLessThanImplementation {
            kstatement.messages.append(.kotlinOperatorFunction(statement, source: translator.syntaxTree.source))
        }
        if kstatement.type == .constructorDeclaration, !kstatement.generics.isEmpty {
            kstatement.messages.append(.kotlinConstructorGenerics(statement, source: translator.syntaxTree.source))
        }
        return kstatement
    }

    static func translate(statement: SubscriptDeclaration, translator: KotlinTranslator) -> [KotlinStatement] {
        let getter = KotlinFunctionDeclaration(statement: statement, isSetter: false)
        getter.role = .operator
        getter.modifiers = statement.modifiers
        getter.generics = statement.generics.resolvingSelf(in: statement)
        getter.returnType = statement.elementType.resolvingSelf(in: statement)
        getter.parameters = statement.parameters.map { $0.resolvingSelf(in: statement).translate(translator: translator) }
        getter.attributes = getter.processAttributes(statement.attributes, from: statement, translator: translator)
        getter.apiFlags = statement.getterType.apiFlags
        translateMemberInfo(declaration: getter, from: statement, modifiers: statement.modifiers, translator: translator)
        translateBody(declaration: getter, from: statement, body: statement.getter?.body, returnType: statement.elementType, asyncBehavior: statement.asyncBehavior, translator: translator)
        if statement.asyncBehavior != .sync {
            getter.messages.append(.kotlinAsyncSubscript(getter, source: translator.syntaxTree.source))
        }

        guard let statementSetter = statement.setter else {
            return [getter]
        }
        let setter = KotlinFunctionDeclaration(statement: statement, isSetter: true)
        setter.role = .operator
        setter.modifiers = getter.modifiers
        setter.modifiers.isMutating = true
        setter.generics = getter.generics
        setter.returnType = .void
        setter.parameters = getter.parameters
        setter.parameters.append(Parameter<KotlinExpression>(externalLabel: statementSetter.parameterName ?? "newValue", declaredType: getter.returnType))
        setter.attributes = getter.attributes
        setter.apiFlags = statement.setterType.apiFlags
        translateMemberInfo(declaration: setter, from: statement, modifiers: statement.modifiers, translator: translator)
        translateBody(declaration: setter, from: statement, body: statementSetter.body, returnType: .void, asyncBehavior: .sync, translator: translator)
        return [getter, setter]
    }

    @discardableResult private static func translateMemberInfo(declaration kstatement: KotlinFunctionDeclaration, from statement: Statement, modifiers: Modifiers, translator: KotlinTranslator) -> Bool {
        guard let owningTypeDeclaration = statement.parent as? TypeDeclaration else {
            return false
        }

        // Make sure extension API is also handled correctly
        let owningDeclarationType = owningTypeDeclaration.nonExtensionDeclarationType ?? owningTypeDeclaration.type
        let owningDeclarationPrimaryTypeInfo = translator.codebaseInfo?.primaryTypeInfo(forNamed: owningTypeDeclaration.signature)
        let owningSignature = owningDeclarationPrimaryTypeInfo?.signature ?? owningTypeDeclaration.signature

        if statement.type == .initDeclaration && owningDeclarationType != .protocolDeclaration {
            kstatement.isOpen = false
            kstatement.modifiers.isOverride = false // Kotlin does not override constructors
            if (statement as? FunctionDeclaration)?.asyncBehavior == .async {
                kstatement.messages.append(.kotlinAsyncConstructor(statement, source: translator.syntaxTree.source))
            }
        } else if statement.type == .deinitDeclaration {
            kstatement.isOpen = owningTypeDeclaration.type == .classDeclaration && !owningTypeDeclaration.modifiers.isFinal
            kstatement.modifiers.visibility = .public
            // Swift deinit is called automatically for all types in hierarchy, but Kotlin finalizers must explicitly override
            if let codebaseInfo = translator.codebaseInfo {
                let inheritedTypeInfos = codebaseInfo.global.inheritanceChainSignatures(forNamed: owningSignature).dropFirst().flatMap { codebaseInfo.typeInfos(forNamed: $0) }
                kstatement.modifiers.isOverride = inheritedTypeInfos.contains { $0.members.contains { $0.declarationType == .deinitDeclaration } }
            }
        } else {
            if owningDeclarationType == .protocolDeclaration {
                // Kotlin uses default public visibility on all interface members
                kstatement.modifiers.visibility = .public
                // Warn if developer was trying to decrease the visibility of this member
                if let owningDeclarationPrimaryTypeInfo, modifiers.visibility < owningDeclarationPrimaryTypeInfo.modifiers.visibility {
                    kstatement.messages.append(.kotlinProtocolMemberVisibility(statement, source: translator.syntaxTree.source))
                }
                // Constructors in an interface will be moved into the interface's Companion interface, where
                // it should be called 'init' and return an instance of the interface
                if kstatement.type == .constructorDeclaration {
                    kstatement.type = .functionDeclaration
                    kstatement.name = "init"
                    kstatement.returnType = owningSignature
                    kstatement.modifiers.isStatic = true
                }
            }
            if !kstatement.modifiers.isOverride && translator.codebaseInfo?.isImplementingKotlinInterfaceMember(declaration: statement, in: owningSignature) == true {
                kstatement.modifiers.isOverride = true
            }
            if owningDeclarationType != .protocolDeclaration {
                kstatement.isOpen = !kstatement.modifiers.isOverride && !modifiers.isFinal && modifiers.visibility != .private && owningDeclarationType == .classDeclaration && !owningTypeDeclaration.modifiers.isFinal
            }
            // Kotlin does not allow you to decrease visibility when overriding a member, so we simply make all overrides public to prevent errors
            if kstatement.modifiers.isOverride {
                kstatement.modifiers.visibility = .public
            }
        }

        if !owningSignature.generics.isEmpty {
            // Kotlin companion objects do not have access to their type's generics, but we can create a generic function so long as the generic
            // is on a parameter rather than in the return type
            if kstatement.isStatic && owningTypeDeclaration.type != .protocolDeclaration {
                kstatement.convertToGenericFunction(owningTypeDeclaration, generics: owningSignature.generics, translator: translator)
            }
            // Within a type C<T>, convert any references to C<none> into C<T>
            let withUnknownGenerics: TypeSignature = .named(owningTypeDeclaration.name, owningTypeDeclaration.generics.entries.map { _ in TypeSignature.none })
            kstatement.returnType = kstatement.returnType.mappingTypes(from: [withUnknownGenerics], to: [owningSignature])
            kstatement.parameters = kstatement.parameters.map {
                var parameter = $0
                parameter.declaredType = parameter.declaredType.mappingTypes(from: [withUnknownGenerics], to: [owningSignature])
                return parameter
            }
        }
        return true
    }

    private static func translateBody(declaration kstatement: KotlinFunctionDeclaration, from statement: Statement, body: CodeBlock?, returnType: TypeSignature, asyncBehavior: AsyncBehavior, translator: KotlinTranslator) {
        kstatement.returnType.appendKotlinMessages(to: kstatement, source: translator.syntaxTree.source)
        kstatement.parameters.forEach { $0.appendKotlinMessages(to: kstatement, source: translator.syntaxTree.source) }
        guard let body else {
            return
        }

        kstatement.body = KotlinCodeBlock.translate(statement: body, translator: translator)
        // Note: we leave optional init handling to our transformers because we handle them differently for different types
        if let body = kstatement.body, statement.type != .initDeclaration {
            if returnType == .void {
                // Guard against using single-statement format for a void function whose only statement returns a value, e.g.:
                // fun f(): Unit = somethingThatReturnsAValueThatShouldBeIgnored()
                if body.statements.count == 1, let expressionStatement = body.statements[0] as? KotlinExpressionStatement, let apiCall = expressionStatement.expression as? APICallExpression, let apiMatch = apiCall.apiMatch, apiMatch.signature.returnType != .none && apiMatch.signature.returnType != .void {
                    body.disallowSingleStatementAppend = true
                }
            } else {
                // We sref() all values from functions. While this is not strictly necessary given that function return
                // values must be assigned to a var before mutating them, it produces cleaner code than calling sref() at
                // function call sites. This is particularly true when calling Kotlin native functions for which we do not
                // have symbols. It also makes functions symmetrical with the behavior of arrays and of mutable properties
                body.updateWithExpectedReturn(.sref(nil))
            }
            if asyncBehavior != .sync && body.updateWithExpectedReturn(.labelIfPresent(KotlinClosure.returnLabel)) {
                kstatement.hasAsyncExplicitReturn = true
            }
        }
        for parameter in kstatement.parameters where parameter.isInOut {
            kstatement.body?.updateWithInOutParameter(name: parameter.internalLabel, source: translator.syntaxTree.source)
        }
    }

    init(name: String, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.name = name
        super.init(type: name == "constructor" ? .constructorDeclaration : name == "finalize" ? .finalizerDeclaration : .functionDeclaration, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(statement: FunctionDeclaration) {
        if statement.type == .initDeclaration {
            self.name = "constructor"
            super.init(type: .constructorDeclaration, statement: statement)
        } else if statement.type == .deinitDeclaration {
            self.name = "finalize"
            super.init(type: .finalizerDeclaration, statement: statement)
        } else {
            self.name = statement.name
            super.init(type: .functionDeclaration, statement: statement)
        }
    }

    private init(statement: SubscriptDeclaration, isSetter: Bool) {
        self.name = isSetter ? "set" : "get"
        super.init(type: .functionDeclaration, statement: statement)
    }

    override func insertDependencies(into dependencies: inout KotlinDependencies) {
        generics.insertDependencies(into: &dependencies)
        returnType.insertDependencies(into: &dependencies)
        parameters.forEach { $0.insertDependencies(into: &dependencies) }
        // We use an array to represent variadic parameters
        if parameters.contains(where: { $0.isVariadic }) {
            dependencies.insertSkipLibType("Array")
        }
    }

    override var children: [KotlinSyntaxNode] {
        var children: [KotlinSyntaxNode] = parameters.compactMap { $0.defaultValue }
        if let delegatingConstructorCall {
            children.append(delegatingConstructorCall)
        }
        if let body {
            children.append(body)
        }
        return children
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if isHashImplementation {
            appendHashCode(to: output, indentation: indentation)
        }
        var hasExplicitReturnType = true
        if let declaration = extras?.declaration {
            output.append(indentation).append(declaration)
        } else {
            attributes.append(to: output, indentation: indentation)
            annotations.appendLines(to: output, indentation: indentation)
            output.append(indentation)
            if isEqualImplementation {
                appendEqualsDeclaration(to: output, indentation: indentation)
            } else if isLessThanImplementation {
                appendLessThanDeclaration(to: output, indentation: indentation)
            } else {
                hasExplicitReturnType = appendFunctionDeclaration(to: output, indentation: indentation)
            }
        }
        if !isExternal, let body {
            if isEqualImplementation {
                appendEqualsBody(body, to: output, indentation: indentation)
            } else if isLessThanImplementation {
                appendLessThanBody(body, to: output, indentation: indentation)
            } else {
                appendFunctionBody(body, to: output, indentation: indentation, hasExplicitReturnType: hasExplicitReturnType)
            }
        } else {
            output.append("\n")
        }
    }

    private func appendFunctionDeclaration(to output: OutputGenerator, indentation: Indentation) -> Bool {
        if role != .local {
            output.append(modifiers.kotlinMemberString(isGlobal: role == .global, isOpen: isOpen, suffix: " "))
        }
        if apiFlags.contains(.async) {
            output.append("suspend ")
        }

        let generics = functionGenerics.filterWhereEqual()
        let isInline = attributes.contains(.inlineAlways) && !isOpen
        if type != .constructorDeclaration {
            if isExternal {
                output.append("external ")
            }
            if isInline {
                output.append("inline ")
            }
            if role == .operator {
                output.append("operator ")
            }
            output.append("fun ")
        }
        if !generics.isEmpty {
            generics.append(to: output, indentation: indentation, modifier: isInline ? "reified" : nil)
            output.append(" ")
        }
        appendExtends(to: output, indentation: indentation)
        output.append(name).append("(")
        for (index, parameter) in parameters.enumerated() {
            if parameter.isVariadic {
                output.append("vararg ")
            }
            let label = parameter.externalLabel ?? parameter.internalLabel
            output.append(label)
            output.append(": ")
            if parameter.isInOut {
                output.append("InOut<")
            }
            output.append(parameter.declaredType.or(.any).kotlin)
            if parameter.isInOut {
                output.append(">")
            }
            // Kotlin does not allow default values to override functions
            if let defaultValue = parameter.defaultValue, !modifiers.isOverride {
                output.append(" = ").append(defaultValue, indentation: indentation)
            }
            if index != parameters.count - 1 || disambiguatingParameterCount > 0 {
                output.append(", ")
            }
        }
        for i in 0..<disambiguatingParameterCount {
            output.append("@Suppress(\"UNUSED_PARAMETER\") unusedp_\(i): Nothing?")
            if !modifiers.isOverride {
                output.append(" = null")
            }
            if i != disambiguatingParameterCount - 1 {
                output.append(", ")
            }
        }
        output.append(")")

        var hasExplicitReturnType = false
        if type != .constructorDeclaration {
            // Kotlin requires an explicit return type for single statement bodies (as we use for async) that return Never, as in:
            //   suspending fun f(): Unit = MainActor.run { throw Error() }
            if returnType != .void || apiFlags.contains(.async) {
                output.append(": ").append(returnType.kotlin)
                hasExplicitReturnType = true
            }
        } else if let delegatingConstructorCall {
            output.append(": ").append(delegatingConstructorCall, indentation: indentation)
        }
        functionGenerics.appendWhere(to: output, indentation: indentation)
        return hasExplicitReturnType
    }

    private func appendFunctionBody(_ body: KotlinCodeBlock, to output: OutputGenerator, indentation: Indentation, hasExplicitReturnType: Bool) {
        let isConstructor = type == .constructorDeclaration
        let callSuperFinalize = type == .finalizerDeclaration && modifiers.isOverride
        guard isConstructor || callSuperFinalize || !body.statements.isEmpty else {
            output.append(" = Unit\n")
            return
        }

        var parameterVals: [String] = []
        for parameter in parameters {
            if parameter.isVariadic && !isGenerated {
                parameterVals.append("val \(parameter.internalLabel) = Array(\(parameter.externalLabel ?? parameter.internalLabel).asIterable())\n")
            } else if let externalLabel = parameter.externalLabel, parameter.internalLabel != externalLabel {
                parameterVals.append("val \(parameter.internalLabel) = \(externalLabel)\n")
            }
        }
        var suppressSideEffectsPropertyName: String? = nil
        if type == .constructorDeclaration || suppressSideEffects, let propertyName = (parent as? KotlinClassDeclaration)?.suppressSideEffectsPropertyName {
            suppressSideEffectsPropertyName = propertyName
            body.syntheticFinally = "\(propertyName) = false"
        } else if let mutationFunctionNames {
            body.syntheticFinally = "\(mutationFunctionNames.didMutate)()"
        }

        // Append Kotlin single statement format if possible
        guard isConstructor || apiFlags.contains(.async) || callSuperFinalize || !parameterVals.isEmpty || suppressSideEffects || mutationFunctionNames != nil || !body.isSingleStatementAppendable(mode: .function) else {
            // There are scenarios in which single statement functions without an explicit return type result in a compiler error, such as a function
            // whose body just calls the same function on another object. So be explicit
            if !hasExplicitReturnType {
                output.append(": ").append(returnType.kotlin)
            }
            output.append(" = ")
            body.appendAsSingleStatement(to: output, indentation: indentation, mode: .function)
            output.append("\n")
            return
        }

        if apiFlags.contains(.async) {
            if apiFlags.contains(.mainActor) {
                output.append(" = MainActor.run ")
            } else if isActorIsolated {
                output.append(" = Actor.run(this) ")
            } else {
                output.append(" = Async.run ")
            }
            if hasAsyncExplicitReturn {
                output.append("\(KotlinClosure.returnLabel)@")
            }
            output.append("{\n")
        } else {
            output.append(" {\n")
        }
        let bodyIndentation = indentation.inc()
        if !body.statements.isEmpty {
            parameterVals.forEach { output.append(bodyIndentation).append($0) }
            if let suppressSideEffectsPropertyName {
                output.append(bodyIndentation).append("\(suppressSideEffectsPropertyName) = true\n")
            } else if let mutationFunctionNames {
                output.append(bodyIndentation).append("\(mutationFunctionNames.willMutate)()\n")
            }
            output.append(body, indentation: bodyIndentation)
        }
        if callSuperFinalize {
            output.append(bodyIndentation).append("super.finalize()\n")
        }
        output.append(indentation).append("}\n")
    }

    private func appendEqualsDeclaration(to output: OutputGenerator, indentation: Indentation) {
        output.append("override fun equals(other: Any?): Boolean")
    }

    private func appendEqualsBody(_ body: KotlinCodeBlock, to output: OutputGenerator, indentation: Indentation) {
        output.append(" {\n")
        let bodyIndentation = indentation.inc()
        let anyGenerics = parameters[1].declaredType.generics.map { _ in TypeSignature.none }
        output.append(bodyIndentation).append("if (other !is \(parameters[1].declaredType.withGenerics(anyGenerics).kotlin)) {\n")
        output.append(bodyIndentation.inc()).append("return false\n")
        output.append(bodyIndentation).append("}\n")
        output.append(bodyIndentation).append("val \(parameters[0].internalLabel) = this\n")
        output.append(bodyIndentation).append("val \(parameters[1].internalLabel) = other\n")
        output.append(body, indentation: bodyIndentation)
        output.append(indentation).append("}\n")
    }

    private func appendLessThanDeclaration(to output: OutputGenerator, indentation: Indentation) {
        output.append("override fun compareTo(other: \(parameters[0].declaredType.kotlin)): Int")
    }

    private func appendLessThanBody(_ body: KotlinCodeBlock, to output: OutputGenerator, indentation: Indentation) {
        output.append(" {\n")
        let bodyIndentation = indentation.inc()
        output.append(bodyIndentation).append("if (this == other) return 0\n")
        output.append(bodyIndentation).append("fun islessthan(\(parameters[0].internalLabel): \(parameters[0].declaredType.kotlin), \(parameters[1].internalLabel): \(parameters[1].declaredType.kotlin)): Boolean {\n")
        output.append(body, indentation: bodyIndentation.inc())
        output.append(bodyIndentation).append("}\n")
        output.append(bodyIndentation).append("return if (islessthan(this, other)) -1 else 1\n")
        output.append(indentation).append("}\n")
    }

    private func appendHashCode(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation).append("override fun hashCode(): Int {\n")
        let bodyIndentation = indentation.inc()
        output.append(bodyIndentation).append("var hasher = Hasher()\n")
        output.append(bodyIndentation).append("hash(into = InOut<Hasher>({ hasher }, { hasher = it }))\n")
        output.append(bodyIndentation).append("return hasher.finalize()\n")
        output.append(indentation).append("}\n")
    }

    private func convertToGenericFunction(_ owningTypeDeclaration: TypeDeclaration, generics genericTypes: [TypeSignature], translator: KotlinTranslator) {
        var genericsUsedInParameters: [TypeSignature] = []
        var remainingGenerics: [TypeSignature] = []
        for genericType in genericTypes {
            if parameters.contains(where: { $0.declaredType.referencesType(genericType) }) {
                genericsUsedInParameters.append(genericType)
            } else {
                remainingGenerics.append(genericType)
            }
        }
        if remainingGenerics.contains(where: { returnType.referencesType($0) }) {
            messages.append(.kotlinGenericStaticMember(self, source: translator.syntaxTree.source))
        } else if owningTypeDeclaration.type == .extensionDeclaration && !owningTypeDeclaration.generics.entries.allSatisfy({ genericsUsedInParameters.contains($0.namedType) }) {
            messages.append(.kotlinGenericExtensionStaticMember(self, source: translator.syntaxTree.source))
        } else if !genericsUsedInParameters.isEmpty && modifiers.isOverride {
            // Can't implement a static protocol requirement (as indicated by the override) with a generic function
            messages.append(.kotlinGenericStaticMember(self, source: translator.syntaxTree.source))
        }
        guard !genericsUsedInParameters.isEmpty else {
            return
        }

        var convertedGenerics: Generics
        if extends != nil {
            convertedGenerics = self.functionGenerics
        } else if let typeInfo = translator.codebaseInfo?.primaryTypeInfo(forNamed: owningTypeDeclaration.signature) {
            convertedGenerics = typeInfo.generics.merge(overrides: owningTypeDeclaration.generics)
        } else {
            convertedGenerics = owningTypeDeclaration.generics
        }
        convertedGenerics.entries = convertedGenerics.entries.filter { genericsUsedInParameters.contains($0.namedType) }
        self.convertedGenerics = convertedGenerics.merge(overrides: generics, addNew: true)
    }
}

class KotlinImportDeclaration: KotlinStatement {
    var modulePath: [String]
    var modulePathString: String {
        guard modulePath.count > 0 else {
            return ""
        }

        // If equivalent package name is the same, assume this is a Kotlin import, otherwise treat as a Swift import
        // Need to check against the unmodified translated package
        let packageNameBare = KotlinTranslator.packageName(forModule: modulePath[0], withDefaultPackageSuffix: nil)
        if packageNameBare == modulePath[0] {
            if modulePath.last == "__" {
                return modulePath.dropLast().joined(separator: ".") + ".*"
            } else {
                return modulePath.joined(separator: ".")
            }
        } else {
            let packageName = KotlinTranslator.packageName(forModule: modulePath[0])
            if modulePath.count == 1 {
                return packageName + ".*"
            } else {
                return packageName + "." + modulePath[1...].joined(separator: ".")
            }
        }
    }

    init(modulePath: [String], sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.modulePath = modulePath
        super.init(type: .importDeclaration, sourceFile: sourceFile, sourceRange: sourceRange)
    }
    
    init(statement: ImportDeclaration) {
        self.modulePath = statement.modulePath
        super.init(type: .importDeclaration, statement: statement)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        guard !modulePath.isEmpty else {
            return
        }
        output.append(indentation)
        output.append("import ")
        output.append(modulePathString)
        output.append("\n")
    }
}

class KotlinInterfaceDeclaration: KotlinStatement {
    var name: String
    var signature: TypeSignature
    var inherits: [TypeSignature] = []
    var companionInterface: TypeSignature?
    var companionInherits: [TypeSignature] = []
    var attributes = Attributes()
    var annotations: [String] = []
    var modifiers = Modifiers()
    var generics = Generics()
    var members: [KotlinStatement] = []
    var movedExtensionImportModulePaths: [[String]] = []

    static func translate(statement: TypeDeclaration, translator: KotlinTranslator) -> [KotlinStatement] {
        let kstatement = KotlinInterfaceDeclaration(statement: statement)
        kstatement.attributes = kstatement.processAttributes(statement.attributes, from: statement, translator: translator)
        kstatement.modifiers = statement.modifiers
        kstatement.inherits = statement.inherits
        kstatement.generics = statement.generics.resolvingSelf(in: statement)
        kstatement.members = statement.members.flatMap { translator.translateStatement($0) }
        guard let codebaseInfo = translator.codebaseInfo else {
            kstatement.inherits.forEach { $0.appendKotlinMessages(to: kstatement, source: translator.syntaxTree.source) }
            return [kstatement]
        }
        if case .interface(let signature) = codebaseInfo.companionType(of: statement.signature) {
            kstatement.companionInterface = signature
        }

        if let typeInfo = codebaseInfo.primaryTypeInfo(forNamed: statement.signature) {
            // Type info contains full resolved generics
            kstatement.signature = typeInfo.signature
            kstatement.inherits = typeInfo.inherits
            kstatement.generics = typeInfo.generics.resolvingSelf(in: statement)
        }

        // Move extensions of this type into the type itself rather than use Kotlin extension functions.
        // This allows us to replace API declarations with implementations. Also Kotlin extension functions
        // act like static functions, which can lead to different behavior
        var originalMembers = kstatement.members
        var newMembers: [KotlinStatement] = []
        var extensionMembers: [Statement] = []
        for (extInfo, extDeclaration, extImportModulePaths) in codebaseInfo.moveableExtensions(of: statement.signature, in: translator.syntaxTree) {
            kstatement.inherits += extInfo.inherits

            let partitioned = KotlinExtensionDeclaration.partition(members: extDeclaration.members, of: kstatement.signature, isFinal: false)
            extensionMembers += partitioned.extensionMembers

            for kmember in partitioned.members.flatMap({ translator.translateStatement($0) }) {
                if !replaceMember(in: &originalMembers, with: kmember) {
                    if newMembers.isEmpty {
                        kmember.ensureLeadingNewlines(1)
                    }
                    newMembers.append(kmember)
                }
            }
            kstatement.movedExtensionImportModulePaths += extImportModulePaths
        }
        kstatement.members = originalMembers + newMembers

        // Kotlin interfaces cannot extend Any
        kstatement.inherits = kstatement.inherits.filter { $0 != .any && $0 != .anyObject }
        kstatement.companionInherits = kstatement.inherits.compactMap {
            return if case .interface(let signature) = codebaseInfo.companionType(of: $0) {
                signature
            } else {
                nil
            }
        }
        kstatement.inherits.forEach { $0.appendKotlinMessages(to: kstatement, source: translator.syntaxTree.source) }

        let kextensionMembers = KotlinExtensionDeclaration.translateExtensionMembers(extensionMembers, of: kstatement.signature, visibility: kstatement.modifiers.visibility, generics: kstatement.generics, declarationType: .protocolDeclaration, translator: translator)
        kextensionMembers.first?.ensureLeadingNewlines(1)
        return [kstatement] + kextensionMembers
    }

    private static func replaceMember(in originalMembers: inout [KotlinStatement], with member: KotlinStatement) -> Bool {
        for i in 0..<originalMembers.count {
            guard originalMembers[i].type == member.type else {
                continue
            }
            if let originalVariableDeclaration = originalMembers[i] as? KotlinVariableDeclaration, let variableDeclaration = member as? KotlinVariableDeclaration {
                if originalVariableDeclaration.isStatic == variableDeclaration.isStatic && originalVariableDeclaration.names == variableDeclaration.names {
                    member.ensureLeadingNewlines(originalMembers[i].leadingNewlines)
                    originalMembers[i] = member
                    return true
                }
            } else if let originalFunctionDeclaration = originalMembers[i] as? KotlinFunctionDeclaration, let functionDeclaration = member as? KotlinFunctionDeclaration {
                if originalFunctionDeclaration.isStatic == functionDeclaration.isStatic && originalFunctionDeclaration.name == functionDeclaration.name && originalFunctionDeclaration.functionType == functionDeclaration.functionType {
                    member.ensureLeadingNewlines(originalMembers[i].leadingNewlines)
                    originalMembers[i] = member
                    return true
                }
            }
        }
        return false
    }

    private init(statement: TypeDeclaration) {
        self.name = statement.name
        self.signature = statement.signature
        super.init(type: .interfaceDeclaration, statement: statement)
    }

    override var children: [KotlinSyntaxNode] {
        return members
    }

    override func insert(statements: [KotlinStatement], after statement: KotlinStatement?) {
        var index = 0
        if let statement {
            if let statementIndex = members.firstIndex(where: { $0 === statement }) {
                index = statementIndex + 1
            } else {
                super.insert(statements: statements, after: statement)
                return
            }
        }
        members.insert(contentsOf: statements, at: index)
        for statement in statements {
            statement.parent = self
            statement.assignParentReferences()
        }
    }

    override func remove(statement: KotlinStatement) {
        members = members.filter { $0 !== statement }
    }

    override func insertDependencies(into dependencies: inout KotlinDependencies) {
        inherits.forEach { $0.insertDependencies(into: &dependencies) }
        generics.insertDependencies(into: &dependencies)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation)
        if let declaration = extras?.declaration {
            output.append(declaration)
        } else {
            attributes.append(to: output, indentation: indentation)
            annotations.appendLines(to: output, indentation: indentation)
            output.append(visibilityDeclaration).append("interface ").append(name)
            generics.append(to: output, indentation: indentation)
            if !inherits.isEmpty {
                output.append(": ").append(inherits.map(\.kotlin).joined(separator: ", "))
            }
            generics.appendWhere(to: output, indentation: indentation)
        }
        output.append(" {\n")

        var staticMembers: [KotlinStatement] = []
        let memberIndentation = indentation.inc()
        for member in members {
            if member.type == .constructorDeclaration || (member as? KotlinMemberDeclaration)?.isStatic == true {
                staticMembers.append(member)
            } else {
                output.append(member, indentation: memberIndentation)
            }
        }
        output.append(indentation).append("}\n")
        appendCompanion(to: output, indentation: indentation, staticMembers: staticMembers)
    }

    private func appendCompanion(to output: OutputGenerator, indentation: Indentation, staticMembers: [KotlinStatement]) {
        guard let companionInterface else {
            return
        }
        output.append(indentation)
        output.append(visibilityDeclaration).append("interface ").append(companionInterface.unqualifiedName)
        generics.append(to: output, indentation: indentation)
        if !companionInherits.isEmpty {
            output.append(": ").append(companionInherits.map(\.kotlin).joined(separator: ", "))
        }
        generics.appendWhere(to: output, indentation: indentation)
        output.append(" {\n")
        let memberIndentation = indentation.inc()
        staticMembers.forEach { output.append($0, indentation: memberIndentation) }
        output.append(indentation).append("}\n")
    }

    private var visibilityDeclaration: String {
        switch modifiers.visibility {
        case .default, .internal:
            return "internal "
        case .open:
            fallthrough
        case .public:
            return ""
        case .private, .fileprivate:
            return "private "
        }
    }
}

/// - Note: We perform full typealias resolution when transpiling. We do not actually use any typealiases in our generated Kotlin. We do translate typealiases, however,
///  so that any manually-written Kotlin has access to them.
class KotlinTypealiasDeclaration: KotlinStatement {
    var name: String
    var attributes = Attributes()
    var modifiers = Modifiers()
    var generics = Generics()
    var aliasedType: TypeSignature = .none

    static func translate(statement: TypealiasDeclaration, translator: KotlinTranslator) -> [KotlinStatement] {
        let messages = validate(statement: statement, translator: translator)
        if statement.owningTypeDeclaration != nil {
            // Kotln does not support nested typealiases
            return messages.map { KotlinMessageStatement(message: $0, statement: statement) }
        }

        let kstatement = KotlinTypealiasDeclaration(statement: statement)
        kstatement.modifiers = statement.modifiers
        kstatement.generics = statement.generics.resolvingSelf(in: statement)
        kstatement.aliasedType = statement.aliasedType
        kstatement.attributes = kstatement.processAttributes(statement.attributes, from: statement, translator: translator)
        kstatement.messages += messages
        return [kstatement]
    }

    private static func validate(statement: TypealiasDeclaration, translator: KotlinTranslator) -> [Message] {
        if statement.generics.entries.contains(where: { !$0.inherits.isEmpty || $0.whereEqual != nil }) {
            return [.kotlinTypeAliasConstrainedGenerics(statement, source: translator.syntaxTree.source)]
        }
        return []
    }

    private init(statement: TypealiasDeclaration) {
        self.name = statement.name
        super.init(type: .typealiasDeclaration, statement: statement)
    }

    override func insertDependencies(into dependencies: inout KotlinDependencies) {
        aliasedType.insertDependencies(into: &dependencies)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if let declaration = extras?.declaration {
            output.append(indentation).append(declaration).append("\n")
        } else {
            attributes.append(to: output, indentation: indentation)
            output.append(indentation).append(modifiers.kotlinMemberString(isGlobal: true, isOpen: false, suffix: " "))
            output.append("typealias ").append(name)
            generics.append(to: output, indentation: indentation)
            output.append(" = ").append(aliasedType.kotlin).append("\n")
        }
    }
}

class KotlinVariableDeclaration: KotlinStatement, KotlinMemberDeclaration {
    var names: [String?]
    var propertyName: String {
        get {
            return (names.first ?? "") ?? ""
        } set {
            names = [newValue]
        }
    }
    var preEscapePropertyName: String?
    var propertyType: TypeSignature {
        get {
            return variableTypes.first ?? .none
        }
        set {
            variableTypes = [newValue]
        }
    }
    var declaredType: TypeSignature = .none
    var isLet = false
    var role: Role = .local
    var isOpen = false
    var annotations: [String] = []
    var getterAnnotations: [String] = []
    var modifiers = Modifiers()
    var attributes = Attributes()
    var apiFlags: APIFlags = []
    var isAsyncLet: Bool {
        return isLet && apiFlags.contains(.async)
    }
    var isActorIsolated = false
    var value: KotlinExpression?
    var getter: Accessor<KotlinCodeBlock>?
    var setter: Accessor<KotlinCodeBlock>?
    var willSet: Accessor<KotlinCodeBlock>?
    var didSet: Accessor<KotlinCodeBlock>?
    var variableTypes: [TypeSignature]
    var hasAsyncExplicitReturn = false
    var mayBeSharedMutableStruct = false
    var isAssignFromWriteable = false
    var onUpdate: (() -> String)?
    var suppressSideEffectsPropertyName: String?
    var mutationFunctionNames: (willMutate: String, didMutate: String)?
    var storage: KotlinVariableStorage?
    var isGenerated = false
    var isDescriptionImplementation: Bool {
        return role.isProperty && propertyName == "description" && propertyType == .string
    }

    enum Role {
        case local
        case global
        case property
        case protocolProperty
        case superclassOverrideProperty

        var isProperty: Bool {
            return self == .property || self == .protocolProperty || self == .superclassOverrideProperty
        }
    }

    // KotlinMemberDeclaration
    var extends: (TypeSignature, KotlinCompanionType, Generics)? {
        didSet {
            if extends != nil {
                isOpen = false
            }
        }
    }
    var isStatic: Bool {
        return modifiers.isStatic
    }
    var visibility: Modifiers.Visibility {
        get {
            return modifiers.visibility
        }
        set {
            modifiers.visibility = newValue
        }
    }

    static func translate(statement: VariableDeclaration, translator: KotlinTranslator) -> KotlinVariableDeclaration {
        let kstatement = KotlinVariableDeclaration(statement: statement)
        kstatement.isLet = statement.isLet
        kstatement.modifiers = statement.modifiers
        kstatement.declaredType = statement.declaredType.resolvingSelf(in: statement)
        let owningTypeDeclaration = statement.parent as? TypeDeclaration
        var owningDeclarationType: StatementType? = nil
        if let owningTypeDeclaration {
            // Make sure extension API is also handled correctly
            owningDeclarationType = owningTypeDeclaration.nonExtensionDeclarationType ?? owningTypeDeclaration.type
            let owningSignature = translator.codebaseInfo?.primaryTypeInfo(forNamed: owningTypeDeclaration.signature)?.signature ?? owningTypeDeclaration.signature

            kstatement.role = .property
            if owningDeclarationType == .protocolDeclaration {
                kstatement.role = .protocolProperty
                // Kotlin uses default public visibility on all interface members
                kstatement.modifiers.visibility = .public
                kstatement.modifiers.setVisibility = .public
                if !kstatement.modifiers.isOverride && translator.codebaseInfo?.isImplementingKotlinInterfaceMember(declaration: statement, in: owningSignature) == true {
                    kstatement.modifiers.isOverride = true
                }
            } else {
                if kstatement.modifiers.isOverride {
                    kstatement.role = .superclassOverrideProperty
                } else if translator.codebaseInfo?.isImplementingKotlinInterfaceMember(declaration: statement, in: owningSignature) == true {
                    kstatement.modifiers.isOverride = true
                }
                kstatement.isOpen = !kstatement.isLet && !kstatement.modifiers.isOverride && !statement.modifiers.isFinal && statement.modifiers.visibility != .private && owningDeclarationType == .classDeclaration && !owningTypeDeclaration.modifiers.isFinal
                if kstatement.isOpen && statement.modifiers.setVisibility == .private {
                    // Stored properties with private setters can't be overridden in either language. Computed properties with private
                    // setters can be overridden in Swift, but not Kotlin. Lift the restriction by promoting the Kotlin visibility
                    if statement.getter == nil {
                        kstatement.isOpen = false
                    } else {
                        kstatement.modifiers.setVisibility = .internal
                    }
                }
            }
            // Kotlin does not allow you to decrease visibility when overriding a member, so we simply make all overrides public to prevent errors
            if kstatement.modifiers.isOverride {
                kstatement.modifiers.visibility = .public
                kstatement.modifiers.setVisibility = .public
            }
            if !owningSignature.generics.isEmpty {
                if kstatement.isStatic && owningSignature.generics.contains(where: { kstatement.declaredType.referencesType($0) }) {
                    kstatement.messages.append(.kotlinGenericStaticMember(kstatement, source: translator.syntaxTree.source))
                } else if kstatement.isStatic && owningTypeDeclaration.type == .extensionDeclaration && !owningTypeDeclaration.generics.isEmpty {
                    kstatement.messages.append(.kotlinGenericExtensionStaticMember(kstatement, source: translator.syntaxTree.source))
                }
                // Within a type C<T>, convert any references to C<none> into C<T>
                let withUnknownGenerics: TypeSignature = .named(owningTypeDeclaration.name, owningTypeDeclaration.generics.entries.map { _ in TypeSignature.none })
                kstatement.declaredType = kstatement.declaredType.mappingTypes(from: [withUnknownGenerics], to: [owningSignature])
            }
        } else if statement.isGlobal {
            kstatement.role = .global
        }
        if let value = statement.value {
            // Kotlin does not call the setter for the assigned initial value, so sref() ourselves
            kstatement.value = translator.translateExpression(value).sref()
        }

        kstatement.attributes = kstatement.processAttributes(statement.attributes, from: statement, translator: translator)
        kstatement.apiFlags = statement.apiFlags
        kstatement.isActorIsolated = statement.asyncBehavior == .actor
        if kstatement.declaredType != .none {
            kstatement.mayBeSharedMutableStruct = statement.constrainedDeclaredType.kotlinMayBeSharedMutableStruct(codebaseInfo: translator.codebaseInfo)
        } else if let kvalue = kstatement.value {
            kstatement.mayBeSharedMutableStruct = kvalue.mayBeSharedMutableStructExpression(orType: true)
        } else {
            kstatement.mayBeSharedMutableStruct = true
        }
        if statement.apiFlags.contains(.writeable) && kstatement.mayBeSharedMutableStruct {
            // Use a closure to build onUpdate code on-demand in case our property name is changed
            kstatement.onUpdate = { [weak kstatement] in
                guard let kstatement else {
                    return ""
                }
                return kstatement.role.isProperty ? "{ this.\(kstatement.propertyName) = it }" : "{ \(kstatement.propertyName) = it }"
            }
            // If a transformer changes our onUpdate closure, the resulting getter code will change
            kstatement.getter = statement.getter?.translate(translator: translator, expectedReturn: .sref({ [weak kstatement] in kstatement?.onUpdate?() ?? "" }))
        } else {
            kstatement.getter = statement.getter?.translate(translator: translator, expectedReturn: .yes)
        }
        kstatement.setter = statement.setter?.translate(translator: translator, expectedReturn: .no)
        kstatement.willSet = statement.willSet?.translate(translator: translator, expectedReturn: .no)
        kstatement.didSet = statement.didSet?.translate(translator: translator, expectedReturn: .no)

        if kstatement.apiFlags.contains(.async) {
            if kstatement.isAsyncLet {
                if let value = kstatement.value {
                    KotlinAwait.setIsAsync(value, source: translator.syntaxTree.source)
                }
            } else {
                if kstatement.isActorIsolated {
                    // Allow synchronous access to private actor mutable variables, and disallow non-private ones. This still
                    // leaves us with potential bugs if a non-isolated actor function accesses its private state, but we have to
                    // allow this because we don't yet support mutable isolated variables
                    if kstatement.apiFlags.contains(.writeable) {
                        if kstatement.modifiers.visibility == .private {
                            kstatement.isActorIsolated = false
                            kstatement.apiFlags.remove(.async)
                        } else {
                            kstatement.messages.append(.kotlinActorMutableProperty(kstatement, source: translator.syntaxTree.source))
                        }
                    }
                }
                // Check the async flag again, because we may have just cleared it above
                if kstatement.apiFlags.contains(.async) && kstatement.getter?.body?.updateWithExpectedReturn(.labelIfPresent(KotlinClosure.returnLabel)) == true {
                    kstatement.hasAsyncExplicitReturn = true
                }
            }
        }

        // Warnings and fixups
        kstatement.declaredType.appendKotlinMessages(to: kstatement, source: translator.syntaxTree.source)
        if kstatement.declaredType == .float || kstatement.declaredType.isUnsigned, let literal = kstatement.value as? KotlinNumericLiteral, literal.suffix.isEmpty {
            kstatement.messages.append(.kotlinNumericCast(kstatement, source: translator.syntaxTree.source, type: kstatement.declaredType.kotlin))
        }
        if kstatement.role.isProperty || kstatement.role == .global {
            if kstatement.propertyType.isUnwrappedOptional && kstatement.propertyType.kotlinIsNative(primitive: true) {
                kstatement.messages.append(.kotlinLateinitPrimitive(kstatement, source: translator.syntaxTree.source))
            }
        } else if let functionDeclaration = statement.parent?.parent as? FunctionDeclaration {
            if functionDeclaration.parameters.contains(where: { kstatement.names.contains($0.internalLabel) && $0.internalLabel != $0.externalLabel && $0.externalLabel != nil }) {
                kstatement.messages.append(.kotlinVariableMirrorInternalParameter(kstatement, source: translator.syntaxTree.source))
            }
        }
        return kstatement
    }

    init(names: [String], variableTypes: [TypeSignature], sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.names = names
        self.variableTypes = variableTypes
        super.init(type: .variableDeclaration, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(statement: VariableDeclaration) {
        self.names = statement.names
        self.variableTypes = statement.variableTypes.map { $0.resolvingSelf(in: statement) }
        super.init(type: .variableDeclaration, statement: statement)
    }

    override func insertDependencies(into dependencies: inout KotlinDependencies) {
        declaredType.insertDependencies(into: &dependencies)
    }

    override var children: [KotlinSyntaxNode] {
        var children: [KotlinSyntaxNode] = []
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

    override func append(to output: OutputGenerator, indentation: Indentation) {
        let storage = initializeStorage()
        if let declaration = extras?.declaration {
            output.append(indentation).append(declaration)
        } else if names.count == 1 && names[0] == nil {
            // Kotlin doesn't support assignment to wildcard
            if let value {
                output.append(indentation).append(value, indentation: indentation)
            }
        } else {
            appendDeclaration(to: output, indentation: indentation, storage: storage)
        }

        if apiFlags.contains(.viewBuilder) || apiFlags.contains(.async), let getterBody = getter?.body {
            appendAsFunctionDefinition(getterBody, to: output, indentation: indentation)
        } else {
            appendPropertyDefinition(to: output, indentation: indentation, storage: storage)
        }
        storage?.appendStorage(self, output, indentation)
        if modifiers.isLazy {
            output.append(indentation).append("private var \(KotlinVariableStorage.lazyInitializedName(self)) = false\n")
        }

        // Create property wrapper-like access for local @Bindable variables. We use a Binding rather than Observable
        // because its closures will keep it in sync with the local value
        if role == .local && attributes.contains(.bindable) {
            output.append(indentation).append("val _\(propertyName) = Binding({ \(propertyName) }, { it -> \(propertyName) = it })\n")
        }
    }

    private func appendDeclaration(to output: OutputGenerator, indentation: Indentation, storage: KotlinVariableStorage?) {
        attributes.append(to: output, indentation: indentation)
        annotations.appendLines(to: output, indentation: indentation)
        output.append(indentation)
        if role.isProperty || role == .global {
            output.append(modifiers.kotlinMemberString(isGlobal: role == .global, isOpen: isOpen, suffix: " "))
            if apiFlags.contains(.async) {
                output.append("suspend ")
            } else if storage == nil && role != .superclassOverrideProperty && declaredType.isUnwrappedOptional {
                output.append("lateinit ")
            }
        }
        if apiFlags.contains(.viewBuilder) || (apiFlags.contains(.async) && !isAsyncLet) {
            output.append("fun ")
        } else if !apiFlags.contains(.writeable) && !isAssignFromWriteable {
            output.append("val ")
        } else {
            output.append("var ")
        }
        if let generics = extends?.2.filterWhereEqual(), !generics.isEmpty {
            generics.append(to: output, indentation: indentation)
            output.append(" ")
        }
        appendExtends(to: output, indentation: indentation)
        if names.count > 1 {
            output.append("(")
        }
        output.append(names.map { $0 ?? "_" }.joined(separator: ", "))
        if names.count > 1 {
            output.append(")")
        }
        if apiFlags.contains(.viewBuilder) || (apiFlags.contains(.async) && !isAsyncLet) {
            output.append("()")
        }

        if declaredType != .none {
            output.append(": ").append(declaredType.kotlin)
        } else if storage != nil && propertyType != .none {
            output.append(": ").append(propertyType.kotlin)
        }
        if (!apiFlags.contains(.async) || isAsyncLet) && storage == nil {
            appendInitialValue(to: output, indentation: indentation)
        }
        extends?.2.appendWhere(to: output, indentation: indentation)
    }

    private func appendAsFunctionDefinition(_ body: KotlinCodeBlock, to output: OutputGenerator, indentation: Indentation) {
        if apiFlags.contains(.mainActor) {
            output.append(" = MainActor.run ")
        } else if isActorIsolated {
            output.append(" = Actor.run(this) ")
        } else if apiFlags.contains(.async) {
            output.append(" = Async.run ")
        } else {
            output.append(" ")
        }
        if hasAsyncExplicitReturn {
            output.append("\(KotlinClosure.returnLabel)@")
        }
        output.append("{\n")
        output.append(body, indentation: indentation.inc())
        output.append(indentation).append("}\n")
    }

    private func appendPropertyDefinition(to output: OutputGenerator, indentation: Indentation, storage: KotlinVariableStorage?) {
        output.append("\n")
        if !getterAnnotations.isEmpty {
            getterAnnotations.appendLines(to: output, indentation: indentation.inc())
        }
        if let getterBody = getter?.body {
            let getterIndentation = indentation.inc()
            if let storage {
                let isSingleStatement = storage.isSingleStatementAppendable(self)
                if isSingleStatement {
                    output.append(getterIndentation).append("get() = ")
                    storage.appendGet(self, { }, true, output, getterIndentation)
                } else {
                    output.append(getterIndentation).append("get() {\n")
                    storage.appendGet(self, { }, false, output, getterIndentation.inc())
                    output.append(getterIndentation).append("}\n")
                }
            } else {
                appendGetterBody(getterBody, to: output, indentation: getterIndentation)
            }
        } else if role == .superclassOverrideProperty {
            output.append(indentation.inc()).append("get() = super.\(propertyName)\n")
        } else if (role.isProperty && role != .protocolProperty) || role == .global, storage != nil || (mayBeSharedMutableStruct && apiFlags.contains(.writeable)) {
            let getterIndentation = indentation.inc()
            output.append(getterIndentation).append("get()")
            let isSingleStatement = storage?.isSingleStatementAppendable(self) != false && (mutationFunctionNames == nil || !modifiers.isLazy)
            if isSingleStatement {
                output.append(" = ")
                appendGetField(to: output, indentation: getterIndentation, storage: storage, isSingleStatement: true)
            } else {
                let getterBodyIndentation = getterIndentation.inc()
                var getIndentation = getterBodyIndentation
                output.append(" {\n")
                if let mutationFunctionNames, modifiers.isLazy {
                    // Lazy getters are considered mutable
                    output.append(getterBodyIndentation).append("val isinitialized = \(KotlinVariableStorage.lazyInitializedName(self))\n")
                    output.append(getterBodyIndentation).append("if (!isinitialized) \(mutationFunctionNames.willMutate)()\n")
                    output.append(getterBodyIndentation).append("try {\n")
                    getIndentation = getterBodyIndentation.inc()
                }
                appendGetField(to: output, indentation: getIndentation, storage: storage, isSingleStatement: false)
                if let mutationFunctionNames, modifiers.isLazy {
                    output.append(getterBodyIndentation).append("} finally {\n")
                    output.append(getIndentation).append("if (!isinitialized) \(mutationFunctionNames.didMutate)()\n")
                    output.append(getterBodyIndentation).append("}\n")
                }
                output.append(getterIndentation).append("}\n")
            }
        }

        let setVisibilityString = modifiers.kotlinSetVisibilityString(isGlobal: role == .global, suffix: " ")
        let hasCustomSet = setter?.body != nil || willSet?.body != nil || didSet?.body != nil
        if hasCustomSet || mutationFunctionNames != nil {
            let isStoredOverride = getter?.body == nil && role == .superclassOverrideProperty
            let setterIndentation = indentation.inc()
            let setterBodyIndentation = setterIndentation.inc()
            output.append(setterIndentation).append(setVisibilityString).append("set(newValue) {\n")
            if mayBeSharedMutableStruct && !isStoredOverride {
                output.append(setterBodyIndentation).append("@Suppress(\"NAME_SHADOWING\") val newValue = newValue.sref()\n")
            }
            var setIndentation = setterBodyIndentation
            if let mutationFunctionNames, !isStoredOverride {
                output.append(setterBodyIndentation).append("\(mutationFunctionNames.willMutate)()\n")
                if hasCustomSet {
                    output.append(setterBodyIndentation).append("try {\n")
                    setIndentation = setIndentation.inc()
                }
            }
            
            if let willSetBody = willSet?.body {
                var willSetIndentation = setIndentation
                if let suppressSideEffectsPropertyName, !isStoredOverride {
                    output.append(setIndentation).append("if (!\(suppressSideEffectsPropertyName)) {\n")
                    willSetIndentation = willSetIndentation.inc()
                }
                if let parameterName = willSet?.parameterName, parameterName != "newValue" {
                    output.append(willSetIndentation).append("val \(parameterName) = newValue\n")
                }
                output.append(willSetBody, indentation: willSetIndentation)
                if suppressSideEffectsPropertyName != nil, !isStoredOverride {
                    output.append(setIndentation).append("}\n")
                }
            }
            
            if let setterBody = setter?.body {
                if let parameterName = setter?.parameterName, parameterName != "newValue" && parameterName != willSet?.parameterName {
                    output.append(setIndentation).append("val \(parameterName) = newValue\n")
                }
                output.append(setterBody, indentation: setIndentation)
            } else {
                if didSetUsesOldValue {
                    if isStoredOverride {
                        output.append(setIndentation).append("val oldValue = super.\(propertyName)\n")
                    } else if storage != nil {
                        output.append(setIndentation).append("val oldValue = this.\(propertyName)\n")
                    } else {
                        output.append(setIndentation).append("val oldValue = field\n")
                    }
                }
                if isStoredOverride {
                    output.append(setIndentation).append("super.\(propertyName) = newValue\n")
                } else {
                    appendSetField(to: output, indentation: setIndentation, storage: storage, isCopy: true)
                }
            }

            if let didSetBody = didSet?.body {
                var didSetIndentation = setIndentation
                if let suppressSideEffectsPropertyName, !isStoredOverride {
                    output.append(setIndentation).append("if (!\(suppressSideEffectsPropertyName)) {\n")
                    didSetIndentation = didSetIndentation.inc()
                }
                output.append(didSetBody, indentation: didSetIndentation)
                if suppressSideEffectsPropertyName != nil, !isStoredOverride {
                    output.append(setIndentation).append("}\n")
                }
            }

            if let mutationFunctionNames, !isStoredOverride {
                if hasCustomSet {
                    output.append(setterBodyIndentation).append("} finally {\n")
                    output.append(setterBodyIndentation.inc()).append("\(mutationFunctionNames.didMutate)()\n")
                    output.append(setterBodyIndentation).append("}\n")
                } else {
                    output.append(setterBodyIndentation).append("\(mutationFunctionNames.didMutate)()\n")
                }
            }
            output.append(setterIndentation).append("}\n")
        } else if (role.isProperty && role != .protocolProperty) || role == .global, apiFlags.contains(.writeable) || isAssignFromWriteable {
            if storage != nil || (mayBeSharedMutableStruct && apiFlags.contains(.writeable)) {
                let setterIndentation = indentation.inc()
                output.append(setterIndentation).append(setVisibilityString).append("set(newValue) {\n")
                appendSetField(to: output, indentation: setterIndentation.inc(), storage: storage, isCopy: false)
                output.append(setterIndentation).append("}\n")
            } else if !setVisibilityString.isEmpty {
                output.append(indentation.inc()).append(setVisibilityString).append("set\n")
            }
        }
    }

    /// Appends any initial value, starting with ` = ...`.
    @discardableResult func appendInitialValue(to output: OutputGenerator, indentation: Indentation) -> Bool {
        if let value {
            output.append(" = ")
            if isAsyncLet {
                output.append("Task { ")
            }
            output.append(value, indentation: indentation)
            if isAsyncLet {
                output.append(" }")
            }
            return true
        } else {
            // In Swift an optional var defaults to nil, but not so in Kotlin
            if (role.isProperty && role != .protocolProperty) || role == .global, declaredType.isOptional, !isLet, getter == nil {
                output.append(" = null")
                return true
            } else {
                return false
            }
        }
    }

    private func appendGetterBody(_ getterBody: KotlinCodeBlock, to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation).append("get()")
        if getterBody.isSingleStatementAppendable(mode: .function) {
            output.append(" = ")
            getterBody.appendAsSingleStatement(to: output, indentation: indentation, mode: .function)
            output.append("\n")
        } else {
            output.append(" {\n")
            output.append(getterBody, indentation: indentation.inc())
            output.append(indentation).append("}\n")
        }
    }

    private func appendGetField(to output: OutputGenerator, indentation: Indentation, storage: KotlinVariableStorage?, isSingleStatement: Bool) {
        let sref: () -> Void = apiFlags.contains(.writeable) && mayBeSharedMutableStruct ? { output.append(".sref(\(self.onUpdate?() ?? ""))") } : { }
        if let storage {
            storage.appendGet(self, sref, isSingleStatement, output, indentation)
        } else {
            if isSingleStatement {
                output.append("field")
            } else {
                output.append(indentation).append("return field")
            }
            sref()
            output.append("\n")
        }
    }

    private func appendSetField(to output: OutputGenerator, indentation: Indentation, storage: KotlinVariableStorage?, isCopy: Bool) {
        let appendValue: () -> Void
        if !isCopy && mayBeSharedMutableStruct {
            appendValue = { output.append("newValue.sref()") }
        } else {
            appendValue = { output.append("newValue") }
        }
        if let storage {
            storage.appendSet(self, appendValue, output, indentation)
        } else {
            output.append(indentation).append("field = ")
            appendValue()
            output.append("\n")
        }
    }

    private func initializeStorage() -> KotlinVariableStorage? {
        if let storage {
            return storage
        }
        guard !apiFlags.contains(.async) else {
            return nil
        }
        guard role == .property || role == .global else {
            return nil
        }

        var storagePrefix = ""
        if let extends {
            storagePrefix = extends.0.name
            if modifiers.isStatic {
                storagePrefix += "Companion"
            }
        }
        let name = "\(storagePrefix)\(propertyName)storage"

        // Lazy?
        if modifiers.isLazy {
            return KotlinVariableStorage(access: name) { variable, output, indentation in
                if variable.propertyType.kotlinIsNative(primitive: true) {
                    output.append(indentation).append("private var \(name) = \(variable.propertyType.kotlinDefaultValue ?? "")\n")
                } else {
                    output.append(indentation).append("private lateinit var \(name): \(variable.propertyType.kotlin)\n")
                }
            }
        }

        // Unwrapped optional with custom get and set logic?
        if declaredType.isUnwrappedOptional, (mayBeSharedMutableStruct && apiFlags.contains(.writeable)) || mutationFunctionNames != nil || getter?.body != nil || setter?.body != nil || willSet?.body != nil || didSet?.body != nil {
            if !apiFlags.contains(.writeable), let getterBody = getter?.body {
                return KotlinVariableStorage(access: name, isUnwrappedOptional: !propertyType.isOptional) { variable, output, indentation in
                    output.append(indentation).append("private val \(name): \(variable.propertyType.asOptional(true).kotlin)\n")
                    variable.appendGetterBody(getterBody, to: output, indentation: indentation.inc())
                }
            } else {
                return KotlinVariableStorage(access: name) { variable, output, indentation in
                    output.append(indentation).append("private lateinit var \(name): \(variable.propertyType.kotlin)\n")
                }
            }
        }

        // Stored static extension property that can't be moved into owning type?
        if extends != nil, modifiers.isStatic, getter?.body == nil || (apiFlags.contains(.writeable) && setter?.body == nil) {
            return KotlinVariableStorage(access: name, isUnwrappedOptional: propertyType.isUnwrappedOptional) { variable, output, indentation in
                output.append(indentation).append("private ")
                output.append(variable.apiFlags.contains(.writeable) ? "var " : "val ")
                output.append(name)
                if variable.declaredType != .none {
                    output.append(": ").append(variable.declaredType.kotlin)
                }
                if let value = variable.value {
                    output.append(" = ").append(value, indentation: indentation)
                } else if variable.declaredType.isOptional {
                    output.append(" = null")
                }
                output.append("\n")
            }
        }

        return nil
    }

    private var didSetUsesOldValue: Bool {
        guard let didSet = self.didSet?.body else {
            return false
        }
        var usesOldValue = false
        didSet.visit {
            if !usesOldValue, ($0 as? KotlinIdentifier)?.name == "oldValue" {
                usesOldValue = true
            }
            return usesOldValue ? .skip : .recurse(nil)
        }
        return usesOldValue
    }
}
