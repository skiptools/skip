/// A node in the Kotlin syntax tree.
///
/// Kotlin expressions are generally mutable, as we may modify the tree in order to generate the desired Kotlin output.
class KotlinExpression: OutputNode {
    let type: KotlinExpressionType
    let sourceFile: Source.File?
    let sourceRange: Source.Range?

    init(type: KotlinExpressionType, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.type = type
        self.sourceFile = sourceFile
        self.sourceRange = sourceRange
    }

    init(type: KotlinExpressionType, expression: Expression) {
        self.type = type
        self.sourceFile = expression.file
        self.sourceRange = expression.range
        self.expressionMessages = expression.expressionMessages
    }

    var children: [KotlinExpression] {
        return []
    }

    /// Any messages about this expression.
    var expressionMessages: [Message] = []

    /// Recursive traversal of all messages from the tree rooted on this syntax expression.
    final var messages: [Message] {
        return expressionMessages + children.flatMap { $0.messages }
    }

    final func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation)
        append(to: output)
    }

    func append(to output: OutputGenerator) {
    }

    final func leadingTrivia(indentation: Indentation) -> String {
        return ""
    }

    final func trailingTrivia(indentation: Indentation) -> String {
        return ""
    }
}

/// Types of Kotlin expressions.
enum KotlinExpressionType {
    case booleanLiteral
    case numericLiteral
    case stringLiteral

    case raw
}

class KotlinRawExpression: KotlinExpression {
    let sourceCode: String

    init(expression: RawExpression) {
        self.sourceCode = expression.sourceCode
        super.init(type: .raw, expression: expression)
    }

    override func append(to output: OutputGenerator) {
        output.append(sourceCode)
    }
}
