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
            if functionDeclaration.type == .constructorDeclaration {
                translateConstructorDeclaration(functionDeclaration, translator: translator)
            } else {
                translateFunctionDeclaration(functionDeclaration, translator: translator)
            }
        } else if let variableDeclaration = node as? KotlinVariableDeclaration {
            translateVariableDeclaration(variableDeclaration, translator: translator)
        } else if let closure = node as? KotlinClosure {
            translateClosure(closure, translator: translator)
        } else if let functionCall = node as? KotlinFunctionCall {
            translateFunctionCallParameters(functionCall, translator: translator)
        }
        return .recurse(nil)
    }

    private func translateConstructorDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, translator: KotlinTranslator) {
        // Translate any assignment to a state var into an assignment to its property wrapper
        functionDeclaration.body?.visit { node in
            if node is KotlinClosure {
                return .skip
            } else if node is KotlinFunctionDeclaration {
                return .skip
            } else if let binaryOperator = node as? KotlinBinaryOperator, binaryOperator.op.symbol == "=", let statePropertyName = statePropertyName(for: binaryOperator.lhs, in: functionDeclaration.parent as? KotlinClassDeclaration) {
                binaryOperator.lhs = KotlinMemberAccess(base: KotlinIdentifier(name: "self"), member: "_" + statePropertyName)
                binaryOperator.rhs = KotlinFunctionCall(function: KotlinIdentifier(name: "State"), arguments: [LabeledValue(label: "initialValue", value: binaryOperator.rhs)])
                binaryOperator.assignParentReferences()
                return .skip
            } else {
                return .recurse(nil)
            }
        }
    }

    private func statePropertyName(for expression: KotlinExpression, in view: KotlinClassDeclaration?) -> String? {
        guard let view else {
            return nil
        }
        var variableName: String? = nil
        if let identifier = expression as? KotlinIdentifier {
            variableName = identifier.name
        } else if let memberAccess = expression as? KotlinMemberAccess, (memberAccess.base as? KotlinIdentifier)?.name == "self" {
            variableName = memberAccess.member
        }
        guard let variableName else {
            return nil
        }
        for member in view.members {
            if let variable = member as? KotlinVariableDeclaration, variable.propertyName == variableName {
                return variable.attributes.contains(.state) ? variableName : nil
            }
        }
        return nil
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
            transform(view: viewDeclaration, body: statement, translator: translator)
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
    
    private func transform(view: KotlinClassDeclaration, body: KotlinVariableDeclaration, translator: KotlinTranslator) {
        body.apiFlags.insert(.viewBuilder)
        
        let variableDeclarations = view.members.compactMap { $0 as? KotlinVariableDeclaration }
        let stateVariables = variableDeclarations.filter { $0.attributes.contains(.state) || $0.attributes.contains(.stateObject) }
        let environmentVariables = variableDeclarations.filter { $0.attributes.contains(.environment) || $0.attributes.contains(.environmentObject) }
        if !stateVariables.isEmpty || !environmentVariables.isEmpty {
            let composeFunction = synthesizeComposeFunction(view: view, stateVariables: stateVariables, environmentVariables: environmentVariables, translator: translator)
            view.insert(statements: [composeFunction], after: body)
            
            for stateVariable in stateVariables {
                synthesizeStateBacking(variable: stateVariable, in: view)
            }
        }
        for bindingVariable in variableDeclarations.filter({ $0.attributes.contains(.binding) }) {
            synthesizeBindingBacking(variable: bindingVariable, in: view, source: translator.syntaxTree.source)
        }
    }
    
    private func synthesizeComposeFunction(view: KotlinClassDeclaration, stateVariables: [KotlinVariableDeclaration], environmentVariables: [KotlinVariableDeclaration], translator: KotlinTranslator) -> KotlinStatement {
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
        for i in 0..<environmentVariables.count {
            guard let statement = synthesizeEnvironmentSync(variable: environmentVariables[i], translator: translator) else {
                continue
            }
            if i == 0 && !composeBodyStatements.isEmpty {
                statement.extras = .singleNewline
            }
            composeBodyStatements.append(statement)
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

    private func synthesizeEnvironmentSync(variable: KotlinVariableDeclaration, translator: KotlinTranslator) -> KotlinStatement? {
        let entry: (key: String, type: TypeSignature?)
        if let environment = (variable.attributes.of(kind: .environment) + variable.attributes.of(kind: .environmentObject)).first {
            let rawKey = environment.tokens.joined(separator: "")
            if let environmentEntry = environmentEntry(for: rawKey, codebaseInfo: translator.codebaseInfo) {
                entry = environmentEntry
            } else {
                entry = (rawKey, nil)
                variable.messages.append(.kotlinEnvironmentKeyType(variable, source: translator.syntaxTree.source))
            }
        } else {
            return nil
        }

        if variable.declaredType == .none && variable.value == nil {
            if let environmentType = entry.type {
                if let defaultValue = environmentType.kotlinDefaultValue {
                    variable.declaredType = environmentType
                    variable.propertyType = environmentType
                    variable.value = KotlinRawExpression(sourceCode: defaultValue)
                } else {
                    variable.declaredType = environmentType.asUnwrappedOptional(true)
                    variable.propertyType = environmentType.asUnwrappedOptional(true)
                }
                if let codebaseInfo = translator.codebaseInfo, variable.mayBeSharedMutableStruct && !environmentType.kotlinMayBeSharedMutableStruct(codebaseInfo: codebaseInfo) {
                    variable.mayBeSharedMutableStruct = false
                    variable.onUpdate = nil
                }
            } else {
                variable.messages.append(.kotlinEnvironmentDeclaredType(variable, source: translator.syntaxTree.source))
            }
        }
        return KotlinRawStatement(sourceCode: "\(variable.propertyName) = composectx.environment[\(entry.key)]")
    }

    private func environmentEntry(for key: String, codebaseInfo: CodebaseInfo.Context?) -> (String, TypeSignature?)? {
        if key.hasSuffix(".self") {
            let typeName = String(key.dropLast(".self".count))
            return (typeName + "::class", .named(typeName, []))
        } else {
            let propertyName: String
            if key.hasPrefix("\\EnvironmentValues.") {
                propertyName = String(key.dropFirst("\\EnvironmentValues.".count))
            } else if key.hasPrefix("\\.") {
                propertyName = String(key.dropFirst(2))
            } else {
                return nil
            }
            let type = codebaseInfo?.matchIdentifier(name: propertyName, inConstrained: .named("EnvironmentValues", []))?.signature
            return ("EnvironmentValues::" + propertyName, type)
        }
    }

    private func synthesizeStateBacking(variable: KotlinVariableDeclaration, in view: KotlinClassDeclaration) {
        let didChangeType: TypeSignature = .function([], .void, []).asOptional(true)
        let didChangeProperty = KotlinVariableDeclaration(names: [variable.stateDidChangePropertyName], variableTypes: [didChangeType])
        didChangeProperty.declaredType = didChangeType
        didChangeProperty.role = .property
        didChangeProperty.modifiers.visibility = .private
        didChangeProperty.apiFlags = [.writeable]
        didChangeProperty.isGenerated = true
        view.insert(statements: [didChangeProperty], after: variable)

        variable.setterSideEffects.append(KotlinRawStatement(sourceCode: "\(variable.stateDidChangePropertyName)?.invoke()"))

        // Tell the @State variable to get and set its value using _variable of type State
        let storageName = "_\(variable.propertyName)"
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
        storage.appendStorage = { variable, output, indentation in
            let stateType = variable.propertyType.asState().kotlin
            output.append(indentation).append(variable.modifiers.kotlinMemberString(isGlobal: false, isOpen: false, suffix: " ")).append("var ").append(storageName).append(": ").append(stateType)
            if let value = variable.value {
                output.append(" = State(")
                value.append(to: output, indentation: indentation)
                output.append(")")
            } else if variable.propertyType.isOptional {
                output.append(" = State(null)")
            }
            output.append("\n")
        }
        variable.storage = storage
    }

    private func synthesizeBindingBacking(variable: KotlinVariableDeclaration, in view: KotlinClassDeclaration, source: Source) {
        let propertyType = variable.declaredType == .none ? variable.propertyType : variable.declaredType
        if propertyType == .none {
            variable.messages.append(.kotlinVariableNeedsTypeDeclaration(variable, source: source))
        }

        // Tell the @Binding variable to get and set its value using _variable of type Binding
        let storageName = "_\(variable.propertyName)"
        var storage = KotlinVariableStorage()
        storage.isSingleStatementAppendable = { _ in true }
        storage.appendGet = { variable, sref, isSingleStatement, output, indentation in
            if !isSingleStatement {
                output.append(indentation).append("return ")
            }
            output.append(storageName).append(".get()")
            sref()
            output.append("\n")
        }
        storage.appendSet = { variable, value, output, indentation in
            output.append(indentation).append(storageName).append(".set(")
            value()
            output.append(")\n")
        }
        storage.appendStorage = { variable, output, indentation in
            output.append(indentation).append(variable.modifiers.kotlinMemberString(isGlobal: false, isOpen: false, suffix: " ")).append("var ").append(storageName).append(": ").append(variable.propertyType.asBinding().kotlin).append("\n")
        }
        variable.storage = storage
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
