/// Generate compiled Swift <-> Kotlin bridging code.
final class KotlinBridgeTransformer: KotlinTransformer {
    // TODO: Implement
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
    }

    func append(toSwiftBridge output: OutputGenerator, imports: Set<String>, translator: KotlinTranslator) -> Bool {
        return false
    }
}

