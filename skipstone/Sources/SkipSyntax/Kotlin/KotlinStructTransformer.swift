/// Give struct semantics to Kotlin classes translated from Swift structs.
///
/// - Seealso: `SkipLib/Struct.kt`
final class KotlinStructTransformer: KotlinTransformer {
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
            if !variableDeclaration.isStatic, variableDeclaration.apiFlags.contains(.writeable) && !variableDeclaration.attributes.isNonMutating, let extends = variableDeclaration.extends, translator.codebaseInfo?.mayBeMutableStruct(type: extends.0) == true {
                variableDeclaration.mutationFunctionNames = mutationFunctionNames
            }
            return .skip
        } else if let functionDeclaration = node as? KotlinFunctionDeclaration {
            if functionDeclaration.modifiers.isMutating {
                handleSelfAssignments(in: functionDeclaration, translator: translator)
                if let extends = functionDeclaration.extends, translator.codebaseInfo?.mayBeMutableStruct(type: extends.0) == true {
                    functionDeclaration.mutationFunctionNames = mutationFunctionNames
                }
            } else if functionDeclaration.type == .constructorDeclaration, (functionDeclaration.parent as? KotlinClassDeclaration)?.declarationType == .structDeclaration {
                handleSelfAssignments(in: functionDeclaration, translator: translator)
            }
        }
        // Recurse to find nested declarations
        return .recurse(nil)
    }

    private func updateStructDeclaration(_ classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) {
        let isNoCopy = classDeclaration.attributes.kotlinHasDirective(.nocopy)
        var hasConstructors = false
        var isMutable = false
        var initializableVariableDeclarations: [KotlinVariableDeclaration] = []
        for member in classDeclaration.members {
            if let variableDeclaration = member as? KotlinVariableDeclaration {
                if !isNoCopy && !variableDeclaration.isStatic && ((variableDeclaration.apiFlags.contains(.writeable) && !variableDeclaration.attributes.isNonMutating && variableDeclaration.getter == nil) || variableDeclaration.modifiers.isLazy) && !variableDeclaration.isGenerated {
                    variableDeclaration.mutationFunctionNames = mutationFunctionNames
                    isMutable = true
                }
                if variableDeclaration.declaredType.isUnwrappedOptional {
                    // Not initialized
                } else if variableDeclaration.value == nil && (variableDeclaration.attributes.contains(.environment) || variableDeclaration.attributes.contains(.environmentObject)) {
                    // It's so rare to want to pass environment values to the constructor that we omit them when they'd cause an error due to
                    // lack of initial value. To fix this we'd need help from the SwiftUI transformer (which runs after us) to figure out the
                    // variable type in many cases
                } else if !variableDeclaration.modifiers.isStatic && variableDeclaration.getter == nil && (!variableDeclaration.isLet || variableDeclaration.value == nil) && !variableDeclaration.modifiers.isLazy && !variableDeclaration.isGenerated {
                    initializableVariableDeclarations.append(variableDeclaration)
                }
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration, !functionDeclaration.isGenerated {
                if functionDeclaration.type == .constructorDeclaration {
                    hasConstructors = true
                } else if !isNoCopy && functionDeclaration.modifiers.isMutating {
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
        let supdateType: TypeSignature = .function([TypeSignature.Parameter(type: .any)], .void, [], nil).asOptional(true)
        let supdate = KotlinVariableDeclaration(names: ["supdate"], variableTypes: [supdateType])
        supdate.declaredType = supdateType
        supdate.role = .property
        supdate.isGenerated = true
        supdate.modifiers = Modifiers(visibility: .public, isOverride: true)
        supdate.apiFlags = [.writeable]
        supdate.extras = .singleNewline
        supdate.parent = classDeclaration
        supdate.assignParentReferences()
        classDeclaration.members.append(supdate)

        let scount = KotlinVariableDeclaration(names: ["smutatingcount"], variableTypes: [.int])
        scount.value = KotlinNumericLiteral(literal: "0")
        scount.role = .property
        scount.isGenerated = true
        scount.modifiers = Modifiers(visibility: .public, isOverride: true)
        scount.apiFlags = [.writeable]
        scount.parent = classDeclaration
        scount.assignParentReferences()
        classDeclaration.members.append(scount)

        let scopy = KotlinFunctionDeclaration(name: "scopy")
        scopy.modifiers = Modifiers(visibility: .public, isOverride: true)
        scopy.isGenerated = true
        scopy.returnType = .named("MutableStruct", [])

        let constructorCall: KotlinExpression
        if useMemberwiseConstructor {
            let initFunction = KotlinMemberAccess(base: KotlinIdentifier(name: classDeclaration.signature.kotlin), member: "init")
            let arguments = variableDeclarations.map {
                let propertyName = $0.attributes.contains(.binding) ? "_" + $0.propertyName : $0.propertyName
                let argumentValue = KotlinIdentifier(name: propertyName)
                argumentValue.mayBeSharedMutableStruct = $0.mayBeSharedMutableStruct
                return LabeledValue<KotlinExpression>(value: argumentValue)
            }
            constructorCall = KotlinFunctionCall(function: initFunction, arguments: arguments)
        } else {
            constructorCall = KotlinRawExpression(sourceCode: "\(classDeclaration.signature.kotlin)(this as MutableStruct)")
        }
        let returnStatement = KotlinReturn(expression: constructorCall)
        scopy.body = KotlinCodeBlock(statements: [returnStatement])
        scopy.parent = classDeclaration
        scopy.assignParentReferences()
        classDeclaration.members.append(scopy)
    }

    private func addMemberwiseConstructor(to classDeclaration: KotlinClassDeclaration, variableDeclarations: [KotlinVariableDeclaration], translator: KotlinTranslator) {
        var minimumVisibility: Modifiers.Visibility = .public
        for variableDeclaration in variableDeclarations {
            if variableDeclaration.modifiers.visibility == .private {
                minimumVisibility = .private
                break
            } else if variableDeclaration.modifiers.visibility == .internal && minimumVisibility == .public {
                minimumVisibility = .internal
            }
        }

        // The visibility of the generated constructor matches the minimum property visibility
        let constructor = KotlinFunctionDeclaration(name: "constructor")
        if (minimumVisibility == .private && classDeclaration.modifiers.visibility != .private)
            || (minimumVisibility == .internal && classDeclaration.modifiers.visibility == .public) {
            constructor.modifiers = Modifiers(visibility: minimumVisibility)
        } else {
            // Use public to omit any modifier on the generated code
            constructor.modifiers = Modifiers(visibility: .public)
        }
        constructor.extras = .singleNewline
        constructor.isGenerated = true

        constructor.parameters = variableDeclarations.map { variableDeclaration in
            let label = variableDeclaration.propertyName
            var type = variableDeclaration.propertyType
            if type == .none {
                if translator.codebaseInfo != nil {
                    variableDeclaration.messages.append(.kotlinConstructorCannotInferPropertyType(variableDeclaration, source: translator.syntaxTree.source))
                }
            } else if variableDeclaration.attributes.contains(.binding) {
                type = type.asBinding()
            }
            var defaultValue: KotlinExpression? = nil
            if let value = variableDeclaration.value {
                defaultValue = value
                // Clear the default value if it will be assigned from the constructor to prevent creating the value twice
                if variableDeclaration.declaredType == .none && variableDeclaration.propertyType == .none {
                    // We can't clear it, however, if we don't know what type to declare the variable
                    defaultValue = KotlinSharedExpressionPointer(shared: value)
                } else {
                    defaultValue = value
                    variableDeclaration.value = nil
                    if variableDeclaration.declaredType == .none {
                        variableDeclaration.declaredType = variableDeclaration.propertyType
                    }
                }
            } else if type.isOptional {
                defaultValue = KotlinNullLiteral()
            }
            return Parameter(externalLabel: label, declaredType: type, defaultValue: defaultValue)
        }

        var bodyStatements: [KotlinStatement] = []
        bodyStatements += variableDeclarations.map { variableDeclaration in
            var assignment: String
            if variableDeclaration.attributes.contains(.state) || variableDeclaration.attributes.contains(.stateObject) {
                var value = variableDeclaration.propertyName
                if variableDeclaration.mayBeSharedMutableStruct {
                    value += ".sref()"
                }
                assignment = "this._\(variableDeclaration.propertyName) = skip.ui.State(\(value))"
            } else if variableDeclaration.attributes.contains(.appStorage) {
                var value = variableDeclaration.propertyName
                if variableDeclaration.mayBeSharedMutableStruct {
                    value += ".sref()"
                }
                let appStorageParameters = KotlinSwiftUITransformer.appStorageAdditionalInitParameters(for: variableDeclaration)
                assignment = "this._\(variableDeclaration.propertyName) = skip.ui.AppStorage(wrappedValue = \(value), \(appStorageParameters))"
            } else if variableDeclaration.attributes.contains(.binding) {
                assignment = "this._\(variableDeclaration.propertyName) = \(variableDeclaration.propertyName)"
            } else {
                assignment = "this.\(variableDeclaration.propertyName) = \(variableDeclaration.propertyName)"
                if !variableDeclaration.apiFlags.contains(.writeable) && variableDeclaration.mayBeSharedMutableStruct {
                    assignment += ".sref()"
                }
            }
            return KotlinRawStatement(sourceCode: assignment)
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
        bodyStatements.append(KotlinRawStatement(sourceCode: "@Suppress(\"NAME_SHADOWING\", \"UNCHECKED_CAST\") val copy = copy as \(classDeclaration.signature.kotlin)"))
        bodyStatements += variableDeclarations.map { variableDeclaration in
            if variableDeclaration.attributes.contains(.state) || variableDeclaration.attributes.contains(.stateObject) {
                return KotlinRawStatement(sourceCode: "this._\(variableDeclaration.propertyName) = skip.ui.State(copy.\(variableDeclaration.propertyName))")
            } else if variableDeclaration.attributes.contains(.appStorage) || variableDeclaration.attributes.contains(.binding) {
                return KotlinRawStatement(sourceCode: "this._\(variableDeclaration.propertyName) = copy._\(variableDeclaration.propertyName)")
            } else {
                return KotlinRawStatement(sourceCode: "this.\(variableDeclaration.propertyName) = copy.\(variableDeclaration.propertyName)")
            }
        }
        constructor.body = KotlinCodeBlock(statements: bodyStatements)
        constructor.parent = classDeclaration
        constructor.assignParentReferences()
        classDeclaration.members.append(constructor)
    }

    private func makeSelfAssignable(_ classDeclaration: KotlinClassDeclaration) -> [KotlinVariableDeclaration] {
        // Assign all stored variables
        var storedVariableDeclarations: [KotlinVariableDeclaration] = []
        for member in classDeclaration.members {
            guard let variableDeclaration = member as? KotlinVariableDeclaration, !variableDeclaration.isStatic && !variableDeclaration.isGenerated else {
                continue
            }
            guard variableDeclaration.getter == nil else {
                continue
            }
            
            // Make let vars writeable, in case they can have different initial values
            variableDeclaration.isAssignFromWriteable = true
            storedVariableDeclarations.append(variableDeclaration)
        }
        return storedVariableDeclarations
    }

    private func handleSelfAssignments(in functionDeclaration: KotlinFunctionDeclaration, translator: KotlinTranslator) {
        guard let body = functionDeclaration.body else {
            return
        }
        let classDeclaration = functionDeclaration.parent as? KotlinClassDeclaration
        guard classDeclaration != nil || functionDeclaration.extends != nil else {
            return
        }

        body.visit { node in
            guard let binaryOperator = node as? KotlinBinaryOperator, binaryOperator.op.symbol == "=", let lhs = binaryOperator.lhs as? KotlinIdentifier, lhs.name == "self", let statement = binaryOperator.parent as? KotlinExpressionStatement else {
                // Closure self assignments are reassigning captured self, not mutating the struct
                return node is KotlinClosure ? .skip : .recurse(nil)
            }
            guard functionDeclaration.extends == nil else {
                binaryOperator.messages.append(.kotlinExtensionSelfAssignment(binaryOperator, source: translator.syntaxTree.source))
                return .skip
            }
            guard let classDeclaration else {
                return .skip
            }

            let storedVariables = makeSelfAssignable(classDeclaration)
            var copyStatements: [KotlinStatement] = []
            if functionDeclaration.type == .constructorDeclaration {
                // In constructors we manually copy each property inline to satisfy the compiler that all properties are initialized
                let copyName: String
                if let copyIdentifier = binaryOperator.rhs as? KotlinIdentifier {
                    copyName = copyIdentifier.name
                } else {
                    // Create a local to copy from so that we don't re-evaluate the expression and cause unwanted side effects
                    copyName = "assignfrom"
                    let copyVariable = KotlinVariableDeclaration(names: [copyName], variableTypes: [classDeclaration.signature], sourceFile: binaryOperator.sourceFile, sourceRange: binaryOperator.sourceRange)
                    copyVariable.value = binaryOperator.rhs
                    copyVariable.isLet = true
                    copyStatements.append(copyVariable)
                }
                copyStatements += selfAssignStatements(from: copyName, storedVariableDeclarations: storedVariables)
            } else {
                // Outside of constructors we call a method to copy all properties rather than expand inline.
                // This makes it easier to surround the code with calls to suppress side effects
                let assignCall = KotlinFunctionCall(function: KotlinIdentifier(name: "assignfrom"), arguments: [LabeledValue(value: binaryOperator.rhs)])
                let assignStatement = KotlinExpressionStatement(type: .expression, sourceFile: statement.sourceFile, sourceRange: statement.sourceRange)
                assignStatement.expression = assignCall
                copyStatements.append(assignStatement)

                addAssignFromFunction(to: classDeclaration, storedVariableDeclarations: storedVariables)
            }
            if let parent = statement.parent as? KotlinStatement {
                parent.insert(statements: copyStatements, after: statement)
                parent.remove(statement: statement)
            } else {
                binaryOperator.messages.append(.internalError(binaryOperator, source: translator.syntaxTree.source))
            }
            return .skip
        }
    }

    private func addAssignFromFunction(to classDeclaration: KotlinClassDeclaration, storedVariableDeclarations: [KotlinVariableDeclaration]) {
        // Already added?
        guard !classDeclaration.members.contains(where: { ($0 as? KotlinFunctionDeclaration)?.name == "assignfrom" }) else {
            return
        }

        let assignfrom = KotlinFunctionDeclaration(name: "assignfrom")
        assignfrom.parameters = [Parameter(externalLabel: "target", declaredType: classDeclaration.signature)]
        assignfrom.modifiers = Modifiers(visibility: .private)
        assignfrom.extras = .singleNewline
        assignfrom.isGenerated = true
        assignfrom.suppressSideEffects = true

        let bodyStatements = selfAssignStatements(from: "target", storedVariableDeclarations: storedVariableDeclarations)
        assignfrom.body = KotlinCodeBlock(statements: bodyStatements)
        assignfrom.body?.disallowSingleStatementAppend = true // Single statement assignment disallowed
        assignfrom.parent = classDeclaration
        assignfrom.assignParentReferences()
        classDeclaration.members.append(assignfrom)
    }

    private func selfAssignStatements(from copy: String, storedVariableDeclarations: [KotlinVariableDeclaration]) -> [KotlinStatement] {
        return storedVariableDeclarations.map { variableDeclaration in
            if variableDeclaration.attributes.contains(.state) {
                return KotlinRawStatement(sourceCode: "this._\(variableDeclaration.propertyName) = skip.ui.State(\(copy).\(variableDeclaration.propertyName))")
            } else if variableDeclaration.attributes.contains(.appStorage) || variableDeclaration.attributes.contains(.binding) {
                return KotlinRawStatement(sourceCode: "this._\(variableDeclaration.propertyName) = \(copy)._\(variableDeclaration.propertyName)")
            } else {
                return KotlinRawStatement(sourceCode: "this.\(variableDeclaration.propertyName) = \(copy).\(variableDeclaration.propertyName)")
            }
        }
    }
}
