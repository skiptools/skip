/// Update uses of `Task` and `async` calls.
final class KotlinConcurrencyTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        guard translator.codebaseInfo != nil else {
            return
        }
        syntaxTree.root.visit { node in
            if let identifier = node as? KotlinIdentifier {
                if identifier.name == "Task", let functionCall = identifier.parent as? KotlinFunctionCall, identifier === functionCall.function {
                    updateTaskConstructor(functionCall)
                }
            } else if let memberAccess = node as? KotlinMemberAccess {
                if memberAccess.member == "value", case .named("Task", _) = memberAccess.baseType {
                    // Special case for Task.value -> Task.value() in our Kotlin implementation
                    memberAccess.member = "value()"
                } else if memberAccess.member == "Task", case .module("Swift", _) = memberAccess.baseType, let functionCall = memberAccess.parent as? KotlinFunctionCall, memberAccess === functionCall.function {
                    updateTaskConstructor(functionCall)
                }
            } else if let awaitExpression = node as? KotlinAwait {
                processAwaitExpression(awaitExpression)
            }
            return .recurse(nil)
        }
    }

    private func updateTaskConstructor(_ functionCall: KotlinFunctionCall) {
        //~~~
    }

    private func processAwaitExpression(_ expression: KotlinAwait) {
        //~~~
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
