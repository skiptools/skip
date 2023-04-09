/// A plugin used to translate a specific facet of Swift code to Kotlin.
///
/// The transformer lifetime is tied to that of the `KotlinCodebaseInfo`. This means that a given transformer instance may be applied to multiple syntax trees.
public protocol KotlinTransformer {
    /// Gather any needed info from the given Swift syntax tree.
    func gather(from syntaxTree: SyntaxTree)

    /// Called when gathering from all syntax trees is complete.
    func prepareForUse(codebaseInfo: CodebaseInfo)

    /// Any issues encountered during information gathering.
    func messages(for sourceFile: Source.FilePath) -> [Message]

    /// Apply this transformer to the given Kotlin syntax tree.
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator)
}

extension KotlinTransformer {
    func gather(from syntaxTree: SyntaxTree) {
    }

    func prepareForUse(codebaseInfo: CodebaseInfo) {
    }

    func messages(for sourceFile: Source.FilePath) -> [Message] {
        return []
    }
}
