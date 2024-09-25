/// A node in the Kotlin syntax tree.
///
/// Kotlin nodes are generally mutable.
class KotlinSyntaxNode: SourceDerived, OutputNode {
    let nodeName: String
    let sourceFile: Source.FilePath?
    let sourceRange: Source.Range?

    init(nodeName: String, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.nodeName = nodeName
        self.sourceFile = sourceFile
        self.sourceRange = sourceRange
    }

    /// Visit this node and its children depth first, performing the given action.
    ///
    /// - Parameters:
    ///   - perform: The action to perform.
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

    /// Insert any non-standard dependencies required by this node.
    func insertDependencies(into dependencies: inout KotlinDependencies) {
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

    /// Find the nearest type declaration by traversing up the syntax tree.
    final var owningTypeDeclaration: KotlinStatement? {
        var current: KotlinSyntaxNode? = self
        while current != nil {
            if current is KotlinClassDeclaration || current is KotlinInterfaceDeclaration {
                return current as? KotlinStatement
            }
            current = current?.parent
        }
        return nil
    }

    var messages: [Message] = []

    /// All messages rooted in this subtree.
    var subtreeMessages: [Message] {
        return messages + children.flatMap { $0.subtreeMessages }
    }

    public var messageSourceRange: Source.Range? {
        return nil
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
