/// Types of Kotlin statements.
enum KotlinStatementType {
    case expression
    case `return`

    case classDeclaration
    case extensionDeclaration
    case functionDeclaration
    case importDeclaration
    case interfaceDeclaration
    case packageDeclaration
    case variableDeclaration

    /// A statement representing raw Kotlin code.
    case raw
    /// A statement that only exists to add a message to the syntax tree.
    case message
}

class KotlinReturn: KotlinExpressionStatement {
    static func translate(statement: Return, translator: KotlinTranslator) -> KotlinExpressionStatement {
        let kstatement = KotlinReturn(statement: statement)
        if let expression = statement.expression {
            kstatement.expression = translator.translateExpression(expression).valueReference
        }
        return kstatement
    }

    init(statement: Return) {
        super.init(type: .return, statement: statement)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if let expression {
            output.append(indentation).append("return ").append(expression).append("\n")
        } else {
            output.append(indentation).append("return")
        }
    }
}

// MARK: - Declarations

class KotlinClassDeclaration: KotlinStatement {
    let name: String
    var inherits: [TypeSignature]
    var superclassCall: String?
    var modifiers: Modifiers
    var isDataClass: Bool
    var members: [KotlinStatement] = []

    static func translate(statement: TypeDeclaration, translator: KotlinTranslator) -> KotlinClassDeclaration {
        let kstatement = KotlinClassDeclaration(statement: statement)
        kstatement.buildSuperclassCall(translator: translator)
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
        self.inherits = statement.inherits
        self.modifiers = statement.modifiers
        self.isDataClass = Self.isDataClass(typeDeclaration: statement)
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
                if !isDataClass && !modifiers.isFinal {
                    output.append("open ")
                }
            case .open:
                output.append(isDataClass ? "public " : "public open ")
            case .public:
                output.append("public ")
                if !isDataClass && !modifiers.isFinal {
                    output.append("open ")
                }
            case .private:
                output.append("private ")
                if !isDataClass && !modifiers.isFinal {
                    output.append("open ")
                }
            }
            if isDataClass {
                output.append("data ")
            }
            output.append("class ").append(name)

            // TODO: Default constructor call

            if !inherits.isEmpty {
                output.append(": ")
                var inherits = inherits
                if let superclassCall {
                    output.append(superclassCall)
                    if inherits.count > 1 {
                        inherits = Array(inherits.dropFirst())
                        output.append(", ")
                    }
                }
                output.append(inherits.map({ $0.qualifiedKotlin }).joined(separator: ", "))
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

    private static func isDataClass(typeDeclaration: TypeDeclaration) -> Bool {
        guard typeDeclaration.type == .structDeclaration else {
            return false
        }
        // TODO: Must have at least one stored property
        return true
    }

    private func buildSuperclassCall(translator: KotlinTranslator) {
        guard let superclass = inherits.first, translator.codebaseInfo?.declarationType(of: superclass.qualifiedDescription) == .classDeclaration else {
            return
        }
        // TODO: Call superclass default constructor with our default constructor params
        superclassCall = "\(superclass.qualifiedKotlin)()"
    }
}

struct KotlinExtensionDeclaration {
    static func translate(statement: ExtensionDeclaration, translator: KotlinTranslator) -> [KotlinStatement] {
        // If the extension is on a type outside this module or is on a protocol, use Kotlin extension
        // functions. Otherwise do not translate the extension - instead we'll move its members into
        // our declaration of its extended type
        let declarationType = translator.codebaseInfo?.declarationType(of: statement.extends.qualifiedDescription)
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
            memberDeclaration.extends = statement.extends
            kotlinStatements.append(member)
        }
        return kotlinStatements
    }
}

class KotlinFunctionDeclaration: KotlinStatement, KotlinMemberDeclaration {
    let name: String
    var returnType: TypeSignature?
    var parameters: [Parameter<KotlinStatement>] = []
    var isAsync: Bool
    var isOpen = false
    var modifiers: Modifiers
    var body: CodeBlock<KotlinStatement>?

    // KotlinMemberDeclaration
    var extends: TypeSignature?
    var isStatic: Bool {
        return modifiers.isStatic
    }

    static func translate(statement: FunctionDeclaration, translator: KotlinTranslator) -> KotlinFunctionDeclaration {
        let kstatement = KotlinFunctionDeclaration(statement: statement)
        kstatement.returnType = statement.returnType
        kstatement.parameters = statement.parameters.map { $0.translate(translator: translator) }
        if let owningTypeDeclaration = statement.owningTypeDeclaration {
            kstatement.isOpen = !statement.modifiers.isFinal && statement.modifiers.visibility != .private && owningTypeDeclaration.type == .classDeclaration && !owningTypeDeclaration.modifiers.isFinal
            if (translator.codebaseInfo?.isProtocolMember(declaration: statement, in: owningTypeDeclaration) == true) {
                kstatement.modifiers.isOverride = true
            }
        }
        if let body = statement.body {
            let bodyStatements = body.statements.flatMap { translator.translateStatement($0) }
            kstatement.body = CodeBlock(statements: bodyStatements)
        }
        kstatement.returnType?.appendKotlinMessages(to: kstatement)
        kstatement.parameters.forEach { $0.type?.appendKotlinMessages(to: kstatement) }
        return kstatement
    }

