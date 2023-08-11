/// Translate SwiftUI to syntactically correct Kotlin.
///
/// We rely on our UI libraries to provide the implementation of the SwiftUI-like API that this translation will result in.
final class KotlinSwiftUITransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        // We need codebase info to issue any warnings, so no point in processing the code without it
        guard translator.codebaseInfo != nil else {
            return
        }
        
        // Does this file need translation?
        var needsTranslation = false
        if translator.packageName == "skip.ui" {
            // We need to be able to transpile the views within our own SkipUI package
            needsTranslation = true
        } else {
            for importDeclaration in syntaxTree.root.statements.compactMap({ $0 as? KotlinImportDeclaration }) {
                if importDeclaration.modulePath.first == "SwiftUI" || importDeclaration.modulePath.first == "SkipUI" {
                    needsTranslation = true
                    break
                }
            }
        }
        if needsTranslation {
            syntaxTree.root.visit { visit($0, translator: translator) }
        }
    }
    
    private func visit(_ node: KotlinSyntaxNode, translator: KotlinTranslator) -> VisitResult<KotlinSyntaxNode> {
        if let functionDeclaration = node as? KotlinFunctionDeclaration {
            translateFunctionDeclaration(functionDeclaration, translator: translator)
        } else if let variableDeclaration = node as? KotlinVariableDeclaration {
            translateVariableDeclaration(variableDeclaration, translator: translator)
        } else if let closure = node as? KotlinClosure {
            translateClosure(closure, translator: translator)
        } else if let functionCall = node as? KotlinFunctionCall {
            translateFunctionCallParameters(functionCall, translator: translator)
        }
        return .recurse(nil)
    }
    
    private func translateFunctionDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, translator: KotlinTranslator) {
        guard functionDeclaration.apiFlags.contains(.viewBuilder) else {
            return
        }
        if let body = functionDeclaration.body {
            functionDeclaration.body = translateViewBuilder(codeBlock: body, translator: translator)
            functionDeclaration.body?.parent = functionDeclaration
        }
    }
    
    private func translateClosure(_ closure: KotlinClosure, translator: KotlinTranslator) {
        guard closure.apiFlags?.contains(.viewBuilder) == true else {
            return
        }
        closure.body = translateViewBuilder(codeBlock: closure.body, fromClosure: closure, translator: translator)
        closure.body.parent = closure
    }
    
    private func translateFunctionCallParameters(_ functionCall: KotlinFunctionCall, translator: KotlinTranslator) {
        // Look for closures passed as ViewBuilder arguments to function calls
        guard case .function(let parameterTypes, _, _) = functionCall.apiMatch?.signature, parameterTypes.count == functionCall.arguments.count else {
            return
        }
        for i in 0..<parameterTypes.count {
            guard case .function(_, _, let apiFlags) = parameterTypes[i].type, apiFlags.contains(.viewBuilder), let closure = functionCall.arguments[i].value as? KotlinClosure else {
                continue
            }
            // If the closure is marked as a ViewBuilder, we'll already process it
            guard closure.apiFlags?.contains(.viewBuilder) != true else {
                continue
            }
            closure.body = translateViewBuilder(codeBlock: closure.body, fromClosure: closure, translator: translator)
            closure.body.parent = closure
        }
    }
    
    private func translateVariableDeclaration(_ statement: KotlinVariableDeclaration, translator: KotlinTranslator) {
        var viewBuilder: KotlinCodeBlock? = nil
        if let viewDeclaration = viewForBody(statement, codebaseInfo: translator.codebaseInfo) {
            transform(view: viewDeclaration, body: statement)
            viewBuilder = statement.getter?.body
        } else if statement.apiFlags.contains(.viewBuilder) {
            viewBuilder = statement.getter?.body
        }
        if let viewBuilder {
            statement.getter?.body = translateViewBuilder(codeBlock: viewBuilder, translator: translator)
            statement.getter?.body?.parent = statement
        }
    }
    
    private func viewForBody(_ variableDeclaration: KotlinVariableDeclaration, codebaseInfo: CodebaseInfo.Context?) -> KotlinClassDeclaration? {
        guard variableDeclaration.role == .property, variableDeclaration.propertyName == "body", !variableDeclaration.isStatic, let classDeclaration = variableDeclaration.parent as? KotlinClassDeclaration else {
            return nil
        }
        guard classDeclaration.inherits.contains(where: { $0.isNamed("View", moduleName: "SwiftUI") }) || isView(type: classDeclaration.signature, codebaseInfo: codebaseInfo) else {
            return nil
        }
        return classDeclaration
    }
    
    private func transform(view: KotlinClassDeclaration, body: KotlinVariableDeclaration) {
        body.apiFlags.insert(.viewBuilder)
        
        let variableDeclarations = view.members.compactMap { $0 as? KotlinVariableDeclaration }
        let stateVariables = variableDeclarations.filter { $0.attributes.contains(.state) || $0.attributes.contains(.stateObject) }
        let environmentVariables = variableDeclarations.filter { $0.attributes.contains(.environment) || $0.attributes.contains(.environmentObject) }
        if !stateVariables.isEmpty || !environmentVariables.isEmpty {
            let composeFunction = synthesizeComposeFunction(view: view, stateVariables: stateVariables, environmentVariables: environmentVariables)
            view.insert(statements: [composeFunction], after: body)
            
            for stateVariable in stateVariables {
                synthesizeStateObservation(variable: stateVariable, in: view)
            }
        }
    }
    
    private func synthesizeComposeFunction(view: KotlinClassDeclaration, stateVariables: [KotlinVariableDeclaration], environmentVariables: [KotlinVariableDeclaration]) -> KotlinStatement {
        let composeFunction = KotlinFunctionDeclaration(name: "Compose")
        composeFunction.modifiers.visibility = .public
        composeFunction.modifiers.isOverride = true
        composeFunction.annotations.append("@Composable")
        composeFunction.parameters.append(Parameter(externalLabel: "composectx", declaredType: .named("ComposeContext", [])))
        composeFunction.extras = .singleNewline

        var composeBodyStatements: [KotlinStatement] = []
        for stateVariable in stateVariables {
            let statements = synthesizeStateSync(variable: stateVariable)
            if !composeBodyStatements.isEmpty {
                statements[0].extras = .singleNewline
            }
            composeBodyStatements += statements
        }
        for environmentVariable in environmentVariables {
            let statements = synthesizeEnvironmentSync(variable: environmentVariable)
            if !composeBodyStatements.isEmpty {
                statements[0].extras = .singleNewline
            }
            composeBodyStatements += statements
        }

        let statement = KotlinRawStatement(sourceCode: "body().Compose(composectx)")
        statement.extras = .singleNewline
        composeBodyStatements.append(statement)

        let body = KotlinCodeBlock(statements: composeBodyStatements)
        composeFunction.body = body
        
        composeFunction.assignParentReferences()
        return composeFunction
    }
    
    private func synthesizeStateSync(variable: KotlinVariableDeclaration) -> [KotlinStatement] {
        let nullDidChange = KotlinRawStatement(sourceCode: "\(variable.stateDidChangePropertyName) = null")
        let initialValue = KotlinRawStatement(sourceCode: "val initial\(variable.propertyName) = \(variable.propertyName)")
        let composeValue = KotlinRawStatement(sourceCode: "var compose\(variable.propertyName) by remember { mutableStateOf(initial\(variable.propertyName)) }")
        let syncValue = KotlinRawStatement(sourceCode: "\(variable.propertyName) = initial\(variable.propertyName)")
        let setDidChange = KotlinRawStatement(sourceCode: "\(variable.stateDidChangePropertyName) = { compose\(variable.propertyName) = \(variable.propertyName) }")
        return [nullDidChange, initialValue, composeValue, syncValue, setDidChange]
    }
    
    private func synthesizeEnvironmentSync(variable: KotlinVariableDeclaration) -> [KotlinStatement] {
        return [] //~~~
    }

    private func synthesizeStateObservation(variable: KotlinVariableDeclaration, in view: KotlinClassDeclaration) {
        let didChangeType: TypeSignature = .function([], .void, []).asOptional(true)
        let didChangeProperty = KotlinVariableDeclaration(names: [variable.stateDidChangePropertyName], variableTypes: [didChangeType])
        didChangeProperty.declaredType = didChangeType
        didChangeProperty.role = .property
        didChangeProperty.modifiers.visibility = .private
        didChangeProperty.apiFlags = [.writeable]
        didChangeProperty.isGenerated = true
        view.insert(statements: [didChangeProperty], after: variable)

        variable.setterSideEffects.append(KotlinRawStatement(sourceCode: "\(variable.stateDidChangePropertyName)?.invoke()"))
    }

    private func translateViewBuilder(codeBlock: KotlinCodeBlock, fromClosure closure: KotlinClosure? = nil, translator: KotlinTranslator) -> KotlinCodeBlock {
        // Add tail calls to compose the views that SwiftUI would build into a TupleView
        codeBlock.visit { node in
            if node is KotlinFunctionDeclaration || node is KotlinClosure {
                // These do not inherit our view builder context and will get processed by the top-level visitation code
                return .skip
            } else if let apiCall = node as? APICallExpression, let expressionStatement = node.parent as? KotlinExpressionStatement {
                // Add our compose tail call to expressions that evaluate to Views and are used as statements
                //~~~ Handle let view = if condition { View1() } else { View2() } (and same with switch)
                if let apiMatch = apiCall.apiMatch {
                    if isView(type: apiMatch.signature, codebaseInfo: translator.codebaseInfo) || isView(type: apiMatch.signature.returnType, codebaseInfo: translator.codebaseInfo) {
                        addComposeTailCall(to: node as! KotlinExpression, statement: expressionStatement)
                    }
                } else {
                    //~~~ Add warnings for unrecognized API use like for async
                }
                return .skip
            } else {
                return .recurse(nil)
            }
        }

        // We may need to use a return label when moving the code block to a closure
        var needsReturnLabel = false
        if !codeBlock.updateRemovingSingleStatementReturn() {
            if let closure {
                needsReturnLabel = closure.hasReturnLabel
            } else {
                needsReturnLabel = codeBlock.updateWithExpectedReturn(.labelIfPresent(KotlinClosure.returnLabel))
            }
        }

        // Wrap the code block in 'return ComposingView { ... }' to return a single view that will compose
        // when the parent adds its tail call
        let composingClosure = KotlinClosure(body: codeBlock)
        composingClosure.parameters = [Parameter(externalLabel: "composectx", declaredType: .named("ComposeContext", []))]
        composingClosure.hasReturnLabel = needsReturnLabel
        let composingArgument = LabeledValue<KotlinExpression>(value: composingClosure)
        let composingFunction = KotlinIdentifier(name: "ComposingView")
        let composingFunctionCall = KotlinFunctionCall(function: composingFunction, arguments: [composingArgument])

        let returnStatement: KotlinStatement = closure == nil ? KotlinReturn(expression: composingFunctionCall) : KotlinExpressionStatement(expression: composingFunctionCall)
        let composingCodeBlock = KotlinCodeBlock(statements: [returnStatement])

        composingCodeBlock.assignParentReferences()
        return composingCodeBlock
    }

    private func addComposeTailCall(to expression: KotlinExpression, statement: KotlinExpressionStatement) {
        let composeMemberAccess = KotlinMemberAccess(base: expression, member: "Compose")
        let contextArgument = LabeledValue<KotlinExpression>(value: KotlinIdentifier(name: "composectx"))
        let composeCall = KotlinFunctionCall(function: composeMemberAccess, arguments: [contextArgument])
        statement.expression = composeCall

        composeCall.parent = statement
        composeCall.assignParentReferences()
    }

    private func isView(type: TypeSignature, codebaseInfo: CodebaseInfo.Context?) -> Bool {
        guard let codebaseInfo else {
            return false
        }
        guard case .named = type else {
            return false
        }
        return codebaseInfo.global.protocolSignatures(forNamed: type)
            .contains { $0.isNamed("View", moduleName: "SwiftUI") }
    }
}

private extension KotlinVariableDeclaration {
    var stateDidChangePropertyName: String {
        return propertyName + "didchange"
    }
}
