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

    convenience init(statementType: String, statement: Statement) {
        self.init(statementType: statementType, sourceFile: statement.file, sourceRange: statement.range, extras: statement.extras)
        if self.message == nil {
            self.message = statement.message
        }
    }

    weak var parent: KotlinStatement?
    var children: [KotlinStatement] {
        return []
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
