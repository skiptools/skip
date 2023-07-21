/// Update uses of `Task` and main actor information used in `async` calls.
final class KotlinConcurrencyTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        let codebaseInfo = translator.codebaseInfo
        var taskClosureIdentifiers: Set<ObjectIdentifier> = []
        syntaxTree.root.visit { node in
            if let functionDeclaration = node as? KotlinFunctionDeclaration {
                // Async implementations change for main actor
                if functionDeclaration.apiFlags.contains(.async) && codebaseInfo?.isMainActor(declaration: functionDeclaration) == true {
                    functionDeclaration.apiFlags.insert(.mainActor)
                }
            } else if let variableDeclaration = node as? KotlinVariableDeclaration {
                // Async implementations change for main actor
                if variableDeclaration.apiFlags.contains(.async) {
                    if variableDeclaration.isAsyncLet {
                        if let codeBlock = variableDeclaration.parent as? KotlinCodeBlock {
                            codeBlock.updateWithAsyncLet(declaration: variableDeclaration, source: translator.syntaxTree.source)
                        }
                    } else if codebaseInfo?.isMainActor(declaration: variableDeclaration) == true {
                        variableDeclaration.apiFlags.insert(.mainActor)
                    }
                }
            } else if let closure = node as? KotlinClosure {
                if !taskClosureIdentifiers.contains(ObjectIdentifier(closure)) {
                    updateClosure(closure, codebaseInfo: codebaseInfo)
                }
            } else if let functionCall = node as? KotlinFunctionCall {
                if let taskClosure = updateTaskClosure(in: functionCall, codebaseInfo: codebaseInfo, source: translator.syntaxTree.source) {
                    taskClosureIdentifiers.insert(ObjectIdentifier(taskClosure))
                }
            }

            if let mainActorTargeting = node as? (KotlinSyntaxNode & KotlinMainActorTargeting) {
                updateMainActorTargeting(mainActorTargeting, codebaseInfo: codebaseInfo, source: translator.syntaxTree.source)
            }
            return .recurse(nil)
        }
    }

    private func updateTaskClosure(in functionCall: KotlinFunctionCall, codebaseInfo: CodebaseInfo.Context?, source: Source) -> KotlinClosure? {
        if let identifier = functionCall.function as? KotlinIdentifier {
            if identifier.name == "Task", let closure = taskClosure(in: functionCall, source: source) {
                updateTaskConstructor(functionCall: functionCall, closure: closure, codebaseInfo: codebaseInfo)
                return closure
            }
        } else if let memberAccess = functionCall.function as? KotlinMemberAccess {
            if memberAccess.member == "Task" && (memberAccess.base as? KotlinIdentifier)?.name == "Swift" {
                if let closure = taskClosure(in: functionCall, source: source) {
                    updateTaskConstructor(functionCall: functionCall, closure: closure, codebaseInfo: codebaseInfo)
                    return closure
                }
            } else if memberAccess.member == "detached" && memberAccess.isBaseType(named: "Task", moduleName: "Swift") {
                if let closure = taskClosure(in: functionCall, source: source) {
                    // Task.detached always launches with the default dispatcher. Only a closure with a specified actor needs to dispatch itself
                    if closure.apiFlags?.contains(.mainActor) != true {
                        closure.isTaskClosure = true
                    }
                    return closure
                }
            } else if memberAccess.member == "run" && memberAccess.isBaseType(named: "MainActor", moduleName: "Swift") {
                if let closure = taskClosure(in: functionCall, source: source) {
                    // MainActor.run always uses the main dispatcher. The closure does not have to dispatch itself.
                    // NOTE: Should MainActor.run also mark the closure as .mainActor for actor inheritance within its body?
                    closure.isTaskClosure = true
                    return closure
                }
            }
        }
        return nil
    }

    private func taskClosure(in functionCall: KotlinFunctionCall, source: Source) -> KotlinClosure? {
        // Closure is always the last argument
        guard let lastArgument = functionCall.arguments.last?.value else {
            return nil
        }
        guard let closure = lastArgument as? KotlinClosure else {
            functionCall.messages.append(.kotlinAsyncTaskClosureInline(functionCall, source: source))
            return nil
        }
        closure.apiFlags?.insert(.async)
        return closure
    }

    private func updateTaskConstructor(functionCall: KotlinFunctionCall, closure: KotlinClosure, codebaseInfo: CodebaseInfo.Context?) {
        // The Task will launch a coroutine with the correct dispatcher based on the main actor argument we insert
        let isMainActorClosure = closure.apiFlags?.contains(.mainActor) == true || (codebaseInfo != nil && isInMainActorContext(node: functionCall, codebaseInfo: codebaseInfo!))
        if isMainActorClosure {
            closure.apiFlags?.insert(.mainActor)
            functionCall.arguments.insert(LabeledValue(label: "isMainActor", value: KotlinBooleanLiteral(literal: true)), at: 0)
        }
        // The closure itself does not need to specify a dispatch
        closure.isTaskClosure = true
    }

    private func updateClosure(_ closure: KotlinClosure, codebaseInfo: CodebaseInfo.Context?) {
        guard let codebaseInfo else {
            return
        }
        guard closure.apiFlags?.contains(.async) == true && closure.apiFlags?.contains(.mainActor) != true else {
            return
        }

        // Async closures inherit actor isolation when they're created. See if this one should be isolated
        if isInMainActorContext(node: closure, codebaseInfo: codebaseInfo) {
            closure.apiFlags?.insert(.mainActor)
        }
    }

    private func updateMainActorTargeting(_ mainActorTargeting: KotlinSyntaxNode & KotlinMainActorTargeting, codebaseInfo: CodebaseInfo.Context?, source: Source) {
        guard let codebaseInfo else {
            return
        }
        guard mainActorTargeting.isInAwait && !mainActorTargeting.isInMainActorContext else {
            return
        }
        guard let needsMainActorIsolation = mainActorTargeting.needsMainActorIsolation else {
            mainActorTargeting.messages.append(.kotlinAsyncAwaitTypeInference(mainActorTargeting, source: source))
            return
        }
        guard needsMainActorIsolation else {
            return
        }

        var mainActorTargeting = mainActorTargeting
        if isInMainActorContext(node: mainActorTargeting, codebaseInfo: codebaseInfo) {
            mainActorTargeting.isInMainActorContext = true
        }
    }

    private func isInMainActorContext(node: KotlinSyntaxNode, codebaseInfo: CodebaseInfo.Context) -> Bool {
        // Traverse up from the given node to determine if it is in a main actor context
        var contextNode: KotlinSyntaxNode? = node
        repeat {
            contextNode = contextNode?.parent
            guard let contextNode else {
                break
            }
            if let functionDeclaration = contextNode as? KotlinFunctionDeclaration {
                return functionDeclaration.apiFlags.contains(.mainActor)
            } else if let variableDeclaration = contextNode as? KotlinVariableDeclaration {
                return variableDeclaration.apiFlags.contains(.mainActor)
            } else if let closure = contextNode as? KotlinClosure, closure.apiFlags?.contains(.async) == true {
                return closure.apiFlags?.contains(.mainActor) == true
            }
        } while true
        return false
    }
}

