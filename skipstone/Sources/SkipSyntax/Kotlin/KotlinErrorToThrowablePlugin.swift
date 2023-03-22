/// Update types that conform to the `Error` protocol to extend from `Throwable`.
class KotlinErrorToThrowablePlugin: KotlinPlugin {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        guard let codebaseInfo = translator.codebaseInfo else {
            return
        }
        syntaxTree.root.visit { visit($0, codebaseInfo: codebaseInfo) }
    }

    private func visit(_ node: KotlinSyntaxNode, codebaseInfo: KotlinCodebaseInfo.Context) -> VisitResult<KotlinSyntaxNode> {
        if let classDeclaration = node as? KotlinClassDeclaration {
            processClassDeclaration(classDeclaration, codebaseInfo: codebaseInfo)
        }
        return .recurse(nil)
    }

    private func processClassDeclaration(_ classDeclaration: KotlinClassDeclaration, codebaseInfo: KotlinCodebaseInfo.Context) {
        guard codebaseInfo.conformsToError(type: classDeclaration.signature) else {
            return
        }
        if let firstInherits = classDeclaration.inherits.first, codebaseInfo.declarationType(of: firstInherits, mustBeInModule: false) == .classDeclaration {
            classDeclaration.messages.append(.kotlinErrorCannotExtendClass(classDeclaration))
            return
        }

        for member in classDeclaration.members {
            guard let variableDeclaration = member as? KotlinVariableDeclaration else {
                continue
            }
            if variableDeclaration.names.first == "message" {
                variableDeclaration.modifiers.isOverride = true
                variableDeclaration.modifiers.visibility = .public
                break
            }
        }

        var throwableInheritsIndex = 0
        if classDeclaration.declarationType == .enumDeclaration {
            // To extend throwable, an enum must be modeled as a sealed class
            classDeclaration.isSealedClassesEnum = true
            // Leave the enum raw type extension first
            throwableInheritsIndex = classDeclaration.enumInheritedRawValueType != nil ? 1 : 0
        }
        classDeclaration.inherits.insert(.named("Throwable", []), at: throwableInheritsIndex)
        classDeclaration.superclassCall = "Throwable()"
    }
}
