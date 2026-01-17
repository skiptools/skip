// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

/// Update uses of `Task` and main actor information used in `async` calls.
final class KotlinConcurrencyTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        let codebaseInfo = translator.codebaseInfo
        var taskClosureIdentifiers: Set<ObjectIdentifier> = []
        syntaxTree.root.visit(ifSkipBlockContent: syntaxTree.isBridgeFile) { node in
            if let functionDeclaration = node as? KotlinFunctionDeclaration {
                if functionDeclaration.apiFlags.options.contains(.async) {
                    if let body = functionDeclaration.body {
                        updateNestingClosures(in: body)
                    }
                    // Async implementations change for main actor
                    if codebaseInfo?.isMainActor(declaration: functionDeclaration) == true {
                        functionDeclaration.apiFlags.options.insert(.mainActor)
                    }
                }
            } else if let variableDeclaration = node as? KotlinVariableDeclaration {
                if variableDeclaration.apiFlags.options.contains(.async) {
                    if variableDeclaration.isAsyncLet {
                        if let codeBlock = variableDeclaration.parent as? KotlinCodeBlock {
                            codeBlock.updateWithAsyncLet(declaration: variableDeclaration, source: translator.syntaxTree.source)
                        }
                    } else {
                        if let body = variableDeclaration.getter?.body {
                            updateNestingClosures(in: body)
                        }
                        // Async implementations change for main actor
                        if codebaseInfo?.isMainActor(declaration: variableDeclaration) == true {
                            variableDeclaration.apiFlags.options.insert(.mainActor)
                        }
                    }
                }
            } else if let closure = node as? KotlinClosure {
                if !taskClosureIdentifiers.contains(ObjectIdentifier(closure)) {
                    updateClosure(closure, codebaseInfo: codebaseInfo)
                }
                if closure.isNoDispatch || closure.apiFlags?.options.contains(.async) == true {
                    updateNestingClosures(in: closure.body)
                }
            } else if let functionCall = node as? KotlinFunctionCall {
                if let taskClosure = updateTaskCall(in: functionCall, codebaseInfo: codebaseInfo, source: translator.syntaxTree.source) {
                    taskClosureIdentifiers.insert(ObjectIdentifier(taskClosure))
                }
            }

            if let mainActorTargeting = node as? (KotlinSyntaxNode & KotlinMainActorTargeting) {
                updateMainActorTargeting(mainActorTargeting, codebaseInfo: codebaseInfo, source: translator.syntaxTree.source)
            }
            return .recurse(nil)
        }
        return []
    }

    private func updateTaskCall(in functionCall: KotlinFunctionCall, codebaseInfo: CodebaseInfo.Context?, source: Source) -> KotlinClosure? {
        if let identifier = functionCall.function as? KotlinIdentifier {
            if identifier.name == "Task", let closure = taskClosure(in: functionCall, source: source) {
                identifier.generics = updateTaskGenerics(identifier.generics)
                updateTaskConstructor(functionCall: functionCall, closure: closure, codebaseInfo: codebaseInfo)
                return closure
            }
        } else if let memberAccess = functionCall.function as? KotlinMemberAccess {
            if memberAccess.member == "Task" && (memberAccess.base as? KotlinIdentifier)?.name == "Swift" {
                memberAccess.generics = updateTaskGenerics(memberAccess.generics)
                if let closure = taskClosure(in: functionCall, source: source) {
                    updateTaskConstructor(functionCall: functionCall, closure: closure, codebaseInfo: codebaseInfo)
                    return closure
                }
            } else if memberAccess.member == "detached" && memberAccess.isBaseType(named: "Task", moduleName: "Swift") {
                if let baseIdentifier = memberAccess.base as? KotlinIdentifier {
                    baseIdentifier.generics = updateTaskGenerics(baseIdentifier.generics)
                } else if let baseMemberAccess = memberAccess.base as? KotlinMemberAccess {
                    baseMemberAccess.generics = updateTaskGenerics(baseMemberAccess.generics)
                }
                if let closure = taskClosure(in: functionCall, source: source) {
                    // Task.detached always launches with the default dispatcher. Only a closure with a specified actor needs to dispatch itself
                    if closure.apiFlags?.options.contains(.mainActor) != true {
                        closure.isNoDispatch = true
                    }
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
        closure.apiFlags?.options.insert(.async)
        return closure
    }

    private func updateTaskConstructor(functionCall: KotlinFunctionCall, closure: KotlinClosure, codebaseInfo: CodebaseInfo.Context?) {
        // The Task will launch a coroutine with the correct dispatcher based on the main actor argument we insert
        let isMainActorClosure = closure.apiFlags?.options.contains(.mainActor) == true || (codebaseInfo != nil && isInMainActorContext(node: functionCall, codebaseInfo: codebaseInfo!))
        if isMainActorClosure {
            closure.apiFlags?.options.insert(.mainActor)
            functionCall.arguments.insert(LabeledValue(label: "isMainActor", value: KotlinBooleanLiteral(literal: true)), at: 0)
        }
        // The closure itself does not need to specify a dispatch
        closure.isNoDispatch = true
    }

    private func updateClosure(_ closure: KotlinClosure, codebaseInfo: CodebaseInfo.Context?) {
        guard let codebaseInfo else {
            return
        }
        guard closure.apiFlags?.options.contains(.async) == true && closure.apiFlags?.options.contains(.mainActor) != true else {
            return
        }

        // Async closures inherit actor isolation when they're created. See if this one should be isolated
        if isInMainActorContext(node: closure, codebaseInfo: codebaseInfo) {
            closure.apiFlags?.options.insert(.mainActor)
        }
    }

    private func updateNestingClosures(in codeBlock: KotlinCodeBlock) {
        codeBlock.visit { node in
            if node is KotlinFunctionDeclaration || node is KotlinClosure {
                return .skip
            } else if let kif = node as? KotlinIf {
                if kif.nestingClosureFunction != nil {
                    kif.nestingClosureFunction = "linvokeSuspend"
                }
                return .recurse(nil)
            } else if let kwhen = node as? KotlinWhen {
                if kwhen.nestingClosureFunction != nil {
                    kwhen.nestingClosureFunction = "linvokeSuspend"
                }
                return .recurse(nil)
            } else {
                return .recurse(nil)
            }
        }
    }

    private func updateTaskGenerics(_ generics: [TypeSignature]?) -> [TypeSignature]? {
        guard let generics else {
            return nil
        }
        return generics.count == 2 ? [generics[0]] : generics
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
                return functionDeclaration.apiFlags.options.contains(.mainActor) || KotlinSwiftUITransformer.viewModifierForBody(functionDeclaration, codebaseInfo: codebaseInfo) != nil
            } else if let variableDeclaration = contextNode as? KotlinVariableDeclaration {
                return variableDeclaration.apiFlags.options.contains(.mainActor) || KotlinSwiftUITransformer.viewForBody(variableDeclaration, codebaseInfo: codebaseInfo) != nil
            } else if let closure = contextNode as? KotlinClosure, closure.apiFlags?.options.contains(.async) == true {
                return closure.apiFlags?.options.contains(.mainActor) == true
            }
        } while true
        return false
    }
}

