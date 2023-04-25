/// Types of Kotlin statements.
enum KotlinStatementType {
    case `break`
    case codeBlock
    case `continue`
    case `defer`
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
    case functionDeclaration
    case importDeclaration
    case interfaceDeclaration
    case typealiasDeclaration
    case variableDeclaration

    // Special statements
    case raw
    case message
}

class KotlinBreak: KotlinStatement {
    var label: String?
    var asReturn = false

    init(statement: Break) {
        self.label = statement.label
        super.init(type: .break, statement: statement)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation)
        if asReturn {
            output.append("return")
        } else {
            output.append("break")
        }
        if let label {
            output.append("@\(label)")
        }
        output.append("\n")
    }
}

class KotlinCodeBlock: KotlinStatement {
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
        var returnRequired = false
        var onUpdate: String? = nil
        var convertBreak = false
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
        case .labelIfBreak(let l):
            label = l
            convertBreak = true
        case .sref(let update):
            onUpdate = update
            sref = true
            returnRequired = true
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
                    if !convertBreak {
                        let returnStatement = statement as! KotlinReturn
                        didFindReturn = true
                        if let label {
                            returnStatement.label = label
                        }
                        if sref {
                            returnStatement.expression = returnStatement.expression?.sref(onUpdate: onUpdate)
                        }
                        return .skip
                    }
                case .break:
                    if convertBreak, let label {
                        let breakStatement = statement as! KotlinBreak
                        if breakStatement.label == nil {
                            breakStatement.label = label
                            breakStatement.asReturn = true
                            didFindReturn = true
                            return .skip
                        }
                    }
                case .functionDeclaration:
                    // Skip embedded functions that may have their own returns
                    return .skip
                case .forLoop, .whileLoop:
                    // Skip loops that may have their own breaks
                    if convertBreak {
                        return .skip
                    }
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
        if didFindReturn {
            return true
        }

