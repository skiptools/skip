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
    func valueReference(onUpdate: String? = nil) -> KotlinExpression {
        // If an update block is supplied, we need to perform a valref even if the value isn't shared so
        // that the update is called on any mutation
        guard mayBeSharedMutableValueExpression(orType: onUpdate != nil) else {
            return self
        }
        return KotlinValueReference(base: self, onUpdate: onUpdate)
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
}

class KotlinRawExpression: KotlinExpression {
    let sourceCode: String

    init(sourceCode: String, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.sourceCode = sourceCode
        super.init(type: .raw, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    init(expression: RawExpression) {
        self.sourceCode = expression.sourceCode
        super.init(type: .raw, expression: expression)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(sourceCode)
    }
}