extension KotlinConcurrencyTransformer: KotlinTypeSignatureOutputTransformer {
    static func outputSignature(for signature: TypeSignature) -> TypeSignature {
        if (signature.isNamed("Task", moduleName: "Swift") || signature.isNamed("ThrowingTaskGroup", moduleName: "Swift")) && signature.generics.count == 2 {
            return signature.withGenerics([signature.generics[0]])
        } else if signature.isNamed("ThrowingDiscardingTaskGroup", moduleName: "Swift") && signature.generics.count == 1 {
            return signature.withGenerics([])
        } else {
            return signature
        }
    }
}

extension CodebaseInfo.Context {
    fileprivate func isMainActor(declaration: KotlinFunctionDeclaration) -> Bool {
        if declaration.apiFlags.options.contains(.mainActor) {
            return true
        }
        let arguments = declaration.parameters.map { LabeledValue(label: $0.externalLabel, value: ArgumentValue(type: $0.declaredType)) }
        let matches: [APIMatch]
        if let owningType = owningType(of: declaration) {
            matches = matchFunction(name: declaration.name, inConstrained: owningType, arguments: arguments)
        } else {
            matches = matchFunction(name: declaration.name, arguments: arguments)
        }
        return matches.first?.apiFlags.options.contains(.mainActor) == true
    }

    fileprivate func isMainActor(declaration: KotlinVariableDeclaration) -> Bool {
        if declaration.apiFlags.options.contains(.mainActor) {
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
        return match?.apiFlags.options.contains(.mainActor) == true
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
