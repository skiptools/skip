/// A plugin used to translate a specific facet of Swift code to Kotlin.
///
/// The transformer lifetime is tied to that of the entire transpilation process. This means that a given transformer instance may be applied to multiple syntax trees.
public protocol KotlinTransformer {
    init()

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

    /// Apply this transformer to the package-level generated source file.
    ///
    /// There is nothing in this tree except code added by the transfomer chain.
    ///
    /// - Returns: Whether any code was added to the tree.
    func apply(toPackage syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> Bool

    /// Apply this transformer to the package-level generated Swift bridge file.
    ///
    /// - Warning: Only `RawStatements` are supported.
    /// - Returns: Whether any code was added to the bridge output.
    func apply(toSwiftBridge syntaxTree: SyntaxTree, imports: inout Set<String>, translator: KotlinTranslator) -> Bool
}

/// The set of builtin transformers in the order in which they should run.
public func builtinKotlinTransformers() -> [KotlinTransformer] {
    return builtinKotlinTransformerTypes.map { $0.init() }
}

public let builtinKotlinTransformerTypes: [KotlinTransformer.Type] = [
    // May change the names of members, so place it before transformers that could use those names in generated code
    KotlinEscapeKeywordsTransformer.self,
    // May add members to implement our internal OptionSet contract, including using self assignment that must be
    // detected and further translated by the KotlinStructTransformer
    KotlinOptionSetTransformer.self,
    // May add members, so place it before transformers that could manipulate those members. May update variable values
    // and move them to constructors, so place before constructor transformer
    KotlinStructTransformer.self,
    // May *remove* information about protocol conformances
    KotlinCommonProtocolsTransformer.self,
    // May add enums and constructors that must be enhanced by subsequent transformers
    KotlinCodableTransformer.self,
    // May add RawRepresentable enum factory function. Requires knowledge of constructors, so place before KotlinEnumTransformer
    KotlinRawRepresentableTransformer.self,
    // May *replace* constructors with factory functions. May add static allCases function. May change optional init call
    // sites to factory calls
    KotlinEnumTransformer.self,
    // May add constructors and modify existing constructors. May suppress property setting side effects in functions.
    // May change optional init call sites
    KotlinConstructorAndSideEffectSupressionTransformer.self,
    // May change superclass initialization. Requires knowledge of all constructors, including added constructors
    KotlinErrorToExceptionTransformer.self,
    // May change the names of stored properties, but adds computed wrapper properties with the previous names. Requires
    // knowledge of all constructors, including added constructors
    KotlinObservationTransformer.self,
    KotlinIfWhenTransformer.self,
    KotlinDeferTransformer.self,
    KotlinDisambiguateFunctionsTransformer.self,
    KotlinTupleLabelTransformer.self,
    // Requires knowledge of enclosing closures added by KotlinIfWhenTransformer
    KotlinConcurrencyTransformer.self,
    // Requires knowledge of enclosing closures added by KotlinIfWhenTransformer
    KotlinSwiftUITransformer.self,
    KotlinImportsTransformer.self,
    KotlinUnitTestTransformer.self,
    KotlinModuleBundleTransformer.self,
    KotlinCompiledBridgeTransformer.self,
    KotlinTranspiledBridgeTransformer.self,
]

/// The builtin transformers can implement this protocol to modify how type signatures are output.
///
/// The returned signature will be written to output instead of the input signature.
///
/// - Note: This is only called for `member`, `module`, and `named` types.
protocol KotlinTypeSignatureOutputTransformer {
    static func outputSignature(for: TypeSignature) -> TypeSignature
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

    func apply(toSwiftBridge syntaxTree: SyntaxTree, imports: inout Set<String>, translator: KotlinTranslator) -> Bool {
        return false
    }
}
