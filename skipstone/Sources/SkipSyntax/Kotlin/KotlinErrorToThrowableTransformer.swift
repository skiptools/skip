/// Update types that conform to the `Error` protocol to extend from `Exception`.
final class KotlinErrorToExceptionTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        guard let codebaseInfo = translator.codebaseInfo else {
            return []
        }
        syntaxTree.root.visit { visit($0, codebaseInfo: codebaseInfo, source: translator.syntaxTree.source) }
        return []
    }

    private func visit(_ node: KotlinSyntaxNode, codebaseInfo: CodebaseInfo.Context, source: Source) -> VisitResult<KotlinSyntaxNode> {
        if let classDeclaration = node as? KotlinClassDeclaration {
            processClassDeclaration(classDeclaration, codebaseInfo: codebaseInfo, source: source)
        }
        return .recurse(nil)
    }

    private func processClassDeclaration(_ classDeclaration: KotlinClassDeclaration, codebaseInfo: CodebaseInfo.Context, source: Source) {
        let inherits = classDeclaration.inherits
        guard !inherits.isEmpty else {
            return
        }
        let isSubclass = classDeclaration.declarationType == .classDeclaration && codebaseInfo.declarationType(forNamed: inherits[0])?.type == .classDeclaration
        let protocols = isSubclass ? Array(inherits.suffix(from: 1)) : inherits
        guard protocols.contains(where: { codebaseInfo.conformsToError(type: $0) }) else {
            return
        }
        guard !isSubclass else {
            if !codebaseInfo.conformsToError(type: inherits[0]) {
                classDeclaration.messages.append(.kotlinErrorCannotExtendClass(classDeclaration, source: source))
            }
            return
        }

        var hasConstructors = false
        for member in classDeclaration.members {
            if member.type == .constructorDeclaration, let constructorDeclaration = member as? KotlinFunctionDeclaration {
                hasConstructors = true
                if constructorDeclaration.delegatingConstructorCall == nil {
                    constructorDeclaration.delegatingConstructorCall = KotlinRawExpression(sourceCode: "super()")
                }
            } else if member.type == .variableDeclaration, let variableDeclaration = member as? KotlinVariableDeclaration {
                if variableDeclaration.propertyName == "message" {
                    variableDeclaration.modifiers.isOverride = true
                    variableDeclaration.modifiers.visibility = .public
                }
            }
        }

        var exceptionInheritsIndex = 0
        if classDeclaration.declarationType == .enumDeclaration {
            // Leave the enum raw type extension first
            exceptionInheritsIndex = classDeclaration.enumInheritedRawValueType != .none ? 1 : 0
        }
        classDeclaration.inherits.insert(.named("Exception", []), at: exceptionInheritsIndex)
        if !hasConstructors {
            classDeclaration.superclassCall = "Exception()"
        }
    }
}
