/// A node in the Kotlin syntax tree.
///
/// Kotlin statements are generally mutable, as we may modify the tree in order to generate the desired Kotlin output.
class KotlinStatement: OutputNode {
    let type: KotlinStatementType
    let sourceFile: Source.File?
    let sourceRange: Source.Range?
    let extras: StatementExtras?

    init(type: KotlinStatementType, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.type = type
        self.sourceFile = sourceFile
        self.sourceRange = sourceRange
        self.extras = extras
    }

    init(type: KotlinStatementType, statement: Statement) {
        self.type = type
        self.sourceFile = statement.file
        self.sourceRange = statement.range
        self.extras = statement.extras
        if self.message == nil {
            self.message = statement.message
        }
    }

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

enum KotlinStatementType {
    case classDeclaration
    case extensionDeclaration
    case functionDeclaration
    case importDeclaration
    case protocolDeclaration
    case variableDeclaration

    /// A statement representing raw Kotlin code.
    case raw
    /// A statement that only exists to add a message to the syntax tree.
    case message
}
