/// A node in the Kotlin syntax tree.
class KotlinExpression: KotlinSyntaxNode {
    let type: KotlinExpressionType

    init(type: KotlinExpressionType, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.type = type
        super.init(nodeName: String(describing: type), sourceFile: sourceFile, sourceRange: sourceRange)
    }

    init(type: KotlinExpressionType, expression: Expression) {
        self.type = type
        super.init(nodeName: String(describing: type), sourceFile: expression.sourceFile, sourceRange: expression.sourceRange)
        self.messages = expression.messages
    }

    final override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation)
        append(to: output)
    }

    func append(to output: OutputGenerator) {
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
