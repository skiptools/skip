/// A node in the Kotlin syntax tree.
class KotlinStatement: OutputNode {
    /// A human-readable type name for this statement.
    let statementType: String
    let sourceFile: Source.File?
    let sourceRange: Source.Range?
    let extras: StatementExtras?

    init(statementType: String, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.statementType = statementType
        self.sourceFile = sourceFile
        self.sourceRange = sourceRange
        self.extras = extras
    }

    weak var parent: KotlinStatement?
    var children: [KotlinStatement] = [] {
        didSet {
            children.forEach { $0.parent = self }
        }
    }

    /// Any pretty print child trees aside from this node's child statements.
    var prettyPrintChildren: [PrettyPrintTree] {
        return []
    }

    /// Pretty-printable tree rooted on this syntax statement.
    final var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintTree(root: statementType, children: prettyPrintChildren + children.map { $0.prettyPrintTree })
    }

    /// Any message about this statement.
    var message: Message?

    /// Recursive traversal of all messages from the tree rooted on this syntax statement.
    final var messages: [Message] {
        var messages: [Message] = []
        if let message, extras?.suppressMessage != true {
            messages.append(message)
        }
        return messages + children.flatMap { $0.messages }
    }

    final func leadingTrivia(indentation: Indentation) -> String {
        return extras?.leadingTrivia(indentation: indentation) ?? ""
    }

    final func trailingTrivia(indentation: Indentation) -> String {
        return extras?.trailingTrivia(indentation: indentation) ?? ""
    }

    func append(to output: OutputGenerator, indentation: Indentation) {
    }
}

/// Implemented by many of our`Statement` types that translate themselves to Kotlin.
protocol KotlinTranslatable {
    func kotlinStatements(translator: KotlinTranslator) -> [KotlinStatement]
}

/// Create a Kotlin statement with populated state, rather than writing a custom type.
class PopulatedKotlinStatement: KotlinStatement {
    let prettyPrintChildrenCall: () -> [PrettyPrintTree]
    let outputCall: (OutputGenerator, Indentation, [KotlinStatement]) -> Void

    init(statementType: String, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil, prettyPrintChildrenCall: @escaping () -> [PrettyPrintTree] = { [] }, outputCall: @escaping (OutputGenerator, Indentation, [KotlinStatement]) -> Void = { _, _, _ in }) {
        self.prettyPrintChildrenCall = prettyPrintChildrenCall
        self.outputCall = outputCall
        super.init(statementType: statementType, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    init(statement: Statement, translator: KotlinTranslator, outputCall: @escaping (OutputGenerator, Indentation, [KotlinStatement]) -> Void = { _, _, _ in }) {
        self.prettyPrintChildrenCall = { statement.prettyPrintChildren }
        self.outputCall = outputCall
        super.init(statementType: String(describing: statement.type), sourceFile: statement.file, sourceRange: statement.range, extras: statement.extras)
        self.children = statement.children.flatMap { translator.translateStatement($0) }
        self.children.forEach { $0.parent = self }
        self.message = statement.message
    }

    override var prettyPrintChildren: [PrettyPrintTree] {
        return prettyPrintChildrenCall()
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        outputCall(output, indentation, children)
    }
}
