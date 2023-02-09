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

    /// Return an expression that creates a by-value copy of the result of this expression if needed to maintain proper semantics for value types.
    ///
    /// - Seealso: `SkipFoundation.Any.valref()`
    final var valueReference: KotlinExpression {
        guard mayBeSharedMutableValueExpression(orType: false) else {
            return self
        }
        let valueReferenceFunction = KotlinMemberAccess(base: self, member: "valref")
        let functionCall = KotlinFunctionCall(function: valueReferenceFunction, arguments: [])
        functionCall.mayBeSharedMutableValue = true
        return functionCall
    }

    /// Return true if this expression may evaluate to a shared mutable value type.
    ///
    /// - Parameters:
    ///   - Parameter orType: If set, also return true if the type of this expression may be a shared mutable value. E.g. an array literal is not shared, but its type is a shared mutable type.
    func mayBeSharedMutableValueExpression(orType: Bool) -> Bool {
        return false
    }

    /// Return true if this is a multi-part expression requiring parenthesization to operate on.
    var isCompoundExpression: Bool {
        return false
    }

    final override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation)
        append(to: output)
    }

    func append(to output: OutputGenerator) {
    }
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
