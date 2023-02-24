/// Types of Kotlin statements.
enum KotlinStatementType {
    case expression
    case `if`
    case `return`

    case classDeclaration
    case constructorDeclaration
    case extensionDeclaration
    case functionDeclaration
    case importDeclaration
    case interfaceDeclaration
    case variableDeclaration

    // Special statements
    case codeBlock
    case raw
    case message
}

class KotlinIf: KotlinStatement {
    var optionalBindingVariables: [OptionalBindingVariable] = []
    var conditions: [KotlinExpression]
    var isGuard = false
    var body: KotlinCodeBlockStatement
    var elseBody: KotlinCodeBlockStatement?

    struct OptionalBindingVariable {
        var name: String
        var declaredType: TypeSignature?
        var value: KotlinExpression
        var isLet: Bool
    }

    /// The entire `if/else if/else if/...` chain.
    ///
    /// The last element may have an `else`.
    var chain: [KotlinIf] {
        var chain = [self]
        while let elseif = chain.last?.elseif {
            chain.append(elseif)
        }
        return chain
    }

    private var elseif: KotlinIf? {
        guard let elseBody, elseBody.statements.count == 1 else {
            return nil
        }
        return elseBody.statements.first as? KotlinIf
    }

    static func translate(statement: If, translator: KotlinTranslator) -> KotlinIf {
        let (optionalBindingVariables, conditions) = extractOptionalBindingVariables(from: statement.conditions, logicalNegated: false, translator: translator)
        let kconditions = conditions.compactMap { translator.translateExpression($0) }
        let kbody = KotlinCodeBlockStatement.translate(statement: statement.body, translator: translator)
        let kstatement = KotlinIf(statement: statement, conditions: kconditions, body: kbody)
        kstatement.optionalBindingVariables = optionalBindingVariables
        if let elseBody = statement.elseBody {
            kstatement.elseBody = KotlinCodeBlockStatement.translate(statement: elseBody, translator: translator)
        }
        return kstatement
    }

    static func translate(statement: Guard, translator: KotlinTranslator) -> KotlinIf {
        let (optionalBindingVariables, conditions) = extractOptionalBindingVariables(from: statement.conditions, logicalNegated: true, translator: translator)
        let kconditions = conditions.compactMap { translator.translateExpression($0).logicalNegated() }
        let kbody = KotlinCodeBlockStatement.translate(statement: statement.body, translator: translator)
        let kstatement = KotlinIf(statement: statement, conditions: kconditions, body: kbody)
        kstatement.optionalBindingVariables = optionalBindingVariables
        kstatement.isGuard = true
        return kstatement
    }

    private static func extractOptionalBindingVariables(from conditions: [Expression], logicalNegated: Bool, translator: KotlinTranslator) -> ([OptionalBindingVariable], [Expression]) {
        var optionalBindingVariables: [OptionalBindingVariable] = []
        var updatedConditions: [Expression] = []
        for condition in conditions {
            // Extract any 'let x = y' to a separate variable and update the condition to 'x != nil'
            if let optionalBinding = condition as? OptionalBinding {
                let optionalBindingValue: KotlinExpression
                if let value = optionalBinding.value {
                    optionalBindingValue = translator.translateExpression(value)
                } else {
                    let identifier = KotlinIdentifier(name: optionalBinding.name)
                    identifier.mayBeSharedMutableValue = optionalBinding.variableType.kotlinMayBeSharedMutableValue(codebaseInfo: translator.codebaseInfo)
                    optionalBindingValue = identifier
                }
                let optionalBindingVariable = OptionalBindingVariable(name: optionalBinding.name, declaredType: optionalBinding.declaredType, value: optionalBindingValue.valueReference(), isLet: optionalBinding.isLet)
                optionalBindingVariables.append(optionalBindingVariable)
                let updatedCondition = BinaryOperator(op: logicalNegated ? .with(symbol: "==") : .with(symbol: "!="), lhs: Identifier(name: optionalBinding.name), rhs: NilLiteral())
                updatedConditions.append(updatedCondition)
            } else {
                updatedConditions.append(condition)
            }
        }
        return (optionalBindingVariables, updatedConditions)
    }

    private init(statement: Statement, conditions: [KotlinExpression], body: KotlinCodeBlockStatement) {
        self.conditions = conditions
        self.body = body
        super.init(type: .if, statement: statement)
    }

