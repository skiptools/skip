/// Give struct semantics to Kotlin classes translated from Swift structs.
class KotlinStructPlugin: KotlinPlugin {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        syntaxTree.root.visit(perform: visit)
    }

    private func visit(_ node: KotlinSyntaxNode) -> VisitResult<KotlinSyntaxNode> {
        guard let classDeclaration = node as? KotlinClassDeclaration else {
            // Don't skip the root code block
            return node is KotlinCodeBlock ? .recurse(nil) : .skip
        }
        if classDeclaration.declarationType == .structDeclaration {
            updateStructDeclaration(classDeclaration)
        }
        return .recurse(nil)
    }

    private func updateStructDeclaration(_ classDeclaration: KotlinClassDeclaration) {
        classDeclaration.inherits.append(.named("ValueSemantics", []))
        let hasConstructors = classDeclaration.members.contains { $0.type == .constructorDeclaration }
        let variableDeclarations = initializableMembers(of: classDeclaration)
        if !hasConstructors && !variableDeclarations.isEmpty {
            addMemberwiseConstructor(to: classDeclaration, variableDeclarations: variableDeclarations)
        } else if !variableDeclarations.isEmpty {
            addValueSemanticsCopyConstructor(to: classDeclaration, variableDeclarations: variableDeclarations)
        }
        // If we generated a memberwise constructor (or have no members and get a default constructor), we can use that to create a copy.
        // Otherwise we generate a copy constructor. In particular, we do not trust any user-written constructor to perform a pure copy
        addValueSemanticsAPI(to: classDeclaration, variableDeclarations: variableDeclarations, useMemberwiseConstructor: !hasConstructors)
    }

    private func addValueSemanticsAPI(to classDeclaration: KotlinClassDeclaration, variableDeclarations: [KotlinVariableDeclaration], useMemberwiseConstructor: Bool) {
        let declaredType: TypeSignature = .optional(.function([TypeSignature.Parameter(type: .any)], .void))
        let valupdate = KotlinVariableDeclaration(names: ["valupdate"], variableTypes: [declaredType])
        valupdate.declaredType = declaredType
        valupdate.isProperty = true
        valupdate.modifiers = Modifiers(visibility: .public, isOverride: true)
        valupdate.extras = .singleNewline
        classDeclaration.members.append(valupdate)

        let valcopy = KotlinFunctionDeclaration(name: "valcopy")
        valcopy.returnType = .named("ValueSemantics", [])
        valcopy.modifiers = Modifiers(visibility: .public, isOverride: true)
        valcopy.extras = .singleNewline

        let constructorCall: KotlinExpression
        if useMemberwiseConstructor {
            let initFunction = KotlinMemberAccess(base: KotlinIdentifier(name: classDeclaration.name), member: "init")
            let arguments = variableDeclarations.map {
                let argumentValue = KotlinIdentifier(name: $0.names[0])
                argumentValue.mayBeSharedMutableValue = $0.mayBeSharedMutableValue
                return LabeledValue<KotlinExpression>(value: argumentValue.valueReference())
            }
            constructorCall = KotlinFunctionCall(function: initFunction, arguments: arguments)
        } else {
            constructorCall = KotlinRawExpression(sourceCode: "\(classDeclaration.name)(this as ValueSemantics)")
        }
        let returnStatement = KotlinReturn(expression: constructorCall)
        valcopy.body = KotlinCodeBlock(statements: [returnStatement])
        classDeclaration.members.append(valcopy)
    }

    private func initializableMembers(of classDeclaration: KotlinClassDeclaration) -> [KotlinVariableDeclaration] {
        return classDeclaration.members.compactMap { (member: KotlinStatement) -> KotlinVariableDeclaration? in
            guard let variableDeclaration = member as? KotlinVariableDeclaration,
                  !variableDeclaration.modifiers.isStatic, variableDeclaration.getter == nil, (!variableDeclaration.isLet || variableDeclaration.value == nil) else {
                return nil
            }
            return variableDeclaration
        }
    }

    private func addMemberwiseConstructor(to classDeclaration: KotlinClassDeclaration, variableDeclarations: [KotlinVariableDeclaration]) {
        let constructor = KotlinFunctionDeclaration(name: "constructor")
        constructor.parameters = variableDeclarations.map { variableDeclaration in
            let label = variableDeclaration.names[0]
            let type = variableDeclaration.variableTypes[0]
            let defaultValue = variableDeclaration.value.map { KotlinSharedExpressionPointer(shared: $0) }
            return Parameter(externalLabel: label, declaredType: type, isVariadic: false, defaultValue: defaultValue)
        }
        constructor.modifiers = Modifiers(visibility: .public)
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
    }

    private func addValueSemanticsCopyConstructor(to classDeclaration: KotlinClassDeclaration, variableDeclarations: [KotlinVariableDeclaration]) {
        // We use a parameter of type 'ValueSemantics' to avoid conflicts with any user-defined constructor
        let constructor = KotlinFunctionDeclaration(name: "constructor")
        constructor.parameters = [Parameter(externalLabel: "copy", declaredType: .named("ValueSemantics", []))]
        constructor.modifiers = Modifiers(visibility: .private)
        constructor.extras = .singleNewline

        let bodyStatements = variableDeclarations.map { variableDeclaration in
            let selfIdentifier = KotlinIdentifier(name: "self")
            let memberAccess = KotlinMemberAccess(base: selfIdentifier, member: variableDeclaration.names[0])
            let copyIdentifier = KotlinIdentifier(name: "copy")
            let copyMemberAccess = KotlinMemberAccess(base: copyIdentifier, member: variableDeclaration.names[0])
            copyMemberAccess.mayBeSharedMutableValue = variableDeclaration.mayBeSharedMutableValue
            let assignmentOperator = KotlinBinaryOperator(op: .with(symbol: "="), lhs: memberAccess, rhs: copyMemberAccess.valueReference())
            let statement = KotlinExpressionStatement(type: .expression)
            statement.expression = assignmentOperator
            return statement
        }
        constructor.body = KotlinCodeBlock(statements: bodyStatements)
        classDeclaration.members.append(constructor)
    }
}
