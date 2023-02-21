/// Migrate SwiftUI constructors to Kotlin constructors.
class KotlinConstructorPlugin: KotlinTranslatorPlugin {
    private let codebaseInfo: KotlinCodebaseInfo.Context

    init(codebaseInfo: KotlinCodebaseInfo.Context) {
        self.codebaseInfo = codebaseInfo
    }

    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> KotlinSyntaxTree {
        syntaxTree.statements.forEach { $0.visitStatements(perform: { visit($0, translator: translator) }) }
        return syntaxTree
    }

    private func visit(_ statement: KotlinStatement, translator: KotlinTranslator) -> KotlinVisitResult {
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
                addSuperclassCall(to: classDeclaration)
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
            let label = variableDeclaration.name
            let type = variableDeclaration.declaredType.or(variableDeclaration.valueType)
            return Parameter(externalLabel: label, declaredType: type, isVariadic: false, defaultValue: variableDeclaration.value)
        }
        constructor.modifiers = classDeclaration.modifiers
        // Swift generated constructors take on the minimimum visibility of the members being initialized
        constructor.modifiers.visibility = minimumVisibility
        constructor.extras = .singleNewline

        let bodyStatements = variableDeclarations.map { variableDeclaration in
            let selfIdentifier = KotlinIdentifier(name: "self")
            let memberAccess = KotlinMemberAccess(base: selfIdentifier, member: variableDeclaration.name)
            let paramIdentifier = KotlinIdentifier(name: variableDeclaration.name)
            let assignmentOperator = KotlinBinaryOperator(op: Operator(symbol: "=", associativity: .right, precedence: .assignment), lhs: memberAccess, rhs: paramIdentifier)
            let statement = KotlinExpressionStatement(type: .expression)
            statement.expression = assignmentOperator
            return statement
        }
        constructor.body = CodeBlock<KotlinStatement>(statements: bodyStatements)

        classDeclaration.members.append(constructor)
        constructor.parent = classDeclaration
        // We're intentionally not calling assignParentReferences on the constructor itself, because we may
        // be sharing parameter default value expressions with variable value expressions. Call on our statements directly
        for bodyStatement in bodyStatements {
            bodyStatement.parent = constructor
            bodyStatement.assignParentReferences()
        }
    }

    private func addInheritedConstructors(to classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) -> Bool {
        let inheritedConstructorParameters = codebaseInfo.constructorParameters(of: classDeclaration.qualifiedName)
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
            let label = parameter.label ?? "_p\(index)_"
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
        constructor.body = CodeBlock<KotlinStatement>(statements: [])

        classDeclaration.members.append(constructor)
        constructor.parent = classDeclaration
        constructor.assignParentReferences()
    }

    private func fixupConstructor(_ constructor: KotlinFunctionDeclaration) -> Bool {
        guard constructor.delegatingConstructorCall == nil else {
            return true
        }
        guard var body = constructor.body else {
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
            constructor.body = body
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
        switch memberAccess.baseType {
        case .this:
            return functionCall
        case .super:
            return functionCall
        default:
            return nil
        }
    }

    private func addSuperclassCall(to classDeclaration: KotlinClassDeclaration) {
        // If we have a superclass, we must instantiate it
        if let inherits = classDeclaration.inherits.first, codebaseInfo.declarationType(of: inherits.description, mustBeInModule: false) == .classDeclaration {
            classDeclaration.superclassCall = "\(inherits.description)()"
        }
    }
}
