/// Generate compiled Swift to Kotlin bridging code.
///
/// - Warning: This visitor assumes that the given syntax tree only contains bridged API.
final class KotlinBridgeToKotlinVisitor {
    private let syntaxTree: KotlinSyntaxTree
    private let options: KotlinBridgeOptions
    private let translator: KotlinTranslator
    private let codebaseInfo: CodebaseInfo.Context
    private var swiftDefinitions: [SwiftDefinition] = []
    private var cdeclFunctions: [CDeclFunction] = []

    init?(for syntaxTree: KotlinSyntaxTree, options: KotlinBridgeOptions, translator: KotlinTranslator) {
        guard syntaxTree.isBridgeFile, let codebaseInfo = translator.codebaseInfo else {
            return nil
        }
        self.syntaxTree = syntaxTree
        self.options = options
        self.translator = translator
        self.codebaseInfo = codebaseInfo
    }

    func visit() -> [KotlinTransformerOutput] {
        var globalFunctionCount = 0
        var bridgedObservables: [KotlinStatement] = []
        var hasSkipFuseImport = false
        var nonKotlinImports: [KotlinStatement] = []
        syntaxTree.root.visit { node in
            if let importDeclaration = node as? KotlinImportDeclaration {
                if importDeclaration.unmappedModulePath.first == "SkipFuse" {
                    hasSkipFuseImport = true
                }
                // Filter compiled-only imports from the transpiled output
                if !isKotlinImport(importDeclaration) {
                    nonKotlinImports.append(importDeclaration)
                }
                return .skip
            } else if let variableDeclaration = node as? KotlinVariableDeclaration {
                if variableDeclaration.role == .global {
                    update(variableDeclaration)
                } else if variableDeclaration.extends != nil {
                    variableDeclaration.checkExtensionUnbridgable(translator: translator)
                }
                return .skip
            } else if let functionDeclaration = node as? KotlinFunctionDeclaration {
                if functionDeclaration.role == .global {
                    if update(functionDeclaration, uniquifier: globalFunctionCount) {
                        globalFunctionCount += 1
                    }
                } else if functionDeclaration.extends != nil {
                    functionDeclaration.checkExtensionUnbridgable(translator: translator)
                }
                return .skip
            } else if let classDeclaration = node as? KotlinClassDeclaration {
                if update(classDeclaration) {
                    if classDeclaration.attributes.contains(.observable) {
                        bridgedObservables.append(classDeclaration)
                    }
                }
                return .recurse(nil)
            } else if let interfaceDeclaration = node as? KotlinInterfaceDeclaration {
                if update(interfaceDeclaration) {
                    if let bridgeImplDefinition = KotlinBridgeToSwiftVisitor.protocolBridgeImplDefinition(forProtocol: interfaceDeclaration.signature, inPackage: translator.packageName, statement: interfaceDeclaration, options: options, codebaseInfo: codebaseInfo) {
                        swiftDefinitions.append(bridgeImplDefinition)
                    }
                }
                return .recurse(nil)
            } else {
                return .recurse(nil)
            }
        }
        nonKotlinImports.forEach { syntaxTree.root.remove(statement: $0) }

        if !hasSkipFuseImport {
            for statement in bridgedObservables {
                statement.messages.append(.kotlinBridgeObservableMissingImport(statement, source: syntaxTree.source))
            }
        }

        var outputs: [KotlinTransformerOutput] = []
        if let bridgeOutput = bridgeOutput() {
            outputs.append(bridgeOutput)
        }
        return outputs
    }

    private func bridgeOutput() -> KotlinTransformerOutput? {
        guard !swiftDefinitions.isEmpty || !cdeclFunctions.isEmpty else {
            return nil
        }
        guard let outputFile = syntaxTree.source.file.bridgeOutputFile else {
            return nil
        }

        let importDeclarations = translator.syntaxTree.root.statements.compactMap { $0 as? ImportDeclaration }
        let swiftDefinitions = self.swiftDefinitions
        let cdeclFunctions = self.cdeclFunctions
        let outputNode = SwiftDefinition { output, indentation, _ in
            output.append("import SkipBridge\n\n")
            for importDeclaration in importDeclarations {
                let path = importDeclaration.modulePath.joined(separator: ".")
                output.append(indentation).append("import ").append(path).append("\n")
            }
            swiftDefinitions.forEach { $0.append(to: output, indentation: indentation) }
            cdeclFunctions.forEach { $0.append(to: output, indentation: indentation) }
        }
        return KotlinTransformerOutput(file: outputFile, node: outputNode, type: .bridgeFromSwift)
    }

    private func isKotlinImport(_ importDeclaration: KotlinImportDeclaration) -> Bool {
        guard !importDeclaration.isKotlinImport else {
            return true
        }
        guard let moduleName = importDeclaration.modulePath.first else {
            return false
        }
        guard CodebaseInfo.moduleNameMap[moduleName] == nil else {
            return true
        }
        guard moduleName != codebaseInfo.global.moduleName else {
            return true
        }
        return codebaseInfo.global.dependentModules.contains { moduleName == $0.moduleName }
    }

