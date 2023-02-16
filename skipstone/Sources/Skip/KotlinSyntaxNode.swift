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

    var children: [KotlinSyntaxNode] {
        return []
    }

    var messages: [Message] = []

    /// All messages rooted in this subtree.
    var subtreeMessages: [Message] {
        return messages + children.flatMap { $0.subtreeMessages }
    }

    var setsIndentationLevel: Bool {
        return false
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
