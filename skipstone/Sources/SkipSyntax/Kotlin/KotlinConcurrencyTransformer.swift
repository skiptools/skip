/// Update uses of `Task` and `async` calls.
final class KotlinConcurrencyTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        guard translator.codebaseInfo != nil else {
            return
        }
        syntaxTree.root.visit { node in
            if node is KotlinIdentifier {
                // TODO
            } else if let memberAccess = node as? KotlinMemberAccess {
                // Special case for Task.value -> Task.value() in our Kotlin implementation
                if memberAccess.member == "value", case .named("Task", _) = memberAccess.baseType {
                    memberAccess.isKotlinFunctionCall = true
                }
            } else if node is KotlinAwait {
                // TODO
            }
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
