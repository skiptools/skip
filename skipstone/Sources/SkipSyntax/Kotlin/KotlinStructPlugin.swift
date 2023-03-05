/// Give struct semantics to Kotlin classes translated from Swift structs.
class KotlinStructPlugin: KotlinPlugin {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        syntaxTree.root.statements.forEach { $0.visit(perform: self.visit) }
    }

    private func visit(_ node: KotlinSyntaxNode) -> VisitResult<KotlinSyntaxNode> {
        guard let classDeclaration = node as? KotlinClassDeclaration else {
            return .skip
        }
        if classDeclaration.declarationType == .structDeclaration {
            updateStructDeclaration(classDeclaration)
        }
        return .recurse(nil)
    }

    private func updateStructDeclaration(_ classDeclaration: KotlinClassDeclaration) {
        var hasConstructors = false
        var isMutable = false
        var initializableVariableDeclarations: [KotlinVariableDeclaration] = []
        for member in classDeclaration.members {
            if let variableDeclaration = member as? KotlinVariableDeclaration {
                if !variableDeclaration.isStatic && !variableDeclaration.isReadOnly {
                    isMutable = true
                }
                if !variableDeclaration.modifiers.isStatic, variableDeclaration.getter == nil, (!variableDeclaration.isLet || variableDeclaration.value == nil) {
                    initializableVariableDeclarations.append(variableDeclaration)
                }
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                if functionDeclaration.type == .constructorDeclaration {
                    hasConstructors = true
                } else if functionDeclaration.modifiers.isMutating {
                    isMutable = true
                }
            }
        }

        if !hasConstructors && !initializableVariableDeclarations.isEmpty {
            addMemberwiseConstructor(to: classDeclaration, variableDeclarations: initializableVariableDeclarations)
        } else if isMutable && !initializableVariableDeclarations.isEmpty {
            addMutableStructCopyConstructor(to: classDeclaration, variableDeclarations: initializableVariableDeclarations)
        }
        if isMutable {
            classDeclaration.inherits.append(.named("MutableStruct", []))
            // If we generated a memberwise constructor (or have no members and get a default constructor), we can use that to create a copy.
            // Otherwise we generate a copy constructor. In particular, we do not trust any user-written constructor to perform a pure copy
            addMutableStructAPI(to: classDeclaration, variableDeclarations: initializableVariableDeclarations, useMemberwiseConstructor: !hasConstructors)
        }
    }

    private func addMutableStructAPI(to classDeclaration: KotlinClassDeclaration, variableDeclarations: [KotlinVariableDeclaration], useMemberwiseConstructor: Bool) {
        let declaredType: TypeSignature = .optional(.function([TypeSignature.Parameter(type: .any)], .void))
        let supdate = KotlinVariableDeclaration(names: ["supdate"], variableTypes: [declaredType])
        supdate.declaredType = declaredType
        supdate.isProperty = true
        supdate.modifiers = Modifiers(visibility: .public, isOverride: true)
        supdate.extras = .singleNewline
        classDeclaration.members.append(supdate)

        let scopy = KotlinFunctionDeclaration(name: "scopy")
        scopy.returnType = .named("MutableStruct", [])
        scopy.modifiers = Modifiers(visibility: .public, isOverride: true)
        scopy.extras = .singleNewline

        let constructorCall: KotlinExpression
        if useMemberwiseConstructor {
            let initFunction = KotlinMemberAccess(base: KotlinIdentifier(name: classDeclaration.name), member: "init")
            let arguments = variableDeclarations.map {
                let argumentValue = KotlinIdentifier(name: $0.names[0])
                argumentValue.mayBeSharedMutableStruct = $0.mayBeSharedMutableStruct
                return LabeledValue<KotlinExpression>(value: argumentValue.sref())
            }
            constructorCall = KotlinFunctionCall(function: initFunction, arguments: arguments)
        } else {
            constructorCall = KotlinRawExpression(sourceCode: "\(classDeclaration.name)(this as MutableStruct)")
        }
        let returnStatement = KotlinReturn(expression: constructorCall)
        scopy.body = KotlinCodeBlock(statements: [returnStatement])
        classDeclaration.members.append(scopy)
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

        var bodyStatements: [KotlinStatement] = []
        bodyStatements += variableDeclarations.map { variableDeclaration in
            return KotlinRawStatement(sourceCode: "this.\(variableDeclaration.names[0]) = \(variableDeclaration.names[0])")
        }
        constructor.body = KotlinCodeBlock(statements: bodyStatements)
        classDeclaration.members.append(constructor)
    }

    private func addMutableStructCopyConstructor(to classDeclaration: KotlinClassDeclaration, variableDeclarations: [KotlinVariableDeclaration]) {
        // We use a parameter of type 'MutableStruct' to avoid conflicts with any user-defined constructor
        let constructor = KotlinFunctionDeclaration(name: "constructor")
        constructor.parameters = [Parameter(externalLabel: "copy", declaredType: .named("MutableStruct", []))]
        constructor.modifiers = Modifiers(visibility: .private)
        constructor.extras = .singleNewline

        var bodyStatements: [KotlinStatement] = []
        bodyStatements.append(KotlinRawStatement(sourceCode: "val copy = copy as \(classDeclaration.name)"))
        bodyStatements += variableDeclarations.map { variableDeclaration in
            return KotlinRawStatement(sourceCode: "this.\(variableDeclaration.names[0]) = copy.\(variableDeclaration.names[0])")
        }
        constructor.body = KotlinCodeBlock(statements: bodyStatements)
        classDeclaration.members.append(constructor)
    }
}