extension KotlinConcurrencyTransformer: KotlinTypeSignatureOutputTransformer {
    static func outputSignature(for signature: TypeSignature) -> TypeSignature {
        if signature.isNamed("Task", moduleName: "Swift") && signature.generics.count == 2 {
            return signature.withGenerics([signature.generics[0]])
        } else {
            return signature
        }
    }
}

extension CodebaseInfo.Context {
    fileprivate func isMainActor(declaration: KotlinFunctionDeclaration) -> Bool {
        if declaration.apiFlags.contains(.mainActor) {
            return true
        }
        let arguments = declaration.parameters.map { LabeledValue(label: $0.externalLabel, value: $0.declaredType) }
        let matches: [APIMatch]
        if let owningType = owningType(of: declaration) {
            matches = matchFunction(name: declaration.name, inConstrained: owningType, arguments: arguments)
        } else {
            matches = matchFunction(name: declaration.name, arguments: arguments)
        }
        return matches.first?.apiFlags.contains(.mainActor) == true
    }

    fileprivate func isMainActor(declaration: KotlinVariableDeclaration) -> Bool {
        if declaration.apiFlags.contains(.mainActor) {
            return true
        }
        let match: APIMatch?
        if declaration.role.isProperty, let owningType = owningType(of: declaration) {
            match = matchIdentifier(name: declaration.propertyName, inConstrained: owningType)
        } else if declaration.role == .global {
            match = matchIdentifier(name: declaration.propertyName)
        } else {
            match = nil
        }
        return match?.apiFlags.contains(.mainActor) == true
    }

    private func owningType(of declaration: KotlinStatement) -> TypeSignature? {
        if let classDeclaration = declaration.parent as? KotlinClassDeclaration {
            return primaryTypeInfo(forNamed: classDeclaration.signature)?.signature
        } else if let interfaceDeclaration = declaration.parent as? KotlinInterfaceDeclaration {
            return primaryTypeInfo(forNamed: interfaceDeclaration.signature)?.signature
        } else if let memberDeclaration = declaration as? KotlinMemberDeclaration {
            return memberDeclaration.extends?.0
        } else {
            return nil
        }
    }
}

extension KotlinMemberAccess {
    fileprivate func isBaseType(named: String, moduleName: String) -> Bool {
        guard baseType == .none else {
            return baseType.isNamed(named, moduleName: moduleName)
        }

        // Try to work even without codebase info
        if let identifier = base as? KotlinIdentifier {
            return identifier.name == named
        } else if let memberAccess = base as? KotlinMemberAccess {
            return memberAccess.member == named && (memberAccess.base as? KotlinIdentifier)?.name == moduleName
        } else {
            return false
        }
    }
}