    private func update(_ variableDeclaration: KotlinVariableDeclaration, in classDeclaration: KotlinClassDeclaration? = nil) {
        guard !variableDeclaration.isGenerated else {
            return
        }
        guard let bridgable = variableDeclaration.checkBridgable(direction: .toKotlin, options: options, translator: translator) else {
            return
        }
        variableDeclaration.extras = nil
        // If this is a let constant with a supported literal value, we'll re-declare rather than bridge it
        guard !isSupportedConstant(variableDeclaration, type: bridgable.type) else {
            return
        }

        let propertyName = variableDeclaration.preEscapedPropertyName ?? variableDeclaration.propertyName
        guard !variableDeclaration.isAppendAsFunction else {
            let functionDeclaration = KotlinFunctionDeclaration(name: propertyName, sourceFile: variableDeclaration.sourceFile, sourceRange: variableDeclaration.sourceRange)
            functionDeclaration.returnType = variableDeclaration.propertyType
            functionDeclaration.role = variableDeclaration.role == .global ? .global : .member
            functionDeclaration.modifiers = variableDeclaration.modifiers
            functionDeclaration.attributes = variableDeclaration.attributes
            functionDeclaration.apiFlags = variableDeclaration.apiFlags
            functionDeclaration.parent = classDeclaration

            let functionBridgable = FunctionBridgable(parameters: [], return: bridgable)
            let (bodyCodeBlock, externalStatements) = addDefinitions(for: functionDeclaration, bridgable: functionBridgable, in: classDeclaration, isDeclaredByVariable: true)
            variableDeclaration.getter = Accessor(body: bodyCodeBlock)
            (variableDeclaration.parent as? KotlinStatement)?.insert(statements: externalStatements, after: variableDeclaration)
            return
        }

        // Remove initial value and make sure type is declared
        variableDeclaration.value = nil
        variableDeclaration.declaredType = bridgable.kotlinType

        let externalName = "Swift_" + ((variableDeclaration.isStatic) ? "Companion_" + propertyName : propertyName)
        var externalFunctionDeclarations: [String] = []
        let (cdecl, cdeclName) = CDeclFunction.declaration(for: variableDeclaration, isCompanion: variableDeclaration.isStatic, name: externalName, translator: translator)

        // Getter
        let isInstance = classDeclaration != nil && !variableDeclaration.isStatic
        let isEnum = classDeclaration?.declarationType == .enumDeclaration
        let isSealedClassesEnum = classDeclaration?.isSealedClassesEnum == true
        let getterArguments: String
        let getterParameters: String
        if isInstance {
            getterArguments = isSealedClassesEnum ? "(javaClass.name)" : isEnum ? "(name)" : "(Swift_peer)"
            getterParameters = isSealedClassesEnum ? "(className: String)" : isEnum ? "(name: String)" : "(Swift_peer: skip.bridge.kt.SwiftObjectPointer)"
        } else {
            getterArguments = "()"
            getterParameters = "()"
        }
        let getterSref: String
        if let onUpdate = variableDeclaration.onUpdate?(), !onUpdate.isEmpty, !options.contains(.kotlincompat) {
            getterSref = ".sref(\(onUpdate))"
        } else {
            getterSref = ""
        }
        var asOptional = bridgable.type.isOptional
        var forceUnwrapString = ""
        if variableDeclaration.apiFlags.throwsType != .none && !bridgable.type.isOptional {
            asOptional = true
            forceUnwrapString = "!!"
        }
        let getterBody = [
            "return " + externalName + getterArguments + forceUnwrapString + getterSref
        ]
        variableDeclaration.getter = Accessor(body: KotlinCodeBlock(statements: getterBody.map { KotlinRawStatement(sourceCode: $0) }))
        externalFunctionDeclarations.append("private external fun \(externalName)\(getterParameters): \(bridgable.kotlinType.asOptional(asOptional).kotlin)")

        let cdeclInstanceParameters: [TypeSignature.Parameter]
        var cdeclGetterBody: [String] = []
        let valueString: String
        if let classDeclaration {
            if isInstance {
                if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
                    cdeclGetterBody.append("let peer_swift: \(classDeclaration.signature) = Swift_peer.pointee()!")
                    valueString = bridgable.type.convertToCDecl(value: "peer_swift.\(propertyName)", strategy: bridgable.strategy, options: options)
                } else if isSealedClassesEnum {
                    cdeclGetterBody.append("let className_swift = String.fromJavaObject(className, options: \(options.jconvertibleOptions))")
                    cdeclGetterBody.append("let peer_swift = \(classDeclaration.signature).fromJavaClassName(className_swift, Java_target, options: \(options.jconvertibleOptions))")
                    valueString = bridgable.type.convertToCDecl(value: "peer_swift.\(propertyName)", strategy: bridgable.strategy, options: options)
                } else if isEnum {
                    cdeclGetterBody.append("let name_swift = String.fromJavaObject(name, options: \(options.jconvertibleOptions))")
                    cdeclGetterBody.append("let peer_swift = \(classDeclaration.signature).fromJavaName(name_swift)")
                    valueString = bridgable.type.convertToCDecl(value: "peer_swift.\(propertyName)", strategy: bridgable.strategy, options: options)
                } else {
                    cdeclGetterBody.append("let peer_swift: SwiftValueTypeBox<\(classDeclaration.signature)> = Swift_peer.pointee()!")
                    valueString = bridgable.type.convertToCDecl(value: "peer_swift.value.\(propertyName)", strategy: bridgable.strategy, options: options)
                }
                cdeclInstanceParameters = [cdeclInstanceParameter(for: classDeclaration)]
            } else {
                valueString = bridgable.type.convertToCDecl(value: "\(classDeclaration.signature).\(propertyName)", strategy: bridgable.strategy, options: options)
                cdeclInstanceParameters = []
            }
        } else {
            valueString = bridgable.type.convertToCDecl(value: propertyName, strategy: bridgable.strategy, options: options)
            cdeclInstanceParameters = []
        }
        if variableDeclaration.apiFlags.throwsType == .none {
            cdeclGetterBody.append("return " + valueString)
        } else {
            cdeclGetterBody.append("do {")
            cdeclGetterBody.append(1, "let f_return_swift = try " + valueString)
            cdeclGetterBody.append(1, "return f_return_swift.toJavaObject(options: \(options.jconvertibleOptions))")
            cdeclGetterBody.append("} catch {")
            cdeclGetterBody.append(1, "JavaThrowError(error, env: Java_env)")
            cdeclGetterBody.append(1, "return nil")
            cdeclGetterBody.append("}")
        }
        let cdeclGetter = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: .function(cdeclInstanceParameters, bridgable.type.asOptional(asOptional).cdecl(strategy: bridgable.strategy, options: options), APIFlags(), nil), body: cdeclGetterBody)
        cdeclFunctions.append(cdeclGetter)

        // Setter
        if variableDeclaration.apiFlags.options.contains(.writeable) {
            let setterArguments: String
            let setterInstanceParameter: String
            if isInstance {
                setterArguments = isSealedClassesEnum ? "javaClass.name, newValue" : isEnum ? "name, newValue" : "Swift_peer, newValue"
                setterInstanceParameter = isSealedClassesEnum ? "className: String, " : isEnum ? "name: String, " : "Swift_peer: skip.bridge.kt.SwiftObjectPointer, "
            } else {
                setterArguments = "newValue"
                setterInstanceParameter = ""
            }
            let setterBody = [
                externalName + "_set(" + setterArguments + ")"
            ]
            variableDeclaration.setter = Accessor(parameterName: "newValue", body: KotlinCodeBlock(statements: setterBody.map { KotlinRawStatement(sourceCode: $0) }))
            externalFunctionDeclarations.append("private external fun \(externalName)_set(\(setterInstanceParameter)value: \(bridgable.kotlinType.kotlin))")

            var cdeclSetterBody: [String] = []
            if let classDeclaration {
                if isInstance {
                    if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
                        cdeclSetterBody.append("let peer_swift: \(classDeclaration.signature) = Swift_peer.pointee()!")
                        cdeclSetterBody.append("peer_swift.\(propertyName) = " + bridgable.type.convertFromCDecl(value: "value", strategy: bridgable.strategy, options: options))
                    } else if isSealedClassesEnum {
                        cdeclSetterBody.append("let className_swift = String.fromJavaObject(className, options: \(options.jconvertibleOptions))")
                        cdeclSetterBody.append("let peer_swift = \(classDeclaration.signature).fromJavaClassName(className_swift, Java_target, options: \(options.jconvertibleOptions))")
                        cdeclSetterBody.append("peer_swift.\(propertyName) = " + bridgable.type.convertFromCDecl(value: "value", strategy: bridgable.strategy, options: options))
                    } else if isEnum {
                        cdeclSetterBody.append("let name_swift = String.fromJavaObject(name, options: \(options.jconvertibleOptions))")
                        cdeclSetterBody.append("let peer_swift = \(classDeclaration.signature).fromJavaName(name_swift)")
                        cdeclSetterBody.append("peer_swift.\(propertyName) = " + bridgable.type.convertFromCDecl(value: "value", strategy: bridgable.strategy, options: options))
                    } else {
                        cdeclSetterBody.append("let peer_swift: SwiftValueTypeBox<\(classDeclaration.signature)> = Swift_peer.pointee()!")
                        cdeclSetterBody.append("peer_swift.value.\(propertyName) = " + bridgable.type.convertFromCDecl(value: "value", strategy: bridgable.strategy, options: options))
                    }
                } else {
                    cdeclSetterBody.append("\(classDeclaration.signature).\(propertyName) = " + bridgable.type.convertFromCDecl(value: "value", strategy: bridgable.strategy, options: options))
                }
            } else {
                cdeclSetterBody.append(propertyName + " = " + bridgable.type.convertFromCDecl(value: "value", strategy: bridgable.strategy, options: options))
            }
            let cdeclSetter = CDeclFunction(name: cdeclName + "_set", cdecl: cdecl + "_1set", signature: .function(cdeclInstanceParameters + [TypeSignature.Parameter(label: "value", type: bridgable.type.cdecl(strategy: bridgable.strategy, options: options))], .void, APIFlags(), nil), body: cdeclSetterBody)
            cdeclFunctions.append(cdeclSetter)
        }
        variableDeclaration.willSet = nil
        variableDeclaration.didSet = nil

        // Add function declarations to transpiled output
        (variableDeclaration.parent as? KotlinStatement)?.insert(statements: externalFunctionDeclarations.map { KotlinRawStatement(sourceCode: $0, isStatic: variableDeclaration.isStatic) }, after: variableDeclaration)
    }

    private func isSupportedConstant(_ variableDeclaration: KotlinVariableDeclaration, type: TypeSignature) -> Bool {
        guard variableDeclaration.isLet, let value = variableDeclaration.value else {
            return false
        }
        guard !(value is KotlinNullLiteral) else {
            return true
        }
        // Only support constants whose values we can mirror in Kotlin without workarounds from the user. For
        // example we don't support Floats because Kotlin requires Float(value)
        switch type.asOptional(false) {
        case .bool:
            return variableDeclaration.value?.type == .booleanLiteral
        case .double, .int, .int32:
            return variableDeclaration.value?.type == .numericLiteral
        case .string:
            guard let stringLiteral = variableDeclaration.value as? KotlinStringLiteral else {
                return false
            }
            return !stringLiteral.segments.contains { $0.isExpression }
        default:
            return false
        }
    }

    private func update(_ functionDeclaration: KotlinFunctionDeclaration, in classDeclaration: KotlinClassDeclaration? = nil, isBridgedSubclass: Bool = false, uniquifier: Int) -> Bool {
        guard !functionDeclaration.isGenerated || functionDeclaration.type == .constructorDeclaration else {
            return false
        }
        let isMutableStructCopyConstructor = classDeclaration != nil && functionDeclaration.isMutableStructCopyConstructor
        let bridgable: FunctionBridgable
        if isMutableStructCopyConstructor {
            let parameterBridgable = Bridgable(type: .named("MutableStruct", []), kotlinType: .module("Swift", .named("MutableStruct", [])), strategy: .peer)
            bridgable = FunctionBridgable(parameters: [parameterBridgable], return: Bridgable(type: .void, kotlinType: .void, strategy: .direct))
        } else {
            guard let functionBridgable = functionDeclaration.checkBridgable(direction: .toKotlin, options: options, translator: translator) else {
                return false
            }
            bridgable = functionBridgable
        }
        functionDeclaration.returnType = bridgable.return.kotlinType
        functionDeclaration.parameters = functionDeclaration.parameters.enumerated().map { index, parameter in
            var parameter = parameter
            parameter.declaredType = bridgable.parameters[index].kotlinType
            return parameter
        }
        functionDeclaration.extras = nil

        let (bodyCodeBlock, externalStatements) = addDefinitions(for: functionDeclaration, bridgable: bridgable, in: classDeclaration, isBridgedSubclass: isBridgedSubclass, isMutableStructCopyConstructor: isMutableStructCopyConstructor, uniquifier: uniquifier)
        functionDeclaration.body = bodyCodeBlock
        (functionDeclaration.parent as? KotlinStatement)?.insert(statements: externalStatements, after: functionDeclaration)
        return true
    }

    private func addDefinitions(for functionDeclaration: KotlinFunctionDeclaration, bridgable: FunctionBridgable, in classDeclaration: KotlinClassDeclaration? = nil, isBridgedSubclass: Bool = false, isMutableStructCopyConstructor: Bool = false, isDeclaredByVariable: Bool = false, uniquifier: Int? = nil) -> (KotlinCodeBlock, [KotlinStatement]) {
        let functionName = functionDeclaration.preEscapedName ?? functionDeclaration.name
        let isAsync = functionDeclaration.apiFlags.options.contains(.async)
        let isThrows = functionDeclaration.apiFlags.throwsType != .none
        let isCompanionCall = functionDeclaration.isStatic || (functionDeclaration.type == .constructorDeclaration && isBridgedSubclass)
        let externalName = (isAsync ? "Swift_callback_" : "Swift_") + (isCompanionCall ? "Companion_" + functionName : functionName) + (uniquifier == nil ? "" : "_\(uniquifier!)")

        var cdeclBody: [String] = []
        for index in 0..<bridgable.parameters.count {
            let strategy = bridgable.parameters[index].strategy
            let parameterType = isMutableStructCopyConstructor ? classDeclaration!.signature : bridgable.parameters[index].type
            cdeclBody.append("let p_\(index)_swift = " + parameterType.convertFromCDecl(value: "p_\(index)", strategy: strategy, options: options))
        }

        if isAsync {
            let callbackType = bridgable.return.type.callbackClosureType(apiFlags: functionDeclaration.apiFlags, kotlin: false)
            cdeclBody.append("let f_callback_swift = " + callbackType.convertFromCDecl(value: "f_callback", strategy: .direct, options: options))
        }

        let swiftCallTarget: String
        var externalArgumentsString: String
        if let classDeclaration, functionDeclaration.type != .constructorDeclaration {
            if functionDeclaration.isStatic {
                swiftCallTarget = classDeclaration.name + "."
                externalArgumentsString = ""
            } else {
                if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
                    cdeclBody.append("let peer_swift: \(classDeclaration.signature) = Swift_peer.pointee()!")
                    swiftCallTarget = "peer_swift."
                    externalArgumentsString = "Swift_peer"
                } else if classDeclaration.isSealedClassesEnum {
                    cdeclBody.append("let className_swift = String.fromJavaObject(className, options: \(options.jconvertibleOptions))")
                    cdeclBody.append("let peer_swift = \(classDeclaration.signature).fromJavaClassName(className_swift, Java_target, options: \(options.jconvertibleOptions))")
                    swiftCallTarget = "peer_swift."
                    externalArgumentsString = "javaClass.name"
                } else if classDeclaration.declarationType == .enumDeclaration {
                    cdeclBody.append("let name_swift = String.fromJavaObject(name, options: \(options.jconvertibleOptions))")
                    cdeclBody.append("let peer_swift = \(classDeclaration.signature).fromJavaName(name_swift)")
                    swiftCallTarget = "peer_swift."
                    externalArgumentsString = "name"
                } else {
                    cdeclBody.append("let peer_swift: SwiftValueTypeBox<\(classDeclaration.signature)> = Swift_peer.pointee()!")
                    swiftCallTarget = "peer_swift.value."
                    externalArgumentsString = "Swift_peer"
                }
            }
        } else {
            swiftCallTarget = ""
            externalArgumentsString = ""
        }
        if !functionDeclaration.parameters.isEmpty {
            if !externalArgumentsString.isEmpty {
                externalArgumentsString += ", "
            }
            externalArgumentsString += functionDeclaration.parameters.map(\.internalLabel).joined(separator: ", ")
        }
        let swiftArgumentsString: String
        if isDeclaredByVariable {
            swiftArgumentsString = ""
        } else {
            swiftArgumentsString = "(" + functionDeclaration.parameters.enumerated().map { index, parameter in
                let swiftArgument = "p_\(index)_swift"
                if !isMutableStructCopyConstructor, let externalLabel = functionDeclaration.preEscapedParameterLabels?[index] ?? parameter.externalLabel {
                    return externalLabel + ": " + swiftArgument
                } else {
                    return swiftArgument
                }
            }.joined(separator: ", ") + ")"
        }

        var body: [String] = []
        let cdeclReturnType: TypeSignature
        if let classDeclaration, functionDeclaration.type == .constructorDeclaration {
            if isBridgedSubclass {
                functionDeclaration.delegatingConstructorCall = KotlinRawExpression(sourceCode: "super(Swift_peer = \(externalName)(\(externalArgumentsString)), marker = null)")
            } else {
                body.append("Swift_peer = \(externalName)(\(externalArgumentsString))")
            }
            if isThrows {
                cdeclBody.append("do {")
                if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
                    cdeclBody.append(1, "let f_return_swift = try \(classDeclaration.signature)\(swiftArgumentsString)")
                } else {
                    cdeclBody.append(1, "let f_return_swift = try SwiftValueTypeBox(\(classDeclaration.signature)\(swiftArgumentsString))")
                }
                cdeclBody.append(1, "return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)")
                cdeclBody.append("} catch {")
                cdeclBody.append(1, "JavaThrowError(error, env: Java_env)")
                cdeclBody.append(1, "return SwiftObjectNil")
                cdeclBody.append("}")
            } else {
                if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
                    cdeclBody.append("let f_return_swift = \(classDeclaration.signature)\(swiftArgumentsString)")
                } else if isMutableStructCopyConstructor {
                    cdeclBody.append("let f_return_swift = SwiftValueTypeBox\(swiftArgumentsString)")
                } else {
                    cdeclBody.append("let f_return_swift = SwiftValueTypeBox(\(classDeclaration.signature)\(swiftArgumentsString))")
                }
                cdeclBody.append("return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)")
            }
            cdeclReturnType = .swiftObjectPointer(kotlin: false)
        } else if isAsync {
            body.append("kotlin.coroutines.suspendCoroutine { f_continuation ->")
            if isThrows {
                if bridgable.return.type == .void {
                    body.append(1, externalName + "(\(externalArgumentsString)) { f_error ->")
                } else {
                    body.append(1, externalName + "(\(externalArgumentsString)) { f_return, f_error ->")
                }
                body.append(2, "if (f_error != null) {")
                body.append(3, "f_continuation.resumeWith(kotlin.Result.failure(f_error))")
                body.append(2, "} else {")
                if bridgable.return.type == .void {
                    body.append(3, "f_continuation.resumeWith(kotlin.Result.success(Unit))")
                } else {
                    let forceUnwrapString = bridgable.return.type.isOptional ? "" : "!!"
                    body.append(3, "f_continuation.resumeWith(kotlin.Result.success(f_return\(forceUnwrapString)))")
                }
                body.append(2, "}")
            } else {
                if bridgable.return.type == .void {
                    body.append(1, externalName + "(\(externalArgumentsString)) {")
                    body.append(2, "f_continuation.resumeWith(kotlin.Result.success(Unit))")
                } else {
                    body.append(1, externalName + "(\(externalArgumentsString)) { f_return ->")
                    body.append(2, "f_continuation.resumeWith(kotlin.Result.success(f_return))")
                }
            }
            body.append(1, "}")
            body.append("}")

            cdeclBody.append("Task {")
            if isThrows {
                cdeclBody.append(1, "do {")
                if bridgable.return.type == .void {
                    cdeclBody.append(2, "try await \(swiftCallTarget)\(functionName)\(swiftArgumentsString)")
                    cdeclBody.append(2, "f_callback_swift(nil)")
                } else {
                    cdeclBody.append(2, "let f_return_swift = try await \(swiftCallTarget)\(functionName)\(swiftArgumentsString)")
                    cdeclBody.append(2, "f_callback_swift(f_return_swift, nil)")
                }
                cdeclBody.append(1, "} catch {")
                cdeclBody.append(2, "jniContext {")
                if bridgable.return.type == .void {
                    cdeclBody.append(3, "f_callback_swift(JavaErrorThrowable(error, env: Java_env))")
                } else {
                    cdeclBody.append(3, "f_callback_swift(nil, JavaErrorThrowable(error, env: Java_env))")
                }
                cdeclBody.append(2, "}")
                cdeclBody.append(1, "}")
            } else if bridgable.return.type == .void {
                cdeclBody.append(1, "await \(swiftCallTarget)\(functionName)\(swiftArgumentsString)")
                cdeclBody.append(1, "f_callback_swift()")
            } else {
                cdeclBody.append(1, "let f_return_swift = await \(swiftCallTarget)\(functionName)\(swiftArgumentsString)")
                cdeclBody.append(1, "f_callback_swift(f_return_swift)")
            }
            cdeclBody.append("}")
            cdeclReturnType = .void
        } else if bridgable.return.type == .void {
            body.append(externalName + "(\(externalArgumentsString))")
            if isThrows {
                cdeclBody.append("do {")
                cdeclBody.append(1, "try \(swiftCallTarget)\(functionName)\(swiftArgumentsString)")
                cdeclBody.append("} catch {")
                cdeclBody.append(1, "JavaThrowError(error, env: Java_env)")
                cdeclBody.append("}")
            } else {
                cdeclBody.append(swiftCallTarget + functionName + "\(swiftArgumentsString)")
            }
            cdeclReturnType = .void
        } else {
            let forceUnwrapString: String
            if isThrows {
                forceUnwrapString = bridgable.return.type.isOptional ? "" : "!!"
                cdeclBody.append("do {")
                cdeclBody.append(1, "let f_return_swift = try \(swiftCallTarget)\(functionName)\(swiftArgumentsString)")
                cdeclBody.append(1, "return " + bridgable.return.type.asOptional(true).convertToCDecl(value: "f_return_swift", strategy: bridgable.return.strategy, options: options))
                cdeclBody.append("} catch {")
                cdeclBody.append(1, "JavaThrowError(error, env: Java_env)")
                cdeclBody.append(1, "return nil")
                cdeclBody.append("}")
                cdeclReturnType = bridgable.return.type.asOptional(true).cdecl(strategy: bridgable.return.strategy, options: options)
            } else {
                forceUnwrapString = ""
                cdeclBody.append("let f_return_swift = \(swiftCallTarget)\(functionName)\(swiftArgumentsString)")
                cdeclBody.append("return " + functionDeclaration.returnType.convertToCDecl(value: "f_return_swift", strategy: bridgable.return.strategy, options: options))
                cdeclReturnType = bridgable.return.type.cdecl(strategy: bridgable.return.strategy, options: options)
            }
            body.append("return \(externalName)(\(externalArgumentsString))\(forceUnwrapString)")
        }

        var externalFunctionDeclaration = "private external fun \(externalName)("
        var externalParametersString: String
        if classDeclaration != nil, functionDeclaration.type != .constructorDeclaration && !functionDeclaration.isStatic {
            if classDeclaration?.isSealedClassesEnum == true {
                externalParametersString = "className: String"
            } else if classDeclaration?.declarationType == .enumDeclaration {
                externalParametersString = "name: String"
            } else {
                externalParametersString = "Swift_peer: skip.bridge.kt.SwiftObjectPointer"
            }
        } else {
            externalParametersString = ""
        }
        if !functionDeclaration.parameters.isEmpty {
            if !externalParametersString.isEmpty {
                externalParametersString += ", "
            }
            externalParametersString += functionDeclaration.parameters.enumerated().map { index, parameter in
                return parameter.internalLabel + ": " + bridgable.parameters[index].kotlinType.kotlin
            }.joined(separator: ", ")
        }
        if isAsync {
            if !externalParametersString.isEmpty {
                externalParametersString += ", "
            }
            externalParametersString += "f_callback: " + bridgable.return.kotlinType.callbackClosureType(apiFlags: functionDeclaration.apiFlags, kotlin: true).kotlin
        }
        externalFunctionDeclaration += externalParametersString
        externalFunctionDeclaration += ")"
        if functionDeclaration.type == .constructorDeclaration {
            externalFunctionDeclaration += ": skip.bridge.kt.SwiftObjectPointer"
        } else if bridgable.return.type != .void && !isAsync {
            var returnType = bridgable.return.kotlinType
            if functionDeclaration.apiFlags.throwsType != .none {
                returnType = returnType.asOptional(true)
            }
            externalFunctionDeclaration += ": " + returnType.kotlin
        }

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: functionDeclaration, isCompanion: isCompanionCall, name: externalName, translator: translator)
        let instanceParameter = classDeclaration != nil && functionDeclaration.type != .constructorDeclaration && !functionDeclaration.isStatic ? [cdeclInstanceParameter(for: classDeclaration!)] : []
        let callbackParameter = isAsync ? [TypeSignature.Parameter(label: "f_callback", type: .javaObjectPointer)] : []
        let cdeclType: TypeSignature = .function(instanceParameter + bridgable.parameters.enumerated().map { (index, bridgable) in
            let strategy = bridgable.strategy
            return TypeSignature.Parameter(label: "p_\(index)", type: bridgable.type.cdecl(strategy: strategy, options: options))
        } + callbackParameter, cdeclReturnType, APIFlags(), nil)
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclType, body: cdeclBody)
        cdeclFunctions.append(cdeclFunction)

        let bodyCodeBlock = KotlinCodeBlock(statements: body.map { KotlinRawStatement(sourceCode: $0) })
        let externalStatements = [KotlinRawStatement(sourceCode: externalFunctionDeclaration, isStatic: isCompanionCall)]
        return (bodyCodeBlock, externalStatements)
    }

    private func isGeneratedMemberwiseConstructor(_ functionDeclaration: KotlinFunctionDeclaration, for classDeclaration: KotlinClassDeclaration?) -> Bool {
        guard let classDeclaration, classDeclaration.declarationType == .structDeclaration, functionDeclaration.type == .constructorDeclaration else {
            return false
        }
        guard functionDeclaration.parameters.count != 1 || !functionDeclaration.parameters[0].declaredType.isNamed("MutableStruct") else {
            return false
        }
        return true
    }

    private func updateEqualsDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, in classDeclaration: KotlinClassDeclaration) {
        functionDeclaration.extras = nil
        let bodySourceCode: [String]
        if functionDeclaration.isKotlinEqualImplementation {
            // equals(other:)
            bodySourceCode = [
                "if (other === this) return true",
                "if (other !is \(classDeclaration.signature.kotlin)) return false",
                "return Swift_isequal(this, other)"
            ]
        } else {
            // ==(lhs:, rhs:)
            bodySourceCode = ["return Swift_isequal(lhs, rhs)"]
        }
        functionDeclaration.body = KotlinCodeBlock(statements: bodySourceCode.map { KotlinRawStatement(sourceCode: $0) })

        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: "private external fun Swift_isequal(lhs: \(classDeclaration.signature), rhs: \(classDeclaration.signature)): Boolean")
        classDeclaration.insert(statements: [externalFunctionDeclaration], after: functionDeclaration)

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: functionDeclaration, isCompanion: false, name: "Swift_isequal", translator: translator)
        let cdeclType: TypeSignature = .function([TypeSignature.Parameter(label: "lhs", type: .javaObjectPointer), TypeSignature.Parameter(label: "rhs", type: .javaObjectPointer)], .bool, APIFlags(), nil)
        let cdeclBody: [String] = [
            "let lhs_swift = \(classDeclaration.signature).fromJavaObject(lhs, options: \(options.jconvertibleOptions))",
            "let rhs_swift = \(classDeclaration.signature).fromJavaObject(rhs, options: \(options.jconvertibleOptions))",
            "return lhs_swift == rhs_swift"
        ]
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclType, body: cdeclBody)
        cdeclFunctions.append(cdeclFunction)
    }

    private func defaultEqualsDeclaration() -> KotlinStatement {
        let equals = KotlinFunctionDeclaration(name: "equals")
        equals.parameters = [Parameter<KotlinExpression>(externalLabel: "other", declaredType: .optional(.any))]
        equals.returnType = .bool
        equals.modifiers.visibility = .public
        equals.modifiers.isOverride = true
        equals.ensureLeadingNewlines(1)
        equals.isGenerated = true
        let sourceCode: [String] = [
            "if (other !is skip.bridge.kt.SwiftPeerBridged) return false",
            "return Swift_peer == other.Swift_peer()"
        ]
        equals.body = KotlinCodeBlock(statements: sourceCode.map { KotlinRawStatement(sourceCode: $0) })
        return equals
    }

    private func updateHashDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, in classDeclaration: KotlinClassDeclaration) {
        functionDeclaration.extras = nil
        let bodySourceCode: [String]
        if functionDeclaration.isKotlinHashImplementation {
            // hashCode()
            bodySourceCode = ["return Swift_hashvalue(Swift_peer).hashCode()"]
        } else {
            // hash(into:)
            bodySourceCode = ["hasher.value.combine(Swift_hashvalue(Swift_peer))"]
        }
        functionDeclaration.body = KotlinCodeBlock(statements: bodySourceCode.map { KotlinRawStatement(sourceCode: $0) })

        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: "private external fun Swift_hashvalue(Swift_peer: skip.bridge.kt.SwiftObjectPointer): Long")
        classDeclaration.insert(statements: [externalFunctionDeclaration], after: functionDeclaration)

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: functionDeclaration, isCompanion: false, name: "Swift_hashvalue", translator: translator)
        let cdeclType: TypeSignature = .function([cdeclInstanceParameter(for: classDeclaration)], .int64, APIFlags(), nil)
        var cdeclBody: [String] = []
        if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
            cdeclBody.append("let peer_swift: \(classDeclaration.signature) = Swift_peer.pointee()!")
            cdeclBody.append("return Int64(peer_swift.hashValue)")
        } else {
            cdeclBody.append("let peer_swift: SwiftValueTypeBox<\(classDeclaration.signature)> = Swift_peer.pointee()!")
            cdeclBody.append("return Int64(peer_swift.value.hashValue)")
        }

        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclType, body: cdeclBody)
        cdeclFunctions.append(cdeclFunction)
    }

    private func defaultHashDeclaration() -> KotlinStatement {
        let hash = KotlinFunctionDeclaration(name: "hashCode")
        hash.returnType = .int
        hash.modifiers.visibility = .public
        hash.modifiers.isOverride = true
        hash.ensureLeadingNewlines(1)
        hash.isGenerated = true
        let sourceCode: [String] = [
            "return Swift_peer.hashCode()",
        ]
        hash.body = KotlinCodeBlock(statements: sourceCode.map { KotlinRawStatement(sourceCode: $0) })
        return hash
    }

    private func updateLessThanDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, in classDeclaration: KotlinClassDeclaration) {
        functionDeclaration.extras = nil
        functionDeclaration.body = KotlinCodeBlock(statements: [
            "return Swift_islessthan(lhs, rhs)"
        ].map { KotlinRawStatement(sourceCode: $0) })

        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: "private external fun Swift_islessthan(lhs: \(classDeclaration.signature), rhs: \(classDeclaration.signature)): Boolean")
        classDeclaration.insert(statements: [externalFunctionDeclaration], after: functionDeclaration)

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: functionDeclaration, isCompanion: false, name: "Swift_islessthan", translator: translator)
        let cdeclType: TypeSignature = .function([TypeSignature.Parameter(label: "lhs", type: .javaObjectPointer), TypeSignature.Parameter(label: "rhs", type: .javaObjectPointer)], .bool, APIFlags(), nil)
        let cdeclBody: [String] = [
            "let lhs_swift = \(classDeclaration.signature).fromJavaObject(lhs, options: \(options.jconvertibleOptions))",
            "let rhs_swift = \(classDeclaration.signature).fromJavaObject(rhs, options: \(options.jconvertibleOptions))",
            "return lhs_swift < rhs_swift"
        ]
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclType, body: cdeclBody)
        cdeclFunctions.append(cdeclFunction)
    }

    @discardableResult private func update(_ interfaceDeclaration: KotlinInterfaceDeclaration) -> Bool {
        guard interfaceDeclaration.checkBridgable(direction: .toKotlin, options: options, translator: translator) else {
            return false
        }
        guard let codebaseInfo = translator.codebaseInfo else {
            return false
        }
        interfaceDeclaration.extras = nil
        interfaceDeclaration.inherits = interfaceDeclaration.inherits.filter { $0.isNamed("Comparable") || $0.checkBridgable(direction: .toKotlin, options: options, codebaseInfo: codebaseInfo) != nil }
        for member in interfaceDeclaration.members {
            if let variableDeclaration = member as? KotlinVariableDeclaration {
                _ = variableDeclaration.checkBridgable(direction: .toKotlin, options: options, translator: translator)
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                _ = functionDeclaration.checkBridgable(direction: .toKotlin, options: options, translator: translator)
            }
        }
        return true
    }

    @discardableResult private func update(_ classDeclaration: KotlinClassDeclaration) -> Bool {
        guard !classDeclaration.isGenerated else {
            return false
        }
        guard classDeclaration.checkBridgable(direction: .toKotlin, options: options, translator: translator) else {
            return false
        }
        guard let codebaseInfo = translator.codebaseInfo else {
            return false
        }
        let superclassInfo = classDeclaration.superclassInfo(translator: translator)
        guard superclassInfo?.attributes.isBridgeToSwift != true else {
            classDeclaration.messages.append(.kotlinBridgeSuperclassBridging(classDeclaration, source: translator.syntaxTree.source))
            return false
        }

        // Figure out our subclass depth within the bridged hierarchy. -1 means not inheritable, 0 means base type
        let subclassDepth: Int
        if let superclassInfo, superclassInfo.attributes.isBridgeToKotlin {
            let hierarchy = codebaseInfo.global.inheritanceChainSignatures(forNamed: superclassInfo.signature)
            var depth = 1
            for i in 1..<hierarchy.count {
                if let typeInfo = codebaseInfo.primaryTypeInfo(forNamed: hierarchy[i]), typeInfo.attributes.isBridgeToKotlin {
                    depth += 1
                } else {
                    break
                }
            }
            subclassDepth = depth
        } else if classDeclaration.declarationType == .classDeclaration && !classDeclaration.modifiers.isFinal {
            subclassDepth = 0
        } else {
            subclassDepth = -1
        }
        let maximumDepth = 4
        guard subclassDepth < maximumDepth else {
            classDeclaration.messages.append(.kotlinBridgeToKotlinSubclassDepth(classDeclaration, maximumDepth: maximumDepth, source: translator.syntaxTree.source))
            return false
        }

        classDeclaration.extras = nil
        classDeclaration.inherits = classDeclaration.inherits.filter {
            (classDeclaration.declarationType == .actorDeclaration && $0.isNamed("Actor")) || $0.isNamed("Comparable") || $0.isNamed("MutableStruct") || $0.checkBridgable(direction: .toKotlin, options: options, codebaseInfo: codebaseInfo) != nil }

        var insertStatements: [KotlinStatement] = []
        let isEnum = classDeclaration.declarationType == .enumDeclaration
        if !isEnum {
            if subclassDepth < 1 {
                classDeclaration.inherits.append(.named("skip.bridge.kt.SwiftPeerBridged", []))

                let swiftPeer = KotlinVariableDeclaration(names: ["Swift_peer"], variableTypes: [.swiftObjectPointer(kotlin: true)])
                swiftPeer.role = .property
                swiftPeer.modifiers.visibility = .public
                swiftPeer.apiFlags.options = .writeable
                swiftPeer.declaredType = .swiftObjectPointer(kotlin: true)
                swiftPeer.isGenerated = true
                insertStatements.append(swiftPeer)
            }

            let swiftPeerConstructor = KotlinFunctionDeclaration(name: "constructor")
            swiftPeerConstructor.modifiers.visibility = .public
            swiftPeerConstructor.parameters = [Parameter<KotlinExpression>(externalLabel: "Swift_peer", declaredType: .swiftObjectPointer(kotlin: true)), Parameter<KotlinExpression>(externalLabel: "marker", declaredType: .named("skip.bridge.kt.SwiftPeerMarker", []).asOptional(true))]
            if subclassDepth < 1 {
                swiftPeerConstructor.body = KotlinCodeBlock(statements: [KotlinRawStatement(sourceCode: "this.Swift_peer = Swift_peer")])
            } else {
                swiftPeerConstructor.delegatingConstructorCall = KotlinRawExpression(sourceCode: "super(Swift_peer = Swift_peer, marker = marker)")
            }
            swiftPeerConstructor.ensureLeadingNewlines(1)
            swiftPeerConstructor.isGenerated = true
            insertStatements.append(swiftPeerConstructor)

            if subclassDepth < 1 {
                let finalize = KotlinFunctionDeclaration(name: "finalize")
                finalize.modifiers.visibility = .public
                finalize.body = KotlinCodeBlock(statements: [
                    "Swift_release(Swift_peer)",
                    "Swift_peer = skip.bridge.kt.SwiftObjectNil"
                ].map { KotlinRawStatement(sourceCode: $0) })
                finalize.ensureLeadingNewlines(1)
                finalize.isGenerated = true
                insertStatements.append(finalize)

                let release = KotlinRawStatement(sourceCode: "private external fun Swift_release(Swift_peer: skip.bridge.kt.SwiftObjectPointer)")
                insertStatements.append(release)
            }

            if !classDeclaration.members.contains(where: { $0.type == .constructorDeclaration }) {
                let constructor = KotlinFunctionDeclaration(name: "constructor")
                constructor.modifiers.visibility = .public
                if subclassDepth < 1 {
                    constructor.body = KotlinCodeBlock(statements: [KotlinRawStatement(sourceCode: "Swift_peer = Swift_constructor()")])
                } else {
                    constructor.delegatingConstructorCall = KotlinRawExpression(sourceCode: "super(Swift_peer = Swift_constructor(), marker = null)")
                }
                constructor.ensureLeadingNewlines(1)
                constructor.isGenerated = true
                insertStatements.append(constructor)

                let externalConstructorName = subclassDepth >= 1 ? "Swift_Companion_constructor" : "Swift_constructor"
                let externalConstructor = KotlinRawStatement(sourceCode: "private external fun \(externalConstructorName)(): skip.bridge.kt.SwiftObjectPointer")
                externalConstructor.isStatic = subclassDepth >= 1
                insertStatements.append(externalConstructor)

                let constructorCdecl = CDeclFunction.declaration(for: classDeclaration, isCompanion: subclassDepth >= 1, name: externalConstructorName, translator: translator)
                var constructorBody: [String] = []
                if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
                    constructorBody.append("let f_return_swift = \(classDeclaration.signature)()")
                } else {
                    constructorBody.append("let f_return_swift = SwiftValueTypeBox(\(classDeclaration.signature)())")
                }
                constructorBody.append("return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)")

                cdeclFunctions.append(CDeclFunction(name: constructorCdecl.cdeclFunctionName, cdecl: constructorCdecl.cdecl, signature: .function([], .swiftObjectPointer(kotlin: false), APIFlags(), nil), body: constructorBody))
            }

            if subclassDepth < 1 {
                let bridgedPeer = KotlinFunctionDeclaration(name: "Swift_peer")
                bridgedPeer.returnType = .swiftObjectPointer(kotlin: true)
                bridgedPeer.modifiers.visibility = .public
                bridgedPeer.modifiers.isOverride = true
                bridgedPeer.body = KotlinCodeBlock(statements: [
                    KotlinReturn(expression: KotlinIdentifier(name: "Swift_peer"))
                ])
                bridgedPeer.ensureLeadingNewlines(1)
                bridgedPeer.isGenerated = true
                insertStatements.append(bridgedPeer)

                let releaseCdecl = CDeclFunction.declaration(for: classDeclaration, isCompanion: false, name: "Swift_release", translator: translator)
                var releaseBody: [String] = []
                if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
                    releaseBody.append("Swift_peer.release(as: \(classDeclaration.signature).self)")
                } else {
                    releaseBody.append("Swift_peer.release(as: SwiftValueTypeBox<\(classDeclaration.signature)>.self)")
                }
                cdeclFunctions.append(CDeclFunction(name: releaseCdecl.cdeclFunctionName, cdecl: releaseCdecl.cdecl, signature: .function([cdeclInstanceParameter(for: classDeclaration)], .void, APIFlags(), nil), body: releaseBody))
            }
        }

        var hasEqualsDeclaration = false
        var hasHashDeclaration = false
        var functionCount = 0
        var enumCases: [KotlinEnumCaseDeclaration] = []
        for member in classDeclaration.members {
            if let enumCaseDeclaration = member as? KotlinEnumCaseDeclaration {
                enumCases.append(enumCaseDeclaration)
            } else if let variableDeclaration = member as? KotlinVariableDeclaration {
                update(variableDeclaration, in: classDeclaration)
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                if functionDeclaration.isEqualImplementation || functionDeclaration.isKotlinEqualImplementation {
                    updateEqualsDeclaration(functionDeclaration, in: classDeclaration)
                    hasEqualsDeclaration = true
                } else if functionDeclaration.isHashImplementation || functionDeclaration.isKotlinHashImplementation {
                    updateHashDeclaration(functionDeclaration, in: classDeclaration)
                    hasHashDeclaration = true
                } else if functionDeclaration.isLessThanImplementation {
                    updateLessThanDeclaration(functionDeclaration, in: classDeclaration)
                } else if functionDeclaration.type == .constructorDeclaration, functionDeclaration.attributes.isNoBridge {
                    // The decoder includes all constructors so that we can detect whether the class needs a default
                    // constructor generated, but it marks constructors that shouldn't be bridged
                    classDeclaration.remove(statement: functionDeclaration)
                } else if update(functionDeclaration, in: classDeclaration, isBridgedSubclass: subclassDepth >= 1, uniquifier: functionCount) {
                    functionCount += 1
                }
            }
        }
        if !isEnum && subclassDepth < 1 {
            if !hasEqualsDeclaration {
                let equalsDeclaration = defaultEqualsDeclaration()
                insertStatements.append(equalsDeclaration)
            }
            if !hasHashDeclaration {
                let hashDeclaration = defaultHashDeclaration()
                insertStatements.append(hashDeclaration)
            }
        }

        (classDeclaration.children.first as? KotlinStatement)?.ensureLeadingNewlines(1)
        classDeclaration.insert(statements: insertStatements, after: nil)

        // Conform to `BridgedToKotlin`
        let classRef = JavaClassRef(for: classDeclaration.signature, packageName: translator.packageName)
        let conformances: String
        switch subclassDepth {
        case -1:
            conformances = "BridgedToKotlin"
        case 0:
            conformances = "BridgedToKotlin, BridgedToKotlinBaseClass"
        default:
            conformances = "BridgedToKotlinSubclass\(subclassDepth)"
        }
        var swift: [String] = []
        swift.append("extension \(classDeclaration.signature): \(conformances) {")
        swift.append(1, classRef.declaration)

        let finalMemberVisibility = classDeclaration.modifiers.visibility > .public ? .public : classDeclaration.modifiers.visibility
        if isEnum {
            swift.append(1, "private static let Java_Companion_class = try! JClass(name: \"\(classRef.className)$Companion\")")
            swift.append(1, "private static let Java_Companion = JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: \"Companion\", sig: \"L\(classRef.className)$Companion;\")!, options: \(options.jconvertibleOptions)))")
            swift.append(1, KotlinBridgeToSwiftVisitor.swiftForEnumJConvertibleContract(className: classRef.className, isSealedClassesEnum: classDeclaration.isSealedClassesEnum, caseDeclarations: enumCases, visibility: finalMemberVisibility, options: options, translator: translator))
        } else {
            let finalMemberVisibilityString = finalMemberVisibility.swift(suffix: " ")
            if subclassDepth < 1 {
                swift.append(1, "\(finalMemberVisibilityString)static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {")
                swift.append(2, "let ptr = SwiftObjectPointer.peer(of: obj!, options: options)")
                if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
                    swift.append(2, "return ptr.pointee()!")
                } else {
                    swift.append(2, "let box: SwiftValueTypeBox<Self> = ptr.pointee()!")
                    swift.append(2, "return box.value")
                }
                swift.append(1, "}")

                let isolation = classDeclaration.declarationType == .actorDeclaration ? "nonisolated " : ""
                swift.append(1, "\(finalMemberVisibilityString)\(isolation)func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {")
                if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
                    swift.append(2, "let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)")
                } else {
                    swift.append(2, "let box = SwiftValueTypeBox(self)")
                    swift.append(2, "let Swift_peer = SwiftObjectPointer.pointer(to: box, retain: true)")
                }
                if subclassDepth == 0 {
                    swift.append(2, "let constructor = Java_findConstructor(base: Self.Java_class, Self.Java_constructor_methodID)")
                    swift.append(2, "return try! constructor.cls.create(ctor: constructor.ctor, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])")
                } else {
                    swift.append(2, "return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])")
                }
                swift.append(1, "}")
            }
            swift.append(1, "private static let Java_constructor_methodID = Java_class.getMethodID(name: \"<init>\", sig: \"(JLskip/bridge/kt/SwiftPeerMarker;)V\")!")
            if subclassDepth >= 1 {
                swift.append(1, "public static let Java_subclass\(subclassDepth)Constructor = (Java_class, Java_constructor_methodID)")
            }
        }
        swift.append("}")

        let swiftDefinition = SwiftDefinition(swift: swift)
        swiftDefinitions.append(swiftDefinition)

        let cdeclFunction = KotlinBridgeToSwiftVisitor.addSwiftProjecting(to: classDeclaration, isBridgedSubclass: subclassDepth >= 1, options: options, translator: translator)
        cdeclFunctions.append(cdeclFunction)
        return true
    }

    private func cdeclInstanceParameter(for classDeclaration: KotlinClassDeclaration) -> TypeSignature.Parameter {
        if classDeclaration.isSealedClassesEnum {
            return TypeSignature.Parameter(label: "className", type: .javaString)
        } else if classDeclaration.declarationType == .enumDeclaration {
            return TypeSignature.Parameter(label: "name", type: .javaString)
        } else {
            return TypeSignature.Parameter(label: "Swift_peer", type: .swiftObjectPointer(kotlin: false))
        }
    }
}
