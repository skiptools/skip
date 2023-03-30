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
            // TODO: We could attempt to identify more re-bindings of the identifier
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

    override var children: [KotlinSyntaxNode] {
        return statements + catches.flatMap { $0.children }
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
        if kcatch.patterns.isEmpty {
            output.append(indentation).append("} catch (error: Throwable) {\n")
            appendCatchBody(kcatch, to: output, indentation: indentation.inc())
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
                appendCatchBody(kcatch, to: output, indentation: indentation.inc())
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
        let ktarget = translator.translateStatement(statement.target).first ?? KotlinMessageStatement(message: .kotlinUntranslatable(statement, source: translator.syntaxTree.source))
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

    static func translate(statement: Throw, translator: KotlinTranslator) -> KotlinThrow {
        let kerror = translator.translateExpression(statement.error)
        return KotlinThrow(statement: statement, error: kerror)
    }

    private init(statement: Throw, error: KotlinExpression) {
        self.error = error
        super.init(type: .throw, statement: statement)
    }

    override var children: [KotlinSyntaxNode] {
        return [error]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation).append("throw ").append(error, indentation: indentation).append("\n")
    }
}

class KotlinTryCatch: KotlinStatement {
    var body: KotlinCodeBlock

    static func translate(statement: DoCatch, translator: KotlinTranslator) -> KotlinTryCatch {
        let matchOn = KotlinIdentifier(name: "error")
        matchOn.isLocalIdentifier = true
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

    static func translate(statement: TypeDeclaration, translator: KotlinTranslator) -> KotlinClassDeclaration {
        let kstatement = KotlinClassDeclaration(statement: statement)
        kstatement.inherits = statement.inherits
        kstatement.modifiers = statement.modifiers
        kstatement.generics = statement.generics
        var members = statement.members.flatMap { translator.translateStatement($0) }
        // Move extensions of this type into the type itself rather than use Kotlin extension functions.
        // Kotlin extension functions act like static functions, which can lead to different behavior
        if let codebaseInfo = translator.codebaseInfo {
            for ext in codebaseInfo.extensions(of: statement.signature) {
                kstatement.inherits += ext.inherits
                members += ext.members.flatMap { translator.translateStatement($0) }
            }
        }
        kstatement.members = members
        kstatement.processEnumCaseDeclarations()
        kstatement.inherits.forEach { $0.appendKotlinMessages(to: kstatement, source: translator.syntaxTree.source) }
        if statement.attributes.attributes.contains(where: { !isIgnorable(attribute: $0) }) {
            kstatement.messages.append(.kotlinAttributeUnsupported(statement, source: translator.syntaxTree.source))
        }
        return kstatement
    }

    private static func isIgnorable(attribute: Attribute) -> Bool {
        switch attribute.signature {
        case .named(let name, _):
            return name == "indirect"
        default:
            return false
        }
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

    override func append(to output: OutputGenerator, indentation: Indentation) {
        let isSealedClassesEnum = isSealedClassesEnum
        output.append(indentation)
        if let declaration = extras?.declaration {
            output.append(declaration)
        } else {
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

            var inherits = inherits
            if declarationType == .enumDeclaration {
                if isSealedClassesEnum {
                    output.append("sealed class ").append(name)
                } else {
                    output.append("enum class ").append(name)
                }
            } else {
                output.append("class ").append(name)
            }
            generics.append(to: output, indentation: indentation)
            if let inheritedRawValueType = enumInheritedRawValueType {
                inherits = Array(inherits.dropFirst())
                output.append("(val rawValue: \(inheritedRawValueType.kotlin))")
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
                //~~~ Interfaces need generic types specified
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
                enumCases.forEach { $0.appendSealedClassFactory(to: output, forEnum: name, forced: forceSealedClassesEnum, indentation: companionMemberIndentation) }
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
    var associatedValues: [Parameter<KotlinExpression>] = []
    var rawValue: KotlinExpression?
    var isLastDeclaration = false

    /// Return the name of the sealed class we create for the given enum case name in an enum with associated values.
    static func sealedClassName(for caseName: String) -> String {
        return caseName + "case"
    }

    static func translate(statement: EnumCaseDeclaration, translator: KotlinTranslator) -> KotlinEnumCaseDeclaration {
        let kstatement = KotlinEnumCaseDeclaration(statement: statement)
        kstatement.associatedValues = statement.associatedValues.map { $0.translate(translator: translator) }
        kstatement.associatedValues.forEach { $0.declaredType.appendKotlinMessages(to: kstatement, source: translator.syntaxTree.source) }
        kstatement.rawValue = statement.rawValue.map { translator.translateExpression($0) }
        if !statement.attributes.isEmpty {
            kstatement.messages.append(.kotlinAttributeUnsupported(statement, source: translator.syntaxTree.source))
        }
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
        return children
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation)
        if let declaration = extras?.declaration {
            output.append(declaration)
        } else if let owningClassDeclaration = parent as? KotlinClassDeclaration, owningClassDeclaration.isSealedClassesEnum {
            output.append("class \(Self.sealedClassName(for: name))")
            if !associatedValues.isEmpty {
                appendAssociatedValueArguments(to: output, asConstructor: true, indentation: indentation)
            }
            output.append(": \(owningClassDeclaration.name)")
            if let rawValue {
                output.append("(").append(rawValue, indentation: indentation).append(") {\n")
            } else {
                output.append("() {\n")
            }
            for (index, value) in associatedValues.enumerated() {
                if let label = value.externalLabel {
                    output.append(indentation.inc()).append("val \(label) = associated\(index)\n")
                }
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

    func appendSealedClassFactory(to output: OutputGenerator, forEnum: String, forced: Bool, indentation: Indentation) {
        output.append(indentation)
        // For cases where the sealed class enum is forced, we always create a new instance b/c we assume some transient state may be added,
        // e.g. the stack trace in the case of Error enums
        if associatedValues.isEmpty && !forced {
            output.append("val \(name): \(forEnum) = \(Self.sealedClassName(for: name))()\n")
        } else {
            output.append("fun \(name)")
            appendAssociatedValueArguments(to: output, asConstructor: false, indentation: indentation)
            output.append(": \(forEnum) {\n")
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
        // If the extension is on a type outside this module or only applies to certain generic constraints, use Kotlin extension
        // functions. Otherwise do not translate the extension - instead we'll move its members into the extended type
        guard statement.generics.whereEqual.isEmpty, translator.codebaseInfo?.declarationType(of: statement.extends, mustBeInModule: true) == nil else {
            return []
        }

        let extends = statement.extends.withGenerics(statement.generics)
        var kotlinStatements: [KotlinStatement] = []
        if !statement.inherits.isEmpty && translator.codebaseInfo != nil {
            let message = Message.kotlinExtensionAddProtocolsToOutsideType(statement, source: translator.syntaxTree.source)
            kotlinStatements.append(KotlinMessageStatement(message: message))
        }
        for member in statement.members {
            if !statement.generics.whereEqual.isEmpty {
                if let variableDeclaration = member as? VariableDeclaration, translator.codebaseInfo?.isProtocolMember(declaration: variableDeclaration, in: extends) == true {
                    kotlinStatements.append(KotlinMessageStatement(message: .kotlinExtensionForConstrainedGenericImplementMember(member, source: translator.syntaxTree.source)))
                } else if let functionDeclaration = member as? FunctionDeclaration, translator.codebaseInfo?.isProtocolMember(declaration: functionDeclaration, in: extends) == true {
                    kotlinStatements.append(KotlinMessageStatement(message: .kotlinExtensionForConstrainedGenericImplementMember(member, source: translator.syntaxTree.source)))
                }
            }
            for kmember in translator.translateStatement(member) {
                guard let memberDeclaration = kmember as? KotlinMemberDeclaration else {
                    kotlinStatements.append(KotlinMessageStatement(message: .kotlinExtensionUnsupportedMember(member, source: translator.syntaxTree.source)))
                    continue
                }
                guard kmember.type != .constructorDeclaration else {
                    kotlinStatements.append(KotlinMessageStatement(message: .kotlinExtensionAddConstructorsToOutsideType(member, source: translator.syntaxTree.source)))
                    continue
                }
                memberDeclaration.extends = extends
                kotlinStatements.append(kmember)
            }
        }
        return kotlinStatements
    }
}

/// - Seealso: ``KotlinConstructorPlugin``
class KotlinFunctionDeclaration: KotlinStatement, KotlinMemberDeclaration {
    var name: String
    var returnType: TypeSignature = .void
    var parameters: [Parameter<KotlinExpression>] = []
    var isAsync = false
    var isOpen = false
    var isGlobal = false
    var modifiers = Modifiers()
    var body: KotlinCodeBlock?
    var delegatingConstructorCall: KotlinExpression?
    var mutationFunctionNames: (willMutate: String, didMutate: String)?
    var uniquifyingParameterCount = 0
    var functionType: TypeSignature {
        return .function(parameters.map(\.signature), returnType)
    }

    // KotlinMemberDeclaration
    var extends: TypeSignature? {
        didSet {
            if extends != nil {
                isOpen = false
            }
        }
    }
    var isStatic: Bool {
        return modifiers.isStatic
    }

    static func translate(statement: FunctionDeclaration, translator: KotlinTranslator) -> KotlinFunctionDeclaration {
        let kstatement = KotlinFunctionDeclaration(statement: statement)
        kstatement.isAsync = statement.isAsync
        kstatement.modifiers = statement.modifiers
        kstatement.returnType = statement.returnType
        kstatement.parameters = statement.parameters.map { $0.translate(translator: translator) }
        var owningDeclarationType: StatementType? = nil
        if let owningTypeDeclaration = statement.owningTypeDeclaration, owningTypeDeclaration === statement.parent {
            // Use codebaseInfo rather than .type directly so that extension API is also handled correctly
            owningDeclarationType = translator.codebaseInfo?.declarationType(of: owningTypeDeclaration.signature, mustBeInModule: false) ?? owningTypeDeclaration.type
            if statement.type == .initDeclaration {
                kstatement.isOpen = false
                kstatement.modifiers.isOverride = false // Kotlin does not override constructors
                if statement.isOptionalInit {
                    kstatement.messages.append(.kotlinConstructorNullReturn(statement, source: translator.syntaxTree.source))
                }
            } else {
                if owningDeclarationType == .protocolDeclaration {
                    // Kotlin uses default public visibility on all interface members
                    kstatement.modifiers.visibility = .public
                } else {
                    if !kstatement.modifiers.isOverride && translator.codebaseInfo?.isProtocolMember(declaration: statement, in: owningTypeDeclaration.signature) == true {
                        kstatement.modifiers.isOverride = true
                    }
                    kstatement.isOpen = !kstatement.modifiers.isOverride && !statement.modifiers.isFinal && statement.modifiers.visibility != .private && owningDeclarationType == .classDeclaration && !owningTypeDeclaration.modifiers.isFinal
                }
                // Kotlin does not all you to decrease visibility when overriding a member, so we simply make all overrides public to prevent errors
                if kstatement.modifiers.isOverride {
                    kstatement.modifiers.visibility = .public
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
        if owningDeclarationType == .protocolDeclaration {
            if statement.type == .initDeclaration {
                kstatement.messages.append(.kotlinProtocolConstructor(statement, source: translator.syntaxTree.source))
            } else if statement.modifiers.isStatic {
                kstatement.messages.append(.kotlinProtocolStaticMember(statement, source: translator.syntaxTree.source))
            }
        }
        if statement.attributes.attributes.contains(where: { !isIgnorable(attribute: $0) }) {
            kstatement.messages.append(.kotlinAttributeUnsupported(statement, source: translator.syntaxTree.source))
        }
        return kstatement
    }

    private static func isIgnorable(attribute: Attribute) -> Bool {
        switch attribute.signature {
        case .named(let name, _):
            return name == "discardableResult"
        default:
            return false
        }
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
        output.append(indentation)
        if let declaration = extras?.declaration {
            output.append(declaration)
        } else {
            output.append(modifiers.kotlinMemberString(isOpen: isOpen, suffix: " "))
            if isAsync {
                output.append("suspend ")
            }

            if type != .constructorDeclaration {
                output.append("fun ")
            }
            if let extends {
                output.append(extends.kotlin).append(".")
                if isStatic {
                    output.append("Companion.")
                }
            }
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
                if let defaultValue = parameter.defaultValue {
                    output.append(" = ").append(defaultValue, indentation: indentation)
                }
                if index != parameters.count - 1 || uniquifyingParameterCount > 0 {
                    output.append(", ")
                }
            }
            for i in 0..<uniquifyingParameterCount {
                output.append("unusedp_\(i): Nothing? = null")
                if i != uniquifyingParameterCount - 1 {
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
        }
        if let body {
            output.append(" {\n")
            if !body.statements.isEmpty {
                let bodyIndentation = indentation.inc()
                for parameter in parameters {
                    if let externalLabel = parameter.externalLabel, parameter.internalLabel != parameter.externalLabel {
                        output.append(bodyIndentation).append("val \(parameter.internalLabel) = \(externalLabel)\n")
                    }
                }
                if type == .constructorDeclaration, let isConstructingPropertyName = (parent as? KotlinClassDeclaration)?.isConstructingPropertyName {
                    output.append(bodyIndentation).append("\(isConstructingPropertyName) = true\n")
                    body.syntheticFinally = "\(isConstructingPropertyName) = false"
                } else if let mutationFunctionNames {
                    output.append(bodyIndentation).append("\(mutationFunctionNames.willMutate)()\n")
                    body.syntheticFinally = "\(mutationFunctionNames.didMutate)()"
                }
                output.append(body, indentation: bodyIndentation)
            }
            output.append(indentation).append("}\n")
        } else {
            output.append("\n")
        }
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
    var inherits: [TypeSignature] = []
    var modifiers = Modifiers()
    var generics = Generics()
    var members: [KotlinStatement] = []

    static func translate(statement: TypeDeclaration, translator: KotlinTranslator) -> KotlinInterfaceDeclaration {
        let kstatement = KotlinInterfaceDeclaration(statement: statement)
        kstatement.inherits = statement.inherits
        kstatement.modifiers = statement.modifiers
        kstatement.generics = statement.generics

        var originalMembers = statement.members.flatMap { translator.translateStatement($0) }
        var newMembers: [KotlinStatement] = []
        // Move extensions of this type into the type itself rather than use Kotlin extension functions.
        // This allows us to replace API declarations with implementations. Also Kotlin extension functions
        // act like static functions, which can lead to different behavior
        if let codebaseInfo = translator.codebaseInfo {
            for ext in codebaseInfo.extensions(of: statement.signature) {
                kstatement.inherits += ext.inherits
                for extMember in ext.members.flatMap({ translator.translateStatement($0) }) {
                    if !replaceMember(in: &originalMembers, with: extMember) {
                        newMembers.append(extMember)
                    }
                }
            }
        }
        kstatement.members = originalMembers + newMembers
        kstatement.inherits.forEach { $0.appendKotlinMessages(to: kstatement, source: translator.syntaxTree.source) }
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
        super.init(type: .interfaceDeclaration, statement: statement)
    }

    override var children: [KotlinSyntaxNode] {
        return members
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
                output.append(": ")
                output.append(inherits.map({ $0.kotlin }).joined(separator: ", "))
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
    var modifiers = Modifiers()
    var generics = Generics()
    var aliasedType: TypeSignature = .none

    // KotlinMemberDeclaration
    var extends: TypeSignature?
    var isStatic: Bool {
        return false
    }

    static func translate(statement: TypealiasDeclaration, translator: KotlinTranslator) -> KotlinTypealiasDeclaration {
        let kstatement = KotlinTypealiasDeclaration(statement: statement)
        kstatement.modifiers = statement.modifiers
        kstatement.generics = statement.generics
        kstatement.aliasedType = statement.aliasedType
        if statement.owningTypeDeclaration != nil {
            kstatement.messages.append(.kotlinTypeAliasNested(statement, source: translator.syntaxTree.source))
        }
        if !statement.generics.whereEqual.isEmpty || statement.generics.entries.contains(where: { !$0.inherits.isEmpty }) {
            kstatement.messages.append(.kotlinTypeAliasConstrainedGenerics(statement, source: translator.syntaxTree.source))
        }
        return kstatement
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
        output.append(indentation).append(modifiers.kotlinMemberString(isOpen: false, suffix: " "))
        output.append("typealias ").append(name)
        generics.append(to: output, indentation: indentation)
        output.append(" = ").append(aliasedType.kotlin)
        generics.appendWhere(to: output, indentation: indentation)
        output.append("\n")
    }
}

class KotlinVariableDeclaration: KotlinStatement, KotlinMemberDeclaration {
    var names: [String?]
    var declaredType: TypeSignature = .none
    var isLet = false
    var isAsync = false
    var isProperty = false
    var isGlobal = false
    var isOpen = false
    var modifiers = Modifiers()
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

    // KotlinMemberDeclaration
    var extends: TypeSignature? {
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
        if let owningTypeDeclaration = statement.owningTypeDeclaration, owningTypeDeclaration === statement.parent {
            // Use codebaseInfo rather than .type directly so that extension API is also handled correctly
            owningDeclarationType = translator.codebaseInfo?.declarationType(of: owningTypeDeclaration.signature, mustBeInModule: false) ?? owningTypeDeclaration.type
            kstatement.isProperty = true
            if owningDeclarationType == .protocolDeclaration {
                // Kotlin uses default public visibility on all interface members
                kstatement.modifiers.visibility = .public
            } else {
                if !kstatement.modifiers.isOverride && translator.codebaseInfo?.isProtocolMember(declaration: statement, in: owningTypeDeclaration.signature) == true {
                    kstatement.modifiers.isOverride = true
                }
                kstatement.isOpen = !kstatement.modifiers.isOverride && !statement.modifiers.isFinal && statement.modifiers.visibility != .private && owningDeclarationType == .classDeclaration && !owningTypeDeclaration.modifiers.isFinal
            }
            // Kotlin does not all you to decrease visibility when overriding a member, so we simply make all overrides public to prevent errors
            if kstatement.modifiers.isOverride {
                kstatement.modifiers.visibility = .public
            }
        } else if statement.isGlobal {
            kstatement.isGlobal = true
        }
        if let value = statement.value {
            kstatement.value = translator.translateExpression(value).sref()
        }

        kstatement.isReadOnly = statement.isLet || (statement.getter != nil && statement.setter == nil)
        if kstatement.declaredType != .none {
            kstatement.mayBeSharedMutableStruct = kstatement.declaredType.kotlinMayBeSharedMutableStruct(codebaseInfo: translator.codebaseInfo)
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
        if !statement.attributes.isEmpty {
            kstatement.messages.append(.kotlinAttributeUnsupported(statement, source: translator.syntaxTree.source))
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
        output.append(indentation)
        if let declaration = extras?.declaration {
            output.append(declaration)
        } else if names.count == 1 && names[0] == nil {
            // Kotlin doesn't support assignment to wildcard
            if let value {
                output.append(value, indentation: indentation)
            }
        } else {
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
            if let extends {
                output.append(extends.kotlin).append(".")
                if isStatic {
                    output.append("Companion.")
                }
            }
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
                if (isProperty || isGlobal), case .optional = declaredType, !isLet, getter == nil {
                    output.append(" = null")
                }
            }
        }
        output.append("\n")

        if let getterBody = getter?.body {
            let getterIndentation = indentation.inc()
            output.append(getterIndentation).append("get() {\n")
            output.append(getterBody, indentation: getterIndentation.inc())
            output.append(getterIndentation).append("}\n")
        } else if mayBeSharedMutableStruct && (isProperty || isGlobal) {
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
        } else if !isReadOnly && mayBeSharedMutableStruct && (isProperty || isGlobal) {
            let setterIndentation = indentation.inc()
            output.append(setterIndentation).append("set(newValue) {\n")
            output.append(setterIndentation.inc()).append("field = newValue.sref()\n")
            output.append(setterIndentation).append("}\n")
        }
    }
}
