/// Translate SwiftUI to syntactically correct Kotlin.
///
/// We rely on our UI libraries to provide the implementation of the SwiftUI-like API that this translation will result in.
final class KotlinSwiftUITransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        // No need to transpile SwiftUI if not a full build
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
                    addKotlinComposeDependencies(to: syntaxTree)
                    break
                }
            }
        }
        if needsTranslation {
            syntaxTree.root.visit { translateVisit($0, translator: translator) }
        }
    }

    /// Return a string of the init parameters needed to construct an `AppStorage` after the `wrappedValue`.
    static func appStorageAdditionalInitParameters(for variableDeclaration: KotlinVariableDeclaration) -> String {
        // Parse annotation tokens to transfer into the constructor args: `@AppStorage("prefsKey", store: UserDefaults.standard)`
        let tokens = variableDeclaration.attributes.of(kind: .appStorage).first?.tokens ?? []
        let keyName = tokens.first ?? "storageKey"
        if tokens.count == 2, let storeName = tokens.last {
            return "\(keyName), store = \(storeName)"
        } else {
            return keyName
        }
    }

    /// If the given variable is the `body` of a `View`, return the parent view.
    static func viewForBody(_ variableDeclaration: KotlinVariableDeclaration, codebaseInfo: CodebaseInfo.Context?) -> KotlinClassDeclaration? {
        guard variableDeclaration.role == .property, variableDeclaration.propertyName == "body", !variableDeclaration.isStatic, let classDeclaration = variableDeclaration.parent as? KotlinClassDeclaration else {
            return nil
        }
        guard isSwiftUIType(named: "View", declaration: classDeclaration, type: classDeclaration.signature, codebaseInfo: codebaseInfo) else {
            return nil
        }
        return classDeclaration
    }

    private static func isSwiftUIType(named: String, declaration: KotlinClassDeclaration? = nil, type: TypeSignature, codebaseInfo: CodebaseInfo.Context?) -> Bool {
        if let declaration, declaration.inherits.contains(where: { $0.isNamed(named, moduleName: "SwiftUI", generics: []) }) {
            return true
        }
        guard let codebaseInfo else {
            return false
        }
        return type.isNamedType && codebaseInfo.global.protocolSignatures(forNamed: type)
                .contains { $0.isNamed(named, moduleName: "SwiftUI") }
    }

    private func translateVisit(_ node: KotlinSyntaxNode, translator: KotlinTranslator) -> VisitResult<KotlinSyntaxNode> {
        if let classDeclaration = node as? KotlinClassDeclaration {
            if omitPreviewProvider(classDeclaration, codebaseInfo: translator.codebaseInfo) {
                return .skip
            } else {
                translateClassDeclaration(classDeclaration, translator: translator)
            }
        } else if let functionDeclaration = node as? KotlinFunctionDeclaration {
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

    private func omitPreviewProvider(_ classDeclaration: KotlinClassDeclaration, codebaseInfo: CodebaseInfo.Context?) -> Bool {
        // The most common thing in a SwiftUI file will be Views, so do a quick exclusion
        guard !Self.isSwiftUIType(named: "View", declaration: classDeclaration, type: classDeclaration.signature, codebaseInfo: codebaseInfo) else {
            return false
        }
        guard Self.isSwiftUIType(named: "PreviewProvider", declaration: classDeclaration, type: classDeclaration.signature, codebaseInfo: codebaseInfo) else {
            return false
        }
        guard let parentStatement = classDeclaration.parent as? KotlinStatement else {
            return false
        }
        parentStatement.remove(statement: classDeclaration)
        return true
    }

    private func translateClassDeclaration(_ classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) {
        var environmentKeyIndex: Int? = nil
        for i in 0..<classDeclaration.inherits.count {
            if classDeclaration.inherits[i].isNamed("EnvironmentKey", moduleName: "SwiftUI") {
                environmentKeyIndex = i
                break
            }
        }
        guard let environmentKeyIndex else {
            return
        }
        guard let defaultValueDeclaration = classDeclaration.members
            .compactMap({ $0 as? KotlinVariableDeclaration })
            .first(where: { $0.propertyName == "defaultValue" && $0.isStatic }),
            defaultValueDeclaration.propertyType != .none else {
            classDeclaration.messages.append(.kotlinEnvironmentValuesKeyDefault(classDeclaration, source: translator.syntaxTree.source))
            return
        }

        // Kotlin requires that the key type be public in order to reflect on it from the SkipUI package
        classDeclaration.modifiers.visibility = .public

        defaultValueDeclaration.modifiers.isOverride = true
        defaultValueDeclaration.modifiers.visibility = .public
        classDeclaration.inherits[environmentKeyIndex] = .named("EnvironmentKey", [defaultValueDeclaration.propertyType])
        classDeclaration.companionInherits.append(.named("EnvironmentKeyCompanion", [defaultValueDeclaration.propertyType]))
    }

    private func translateConstructorDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, translator: KotlinTranslator) {
        // Only need to consider Views
        guard let classDeclaration = functionDeclaration.parent as? KotlinClassDeclaration, Self.isSwiftUIType(named: "View", declaration: classDeclaration, type: classDeclaration.signature, codebaseInfo: translator.codebaseInfo) else {
            return
        }

        // Translate any assignment to a state var into an assignment to its property wrapper
        functionDeclaration.body?.visit { node in
            if node is KotlinClosure {
                return .skip
            } else if node is KotlinFunctionDeclaration {
                return .skip
            } else if let binaryOperator = node as? KotlinBinaryOperator, binaryOperator.op.symbol == "=", let propertyWrapper = propertyWrapper(for: binaryOperator.lhs, in: functionDeclaration.parent as? KotlinClassDeclaration) {
                binaryOperator.lhs = KotlinMemberAccess(base: KotlinIdentifier(name: "self"), member: propertyWrapper.name)
                binaryOperator.rhs = KotlinFunctionCall(function: KotlinIdentifier(name: propertyWrapper.propertyWrapperTypeName), arguments: [LabeledValue(label: nil, value: binaryOperator.rhs)])
                binaryOperator.assignParentReferences()
                return .skip
            } else {
                return .recurse(nil)
            }
        }
    }

    /// If the given expression is a reference to a property wrapper type, return the underlying property name.
    private func propertyWrapper(for expression: KotlinExpression, in view: KotlinClassDeclaration?) -> (name: String, propertyWrapperTypeName: String)? {
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
                if variable.attributes.contains(.state) || variable.attributes.contains(.stateObject) {
                    return ("_" + variableName, "skip.ui.State")
                } else if variable.attributes.contains(.bindable) || variable.attributes.contains(.observedObject) {
                    return ("_" + variableName, "skip.ui.Bindable")
                } else {
                    return nil
                }
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
        // Translate .environment(\.keyPath, value) calls. The key path will have been transpiled
        // to a closure that reads the named property, but we want to set it in EnvironmentValues
        if (functionCall.function as? KotlinMemberAccess)?.member == "environment" || (functionCall.function as? KotlinIdentifier)?.name == "environment", functionCall.arguments.count == 2, let keyPath = functionCall.arguments[0].value as? KotlinKeyPathLiteral {
            updateEnvironmentFunctionCallParameters(for: keyPath, in: functionCall, codebaseInfo: translator.codebaseInfo)
            return
        }

        // Look for closures passed as ViewBuilder arguments to function calls
        guard case .function(let parameterTypes, _, _, _) = functionCall.apiMatch?.signature, parameterTypes.count == functionCall.arguments.count else {
            return
        }
        for i in 0..<parameterTypes.count {
            guard case .function(_, _, let apiFlags, _) = parameterTypes[i].type, apiFlags.contains(.viewBuilder), let closure = functionCall.arguments[i].value as? KotlinClosure else {
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
        if let viewDeclaration = Self.viewForBody(statement, codebaseInfo: translator.codebaseInfo) {
            // We perform our View transformations when we find the body
            transform(view: viewDeclaration, body: statement, translator: translator)
            viewBuilder = statement.getter?.body
        } else if statement.apiFlags.contains(.viewBuilder) {
            viewBuilder = statement.getter?.body
        } else if let classDeclaration = statement.parent as? KotlinClassDeclaration, classDeclaration.signature.isNamed("EnvironmentValues", moduleName: "SwiftUI", generics: []), statement.getter != nil {
            translateEnvironmentValue(statement)
        } else if statement.extends?.0.isNamed("EnvironmentValues", moduleName: "SwiftUI", generics: []) == true, statement.getter != nil {
            translateEnvironmentValue(statement)
        }
        if let viewBuilder {
            statement.getter?.body = translateViewBuilder(codeBlock: viewBuilder, translator: translator)
            statement.getter?.body?.parent = statement
        }
    }

    /// Perform `View` transformations.
    private func transform(view: KotlinClassDeclaration, body: KotlinVariableDeclaration, translator: KotlinTranslator) {
        body.apiFlags.insert(.viewBuilder)
        
        let variableDeclarations = view.members.compactMap { $0 as? KotlinVariableDeclaration }
        let stateVariables = variableDeclarations.filter { $0.attributes.contains(.state) || $0.attributes.contains(.stateObject) }
        let environmentVariables = variableDeclarations.filter { $0.attributes.contains(.environment) || $0.attributes.contains(.environmentObject) }
        let bindingVariables = variableDeclarations.filter { $0.attributes.contains(.binding) }
        let bindableVariables = variableDeclarations.filter { $0.attributes.contains(.bindable) || $0.attributes.contains(.observedObject) }
        let appStorageVariables = variableDeclarations.filter { $0.attributes.contains(.appStorage) }
        if !stateVariables.isEmpty || !environmentVariables.isEmpty || !appStorageVariables.isEmpty {
            let composeFunction = synthesizeComposeFunction(view: view, stateVariables: stateVariables, environmentVariables: environmentVariables, appStorageVariables: appStorageVariables, translator: translator)
            view.insert(statements: [composeFunction], after: body)
            
            for stateVariable in stateVariables {
                synthesizeStateBacking(variable: stateVariable, in: view, propertyWrapperTypeName: "skip.ui.State")
            }
        }
        for bindingVariable in bindingVariables {
            synthesizeBindingBacking(variable: bindingVariable, in: view, source: translator.syntaxTree.source)
        }
        for bindableVariable in bindableVariables {
            synthesizeStateBacking(variable: bindableVariable, in: view, propertyWrapperTypeName: "skip.ui.Bindable")
        }
        for appStorageVariable in appStorageVariables {
            synthesizeAppStorageBacking(variable: appStorageVariable, in: view, source: translator.syntaxTree.source)
        }
    }

    /// Create an override of the SkipUI `Compose` function on views to handle state synchronization, etc.
    private func synthesizeComposeFunction(view: KotlinClassDeclaration, stateVariables: [KotlinVariableDeclaration], environmentVariables: [KotlinVariableDeclaration], appStorageVariables: [KotlinVariableDeclaration], translator: KotlinTranslator) -> KotlinStatement {
        let composeFunction = KotlinFunctionDeclaration(name: "ComposeContent")
        composeFunction.modifiers.visibility = .public
        composeFunction.modifiers.isOverride = true
        composeFunction.annotations.append("@Composable")
        if !stateVariables.isEmpty {
            composeFunction.annotations.append("@Suppress(\"UNCHECKED_CAST\")")
        }
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
        for appStorageVariable in appStorageVariables {
            let statements = synthesizeAppStorageSync(variable: appStorageVariable)
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

    /// Create code to remember and sync a state variable.
    private func synthesizeStateSync(variable: KotlinVariableDeclaration) -> [KotlinStatement] {
        let initialValue = KotlinRawStatement(sourceCode: "val initial\(variable.propertyName) = _\(variable.propertyName).wrappedValue")
        let composeValue = KotlinRawStatement(sourceCode: "var compose\(variable.propertyName) by rememberSaveable(stateSaver = composectx.stateSaver as Saver<\(variable.propertyType.kotlin), Any>) { mutableStateOf(initial\(variable.propertyName)) }")
        let syncValue = KotlinRawStatement(sourceCode: "_\(variable.propertyName).sync(compose\(variable.propertyName), { compose\(variable.propertyName) = it })")
        return [initialValue, composeValue, syncValue]
    }

    /// Create code to remember and sync a state variable.
    private func synthesizeAppStorageSync(variable: KotlinVariableDeclaration) -> [KotlinStatement] {
        let initialValue = KotlinRawStatement(sourceCode: "val initial\(variable.propertyName) = _\(variable.propertyName).wrappedValue")
        let composeValue = KotlinRawStatement(sourceCode: "var compose\(variable.propertyName) by remember { mutableStateOf(initial\(variable.propertyName)) }")
        let syncValue = KotlinRawStatement(sourceCode: "_\(variable.propertyName).sync(compose\(variable.propertyName), { compose\(variable.propertyName) = it })")
        return [initialValue, composeValue, syncValue]
    }

    /// Create code to initialize an environment variable.
    private func synthesizeEnvironmentSync(variable: KotlinVariableDeclaration, translator: KotlinTranslator) -> KotlinStatement? {
        let entry: (key: String, type: TypeSignature?, isObject: Bool)
        if let environment = (variable.attributes.of(kind: .environment) + variable.attributes.of(kind: .environmentObject)).first {
            let rawKey = environment.tokens.first ?? ""
            if let environmentEntry = environmentEntry(for: variable, key: rawKey, codebaseInfo: translator.codebaseInfo) {
                entry = environmentEntry
            } else {
                variable.messages.append(.kotlinEnvironmentKeyType(variable, source: translator.syntaxTree.source))
                return nil
            }
        } else {
            return nil
        }

        // Handle the fact that environment vars do not have an initial value and may not have a declared type
        let environmentType = variable.declaredType == .none ? entry.type : variable.declaredType
        if variable.value == nil {
            var updatedType: TypeSignature? = nil
            if let environmentType, let defaultValue = environmentType.kotlinDefaultValue {
                if variable.declaredType == .none {
                    updatedType = environmentType
                    variable.declaredType = environmentType
                    variable.propertyType = environmentType
                }
                variable.value = KotlinRawExpression(sourceCode: defaultValue)
            } else if let environmentType {
                if variable.declaredType == .none {
                    updatedType = environmentType
                }
                variable.declaredType = environmentType.asUnwrappedOptional(true)
                variable.propertyType = environmentType.asUnwrappedOptional(true)
            } else {
                variable.messages.append(.kotlinEnvironmentDeclaredType(variable, source: translator.syntaxTree.source))
            }
            // Erase handling of mutable struct property if the actual type is not a mutable struct
            if let updatedType, let codebaseInfo = translator.codebaseInfo, variable.mayBeSharedMutableStruct && !updatedType.kotlinMayBeSharedMutableStruct(codebaseInfo: codebaseInfo) {
                variable.mayBeSharedMutableStruct = false
                variable.onUpdate = nil
            }
        }

        var valueSourceCode: String
        if entry.isObject {
            valueSourceCode = "EnvironmentValues.shared.environmentObject(type = \(entry.key))"
            if environmentType?.isOptional == false {
                valueSourceCode += "!!"
            }
        } else {
            valueSourceCode = "EnvironmentValues.shared.\(entry.key)"
        }
        return KotlinRawStatement(sourceCode: "\(variable.propertyName) = \(valueSourceCode)")
    }

    /// Given a Swift `@Environment` property wrapper key, return the Kotlin key and the expected value type.
    private func environmentEntry(for variableDeclaration: KotlinVariableDeclaration, key: String, codebaseInfo: CodebaseInfo.Context?) -> (key: String, type: TypeSignature?, isObject: Bool)? {
        if key.isEmpty {
            let type = variableDeclaration.declaredType
            return type == .none ? nil : (type.kotlin + "::class", type, true)
        } else if key.hasSuffix(".self") {
            let typeName = String(key.dropLast(".self".count))
            return (typeName + "::class", .named(typeName, []), true)
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
            return (propertyName, type, false)
        }
    }

    /// Create the additional property synthesized for `@State` and similar variables.
    private func synthesizeStateBacking(variable: KotlinVariableDeclaration, in view: KotlinClassDeclaration, propertyWrapperTypeName: String) {
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
            let stateType = variable.propertyType.asPropertyWrapper(propertyWrapperTypeName).kotlin
            output.append(indentation).append(variable.modifiers.kotlinMemberString(isGlobal: false, isOpen: false, suffix: " ")).append("var ").append(storageName).append(": ").append(stateType)
            if let value = variable.value {
                output.append(" = \(propertyWrapperTypeName)(")
                value.append(to: output, indentation: indentation)
                output.append(")")
            } else if variable.propertyType.isOptional {
                output.append(" = \(propertyWrapperTypeName)(null)")
            }
            output.append("\n")
        }
        variable.storage = storage
    }

    /// Create the extra property synthesized for `@Binding` variables.
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
            output.append(indentation).append(variable.modifiers.kotlinMemberString(isGlobal: false, isOpen: false, suffix: " ")).append("var ").append(storageName).append(": ").append(variable.propertyType.asBinding().kotlin).append("\n")
        }
        variable.storage = storage
    }

    /// Create the additional property synthesized for `@AppStorage` variables.
    private func synthesizeAppStorageBacking(variable: KotlinVariableDeclaration, in view: KotlinClassDeclaration, source: Source) {
        // Tell the @AppStorage variable to get and set its value using _variable of type AppStorage
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
            let storageType = variable.propertyType.asPropertyWrapper("skip.ui.AppStorage").kotlin
            output.append(indentation).append(variable.modifiers.kotlinMemberString(isGlobal: false, isOpen: false, suffix: " ")).append("var ").append(storageName).append(": ").append(storageType)
            if let value = variable.value {
                output.append(" = skip.ui.AppStorage(")
                value.append(to: output, indentation: indentation)
                output.append(", ")
                output.append(Self.appStorageAdditionalInitParameters(for: variable))
                output.append(")")
            } else if variable.propertyType.isOptional {
                output.append(" = skip.ui.AppStorage(null, ")
                output.append(Self.appStorageAdditionalInitParameters(for: variable))
                output.append(")")
            }
            output.append("\n")
        }
        variable.storage = storage
    }

    private func translateViewBuilder(codeBlock: KotlinCodeBlock, fromClosure closure: KotlinClosure? = nil, translator: KotlinTranslator) -> KotlinCodeBlock {
        // Add tail calls to compose the views that SwiftUI would build into a TupleView
        codeBlock.visit { node in
            if node is KotlinFunctionDeclaration || node is KotlinClosure {
                // These do not inherit our view builder context and will get processed by the top-level visitation code
                return .skip
            } else if let apiCall = node as? APICallExpression, let expressionStatement = node.parent as? KotlinExpressionStatement, !isInAssignmentExpression(expressionStatement, in: codeBlock) {
                // Add our compose tail call to expressions that evaluate to Views and are used as statements
                if let apiMatch = apiCall.apiMatch {
                    if Self.isSwiftUIType(named: "View", type: apiMatch.signature, codebaseInfo: translator.codebaseInfo) || Self.isSwiftUIType(named: "View", type: apiMatch.signature.returnType, codebaseInfo: translator.codebaseInfo) {
                        addComposeTailCall(to: node as! KotlinExpression, statement: expressionStatement)
                    }
                } else {
                    node.messages.append(.kotlinSwiftUITypeInference(node, source: translator.syntaxTree.source))
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
            // Add a final return value just in case the closure logic doesn't guarantee one
            codeBlock.statements.append(KotlinRawStatement(sourceCode: "ComposeResult.ok"))
        }

        // Wrap the code block in 'return ComposeView { ... }' to return a single view that will compose
        // when the parent adds its tail call
        let composingClosure = KotlinClosure(body: codeBlock)
        composingClosure.parameters = [Parameter(externalLabel: "composectx", declaredType: .named("ComposeContext", []))]
        composingClosure.hasReturnLabel = needsReturnLabel
        let composingArgument = LabeledValue<KotlinExpression>(value: composingClosure)
        let composingFunction = KotlinIdentifier(name: "ComposeView")
        let composingFunctionCall = KotlinFunctionCall(function: composingFunction, arguments: [composingArgument])
        composingFunctionCall.hasTrailingClosures = true

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

    private func isInAssignmentExpression(_ statement: KotlinStatement, in codeBlock: KotlinCodeBlock) -> Bool {
        var node: KotlinSyntaxNode = statement
        while node !== codeBlock {
            if let binaryOperator = node as? KotlinBinaryOperator, binaryOperator.op.precedence == .assignment {
                return true
            } else if node is KotlinVariableDeclaration {
                return true
            }
            if let parent = node.parent {
                node = parent
            } else {
                break
            }
        }
        return false
    }

    private func translateEnvironmentValue(_ statement: KotlinVariableDeclaration) {
        statement.getterAnnotations.append("@Composable")
        statement.onUpdate = nil
        guard let setter = statement.setter else {
            return
        }
        statement.setter = nil
        statement.apiFlags.remove(.writeable)

        let setFunction = KotlinFunctionDeclaration(name: "set" + statement.propertyName)
        setFunction.extends = statement.extends
        setFunction.modifiers = statement.modifiers
        setFunction.parameters = [Parameter<KotlinExpression>(externalLabel: setter.parameterName ?? "newValue", declaredType: statement.declaredType)]
        setFunction.body = setter.body

        (statement.parent as? KotlinStatement)?.insert(statements: [setFunction], after: statement)
    }

    private func updateEnvironmentFunctionCallParameters(for keyPath: KotlinKeyPathLiteral, in functionCall: KotlinFunctionCall, codebaseInfo: CodebaseInfo.Context?) {
        guard keyPath.components.count == 1, case .property(let property) = keyPath.components[0] else {
            return
        }

        let code = "EnvironmentValues.shared.set\(property)(it)"
        let codeBlock = KotlinCodeBlock(statements: [KotlinRawStatement(sourceCode: code)])
        let closure = KotlinClosure(body: codeBlock, sourceFile: keyPath.sourceFile, sourceRange: keyPath.sourceRange)
        closure.returnType = .void
        closure.inferredReturnType = .void
        closure.parent = functionCall
        functionCall.arguments[0] = LabeledValue(label: functionCall.arguments[0].label, value: closure)

        guard let memberAccess = functionCall.arguments[1].value as? KotlinMemberAccess, memberAccess.baseType == .none || memberAccess.baseType == .any, let codebaseInfo else {
            return
        }
        // Attempt to fill in the base type using the EnvironmentValues property being accessed
        if let match = codebaseInfo.matchIdentifier(name: property, inConstrained: .named("EnvironmentValues", [])) {
            memberAccess.baseType = match.signature
        }
    }

    private func addKotlinComposeDependencies(to syntaxTree: KotlinSyntaxTree) {
        syntaxTree.dependencies.imports.insert("androidx.compose.runtime.Composable")
        syntaxTree.dependencies.imports.insert("androidx.compose.runtime.getValue")
        syntaxTree.dependencies.imports.insert("androidx.compose.runtime.mutableStateOf")
        syntaxTree.dependencies.imports.insert("androidx.compose.runtime.remember")
        syntaxTree.dependencies.imports.insert("androidx.compose.runtime.setValue")
        syntaxTree.dependencies.imports.insert("androidx.compose.runtime.saveable.rememberSaveable")
        syntaxTree.dependencies.imports.insert("androidx.compose.runtime.saveable.Saver")
        syntaxTree.dependencies.imports.insert("skip.foundation.*")
        syntaxTree.dependencies.imports.insert("skip.model.*")
    }
}
