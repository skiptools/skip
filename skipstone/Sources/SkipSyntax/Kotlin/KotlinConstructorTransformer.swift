/// Migrate Swift constructors to Kotlin constructors.
class KotlinConstructorTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        syntaxTree.root.visit { visit($0, translator: translator) }
    }

    private func visit(_ node: KotlinSyntaxNode, translator: KotlinTranslator) -> VisitResult<KotlinSyntaxNode> {
        guard let classDeclaration = node as? KotlinClassDeclaration else {
            // Recurse to find nested declarations
            return .recurse(nil)
        }
        // Enums are handled in the EnumTransformer
        if classDeclaration.declarationType != .enumDeclaration {
            fixupConstructors(for: classDeclaration, translator: translator)
        }
        return .recurse(nil)
    }

    private func fixupConstructors(for classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) {
        let constructors = classDeclaration.members.compactMap { (member: KotlinStatement) -> KotlinFunctionDeclaration? in
            guard member.type == .constructorDeclaration else {
                return nil
            }
            return member as? KotlinFunctionDeclaration
        }
        let superclass = superclass(of: classDeclaration, translator: translator)
        if constructors.isEmpty {
            if classDeclaration.declarationType != .structDeclaration, let superclass, !addInheritedConstructors(to: classDeclaration, translator: translator) {
                classDeclaration.superclassCall = "\(superclass.kotlin)()"
            }
        } else {
            var hasNonEmptyConstructor = false
            for constructor in constructors {
                fixupClassConstructor(constructor, isSubclass: superclass != nil, translator: translator)
                if constructor.body?.statements.isEmpty == false {
                    hasNonEmptyConstructor = true
                }
            }
            if hasNonEmptyConstructor {
                addIsConstructingProperty(to: classDeclaration)
            }
        }
    }

    private func addInheritedConstructors(to classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) -> Bool {
        let inheritedConstructorParameters = translator.codebaseInfo?.constructorParameters(of: classDeclaration.signature) ?? []
        guard !inheritedConstructorParameters.isEmpty else {
            return false
        }
        for constructorParameters in inheritedConstructorParameters {
            addInheritedConstructor(parameters: constructorParameters, to: classDeclaration, translator: translator)
        }
        return true
    }

    private func addInheritedConstructor(parameters: [Parameter<Expression>], to classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) {
        let constructor = KotlinFunctionDeclaration(name: "constructor")
        constructor.modifiers = classDeclaration.modifiers
        constructor.extras = .singleNewline
        constructor.isGenerated = true
        constructor.returnType = classDeclaration.signature

        var superCall = "super("
        constructor.parameters = parameters.enumerated().map { (index, parameter) in
            let label = parameter.externalLabel ?? "p_\(index)"
            if index > 0 {
                superCall += ", "
            }
            superCall += label

            var kdefaultValue: KotlinExpression? = nil
            if let defaultValue = parameter.defaultValue {
                kdefaultValue = translator.translateExpression(defaultValue)
            }
            return Parameter(externalLabel: label, declaredType: parameter.declaredType, isInOut: parameter.isInOut, isVariadic: parameter.isVariadic, defaultValue: kdefaultValue)
        }
        superCall += ")"
        constructor.delegatingConstructorCall = KotlinRawExpression(sourceCode: superCall)

        constructor.body = KotlinCodeBlock(statements: [])
        constructor.parent = classDeclaration
        constructor.assignParentReferences()
        classDeclaration.members.append(constructor)
    }

    private func fixupClassConstructor(_ constructor: KotlinFunctionDeclaration, isSubclass: Bool, translator: KotlinTranslator) {
        if constructor.isOptionalInit {
            constructor.messages.append(.kotlinConstructorNullReturn(constructor, source: translator.syntaxTree.source))
        }
        guard constructor.delegatingConstructorCall == nil, let body = constructor.body else {
            return
        }

        // Find any call to self or super init and move it to the Kotlin delegating constructor call
        for (index, statement) in body.statements.enumerated() {
            guard let delegatingCall = delegatingConstructorCall(for: statement) else {
                continue
            }
            if constructor.delegatingConstructorCall != nil {
                statement.messages.append(.kotlinConstructorSingleDelegatingStatement(statement, source: translator.syntaxTree.source))
                break
            }
            body.statements.remove(at: index)
            constructor.delegatingConstructorCall = delegatingCall
        }
        if isSubclass && constructor.delegatingConstructorCall == nil {
            constructor.delegatingConstructorCall = KotlinRawExpression(sourceCode: "super()")
        }
    }

    private func delegatingConstructorCall(for statement: KotlinStatement) -> KotlinExpression? {
        guard statement.type == .expression, let expressionStatement = statement as? KotlinExpressionStatement else {
            return nil
        }
        guard expressionStatement.expression?.type == .functionCall, let functionCall = expressionStatement.expression as? KotlinFunctionCall else {
            return nil
        }
        guard functionCall.function.type == .memberAccess, let memberAccess = functionCall.function as? KotlinMemberAccess else {
            return nil
        }
        guard memberAccess.member == "init" else {
            return nil
        }
        switch memberAccess.baseKind {
        case .this:
            return functionCall
        case .super:
            return functionCall
        default:
            return nil
        }
    }

    private func superclass(of classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) -> TypeSignature? {
        guard let inherits = classDeclaration.inherits.first, translator.codebaseInfo?.declarationType(forNamed: inherits) == .classDeclaration else {
            return nil
        }
        return inherits
    }

    private func addIsConstructingProperty(to classDeclaration: KotlinClassDeclaration) {
        for member in classDeclaration.members {
            guard let variableDeclaration = member as? KotlinVariableDeclaration else {
                continue
            }
            // We only need to add the check if there are any member vars with willSet, didSet
            if !variableDeclaration.modifiers.isStatic, variableDeclaration.willSet != nil || variableDeclaration.didSet != nil {
                classDeclaration.isConstructingPropertyName = "isconstructing"
                variableDeclaration.isConstructingPropertyName = "isconstructing"
            }
        }
    }
}
