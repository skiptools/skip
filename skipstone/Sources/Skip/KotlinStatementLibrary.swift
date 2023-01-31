class KotlinMessageStatement: KotlinStatement {
    init(message: Message) {
        super.init(type: .message)
        self.message = message
    }

    init(statement: Statement) {
        super.init(type: .message, statement: statement)
    }
}

class KotlinRawStatement: KotlinStatement {
    let sourceCode: String

    init(statement: RawStatement) {
        self.sourceCode = statement.sourceCode
        super.init(type: .raw, statement: statement)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation).append(sourceCode).append("\n")
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
        for ext in translator.codebaseInfo.extensions(of: statement) {
            kstatement.inherits += ext.inherits
            members += ext.members.flatMap { translator.translateStatement($0) }
        }
        kstatement.members = members
        return kstatement
    }

    private init(statement: TypeDeclaration) {
        self.name = statement.name
        self.inherits = statement.inherits
        self.modifiers = statement.modifiers
        self.isDataClass = Self.isDataClass(typeDeclaration: statement)
        super.init(type: .classDeclaration, statement: statement)
    }

    override var children: [KotlinStatement] {
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
                output.append(inherits.map({ $0.qualifiedDescription }).joined(separator: ", "))
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
        guard let superclass = inherits.first, translator.codebaseInfo.declarationType(of: superclass.qualifiedDescription) == .classDeclaration else {
            return
        }
        // TODO: Call superclass default constructor with our default constructor params
        superclassCall = "\(superclass.qualifiedDescription)()"
    }
}

struct KotlinExtensionDeclaration {
    static func translate(statement: ExtensionDeclaration, translator: KotlinTranslator) -> [KotlinStatement] {
        // If the extension is on a type outside this module or is on a protocol, use Kotlin extension
        // functions. Otherwise do not translate the extension - instead we'll move its members into
        // our declaration of its extended type
        let declarationType = translator.codebaseInfo.declarationType(of: statement.extends.qualifiedDescription)
        guard declarationType == nil || declarationType == .protocolDeclaration else {
            return []
        }

        var kotlinStatements: [KotlinStatement] = []
        if !statement.inherits.isEmpty {
            kotlinStatements.append(KotlinMessageStatement(message: Message(severity: .warning, message: "Cannot add protocol conformances via extensions to Kotlin interfaces or to types defined outside this module", file: statement.file, range: statement.range)))
        }
        for member in statement.members.flatMap({ translator.translateStatement($0) }) {
            guard let memberDeclaration = member as? KotlinMemberDeclaration else {
                kotlinStatements.append(KotlinMessageStatement(message: Message(severity: .warning, message: "This declaration is not supported in Kotlin extensions", file: member.sourceFile, range: member.sourceRange)))
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
    var modifiers: Modifiers
    var isAsync: Bool
    var isOpen = false
    var isProtocolFunction = false
    var body: CodeBlock<KotlinStatement>?

    // KotlinMemberDeclaration
    var extends: TypeSignature?
    var isStatic: Bool {
        return modifiers.isStatic
    }

    static func translate(statement: FunctionDeclaration, translator: KotlinTranslator) -> KotlinFunctionDeclaration {
        let kstatement = KotlinFunctionDeclaration(statement: statement)
        kstatement.returnType = statement.returnType
        kstatement.parameters = statement.parameters.map { parameter in
            var kdefaultValue: KotlinStatement? = nil
            if let defaultValue = parameter.defaultValue {
                kdefaultValue = translator.translateStatement(defaultValue).first
            }
            return Parameter(externalName: parameter.externalName, internalName: parameter.internalName, type: parameter.type, isVariadic: parameter.isVariadic, defaultValue: kdefaultValue)
        }
        if let owningTypeDeclaration = statement.owningTypeDeclaration {
            kstatement.isOpen = !statement.modifiers.isFinal && statement.modifiers.visibility != .private && owningTypeDeclaration.type == .classDeclaration && !owningTypeDeclaration.modifiers.isFinal
            kstatement.isProtocolFunction = translator.codebaseInfo.isProtocolFunction(declaration: statement, in: owningTypeDeclaration)
        }
        if let body = statement.body {
            let bodyStatements = body.statements.flatMap { translator.translateStatement($0) }
            kstatement.body = CodeBlock(statements: bodyStatements)
        }
        return kstatement
    }

    private init(statement: FunctionDeclaration) {
        self.name = statement.name
        self.modifiers = statement.modifiers
        self.isAsync = statement.isAsync
        super.init(type: .functionDeclaration, statement: statement)
    }

    override var children: [KotlinStatement] {
        return parameters.compactMap { $0.defaultValue }
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
                output.append("public ")
            case .public:
                output.append("public ")
            case .private:
                output.append("private ")
            }
            if isOpen {
                output.append("open ")
            }
            if isAsync {
                output.append("suspend ")
            }

            output.append("fun ")
            if let extends {
                output.append(extends.qualifiedDescription).append(".")
                if isStatic {
                    output.append("Companion.")
                }
            }
            output.append(name).append("(")
            for entry in parameters.enumerated() {
                let parameter = entry.element
                let name = parameter.externalName.isEmpty ? parameter.internalName : parameter.externalName
                output.append(name)
                output.append(": ")
                output.append(parameter.type?.qualifiedDescription ?? "Any")
                if let defaultValue = parameter.defaultValue {
                    output.append(" = ").append(defaultValue, indentation: 0)
                }
                if entry.offset != parameters.count - 1 {
                    output.append(", ")
                }
            }
            output.append("): \(returnType?.qualifiedDescription ?? "Unit")")
        }
        if let body {
            output.append(" {\n")
            output.append(body.statements, indentation: indentation.inc())
            output.append(indentation).append("}\n")
        }
    }
}

class KotlinImportDeclaration: KotlinStatement {
    let modulePath: [String]

    init(statement: ImportDeclaration) {
        self.modulePath = statement.modulePath
        super.init(type: .importDeclaration, statement: statement)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation)
        output.append("import ")
        output.append(modulePath.joined(separator: "."))
        if modulePath.count == 1 {
            output.append(".*")
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
        return kstatement
    }

    private init(statement: TypeDeclaration) {
        self.name = statement.name
        self.inherits = statement.inherits
        self.modifiers = statement.modifiers
        super.init(type: .interfaceDeclaration, statement: statement)
    }

    override var children: [KotlinStatement] {
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
                output.append(inherits.map({ $0.qualifiedDescription }).joined(separator: ", "))
            }
        }
        output.append(" {\n")
        children.forEach { output.append($0, indentation: indentation.inc()) }
        output.append(indentation).append("}\n")
    }
}
