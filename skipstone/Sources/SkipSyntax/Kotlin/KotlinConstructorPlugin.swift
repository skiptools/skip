/// Migrate Swift constructors to Kotlin constructors.
class KotlinConstructorPlugin: KotlinPlugin {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        syntaxTree.root.visit { visit($0, translator: translator) }
    }

    private func visit(_ node: KotlinSyntaxNode, translator: KotlinTranslator) -> VisitResult<KotlinSyntaxNode> {
        guard let statement = node as? KotlinStatement else {
            return .skip
        }
        switch statement.type {
        case .classDeclaration:
            let classDeclaration = statement as! KotlinClassDeclaration
            let constructors = classDeclaration.members.filter { $0.type == .constructorDeclaration }
            var mayNeedSuperclassCall = false
            if constructors.isEmpty {
                if classDeclaration.declarationType == .structDeclaration {
                    addMemberwiseConstructor(to: classDeclaration)
                } else {
                    mayNeedSuperclassCall = !addInheritedConstructors(to: classDeclaration, translator: translator)
                }
            } else {
                for constructor in constructors {
                    if !fixupConstructor(constructor as! KotlinFunctionDeclaration) {
                        mayNeedSuperclassCall = true
                    }
                }
            }
            if mayNeedSuperclassCall {
                addSuperclassCall(to: classDeclaration, translator: translator)
            }
        case .constructorDeclaration:
            return .skip
        case .variableDeclaration:
            return .skip
        case .functionDeclaration:
            return .skip
        default:
            break
        }
        return .recurse(nil)
    }

    private func addMemberwiseConstructor(to classDeclaration: KotlinClassDeclaration) {
        var minimumVisibility = classDeclaration.modifiers.visibility
        let variableDeclarations = classDeclaration.members.compactMap { (member: KotlinStatement) -> KotlinVariableDeclaration? in
            guard let variableDeclaration = member as? KotlinVariableDeclaration, !variableDeclaration.isLet, variableDeclaration.getter == nil else {
                return nil
            }
            if variableDeclaration.modifiers.visibility < minimumVisibility {
                minimumVisibility = variableDeclaration.modifiers.visibility
            }
            return variableDeclaration
        }
        guard !variableDeclarations.isEmpty else {
            return
        }

        let constructor = KotlinFunctionDeclaration(name: "constructor")
        constructor.parameters = variableDeclarations.map { variableDeclaration in
            let label = variableDeclaration.names[0]
            let type = variableDeclaration.variableTypes[0]
            return Parameter(externalLabel: label, declaredType: type, isVariadic: false, defaultValue: variableDeclaration.value)
        }
        constructor.modifiers = classDeclaration.modifiers
        // Swift generated constructors take on the minimimum visibility of the members being initialized
        constructor.modifiers.visibility = minimumVisibility
        constructor.extras = .singleNewline

        let bodyStatements = variableDeclarations.map { variableDeclaration in
            let selfIdentifier = KotlinIdentifier(name: "self")
            let memberAccess = KotlinMemberAccess(base: selfIdentifier, member: variableDeclaration.names[0])
            let paramIdentifier = KotlinIdentifier(name: variableDeclaration.names[0])
            let assignmentOperator = KotlinBinaryOperator(op: .with(symbol: "="), lhs: memberAccess, rhs: paramIdentifier)
            let statement = KotlinExpressionStatement(type: .expression)
            statement.expression = assignmentOperator
            return statement
        }
        constructor.body = KotlinCodeBlock(statements: bodyStatements)

        classDeclaration.members.append(constructor)
        constructor.parent = classDeclaration
        // We're intentionally not calling assignParentReferences on the constructor itself, because we may
        // be sharing parameter default value expressions with variable value expressions. Call on our body directly
        constructor.body?.parent = constructor
        constructor.body?.assignParentReferences()
    }

    private func addInheritedConstructors(to classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) -> Bool {
        let inheritedConstructorParameters = translator.codebaseInfo?.constructorParameters(of: classDeclaration.qualifiedName) ?? []
        guard !inheritedConstructorParameters.isEmpty else {
            return false
        }
        for constructorParameters in inheritedConstructorParameters {
            addInheritedConstructor(parameters: constructorParameters, to: classDeclaration, translator: translator)
        }
        return true
    }

    private func addInheritedConstructor(parameters: [KotlinCodebaseInfo.ConstructorParameter], to classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) {
        let constructor = KotlinFunctionDeclaration(name: "constructor")
        var superCall = "super("
        constructor.parameters = parameters.enumerated().map { (index, parameter) in
            let label = parameter.label ?? "p_\(index)"
            if index > 0 {
                superCall += ", "
            }
            superCall += label

            var kdefaultValue: KotlinExpression? = nil
            if let defaultValue = parameter.defaultValue {
                kdefaultValue = translator.translateExpression(defaultValue)
            }
            return Parameter(externalLabel: label, declaredType: parameter.type, isVariadic: parameter.isVariadic, defaultValue: kdefaultValue)
        }
        superCall += ")"
        constructor.delegatingConstructorCall = KotlinRawExpression(sourceCode: superCall)

        constructor.modifiers = classDeclaration.modifiers
        constructor.extras = .singleNewline
        constructor.body = KotlinCodeBlock(statements: [])

        classDeclaration.members.append(constructor)
        constructor.parent = classDeclaration
        constructor.assignParentReferences()
    }

    private func fixupConstructor(_ constructor: KotlinFunctionDeclaration) -> Bool {
        guard constructor.delegatingConstructorCall == nil else {
            return true
        }
        guard let body = constructor.body else {
            return false
        }

        // Find any call to self or super init and move it to the Kotlin delegating constructor call
        for (index, statement) in body.statements.enumerated() {
            guard let delegatingCall = delegatingConstructorCall(for: statement) else {
                continue
            }
            if constructor.delegatingConstructorCall != nil {
                statement.messages.append(.kotlinConstructorSingleDelegatingStatement(statement))
                break
            }
            body.statements.remove(at: index)
            constructor.delegatingConstructorCall = delegatingCall
        }
        return constructor.delegatingConstructorCall != nil
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

    private func addSuperclassCall(to classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) {
        // If we have a superclass, we must instantiate it
        if let inherits = classDeclaration.inherits.first, translator.codebaseInfo?.declarationType(of: inherits.description, mustBeInModule: false) == .classDeclaration {
            classDeclaration.superclassCall = "\(inherits.description)()"
        }
    }
}
