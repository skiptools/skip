/// A node in the Kotlin syntax tree.
protocol KotlinStatement {
    /// A human-readable type name for this statement.
    var statementType: String { get }
    var sourceRange: Source.Range? { get }
    var children: [KotlinStatement] { get }

    /// Kotlin source code. May be empty.
    func code(indentation: Indentation) -> String

    /// Pretty-printable tree rooted on this syntax statement.
    var prettyPrintTree: PrettyPrintTree { get }

    /// Any message about this statement.
    var message: Message? { get }

    /// Recursive traversal of all messages from the tree rooted on this syntax statement.
    var allMessages: [Message] { get }
}

extension KotlinStatement {
    var sourceRange: Source.Range? {
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

    var allMessages: [Message] {
        var messages: [Message] = []
        if let message {
            messages.append(message)
        }
        return messages + children.flatMap { $0.allMessages }
    }
}

/// Implemented by many of our`Statement` types below that translate themselves to Kotlin.
protocol KotlinTranslatable {
    func kotlinStatements(with translator: KotlinTranslator) -> [KotlinStatement]
}

/// Create a Kotlin statement with populated state, rather than creating a custom type.
struct PopulatedKotlinStatement: KotlinStatement {
    let statementType: String
    var sourceRange: Source.Range?
    var children: [KotlinStatement]
    var message: Message?
    var prettyPrintChildrenCall: () -> [PrettyPrintTree]
    var codeCall: (Indentation, [KotlinStatement]) -> String

    init(statementType: String, sourceRange: Source.Range? = nil, children: [KotlinStatement] = [], message: Message? = nil, prettyPrintChildrenCall: @escaping () -> [PrettyPrintTree] = { [] }, codeCall: @escaping (Indentation, [KotlinStatement]) -> String = { _, _ in "" }) {
        self.statementType = statementType
        self.sourceRange = sourceRange
        self.children = children
        self.message = message
        self.prettyPrintChildrenCall = prettyPrintChildrenCall
        self.codeCall = codeCall
    }

    init(statement: Statement, translator: KotlinTranslator, codeCall: @escaping (Indentation, [KotlinStatement]) -> String = { _, _ in "" }) {
        self.statementType = String(describing: statement.type)
        self.sourceRange = statement.range
        self.children = statement.children.flatMap { translator.translateStatement($0) }
        self.message = statement.message
        self.prettyPrintChildrenCall = { statement.prettyPrintChildren }
        self.codeCall = codeCall
    }

    var prettyPrintChildren: [PrettyPrintTree] {
        return prettyPrintChildrenCall()
    }

    func code(indentation: Indentation) -> String {
        return codeCall(indentation, children)
    }
}

extension ImportDeclaration: KotlinTranslatable {
    func kotlinStatements(with translator: KotlinTranslator) -> [KotlinStatement] {
        let statement = PopulatedKotlinStatement(statement: self, translator: translator) { indentation, _ in
            return "\(indentation)import \(modulePath.joined(separator: "."))"
        }
        return [statement]
    }
}

extension ProtocolDeclaration: KotlinTranslatable {
    func kotlinStatements(with translator: KotlinTranslator) -> [KotlinStatement] {
        let statement = PopulatedKotlinStatement(statement: self, translator: translator) { indentation, children in
            // TODO: Children
            return "\(indentation)interface \(name) {}"
        }
        return [statement]
    }
}

extension RawStatement: KotlinTranslatable {
    func kotlinStatements(with translator: KotlinTranslator) -> [KotlinStatement] {
        let statement = PopulatedKotlinStatement(statement: self, translator: translator) { indentation, _ in
            return "\(indentation)\(sourceCode)"
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
