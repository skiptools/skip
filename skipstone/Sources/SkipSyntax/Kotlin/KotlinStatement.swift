/// A node in the Kotlin syntax tree.
class KotlinStatement: KotlinSyntaxNode {
    let type: KotlinStatementType
    var extras: StatementExtras?

    init(type: KotlinStatementType, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.type = type
        self.extras = extras
        super.init(nodeName: String(describing: type), sourceFile: sourceFile, sourceRange: sourceRange)
    }

    init(type: KotlinStatementType, statement: Statement) {
        self.type = type
        self.extras = statement.extras
        super.init(nodeName: String(describing: type), sourceFile: statement.sourceFile, sourceRange: statement.sourceRange)
        self.messages = statement.messages
    }

    /// Insert child statements.
    ///
    /// Must be overridden by supporting statement types.
    func insert(statements: [KotlinStatement], after statement: KotlinStatement?) {
        messages.append(.internalError(self))
    }

    /// Remove child statements.
    ///
    /// Must be overridden by supporting statement types.
    func remove(statement: KotlinStatement) {
        messages.append(.internalError(self))
    }

    final override var subtreeMessages: [Message] {
        if extras?.suppressMessages == true {
            // Filter out our own messages and any child Expression messages, but leave child statements
            return children.filter { $0 is KotlinStatement }.flatMap { $0.subtreeMessages }
        } else {
            return messages + children.flatMap { $0.subtreeMessages }
        }
    }

    final override func leadingTrivia(indentation: Indentation) -> String {
        return extras?.leadingTrivia(indentation: indentation) ?? ""
    }

    final override func trailingTrivia(indentation: Indentation) -> String {
        return extras?.trailingTrivia(indentation: indentation) ?? ""
    }

    /// The number of leading newlines detected in our leading trivia.
    final var leadingNewlines: Int {
        guard let extras else {
            return 0
        }
        var count = 0
        for leadingTrivia in extras.leadingTrivia {
            if leadingTrivia == "\n" {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    /// Attempt to ensure that this statement will contains at least the given number of leading newlines.
    ///
    /// Used to make output more readable.
    final func ensureLeadingNewlines(_ count: Int) {
        let additional = count - leadingNewlines
        guard additional > 0 else {
            return
        }
        let newlines = Array(repeating: "\n", count: additional)
        if extras == nil {
            extras = StatementExtras(directives: [], leadingTrivia: newlines, trailingTrivia: [])
        } else {
            extras!.leadingTrivia = newlines + extras!.leadingTrivia
        }
    }
}

/// Additional requirements for type members to handle extensions and companion objects in Kotlin.
protocol KotlinMemberDeclaration: AnyObject {
    var extends: (TypeSignature, Generics)? { get set }
    var isStatic: Bool { get }
    var visibility: Modifiers.Visibility { get set }
}

extension KotlinMemberDeclaration {
    func appendExtends(to output: OutputGenerator, indentation: Indentation) {
        guard let extends else {
            return
        }
        output.append(extends.0.withGenerics([]).kotlin)
        if !isStatic {
            extends.1.append(to: output, indentation: indentation)
        }
        output.append(".")
        if isStatic {
            output.append("Companion.")
        }
    }
}

/// Use cases to generate single-statement append syntax.
enum KotlinSingleStatementAppendMode {
    case `case`
    case closure
    case function
}

/// A statement **or expression** that can veto Kotlin's single-statement format, e.g. `fun f() = <statement>`.
///
/// Expressions are single-statement appendable by default. Statements are not.
protocol KotlinSingleStatementVetoing {
    func isSingleStatementAppendable(mode: KotlinSingleStatementAppendMode) -> Bool
}

/// A statement that can be appended in Kotlin single-statement format, e.g. `fun f() = <statement>`.
protocol KotlinSingleStatementAppendable: KotlinSingleStatementVetoing {
    func appendAsSingleStatement(to output: OutputGenerator, indentation: Indentation, mode: KotlinSingleStatementAppendMode)
}

extension KotlinSingleStatementAppendable {
    func isSingleStatementAppendable(mode: KotlinSingleStatementAppendMode) -> Bool {
        return true
    }
}

class KotlinExpressionStatement: KotlinStatement, KotlinSingleStatementAppendable {
    var expression: KotlinExpression?

    static func translate(statement: ExpressionStatement, translator: KotlinTranslator) -> KotlinExpressionStatement {
        let kstatement = KotlinExpressionStatement(statement: statement)
        if let expression = statement.expression {
            kstatement.expression = translator.translateExpression(expression)
        }
        return kstatement
    }

    init(type: KotlinStatementType = .expression, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        super.init(type: type, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    init(type: KotlinStatementType = .expression, statement: ExpressionStatement) {
        super.init(type: type, statement: statement)
    }

    init(expression: KotlinExpression?) {
        self.expression = expression
        super.init(type: .expression)
    }

    override var children: [KotlinSyntaxNode] {
        return expression == nil ? [] : [expression!]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if let expression {
            output.append(indentation).append(expression, indentation: indentation).append("\n")
        }
    }

    func isSingleStatementAppendable(mode: KotlinSingleStatementAppendMode) -> Bool {
        guard let expression else {
            return true
        }
        switch expression.type {
        case .functionCall:
            // Don't use single statement for calls that return Never
            if let functionIdentifier = (expression as! KotlinFunctionCall).function as? KotlinIdentifier, functionIdentifier.name == "fatalError" {
                return false
            }
        case .try:
            // Don't turn try/catch into a single statement. We've seen odd incompatibilities with try? and Unit functions
            return false
        default:
            return true
        }
        return true
    }

    func appendAsSingleStatement(to output: OutputGenerator, indentation: Indentation, mode: KotlinSingleStatementAppendMode) {
        if let expression {
            expression.append(to: output, indentation: indentation)
        } else if mode == .function {
            output.append("Unit")
        }
    }
}

class KotlinMessageStatement: KotlinStatement {
    init(message: Message, statement: Statement? = nil) {
        super.init(type: .message, sourceFile: statement?.sourceFile, sourceRange: statement?.sourceRange, extras: statement?.extras)
        self.messages.append(message)
    }

    init(statement: Statement) {
        super.init(type: .message, statement: statement)
    }
}

class KotlinRawStatement: KotlinStatement, KotlinSingleStatementAppendable {
    let sourceCode: String

    init(sourceCode: String, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.sourceCode = sourceCode
        super.init(type: .raw, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    init(statement: RawStatement) {
        self.sourceCode = statement.sourceCode
        super.init(type: .raw, statement: statement)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation).append(sourceCode).append("\n")
    }

    func appendAsSingleStatement(to output: OutputGenerator, indentation: Indentation, mode: KotlinSingleStatementAppendMode) {
        if mode == .function && sourceCode == "return" {
            output.append("Unit")
        } else if mode == .function && sourceCode.hasPrefix("return ") {
            output.append(String(sourceCode.dropFirst("return ".count)))
        } else {
            output.append(sourceCode)
        }
    }
}
