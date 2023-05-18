/// Update uses of `Task` and `async` calls.
final class KotlinConcurrencyTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        syntaxTree.root.visit { node in
            return .recurse(nil)
        }
    }
}

extension KotlinConcurrencyTransformer: KotlinTypeSignatureOutputTransformer {
    static func outputSignature(for signature: TypeSignature) -> TypeSignature {
        if case .named("Task", let generics) = signature, generics.count == 2 {
            return .named("Task", [generics[0]])
        } else {
            return signature
        }
    }
}
