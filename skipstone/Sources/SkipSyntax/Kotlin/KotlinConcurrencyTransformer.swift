/// Update uses of `Task` and main actor information used in `async` calls.
final class KotlinConcurrencyTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        guard let codebaseInfo = translator.codebaseInfo else {
            return
        }
        syntaxTree.root.visit { node in
            if let functionDeclaration = node as? KotlinFunctionDeclaration {
                // Async implementations change for main actor
                if functionDeclaration.asyncOptions.contains(.async) && codebaseInfo.isMainActor(declaration: functionDeclaration) {
                    functionDeclaration.asyncOptions.insert(.mainActor)
                }
            } else if let variableDeclaration = node as? KotlinVariableDeclaration {
                // Async implementations change for main actor
                if variableDeclaration.asyncOptions.contains(.async) && codebaseInfo.isMainActor(declaration: variableDeclaration) {
                    variableDeclaration.asyncOptions.insert(.mainActor)
                }
            } else if let identifier = node as? KotlinIdentifier {
                if identifier.name == "Task", let functionCall = identifier.parent as? KotlinFunctionCall, identifier === functionCall.function {
                    updateTaskConstructor(functionCall, codebaseInfo: codebaseInfo)
                }
            } else if let memberAccess = node as? KotlinMemberAccess {
                if memberAccess.member == "value" && memberAccess.baseType.isNamed("Task", moduleName: "Swift") {
                    // Special case for Task.value -> Task.value() in our Kotlin implementation
                    memberAccess.member = "value()"
                } else if memberAccess.member == "Task", case .module("Swift", _) = memberAccess.baseType, let functionCall = memberAccess.parent as? KotlinFunctionCall, memberAccess === functionCall.function {
                    updateTaskConstructor(functionCall, codebaseInfo: codebaseInfo)
                } else if memberAccess.member == "detached" && memberAccess.baseType.isNamed("Task", moduleName: "Swift"), let functionCall = memberAccess.parent as? KotlinFunctionCall, memberAccess === functionCall.function {
                    updateTaskConstructor(functionCall, isDetached: true, codebaseInfo: codebaseInfo)
                }
            } else if let mainActorTargeting = node as? (KotlinSyntaxNode & KotlinMainActorTargeting) {
                // Update any main actor await call to see if it's in a main actor context
                if mainActorTargeting.isInAwait && mainActorTargeting.needsMainActorIsolation == true {
                    updateMainActorTargeting(mainActorTargeting, codebaseInfo: codebaseInfo)
                }
            }
            return .recurse(nil)
        }
    }

    private func updateTaskConstructor(_ functionCall: KotlinFunctionCall, isDetached: Bool = false, codebaseInfo: CodebaseInfo.Context) {
        //~~~ add an argument if task is main actor-bound
    }

    private func updateMainActorTargeting(_ mainActorTargeting: KotlinSyntaxNode & KotlinMainActorTargeting, codebaseInfo: CodebaseInfo.Context) {
        //~~~ set whether in main actor context
    }
}

extension KotlinConcurrencyTransformer: KotlinTypeSignatureOutputTransformer {
    static func outputSignature(for signature: TypeSignature) -> TypeSignature {
        if signature.isNamed("Task", moduleName: "Swift") && signature.generics.count == 2 {
            return signature.withGenerics([signature.generics[0]])
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
        if declaration.role.isProperty, let owningType = owningType(of: declaration) {
            match = matchIdentifier(name: declaration.propertyName, inConstrained: owningType)
        } else if declaration.role == .global {
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
