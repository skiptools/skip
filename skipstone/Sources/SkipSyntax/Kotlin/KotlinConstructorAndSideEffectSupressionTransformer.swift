/// Migrate Swift constructors to Kotlin constructors, include suppressing property side effects.
final class KotlinConstructorAndSideEffectSupressionTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        syntaxTree.root.visit { visit($0, translator: translator) }
    }

    private func visit(_ node: KotlinSyntaxNode, translator: KotlinTranslator) -> VisitResult<KotlinSyntaxNode> {
        if let classDeclaration = node as? KotlinClassDeclaration {
            let hasNonEmptyConstructors = fixupConstructors(for: classDeclaration, translator: translator)
            if hasNonEmptyConstructors || classDeclaration.members.contains(where: { ($0 as? KotlinFunctionDeclaration)?.suppressSideEffects == true }) {
                addSuppressSideEffectsProperty(to: classDeclaration)
            }
        } else if let functionCall = node as? KotlinFunctionCall, functionCall.isOptionalInit {
            // Rather than catching the NullReturnException from our Kotlin optional init function and then force unwrapping,
            // just let the exception propagate
            if let postfixOperator = functionCall.parent as? KotlinPostfixOperator, postfixOperator.operatorSymbol == "!" {
                functionCall.isOptionalInit = false
                postfixOperator.operatorSymbol = ""
            }
        }
        return .recurse(nil)
    }

    private func fixupConstructors(for classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) -> Bool {
        let constructors = classDeclaration.members.compactMap { (member: KotlinStatement) -> KotlinFunctionDeclaration? in
            guard member.type == .constructorDeclaration else {
                return nil
            }
            return member as? KotlinFunctionDeclaration
        }

        let superclass = superclass(of: classDeclaration, translator: translator)
        var hasNonEmptyConstructor = false
        if constructors.isEmpty {
            if classDeclaration.declarationType != .structDeclaration, let superclass, !addInheritedConstructors(to: classDeclaration, translator: translator) {
                classDeclaration.superclassCall = "\(superclass.kotlin)()"
            }
        } else {
            for constructor in constructors {
                fixupClassConstructor(constructor, for: classDeclaration, isSubclass: superclass != nil, translator: translator)
                if constructor.body?.statements.isEmpty == false {
                    hasNonEmptyConstructor = true
                }
            }
        }
        return hasNonEmptyConstructor
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
            return Parameter(externalLabel: label, declaredType: parameter.declaredType, isInOut: parameter.isInOut, isVariadic: parameter.isVariadic, attributes: parameter.attributes, defaultValue: kdefaultValue)
        }
        superCall += ")"
        constructor.delegatingConstructorCall = KotlinRawExpression(sourceCode: superCall)

        constructor.body = KotlinCodeBlock(statements: [])
        constructor.parent = classDeclaration
        constructor.assignParentReferences()
        classDeclaration.members.append(constructor)
    }

    private func fixupClassConstructor(_ constructor: KotlinFunctionDeclaration, for classDeclaration: KotlinClassDeclaration, isSubclass: Bool, translator: KotlinTranslator) {
        guard let body = constructor.body else {
            return
        }
        if constructor.isOptionalInit {
            constructor.body?.updateWithExpectedReturn(.throwIfNull)
        }
        guard constructor.delegatingConstructorCall == nil else {
            return
        }

        // Find any call to self or super init and move it to the Kotlin delegating constructor call
        var assignConstructionValues = true
        for (index, statement) in body.statements.enumerated() {
            guard let (delegatingCall, isSuper) = delegatingConstructorCall(for: statement) else {
                continue
            }
            body.statements.remove(at: index)
            fixupDelegatingConstructorCall(delegatingCall, in: constructor, translator: translator)
            constructor.delegatingConstructorCall = delegatingCall
            assignConstructionValues = isSuper
            break
        }
        // Validate that there aren't additional or conditional delegating calls
        body.visit { syntaxNode in
            if let statement = syntaxNode as? KotlinStatement, delegatingConstructorCall(for: statement) != nil {
                statement.messages.append(.kotlinConstructorSingleDelegatingStatement(statement, source: translator.syntaxTree.source))
            }
            return .recurse(nil)
        }
        // Add super call if needed
        if isSubclass && constructor.delegatingConstructorCall == nil {
            constructor.delegatingConstructorCall = KotlinRawExpression(sourceCode: "super()")
        }
        if assignConstructionValues && !constructor.isMutableStructCopyConstructor {
            self.assignConstructionValues(in: body, for: classDeclaration)
        }
    }

    private func assignConstructionValues(in body: KotlinCodeBlock, for classDeclaration: KotlinClassDeclaration) {
        let statements = classDeclaration.members.compactMap { (member: KotlinStatement) -> KotlinStatement? in
            guard let variableDeclaration = member as? KotlinVariableDeclaration, variableDeclaration.isLet, let constructionValue = variableDeclaration.constructionValue else {
                return nil
            }
            let access = KotlinMemberAccess(base: KotlinIdentifier(name: "self"), member: variableDeclaration.propertyName)
            let assignment = KotlinBinaryOperator(op: .with(symbol: "="), lhs: access, rhs: constructionValue)
            return KotlinExpressionStatement(expression: assignment)
        }
        if !statements.isEmpty {
            body.insert(statements: statements, after: nil)
        }
    }

    private func delegatingConstructorCall(for statement: KotlinStatement) -> (KotlinFunctionCall, isSuper: Bool)? {
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
        return memberAccess.isBaseSelfOrSuper ? (functionCall, (memberAccess.base as? KotlinIdentifier)?.name == "super") : nil
    }

    private func fixupDelegatingConstructorCall(_ functionCall: KotlinFunctionCall, in constructor: KotlinFunctionDeclaration, translator: KotlinTranslator) {
        // Make sure that the delegating call doesn't use locals that won't be available when it is moved (e.g. any local other
        // than the constructor parameters). This includes mapping internal parameter names to external ones
        for argument in functionCall.arguments {
            argument.value.visit { node in
                // Closures might introduce their own identifiers, which should be fine
                guard !(node is KotlinClosure) else {
                    return .skip
                }
                if let identifier = node as? KotlinIdentifier, identifier.isLocalOrSelfIdentifier && identifier.name != "self" {
                    if let parameter = constructor.parameters.first(where: { $0.internalLabel == identifier.name }) {
                        if let externalLabel = parameter.externalLabel {
                            identifier.name = externalLabel
                        }
                    } else {
                        identifier.messages.append(.kotlinConstructorDelegatingStatementArguments(identifier, source: translator.syntaxTree.source))
                    }
                }
                return .recurse(nil)
            }
        }
        // The delegating call should not be treated as an optional init call
        functionCall.isOptionalInit = false
        // Cannot use trailing closures in delegating calls
        functionCall.hasTrailingClosures = false
    }

    private func superclass(of classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) -> TypeSignature? {
        guard let inherits = classDeclaration.inherits.first, translator.codebaseInfo?.declarationType(forNamed: inherits)?.type == .classDeclaration else {
            return nil
        }
        return inherits
    }

    private func addSuppressSideEffectsProperty(to classDeclaration: KotlinClassDeclaration) {
        for member in classDeclaration.members {
            guard let variableDeclaration = member as? KotlinVariableDeclaration else {
                continue
            }
            // We only need to add the check if there are any member vars with willSet, didSet
            if !variableDeclaration.modifiers.isStatic, variableDeclaration.willSet != nil || variableDeclaration.didSet != nil {
                classDeclaration.suppressSideEffectsPropertyName = "suppresssideeffects"
                variableDeclaration.suppressSideEffectsPropertyName = "suppresssideeffects"
            }
        }
    }
}
