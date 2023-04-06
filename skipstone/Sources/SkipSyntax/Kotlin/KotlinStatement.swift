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

    final override func leadingTrivia(indentation: Indentation) -> String {
        return extras?.leadingTrivia(indentation: indentation) ?? ""
    }

    final override func trailingTrivia(indentation: Indentation) -> String {
        return extras?.trailingTrivia(indentation: indentation) ?? ""
    }
}

/// Additional requirements for type members to handle extensions and companion objects in Kotlin.
protocol KotlinMemberDeclaration: AnyObject {
    var extends: (TypeSignature, Generics)? { get set }
    var isStatic: Bool { get }
}

extension KotlinMemberDeclaration {
    func appendExtends(to output: OutputGenerator, indentation: Indentation) {
        guard let extends else {
            return
        }
        output.append(extends.0.withGenerics([]).kotlin)
        extends.1.append(to: output, indentation: indentation)
        output.append(".")
        if isStatic {
            output.append("Companion.")
        }
    }
}

class KotlinExpressionStatement: KotlinStatement {
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

    override var children: [KotlinSyntaxNode] {
        return expression == nil ? [] : [expression!]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if let expression {
            output.append(indentation).append(expression, indentation: indentation).append("\n")
        }
    }
}

class KotlinMessageStatement: KotlinStatement {
    init(message: Message) {
        super.init(type: .message)
        self.messages = [message]
    }

    init(statement: Statement) {
        super.init(type: .message, statement: statement)
    }
}

class KotlinRawStatement: KotlinStatement {
    let sourceCode: String

    init(sourceCode: String) {
        self.sourceCode = sourceCode
        super.init(type: .raw)
    }

    init(statement: RawStatement) {
        self.sourceCode = statement.sourceCode
        super.init(type: .raw, statement: statement)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation).append(sourceCode).append("\n")
    }
}
