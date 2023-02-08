import SwiftSyntax

/// A node in the syntax tree.
///
/// Nodes are generally immutable after `resolve` is called with the parent set, allowing each node to finalize itself with any contextual information.
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

    var children: [SyntaxNode] {
        return []
    }

    /// Pretty print child trees for this node's attributes, excluding `children`.
    var prettyPrintAttributes: [PrettyPrintTree] {
        return []
    }

    final var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintTree(root: nodeName, children: prettyPrintAttributes + children.map { $0.prettyPrintTree })
    }

    var messages: [Message] = []

    /// All messages rooted in this subtree.
    var subtreeMessages: [Message] {
        return messages + children.flatMap { $0.subtreeMessages }
    }
}
