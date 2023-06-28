/// Update types that conform to the `Error` protocol to extend from `Exception`.
final class KotlinErrorToExceptionTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        guard let codebaseInfo = translator.codebaseInfo else {
            return
        }
        syntaxTree.root.visit { visit($0, codebaseInfo: codebaseInfo, source: translator.syntaxTree.source) }
    }

    private func visit(_ node: KotlinSyntaxNode, codebaseInfo: CodebaseInfo.Context, source: Source) -> VisitResult<KotlinSyntaxNode> {
        if let classDeclaration = node as? KotlinClassDeclaration {
            processClassDeclaration(classDeclaration, codebaseInfo: codebaseInfo, source: source)
        }
        return .recurse(nil)
    }

    private func processClassDeclaration(_ classDeclaration: KotlinClassDeclaration, codebaseInfo: CodebaseInfo.Context, source: Source) {
        guard codebaseInfo.conformsToError(type: classDeclaration.signature) else {
            return
        }
        if let firstInherits = classDeclaration.inherits.first, codebaseInfo.declarationType(forNamed: firstInherits) == .classDeclaration {
            classDeclaration.messages.append(.kotlinErrorCannotExtendClass(classDeclaration, source: source))
            return
        }

        var hasConstructors = false
        for member in classDeclaration.members {
            if member.type == .constructorDeclaration, let constructorDeclaration = member as? KotlinFunctionDeclaration {
                hasConstructors = true
                constructorDeclaration.delegatingConstructorCall = KotlinRawExpression(sourceCode: "super()")
            }
            guard let variableDeclaration = member as? KotlinVariableDeclaration else {
                continue
            }
            if variableDeclaration.propertyName == "message" {
                variableDeclaration.modifiers.isOverride = true
                variableDeclaration.modifiers.visibility = .public
                break
            }
        }

        var exceptionInheritsIndex = 0
        if classDeclaration.declarationType == .enumDeclaration {
            // To extend Exception, an enum must be modeled as a sealed class, and we cannot create singleton case instances
            classDeclaration.isSealedClassesEnum = true
            classDeclaration.alwaysCreateNewSealedClassInstances = true
            // Leave the enum raw type extension first
            exceptionInheritsIndex = classDeclaration.enumInheritedRawValueType != .none ? 1 : 0
        }
        classDeclaration.inherits.insert(.named("Exception", []), at: exceptionInheritsIndex)
        if !hasConstructors {
            classDeclaration.superclassCall = "Exception()"
        }
    }
}
