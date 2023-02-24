/// A node in the Kotlin syntax tree.
///
/// Kotlin nodes are generally mutable.
class KotlinSyntaxNode: SourceDerived, OutputNode {
    let nodeName: String
    let sourceFile: Source.File?
    let sourceRange: Source.Range?

    init(nodeName: String, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.nodeName = nodeName
        self.sourceFile = sourceFile
        self.sourceRange = sourceRange
    }

    /// Visit this node and its children depth first, performing the given action.
    ///
    /// - Parameters:
    ///   - Parameter perform: The action to perform.
    func visit(perform: (KotlinSyntaxNode) -> VisitResult<KotlinSyntaxNode>) {
        if case .recurse(let onLeave) = perform(self) {
            for child in children {
                child.visit(perform: perform)
            }
            if let onLeave {
                onLeave(self)
            }
        }
    }

    weak var parent: KotlinSyntaxNode?
    var children: [KotlinSyntaxNode] {
        return []
    }

    /// Assign parent references below this node.
    final func assignParentReferences() {
        for child in children {
            child.parent = self
            child.assignParentReferences()
        }
    }

    var messages: [Message] = []

    /// All messages rooted in this subtree.
    var subtreeMessages: [Message] {
        return messages + children.flatMap { $0.subtreeMessages }
    }

    func leadingTrivia(indentation: Indentation) -> String {
        return ""
    }

    func trailingTrivia(indentation: Indentation) -> String {
        return ""
    }

    func append(to output: OutputGenerator, indentation: Indentation) {
    }
}
