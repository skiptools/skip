/// A node in the Kotlin syntax tree.
protocol KotlinStatement: OutputNode {
    /// A human-readable type name for this statement.
    var statementType: String { get }
    var sourceFile: Source.File? { get }
    var sourceRange: Source.Range? { get }
    var extras: StatementExtras? { get }
    var children: [KotlinStatement] { get }

    /// Pretty-printable tree rooted on this syntax statement.
    var prettyPrintTree: PrettyPrintTree { get }

    /// Any message about this statement.
    var message: Message? { get }

    /// Recursive traversal of all messages from the tree rooted on this syntax statement.
    var messages: [Message] { get }
}

extension KotlinStatement {
    var sourceFile: Source.File? {
        return nil
    }

    var sourceRange: Source.Range? {
        return nil
    }

    var extras: StatementExtras? {
        return nil
    }

    var children: [KotlinStatement] {
        return []
    }

    var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintTree(root: statementType, children: prettyPrintChildren + children.map { $0.prettyPrintTree })
    }

    var prettyPrintChildren: [PrettyPrintTree] {
        return []
    }

    var message: Message? {
        return nil
    }

    var messages: [Message] {
        var messages: [Message] = []
        if let message, extras?.directives.contains(.nowarn) != true {
            messages.append(message)
        }
        return messages + children.flatMap { $0.messages }
    }

    func leadingTrivia(indentation: Indentation) -> String {
        return extras?.leadingTrivia(indentation: indentation) ?? ""
    }
}

/// Implemented by many of our`Statement` types below that translate themselves to Kotlin.
protocol KotlinTranslatable {
    func kotlinStatements(with translator: KotlinTranslator) -> [KotlinStatement]
}

/// Create a Kotlin statement with populated state, rather than writing a custom type.
struct PopulatedKotlinStatement: KotlinStatement {
    let statementType: String
    var sourceFile: Source.File?
    var sourceRange: Source.Range?
    var extras: StatementExtras?
    var children: [KotlinStatement]
    var message: Message?
    var prettyPrintChildrenCall: () -> [PrettyPrintTree]
    var outputCall: (OutputGenerator, Indentation, [KotlinStatement]) -> Void

    init(statementType: String, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil, children: [KotlinStatement] = [], message: Message? = nil, prettyPrintChildrenCall: @escaping () -> [PrettyPrintTree] = { [] }, outputCall: @escaping (OutputGenerator, Indentation, [KotlinStatement]) -> Void = { _, _, _ in }) {
        self.statementType = statementType
        self.sourceFile = sourceFile
        self.sourceRange = sourceRange
        self.extras = extras
        self.children = children
        self.message = message
        self.prettyPrintChildrenCall = prettyPrintChildrenCall
        self.outputCall = outputCall
    }

    init(statement: Statement, translator: KotlinTranslator, outputCall: @escaping (OutputGenerator, Indentation, [KotlinStatement]) -> Void = { _, _, _ in }) {
        self.statementType = String(describing: statement.type)
        self.sourceFile = statement.file
        self.sourceRange = statement.range
        self.extras = statement.extras
        self.children = statement.children.flatMap { translator.translateStatement($0) }
        self.message = statement.message
        self.prettyPrintChildrenCall = { statement.prettyPrintChildren }
        self.outputCall = outputCall
    }

    var prettyPrintChildren: [PrettyPrintTree] {
        return prettyPrintChildrenCall()
    }

    func append(to output: OutputGenerator, indentation: Indentation) {
        outputCall(output, indentation, children)
    }
}

extension ImportDeclaration: KotlinTranslatable {
    func kotlinStatements(with translator: KotlinTranslator) -> [KotlinStatement] {
        let statement = PopulatedKotlinStatement(statement: self, translator: translator) { output, indentation, _ in
            output.append(indentation)
            output.append("import ")
            output.append(modulePath.joined(separator: "."))
            output.append("\n")
        }
        return [statement]
    }
}

extension ProtocolDeclaration: KotlinTranslatable {
    func kotlinStatements(with translator: KotlinTranslator) -> [KotlinStatement] {
        let statement = PopulatedKotlinStatement(statement: self, translator: translator) { output, indentation, children in
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
        return [statement]
    }
}

extension RawStatement: KotlinTranslatable {
    func kotlinStatements(with translator: KotlinTranslator) -> [KotlinStatement] {
        let statement = PopulatedKotlinStatement(statement: self, translator: translator) { output, indentation, _ in
            output.append(indentation)
            output.append(sourceCode)
            output.append("\n")
        }
        return [statement]
    }
}

extension MessageStatement: KotlinTranslatable {
    func kotlinStatements(with translator: KotlinTranslator) -> [KotlinStatement] {
        let statement = PopulatedKotlinStatement(statement: self, translator: translator)
        return [statement]
    }
}
