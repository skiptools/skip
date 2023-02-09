import SwiftSyntax

/// A node in the syntax tree.
class SyntaxNode: SourceDerived, PrettyPrintable {
    let nodeName: String
    let syntax: SyntaxProtocol?
    let sourceFile: Source.File?
    let sourceRange: Source.Range?

    init(nodeName: String, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.nodeName = nodeName
        self.syntax = syntax
        self.sourceFile = sourceFile
        self.sourceRange = sourceRange
    }

    /// Resolve contextual information about this node's attributes after the parent node is set.
    func resolveAttributes() {
    }

    /// Perform type inference.
    ///
    /// This is called after `resolve`.
    @discardableResult func inferTypes(context: TypeInferenceContext, expecting: TypeSignature = .none) -> TypeInferenceContext {
        children.forEach { $0.inferTypes(context: context) }
        return context
    }

    /// The inferred type of this expression.
    var inferredType: TypeSignature {
        return .none
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

    /// Traverse up the syntax tree to fully qualify a type name.
    final func qualifyReferencedTypeName(_ typeName: String) -> String {
        // Look for a qualified name whose last token(s) are the given type name
        let suffix = ".\(typeName)"
        var current: SyntaxNode? = self
        while current != nil {
            // Find the next declared type up the statement chain
            guard let owningType = current?.owningTypeDeclaration else {
                break
            }
            // Look for any direct child of that type with a matching qualified name
            if let referencedType = owningType.children.first(where: { ($0 as? TypeDeclaration)?.qualifiedName.hasSuffix(suffix) == true }) {
                return (referencedType as! TypeDeclaration).qualifiedName
            }
            // Move up to the next owning type and repeat
            current = owningType.parent
        }
        return typeName
    }

    /// Traverse up the syntax tree to fully qualify a type name declared by a class, struct, etc.
    final func qualifyDeclaredTypeName(_ typeName: String) -> String {
        if let typeDeclaration = parent?.owningTypeDeclaration {
            return "\(typeDeclaration.qualifiedName).\(typeName)"
        }
        return typeName
    }
}
