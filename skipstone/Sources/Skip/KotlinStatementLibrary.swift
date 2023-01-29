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
        output.append(indentation)
        output.append(sourceCode)
        output.append("\n")
    }
}

// MARK: - Declarations

class KotlinClassDeclaration: KotlinStatement {
    let name: String
    var members: [KotlinStatement] = [] {
        didSet {
            members.forEach { $0.parent = self }
        }
    }

    static func translate(statement: ClassDeclaration, translator: KotlinTranslator) -> KotlinClassDeclaration {
        let kstatement = KotlinClassDeclaration(statement: statement)
        kstatement.members = statement.members.flatMap { translator.translateStatement($0) }
        return kstatement
    }

    private init(statement: ClassDeclaration) {
        self.name = statement.name
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
            // TODO: Visibility, generics, inheritance, children
            output.append("class ")
            output.append(name)
        }
        output.append(" {\n")
        children.forEach { output.append($0, indentation: indentation.inc()) }
        output.append(indentation)
        output.append("}\n")
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
        output.append("\n")
    }
}

class KotlinProtocolDeclaration: KotlinStatement {
    let name: String
    var members: [KotlinStatement] = [] {
        didSet {
            members.forEach { $0.parent = self }
        }
    }

    static func translate(statement: ProtocolDeclaration, translator: KotlinTranslator) -> KotlinProtocolDeclaration {
        let kstatement = KotlinProtocolDeclaration(statement: statement)
        kstatement.members = statement.members.flatMap { translator.translateStatement($0) }
        return kstatement
    }

    private init(statement: ProtocolDeclaration) {
        self.name = statement.name
        super.init(type: .protocolDeclaration, statement: statement)
    }

    override var children: [KotlinStatement] {
        return members
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation)
        if let declaration = extras?.declaration {
            output.append(declaration)
        } else {
            // TODO: Visibility, generics, inheritance, children
            output.append("interface ")
            output.append(name)
        }
        output.append(" {\n")
        children.forEach { output.append($0, indentation: indentation.inc()) }
        output.append(indentation)
        output.append("}\n")
    }
}