    private init(statement: FunctionDeclaration) {
        self.name = statement.name
        self.isAsync = statement.isAsync
        self.modifiers = statement.modifiers
        super.init(type: .functionDeclaration, statement: statement)
    }

    override var children: [KotlinSyntaxNode] {
        return parameters.compactMap { $0.defaultValue } + (body?.statements ?? [])
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

            output.append("fun ")
            if let extends {
                output.append(extends.qualifiedKotlin).append(".")
                if isStatic {
                    output.append("Companion.")
                }
            }
            output.append(name).append("(")
            for (index, parameter) in parameters.enumerated() {
                let name = parameter.externalName.isEmpty ? parameter.internalName : parameter.externalName
                output.append(name)
                output.append(": ")
                output.append(parameter.type?.qualifiedKotlin ?? "Any")
                if let defaultValue = parameter.defaultValue {
                    output.append(" = ").append(defaultValue, indentation: 0)
                }
                if index != parameters.count - 1 {
                    output.append(", ")
                }
            }
            output.append("): \(returnType?.qualifiedKotlin ?? "Unit")")
        }
        if let body {
            output.append(" {\n")
            let bodyIndentation = indentation.inc()
            for parameter in parameters {
                if parameter.internalName != parameter.externalName {
                    output.append(bodyIndentation).append("val \(parameter.internalName) = \(parameter.externalName)\n")
                }
            }
            output.append(body.statements, indentation: bodyIndentation)
            output.append(indentation).append("}\n")
        } else {
            output.append("\n")
        }
    }
}

class KotlinImportDeclaration: KotlinStatement {
    let modulePath: [String]

    init(modulePath: [String]) {
        self.modulePath = modulePath
        super.init(type: .importDeclaration)
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
    let name: String
    var inherits: [TypeSignature]
    var modifiers: Modifiers
    var members: [KotlinStatement] = []

    static func translate(statement: TypeDeclaration, translator: KotlinTranslator) -> KotlinInterfaceDeclaration {
        let kstatement = KotlinInterfaceDeclaration(statement: statement)
        kstatement.members = statement.members.flatMap { translator.translateStatement($0) }
        kstatement.inherits.forEach { $0.appendKotlinMessages(to: kstatement) }
        return kstatement
    }

    private init(statement: TypeDeclaration) {
        self.name = statement.name
        self.inherits = statement.inherits
        self.modifiers = statement.modifiers
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
                output.append(inherits.map({ $0.qualifiedKotlin }).joined(separator: ", "))
            }
        }
        output.append(" {\n")
        children.forEach { output.append($0, indentation: indentation.inc()) }
        output.append(indentation).append("}\n")
    }
}

class KotlinPackageDeclaration: KotlinStatement {
    let name: String

    init(name: String) {
        self.name = name
        super.init(type: .packageDeclaration)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation).append("package \(name)\n\n")
    }
}

class KotlinVariableDeclaration: KotlinStatement, KotlinMemberDeclaration {
    let name: String
    var declaredType: TypeSignature?
    var isLet: Bool
    var isAsync: Bool
    var isProperty = false
    var isGlobal = false
    var isOpen = false
    var modifiers: Modifiers
    var value: KotlinExpression?
    var getter: Accessor<KotlinStatement>?
    var setter: Accessor<KotlinStatement>?
    var willSet: Accessor<KotlinStatement>?
    var didSet: Accessor<KotlinStatement>?

    // KotlinMemberDeclaration
    var extends: TypeSignature?
    var isStatic: Bool {
        return modifiers.isStatic
    }

    static func translate(statement: VariableDeclaration, translator: KotlinTranslator) -> KotlinVariableDeclaration {
        let kstatement = KotlinVariableDeclaration(statement: statement)
        kstatement.declaredType = statement.declaredType
        if let owningTypeDeclaration = statement.owningTypeDeclaration {
            kstatement.isProperty = statement.parent === owningTypeDeclaration
            kstatement.isOpen = kstatement.isProperty && !statement.modifiers.isFinal && statement.modifiers.visibility != .private && owningTypeDeclaration.type == .classDeclaration && !owningTypeDeclaration.modifiers.isFinal
            if kstatement.isProperty && translator.codebaseInfo?.isProtocolMember(declaration: statement, in: owningTypeDeclaration) == true {
                kstatement.modifiers.isOverride = true
            }
        } else {
            kstatement.isGlobal = true
        }
        if let value = statement.value {
            kstatement.value = translator.translateExpression(value).valueReference
        }
        kstatement.getter = statement.getter?.translate(translator: translator)
        kstatement.setter = statement.setter?.translate(translator: translator)
        kstatement.willSet = statement.willSet?.translate(translator: translator)
        kstatement.didSet = statement.didSet?.translate(translator: translator)
        kstatement.declaredType?.appendKotlinMessages(to: kstatement)
        if statement.isAsync {
            kstatement.messages.append(.kotlinAsyncProperties(kstatement))
        }
        return kstatement
    }

