/// A plugin used to translate a specific facet of Swift code to Kotlin.
///
/// The transformer lifetime is tied to that of the entire transpilation process. This means that a given transformer instance may be applied to multiple syntax trees.
public protocol KotlinTransformer {
    /// Gather any needed info from the given Swift syntax tree.
    ///
    /// - Note: This phase is run during pre-flight and can also be used to add messages to the syntax trees.
    func gather(from syntaxTree: SyntaxTree)

    /// Called when gathering from all syntax trees is complete.
    func prepareForUse(codebaseInfo: CodebaseInfo?)

    /// Any issues encountered during information gathering.
    func messages(for sourceFile: Source.FilePath) -> [Message]

    /// Apply this transformer to the given Kotlin syntax tree.
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator)

    /// Apply this transformer to the package-level generated source file. There is nothing in this tree except code added by the transfomer chain.
    ///
    /// - Returns: Whether any code was added to the tree.
    func apply(toPackage syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> Bool
}

/// The set of builtin transformers in the order in which they should run.
public func builtinKotlinTransformers() -> [KotlinTransformer] {
    return [
        // May change the names of members, so place it before transformers that could use those names in generated code
        KotlinEscapeKeywordsTransformer(),
        // May add members, so place it before transformers that could manipulate those members
        KotlinStructTransformer(),
        // May alter superclasses and change enums to use sealed classes
        KotlinErrorToThrowableTransformer(),
        // May *remove* information about protocol conformances. May change enums to use sealed classes. Requires knowledge of
        // sealed vs. unsealed enums. Take care with placement in transformers list
        KotlinEquatableHashableComparableTransformer(),
        // May add constructors
        KotlinConstructorTransformer(),
        // May add static allCases function
        KotlinCaseIterableTransformer(),
        KotlinIfWhenTransformer(),
        KotlinDeferTransformer(),
        KotlinDisambiguateFunctionsTransformer(),
        KotlinTupleLabelTransformer(),
        KotlinSwiftUITransformer(),
        KotlinImportMapTransformer(),
        KotlinTestAnnotationTransformer(),
    ]
}

extension KotlinTransformer {
    func gather(from syntaxTree: SyntaxTree) {
    }

    func prepareForUse(codebaseInfo: CodebaseInfo?) {
    }

    func messages(for sourceFile: Source.FilePath) -> [Message] {
        return []
    }

    func apply(toPackage syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> Bool {
        return false
    }
}
