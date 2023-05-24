/// A node in the Kotlin syntax tree.
class KotlinExpression: KotlinSyntaxNode {
    let type: KotlinExpressionType

    init(type: KotlinExpressionType, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.type = type
        super.init(nodeName: String(describing: type), sourceFile: sourceFile, sourceRange: sourceRange)
    }

    init(type: KotlinExpressionType, expression: Expression) {
        self.type = type
        super.init(nodeName: String(describing: type), sourceFile: expression.sourceFile, sourceRange: expression.sourceRange)
        self.messages = expression.messages
    }

    /// Return an expression that creates a by-value copy of the result of this expression if needed to maintain proper semantics for struct types.
    ///
    /// - Seealso: `SkipFoundation.Any.sref()`
    func sref(onUpdate: String? = nil) -> KotlinExpression {
        // If an update block is supplied, we need to perform a sref even if the value isn't shared so
        // that the update is called on any mutation
        guard mayBeSharedMutableStructExpression(orType: onUpdate != nil) else {
            return self
        }
        return KotlinSRef(base: self, onUpdate: onUpdate)
    }

    /// Return true if this expression may evaluate to a shared mutable struct type.
    ///
    /// - Parameters:
    ///   - orType: If set, also return true if the type of this expression may be a shared mutable struct. E.g. an array literal is not shared, but its type is a shared mutable struct.
    func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
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

/// Expression that can be the target of an `await`.
protocol KotlinAwaitable {
    var apiFlags: APIFlags? { get }
    var isInAwait: Bool { get set }
}

enum KotlinAwaitableMode {
    case none
    /// Call must be isolated to main actor.
    case mainActor
    /// Call is a function reference that will be appended to to form a function call that must be on the main actor.
    case mainActorFunctionReference
}

extension KotlinAwaitable where Self: KotlinSyntaxNode {
    /// Whether to add actor isolation to the call site.
    var awaitableOutputMode: KotlinAwaitableMode {
        guard isInAwait else {
            return .none
        }
        guard let mode = awaitableMode, mode != .none else {
            return .none
        }
        // Are we already in an isolated mode? See if we have an isolated parent before we hit the await call
        var parent = self.parent
        if mode == .mainActorFunctionReference {
            parent = parent?.parent // Traverse up to function's parent
        }
        while parent != nil && !(parent is KotlinAwait) {
            if let awaitable = parent as? (KotlinSyntaxNode & KotlinAwaitable), awaitable.awaitableOutputMode != .none {
                return .none
            }
            parent = parent?.parent
        }
        return mode
    }

    var awaitableMode: KotlinAwaitableMode? {
        if let functionCall = parent as? KotlinFunctionCall, functionCall.function === self {
            if let functionCallMode = functionCall.awaitableMode {
                return functionCallMode == .none ? KotlinAwaitableMode.none : .mainActorFunctionReference
            } else {
                return nil
            }
        } else if let subscriptCall = parent as? KotlinSubscript, subscriptCall.base === self {
            if let subscriptCallMode = subscriptCall.awaitableMode {
                return subscriptCallMode == .none ? KotlinAwaitableMode.none : .mainActorFunctionReference
            } else {
                return nil
            }
        } else if let apiFlags {
            return !apiFlags.contains(.async) && apiFlags.contains(.mainActor) ? .mainActor : KotlinAwaitableMode.none
        } else {
            return nil
        }
    }
}

class KotlinRawExpression: KotlinExpression {
    let sourceCode: String

    init(sourceCode: String, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
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

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        return shared.mayBeSharedMutableStructExpression(orType: orType)
    }

    override var isCompoundExpression: Bool {
        return shared.isCompoundExpression
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(shared, indentation: indentation)
    }
}
