/// Adapts `@Observable` and `ObservableObject` types for use in Combine.
final class KotlinObservationTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        syntaxTree.root.visit { node in
            if let importDeclaration = node as? KotlinImportDeclaration {
                addObservationImportDependencies(statement: importDeclaration, in: syntaxTree)
            } else if let classDeclaration = node as? KotlinClassDeclaration {
                if classDeclaration.attributes.contains(.observable) {
                    addKotlinObservationDependencies(to: syntaxTree)
                    updateObservableClass(statement: classDeclaration, source: translator.syntaxTree.source)
                } else if classDeclaration.type == .classDeclaration {
                    if (handleObservableObject(statement: classDeclaration, translator: translator)) {
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

    private func updateObservableClass(statement: KotlinClassDeclaration, source: Source) {
        statement.annotations.append("@Stable")
        statement.inherits.append(.named("Observable", []))
        for member in statement.members {
            guard let variableDeclaration = member as? KotlinVariableDeclaration else {
                continue
            }
            if !variableDeclaration.isGenerated
                && !variableDeclaration.isStatic
                && !variableDeclaration.isLet
                && variableDeclaration.getter == nil
                && variableDeclaration.role != .superclassOverrideProperty
                && !variableDeclaration.attributes.contains(.observationIgnored) {
                makeObservable(statement: variableDeclaration, in: statement, source: source)
            }
            addManualObservationCallMessages(in: variableDeclaration, source: source)
        }
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
        } else if let codebaseInfo = translator.codebaseInfo {
            let inheritanceChain = codebaseInfo.global.inheritanceChainSignatures(forNamed: statement.signature)
            isObservableObjectBaseType = !inheritanceChain.isEmpty && lastObservableObjectType(in: inheritanceChain, codebaseInfo: codebaseInfo) == inheritanceChain.first
        }
        var hasPublishedProperties = false
        var hasObjectWillChangePublisher = false
        for member in statement.members {
            if let variableDeclaration = member as? KotlinVariableDeclaration {
                if variableDeclaration.attributes.contains(.published) {
                    makeObservable(statement: variableDeclaration, in: statement, isPublished: true, source: translator.syntaxTree.source)
                    hasPublishedProperties = true
                } else if variableDeclaration.propertyName == "objectWillChange" {
                    variableDeclaration.modifiers.visibility = .public
                    variableDeclaration.modifiers.isOverride = true
                    hasObjectWillChangePublisher = true
                }
            }
        }

        let isObservableObject = isObservableObjectBaseType || hasPublishedProperties
        if isObservableObject {
            statement.annotations.append("@Stable")
        }
        if isObservableObjectBaseType && !hasObjectWillChangePublisher {
            let objectWillChangeDeclaration = KotlinRawStatement(sourceCode: "override val objectWillChange = ObservableObjectPublisher()")
            statement.insert(statements: [objectWillChangeDeclaration], after: nil)
        }
        return isObservableObject
    }

    private func lastObservableObjectType(in types: [TypeSignature], codebaseInfo: CodebaseInfo.Context) -> TypeSignature? {
        for type in types.reversed() {
            if codebaseInfo.global.protocolSignatures(forNamed: type).contains(where: \.isObservableObject) {
                return type
            }
        }
        return nil
    }

    private func makeObservable(statement: KotlinVariableDeclaration, in classDeclaration: KotlinClassDeclaration, isPublished: Bool = false, source: Source) {
        let propertyType = statement.declaredType == .none ? statement.propertyType : statement.declaredType
        if propertyType == .none {
            statement.messages.append(.kotlinVariableNeedsTypeDeclaration(statement, source: source))
        }

        // Tell the observable variable to get and set its value using a state var. If we don't have an initial value,
        // we'll use a default or make the state var optional and force unwrap on get
        let storageName = "\(statement.propertyName)state"
        let storageDefaultValue = statement.propertyType.kotlinDefaultValue
        let isUnwrappedOptional = (statement.value == nil || statement.modifiers.isLazy) && storageDefaultValue == nil
        let storageType = isUnwrappedOptional ? propertyType.asOptional(true) : propertyType
        let modifierString = statement.modifiers.kotlinMemberString(isGlobal: false, isOpen: false, suffix: " ")
        var storage = KotlinVariableStorage(access: storageName, isUnwrappedOptional: isUnwrappedOptional) { variable, output, indentation in
            output.append(indentation).append(modifierString)
            output.append("var \(storageName)")
            if storageType != .none {
                output.append(": \(storageType.kotlin)")
            }
            output.append(" by mutableStateOf(")
            if let value = variable.value, !variable.modifiers.isLazy {
                output.append(value, indentation: indentation)
            } else if let storageDefaultValue {
                output.append(storageDefaultValue)
            } else {
                output.append("null")
            }
            output.append(")\n")
        }
        if isPublished {
            // Publish will change prior to setting storage
            let defaultStorageSet = storage.appendSet
            storage.appendSet = { variable, value, output, indentation in
                output.append(indentation).append("val storagevalue = ")
                value()
                output.append("\n")
                output.append(indentation).append("objectWillChange.send()\n")
                output.append(indentation).append("_").append(variable.propertyName).append(".projectedValue.send(storagevalue)\n")
                defaultStorageSet(variable, { output.append("storagevalue") }, output, indentation)
            }

            // Add publisher "property wrapper"
            let publishedInitalValue = isUnwrappedOptional ? "" : storageName
            let publishedDeclaration = KotlinRawStatement(sourceCode: "\(modifierString)val _\(statement.propertyName) = Published<\(propertyType.kotlin)>(\(publishedInitalValue))")
            classDeclaration.insert(statements: [publishedDeclaration], after: statement)
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
        syntaxTree.dependencies.imports.insert("androidx.compose.runtime.getValue")
        syntaxTree.dependencies.imports.insert("androidx.compose.runtime.mutableStateOf")
        syntaxTree.dependencies.imports.insert("androidx.compose.runtime.setValue")
        syntaxTree.dependencies.imports.insert("androidx.compose.runtime.Stable")
    }
}

extension TypeSignature {
    fileprivate var isObservableObject: Bool {
        return isNamed("ObservableObject", moduleName: "Combine") || isNamed("ObservableObject", moduleName: "SwiftUI")
    }
}
