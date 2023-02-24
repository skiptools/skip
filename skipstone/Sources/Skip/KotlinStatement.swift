/// A node in the Kotlin syntax tree.
class KotlinStatement: KotlinSyntaxNode {
    let type: KotlinStatementType
    var extras: StatementExtras?

    init(type: KotlinStatementType, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
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

    /// Visit this statement and its children depth first, performing the given action.
    ///
    /// - Parameters:
    ///   - Parameter perform: The action to perform.
    /// - Warning: This method does not traverse through `Expressions` to find additional statements (e.g. in closures).
    func visitStatements(perform: (KotlinStatement) -> VisitResult<KotlinStatement>) {
        if case .recurse(let onLeave) = perform(self) {
            for child in children {
                if let statement = child as? KotlinStatement {
                    statement.visitStatements(perform: perform)
                }
            }
            if let onLeave {
                onLeave(self)
            }
        }
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
    var extends: TypeSignature? { get set }
    var isStatic: Bool { get }
}

class KotlinCodeBlockStatement: KotlinStatement {
    var statements: [KotlinStatement]

    static func translate(statement: CodeBlockStatement, translator: KotlinTranslator) -> KotlinCodeBlockStatement {
        let kstatements = statement.statements.flatMap { translator.translateStatement($0) }
        return KotlinCodeBlockStatement(statements: kstatements)
    }

    init(statements: [KotlinStatement] = []) {
        self.statements = statements
        super.init(type: .codeBlock)
    }

    /// Perform any necessary updates to the return statements in this block.
    ///
    /// - Returns: Whether any return statements were found.
    @discardableResult func updateWithExpectedReturn(_ expectedReturn: ExpectedReturn) -> Bool {
        var label: String?
        var valref = false
        var returnRequired = false
        var onUpdate: String? = nil
        switch expectedReturn {
        case .no:
            // Don't shortcut and return here because we need to return whether any return statements were found
            break
        case .yes:
            returnRequired = true
        case .labelIfPresent(let l):
            label = l
        case .valueReference(let update):
            onUpdate = update
            valref = true
            returnRequired = true
        }

        var didFindReturn = false
        visitStatements { statement in
            switch statement.type {
            case .functionDeclaration:
                // Skip embedded functions that may have their own returns
                return .skip
            case .return:
                let returnStatement = statement as! KotlinReturn
                didFindReturn = true
                if let label {
                    returnStatement.label = label
                }
                if valref {
                    returnStatement.expression = returnStatement.expression?.valueReference(onUpdate: onUpdate)
                }
                return .skip
            default:
                break
            }
            return .recurse(nil)
        }
        if didFindReturn {
            return true
        }

        // If this was an implicit return, replace it with an explicit one if a return is required
        guard returnRequired, statements.count == 1, statements[0].type == .expression, var expression = (statements[0] as! KotlinExpressionStatement).expression else {
            return false
        }
        if valref {
            expression = expression.valueReference(onUpdate: onUpdate)
        }
        statements = [KotlinReturn(expression: expression)]
        return true
    }

    override var children: [KotlinSyntaxNode] {
        return statements
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(statements, indentation: indentation)
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

    init(type: KotlinStatementType = .expression, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
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
