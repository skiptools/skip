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
    func sref(onUpdate: (() -> String)? = nil) -> KotlinExpression {
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

    /// Return whether this expression is part of an optional chain.
    var optionalChain: KotlinOptionalChain {
        return .none
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

enum KotlinOptionalChain {
    case none
    /// Chained call with ?.
    case explicit
    /// Part of a chain of calls that originates with ?.
    case implicit
}

/// Expression that participates in main actor targeting.
protocol KotlinMainActorTargeting {
    var apiFlags: APIFlags? { get }
    var isInAwait: Bool { get set }
    var isInMainActorContext: Bool { get set }
    /// The main actor mode of the given child node.
    func mainActorMode(for child: KotlinSyntaxNode) -> KotlinMainActorMode
}

enum KotlinMainActorMode {
    case none
    /// Call must be isolated to main actor.
    case isolated
    /// Call is a function reference wose arguments will be appended to form a function call that must be on the main actor.
    case isolatedFunctionReference
}

extension KotlinMainActorTargeting where Self: KotlinSyntaxNode {
    /// Whether to add main actor isolation to the call site.
    ///
    /// - Returns: A tuple of (1) the effective isolation mode needed, and (2) the mode to encode into the output of this node.
    ///     These values may be different if a parent node's isolation will capture and isolate this node already.
    var mainActorMode: (effective: KotlinMainActorMode, output: KotlinMainActorMode) {
        guard isInAwait && !isInMainActorContext else {
            return (.none, .none)
        }
        guard let needsMainActorIsolation = self.needsMainActorIsolation else {
            return (.none, .none)
        }
        let mode: KotlinMainActorMode = needsMainActorIsolation ? .isolated : .none

        // Are we already captured in an isolated call? See if we have an isolated parent before we hit the await call
        var child: KotlinSyntaxNode = self
        while child.parent != nil && !(child.parent is KotlinAwait) {
            if let mainActorTargeting = child.parent as? (KotlinSyntaxNode & KotlinMainActorTargeting) {
                let parentMode = mainActorTargeting.mainActorMode
                if parentMode.effective != .none {
                    // If parent is isolated, ask the parent how it captures this child
                    let childMode = mainActorTargeting.mainActorMode(for: child)
                    switch childMode {
                    case .none:
                        // Parent won't output child as main actor, so child should handle it
                        return (mode, mode)
                    case .isolated:
                        // Parent will include child in main actor isolation, so child does nothing
                        return (mode, .none)
                    case .isolatedFunctionReference:
                        // Parent is a function call. If the parent is outputting the end of the isolation code
                        // along with the function arguments, we have to output the beginning
                        return (.isolated, parentMode.output == .none ? .none : .isolatedFunctionReference)
                    }
                }
                // Parent is not isolated, so child should handle it
                return (mode, mode)
            }
            child = child.parent!
        }
        return (mode, mode)
    }

    var needsMainActorIsolation: Bool? {
        guard let apiFlags else {
            return nil
        }
        return !apiFlags.contains(.async) && apiFlags.contains(.mainActor)
    }
}

/// An expression that can take part in a binding.
protocol KotlinSwiftUIBindable {
    /// Whether this is a binding expression.
    var isSwiftUIBinding: Bool { get }
    
    /// Append this expression as part of a binding path, using the given block to append the remaining path.
    ///
    /// This is called by a parent expression in place of `append` when the child's `isBinding` is `true`.
    func appendSwiftUIBindingPath(to output: OutputGenerator, indentation: Indentation, appendPath: @escaping (OutputGenerator, Indentation, KotlinBindableBase) -> Void)
}

typealias KotlinBindableBase = (OutputGenerator, Indentation) -> Void

extension KotlinSwiftUIBindable {
    /// Helper function for bindables to create an instance binding.
    func appendInstanceBinding(to output: OutputGenerator, indentation: Indentation, isBoundInstance: Bool = false, appendPath: (OutputGenerator, Indentation, KotlinBindableBase) -> Void, appendInstance: () -> Void) {
        output.append(isBoundInstance ? "Binding.boundInstance(" : "Binding.instance(")
        appendInstance()
        output.append(", { ")
        appendPath(output, indentation) { output, _ in output.append("it") }
        output.append(" }, { it, newvalue -> ")
        appendPath(output, indentation) { output, _ in output.append("it") }
        output.append(" = newvalue })")
    }
}

/// An expression that can act as the target of a cast operation.
protocol KotlinCastTarget {
    var generics: [TypeSignature]? { get }
    var castTargetType: KotlinCastTargetType { get set }
}

enum KotlinCastTargetType {
    case none, target, typeErasedTarget
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

    override var optionalChain: KotlinOptionalChain {
        return shared.optionalChain
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(shared, indentation: indentation)
    }
}