    override var children: [KotlinSyntaxNode] {
        var children: [KotlinSyntaxNode] = conditions
        children.append(body)
        if let elseBody {
            children.append(elseBody)
        }
        return children
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        let ifChain = chain
        let optionalBindingVariables = ifChain.flatMap { $0.optionalBindingVariables }
        for optionalBindingVariable in optionalBindingVariables {
            output.append(indentation).append(optionalBindingVariable.isLet ? "val " : "var ").append(optionalBindingVariable.name)
            output.append(" = ").append(optionalBindingVariable.value, indentation: indentation).append("\n")
        }
        for (index, statement) in chain.enumerated() {
            if index == 0 {
                output.append(indentation).append("if (")
            } else {
                output.append(indentation).append("} else if (")
            }
            statement.appendConditions(to: output, indentation: indentation)
            output.append(") {\n")

            let bodyIndentation = indentation.inc()
            output.append(statement.body, indentation: bodyIndentation)

            if index == chain.count - 1 {
                if let elseBody = statement.elseBody {
                    output.append(indentation).append("} else {\n")
                    output.append(elseBody, indentation: bodyIndentation)
                }
                output.append(indentation).append("}\n")
            }
        }
    }

    private func appendConditions(to output: OutputGenerator, indentation: Indentation) {
        guard conditions.count > 1 else {
            if let condition = conditions.first {
                condition.append(to: output, indentation: indentation)
            }
            return
        }

        for (index, condition) in conditions.enumerated() {
            let isCompound = condition.isCompoundExpression
            if isCompound {
                output.append("(")
            }
            output.append(condition, indentation: indentation)
            if isCompound {
                output.append(")")
            }
            if index < conditions.count - 1 {
                output.append(" ").append(isGuard ? "||" : "&&").append(" ")
            }
        }
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

// MARK: - Declarations

class KotlinClassDeclaration: KotlinStatement {
    var name: String
    var qualifiedName: String
    var inherits: [TypeSignature] = []
    var superclassCall: String?
    var modifiers = Modifiers()
    var declarationType: StatementType
    var members: [KotlinStatement] = []

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
        kstatement.inherits.forEach { $0.appendKotlinMessages(to: kstatement) }
        return kstatement
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
                output.append(declarationType == .classDeclaration ? "public open " : "public ")
            case .public:
                output.append("public ")
                if declarationType == .classDeclaration && !modifiers.isFinal {
                    output.append("open ")
                }
            case .private:
                output.append("private ")
                if declarationType == .classDeclaration && !modifiers.isFinal {
                    output.append("open ")
                }
            }
            output.append("class ").append(name)
            if !inherits.isEmpty {
                output.append(": ")
                var inherits = inherits
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

        let memberIndentation = indentation.inc()
        let staticMembers = members.filter { ($0 as? KotlinMemberDeclaration)?.isStatic == true }
        let nonstaticMembers = members.filter { ($0 as? KotlinMemberDeclaration)?.isStatic != true }
        nonstaticMembers.forEach { output.append($0, indentation: memberIndentation) }

        output.append("\n").append(memberIndentation).append("companion object {\n")
        staticMembers.forEach { output.append($0, indentation: memberIndentation.inc()) }
        output.append(memberIndentation).append("}\n")

        output.append(indentation).append("}\n")
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

class KotlinFunctionDeclaration: KotlinStatement, KotlinMemberDeclaration {
    var name: String
    var returnType: TypeSignature = .none
    var parameters: [Parameter<KotlinExpression>] = []
    var isAsync = false
    var isOpen = false
    var modifiers = Modifiers()
    var body: KotlinCodeBlockStatement?
    var delegatingConstructorCall: KotlinExpression?

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
            kstatement.body = KotlinCodeBlockStatement.translate(statement: body, translator: translator)
            kstatement.body?.updateWithExpectedReturn(statement.returnType == .void ? .no : .valueReference(nil))
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

        return kstatement
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
            output.append(modifiers.kotlinMemberString(isOpen: isOpen)).append(" ")
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
                output.append(parameter.declaredType.or(.any).kotlin)
                if let defaultValue = parameter.defaultValue {
                    output.append(" = ").append(defaultValue, indentation: indentation)
                }
                if index != parameters.count - 1 {
                    output.append(", ")
                }
            }
            output.append(")")
            if type != .constructorDeclaration {
                let returnType = returnType.or(.void)
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

class KotlinVariableDeclaration: KotlinStatement, KotlinMemberDeclaration {
    var name: String
    var declaredType: TypeSignature = .none
    var isLet = false
    var isAsync = false
    var isProperty = false
    var isGlobal = false
    var isOpen = false
    var modifiers = Modifiers()
    var value: KotlinExpression?
    var getter: Accessor<KotlinCodeBlockStatement>?
    var setter: Accessor<KotlinCodeBlockStatement>?
    var willSet: Accessor<KotlinCodeBlockStatement>?
    var didSet: Accessor<KotlinCodeBlockStatement>?
    var variableType: TypeSignature = .none
    var mayBeSharedMutableValue = false
    var isReadOnly = false
    var onUpdate: String?

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
            kstatement.value = translator.translateExpression(value).valueReference()
        }
        kstatement.variableType = statement.variableType

        kstatement.isReadOnly = statement.isLet || (statement.getter != nil && statement.setter == nil)
        if kstatement.declaredType != .none {
            kstatement.mayBeSharedMutableValue = kstatement.declaredType.kotlinMayBeSharedMutableValue(codebaseInfo: translator.codebaseInfo)
        } else if let kvalue = kstatement.value {
            kstatement.mayBeSharedMutableValue = kvalue.mayBeSharedMutableValueExpression(orType: true)
        } else {
            kstatement.mayBeSharedMutableValue = true
        }
        if kstatement.mayBeSharedMutableValue {
            kstatement.onUpdate = kstatement.isReadOnly ? nil : kstatement.isProperty ? "{ this.\(kstatement.name) = it }" : "{ \(kstatement.name) = it }"
            kstatement.getter = statement.getter?.translate(translator: translator, expectedReturn: .valueReference(kstatement.onUpdate))
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
        return kstatement
    }

    private init(statement: VariableDeclaration) {
        self.name = statement.name
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
                output.append(modifiers.kotlinMemberString(isOpen: isOpen && getter != nil)).append(" ")
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
            output.append(name)

            if declaredType != .none {
                output.append(": ").append(declaredType.kotlin)
            }
            if let value {
                output.append(" = ").append(value, indentation: indentation)
            }
            output.append("\n")
        }

        if let getterBody = getter?.body {
            let getterIndentation = indentation.inc()
            output.append(getterIndentation).append("get() {\n")
            output.append(getterBody, indentation: getterIndentation.inc())
            output.append(getterIndentation).append("}\n")
        } else if mayBeSharedMutableValue && (isProperty || isGlobal) {
            let getterIndentation = indentation.inc()
            output.append(getterIndentation).append("get() {\n")
            output.append(getterIndentation.inc()).append("return field.valref(\(onUpdate ?? ""))\n")
            output.append(getterIndentation).append("}\n")
        }
        if setter?.body != nil || willSet?.body != nil || didSet?.body != nil {
            let setterIndentation = indentation.inc()
            let setterBodyIndentation = setterIndentation.inc()
            if mayBeSharedMutableValue {
                output.append(setterIndentation).append("set(newGivenValue) {\n")
                output.append(setterBodyIndentation).append("val newValue = newGivenValue.valref()\n")
            } else {
                output.append(setterIndentation).append("set(newValue) {\n")
            }
            if let willSetBody = willSet?.body {
                if let parameterName = willSet?.parameterName, parameterName != "newValue" {
                    output.append(setterBodyIndentation).append("val \(parameterName) = newValue\n")
                }
                output.append(willSetBody, indentation: setterBodyIndentation)
            }
            if let setterBody = setter?.body {
                if let parameterName = setter?.parameterName, parameterName != "newValue" && parameterName != willSet?.parameterName {
                    output.append(setterBodyIndentation).append("val \(parameterName) = newValue\n")
                }
                output.append(setterBody, indentation: setterBodyIndentation)
            } else {
                if didSet?.body != nil {
                    output.append(setterBodyIndentation).append("val oldValue = field\n")
                }
                output.append(setterBodyIndentation).append("field = newValue\n")
            }
            if let didSetBody = didSet?.body {
                output.append(didSetBody, indentation: setterBodyIndentation)
            }
            output.append(setterIndentation).append("}\n")
        } else if !isReadOnly && mayBeSharedMutableValue && (isProperty || isGlobal) {
            let setterIndentation = indentation.inc()
            output.append(setterIndentation).append("set(newValue) {\n")
            output.append(setterIndentation.inc()).append("field = newValue.valref()\n")
            output.append(setterIndentation).append("}\n")
        }
    }
}