    private init(statement: VariableDeclaration) {
        self.name = statement.name
        self.isLet = statement.isLet
        self.isAsync = statement.isAsync
        self.modifiers = statement.modifiers
        super.init(type: .variableDeclaration, statement: statement)
    }

    override var children: [KotlinSyntaxNode] {
        var children: [KotlinSyntaxNode] = []
        if let value {
            children.append(value)
        }
        if let statements = getter?.statements {
            children += statements
        }
        if let statements = setter?.statements {
            children += statements
        }
        if let statements = willSet?.statements {
            children += statements
        }
        if let statements = didSet?.statements {
            children += statements
        }
        return children
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation)
        if let declaration = extras?.declaration {
            output.append(declaration)
        } else {
            if isProperty || isGlobal {
                output.append(modifiers.kotlinMemberString(isOpen: isOpen)).append(" ")
                if case .unwrappedOptional = declaredType {
                    output.append("lateinit ")
                }
            }
            if isLet || (getter != nil && setter == nil) {
                output.append("val ")
            } else {
                output.append("var ")
            }
            if let extends {
                output.append(extends.qualifiedKotlin).append(".")
                if isStatic {
                    output.append("Companion.")
                }
            }
            output.append(name)

            if let declaredType {
                output.append(": ").append(declaredType.qualifiedKotlin)
            }
            if let value {
                output.append(" = ").append(value, indentation: 0)
            }
            output.append("\n")
        }

        if isProperty && mayBeSharedMutableValue {
            let onUpdate = "{ this.\(name) = it }"
            let getterIndentation = indentation.inc()
            output.append(getterIndentation).append("get() {\n")
            let getterBodyIndentation = getterIndentation.inc()
            if let getterStatements = getter?.statements {
                output.append(getterBodyIndentation).append("return {\n")
                output.append(getterStatements, indentation: getterBodyIndentation.inc())
                output.append(getterBodyIndentation).append("}().valref(\(onUpdate))\n")
            } else {
                output.append(getterBodyIndentation).append("return field.valref(\(onUpdate))\n")
            }
            output.append(getterIndentation).append("}\n")
        } else if let getterStatements = getter?.statements {
            let getterIndentation = indentation.inc()
            output.append(getterIndentation).append("get() {\n")
            output.append(getterStatements, indentation: getterIndentation.inc())
            output.append(getterIndentation).append("}\n")
        }
        if setter?.statements != nil || willSet?.statements != nil || didSet?.statements != nil {
            let setterIndentation = indentation.inc()
            let setterBodyIndentation = setterIndentation.inc()
            if mayBeSharedMutableValue {
                output.append(setterIndentation).append("set(newGivenValue) {\n")
                output.append(setterBodyIndentation).append("val newValue = newGivenValue.valref()\n")
            } else {
                output.append(setterIndentation).append("set(newValue) {\n")
            }
            if let willSetStatements = willSet?.statements {
                if let parameterName = willSet?.parameterName, parameterName != "newValue" {
                    output.append(setterBodyIndentation).append("val \(parameterName) = newValue\n")
                }
                output.append(willSetStatements, indentation: setterBodyIndentation)
            }
            if let setterStatements = setter?.statements {
                if let parameterName = setter?.parameterName, parameterName != "newValue" && parameterName != willSet?.parameterName {
                    output.append(setterBodyIndentation).append("val \(parameterName) = newValue\n")
                }
                output.append(setterStatements, indentation: setterBodyIndentation)
            } else {
                if didSet?.statements != nil {
                    output.append(setterBodyIndentation).append("val oldValue = field\n")
                }
                output.append(setterBodyIndentation).append("field = newValue\n")
            }
            if let didSetStatements = didSet?.statements {
                output.append(didSetStatements, indentation: setterBodyIndentation)
            }
            output.append(setterIndentation).append("}\n")
        }
    }

    private var mayBeSharedMutableValue: Bool {
        if let declaredType {
            return declaredType.kotlinMayBeSharedMutableValue
        } else if let value {
            return value.mayBeSharedMutableValueExpression(orType: true)
        } else {
            return true
        }
    }
}
