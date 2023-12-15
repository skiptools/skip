import SwiftSyntax

/// A node in the syntax tree.
class SyntaxNode: SourceDerived, PrettyPrintable {
    let nodeName: String
    let syntax: SyntaxProtocol?
    let sourceFile: Source.FilePath?
    let sourceRange: Source.Range?

    init(nodeName: String, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.nodeName = nodeName
        self.syntax = syntax
        self.sourceFile = sourceFile
        self.sourceRange = sourceRange
    }

    /// If this node declares a new type, fully qualify its signature.
    ///
    /// This is done to fully qualify class, struct, etc signatures before we resolve all attributes and their types.
    func qualifyTypeDeclaration() {
    }

    /// Resolve contextual information about this node's attributes and types after the parent node is set.
    func resolveAttributes(in syntaxTree: SyntaxTree, context: TypeResolutionContext) {
    }

    /// Resolve this node and all nodes beneath it.
    final func resolveSubtreeAttributes(in syntaxTree: SyntaxTree, context: TypeResolutionContext) {
        // First we fully qualify class, struct, etc declaration signatures
        qualifySubtreeTypeDeclarationsAndAssignParents()
        // Then we resolve references to those types
        resolveQualifiedSubtreeAttributes(in: syntaxTree, context: context)
    }

    private func qualifySubtreeTypeDeclarationsAndAssignParents() {
        qualifyTypeDeclaration()
        for child in children {
            child.parent = self
            child.qualifySubtreeTypeDeclarationsAndAssignParents()
        }
    }

    private func resolveQualifiedSubtreeAttributes(in syntaxTree: SyntaxTree, context: TypeResolutionContext) {
        resolveAttributes(in: syntaxTree, context: context)
        children.forEach { $0.resolveQualifiedSubtreeAttributes(in: syntaxTree, context: context) }
    }

    /// Perform type inference.
    ///
    /// This is called after `resolveAttributes`.
    @discardableResult func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        children.forEach { $0.inferTypes(context: context, expecting: .none) }
        return context
    }

    /// The inferred type of this expression.
    var inferredType: TypeSignature {
        return .none
    }

    /// Visit this node and its children depth first, performing the given action.
    ///
    /// - Parameters:
    ///   - perform: The action to perform.
    func visit(perform: (SyntaxNode) -> VisitResult<SyntaxNode>) {
        if case .recurse(let onLeave) = perform(self) {
            for child in children {
                child.visit(perform: perform)
            }
            if let onLeave {
                onLeave(self)
            }
        }
    }

    weak var parent: SyntaxNode?
    var children: [SyntaxNode] {
        return []
    }

    /// Pretty print child trees for this node's attributes, excluding `children`.
    var prettyPrintAttributes: [PrettyPrintTree] {
        return []
    }

    final var prettyPrintTree: PrettyPrintTree {
        var subtrees = prettyPrintAttributes
        if inferredType != .none {
            subtrees.append(PrettyPrintTree(root: "inferredType", children: [PrettyPrintTree(root: inferredType.description)]))
        }
        subtrees += children.map { $0.prettyPrintTree }
        return PrettyPrintTree(root: nodeName, children: subtrees)
    }

    var messages: [Message] = []

    /// All messages rooted in this subtree.
    var subtreeMessages: [Message] {
        return messages + children.flatMap { $0.subtreeMessages }
    }

    public var messageSourceRange: Source.Range? {
        return nil
    }

    /// Find the nearest type declaration by traversing up the syntax tree.
    final var owningTypeDeclaration: TypeDeclaration? {
        var current: SyntaxNode? = self
        while current != nil {
            if let typeDeclaration = current as? TypeDeclaration {
                return typeDeclaration
            }
            current = current?.parent
        }
        return nil
    }

    /// Whether this node is at the global/root level.
    final var isGlobal: Bool {
        return owningTypeDeclaration == nil && parent?.parent == nil
    }

    /// Find the nearest function, subscript, or variable getter/setter declaration by traversing up the syntax tree.
    ///
    /// Returns `nil` if we encounter a type before a function.
    final var owningFunctionDeclaration: Statement? {
        var current: SyntaxNode? = self
        while current != nil {
            if let statement = current as? Statement {
                switch statement.type {
                case .functionDeclaration, .initDeclaration, .subscriptDeclaration, .variableDeclaration:
                    return statement
                case .actorDeclaration, .classDeclaration, .enumDeclaration, .extensionDeclaration, .protocolDeclaration, .structDeclaration:
                    return nil
                default:
                    break
                }
            }
            current = current?.parent
        }
        return nil
    }

    /// Whether this node is called as a function.
    final var isCalledAsFunction: Bool {
        return self === (parent as? FunctionCall)?.function
    }

    /// Whether this node is within an `#if SKIP` block in the source.
    final var isInSkipBlock: Bool {
        var node: SyntaxNode? = self
        while node != nil {
            if (node as? Statement)?.extras?.directives.contains(.skipBlock) == true {
                return true
            }
            node = node?.parent
        }
        return false
    }

    /// Traverse up the syntax tree to fully qualify a type.
    ///
    /// - Returns: A qualified type or a typealiased type signature whose type must then be resolved.
    final func qualifyReferencedNamedType(name: String, generics: [TypeSignature], context: TypeResolutionContext) -> (qualified: TypeSignature, isGenericParameter: Bool) {
        // Is this type a generic of the enclosing function?
        if generics.isEmpty, let owningFunction = owningFunctionDeclaration as? FunctionDeclaration {
            if let generic = owningFunction.generics.entries.first(where: { $0.name == name }) {
                return (generic.namedType, true)
            }
        }

        // Look for a qualified name whose last token is the given type name
        let suffix = ".\(name)"
        var current: SyntaxNode? = self
        while current != nil {
            // Find the next declared type up the statement chain
            guard let owningType = current?.owningTypeDeclaration else {
                break
            }
            // Look for any direct child of that type with a matching qualified name
            if let referencedType = owningType.members.first(where: { ($0 as? TypeDeclaration)?.signature.name.hasSuffix(suffix) == true }) {
                return ((referencedType as! TypeDeclaration).signature.withGenerics(generics), false)
            } else if let referencedTypealias = owningType.members.first(where: { ($0 as? TypealiasDeclaration)?.name == name }) {
                return ((referencedTypealias as! TypealiasDeclaration).signature.withGenerics(generics), false)
            } else if generics.isEmpty, let generic = owningType.generics.entries.first(where: { $0.name == name }) {
                return (generic.namedType, true)
            }
            // Move up to the next owning type and repeat
            current = owningType.parent
        }
        let type: TypeSignature = .named(name, generics)
        if let owningType = owningTypeDeclaration {
            return (context.qualifyInherited(type: type, in: owningType.signature), false)
        } else {
            return (type, false)
        }
    }

    /// Traverse up the syntax tree to fully qualify a type name declared by a class, struct, etc.
    final func qualifyDeclaredType(_ type: TypeSignature) -> TypeSignature {
        if let typeDeclaration = parent?.owningTypeDeclaration {
            return type.asMember(of: typeDeclaration.signature)
        }
        return type
    }
}
