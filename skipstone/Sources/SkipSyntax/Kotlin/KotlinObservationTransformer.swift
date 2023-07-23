/// Adapts `@Observable` and `ObservableObject` types for use in Combine.
final class KotlinObservationTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        syntaxTree.root.visit { node in
            if let importDeclaration = node as? KotlinImportDeclaration {
                mapObservationImport(statement: importDeclaration, in: syntaxTree)
            } else if let classDeclaration = node as? KotlinClassDeclaration {
                if classDeclaration.attributes.contains(.observable) {
                    updateObservableClass(statement: classDeclaration, source: translator.syntaxTree.source)
                } else if classDeclaration.type == .classDeclaration {
                    updatePublishedProperties(in: classDeclaration, source: translator.syntaxTree.source)
                }
            }
            return .recurse(nil)
        }
    }

    private func mapObservationImport(statement: KotlinImportDeclaration, in syntaxTree: KotlinSyntaxTree) {
        guard statement.modulePath.first == "Combine" || statement.modulePath.first == "Observation" || statement.modulePath.first == "SwiftUI" else {
            return
        }
        (statement.parent as? KotlinStatement)?.remove(statement: statement)
        syntaxTree.dependencies.imports.insert("androidx.compose.runtime.*")
    }

    private func updateObservableClass(statement: KotlinClassDeclaration, source: Source) {
        statement.annotations.append("@Stable")
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

    private func updatePublishedProperties(in statement: KotlinClassDeclaration, source: Source) {
        if let observableObjectIndex = statement.inherits.firstIndex(where: { $0.isNamed("ObservableObject", moduleName: "Combine") }) {
            statement.inherits.remove(at: observableObjectIndex)
            statement.annotations.append("@Stable")
        }
        for member in statement.members {
            if let variableDeclaration = member as? KotlinVariableDeclaration, variableDeclaration.attributes.contains(.published) {
                makeObservable(statement: variableDeclaration, in: statement, isPublished: true, source: source)
                if !statement.annotations.contains("@Stable") {
                    statement.annotations.append("@Stable")
                }
            }
        }
    }

    private func makeObservable(statement: KotlinVariableDeclaration, in classDeclaration: KotlinClassDeclaration, isPublished: Bool = false, source: Source) {
        let propertyType = statement.declaredType == .none ? statement.propertyType : statement.declaredType
        if propertyType == .none {
            statement.messages.append(.kotlinVariableNeedsTypeDeclaration(statement, source: source))
        }

        // Tell the observable variable to get and set its value using a state var. If we don't have an initial value,
        // we'll make the state var optional and force unwrap on get
        let storageName = "\(statement.propertyName)state"
        let isUnwrappedOptional = (statement.value == nil || statement.modifiers.isLazy) && !statement.propertyType.isOptional
        let storageType = isUnwrappedOptional ? propertyType.asOptional(true) : propertyType
        statement.storageVariable = KotlinStorageVariable(name: storageName, isUnwrappedOptional: isUnwrappedOptional) { variable, output, indentation in
            output.append(indentation).append(variable.modifiers.kotlinMemberString(isGlobal: false, isOpen: false, suffix: " "))
            output.append("var \(storageName)")
            if storageType != .none {
                output.append(": \(storageType.kotlin)")
            }
            output.append(" by mutableStateOf(")
            if let value = variable.value, !variable.modifiers.isLazy {
                output.append(value, indentation: indentation)
            } else {
                output.append("null")
            }
            output.append(")\n")
        }
    }
}
