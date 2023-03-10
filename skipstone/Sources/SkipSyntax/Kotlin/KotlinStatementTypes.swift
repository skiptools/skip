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

    init(statement: Break) {
        self.label = statement.label
        super.init(type: .break, statement: statement)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation).append("break")
        if let label {
            output.append("@\(label)")
        }
        output.append("\n")
    }
}

class KotlinCodeBlock: KotlinStatement {
    var statements: [KotlinStatement]
    var deferCount = 0

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
    @discardableResult func updateWithExpectedReturn(_ expectedReturn: ExpectedReturn) -> Bool {
        var label: String?
        var sref = false
        var returnRequired = false
        var onUpdate: String? = nil
        switch expectedReturn {
        case .no:
            // Don't shortcut and return here because we need to return whether any return statements were found
            break
        case .yes:
            returnRequired = true
        case .labelIfPresent(let l):
            label = l
        case .sref(let update):
            onUpdate = update
            sref = true
            returnRequired = true
        }

        var didFindReturn = false
        visit { node in
            if let statement = node as? KotlinStatement {
                switch statement.type {
                case .functionDeclaration:
                    // Skip embedded functions that may have their own returns
                    return .skip
                case .return:
                    let returnStatement = statement as! KotlinReturn
                    didFindReturn = true
                    if let label {
                        returnStatement.label = label
                    }
                    if sref {
                        returnStatement.expression = returnStatement.expression?.sref(onUpdate: onUpdate)
                    }
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
    func updateWithInOutParameter(name: String) {
        visit { node in
            // TODO: We could attempt to identify more re-bindings of the identifier
            if let identifier = node as? KotlinIdentifier {
                if identifier.name == name {
                    identifier.isInOut = true
                }
            } else if let variableDeclaration = node as? KotlinVariableDeclaration {
                if variableDeclaration.names.contains(name) {
                    variableDeclaration.messages.append(.kotlinInOutParameterAssignment(variableDeclaration))
                }
            }
            return .recurse(nil)
        }
    }

    override var children: [KotlinSyntaxNode] {
        return statements
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        var statementIndentation = indentation
        if deferCount > 0 {
            if deferCount == 1 {
                output.append(indentation).append("var deferaction: (() -> Unit)? = null\n")
            } else {
                output.append(indentation).append("val deferactions: MutableList<() -> Unit> = mutableListOf()\n")
            }
            output.append(indentation).append("try {\n")
            statementIndentation = statementIndentation.inc()
        }
        output.append(statements, indentation: statementIndentation)
        if deferCount > 0 {
            output.append(indentation).append("} finally {\n")
            if deferCount == 1 {
                output.append(statementIndentation).append("deferaction?.invoke()\n")
            } else {
                output.append(statementIndentation).append("deferactions.asReversed().forEach { it.invoke() }\n")
            }
            output.append(indentation).append("}\n")
        }
    }

    func appendDefer(_ body: KotlinCodeBlock, to output: OutputGenerator, indentation: Indentation) {
        if deferCount == 1 {
            output.append(indentation).append("deferaction = {\n")
            output.append(body, indentation: indentation.inc())
            output.append(indentation).append("}\n")
        } else {
            output.append(indentation).append("deferactions.add {\n")
            output.append(body, indentation: indentation.inc())
            output.append(indentation).append("}\n")
        }
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
    var body: KotlinCodeBlock

    static func translate(statement: ForLoop, translator: KotlinTranslator) -> KotlinForLoop {
        let ksequence = translator.translateExpression(statement.sequence)
        let kbody = KotlinCodeBlock.translate(statement: statement.body, translator: translator)
        let kstatement = KotlinForLoop(statement: statement, sequence: ksequence, body: kbody)
        kstatement.declaredType = statement.declaredType
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
        if identifierNames.count > 1 {
            output.append("(")
        }
        output.append(identifierNames.map { $0 ?? "_" }.joined(separator: ", "))
        if identifierNames.count > 1 {
            output.append(")")
        }
        output.append(" in ")
        output.append(sequence.sref(), indentation: indentation)
        output.append(") {\n")

        // Re-declare vars
        let bodyIndentation = indentation.inc()
        for identifierPattern in identifierPatterns {
            if let name = identifierPattern.name, identifierPattern.isVar {
                output.append(bodyIndentation).append("var ").append(name).append(" = ").append("\(name)_0\n")
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
        let ktarget = translator.translateStatement(statement.target).first ?? KotlinMessageStatement(message: .kotlinUntranslatable(statement))
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

class KotlinWhileLoop: KotlinStatement {
    var conditions: [KotlinExpression]
    var casePatternVariables: [KotlinCasePattern.Variable]
    var body: KotlinCodeBlock
    var isDoWhile = false

    static func translate(statement: WhileLoop, translator: KotlinTranslator) -> KotlinWhileLoop {
        let (kconditions, kvariables, messages) = translate(conditions: statement.conditions, translator: translator)
        let kbody = KotlinCodeBlock.translate(statement: statement.body, translator: translator)
        let kstatement = KotlinWhileLoop(statement: statement, conditions: kconditions, casePatternVariables: kvariables, body: kbody)
        kstatement.isDoWhile = statement.isRepeatWhile
        kstatement.messages += messages
        return kstatement
    }

    private static func translate(conditions: [Expression], translator: KotlinTranslator) -> ([KotlinExpression], [KotlinCasePattern.Variable], [Message]) {
        var kconditions: [KotlinExpression] = []
        var kvariables: [KotlinCasePattern.Variable] = []
        var messages: [Message] = []
        for condition in conditions {
            kconditions.append(translator.translateExpression(condition))
            // We could copy the binding value from the condition in order to bind variables in the loop body, but this would cause
            // re-execution of the expression code, which could have side effects
            if let optionalBinding = condition as? OptionalBinding, KotlinOptionalBinding.translateVariable(expression: optionalBinding, translator: translator) != nil {
                messages.append(.kotlinLoopOptionalBinding(optionalBinding))
            } else if let matchingCase = condition as? MatchingCase, let casePatternVariables = KotlinCasePattern.translateVariables(expression: matchingCase.pattern, translator: translator) {
                kvariables += casePatternVariables
            }
        }
        return (kconditions, kvariables, messages)
    }

    private init(statement: WhileLoop, conditions: [KotlinExpression], casePatternVariables: [KotlinCasePattern.Variable], body: KotlinCodeBlock) {
        self.conditions = conditions
        self.casePatternVariables = casePatternVariables
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
            for casePatternVariable in casePatternVariables {
                casePatternVariable.append(to: output, indentation: indentation)
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
    var qualifiedName: String
    var inherits: [TypeSignature] = []
    var superclassCall: String?
    var modifiers = Modifiers()
    var declarationType: StatementType
    var members: [KotlinStatement] = []
    var isConstructingPropertyName: String?
    var isEnumWithAssociatedValues: Bool {
        return members.contains { ($0 as? KotlinEnumCaseDeclaration)?.associatedValues.isEmpty == false }
    }
    var enumInheritedRawValueType: TypeSignature? {
        guard let inherits = inherits.first else {
            return nil
        }
        return inherits.isNumeric || inherits == .string ? inherits : nil
    }

    static func translate(statement: TypeDeclaration, translator: KotlinTranslator) -> KotlinClassDeclaration {
        let kstatement = KotlinClassDeclaration(statement: statement)
        kstatement.inherits = statement.inherits
        kstatement.modifiers = statement.modifiers
        var members = statement.members.flatMap { translator.translateStatement($0) }
        // Move extensions of this type into the type itself rather than use Kotlin extension functions.
        // Kotlin extension functions act like static functions, which can lead to different behavior
        if let codebaseInfo = translator.codebaseInfo {
            for ext in codebaseInfo.extensions(of: statement) {
                kstatement.inherits += ext.inherits
                members += ext.members.flatMap { translator.translateStatement($0) }
            }
        }
        kstatement.members = members
        kstatement.processEnumCaseDeclarations()
        kstatement.inherits.forEach { $0.appendKotlinMessages(to: kstatement) }
        if statement.attributes.attributes.contains(where: { !isIgnorable(attribute: $0) }) {
            kstatement.messages.append(.kotlinAttributeUnsupported(statement))
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
        self.qualifiedName = statement.qualifiedName
        self.declarationType = statement.type
        super.init(type: .classDeclaration, statement: statement)
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
                let isEnumWithAssociatedValues = self.isEnumWithAssociatedValues
                if isEnumWithAssociatedValues {
                    output.append("sealed class ").append(name)
                } else {
                    output.append("enum class ").append(name)
                    if let inheritedRawValueType = enumInheritedRawValueType {
                        inherits = Array(inherits.dropFirst())
                        output.append("(val rawValue: \(inheritedRawValueType.kotlin))")
                    }
                }
            } else {
                output.append("class ").append(name)
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
        if !staticMembers.isEmpty || modifiers.visibility == .public || modifiers.visibility == .open {
            output.append("\n")
            output.append(memberIndentation).append("companion object {\n")
            staticMembers.forEach { output.append($0, indentation: memberIndentation.inc()) }
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

    static func translate(statement: EnumCaseDeclaration, translator: KotlinTranslator) -> KotlinEnumCaseDeclaration {
        let kstatement = KotlinEnumCaseDeclaration(statement: statement)
        kstatement.associatedValues = statement.associatedValues.map { $0.translate(translator: translator) }
        kstatement.associatedValues.forEach { $0.declaredType.appendKotlinMessages(to: kstatement) }
        kstatement.rawValue = statement.rawValue.map { translator.translateExpression($0) }
        if !statement.modifiers.isEmpty {
            kstatement.messages.append(.kotlinEnumModifierUnsupported(statement))
        }
        if !statement.attributes.isEmpty {
            kstatement.messages.append(.kotlinAttributeUnsupported(statement))
        }
        return kstatement
    }

    private init(statement: EnumCaseDeclaration) {
        self.name = statement.name
        super.init(type: .enumCaseDeclaration, statement: statement)
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
        } else if let owningClassDeclaration = parent as? KotlinClassDeclaration, owningClassDeclaration.isEnumWithAssociatedValues {
            output.append("class \(name)")
            var propertyDeclarations: [String] = []
            if !associatedValues.isEmpty {
               output.append("(")
               for (index, value) in associatedValues.enumerated() {
                   if let label = value.externalLabel {
                       output.append(label).append(": ")
                       propertyDeclarations.append("val associated\(index) = \(label)")
                   } else {
                       output.append("val associated\(index): ")
                   }
                   output.append(value.declaredType.or(.any).kotlin)
                   if let defaultValue = value.defaultValue {
                       output.append(" = ").append(defaultValue, indentation: indentation)
                   }
                   if index != associatedValues.count - 1 {
                       output.append(", ")
                   }
               }
               output.append(")")
            }
            output.append(": \(owningClassDeclaration.name)() {\n")
            propertyDeclarations.forEach { output.append(indentation.inc()).append($0).append("\n") }
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
}

struct KotlinExtensionDeclaration {
    static func translate(statement: ExtensionDeclaration, translator: KotlinTranslator) -> [KotlinStatement] {
        // If the extension is on a type outside this module or is on a protocol, use Kotlin extension
        // functions. Otherwise do not translate the extension - instead we'll move its members into
        // our declaration of its extended type
        let declarationType = translator.codebaseInfo?.declarationType(of: statement.extends.description, mustBeInModule: true)
        guard declarationType == nil || declarationType == .protocolDeclaration else {
            return []
        }

        var kotlinStatements: [KotlinStatement] = []
        if !statement.inherits.isEmpty && translator.codebaseInfo != nil {
            let message: Message
            if declarationType == .protocolDeclaration {
                message = .kotlinExtensionAddProtocolsToInterface(statement)
            } else {
                message = .kotlinExtensionAddProtocolsToOutsideType(statement)
            }
            kotlinStatements.append(KotlinMessageStatement(message: message))
        }
        for member in statement.members.flatMap({ translator.translateStatement($0) }) {
            guard let memberDeclaration = member as? KotlinMemberDeclaration else {
                kotlinStatements.append(KotlinMessageStatement(message: .kotlinExtensionUnsupportedMember(member)))
                continue
            }
            guard member.type != .constructorDeclaration else {
                kotlinStatements.append(KotlinMessageStatement(message: .kotlinExtensionAddConstructorsToOutsideType(member)))
                continue
            }
            memberDeclaration.extends = statement.extends
            kotlinStatements.append(member)
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
    var modifiers = Modifiers()
    var body: KotlinCodeBlock?
    var delegatingConstructorCall: KotlinExpression?
    var mutationFunctionNames: (willMutate: String, didMutate: String)?

    // KotlinMemberDeclaration
    var extends: TypeSignature?
    var isStatic: Bool {
        return modifiers.isStatic
    }

    static func translate(statement: FunctionDeclaration, translator: KotlinTranslator) -> KotlinFunctionDeclaration {
        let kstatement = KotlinFunctionDeclaration(statement: statement)
        kstatement.isAsync = statement.isAsync
        kstatement.modifiers = statement.modifiers
        kstatement.returnType = statement.returnType
        kstatement.parameters = statement.parameters.map { $0.translate(translator: translator) }
        if let owningTypeDeclaration = statement.owningTypeDeclaration {
            kstatement.isOpen = !statement.modifiers.isFinal && statement.modifiers.visibility != .private && owningTypeDeclaration.type == .classDeclaration && !owningTypeDeclaration.modifiers.isFinal
            if (translator.codebaseInfo?.isProtocolMember(declaration: statement, in: owningTypeDeclaration) == true) {
                kstatement.modifiers.isOverride = true
            }
        }
        if let body = statement.body {
            kstatement.body = KotlinCodeBlock.translate(statement: body, translator: translator)
            kstatement.body?.updateWithExpectedReturn(statement.returnType == .void ? .no : .sref(nil))
            for parameter in kstatement.parameters where parameter.isInOut {
                kstatement.body?.updateWithInOutParameter(name: parameter.internalLabel)
            }
        }
        kstatement.returnType.appendKotlinMessages(to: kstatement)
        kstatement.parameters.forEach { $0.declaredType.appendKotlinMessages(to: kstatement) }

        // Warnings and fixups
        if let owningTypeDeclaration = statement.owningTypeDeclaration, owningTypeDeclaration === statement.parent, owningTypeDeclaration.type == .protocolDeclaration {
            if statement.type == .initDeclaration {
                kstatement.messages.append(.kotlinProtocolConstructor(statement))
            } else if statement.modifiers.isStatic {
                kstatement.messages.append(.kotlinProtocolStaticFunction(statement))
            }
        }
        if statement.type == .initDeclaration {
            kstatement.isOpen = false
            kstatement.modifiers.isOverride = false // Kotlin does not override constructors
            if statement.isOptionalInit {
                kstatement.messages.append(.kotlinConstructorNullReturn(statement))
            }
        }
        if statement.attributes.attributes.contains(where: { !isIgnorable(attribute: $0) }) {
            kstatement.messages.append(.kotlinAttributeUnsupported(statement))
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

    init(name: String, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.name = name
        super.init(type: name == "constructor" ? .constructorDeclaration : .functionDeclaration, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(statement: FunctionDeclaration) {
        self.name = statement.type == .initDeclaration ? "constructor" : statement.name
        super.init(type: statement.type == .initDeclaration ? .constructorDeclaration : .functionDeclaration, statement: statement)
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
                if index != parameters.count - 1 {
                    output.append(", ")
                }
            }
            output.append(")")
            if type != .constructorDeclaration {
                if returnType != .void {
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
                    output.append(bodyIndentation).append("try {\n")
                    output.append(body, indentation: bodyIndentation.inc())
                    output.append(bodyIndentation).append("} finally {\n")
                    output.append(bodyIndentation.inc()).append("\(isConstructingPropertyName) = false\n")
                    output.append(bodyIndentation).append("}\n")
                } else if let mutationFunctionNames {
                    output.append(bodyIndentation).append("\(mutationFunctionNames.willMutate)()\n")
                    output.append(bodyIndentation).append("try {\n")
                    output.append(body, indentation: bodyIndentation.inc())
                    output.append(bodyIndentation).append("} finally {\n")
                    output.append(bodyIndentation.inc()).append("\(mutationFunctionNames.didMutate)()\n")
                    output.append(bodyIndentation).append("}\n")
                } else {
                    output.append(body, indentation: bodyIndentation)
                }
            }
            output.append(indentation).append("}\n")
        } else {
            output.append("\n")
        }
    }
}

class KotlinImportDeclaration: KotlinStatement {
    var modulePath: [String]

    init(modulePath: [String], sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
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
    var members: [KotlinStatement] = []

    static func translate(statement: TypeDeclaration, translator: KotlinTranslator) -> KotlinInterfaceDeclaration {
        let kstatement = KotlinInterfaceDeclaration(statement: statement)
        kstatement.inherits = statement.inherits
        kstatement.modifiers = statement.modifiers
        kstatement.members = statement.members.flatMap { translator.translateStatement($0) }
        kstatement.inherits.forEach { $0.appendKotlinMessages(to: kstatement) }
        return kstatement
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
            if !inherits.isEmpty {
                output.append(": ")
                output.append(inherits.map({ $0.kotlin }).joined(separator: ", "))
            }
        }
        output.append(" {\n")
        children.forEach { output.append($0, indentation: indentation.inc()) }
        output.append(indentation).append("}\n")
    }
}

class KotlinTypealiasDeclaration: KotlinStatement, KotlinMemberDeclaration {
    var name: String
    var modifiers = Modifiers()
    var aliasedType: TypeSignature

    // KotlinMemberDeclaration
    var extends: TypeSignature?
    var isStatic: Bool {
        return false
    }

    init(statement: TypealiasDeclaration) {
        self.name = statement.name
        self.modifiers = statement.modifiers
        self.aliasedType = statement.aliasedType
        super.init(type: .typealiasDeclaration, statement: statement)
        if statement.owningTypeDeclaration != nil {
            self.messages.append(.kotlinTypeAliasNested(statement))
        }
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation).append(modifiers.kotlinMemberString(isOpen: false, suffix: " "))
        output.append("typealias ").append(name).append(" = ").append(aliasedType.kotlin).append("\n")
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
    var extends: TypeSignature?
    var isStatic: Bool {
        return modifiers.isStatic
    }

    static func translate(statement: VariableDeclaration, translator: KotlinTranslator) -> KotlinVariableDeclaration {
        let kstatement = KotlinVariableDeclaration(statement: statement)
        kstatement.isLet = statement.isLet
        kstatement.isAsync = statement.isAsync
        kstatement.modifiers = statement.modifiers
        kstatement.declaredType = statement.declaredType
        if let owningTypeDeclaration = statement.owningTypeDeclaration {
            kstatement.isProperty = statement.parent === owningTypeDeclaration
            kstatement.isOpen = kstatement.isProperty && !statement.modifiers.isFinal && statement.modifiers.visibility != .private && owningTypeDeclaration.type == .classDeclaration && !owningTypeDeclaration.modifiers.isFinal
            if kstatement.isProperty && translator.codebaseInfo?.isProtocolMember(declaration: statement, in: owningTypeDeclaration) == true {
                kstatement.modifiers.isOverride = true
            }
        } else if statement.parent?.parent == nil {
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

        kstatement.declaredType.appendKotlinMessages(to: kstatement)
        if statement.isAsync {
            kstatement.messages.append(.kotlinAsyncProperties(kstatement))
        }
        if !statement.attributes.isEmpty {
            kstatement.messages.append(.kotlinAttributeUnsupported(statement))
        }
        return kstatement
    }

    init(names: [String], variableTypes: [TypeSignature], sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.names = names
        self.variableTypes = variableTypes
        super.init(type: .variableDeclaration, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(statement: VariableDeclaration) {
        self.names = statement.names
        self.variableTypes = statement.variableTypes
        super.init(type: .variableDeclaration, statement: statement)
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
            output.append("\n")
        }

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