        // If this was an implicit return, replace it with an explicit one if a return is required
        guard returnRequired, statements.count == 1, statements[0].type == .expression, var expression = (statements[0] as! KotlinExpressionStatement).expression else {
            return false
        }
        if sref {
            expression = expression.sref(onUpdate: onUpdate)
        }
        statements = [KotlinReturn(expression: expression)]
        return true
    }

    /// Perform any updates to handle references to the given `inout` parameter.
    func updateWithInOutParameter(name: String, source: Source) {
        visit { node in
            if let identifier = node as? KotlinIdentifier {
                if identifier.name == name {
                    identifier.isInOut = true
                }
            } else if let variableDeclaration = node as? KotlinVariableDeclaration {
                if variableDeclaration.names.contains(name) {
                    variableDeclaration.messages.append(.kotlinInOutParameterAssignment(variableDeclaration, source: source))
                }
            }
            return .recurse(nil)
        }
    }

    /// Add warning messages for attempts to assign to self.
    func addSelfAssignmentMessages(source: Source) {
        visit { node in
            if let binaryOperator = node as? KotlinBinaryOperator, binaryOperator.op.symbol == "=", let lhs = binaryOperator.lhs as? KotlinIdentifier, lhs.name == "self" {
                binaryOperator.messages.append(.kotlinSelfAssignment(binaryOperator, source: source))
                return .skip
            } else {
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
            output.append(bodyIndentation).append("val error = error.aserror()\n")
            appendCatchBody(kcatch, to: output, indentation: bodyIndentation)
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

    private func appendCatchBody(_ kcatch: KotlinCase, to output: OutputGenerator, indentation: Indentation) {
        for bindingVariable in kcatch.caseBindingVariables {
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

class KotlinForLoop: KotlinStatement {
    var identifierPatterns: [IdentifierPattern]
    var declaredType: TypeSignature = .none
    var sequence: KotlinExpression
    var whereGuard: KotlinExpression?
    var isNonNilMatch = false
    var body: KotlinCodeBlock

    static func translate(statement: ForLoop, translator: KotlinTranslator) -> KotlinForLoop {
        let ksequence = translator.translateExpression(statement.sequence)
        if statement.isAwait {
            KotlinAwait.setIsAsynchronous(ksequence)
        }
        let kbody = KotlinCodeBlock.translate(statement: statement.body, translator: translator)
        let kstatement = KotlinForLoop(statement: statement, sequence: ksequence, body: kbody)
        kstatement.declaredType = statement.declaredType
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

    init(expression: KotlinExpression) {
        super.init(type: .return, sourceFile: expression.sourceFile, sourceRange: expression.sourceRange)
        self.expression = expression
    }

    private init(statement: Return) {
        super.init(type: .return, statement: statement)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if let expression {
            output.append(indentation).append("return")
            if let label {
                output.append("@\(label)")
            }
            output.append(" ").append(expression, indentation: indentation).append("\n")
        } else {
            output.append(indentation).append("return")
            if let label {
                output.append("@\(label)")
            }
            output.append("\n")
        }
    }
}

class KotlinThrow: KotlinStatement {
    var error: KotlinExpression
    var errorIsThrowable = false

    static func translate(statement: Throw, translator: KotlinTranslator) -> KotlinThrow {
        let kerror = translator.translateExpression(statement.error)
        let kstatement = KotlinThrow(statement: statement, error: kerror)
        if let errorDeclarationType = translator.codebaseInfo?.declarationType(forNamed: statement.error.inferredType) {
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
        var caseTargetVariable: KotlinCaseTargetVariable? = nil
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
        kexpression.messages = messages
        return kexpression
    }

    private static func promotedBindingIdentifier(from kcatch: inout KotlinCase) -> String? {
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
    var body: KotlinCodeBlock
    var isDoWhile = false

    static func translate(statement: WhileLoop, translator: KotlinTranslator) -> KotlinWhileLoop {
        let (kconditions, caseBindingVariables, messages) = translate(conditions: statement.conditions, translator: translator)
        let kbody = KotlinCodeBlock.translate(statement: statement.body, translator: translator)
        let kstatement = KotlinWhileLoop(statement: statement, conditions: kconditions, caseBindingVariables: caseBindingVariables, body: kbody)
        kstatement.isDoWhile = statement.isRepeatWhile
        kstatement.messages += messages
        return kstatement
    }

    private static func translate(conditions: [Expression], translator: KotlinTranslator) -> ([KotlinExpression], [KotlinBindingVariable], [Message]) {
        var kconditions: [KotlinExpression] = []
        var caseBindingVariables: [KotlinBindingVariable] = []
        var messages: [Message] = []
        for condition in conditions {
            // We could copy the binding value from the condition in order to bind variables in the loop body, but this would cause
            // re-execution of the expression code, which could have side effects
            if let optionalBinding = condition as? OptionalBinding {
                let (variable, optionalCondition) = KotlinOptionalBinding.translate(expression: optionalBinding, translator: translator)
                kconditions.append(optionalCondition)
                if variable != nil {
                    messages.append(.kotlinLoopOptionalBinding(optionalBinding, source: translator.syntaxTree.source))
                }
            } else if let matchingCase = condition as? MatchingCase {
                let (targetVariable, bindingVariables, caseCondition) = KotlinMatchingCase.translate(expression: matchingCase, translator: translator)
                kconditions.append(caseCondition)
                caseBindingVariables += bindingVariables
                if targetVariable != nil {
                    messages.append(.kotlinLoopCaseValue(matchingCase, source: translator.syntaxTree.source))
                }
            } else {
                kconditions.append(translator.translateExpression(condition))
            }
        }
        return (kconditions, caseBindingVariables, messages)
    }

    private init(statement: WhileLoop, conditions: [KotlinExpression], caseBindingVariables: [KotlinBindingVariable], body: KotlinCodeBlock) {
        self.conditions = conditions
        self.caseBindingVariables = caseBindingVariables
        self.body = body
        super.init(type: .whileLoop, statement: statement)
    }

    override var children: [KotlinSyntaxNode] {
        return conditions + [body]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if isDoWhile {
            output.append(indentation).append("do {\n")
            output.append(body, indentation: indentation.inc())
            output.append(indentation).append("} while (")
            conditions.appendAsLogicalConditions(to: output, indentation: indentation)
            output.append(")\n")
        } else {
            output.append(indentation).append("while (")
            conditions.appendAsLogicalConditions(to: output, indentation: indentation)
            output.append(") {\n")
            let bodyIndentation = indentation.inc()
            for caseBindingVariable in caseBindingVariables {
                output.append(bodyIndentation)
                caseBindingVariable.append(to: output, indentation: bodyIndentation)
                output.append("\n")
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
    var superclassCall: String?
    var attributes = Attributes()
    var modifiers = Modifiers()
    var generics = Generics()
    var declarationType: StatementType
    var members: [KotlinStatement] = []
    var isConstructingPropertyName: String?
    var enumInheritedRawValueType: TypeSignature? {
        guard let inherits = inherits.first else {
            return nil
        }
        return inherits.isNumeric || inherits == .string ? inherits : nil
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

    static func translate(statement: TypeDeclaration, translator: KotlinTranslator) -> KotlinClassDeclaration {
        let kstatement = KotlinClassDeclaration(statement: statement)
        kstatement.inherits = statement.inherits
        kstatement.modifiers = statement.modifiers
        kstatement.generics = statement.generics
        if let owningTypeDeclaration = statement.parent?.owningTypeDeclaration, !owningTypeDeclaration.generics.isEmpty {
            kstatement.messages.append(.kotlinGenericTypeNested(statement, source: translator.syntaxTree.source))
        }
        kstatement.attributes = kstatement.processAttributes(statement.attributes, translator: translator)

        var members = statement.members.flatMap { translator.translateStatement($0) }
        if let codebaseInfo = translator.codebaseInfo {
            if let typeInfo = codebaseInfo.primaryTypeInfo(forNamed: statement.signature) {
                // Type info contains full resolved generics
                kstatement.signature = typeInfo.signature
                kstatement.inherits = typeInfo.inherits
                kstatement.generics = typeInfo.generics
            }

            // Move extensions of this type into the type itself rather than use Kotlin extension functions.
            // Kotlin extension functions act like static functions, which can lead to different behavior
            for (extInfo, extDeclaration) in codebaseInfo.extensions(of: statement.signature) where extDeclaration.canMoveIntoExtendedType {
                kstatement.inherits += extInfo.inherits
                members += extDeclaration.members.flatMap { translator.translateStatement($0) }
            }
        }
        kstatement.members = members
        if statement.type == .enumDeclaration {
            kstatement.processEnumCaseDeclarations()
        }

        kstatement.inherits.forEach { $0.appendKotlinMessages(to: kstatement, source: translator.syntaxTree.source) }
        return kstatement
    }

    private init(statement: TypeDeclaration) {
        self.name = statement.name
        self.signature = statement.signature
        self.declarationType = statement.type
        super.init(type: .classDeclaration, statement: statement)
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

    override func append(to output: OutputGenerator, indentation: Indentation) {
        let isSealedClassesEnum = isSealedClassesEnum
        if let declaration = extras?.declaration {
            output.append(indentation).append(declaration)
        } else {
            attributes.append(to: output, indentation: indentation)
            output.append(indentation)
            switch modifiers.visibility {
            case .default:
                fallthrough
            case .internal:
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
            generics.append(to: output, indentation: indentation, outParameters: isSealedClassesEnum)

            var inherits = inherits
            if let inheritedRawValueType = enumInheritedRawValueType {
                inherits = Array(inherits.dropFirst())
                // Add an unused parameter to disambiguate from the RawRepresentable constructor
                output.append("(override val rawValue: \(inheritedRawValueType.kotlin), unusedp: Nothing? = null)")
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
        enumCases.forEach { output.append($0, indentation: memberIndentation) }
        nonstaticMembers.forEach { output.append($0, indentation: memberIndentation) }

        if let isConstructingPropertyName {
            output.append("\n")
            output.append(memberIndentation).append("private var \(isConstructingPropertyName) = false\n")
        }

        // Always add a companion object to public types in case another module extends it with static members
        if !staticMembers.isEmpty || modifiers.visibility == .public || modifiers.visibility == .open || isSealedClassesEnum {
            output.append("\n")
            output.append(memberIndentation).append("companion object {\n")
            let companionMemberIndentation = memberIndentation.inc()
            if isSealedClassesEnum {
                enumCases.forEach { $0.appendSealedClassFactory(to: output, forEnum: name, alwaysCreateNewInstances: alwaysCreateNewSealedClassInstances, indentation: companionMemberIndentation) }
                if !staticMembers.isEmpty {
                    output.append("\n")
                }
            }
            staticMembers.forEach { output.append($0, indentation: companionMemberIndentation) }
            output.append(memberIndentation).append("}\n")
        }
        output.append(indentation).append("}\n")
    }

    private func processEnumCaseDeclarations() {
        guard declarationType == .enumDeclaration else {
            return
        }

        let caseDeclarations = members.compactMap { $0 as? KotlinEnumCaseDeclaration }
        let rawValueType = enumInheritedRawValueType
        var lastRawValueInt = -1
        for (index, caseDeclaration) in caseDeclarations.enumerated() {
            if let rawValueType {
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
                    caseDeclaration.rawValue = KotlinStringLiteral(literal: caseDeclaration.name)
                }
            }
            caseDeclaration.isLastDeclaration = index == caseDeclarations.count - 1
        }
    }
}

class KotlinEnumCaseDeclaration: KotlinStatement {
    var name: String
    var generics: Generics = Generics()
    var enumGenerics: Generics = Generics()
    var associatedValues: [Parameter<KotlinExpression>] = []
    var rawValue: KotlinExpression?
    var isLastDeclaration = false
    var members: [KotlinStatement] = []

    /// Return the name of the sealed class we create for the given enum case name in an enum with associated values.
    static func sealedClassName(for caseName: String) -> String {
        if let first = caseName.first, first.isLowercase {
            return first.uppercased() + caseName.dropFirst()
        }
        return caseName + "Case"
    }

    static func translate(statement: EnumCaseDeclaration, translator: KotlinTranslator) -> KotlinEnumCaseDeclaration {
        let kstatement = KotlinEnumCaseDeclaration(statement: statement)
        kstatement.associatedValues = statement.associatedValues.map { $0.translate(translator: translator) }
        kstatement.associatedValues.forEach { $0.declaredType.appendKotlinMessages(to: kstatement, source: translator.syntaxTree.source) }
        kstatement.rawValue = statement.rawValue.map { translator.translateExpression($0) }
        if let owningTypeDeclaration = statement.owningTypeDeclaration {
            let genericsEntries = owningTypeDeclaration.generics.entries.map { entry in
                if kstatement.associatedValues.contains(where: { $0.declaredType.referencesType(entry.namedType) }) {
                    return entry
                } else {
                    return Generic(name: entry.name, whereEqual: .named("Nothing", []))
                }
            }
            kstatement.enumGenerics = Generics(entries: genericsEntries)
            kstatement.generics = kstatement.enumGenerics.filterWhereEqual()
        }
        let _ = kstatement.processAttributes(statement.attributes, translator: translator)
        return kstatement
    }

    private init(statement: EnumCaseDeclaration) {
        self.name = statement.name
        super.init(type: .enumCaseDeclaration, statement: statement)
    }

    override func insertDependencies(into dependencies: inout KotlinDependencies) {
        if associatedValues.contains(where: { $0.declaredType.kotlinReferencesKClass }) {
            dependencies.insertReflect()
        }
    }

    override var children: [KotlinSyntaxNode] {
        var children: [KotlinSyntaxNode] = associatedValues.compactMap { $0.defaultValue }
        if let rawValue {
            children.append(rawValue)
        }
        return children + members
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation)
        if let declaration = extras?.declaration {
            output.append(declaration)
        } else if let owningClassDeclaration = parent as? KotlinClassDeclaration, owningClassDeclaration.isSealedClassesEnum {
            output.append("class \(Self.sealedClassName(for: name))")
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
            for (index, value) in associatedValues.enumerated() {
                if let label = value.externalLabel {
                    output.append(indentation.inc()).append("val \(label) = associated\(index)\n")
                }
            }
            if !members.isEmpty {
                output.append("\n")
                members.forEach { $0.append(to: output, indentation: indentation.inc()) }
            }
            output.append(indentation).append("}\n")
        } else {
            output.append(name)
            if let rawValue {
                output.append("(").append(rawValue, indentation: indentation).append(")")
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
        if associatedValues.isEmpty && !alwaysCreateNewInstances {
            output.append("val \(name): \(forEnum)")
            enumGenerics.append(to: output, indentation: indentation)
            output.append(" = \(Self.sealedClassName(for: name))")
            generics.appendWhere(to: output, indentation: indentation)
            output.append("()\n")
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
            output.append(" {\n")
            output.append(indentation.inc()).append("return \(Self.sealedClassName(for: name))(")
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
            output.append(indentation).append("}\n")
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
        // If the extension can't move into its extended type or is on a type outside this module, use Kotlin extension
        // functions. Otherwise do not translate the extension - instead we'll move its members into the extended type
        guard !statement.canMoveIntoExtendedType || translator.codebaseInfo?.declarationType(forNamed: statement.extends, mustBeInModule: true) == nil else {
            return []
        }

        var kotlinStatements: [KotlinStatement] = []
        if !statement.inherits.isEmpty && translator.codebaseInfo != nil {
            let message: Message
            if !statement.canMoveIntoExtendedType {
                message = Message.kotlinExtensionAddProtocolsToUnmovable(statement, source: translator.syntaxTree.source)
            } else {
                message = Message.kotlinExtensionAddProtocolsToOutsideType(statement, source: translator.syntaxTree.source)
            }
            kotlinStatements.append(KotlinMessageStatement(message: message, statement: statement))
        }
        var extends = statement.extends
        var generics = statement.generics
        if let extendedTypeInfo = translator.codebaseInfo?.primaryTypeInfo(forNamed: statement.extends) {
            // Set the extended type to match its primary type and put the complete set of constraints into the generics object
            extends = extendedTypeInfo.signature
            generics = extendedTypeInfo.generics.merge(extension: statement.extends, generics: statement.generics)
        }
        for member in statement.members {
            if !statement.canMoveIntoExtendedType {
                // Check that an extension that will be implemented as extension functions because it has generic constraints, etc is not
                // attempting to override member functions. Kotlin extension functions can never override members
                if let variableDeclaration = member as? VariableDeclaration, translator.codebaseInfo?.isImplementingMember(declaration: variableDeclaration, inExtension: extends, with: generics) == true {
                    kotlinStatements.append(KotlinMessageStatement(message: .kotlinExtensionImplementMember(member, source: translator.syntaxTree.source), statement: member))
                } else if let functionDeclaration = member as? FunctionDeclaration, translator.codebaseInfo?.isImplementingMember(declaration: functionDeclaration, inExtension: extends, with: generics) == true {
                    kotlinStatements.append(KotlinMessageStatement(message: .kotlinExtensionImplementMember(member, source: translator.syntaxTree.source), statement: member))
                }
            }
            for kmember in translator.translateStatement(member) {
                guard let memberDeclaration = kmember as? KotlinMemberDeclaration else {
                    kotlinStatements.append(KotlinMessageStatement(message: .kotlinExtensionUnsupportedMember(member, source: translator.syntaxTree.source), statement: member))
                    continue
                }
                guard kmember.type != .constructorDeclaration else {
                    kotlinStatements.append(KotlinMessageStatement(message: .kotlinExtensionAddConstructorsToOutsideType(member, source: translator.syntaxTree.source), statement: member))
                    continue
                }
                memberDeclaration.extends = (extends, generics)
                kotlinStatements.append(kmember)
            }
        }
        return kotlinStatements
    }
}

/// - Seealso: ``KotlinConstructorTransformer``
class KotlinFunctionDeclaration: KotlinStatement, KotlinMemberDeclaration {
    var name: String
    var returnType: TypeSignature = .void
    var parameters: [Parameter<KotlinExpression>] = []
    var isAsync = false
    var isOpen = false
    var isGlobal = false
    var isLocal = false
    var isOptionalInit = false
    var annotations: [String] = []
    var attributes = Attributes()
    var modifiers = Modifiers()
    var generics = Generics()
    var convertedGenerics: Generics? = nil
    var body: KotlinCodeBlock?
    var delegatingConstructorCall: KotlinExpression?
    var mutationFunctionNames: (willMutate: String, didMutate: String)?
    var disambiguatingParameterCount = 0
    var isGenerated = false
    var functionType: TypeSignature {
        return .function(parameters.map(\.signature), returnType)
    }
    var functionGenerics: Generics {
        get {
            if let convertedGenerics {
                return convertedGenerics
            }
            guard let extendsGenerics = extends?.1, !extendsGenerics.isEmpty else {
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
        return name == "hash" && !modifiers.isStatic && parameters.count == 1 && parameters[0].isInOut && parameters[0].declaredType == .named("Hasher", [])
    }
    var isLessThanImplementation: Bool {
        return name == "<" && modifiers.isStatic && parameters.count == 2
    }

    // KotlinMemberDeclaration
    var extends: (TypeSignature, Generics)? {
        didSet {
            if extends != nil {
                isOpen = false
            }
        }
    }
    var isStatic: Bool {
        return modifiers.isStatic && !isEqualImplementation && !isLessThanImplementation
    }

    static func translate(statement: FunctionDeclaration, translator: KotlinTranslator) -> KotlinFunctionDeclaration {
        let kstatement = KotlinFunctionDeclaration(statement: statement)
        kstatement.isAsync = statement.isAsync
        kstatement.isOptionalInit = statement.isOptionalInit
        kstatement.modifiers = statement.modifiers
        kstatement.generics = statement.generics
        kstatement.returnType = statement.returnType
        kstatement.parameters = statement.parameters.map { $0.translate(translator: translator) }
        kstatement.attributes = kstatement.processAttributes(statement.attributes, translator: translator)
        var owningDeclarationType: StatementType? = nil
        if statement.parent?.owningFunctionDeclaration != nil {
            kstatement.isLocal = true
        } else if let owningTypeDeclaration = statement.parent as? TypeDeclaration {
            // Use codebaseInfo rather than .type directly so that extension API is also handled correctly
            owningDeclarationType = translator.codebaseInfo?.declarationType(forNamed: owningTypeDeclaration.signature) ?? owningTypeDeclaration.type
            let owningSignature = translator.codebaseInfo?.primaryTypeInfo(forNamed: owningTypeDeclaration.signature)?.signature ?? owningTypeDeclaration.signature

            if statement.type == .initDeclaration {
                kstatement.isOpen = false
                kstatement.modifiers.isOverride = false // Kotlin does not override constructors
            } else {
                if owningDeclarationType == .protocolDeclaration {
                    // Kotlin uses default public visibility on all interface members
                    kstatement.modifiers.visibility = .public
                } else {
                    if !kstatement.modifiers.isOverride && translator.codebaseInfo?.isImplementingProtocolMember(declaration: statement, in: owningTypeDeclaration.signature) == true {
                        kstatement.modifiers.isOverride = true
                    }
                    kstatement.isOpen = !kstatement.modifiers.isOverride && !statement.modifiers.isFinal && statement.modifiers.visibility != .private && owningDeclarationType == .classDeclaration && !owningTypeDeclaration.modifiers.isFinal
                }
                // Kotlin does not all you to decrease visibility when overriding a member, so we simply make all overrides public to prevent errors
                if kstatement.modifiers.isOverride {
                    kstatement.modifiers.visibility = .public
                }
            }
            if !owningSignature.generics.isEmpty {
                // Kotlin companion objects do not have access to their type's generics, but we can create a generic function so long as the generic
                // is on a parameter rather than in the return type
                if kstatement.isStatic {
                    kstatement.convertToGenericFunction(owningTypeDeclaration, generics: owningSignature.generics, translator: translator)
                }
                // Kotlin does not allow a generic type to refer to itself without constraints
                let withoutGenerics: TypeSignature = .named(owningTypeDeclaration.name, [])
                kstatement.returnType = kstatement.returnType.mappingTypes(from: [withoutGenerics], to: [owningSignature])
                kstatement.parameters = kstatement.parameters.map {
                    var parameter = $0
                    parameter.declaredType = parameter.declaredType.mappingTypes(from: [withoutGenerics], to: [owningSignature])
                    return parameter
                }
            }
        } else if statement.isGlobal {
            kstatement.isGlobal = true
        }
        if let body = statement.body {
            kstatement.body = KotlinCodeBlock.translate(statement: body, translator: translator)
            kstatement.body?.updateWithExpectedReturn(statement.returnType == .void || statement.type == .initDeclaration ? .no : .sref(nil))
            for parameter in kstatement.parameters where parameter.isInOut {
                kstatement.body?.updateWithInOutParameter(name: parameter.internalLabel, source: translator.syntaxTree.source)
            }
        }
        kstatement.returnType.appendKotlinMessages(to: kstatement, source: translator.syntaxTree.source)
        kstatement.parameters.forEach { $0.declaredType.appendKotlinMessages(to: kstatement, source: translator.syntaxTree.source) }

        // Warnings and fixups
        if let firstCharacter = kstatement.name.first, firstCharacter != "_" && firstCharacter != "$" && firstCharacter != "`" && !firstCharacter.isLetter && !firstCharacter.isNumber && !kstatement.isEqualImplementation && !kstatement.isLessThanImplementation {
            kstatement.messages.append(.kotlinOperatorFunction(statement, source: translator.syntaxTree.source))
        }
        if owningDeclarationType == .protocolDeclaration {
            if statement.type == .initDeclaration {
                kstatement.messages.append(.kotlinProtocolConstructor(statement, source: translator.syntaxTree.source))
            } else if statement.modifiers.isStatic {
                kstatement.messages.append(.kotlinProtocolStaticMember(statement, source: translator.syntaxTree.source))
            }
        }
        return kstatement
    }

    init(name: String, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.name = name
        super.init(type: name == "constructor" ? .constructorDeclaration : .functionDeclaration, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(statement: FunctionDeclaration) {
        self.name = statement.type == .initDeclaration ? "constructor" : statement.name
        super.init(type: statement.type == .initDeclaration ? .constructorDeclaration : .functionDeclaration, statement: statement)
    }

    override func insertDependencies(into dependencies: inout KotlinDependencies) {
        if returnType.kotlinReferencesKClass || parameters.contains(where: { $0.declaredType.kotlinReferencesKClass }) {
            dependencies.insertReflect()
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
        if let declaration = extras?.declaration {
            output.append(indentation).append(declaration)
        } else {
            attributes.append(to: output, indentation: indentation)
            output.append(indentation)
            for annotation in annotations {
                output.append(annotation + " ")
            }
            if isEqualImplementation {
                appendEqualsDeclaration(to: output, indentation: indentation)
            } else if isLessThanImplementation {
                appendLessThanDeclaration(to: output, indentation: indentation)
            } else {
                appendFunctionDeclaration(to: output, indentation: indentation)
            }
        }
        if let body {
            output.append(" {\n")
            if !body.statements.isEmpty {
                if isEqualImplementation {
                    appendEqualsBody(body, to: output, indentation: indentation.inc())
                } else if isLessThanImplementation {
                    appendLessThanBody(body, to: output, indentation: indentation.inc())
                } else {
                    appendFunctionBody(body, to: output, indentation: indentation.inc())
                }
            }
            output.append(indentation).append("}\n")
        } else {
            output.append("\n")
        }
    }

    private func appendFunctionDeclaration(to output: OutputGenerator, indentation: Indentation) {
        if !isLocal {
            output.append(modifiers.kotlinMemberString(isOpen: isOpen, suffix: " "))
        }
        if isAsync {
            output.append("suspend ")
        }

        if type != .constructorDeclaration {
            output.append("fun ")
        }
        let generics = functionGenerics.filterWhereEqual()
        if !generics.isEmpty {
            generics.append(to: output, indentation: indentation)
            output.append(" ")
        }
        appendExtends(to: output, indentation: indentation)
        output.append(name).append("(")
        for (index, parameter) in parameters.enumerated() {
            if parameter.isVariadic {
                output.append("varargs ")
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
            output.append("unusedp_\(i): Nothing?")
            if !modifiers.isOverride {
                output.append(" = null")
            }
            if i != disambiguatingParameterCount - 1 {
                output.append(", ")
            }
        }
        output.append(")")
        if type != .constructorDeclaration {
            if returnType != .void && type != .constructorDeclaration {
                output.append(": ").append(returnType.kotlin)
            }
        } else if let delegatingConstructorCall {
            output.append(": ").append(delegatingConstructorCall, indentation: indentation)
        }
        functionGenerics.appendWhere(to: output, indentation: indentation)
    }

    private func appendFunctionBody(_ body: KotlinCodeBlock, to output: OutputGenerator, indentation: Indentation) {
        for parameter in parameters {
            if let externalLabel = parameter.externalLabel, parameter.internalLabel != parameter.externalLabel {
                output.append(indentation).append("val \(parameter.internalLabel) = \(externalLabel)\n")
            }
        }
        if type == .constructorDeclaration, let isConstructingPropertyName = (parent as? KotlinClassDeclaration)?.isConstructingPropertyName {
            output.append(indentation).append("\(isConstructingPropertyName) = true\n")
            body.syntheticFinally = "\(isConstructingPropertyName) = false"
        } else if let mutationFunctionNames {
            output.append(indentation).append("\(mutationFunctionNames.willMutate)()\n")
            body.syntheticFinally = "\(mutationFunctionNames.didMutate)()"
        }
        output.append(body, indentation: indentation)
    }

    private func appendEqualsDeclaration(to output: OutputGenerator, indentation: Indentation) {
        output.append("override fun equals(other: Any?): Boolean")
    }

    private func appendEqualsBody(_ body: KotlinCodeBlock, to output: OutputGenerator, indentation: Indentation) {
        let anyGenerics = parameters[1].declaredType.generics.map { _ in TypeSignature.named("*", []) }
        output.append(indentation).append("if (other !is \(parameters[1].declaredType.withGenerics(anyGenerics).kotlin)) {\n")
        output.append(indentation.inc()).append("return false\n")
        output.append(indentation).append("}\n")
        output.append(indentation).append("val \(parameters[0].internalLabel) = this\n")
        output.append(indentation).append("val \(parameters[1].internalLabel) = other\n")
        output.append(body, indentation: indentation)
    }

    private func appendLessThanDeclaration(to output: OutputGenerator, indentation: Indentation) {
        output.append("override fun compareTo(other: \(parameters[0].declaredType.kotlin)): Int")
    }

    private func appendLessThanBody(_ body: KotlinCodeBlock, to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation).append("if (this == other) return 0\n")
        output.append(indentation).append("fun islessthan(\(parameters[0].internalLabel): \(parameters[0].declaredType.kotlin), \(parameters[1].internalLabel): \(parameters[1].declaredType.kotlin)): Boolean {\n")
        output.append(body, indentation: indentation.inc())
        output.append(indentation).append("}\n")
        output.append(indentation).append("return if (islessthan(this, other)) -1 else 1\n")
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
        output.append(KotlinTranslator.packageName(forModule: modulePath[0]))
        if modulePath.count == 1 {
            output.append(".*")
        } else {
            output.append(".").append(modulePath[1...].joined(separator: "."))
        }
        output.append("\n")
    }
}

class KotlinInterfaceDeclaration: KotlinStatement {
    var name: String
    var signature: TypeSignature
    var inherits: [TypeSignature] = []
    var modifiers = Modifiers()
    var generics = Generics()
    var members: [KotlinStatement] = []

    static func translate(statement: TypeDeclaration, translator: KotlinTranslator) -> KotlinInterfaceDeclaration {
        let kstatement = KotlinInterfaceDeclaration(statement: statement)
        kstatement.modifiers = statement.modifiers
        kstatement.inherits = statement.inherits
        kstatement.generics = statement.generics
        kstatement.members = statement.members.flatMap { translator.translateStatement($0) }
        kstatement.inherits.forEach { $0.appendKotlinMessages(to: kstatement, source: translator.syntaxTree.source) }
        guard let codebaseInfo = translator.codebaseInfo else {
            return kstatement
        }

        if let typeInfo = codebaseInfo.primaryTypeInfo(forNamed: statement.signature) {
            // Type info contains full resolved generics
            kstatement.signature = typeInfo.signature
            kstatement.inherits = typeInfo.inherits
            kstatement.generics = typeInfo.generics
        }

        // Move extensions of this type into the type itself rather than use Kotlin extension functions.
        // This allows us to replace API declarations with implementations. Also Kotlin extension functions
        // act like static functions, which can lead to different behavior
        var originalMembers = kstatement.members
        var newMembers: [KotlinStatement] = []
        for (extInfo, extDeclaration) in codebaseInfo.extensions(of: statement.signature) where extDeclaration.canMoveIntoExtendedType {
            kstatement.inherits += extInfo.inherits
            for extMember in extDeclaration.members.flatMap({ translator.translateStatement($0) }) {
                if !replaceMember(in: &originalMembers, with: extMember) {
                    newMembers.append(extMember)
                }
            }
        }
        kstatement.members = originalMembers + newMembers
        return kstatement
    }

    private static func replaceMember(in originalMembers: inout [KotlinStatement], with member: KotlinStatement) -> Bool {
        for i in 0..<originalMembers.count {
            guard originalMembers[i].type == member.type else {
                continue
            }
            if let originalVariableDeclaration = originalMembers[i] as? KotlinVariableDeclaration, let variableDeclaration = member as? KotlinVariableDeclaration {
                if originalVariableDeclaration.names == variableDeclaration.names {
                    originalMembers[i] = member
                    return true
                }
            } else if let originalFunctionDeclaration = originalMembers[i] as? KotlinFunctionDeclaration, let functionDeclaration = member as? KotlinFunctionDeclaration {
                if originalFunctionDeclaration.name == functionDeclaration.name && originalFunctionDeclaration.functionType == functionDeclaration.functionType {
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

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation)
        if let declaration = extras?.declaration {
            output.append(declaration)
        } else {
            switch modifiers.visibility {
            case .default:
                fallthrough
            case .internal:
                output.append("internal ")
            case .open:
                fallthrough
            case .public:
                output.append("public ")
            case .private:
                output.append("private ")
            }
            output.append("interface ").append(name)
            generics.append(to: output, indentation: indentation)
            if !inherits.isEmpty {
                output.append(": ").append(inherits.map(\.kotlin).joined(separator: ", "))
            }
            generics.appendWhere(to: output, indentation: indentation)
        }
        output.append(" {\n")
        children.forEach { output.append($0, indentation: indentation.inc()) }
        output.append(indentation).append("}\n")
    }
}

class KotlinTypealiasDeclaration: KotlinStatement, KotlinMemberDeclaration {
    var name: String
    var attributes = Attributes()
    var modifiers = Modifiers()
    var generics = Generics()
    var aliasedType: TypeSignature = .none

    // KotlinMemberDeclaration
    var extends: (TypeSignature, Generics)?
    var isStatic: Bool {
        return false
    }

    static func translate(statement: TypealiasDeclaration, translator: KotlinTranslator) -> KotlinTypealiasDeclaration? {
        let kstatement = KotlinTypealiasDeclaration(statement: statement)
        kstatement.modifiers = statement.modifiers
        kstatement.generics = statement.generics
        kstatement.aliasedType = statement.aliasedType
        kstatement.attributes = kstatement.processAttributes(statement.attributes, translator: translator)

        var isNested = false
        if statement.owningFunctionDeclaration != nil {
            isNested = true
        } else if let owningTypeDeclaration = statement.owningTypeDeclaration {
            // This might be a typealias that specifies one of our protocol's associatedtypes. But we can only detect that case if we have full
            // codebase info, which we don't have during pre-checks. Compromise and warn if the typealias is used anywhere in our API
            if owningTypeDeclaration.type == .protocolDeclaration || owningTypeDeclaration.inherits.isEmpty {
                isNested = true
            } else if let codebaseInfo = translator.codebaseInfo {
                let protocolSignatures = codebaseInfo.global.protocolSignatures(forNamed: owningTypeDeclaration.signature)
                if protocolSignatures.contains(where: { $0.generics.contains { $0.name == statement.name } }) {
                    return nil
                } else {
                    isNested = true
                }
            } else {
                for member in owningTypeDeclaration.members {
                    if memberDeclaration(member, usesTypealias: statement.name) {
                        isNested = true
                        break
                    }
                }
            }
        }
        if isNested {
            kstatement.messages.append(.kotlinTypeAliasNested(statement, source: translator.syntaxTree.source))
        }
        if statement.generics.entries.contains(where: { !$0.inherits.isEmpty || $0.whereEqual != nil }) {
            kstatement.messages.append(.kotlinTypeAliasConstrainedGenerics(statement, source: translator.syntaxTree.source))
        }
        return kstatement
    }

    /// Check whether the given member uses the given type.
    ///
    /// - Note: This is not a comprehensive check.
    private static func memberDeclaration(_ member: Statement, usesTypealias aliasName: String) -> Bool {
        let aliasType: TypeSignature = .named(aliasName, [])
        if let variableDeclaration = member as? VariableDeclaration {
            return variableDeclaration.variableTypes.contains { $0.referencesType(aliasType) }
        } else if let functionDeclaration = member as? FunctionDeclaration {
            return functionDeclaration.functionType.referencesType(aliasType)
        } else {
            return false
        }
    }

    private init(statement: TypealiasDeclaration) {
        self.name = statement.name
        super.init(type: .typealiasDeclaration, statement: statement)
    }

    override func insertDependencies(into dependencies: inout KotlinDependencies) {
        if aliasedType.kotlinReferencesKClass {
            dependencies.insertReflect()
        }
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if let declaration = extras?.declaration {
            output.append(indentation).append(declaration).append("\n")
        } else {
            attributes.append(to: output, indentation: indentation)
            output.append(indentation).append(modifiers.kotlinMemberString(isOpen: false, suffix: " "))
            output.append("typealias ").append(name)
            generics.append(to: output, indentation: indentation)
            output.append(" = ").append(aliasedType.kotlin).append("\n")
        }
    }
}

class KotlinVariableDeclaration: KotlinStatement, KotlinMemberDeclaration {
    var names: [String?]
    var declaredType: TypeSignature = .none
    var isLet = false
    var isAsync = false
    var isProperty = false
    var isProtocolProperty = false
    var isGlobal = false
    var isOpen = false
    var modifiers = Modifiers()
    var attributes = Attributes()
    var value: KotlinExpression?
    var getter: Accessor<KotlinCodeBlock>?
    var setter: Accessor<KotlinCodeBlock>?
    var willSet: Accessor<KotlinCodeBlock>?
    var didSet: Accessor<KotlinCodeBlock>?
    var variableTypes: [TypeSignature]
    var mayBeSharedMutableStruct = false
    var isReadOnly = false
    var onUpdate: String?
    var isConstructingPropertyName: String?
    var mutationFunctionNames: (willMutate: String, didMutate: String)?
    var isGenerated = false
    var isDescriptionImplementation: Bool {
        return isProperty && names == ["description"] && variableTypes == [.string]
    }

    // KotlinMemberDeclaration
    var extends: (TypeSignature, Generics)? {
        didSet {
            if extends != nil {
                isOpen = false
            }
        }
    }
    var isStatic: Bool {
        return modifiers.isStatic
    }

    static func translate(statement: VariableDeclaration, translator: KotlinTranslator) -> KotlinVariableDeclaration {
        let kstatement = KotlinVariableDeclaration(statement: statement)
        kstatement.isLet = statement.isLet
        kstatement.isAsync = statement.isAsync
        kstatement.modifiers = statement.modifiers
        kstatement.declaredType = statement.declaredType
        var owningDeclarationType: StatementType? = nil
        if let owningTypeDeclaration = statement.parent as? TypeDeclaration {
            // Use codebaseInfo rather than .type directly so that extension API is also handled correctly
            owningDeclarationType = translator.codebaseInfo?.declarationType(forNamed: owningTypeDeclaration.signature) ?? owningTypeDeclaration.type
            let owningSignature = translator.codebaseInfo?.primaryTypeInfo(forNamed: owningTypeDeclaration.signature)?.signature ?? owningTypeDeclaration.signature

            kstatement.isProperty = true
            if owningDeclarationType == .protocolDeclaration {
                kstatement.isProtocolProperty = true
                // Kotlin uses default public visibility on all interface members
                kstatement.modifiers.visibility = .public
            } else {
                if !kstatement.modifiers.isOverride && translator.codebaseInfo?.isImplementingProtocolMember(declaration: statement, in: owningTypeDeclaration.signature) == true {
                    kstatement.modifiers.isOverride = true
                }
                kstatement.isOpen = !kstatement.modifiers.isOverride && !statement.modifiers.isFinal && statement.modifiers.visibility != .private && owningDeclarationType == .classDeclaration && !owningTypeDeclaration.modifiers.isFinal
            }
            // Kotlin does not all you to decrease visibility when overriding a member, so we simply make all overrides public to prevent errors
            if kstatement.modifiers.isOverride {
                kstatement.modifiers.visibility = .public
            }
            if !owningSignature.generics.isEmpty {
                if kstatement.isStatic && owningSignature.generics.contains(where: { kstatement.declaredType.referencesType($0) }) {
                    kstatement.messages.append(.kotlinGenericStaticMember(kstatement, source: translator.syntaxTree.source))
                } else if kstatement.isStatic && owningTypeDeclaration.type == .extensionDeclaration && !owningTypeDeclaration.generics.isEmpty {
                    kstatement.messages.append(.kotlinGenericExtensionStaticMember(kstatement, source: translator.syntaxTree.source))
                }
                // Kotlin does not allow a generic type to refer to itself without constraints
                let withoutGenerics: TypeSignature = .named(owningTypeDeclaration.name, [])
                kstatement.declaredType = kstatement.declaredType.mappingTypes(from: [withoutGenerics], to: [owningSignature])
            }
        } else if statement.isGlobal {
            kstatement.isGlobal = true
        }
        if let value = statement.value {
            // Kotlin does not call the setter for the assigned initial value, so sref() ourselves
            kstatement.value = translator.translateExpression(value).sref()
        }

        kstatement.attributes = kstatement.processAttributes(statement.attributes, translator: translator)
        kstatement.isReadOnly = statement.isLet || (statement.getter != nil && statement.setter == nil)
        if kstatement.declaredType != .none {
            kstatement.mayBeSharedMutableStruct = statement.constrainedDeclaredType.kotlinMayBeSharedMutableStruct(codebaseInfo: translator.codebaseInfo)
        } else if let kvalue = kstatement.value {
            kstatement.mayBeSharedMutableStruct = kvalue.mayBeSharedMutableStructExpression(orType: true)
        } else {
            kstatement.mayBeSharedMutableStruct = true
        }
        if kstatement.mayBeSharedMutableStruct {
            kstatement.onUpdate = kstatement.isReadOnly ? nil : kstatement.isProperty ? "{ this.\(kstatement.names[0] ?? "") = it }" : "{ \(kstatement.names[0] ?? "") = it }"
            kstatement.getter = statement.getter?.translate(translator: translator, expectedReturn: .sref(kstatement.onUpdate))
        } else {
            kstatement.getter = statement.getter?.translate(translator: translator, expectedReturn: .yes)
        }
        kstatement.setter = statement.setter?.translate(translator: translator, expectedReturn: .no)
        kstatement.willSet = statement.willSet?.translate(translator: translator, expectedReturn: .no)
        kstatement.didSet = statement.didSet?.translate(translator: translator, expectedReturn: .no)

        // Warnings and fixups
        kstatement.declaredType.appendKotlinMessages(to: kstatement, source: translator.syntaxTree.source)
        if statement.isAsync {
            kstatement.messages.append(.kotlinAsyncProperties(kstatement, source: translator.syntaxTree.source))
        }
        if owningDeclarationType == .protocolDeclaration {
            if statement.modifiers.isStatic {
                kstatement.messages.append(.kotlinProtocolStaticMember(statement, source: translator.syntaxTree.source))
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
        self.variableTypes = statement.variableTypes
        super.init(type: .variableDeclaration, statement: statement)
    }

    override func insertDependencies(into dependencies: inout KotlinDependencies) {
        if declaredType.kotlinReferencesKClass {
            dependencies.insertReflect()
        }
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
        if let declaration = extras?.declaration {
            output.append(indentation).append(declaration)
        } else if names.count == 1 && names[0] == nil {
            // Kotlin doesn't support assignment to wildcard
            if let value {
                output.append(indentation).append(value, indentation: indentation)
            }
        } else {
            attributes.append(to: output, indentation: indentation)
            output.append(indentation)
            if isProperty || isGlobal {
                // We can't override stored properties in Swift, so only need to mark open if computed
                output.append(modifiers.kotlinMemberString(isOpen: isOpen && getter != nil, suffix: " "))
                if case .unwrappedOptional = declaredType {
                    output.append("lateinit ")
                }
            }
            if isReadOnly {
                output.append("val ")
            } else {
                output.append("var ")
            }
            if let generics = extends?.1.filterWhereEqual(), !generics.isEmpty {
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

            if declaredType != .none {
                output.append(": ").append(declaredType.kotlin)
            }
            if let value {
                output.append(" = ").append(value, indentation: indentation)
            } else {
                // In Swift an optional var defaults to nil, but not so in Kotlin
                if (isProperty || isGlobal), !isProtocolProperty, declaredType.isOptional, !isLet, getter == nil {
                    output.append(" = null")
                }
            }
            extends?.1.appendWhere(to: output, indentation: indentation)
        }
        output.append("\n")

        if let getterBody = getter?.body {
            let getterIndentation = indentation.inc()
            output.append(getterIndentation).append("get() {\n")
            output.append(getterBody, indentation: getterIndentation.inc())
            output.append(getterIndentation).append("}\n")
        } else if mayBeSharedMutableStruct && (isProperty || isGlobal) && !isProtocolProperty {
            let getterIndentation = indentation.inc()
            output.append(getterIndentation).append("get() {\n")
            output.append(getterIndentation.inc()).append("return field.sref(\(onUpdate ?? ""))\n")
            output.append(getterIndentation).append("}\n")
        }

        let hasCustomSet = setter?.body != nil || willSet?.body != nil || didSet?.body != nil
        if hasCustomSet || mutationFunctionNames != nil {
            let setterIndentation = indentation.inc()
            let setterBodyIndentation = setterIndentation.inc()
            output.append(setterIndentation).append("set(newValue) {\n")
            if mayBeSharedMutableStruct {
                output.append(setterBodyIndentation).append("val newValue = newValue.sref()\n")
            }
            var setIndentation = setterBodyIndentation
            if let mutationFunctionNames {
                output.append(setterBodyIndentation).append("\(mutationFunctionNames.willMutate)()\n")
                if hasCustomSet {
                    output.append(setterBodyIndentation).append("try {\n")
                    setIndentation = setIndentation.inc()
                }
            }

            if let willSetBody = willSet?.body {
                var willSetIndentation = setIndentation
                if let isConstructingPropertyName {
                    output.append(setIndentation).append("if (!\(isConstructingPropertyName)) {\n")
                    willSetIndentation = willSetIndentation.inc()
                }
                if let parameterName = willSet?.parameterName, parameterName != "newValue" {
                    output.append(willSetIndentation).append("val \(parameterName) = newValue\n")
                }
                output.append(willSetBody, indentation: willSetIndentation)
                if isConstructingPropertyName != nil {
                    output.append(setIndentation).append("}\n")
                }
            }

            if let setterBody = setter?.body {
                if let parameterName = setter?.parameterName, parameterName != "newValue" && parameterName != willSet?.parameterName {
                    output.append(setIndentation).append("val \(parameterName) = newValue\n")
                }
                output.append(setterBody, indentation: setIndentation)
            } else {
                if didSet?.body != nil {
                    output.append(setIndentation).append("val oldValue = field\n")
                }
                output.append(setIndentation).append("field = newValue\n")
            }

            if let didSetBody = didSet?.body {
                var didSetIndentation = setIndentation
                if let isConstructingPropertyName {
                    output.append(setIndentation).append("if (!\(isConstructingPropertyName)) {\n")
                    didSetIndentation = didSetIndentation.inc()
                }
                output.append(didSetBody, indentation: didSetIndentation)
                if isConstructingPropertyName != nil {
                    output.append(setIndentation).append("}\n")
                }
            }
            if let mutationFunctionNames {
                if hasCustomSet {
                    output.append(setterBodyIndentation).append("} finally {\n")
                    output.append(setterBodyIndentation.inc()).append("\(mutationFunctionNames.didMutate)()\n")
                    output.append(setterBodyIndentation).append("}\n")
                } else {
                    output.append(setterBodyIndentation).append("\(mutationFunctionNames.didMutate)()\n")
                }
            }
            output.append(setterIndentation).append("}\n")
        } else if !isReadOnly && mayBeSharedMutableStruct && (isProperty || isGlobal) && !isProtocolProperty {
            let setterIndentation = indentation.inc()
            output.append(setterIndentation).append("set(newValue) {\n")
            output.append(setterIndentation.inc()).append("field = newValue.sref()\n")
            output.append(setterIndentation).append("}\n")
        }
    }
}
