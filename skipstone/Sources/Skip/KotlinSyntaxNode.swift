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

    var derivationMessages: [Message] = []

    /// All messages rooted in this subtree.
    var messages: [Message] {
        return derivationMessages + children.flatMap { $0.messages }
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
