// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

/// Give struct semantics to Kotlin classes translated from Swift structs.
///
/// - Seealso: `SkipLib/Struct.kt`
final class KotlinStructTransformer: KotlinTransformer {
    static let mutationFunctionNames = ("willmutate", "didmutate")

    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        syntaxTree.root.visit { visit($0, translator: translator) }
        return []
    }

    private func visit(_ node: KotlinSyntaxNode, translator: KotlinTranslator) -> VisitResult<KotlinSyntaxNode> {
        if let classDeclaration = node as? KotlinClassDeclaration {
            if classDeclaration.declarationType == .structDeclaration {
                updateStructDeclaration(classDeclaration, translator: translator)
            }
        } else if let variableDeclaration = node as? KotlinVariableDeclaration {
            if !variableDeclaration.isStatic, variableDeclaration.apiFlags.options.contains(.writeable) && !variableDeclaration.attributes.isNonMutating, let extends = variableDeclaration.extends, translator.codebaseInfo?.mayBeMutableStruct(type: extends.0) == true {
                variableDeclaration.mutationFunctionNames = Self.mutationFunctionNames
            }
            return .skip
        } else if let functionDeclaration = node as? KotlinFunctionDeclaration {
            if functionDeclaration.modifiers.isMutating {
                handleSelfAssignments(in: functionDeclaration, translator: translator)
                if let extends = functionDeclaration.extends, translator.codebaseInfo?.mayBeMutableStruct(type: extends.0) == true {
                    functionDeclaration.mutationFunctionNames = Self.mutationFunctionNames
                }
            } else if functionDeclaration.type == .constructorDeclaration, (functionDeclaration.parent as? KotlinClassDeclaration)?.declarationType == .structDeclaration {
                handleSelfAssignments(in: functionDeclaration, translator: translator)
            }
        }
        // Recurse to find nested declarations
        return .recurse(nil)
    }

    private func updateStructDeclaration(_ classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) {
        let isNoCopy = classDeclaration.attributes.contains(directive: KotlinDirective.nocopy)
        var hasConstructors = false
        var isMutable = false
        var hasMutableStructCopyConstructor = false
        var transformsConstructorParameters = false
        var initializableVariableDeclarations: [KotlinVariableDeclaration] = []
        var copyableVariableDeclarations: [KotlinVariableDeclaration] = []
        for member in classDeclaration.members {
            if let variableDeclaration = member as? KotlinVariableDeclaration {
                if !isNoCopy && !variableDeclaration.isStatic && ((variableDeclaration.apiFlags.options.contains(.writeable) && !variableDeclaration.attributes.isNonMutating && variableDeclaration.getter == nil) || variableDeclaration.modifiers.isLazy) && !variableDeclaration.isGenerated {
                    variableDeclaration.mutationFunctionNames = Self.mutationFunctionNames
                    isMutable = true
                }
                if variableDeclaration.value == nil && (variableDeclaration.attributes.environmentAttribute != nil || variableDeclaration.attributes.contains(.focusState)) {
                    // It's so rare to want to pass environment values to the constructor that we omit them when they'd cause an error due to
                    // lack of initial value. To fix this we'd need help from the SwiftUI transformer (which runs after us) to figure out the
                    // variable type in many cases
                } else if !variableDeclaration.modifiers.isStatic && variableDeclaration.getter == nil && !variableDeclaration.isGenerated {
                    copyableVariableDeclarations.append(variableDeclaration)
                    if !variableDeclaration.isLet || variableDeclaration.value == nil {
                        initializableVariableDeclarations.append(variableDeclaration)
                        transformsConstructorParameters = transformsConstructorParameters || variableDeclaration.isTransformedToViewBuilderClosureParameter
                    }
                }
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                if functionDeclaration.isMutableStructCopyConstructor {
                    hasMutableStructCopyConstructor = true
                } else if !functionDeclaration.isGenerated {
                    if functionDeclaration.type == .constructorDeclaration {
                        // NOTE: Swift doesn't generate a default constructor even if your only constructor is a custom Decodable
                        // constructor. So this condition shouldn't be here. But we had this "bug" early on in the transpiler, and
                        // we've decided to maintain the previous behavior in case it is being relied upon
                        if !functionDeclaration.isDecodableConstructor || (translator.syntaxTree.isBridgeFile && !functionDeclaration.isInIfSkipBlock) {
                            hasConstructors = true
                        }
                    } else if !isNoCopy && functionDeclaration.modifiers.isMutating {
                        functionDeclaration.mutationFunctionNames = Self.mutationFunctionNames
                        isMutable = true
                    }
                }
            }
        }
        let isOptionSet = classDeclaration.inherits.contains { $0.isNamed("OptionSet", moduleName: "Swift") }
        isMutable = isMutable || isOptionSet

        let needsMemberwiseConstructor = !classDeclaration.unbridgedMembers.suppressDefaultConstructorGeneration && !hasConstructors && !initializableVariableDeclarations.isEmpty
        if needsMemberwiseConstructor {
            addMemberwiseConstructor(to: classDeclaration, variableDeclarations: initializableVariableDeclarations, translator: translator)
        }
        // The reason we use a mutable struct copy constructor for bridged generic Swift types is that
        // we can't bridge standard constructors of generic types
        let needsMutableStructCopyConstructor = isMutable && (classDeclaration.unbridgedMembers.suppressDefaultConstructorGeneration || transformsConstructorParameters || (!needsMemberwiseConstructor && !copyableVariableDeclarations.isEmpty) || (needsMemberwiseConstructor && copyableVariableDeclarations.count > initializableVariableDeclarations.count) || (translator.syntaxTree.isBridgeFile && !classDeclaration.isInIfSkipBlock && !classDeclaration.generics.isEmpty))
        if needsMutableStructCopyConstructor && !hasMutableStructCopyConstructor {
            addMutableStructCopyConstructor(to: classDeclaration, isOptionSet: isOptionSet, variableDeclarations: copyableVariableDeclarations)
        }
        if !classDeclaration.unbridgedMembers.suppressDefaultConstructorGeneration && !hasConstructors && !needsMemberwiseConstructor && needsMutableStructCopyConstructor {
            // If we add a copy constructor, be sure to also have a default constructor
            addMemberwiseConstructor(to: classDeclaration, variableDeclarations: [], translator: translator)
        }
        if isMutable {
            classDeclaration.inherits.append(.named("MutableStruct", []))
            // If we generated a complete memberwise constructor (or have no members and get a default constructor), we can use that to create
            // a copy. Otherwise we generate a copy constructor. We do not trust any user-written constructor to perform a pure copy
            addMutableStructAPI(to: classDeclaration, variableDeclarations: initializableVariableDeclarations, useMutableStructCopyConstructor: needsMutableStructCopyConstructor)
        }
    }

    private func addMutableStructAPI(to classDeclaration: KotlinClassDeclaration, variableDeclarations: [KotlinVariableDeclaration], useMutableStructCopyConstructor: Bool) {
        let supdateType: TypeSignature = .function([TypeSignature.Parameter(type: .any)], .void, APIFlags(), nil).asOptional(true)
        let supdate = KotlinVariableDeclaration(names: ["supdate"], variableTypes: [supdateType])
        supdate.declaredType = supdateType
        supdate.role = .property
        supdate.isGenerated = true
        supdate.modifiers = Modifiers(visibility: .public, isOverride: true)
        supdate.apiFlags = APIFlags(isWriteable: true)
        supdate.extras = .singleNewline
        supdate.parent = classDeclaration
        supdate.assignParentReferences()
        classDeclaration.members.append(supdate)

        let scount = KotlinVariableDeclaration(names: ["smutatingcount"], variableTypes: [.int])
        scount.value = KotlinNumericLiteral(literal: "0")
        scount.role = .property
        scount.isGenerated = true
        scount.modifiers = Modifiers(visibility: .public, isOverride: true)
        scount.apiFlags = APIFlags(isWriteable: true)
        scount.parent = classDeclaration
        scount.assignParentReferences()
        classDeclaration.members.append(scount)

        let scopy = KotlinFunctionDeclaration(name: "scopy")
        scopy.modifiers = Modifiers(visibility: .public, isOverride: true)
        scopy.isGenerated = true
        scopy.returnType = .named("MutableStruct", [])

        let constructorCall: KotlinExpression
        if useMutableStructCopyConstructor {
            constructorCall = KotlinRawExpression(sourceCode: "\(classDeclaration.signature.kotlin)(this as MutableStruct)")
        } else {
            let initFunction = KotlinMemberAccess(base: KotlinIdentifier(name: classDeclaration.signature.kotlin), member: "init")
            let arguments = variableDeclarations.map { variableDeclaration in
                let propertyName = variableDeclaration.attributes.contains(.binding) ? "_" + variableDeclaration.propertyName : variableDeclaration.propertyName
                let identifier = KotlinIdentifier(name: propertyName)
                identifier.mayBeSharedMutableStruct = variableDeclaration.mayBeSharedMutableStruct

                let argumentValue: KotlinExpression
                if variableDeclaration.modifiers.isLazy {
                    // if (varinitialized) { var } else { null }
                    let isInitialized = KotlinIdentifier(name: KotlinVariableStorage.isLazyInitialized(variableDeclaration))
                    let ifCondition = KotlinIf.ConditionSet(conditions: [isInitialized])
                    let ifBody = KotlinCodeBlock(statements: [KotlinExpressionStatement(expression: identifier)])
                    let ifInitialized = KotlinIf(conditionSets: [ifCondition], body: ifBody)
                    ifInitialized.elseBody = KotlinCodeBlock(statements: [KotlinExpressionStatement(expression: KotlinNullLiteral())])
                    argumentValue = ifInitialized
                } else {
                    argumentValue = identifier
                }
                return LabeledValue<KotlinExpression>(value: argumentValue)
            }
            constructorCall = KotlinFunctionCall(function: initFunction, arguments: arguments)
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

        // Create a memberwise constructor for all properties that matches the minimum property visibility
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
        let parameters = prepareMemberwiseConstructorParameters(for: classDeclaration, variableDeclarations: variableDeclarations, translator: translator)
        constructor.parameters = parameters
        if constructor.modifiers.visibility == .private {
            // Differentiate the private constructor with an extra param so we can call it specifically
            constructor.parameters.append(Parameter(externalLabel: "privatep", declaredType: .named("Nothing", []).asOptional(true), defaultValue: KotlinNullLiteral()))
        }

        var bodyStatements: [KotlinStatement] = []
        bodyStatements += variableDeclarations.map { variableDeclaration in
            var assignment: String
            if variableDeclaration.attributes.stateAttribute != nil {
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
                let appStorageParameters = KotlinSwiftUITransformer.appStorageAdditionalInitParameters(for: variableDeclaration, codebaseInfo: translator.codebaseInfo)
                assignment = "this._\(variableDeclaration.propertyName) = skip.ui.AppStorage(wrappedValue = \(value), \(appStorageParameters))"
            } else if variableDeclaration.attributes.contains(.binding) {
                assignment = "this._\(variableDeclaration.propertyName) = \(variableDeclaration.propertyName)"
            } else if variableDeclaration.attributes.contains(.bindable) || variableDeclaration.attributes.contains(.observedObject) {
                assignment = "this._\(variableDeclaration.propertyName) = skip.ui.Bindable(\(variableDeclaration.propertyName))"
            } else if variableDeclaration.attributes.contains(.focusState) {
                var value = variableDeclaration.propertyName
                if variableDeclaration.mayBeSharedMutableStruct {
                    value += ".sref()"
                }
                assignment = "this._\(variableDeclaration.propertyName) = skip.ui.FocusState(\(value))"
            } else {
                if variableDeclaration.modifiers.isLazy {
                    assignment = "if (\(variableDeclaration.propertyName) != null) { this.\(variableDeclaration.propertyName) = \(variableDeclaration.propertyName)"
                } else if variableDeclaration.isTransformedToViewBuilderClosureParameter {
                    assignment = "this.\(variableDeclaration.propertyName) = \(variableDeclaration.propertyName)()"
                } else {
                    assignment = "this.\(variableDeclaration.propertyName) = \(variableDeclaration.propertyName)"
                }
                if !variableDeclaration.apiFlags.options.contains(.writeable) && variableDeclaration.mayBeSharedMutableStruct {
                    assignment += ".sref()"
                }
                if variableDeclaration.modifiers.isLazy {
                    assignment += " }"
                }
            }
            return KotlinRawStatement(sourceCode: assignment)
        }
        constructor.body = KotlinCodeBlock(statements: bodyStatements)
        constructor.parent = classDeclaration
        constructor.assignParentReferences()
        classDeclaration.members.append(constructor)

        // If we generated a private constructor, generate a non-private version that can be called by outside code
        if constructor.modifiers.visibility == .private {
            let constructor = KotlinFunctionDeclaration(name: "constructor")
            // Use public to omit any modifier on the generated code
            constructor.modifiers = Modifiers(visibility: .public)
            constructor.extras = .singleNewline
            constructor.isGenerated = true

            let nonPrivateParameters = zip(variableDeclarations, parameters)
                .filter { $0.0.modifiers.visibility != .private }
                .map(\.1)
            var parametersEqual = nonPrivateParameters.map {
                if let label = $0.externalLabel {
                    "\(label) = \(label)"
                } else {
                    $0.internalLabel
                }
            }.joined(separator: ", ")
            if !nonPrivateParameters.isEmpty {
                parametersEqual += ", "
            }
            parametersEqual += "privatep = null"

            constructor.parameters = nonPrivateParameters
            constructor.delegatingConstructorCall = KotlinRawExpression(sourceCode: "this(" + parametersEqual + ")")
            constructor.body = KotlinCodeBlock()
            constructor.parent = classDeclaration
            constructor.assignParentReferences()
            classDeclaration.members.append(constructor)
        }
    }

    private func prepareMemberwiseConstructorParameters(for classDeclaration: KotlinClassDeclaration, variableDeclarations: [KotlinVariableDeclaration], translator: KotlinTranslator) -> [Parameter<KotlinExpression>] {
        return variableDeclarations.map { variableDeclaration in
            let label = variableDeclaration.propertyName
            var type = variableDeclaration.propertyType
            if type == .none {
                if translator.codebaseInfo != nil {
                    variableDeclaration.messages.append(.kotlinConstructorCannotInferPropertyType(variableDeclaration, source: translator.syntaxTree.source))
                }
            } else if variableDeclaration.attributes.contains(.binding) {
                type = type.asBinding()
            } else if variableDeclaration.modifiers.isLazy {
                type = type.asOptional(true)
            } else if variableDeclaration.isTransformedToViewBuilderClosureParameter {
                type = .function([], variableDeclaration.propertyType, APIFlags(), nil)
                type = variableDeclaration.attributes.apply(toFunction: type)
            }
            let defaultValue: KotlinExpression?
            if let value = variableDeclaration.value {
                // Clear the default value if it will be assigned from the constructor to prevent creating the value twice.
                // We can't clear it, however, if we don't know what type to declare the variable
                defaultValue = KotlinSharedExpressionPointer(shared: value)
                if variableDeclaration.declaredType != .none || variableDeclaration.propertyType != .none {
                    variableDeclaration.value = nil
                    variableDeclaration.constructionValue = value
                    if variableDeclaration.declaredType == .none {
                        variableDeclaration.declaredType = variableDeclaration.propertyType
                    }
                }
            } else if type.isOptional {
                defaultValue = KotlinNullLiteral()
            } else {
                defaultValue = nil
            }
            return Parameter(externalLabel: label, declaredType: type, defaultValue: defaultValue)
        }
    }

    private func addMutableStructCopyConstructor(to classDeclaration: KotlinClassDeclaration, isOptionSet: Bool, variableDeclarations: [KotlinVariableDeclaration]) {
        // We use a parameter of type 'MutableStruct' to avoid conflicts with any user-defined constructor
        let constructor = KotlinFunctionDeclaration(name: "constructor")
        constructor.parameters = [Parameter(externalLabel: "copy", declaredType: .named("MutableStruct", []))]
        constructor.modifiers = Modifiers(visibility: .private)
        constructor.extras = .singleNewline
        constructor.isGenerated = true

        var bodyStatements: [KotlinStatement] = []
        let castStatement = KotlinRawStatement(sourceCode: "@Suppress(\"NAME_SHADOWING\", \"UNCHECKED_CAST\") val copy = copy as \(classDeclaration.signature.kotlin)")
        if isOptionSet {
            bodyStatements.append(castStatement)
            bodyStatements.append(KotlinRawStatement(sourceCode: "this.rawValue = copy.rawValue"))
        } else if !variableDeclarations.isEmpty {
            bodyStatements.append(castStatement)
            bodyStatements += variableDeclarations.map { variableDeclaration in
                if variableDeclaration.attributes.stateAttribute != nil {
                    return KotlinRawStatement(sourceCode: "this._\(variableDeclaration.propertyName) = skip.ui.State(copy.\(variableDeclaration.propertyName))")
                } else if variableDeclaration.attributes.contains(.appStorage) || variableDeclaration.attributes.contains(.binding) {
                    return KotlinRawStatement(sourceCode: "this._\(variableDeclaration.propertyName) = copy._\(variableDeclaration.propertyName)")
                } else if variableDeclaration.attributes.contains(.bindable) || variableDeclaration.attributes.contains(.observedObject) {
                    return KotlinRawStatement(sourceCode: "this._\(variableDeclaration.propertyName) = skip.ui.Bindable(copy.\(variableDeclaration.propertyName))")
                } else if variableDeclaration.attributes.contains(.focusState) {
                    return KotlinRawStatement(sourceCode: "this._\(variableDeclaration.propertyName) = skip.ui.FocusState(copy.\(variableDeclaration.propertyName))")
                } else {
                    // Clear the default value if it will be assigned from the constructor to prevent creating the value twice. The constructor
                    // transformer will then add these assignments to each constructor. So we only do this for 'let' values that other constructors
                    // will not already assign. We also can't clear the value if we don't know what type to declare the variable
                    if variableDeclaration.isLet, let value = variableDeclaration.value, variableDeclaration.declaredType != .none || variableDeclaration.propertyType != .none {
                        variableDeclaration.value = nil
                        variableDeclaration.constructionValue = value
                        if variableDeclaration.declaredType == .none {
                            variableDeclaration.declaredType = variableDeclaration.propertyType
                        }
                    }
                    var assignment = ""
                    if variableDeclaration.modifiers.isLazy {
                        assignment += "if (\(KotlinVariableStorage.isLazyInitialized(variableDeclaration, instance: "copy"))) { "
                    }
                    assignment += "this.\(variableDeclaration.propertyName) = copy.\(variableDeclaration.propertyName)"
                    if variableDeclaration.modifiers.isLazy {
                        assignment += " }"
                    }
                    return KotlinRawStatement(sourceCode: assignment)
                }
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
            guard classDeclaration.declarationType != .enumDeclaration else {
                binaryOperator.messages.append(.kotlinEnumSelfAssignment(binaryOperator, source: translator.syntaxTree.source))
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
            if variableDeclaration.attributes.stateAttribute != nil {
                return KotlinRawStatement(sourceCode: "this._\(variableDeclaration.propertyName) = skip.ui.State(\(copy).\(variableDeclaration.propertyName))")
            } else if variableDeclaration.attributes.contains(.appStorage) || variableDeclaration.attributes.contains(.binding) {
                return KotlinRawStatement(sourceCode: "this._\(variableDeclaration.propertyName) = \(copy)._\(variableDeclaration.propertyName)")
            } else if variableDeclaration.attributes.contains(.bindable) || variableDeclaration.attributes.contains(.observedObject) {
                return KotlinRawStatement(sourceCode: "this._\(variableDeclaration.propertyName) = skip.ui.Bindable(\(copy).\(variableDeclaration.propertyName))")
            } else if variableDeclaration.attributes.contains(.focusState) {
                return KotlinRawStatement(sourceCode: "this._\(variableDeclaration.propertyName) = skip.ui.FocusState(\(copy).\(variableDeclaration.propertyName))")
            } else {
                return KotlinRawStatement(sourceCode: "this.\(variableDeclaration.propertyName) = \(copy).\(variableDeclaration.propertyName)")
            }
        }
    }
}

extension KotlinVariableDeclaration {
    /// Whether this variable is transformed into a closure when made into a default constructor parameter.
    var isTransformedToViewBuilderClosureParameter: Bool {
        return !propertyType.isFunction && attributes.contains(.viewBuilder) && !apiFlags.options.contains(.computed)
    }
}
