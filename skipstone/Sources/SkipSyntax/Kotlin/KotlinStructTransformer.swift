/// Give struct semantics to Kotlin classes translated from Swift structs.
///
/// - Seealso: `SkipLib/Struct.kt`
class KotlinStructTransformer: KotlinTransformer {
    private let mutationFunctionNames = ("willmutate", "didmutate")

    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        syntaxTree.root.visit { visit($0, translator: translator) }
    }

    private func visit(_ node: KotlinSyntaxNode, translator: KotlinTranslator) -> VisitResult<KotlinSyntaxNode> {
        if let classDeclaration = node as? KotlinClassDeclaration {
            if classDeclaration.declarationType == .structDeclaration {
                updateStructDeclaration(classDeclaration, translator: translator)
            }
        } else if let variableDeclaration = node as? KotlinVariableDeclaration {
            if !variableDeclaration.isStatic, !variableDeclaration.isReadOnly, let extends = variableDeclaration.extends, translator.codebaseInfo?.declarationType(forNamed: extends.0) == .structDeclaration {
                variableDeclaration.mutationFunctionNames = mutationFunctionNames
            }
            return .skip
        } else if let functionDeclaration = node as? KotlinFunctionDeclaration {
            if functionDeclaration.modifiers.isMutating {
                functionDeclaration.body?.addSelfAssignmentMessages(source: translator.syntaxTree.source)
                if let extends = functionDeclaration.extends, translator.codebaseInfo?.declarationType(forNamed: extends.0) == .structDeclaration {
                    functionDeclaration.mutationFunctionNames = mutationFunctionNames
                }
            } else if functionDeclaration.type == .constructorDeclaration {
                functionDeclaration.body?.addSelfAssignmentMessages(source: translator.syntaxTree.source)
            }
        }
        // Recurse to find nested declarations
        return .recurse(nil)
    }

    private func updateStructDeclaration(_ classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) {
        var hasConstructors = false
        var isMutable = false
        var initializableVariableDeclarations: [KotlinVariableDeclaration] = []
        for member in classDeclaration.members {
            if let variableDeclaration = member as? KotlinVariableDeclaration {
                if !variableDeclaration.isStatic && !variableDeclaration.isReadOnly {
                    variableDeclaration.mutationFunctionNames = mutationFunctionNames
                    isMutable = true
                }
                if !variableDeclaration.modifiers.isStatic, variableDeclaration.getter == nil, (!variableDeclaration.isLet || variableDeclaration.value == nil) {
                    initializableVariableDeclarations.append(variableDeclaration)
                }
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                if functionDeclaration.type == .constructorDeclaration {
                    hasConstructors = true
                } else if functionDeclaration.modifiers.isMutating {
                    functionDeclaration.mutationFunctionNames = mutationFunctionNames
                    isMutable = true
                }
            }
        }

        if !hasConstructors && !initializableVariableDeclarations.isEmpty {
            addMemberwiseConstructor(to: classDeclaration, variableDeclarations: initializableVariableDeclarations, translator: translator)
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
        let supdateType: TypeSignature = .optional(.function([TypeSignature.Parameter(type: .any)], .void))
        let supdate = KotlinVariableDeclaration(names: ["supdate"], variableTypes: [supdateType])
        supdate.declaredType = supdateType
        supdate.isProperty = true
        supdate.isGenerated = true
        supdate.modifiers = Modifiers(visibility: .public, isOverride: true)
        supdate.extras = .singleNewline
        supdate.parent = classDeclaration
        supdate.assignParentReferences()
        classDeclaration.members.append(supdate)

        let scount = KotlinVariableDeclaration(names: ["smutatingcount"], variableTypes: [.int])
        scount.value = KotlinNumericLiteral(literal: "0")
        scount.isProperty = true
        scount.isGenerated = true
        scount.modifiers = Modifiers(visibility: .public, isOverride: true)
        scount.parent = classDeclaration
        scount.assignParentReferences()
        classDeclaration.members.append(scount)

        let scopy = KotlinFunctionDeclaration(name: "scopy")
        scopy.modifiers = Modifiers(visibility: .public, isOverride: true)
        scopy.isGenerated = true
        scopy.returnType = .named("MutableStruct", [])

        let constructorCall: KotlinExpression
        if useMemberwiseConstructor {
            let initFunction = KotlinMemberAccess(base: KotlinIdentifier(name: classDeclaration.name), member: "init")
            let arguments = variableDeclarations.map {
                let argumentValue = KotlinIdentifier(name: $0.names[0] ?? "")
                argumentValue.mayBeSharedMutableStruct = $0.mayBeSharedMutableStruct
                return LabeledValue<KotlinExpression>(value: argumentValue.sref())
            }
            constructorCall = KotlinFunctionCall(function: initFunction, arguments: arguments)
        } else {
            constructorCall = KotlinRawExpression(sourceCode: "\(classDeclaration.name)(this as MutableStruct)")
        }
        let returnStatement = KotlinReturn(expression: constructorCall)
        scopy.body = KotlinCodeBlock(statements: [returnStatement])
        scopy.parent = classDeclaration
        scopy.assignParentReferences()
        classDeclaration.members.append(scopy)
    }

    private func addMemberwiseConstructor(to classDeclaration: KotlinClassDeclaration, variableDeclarations: [KotlinVariableDeclaration], translator: KotlinTranslator) {
        let constructor = KotlinFunctionDeclaration(name: "constructor")
        constructor.modifiers = Modifiers(visibility: .public)
        constructor.extras = .singleNewline
        constructor.isGenerated = true

        constructor.parameters = variableDeclarations.map { variableDeclaration in
            let label = variableDeclaration.names[0]
            let type = variableDeclaration.variableTypes[0]
            if type == .none && translator.codebaseInfo != nil {
                variableDeclaration.messages.append(.kotlinConstructorCannotInferPropertyType(variableDeclaration, source: translator.syntaxTree.source))
            }
            var defaultValue: KotlinExpression? = nil
            if let value = variableDeclaration.value {
                defaultValue = KotlinSharedExpressionPointer(shared: value)
            } else if type.isOptional {
                defaultValue = KotlinNullLiteral()
            }
            return Parameter(externalLabel: label, declaredType: type, defaultValue: defaultValue)
        }

        var bodyStatements: [KotlinStatement] = []
        bodyStatements += variableDeclarations.map { variableDeclaration in
            return KotlinRawStatement(sourceCode: "this.\(variableDeclaration.names[0] ?? "") = \(variableDeclaration.names[0] ?? "")")
        }
        constructor.body = KotlinCodeBlock(statements: bodyStatements)
        constructor.parent = classDeclaration
        constructor.assignParentReferences()
        classDeclaration.members.append(constructor)
    }

    private func addMutableStructCopyConstructor(to classDeclaration: KotlinClassDeclaration, variableDeclarations: [KotlinVariableDeclaration]) {
        // We use a parameter of type 'MutableStruct' to avoid conflicts with any user-defined constructor
        let constructor = KotlinFunctionDeclaration(name: "constructor")
        constructor.parameters = [Parameter(externalLabel: "copy", declaredType: .named("MutableStruct", []))]
        constructor.modifiers = Modifiers(visibility: .private)
        constructor.extras = .singleNewline
        constructor.isGenerated = true

        var bodyStatements: [KotlinStatement] = []
        bodyStatements.append(KotlinRawStatement(sourceCode: "val copy = copy as \(classDeclaration.name)"))
        bodyStatements += variableDeclarations.map { variableDeclaration in
            return KotlinRawStatement(sourceCode: "this.\(variableDeclaration.names[0] ?? "") = copy.\(variableDeclaration.names[0] ?? "")")
        }
        constructor.body = KotlinCodeBlock(statements: bodyStatements)
        constructor.parent = classDeclaration
        constructor.assignParentReferences()
        classDeclaration.members.append(constructor)
    }
}
