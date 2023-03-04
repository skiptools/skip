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
    /// - Seealso: `CrossFoundation.Any.sref()`
    func valueReference(onUpdate: String? = nil) -> KotlinExpression {
        // If an update block is supplied, we need to perform a sref even if the value isn't shared so
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

    /// Create a new expression that is the logical negation of this one.
    func logicalNegated() -> KotlinExpression {
        var target: KotlinExpression = self
        if target.isCompoundExpression {
            target = KotlinParenthesized(content: target)
        }
        return KotlinPrefixOperator(operatorSymbol: "!", target: target)
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

/// Special expression type that points to an expression elsewhere in the syntax tree.
///
/// - Note: The shared expression is not included as a child, because it will already have a parent.
class KotlinSharedExpressionPointer: KotlinExpression {
    let shared: KotlinExpression

    init(shared: KotlinExpression) {
        self.shared = (shared as? KotlinSharedExpressionPointer)?.shared ?? shared
        super.init(type: .sharedExpressionPointer)
    }

    override func mayBeSharedMutableValueExpression(orType: Bool) -> Bool {
        return shared.mayBeSharedMutableValueExpression(orType: orType)
    }

    override var isCompoundExpression: Bool {
        return shared.isCompoundExpression
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(shared, indentation: indentation)
    }
}
