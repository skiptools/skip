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
            } else if let mainActorTargeting = node as? (KotlinSyntaxNode & KotlinMainActorTargeting) {
                if mainActorTargeting.isInAwait && mainActorTargeting.needsMainActorIsolation
            }
            return .recurse(nil)
        }
    }

    private func updateTaskConstructor(_ functionCall: KotlinFunctionCall) {
        //~~~
    }

    private func processAwaitExpression(_ expression: KotlinAwait) {
        var isInMainActorContext: Bool? = nil
        expression.visit { node in

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

fileprivate extension CodebaseInfo.Context {
    func isMainActor(declaration: KotlinFunctionDeclaration) -> Bool {
        if declaration.attributes.contains(.mainActor) {
            return true
        }
        let arguments = declaration.parameters.map { LabeledValue(label: $0.externalLabel, value: $0.declaredType) }
        let matches: [APIMatch]
        if let owningType = owningType(of: declaration) {
            matches = matchFunction(name: declaration.name, inConstrained: owningType, arguments: arguments)
        } else {
            matches = matchFunction(name: declaration.name, arguments: arguments)
        }
        return matches.first?.apiFlags.contains(.mainActor) == true
    }

    func isMainActor(declaration: KotlinVariableDeclaration) -> Bool {
        if declaration.attributes.contains(.mainActor) {
            return true
        }
        let match: APIMatch?
        if declaration.isProperty, let owningType = owningType(of: declaration) {
            match = matchIdentifier(name: declaration.propertyName, inConstrained: owningType)
        } else if declaration.isGlobal {
            match = matchIdentifier(name: declaration.propertyName)
        } else {
            match = nil
        }
        return match?.apiFlags.contains(.mainActor) == true
    }

    private func owningType(of declaration: KotlinStatement) -> TypeSignature? {
        if let classDeclaration = declaration.parent as? KotlinClassDeclaration {
            return primaryTypeInfo(forNamed: classDeclaration.signature)?.signature
        } else if let interfaceDeclaration = declaration.parent as? KotlinInterfaceDeclaration {
            return primaryTypeInfo(forNamed: interfaceDeclaration.signature)?.signature
        } else if let memberDeclaration = declaration as? KotlinMemberDeclaration {
            return memberDeclaration.extends?.0
        } else {
            return nil
        }
    }
}
