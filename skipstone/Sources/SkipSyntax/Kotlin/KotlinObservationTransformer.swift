/// Adapts `@Observable` and `ObservableObject` types for use in Combine and SwiftUI.
final class KotlinObservationTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        syntaxTree.root.visit { node in
            if let importDeclaration = node as? KotlinImportDeclaration {
                addObservationImportDependencies(statement: importDeclaration, in: syntaxTree)
            } else if let classDeclaration = node as? KotlinClassDeclaration {
                if classDeclaration.attributes.contains(.observable) {
                    addKotlinObservationDependencies(to: syntaxTree)
                    updateObservableClass(statement: classDeclaration, translator: translator)
                } else if classDeclaration.type == .classDeclaration {
                    if handleObservableObject(statement: classDeclaration, translator: translator) {
                        addKotlinObservationDependencies(to: syntaxTree)
                    }
                }
            } else if let functionCall = node as? KotlinFunctionCall {
                updateAssignTo(expression: functionCall)
            }
            return .recurse(nil)
        }
    }

    private func addObservationImportDependencies(statement: KotlinImportDeclaration, in syntaxTree: KotlinSyntaxTree) {
        guard statement.modulePath.first == "Combine" || statement.modulePath.first == "Observation" else {
            return
        }
        addKotlinObservationDependencies(to: syntaxTree)
    }

    private func updateObservableClass(statement: KotlinClassDeclaration, translator: KotlinTranslator) {
        statement.annotations.append("@Stable")
        statement.inherits.append(.named("Observable", []))
        
        let observableVariables = statement.members.compactMap { (member: KotlinStatement) -> KotlinVariableDeclaration? in
            guard let variableDeclaration = member as? KotlinVariableDeclaration else {
                return nil
            }
            guard !variableDeclaration.isGenerated
                && !variableDeclaration.isStatic
                && !variableDeclaration.isLet
                && variableDeclaration.getter == nil
                && variableDeclaration.role != .superclassOverrideProperty
                && !variableDeclaration.attributes.contains(.observationIgnored) else {
                return nil
            }
            return variableDeclaration
        }
        for observableVariable in observableVariables {
            makeObservable(statement: observableVariable, in: statement, source: translator.syntaxTree.source)
            addManualObservationCallMessages(in: observableVariable, source: translator.syntaxTree.source)
        }
        updateObservableVariableInitializations(in: statement, for: observableVariables)
    }

    private func updateObservableVariableInitializations(in statement: KotlinClassDeclaration, for variables: [KotlinVariableDeclaration], isPublished: Bool = false) {
        statement.members
            .compactMap { $0 as? KotlinFunctionDeclaration }
            .filter { $0.type == .constructorDeclaration }
            .forEach { updateObservableVariableInitializations(in: $0, for: variables, isPublished: isPublished) }
    }

    private func updateObservableVariableInitializations(in constructor: KotlinFunctionDeclaration, for variables: [KotlinVariableDeclaration], isPublished: Bool) {
        // Translate any assignment to an observable var into an assignment to its property wrapper
        constructor.body?.visit { node in
            if node is KotlinClosure {
                return .skip
            } else if node is KotlinFunctionDeclaration {
                return .skip
            } else if let binaryOperator = node as? KotlinBinaryOperator, binaryOperator.op.symbol == "=", let propertyWrapper = propertyWrapper(for: binaryOperator.lhs, in: variables, isPublished: isPublished) {
                binaryOperator.lhs = KotlinMemberAccess(base: KotlinIdentifier(name: "self"), member: propertyWrapper.name)
                binaryOperator.rhs = KotlinFunctionCall(function: KotlinIdentifier(name: propertyWrapper.propertyWrapperTypeName), arguments: [LabeledValue(label: nil, value: binaryOperator.rhs)])
                binaryOperator.assignParentReferences()
                return .skip
            } else {
                return .recurse(nil)
            }
        }
    }

    private func propertyWrapper(for expression: KotlinExpression, in variables: [KotlinVariableDeclaration], isPublished: Bool) -> (name: String, propertyWrapperTypeName: String)? {
        var variableName: String? = nil
        if let identifier = expression as? KotlinIdentifier {
            variableName = identifier.name
        } else if let memberAccess = expression as? KotlinMemberAccess, (memberAccess.base as? KotlinIdentifier)?.name == "self" {
            variableName = memberAccess.member
        }
        guard let variableName else {
            return nil
        }
        for variable in variables {
            if variable.propertyName == variableName {
                return ("_" + variableName, isPublished ? "skip.model.Published" : "skip.model.Observed")
            }
        }
        return nil
    }

    private func addManualObservationCallMessages(in variableDeclaration: KotlinVariableDeclaration, source: Source) {
        variableDeclaration.getter?.body?.visit { node in
            if let functionCall = node as? KotlinFunctionCall {
                if functionCall.arguments.count == 1 && functionCall.arguments[0].label == "keyPath" && isFunction(functionCall.function, observationCallTo: "access") {
                    functionCall.messages.append(.kotlinObservationManualTrigger(functionCall, source: source))
                    return .skip
                }
            }
            return .recurse(nil)
        }
        variableDeclaration.setter?.body?.visit { node in
            if let functionCall = node as? KotlinFunctionCall {
                if functionCall.arguments.count == 2 && functionCall.arguments[0].label == "keyPath" && functionCall.arguments[1].label == nil && isFunction(functionCall.function, observationCallTo: "withMutation") {
                    functionCall.messages.append(.kotlinObservationManualTrigger(functionCall, source: source))
                    return .skip
                }
            }
            return .recurse(nil)
        }
    }

    private func isFunction(_ function: KotlinExpression, observationCallTo name: String) -> Bool {
        if let identifier = function as? KotlinIdentifier {
            return identifier.name == name
        } else if let memberAccess = function as? KotlinMemberAccess {
            return memberAccess.member == name
        } else {
            return false
        }
    }

    private func handleObservableObject(statement: KotlinClassDeclaration, translator: KotlinTranslator) -> Bool {
        var isObservableObjectBaseType = false
        if let observableObjectIndex = statement.inherits.firstIndex(where: \.isObservableObject) {
            // Remove any package specification
            statement.inherits[observableObjectIndex] = .named("ObservableObject", [])
            isObservableObjectBaseType = true
        } else if let codebaseInfo = translator.codebaseInfo?.global {
            let observableObjectIndex = codebaseInfo.inheritanceChainSignatures(forNamed: statement.signature)
                .lastIndex { codebaseInfo.protocolSignatures(forNamed: $0).contains(where: \.isObservableObject) }
            isObservableObjectBaseType = observableObjectIndex == 0
        }
        var publishedVariables: [KotlinVariableDeclaration] = []
        var hasObjectWillChangePublisher = false
        for member in statement.members {
            guard let variableDeclaration = member as? KotlinVariableDeclaration else {
                continue
            }
            if variableDeclaration.attributes.contains(.published) {
                publishedVariables.append(variableDeclaration)
            } else if variableDeclaration.propertyName == "objectWillChange" {
                variableDeclaration.modifiers.visibility = .public
                variableDeclaration.modifiers.isOverride = true
                hasObjectWillChangePublisher = true
            }
        }
        guard isObservableObjectBaseType || !publishedVariables.isEmpty else {
            return false
        }

        statement.annotations.append("@Stable")
        if isObservableObjectBaseType && !hasObjectWillChangePublisher {
            let objectWillChangeDeclaration = KotlinRawStatement(sourceCode: "override val objectWillChange = ObservableObjectPublisher()")
            statement.insert(statements: [objectWillChangeDeclaration], after: nil)
        }
        publishedVariables.forEach { makeObservable(statement: $0, in: statement, isPublished: true, source: translator.syntaxTree.source) }
        updateObservableVariableInitializations(in: statement, for: publishedVariables, isPublished: true)
        return true
    }

    private func makeObservable(statement: KotlinVariableDeclaration, in classDeclaration: KotlinClassDeclaration, isPublished: Bool = false, source: Source) {
        let propertyType = statement.declaredType == .none ? statement.propertyType : statement.declaredType
        if propertyType == .none {
            statement.messages.append(.kotlinVariableNeedsTypeDeclaration(statement, source: source))
        }

        // Tell the observable variable to get and set its value using _variable of type Observed/Published
        let storageName = "_\(statement.propertyName)"
        var storage = KotlinVariableStorage()
        storage.isSingleStatementAppendable = { _ in true }
        storage.appendGet = { variable, sref, isSingleStatement, output, indentation in
            if !isSingleStatement {
                output.append(indentation).append("return ")
            }
            output.append(storageName).append(".wrappedValue")
            sref()
            output.append("\n")
        }
        storage.appendSet = { variable, value, output, indentation in
            output.append(indentation).append(storageName).append(".wrappedValue = ")
            value()
            output.append("\n")
        }
        let propertyWrapperTypeName = isPublished ? "skip.model.Published" : "skip.model.Observed"
        storage.appendStorage = { variable, output, indentation in
            let stateType = propertyType.asPropertyWrapper(propertyWrapperTypeName).kotlin
            output.append(indentation).append(variable.modifiers.kotlinMemberString(isGlobal: false, isOpen: false, suffix: " ")).append("var ").append(storageName).append(": ").append(stateType)
            if let value = variable.value {
                output.append(" = \(propertyWrapperTypeName)(")
                value.append(to: output, indentation: indentation)
                output.append(")")
            } else if propertyType.isOptional {
                output.append(" = \(propertyWrapperTypeName)(null)")
            }
            output.append("\n")
        }
        if isPublished {
            // Publish will change prior to setting storage
            let defaultStorageSet = storage.appendSet
            storage.appendSet = { variable, value, output, indentation in
                output.append(indentation).append("objectWillChange.send()\n")
                defaultStorageSet(variable, value, output, indentation)
            }
        }
        statement.storage = storage
    }

    private func updateAssignTo(expression: KotlinFunctionCall) {
        // Support Publisher.assign(to: \.property, on: object)
        guard expression.arguments.count == 2, expression.arguments[0].label == "to", expression.arguments[1].label == "on" else {
            return
        }
        guard let function = expression.function as? KotlinMemberAccess, function.member == "assign" else {
            return
        }
        if let keyPath = expression.arguments[0].value as? KotlinKeyPathLiteral {
            keyPath.isWrite = true
        }
    }

    private func addKotlinObservationDependencies(to syntaxTree: KotlinSyntaxTree) {
        syntaxTree.dependencies.imports.insert("androidx.compose.runtime.mutableStateOf")
        syntaxTree.dependencies.imports.insert("androidx.compose.runtime.Stable")
    }
}

extension TypeSignature {
    fileprivate var isObservableObject: Bool {
        return isNamed("ObservableObject", moduleName: "Combine") || isNamed("ObservableObject", moduleName: "SwiftUI")
    }
}
