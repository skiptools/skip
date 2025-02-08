/// Generate compiled Swift to Kotlin bridging code.
///
/// - Warning: This visitor assumes that the given syntax tree only contains bridged API.
final class KotlinBridgeToKotlinVisitor {
    private let syntaxTree: KotlinSyntaxTree
    private let options: KotlinBridgeOptions
    private let translator: KotlinTranslator
    private let codebaseInfo: CodebaseInfo.Context
    private let includesUI: Bool
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
        self.includesUI = syntaxTree.root.statements.compactMap({ $0 as? KotlinImportDeclaration }).contains { $0.modulePath.first == "SkipFuseUI" }
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
                    if let bridgeImpl = KotlinBridgeToSwiftVisitor.protocolBridgeImplDefinition(forProtocol: interfaceDeclaration.signature, inPackage: translator.packageName, statement: interfaceDeclaration, options: options, autoBridge: syntaxTree.autoBridge, codebaseInfo: codebaseInfo) {
                        swiftDefinitions.append(bridgeImpl)
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
        return codebaseInfo.global.dependentModules.contains { moduleName == $0.moduleName && !$0.isEmpty }
    }

    @discardableResult private func update(_ variableDeclaration: KotlinVariableDeclaration, in classDeclaration: KotlinClassDeclaration? = nil, inExtensionOf interfaceDeclaration: KotlinInterfaceDeclaration? = nil) -> Bool {
        guard !variableDeclaration.isGenerated else {
            return false
        }
        guard let bridgable = variableDeclaration.checkBridgable(direction: .toKotlin, options: options, translator: translator) else {
            return false
        }
        variableDeclaration.extras = nil
        // If this is a let constant with a supported literal value, we'll re-declare rather than bridge it
        guard !isSupportedConstant(variableDeclaration, type: bridgable.type) else {
            return false
        }

        let propertyName = variableDeclaration.preEscapedPropertyName ?? variableDeclaration.propertyName
        guard !variableDeclaration.isAppendAsFunction else {
            let functionDeclaration = KotlinFunctionDeclaration(name: propertyName, sourceFile: variableDeclaration.sourceFile, sourceRange: variableDeclaration.sourceRange)
            functionDeclaration.returnType = variableDeclaration.propertyType
            functionDeclaration.role = variableDeclaration.role == .global ? .global : .member
            functionDeclaration.modifiers = variableDeclaration.modifiers
            functionDeclaration.attributes = variableDeclaration.attributes
            functionDeclaration.apiFlags = variableDeclaration.apiFlags
            functionDeclaration.parent = classDeclaration ?? interfaceDeclaration

            let functionBridgable = FunctionBridgable(parameters: [], return: bridgable)
            let (bodyCodeBlock, externalStatements) = addDefinitions(for: functionDeclaration, bridgable: functionBridgable, in: classDeclaration, inExtensionOf: interfaceDeclaration, isDeclaredByVariable: true)
            variableDeclaration.getter = Accessor(body: bodyCodeBlock)
            let parent = interfaceDeclaration?.parent ?? variableDeclaration.parent
            (parent as? KotlinStatement)?.insert(statements: externalStatements, after: interfaceDeclaration ?? variableDeclaration)
            return true
        }

        // Remove initial value and make sure type is declared
        variableDeclaration.value = nil
        variableDeclaration.declaredType = bridgable.kotlinType

        let externalName = "Swift_" + (interfaceDeclaration == nil ? "" : interfaceDeclaration!.name + "_") + (variableDeclaration.isStatic ? "Companion_" : "") + propertyName
        var externalFunctionDeclarations: [String] = []
        let (cdecl, cdeclName) = CDeclFunction.declaration(for: variableDeclaration, isCompanion: variableDeclaration.isStatic, name: externalName, translator: translator)

        // Getter
        let isInstance = classDeclaration != nil && !variableDeclaration.isStatic
        let isProtocolInstance = interfaceDeclaration != nil && !variableDeclaration.isStatic
        let isBasicEnum = classDeclaration?.declarationType == .enumDeclaration && classDeclaration?.isSealedClassesEnum == false
        let isNonGenericSealedClassesEnum = classDeclaration?.isSealedClassesEnum == true && classDeclaration?.generics.isEmpty != false
        let getterArguments: String
        let getterParameters: String
        if isInstance {
            getterArguments = isNonGenericSealedClassesEnum ? "(javaClass.name)" : isBasicEnum ? "(name)" : "(Swift_peer)"
            getterParameters = isNonGenericSealedClassesEnum ? "(className: String)" : isBasicEnum ? "(name: String)" : "(Swift_peer: skip.bridge.kt.SwiftObjectPointer)"
        } else if isProtocolInstance {
            getterArguments = "(this)"
            getterParameters = "(Java_iface: \(interfaceDeclaration!.name))"
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
        let castString = bridgable.genericType == nil ? "" : " as \(bridgable.kotlinType.kotlin)"
        let getterBody: [String]
        if bridgable.genericType == nil {
            getterBody = [
                "return \(externalName)\(getterArguments)\(forceUnwrapString)\(getterSref)"
            ]
        } else {
            getterBody = [
                "return (\(externalName)\(getterArguments)\(forceUnwrapString)\(castString))\(getterSref)"
            ]
        }
        variableDeclaration.getter = Accessor(body: KotlinCodeBlock(statements: getterBody.map { KotlinRawStatement(sourceCode: $0) }))
        externalFunctionDeclarations.append("private external fun \(externalName)\(getterParameters): \(bridgable.externalType.asOptional(asOptional).kotlin)")

        let cdeclInstanceParameters: [TypeSignature.Parameter]
        var cdeclGetterBody: [String] = []
        let valueString: String
        let optionsString = options.jconvertibleOptions
        if let classDeclaration {
            if isInstance {
                if !classDeclaration.generics.isEmpty {
                    cdeclGetterBody.append("let peer_swift: \(classDeclaration.signature.typeErasedClass) = Swift_peer.pointee()!")
                    valueString = bridgable.type.convertToCDecl(value: "peer_swift.get_\(propertyName)()", strategy: bridgable.strategy, options: options)
                } else if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
                    cdeclGetterBody.append("let peer_swift: \(classDeclaration.signature) = Swift_peer.pointee()!")
                    valueString = bridgable.type.convertToCDecl(value: "peer_swift.\(propertyName)", strategy: bridgable.strategy, options: options)
                } else if isNonGenericSealedClassesEnum {
                    cdeclGetterBody.append("let className_swift = String.fromJavaObject(className, options: \(optionsString))")
                    cdeclGetterBody.append("let peer_swift = \(classDeclaration.signature).fromJavaClassName(className_swift, Java_target, options: \(optionsString))")
                    valueString = bridgable.type.convertToCDecl(value: "peer_swift.\(propertyName)", strategy: bridgable.strategy, options: options)
                } else if isBasicEnum {
                    cdeclGetterBody.append("let name_swift = String.fromJavaObject(name, options: \(optionsString))")
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
        } else if let interfaceDeclaration {
            if isProtocolInstance {
                cdeclGetterBody.append("let peer_swift = AnyBridging.fromJavaObject(Java_iface, options: \(optionsString)) as! any \(interfaceDeclaration.name)")
                valueString = bridgable.type.convertToCDecl(value: "peer_swift.\(propertyName)", strategy: bridgable.strategy, options: options)
                cdeclInstanceParameters = [TypeSignature.Parameter(label: "Java_iface", type: .javaObjectPointer)]
            } else {
                valueString = bridgable.type.convertToCDecl(value: "\(interfaceDeclaration.name).\(propertyName)", strategy: bridgable.strategy, options: options)
                cdeclInstanceParameters = []
            }
        } else {
            valueString = bridgable.type.convertToCDecl(value: propertyName, strategy: bridgable.strategy, options: options)
            cdeclInstanceParameters = []
        }
        if variableDeclaration.apiFlags.throwsType == .none {
            appendMainActorIsolated(&cdeclGetterBody, isolated: variableDeclaration.apiFlags.options.contains(.mainActor), isReturn: true) { body, indentation in
                body.append(indentation, "return " + valueString)
            }
        } else {
            cdeclGetterBody.append("do {")
            appendMainActorIsolated(&cdeclGetterBody, 1, isolated: variableDeclaration.apiFlags.options.contains(.mainActor), isThrows: true, isReturn: true) { body, indentation in
                body.append(indentation, "let f_return_swift = try " + valueString)
                body.append(indentation, "return f_return_swift.toJavaObject(options: \(optionsString))")
            }
            cdeclGetterBody.append("} catch {")
            cdeclGetterBody.append(1, "JThrowable.throw(error, options: \(optionsString), env: Java_env)")
            cdeclGetterBody.append(1, "return nil")
            cdeclGetterBody.append("}")
        }
        let cdeclGetter = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: .function(cdeclInstanceParameters, bridgable.type.asOptional(asOptional).cdecl(strategy: bridgable.strategy, options: options), APIFlags(), nil), body: cdeclGetterBody)
        cdeclFunctions.append(cdeclGetter)

        // Setter
        if variableDeclaration.apiFlags.options.contains(.writeable) {
            let castString = bridgable.genericType == nil ? "" : " as \(TypeSignature.any.asOptional(bridgable.type.isOptional).kotlin)"
            let setterArguments: String
            let setterInstanceParameter: String
            if isInstance {
                setterArguments = isNonGenericSealedClassesEnum ? "javaClass.name, newValue\(castString)" : isBasicEnum ? "name, newValue\(castString)" : "Swift_peer, newValue\(castString)"
                setterInstanceParameter = isNonGenericSealedClassesEnum ? "className: String, " : isBasicEnum ? "name: String, " : "Swift_peer: skip.bridge.kt.SwiftObjectPointer, "
            } else if isProtocolInstance {
                setterArguments = "this, newValue\(castString)"
                setterInstanceParameter = "Java_iface: \(interfaceDeclaration!.name), "
            } else {
                setterArguments = "newValue\(castString)"
                setterInstanceParameter = ""
            }
            let setterBody = [
                externalName + "_set(" + setterArguments + ")"
            ]
            variableDeclaration.setter = Accessor(parameterName: "newValue", body: KotlinCodeBlock(statements: setterBody.map { KotlinRawStatement(sourceCode: $0) }))
            externalFunctionDeclarations.append("private external fun \(externalName)_set(\(setterInstanceParameter)value: \(bridgable.externalType.kotlin))")

            var cdeclSetterBody: [String] = []
            let setValueString: String
            if let classDeclaration {
                if isInstance {
                    if !classDeclaration.generics.isEmpty {
                        cdeclSetterBody.append("let peer_swift: \(classDeclaration.signature.typeErasedClass) = Swift_peer.pointee()!")
                        setValueString = "peer_swift.set_\(propertyName)(" + bridgable.constrainedType.convertFromCDecl(value: "value", strategy: bridgable.strategy, options: options) + ")"
                    } else if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
                        cdeclSetterBody.append("let peer_swift: \(classDeclaration.signature) = Swift_peer.pointee()!")
                        setValueString = "peer_swift.\(propertyName) = " + bridgable.constrainedType.convertFromCDecl(value: "value", strategy: bridgable.strategy, options: options)
                    } else if isNonGenericSealedClassesEnum {
                        cdeclSetterBody.append("let className_swift = String.fromJavaObject(className, options: \(optionsString))")
                        cdeclSetterBody.append("let peer_swift = \(classDeclaration.signature).fromJavaClassName(className_swift, Java_target, options: \(optionsString))")
                        setValueString = "peer_swift.\(propertyName) = " + bridgable.constrainedType.convertFromCDecl(value: "value", strategy: bridgable.strategy, options: options)
                    } else if isBasicEnum {
                        cdeclSetterBody.append("let name_swift = String.fromJavaObject(name, options: \(optionsString))")
                        cdeclSetterBody.append("let peer_swift = \(classDeclaration.signature).fromJavaName(name_swift)")
                        setValueString = "peer_swift.\(propertyName) = " + bridgable.constrainedType.convertFromCDecl(value: "value", strategy: bridgable.strategy, options: options)
                    } else {
                        cdeclSetterBody.append("let peer_swift: SwiftValueTypeBox<\(classDeclaration.signature)> = Swift_peer.pointee()!")
                        setValueString = "peer_swift.value.\(propertyName) = " + bridgable.constrainedType.convertFromCDecl(value: "value", strategy: bridgable.strategy, options: options)
                    }
                } else {
                    setValueString = "\(classDeclaration.signature).\(propertyName) = " + bridgable.constrainedType.convertFromCDecl(value: "value", strategy: bridgable.strategy, options: options)
                }
            } else if let interfaceDeclaration {
                if isProtocolInstance {
                    cdeclSetterBody.append("let peer_swift = AnyBridging.fromJavaObject(Java_iface, options: \(optionsString)) as! any \(interfaceDeclaration.name)")
                    setValueString = "peer_swift.\(propertyName) = " + bridgable.constrainedType.convertFromCDecl(value: "value", strategy: bridgable.strategy, options: options)
                } else {
                    setValueString = "\(interfaceDeclaration.name).\(propertyName) = " + bridgable.constrainedType.convertFromCDecl(value: "value", strategy: bridgable.strategy, options: options)
                }
            } else {
                setValueString = propertyName + " = " + bridgable.constrainedType.convertFromCDecl(value: "value", strategy: bridgable.strategy, options: options)
            }
            appendMainActorIsolated(&cdeclSetterBody, isolated: variableDeclaration.apiFlags.options.contains(.mainActor)) { body, indentation in
                body.append(indentation, setValueString)
            }
            let cdeclSetter = CDeclFunction(name: cdeclName + "_set", cdecl: cdecl + "_1set", signature: .function(cdeclInstanceParameters + [TypeSignature.Parameter(label: "value", type: bridgable.type.cdecl(strategy: bridgable.strategy, options: options))], .void, APIFlags(), nil), body: cdeclSetterBody)
            cdeclFunctions.append(cdeclSetter)
        }
        variableDeclaration.willSet = nil
        variableDeclaration.didSet = nil

        // Add function declarations to transpiled output
        let parent = interfaceDeclaration?.parent ?? variableDeclaration.parent
        (parent as? KotlinStatement)?.insert(statements: externalFunctionDeclarations.map { KotlinRawStatement(sourceCode: $0, isStatic: variableDeclaration.isStatic) }, after: interfaceDeclaration ?? variableDeclaration)
        return true
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

    private func update(_ functionDeclaration: KotlinFunctionDeclaration, in classDeclaration: KotlinClassDeclaration? = nil, isBridgedSubclass: Bool = false, inExtensionOf interfaceDeclaration: KotlinInterfaceDeclaration? = nil, uniquifier: Int) -> Bool {
        guard !functionDeclaration.isGenerated || functionDeclaration.type == .constructorDeclaration else {
            return false
        }
        let isMutableStructCopyConstructor = classDeclaration != nil && functionDeclaration.isMutableStructCopyConstructor
        let bridgable: FunctionBridgable
        if isMutableStructCopyConstructor {
            let parameterBridgable = Bridgable(type: .named("MutableStruct", []), kotlinType: .module("Swift", .named("MutableStruct", [])), genericType: nil, strategy: .peer)
            bridgable = FunctionBridgable(parameters: [parameterBridgable], return: Bridgable(type: .void, kotlinType: .void, genericType: nil, strategy: .direct))
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
        functionDeclaration.generics = functionDeclaration.generics.filterBridging(codebaseInfo: codebaseInfo)

        let (bodyCodeBlock, externalStatements) = addDefinitions(for: functionDeclaration, bridgable: bridgable, in: classDeclaration, isBridgedSubclass: isBridgedSubclass, inExtensionOf: interfaceDeclaration, isMutableStructCopyConstructor: isMutableStructCopyConstructor, uniquifier: uniquifier)
        functionDeclaration.body = bodyCodeBlock

        let parent = interfaceDeclaration?.parent ?? functionDeclaration.parent
        (parent as? KotlinStatement)?.insert(statements: externalStatements, after: interfaceDeclaration ?? functionDeclaration)
        return true
    }

    private func addDefinitions(for functionDeclaration: KotlinFunctionDeclaration, bridgable: FunctionBridgable, in classDeclaration: KotlinClassDeclaration? = nil, isBridgedSubclass: Bool = false, inExtensionOf interfaceDeclaration: KotlinInterfaceDeclaration? = nil, isMutableStructCopyConstructor: Bool = false, isDeclaredByVariable: Bool = false, uniquifier: Int? = nil) -> (KotlinCodeBlock, [KotlinStatement]) {
        let functionName = functionDeclaration.preEscapedName ?? functionDeclaration.name
        let isAsync = functionDeclaration.apiFlags.options.contains(.async)
        let isThrows = functionDeclaration.apiFlags.throwsType != .none
        let isCompanionCall = functionDeclaration.isStatic || (functionDeclaration.type == .constructorDeclaration && isBridgedSubclass)
        let externalName = (isAsync ? "Swift_callback_" : "Swift_") + (interfaceDeclaration == nil ? "" : interfaceDeclaration!.name + "_") + (isCompanionCall ? "Companion_" : "") + functionName + (uniquifier == nil ? "" : "_\(uniquifier!)")

        var cdeclBody: [String] = []
        if !isMutableStructCopyConstructor || classDeclaration?.generics.isEmpty != false {
            for index in 0..<bridgable.parameters.count {
                let strategy = bridgable.parameters[index].strategy
                let parameterType = isMutableStructCopyConstructor ? classDeclaration!.signature : bridgable.parameters[index].constrainedType
                cdeclBody.append("let p_\(index)_swift = " + parameterType.convertFromCDecl(value: "p_\(index)", strategy: strategy, options: options))
            }
        }

        if isAsync {
            let callbackType = bridgable.return.constrainedType.callbackClosureType(apiFlags: functionDeclaration.apiFlags, kotlin: false)
            cdeclBody.append("let f_callback_swift = " + callbackType.convertFromCDecl(value: "f_callback", strategy: .direct, options: options))
        }

        let swiftCallTarget: String
        var externalArgumentsString: String
        var swiftFunctionName = functionName
        let optionsString = options.jconvertibleOptions
        if let classDeclaration, functionDeclaration.type != .constructorDeclaration {
            if functionDeclaration.isStatic {
                swiftCallTarget = classDeclaration.name + "."
                externalArgumentsString = ""
            } else {
                if !classDeclaration.generics.isEmpty {
                    cdeclBody.append("let peer_swift: \(classDeclaration.signature.typeErasedClass) = Swift_peer.pointee()!")
                    swiftCallTarget = "peer_swift."
                    swiftFunctionName += uniquifier == nil ? "" : "_\(uniquifier!)"
                    externalArgumentsString = "Swift_peer"
                } else if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
                    cdeclBody.append("let peer_swift: \(classDeclaration.signature) = Swift_peer.pointee()!")
                    swiftCallTarget = "peer_swift."
                    externalArgumentsString = "Swift_peer"
                } else if classDeclaration.isSealedClassesEnum {
                    cdeclBody.append("let className_swift = String.fromJavaObject(className, options: \(optionsString))")
                    cdeclBody.append("let peer_swift = \(classDeclaration.signature).fromJavaClassName(className_swift, Java_target, options: \(optionsString))")
                    swiftCallTarget = "peer_swift."
                    externalArgumentsString = "javaClass.name"
                } else if classDeclaration.declarationType == .enumDeclaration {
                    cdeclBody.append("let name_swift = String.fromJavaObject(name, options: \(optionsString))")
                    cdeclBody.append("let peer_swift = \(classDeclaration.signature).fromJavaName(name_swift)")
                    swiftCallTarget = "peer_swift."
                    externalArgumentsString = "name"
                } else {
                    cdeclBody.append("let peer_swift: SwiftValueTypeBox<\(classDeclaration.signature)> = Swift_peer.pointee()!")
                    swiftCallTarget = "peer_swift.value."
                    externalArgumentsString = "Swift_peer"
                }
            }
        } else if let interfaceDeclaration {
            if functionDeclaration.isStatic {
                swiftCallTarget = interfaceDeclaration.name + "."
                externalArgumentsString = ""
            } else {
                cdeclBody.append("let peer_swift = AnyBridging.fromJavaObject(Java_iface, options: \(optionsString)) as! any \(interfaceDeclaration.name)")
                swiftCallTarget = "peer_swift."
                externalArgumentsString = "this"
            }
        } else {
            swiftCallTarget = ""
            externalArgumentsString = ""
        }
        if !functionDeclaration.parameters.isEmpty {
            if !externalArgumentsString.isEmpty {
                externalArgumentsString += ", "
            }
            externalArgumentsString += zip(functionDeclaration.parameters, bridgable.parameters).map { parameter, bridgable in
                return bridgable.genericType == nil ? parameter.internalLabel : "\(parameter.internalLabel) as \(TypeSignature.any.asOptional(bridgable.type.isOptional).kotlin)"
            }.joined(separator: ", ")
        }
        let swiftArgumentsString: String
        if isDeclaredByVariable {
            swiftArgumentsString = ""
        } else {
            swiftArgumentsString = "(" + functionDeclaration.parameters.enumerated().map { index, parameter in
                let swiftArgument = "p_\(index)_swift"
                if !isMutableStructCopyConstructor, classDeclaration?.generics.isEmpty != false, let externalLabel = functionDeclaration.preEscapedParameterLabels?[index] ?? parameter.externalLabel {
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
                cdeclBody.append(1, "JThrowable.throw(error, options: \(optionsString), env: Java_env)")
                cdeclBody.append(1, "return SwiftObjectNil")
                cdeclBody.append("}")
            } else {
                if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
                    cdeclBody.append("let f_return_swift = \(classDeclaration.signature)\(swiftArgumentsString)")
                } else if isMutableStructCopyConstructor && !classDeclaration.generics.isEmpty {
                    // Create a new type-erased wrapper using the original instance
                    cdeclBody.append("let ptr = SwiftObjectPointer.peer(of: p_0, options: \(optionsString))")
                    cdeclBody.append("let peer_swift: \(classDeclaration.signature.typeErasedClass) = ptr.pointee()!")
                    cdeclBody.append("let f_return_swift = (peer_swift.genericvalue as! TypeErasedConvertible).toTypeErased()")
                } else if isMutableStructCopyConstructor {
                    cdeclBody.append("let f_return_swift = SwiftValueTypeBox\(swiftArgumentsString)")
                } else {
                    cdeclBody.append("let f_return_swift = SwiftValueTypeBox(\(classDeclaration.signature)\(swiftArgumentsString))")
                }
                cdeclBody.append("return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)")
            }
            cdeclReturnType = .swiftObjectPointer(kotlin: false)
        } else if isAsync {
            let castString = bridgable.return.genericType == nil ? "" : " as \(bridgable.return.kotlinType.kotlin)"
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
                    body.append(3, "f_continuation.resumeWith(kotlin.Result.success(f_return\(forceUnwrapString)\(castString)))")
                }
                body.append(2, "}")
            } else {
                if bridgable.return.type == .void {
                    body.append(1, externalName + "(\(externalArgumentsString)) {")
                    body.append(2, "f_continuation.resumeWith(kotlin.Result.success(Unit))")
                } else {
                    body.append(1, externalName + "(\(externalArgumentsString)) { f_return ->")
                    body.append(2, "f_continuation.resumeWith(kotlin.Result.success(f_return\(castString)))")
                }
            }
            body.append(1, "}")
            body.append("}")

            cdeclBody.append("Task {")
            if isThrows {
                cdeclBody.append(1, "do {")
                if bridgable.return.type == .void {
                    cdeclBody.append(2, "try await \(swiftCallTarget)\(swiftFunctionName)\(swiftArgumentsString)")
                    cdeclBody.append(2, "f_callback_swift(nil)")
                } else {
                    cdeclBody.append(2, "let f_return_swift = try await \(swiftCallTarget)\(swiftFunctionName)\(swiftArgumentsString)")
                    cdeclBody.append(2, "f_callback_swift(f_return_swift, nil)")
                }
                cdeclBody.append(1, "} catch {")
                cdeclBody.append(2, "jniContext {")
                if bridgable.return.type == .void {
                    cdeclBody.append(3, "f_callback_swift(JThrowable.toThrowable(error, options: \(optionsString)))")
                } else {
                    cdeclBody.append(3, "f_callback_swift(nil, JThrowable.toThrowable(error, options: \(optionsString)))")
                }
                cdeclBody.append(2, "}")
                cdeclBody.append(1, "}")
            } else if bridgable.return.type == .void {
                cdeclBody.append(1, "await \(swiftCallTarget)\(swiftFunctionName)\(swiftArgumentsString)")
                cdeclBody.append(1, "f_callback_swift()")
            } else {
                cdeclBody.append(1, "let f_return_swift = await \(swiftCallTarget)\(swiftFunctionName)\(swiftArgumentsString)")
                cdeclBody.append(1, "f_callback_swift(f_return_swift)")
            }
            cdeclBody.append("}")
            cdeclReturnType = .void
        } else if bridgable.return.type == .void {
            body.append(externalName + "(\(externalArgumentsString))")
            if isThrows {
                cdeclBody.append("do {")
                appendMainActorIsolated(&cdeclBody, 1, isolated: functionDeclaration.apiFlags.options.contains(.mainActor), isThrows: true) { body, indentation in
                    body.append(indentation, "try \(swiftCallTarget)\(swiftFunctionName)\(swiftArgumentsString)")
                }
                cdeclBody.append("} catch {")
                cdeclBody.append(1, "JThrowable.throw(error, options: \(optionsString), env: Java_env)")
                cdeclBody.append("}")
            } else {
                cdeclBody.append("\(swiftCallTarget)\(swiftFunctionName)\(swiftArgumentsString)")
            }
            cdeclReturnType = .void
        } else {
            let forceUnwrapString: String
            if isThrows {
                forceUnwrapString = bridgable.return.type.isOptional ? "" : "!!"
                cdeclBody.append("do {")
                appendMainActorIsolated(&cdeclBody, 1, isolated: functionDeclaration.apiFlags.options.contains(.mainActor), isThrows: true, isReturn: true) { body, indentation in
                    body.append(indentation, "let f_return_swift = try \(swiftCallTarget)\(swiftFunctionName)\(swiftArgumentsString)")
                    body.append(indentation, "return " + bridgable.return.type.asOptional(true).convertToCDecl(value: "f_return_swift", strategy: bridgable.return.strategy, options: options))
                }
                cdeclBody.append("} catch {")
                cdeclBody.append(1, "JThrowable.throw(error, options: \(optionsString), env: Java_env)")
                cdeclBody.append(1, "return nil")
                cdeclBody.append("}")
                cdeclReturnType = bridgable.return.type.asOptional(true).cdecl(strategy: bridgable.return.strategy, options: options)
            } else {
                forceUnwrapString = ""
                appendMainActorIsolated(&cdeclBody, isolated: functionDeclaration.apiFlags.options.contains(.mainActor), isReturn: true) { body, indentation in
                    body.append(indentation, "let f_return_swift = \(swiftCallTarget)\(swiftFunctionName)\(swiftArgumentsString)")
                    body.append(indentation, "return " + functionDeclaration.returnType.convertToCDecl(value: "f_return_swift", strategy: bridgable.return.strategy, options: options))
                }
                cdeclReturnType = bridgable.return.type.cdecl(strategy: bridgable.return.strategy, options: options)
            }
            let castString = bridgable.return.genericType == nil ? "" : " as \(bridgable.return.kotlinType.kotlin)"
            body.append("return \(externalName)(\(externalArgumentsString))\(forceUnwrapString)\(castString)")
        }

        var externalFunctionDeclaration = "private external fun \(externalName)("
        var externalParametersString: String
        if classDeclaration != nil, functionDeclaration.type != .constructorDeclaration && !functionDeclaration.isStatic {
            if classDeclaration?.generics.isEmpty == false {
                externalParametersString = "Swift_peer: skip.bridge.kt.SwiftObjectPointer"
            } else if classDeclaration?.isSealedClassesEnum == true {
                externalParametersString = "className: String"
            } else if classDeclaration?.declarationType == .enumDeclaration {
                externalParametersString = "name: String"
            } else {
                externalParametersString = "Swift_peer: skip.bridge.kt.SwiftObjectPointer"
            }
        } else if let interfaceDeclaration, !functionDeclaration.isStatic {
            externalParametersString = "Java_iface: \(interfaceDeclaration.name)"
        } else {
            externalParametersString = ""
        }
        if !functionDeclaration.parameters.isEmpty {
            if !externalParametersString.isEmpty {
                externalParametersString += ", "
            }
            externalParametersString += functionDeclaration.parameters.enumerated().map { index, parameter in
                return parameter.internalLabel + ": " + bridgable.parameters[index].externalType.kotlin
            }.joined(separator: ", ")
        }
        if isAsync {
            if !externalParametersString.isEmpty {
                externalParametersString += ", "
            }
            externalParametersString += "f_callback: " + bridgable.return.externalType.callbackClosureType(apiFlags: functionDeclaration.apiFlags, kotlin: true).kotlin
        }
        externalFunctionDeclaration += externalParametersString
        externalFunctionDeclaration += ")"
        if functionDeclaration.type == .constructorDeclaration {
            externalFunctionDeclaration += ": skip.bridge.kt.SwiftObjectPointer"
        } else if bridgable.return.type != .void && !isAsync {
            var returnType: TypeSignature = bridgable.return.externalType
            if functionDeclaration.apiFlags.throwsType != .none {
                returnType = returnType.asOptional(true)
            }
            externalFunctionDeclaration += ": " + returnType.kotlin
        }

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: functionDeclaration, isCompanion: isCompanionCall, name: externalName, translator: translator)
        let instanceParameter: [TypeSignature.Parameter]
        if classDeclaration != nil && functionDeclaration.type != .constructorDeclaration && !functionDeclaration.isStatic { instanceParameter = [cdeclInstanceParameter(for: classDeclaration!)]
        } else if interfaceDeclaration != nil, !functionDeclaration.isStatic {
            instanceParameter = [TypeSignature.Parameter(label: "Java_iface", type: .javaObjectPointer)]
        } else {
            instanceParameter = []
        }
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
        let anyGenerics = classDeclaration.signature.generics.map { _ in TypeSignature.any }
        let classWithAnyGenerics = classDeclaration.signature.withGenerics(anyGenerics)
        let bodySourceCode: [String]
        if functionDeclaration.isKotlinEqualImplementation {
            // equals(other:)
            bodySourceCode = [
                "if (other === this) return true",
                "if (other !is \(classWithAnyGenerics.kotlin)) return false",
                "return Swift_isequal(this, other)"
            ]
        } else {
            // ==(lhs:, rhs:)
            bodySourceCode = ["return Swift_isequal(lhs, rhs)"]
        }
        functionDeclaration.body = KotlinCodeBlock(statements: bodySourceCode.map { KotlinRawStatement(sourceCode: $0) })

        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: "private external fun Swift_isequal(lhs: \(classWithAnyGenerics), rhs: \(classWithAnyGenerics)): Boolean")
        classDeclaration.insert(statements: [externalFunctionDeclaration], after: functionDeclaration)

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: functionDeclaration, isCompanion: false, name: "Swift_isequal", translator: translator)
        let cdeclType: TypeSignature = .function([TypeSignature.Parameter(label: "lhs", type: .javaObjectPointer), TypeSignature.Parameter(label: "rhs", type: .javaObjectPointer)], .bool, APIFlags(), nil)
        var cdeclBody: [String]
        let retString: String
        if !classDeclaration.generics.isEmpty {
            cdeclBody = [
                "let lhs_swift: \(classDeclaration.signature.typeErasedClass) = lhs.pointee()!",
                "let rhs_swift: \(classDeclaration.signature.typeErasedClass) = rhs.pointee()!"
            ]
            retString = "return lhs_swift.isequal(rhs_swift)"
        } else {
            cdeclBody = [
                "let lhs_swift = \(classDeclaration.signature).fromJavaObject(lhs, options: \(options.jconvertibleOptions))",
                "let rhs_swift = \(classDeclaration.signature).fromJavaObject(rhs, options: \(options.jconvertibleOptions))"
            ]
            retString = "return lhs_swift == rhs_swift"
        }
        if functionDeclaration.apiFlags.options.contains(.mainActor) {
            cdeclBody.append("return MainActor.assumeIsolated {")
            cdeclBody.append(1, retString)
            cdeclBody.append("}")
        } else {
            cdeclBody.append(retString)
        }
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclType, body: cdeclBody)
        cdeclFunctions.append(cdeclFunction)
    }

    private func defaultEqualsDeclaration(for classDeclaration: KotlinClassDeclaration) -> ([KotlinStatement], CDeclFunction?) {
        let equals = KotlinFunctionDeclaration(name: "equals")
        equals.parameters = [Parameter<KotlinExpression>(externalLabel: "other", declaredType: .optional(.any))]
        equals.returnType = .bool
        equals.modifiers.visibility = .public
        equals.modifiers.isOverride = true
        equals.ensureLeadingNewlines(1)
        equals.isGenerated = true
        equals.parent = classDeclaration

        let statements: [KotlinStatement]
        let sourceCode: [String]
        let cdeclFunction: CDeclFunction?
        if !classDeclaration.generics.isEmpty, classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
            let externalFunctionDeclaration = KotlinRawStatement(sourceCode: "private external fun Swift_isequal(lhs: skip.bridge.kt.SwiftObjectPointer, rhs: skip.bridge.kt.SwiftObjectPointer): Boolean")
            statements = [equals, externalFunctionDeclaration]
            sourceCode = [
                "if (other !is skip.bridge.kt.SwiftPeerBridged) return false",
                "return Swift_isequal(Swift_peer, other.Swift_peer())"
            ]

            let (cdecl, cdeclName) = CDeclFunction.declaration(for: equals, isCompanion: false, name: "Swift_isequal", translator: translator)
            let cdeclType: TypeSignature = .function([TypeSignature.Parameter(label: "lhs", type: .swiftObjectPointer(kotlin: false)), TypeSignature.Parameter(label: "rhs", type: .swiftObjectPointer(kotlin: false))], .bool, APIFlags(), nil)
            cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclType, body: [
                "let lhs_swift: \(classDeclaration.signature.typeErasedClass) = lhs.pointee()!",
                "let rhs_swift: \(classDeclaration.signature.typeErasedClass) = rhs.pointee()!",
                "return lhs_swift.genericptr == rhs_swift.genericptr"
            ])
        } else {
            statements = [equals]
            sourceCode = [
                "if (other !is skip.bridge.kt.SwiftPeerBridged) return false",
                "return Swift_peer == other.Swift_peer()"
            ]
            cdeclFunction = nil
        }
        equals.body = KotlinCodeBlock(statements: sourceCode.map { KotlinRawStatement(sourceCode: $0) })
        return (statements, cdeclFunction)
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
        if !classDeclaration.generics.isEmpty {
            cdeclBody.append("let peer_swift: \(classDeclaration.signature.typeErasedClass) = Swift_peer.pointee()!")
            cdeclBody.append("return Int64((peer_swift.genericvalue as! (any Hashable)).hashValue)")
        } else if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
            cdeclBody.append("let peer_swift: \(classDeclaration.signature) = Swift_peer.pointee()!")
            cdeclBody.append("return Int64(peer_swift.hashValue)")
        } else {
            cdeclBody.append("let peer_swift: SwiftValueTypeBox<\(classDeclaration.signature)> = Swift_peer.pointee()!")
            cdeclBody.append("return Int64(peer_swift.value.hashValue)")
        }

        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclType, body: cdeclBody)
        cdeclFunctions.append(cdeclFunction)
    }

    private func defaultHashDeclaration(for classDeclaration: KotlinClassDeclaration) -> ([KotlinStatement], CDeclFunction?) {
        let hash = KotlinFunctionDeclaration(name: "hashCode")
        hash.returnType = .int
        hash.modifiers.visibility = .public
        hash.modifiers.isOverride = true
        hash.ensureLeadingNewlines(1)
        hash.isGenerated = true
        hash.parent = classDeclaration

        let statements: [KotlinStatement]
        let sourceCode: [String]
        let cdeclFunction: CDeclFunction?
        if !classDeclaration.generics.isEmpty, classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
            let externalFunctionDeclaration = KotlinRawStatement(sourceCode: "private external fun Swift_hashvalue(Swift_peer: skip.bridge.kt.SwiftObjectPointer): Long")
            statements = [hash, externalFunctionDeclaration]
            sourceCode = ["return Swift_hashvalue(Swift_peer).hashCode()"]

            let (cdecl, cdeclName) = CDeclFunction.declaration(for: hash, isCompanion: false, name: "Swift_hashvalue", translator: translator)
            let cdeclType: TypeSignature = .function([cdeclInstanceParameter(for: classDeclaration)], .int64, APIFlags(), nil)
            cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclType, body: [
                "let peer_swift: \(classDeclaration.signature.typeErasedClass) = Swift_peer.pointee()!",
                "return Int64(peer_swift.genericptr.hashValue)"
            ])
        } else {
            statements = [hash]
            sourceCode = ["return Swift_peer.hashCode()"]
            cdeclFunction = nil
        }
        hash.body = KotlinCodeBlock(statements: sourceCode.map { KotlinRawStatement(sourceCode: $0) })
        return (statements, cdeclFunction)
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
        var cdeclBody: [String]
        let retString: String
        if !classDeclaration.generics.isEmpty {
            cdeclBody = [
                "let lhs_ptr = SwiftObjectPointer.peer(of: lhs, options: \(options.jconvertibleOptions))",
                "let lhs_swift: \(classDeclaration.signature.typeErasedClass) = lhs_ptr.pointee()!",
                "let rhs_ptr = SwiftObjectPointer.peer(of: rhs, options: \(options.jconvertibleOptions))",
                "let rhs_swift: \(classDeclaration.signature.typeErasedClass) = rhs_ptr.pointee()!"
            ]
            retString = "return lhs_swift.islessthan(rhs_swift)"
        } else {
            cdeclBody = [
                "let lhs_swift = \(classDeclaration.signature).fromJavaObject(lhs, options: \(options.jconvertibleOptions))",
                "let rhs_swift = \(classDeclaration.signature).fromJavaObject(rhs, options: \(options.jconvertibleOptions))"
            ]
            retString = "return lhs_swift < rhs_swift"
        }
        if functionDeclaration.apiFlags.options.contains(.mainActor) {
            cdeclBody.append("return MainActor.assumeIsolated {")
            cdeclBody.append(1, retString)
            cdeclBody.append("}")
        } else {
            cdeclBody.append(retString)
        }
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
        let extensions = codebaseInfo.typeInfos(forNamed: interfaceDeclaration.signature).filter { $0.declarationType == .extensionDeclaration }

        interfaceDeclaration.extras = nil
        interfaceDeclaration.inherits = interfaceDeclaration.inherits.filter { $0.isNamed("Comparable") || $0.checkBridgable(direction: .toKotlin, options: options, generics: interfaceDeclaration.generics, codebaseInfo: codebaseInfo) != nil }
        var extensionFunctionCount = 0
        for member in interfaceDeclaration.members {
            if let variableDeclaration = member as? KotlinVariableDeclaration {
                let isExtension = extensions.contains { info in
                    info.variables.contains { $0.name == (variableDeclaration.preEscapedPropertyName ?? variableDeclaration.propertyName) }
                }
                if isExtension {
                    update(variableDeclaration, inExtensionOf: interfaceDeclaration)
                } else {
                    let _ = variableDeclaration.checkBridgable(direction: .toKotlin, options: options, translator: translator)
                }
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                let isExtension = extensions.contains { info in
                    info.functions.contains { $0.name == (functionDeclaration.preEscapedName ?? functionDeclaration.name) && $0.signature == functionDeclaration.functionType }
                }
                if isExtension {
                    if update(functionDeclaration, inExtensionOf: interfaceDeclaration, uniquifier: extensionFunctionCount) {
                        extensionFunctionCount += 1
                    }
                } else {
                    let _ = functionDeclaration.checkBridgable(direction: .toKotlin, options: options, translator: translator)
                }
            }
        }

        // Must do this last after determining member generic constraints
        interfaceDeclaration.generics = interfaceDeclaration.generics.filterBridging(codebaseInfo: codebaseInfo)
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
        if let superclassInfo {
            guard !superclassInfo.attributes.isBridgeToSwift else {
                classDeclaration.messages.append(.kotlinBridgeSuperclassBridging(classDeclaration, source: translator.syntaxTree.source))
                return false
            }
            guard !superclassInfo.attributes.isBridgeToKotlin || (classDeclaration.generics.isEmpty && superclassInfo.generics.isEmpty) else {
                classDeclaration.messages.append(.kotlinBridgeUnsupportedFeature(classDeclaration, feature: "inheritance of generic classes", source: translator.syntaxTree.source))
                return false
            }
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
        // We'll be adding constructors, so we can't use a superclass call. Transform it into a call to super(...)
        // that we can add as a delegating call to each constructor. If this is a sealed classes enum, though, we
        // keep the superclass call because we won't add constructors. This is most common for Error enums calling Exception()
        let isNonGenericEnum = classDeclaration.declarationType == .enumDeclaration && classDeclaration.generics.isEmpty
        let superclassCall: String?
        if isNonGenericEnum {
            superclassCall = nil
        } else if let call = classDeclaration.superclassCall {
            if let argumentsStart = call.firstIndex(of: "(") {
                superclassCall = "super" + call[argumentsStart...]
            } else {
                superclassCall = "super()"
            }
            classDeclaration.superclassCall = nil
        } else {
            superclassCall = nil
        }

        let isError = classDeclaration.inherits.first?.isNamed("Exception") == true && classDeclaration.inherits.contains { $0.isNamed("Error", moduleName: "Swift", generics: []) }
        var isView = false
        classDeclaration.extras = nil
        classDeclaration.inherits = classDeclaration.inherits.compactMap {
            guard !includesUI || !$0.isNamed("View", moduleName: "SkipFuseUI", generics: []) else {
                isView = true
                return .skipUIView
            }
            guard (classDeclaration.declarationType == .actorDeclaration && $0.isNamed("Actor"))
                || (isError && $0.isNamed("Exception"))
                || $0.isNamed("Comparable")
                || $0.isNamed("MutableStruct")
                || $0.checkBridgable(direction: .toKotlin, options: options, generics: classDeclaration.generics, codebaseInfo: codebaseInfo) != nil else {
                return nil
            }
            return $0
        }

        var insertStatements: [KotlinStatement] = []
        if !isNonGenericEnum {
            if subclassDepth < 1 {
                classDeclaration.inherits.append(.named("skip.bridge.kt.SwiftPeerBridged", []))

                let swiftPeerType: TypeSignature = .swiftObjectPointer(kotlin: true)
                let swiftPeer = KotlinVariableDeclaration(names: ["Swift_peer"], variableTypes: [swiftPeerType])
                swiftPeer.role = .property
                swiftPeer.modifiers.visibility = .public
                swiftPeer.apiFlags.options = .writeable
                swiftPeer.declaredType = swiftPeerType
                swiftPeer.value = KotlinRawExpression(sourceCode: "skip.bridge.kt.SwiftObjectNil")
                swiftPeer.isGenerated = true
                insertStatements.append(swiftPeer)
            }

            if !classDeclaration.isSealedClassesEnum {
                let swiftPeerConstructor = KotlinFunctionDeclaration(name: "constructor")
                swiftPeerConstructor.modifiers.visibility = .public
                swiftPeerConstructor.parameters = [Parameter<KotlinExpression>(externalLabel: "Swift_peer", declaredType: .swiftObjectPointer(kotlin: true)), Parameter<KotlinExpression>(externalLabel: "marker", declaredType: .named("skip.bridge.kt.SwiftPeerMarker", []).asOptional(true))]
                if subclassDepth < 1 {
                    if let superclassCall {
                        swiftPeerConstructor.delegatingConstructorCall = KotlinRawExpression(sourceCode: superclassCall)
                    } else if isError {
                        swiftPeerConstructor.delegatingConstructorCall = KotlinRawExpression(sourceCode: "super()")
                    }
                    swiftPeerConstructor.body = KotlinCodeBlock(statements: [KotlinRawStatement(sourceCode: "this.Swift_peer = Swift_peer")])
                } else {
                    swiftPeerConstructor.delegatingConstructorCall = KotlinRawExpression(sourceCode: "super(Swift_peer = Swift_peer, marker = marker)")
                }
                swiftPeerConstructor.ensureLeadingNewlines(1)
                swiftPeerConstructor.isGenerated = true
                insertStatements.append(swiftPeerConstructor)
            }

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

            if !isView && !classDeclaration.unbridgedMembers.suppressDefaultConstructorGeneration && classDeclaration.generics.isEmpty && !classDeclaration.members.contains(where: { $0.type == .constructorDeclaration }) {
                let constructor = KotlinFunctionDeclaration(name: "constructor")
                constructor.modifiers.visibility = .public
                if subclassDepth < 1 {
                    if let superclassCall {
                        constructor.delegatingConstructorCall = KotlinRawExpression(sourceCode: superclassCall)
                    } else if isError {
                        constructor.delegatingConstructorCall = KotlinRawExpression(sourceCode: "super()")
                    }
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
                if !classDeclaration.generics.isEmpty {
                    releaseBody.append("Swift_peer.release(as: \(classDeclaration.signature.typeErasedClass).self)")
                } else if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
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
        var bridgedVariableDeclarations: [KotlinVariableDeclaration] = []
        var bridgedFunctionDeclarations: [(KotlinFunctionDeclaration, Int?)] = []
        var enumCases: [KotlinEnumCaseDeclaration] = []
        for member in classDeclaration.members {
            if let enumCaseDeclaration = member as? KotlinEnumCaseDeclaration {
                enumCases.append(enumCaseDeclaration)
            } else if let variableDeclaration = member as? KotlinVariableDeclaration {
                if isView && variableDeclaration.propertyName == "body" {
                    // We substitute our own body
                    classDeclaration.remove(statement: variableDeclaration)
                } else if update(variableDeclaration, in: classDeclaration) {
                    bridgedVariableDeclarations.append(variableDeclaration)
                }
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                if functionDeclaration.isEqualImplementation || functionDeclaration.isKotlinEqualImplementation {
                    updateEqualsDeclaration(functionDeclaration, in: classDeclaration)
                    bridgedFunctionDeclarations.append((functionDeclaration, nil))
                    hasEqualsDeclaration = true
                } else if functionDeclaration.isHashImplementation || functionDeclaration.isKotlinHashImplementation {
                    updateHashDeclaration(functionDeclaration, in: classDeclaration)
                    bridgedFunctionDeclarations.append((functionDeclaration, nil))
                    hasHashDeclaration = true
                } else if functionDeclaration.isLessThanImplementation {
                    updateLessThanDeclaration(functionDeclaration, in: classDeclaration)
                    bridgedFunctionDeclarations.append((functionDeclaration, nil))
                } else if update(functionDeclaration, in: classDeclaration, isBridgedSubclass: subclassDepth >= 1, uniquifier: functionCount) {
                    bridgedFunctionDeclarations.append((functionDeclaration, functionCount))
                    functionCount += 1
                }
            }
        }
        if !isNonGenericEnum && subclassDepth < 1 {
            if !hasEqualsDeclaration {
                let (equalsDeclarations, cdeclFunction) = defaultEqualsDeclaration(for: classDeclaration)
                insertStatements += equalsDeclarations
                if let cdeclFunction {
                    cdeclFunctions.append(cdeclFunction)
                }
            }
            if !hasHashDeclaration {
                let (hashDeclarations, cdeclFunction) = defaultHashDeclaration(for: classDeclaration)
                insertStatements += hashDeclarations
                if let cdeclFunction {
                    cdeclFunctions.append(cdeclFunction)
                }
            }
        }
        // Must do this last after determining member generic constraints
        classDeclaration.generics = classDeclaration.generics.filterBridging(codebaseInfo: codebaseInfo)

        let finalMemberVisibility = min(classDeclaration.modifiers.visibility, .public)
        var additionalSwiftDeclarations: [String] = []
        var additionalCDeclFunctions: [CDeclFunction] = []
        if isView {
            let (statements, swift, cdeclFunctions) = addViewImplementation(to: classDeclaration, visibility: finalMemberVisibility)
            insertStatements += statements
            additionalSwiftDeclarations += swift
            additionalCDeclFunctions += cdeclFunctions
        }

        (classDeclaration.children.first as? KotlinStatement)?.ensureLeadingNewlines(1)
        classDeclaration.insert(statements: insertStatements, after: nil)

        // Conform to `BridgedToKotlin`
        let classRef = JavaClassRef(for: classDeclaration.signature, packageName: translator.packageName)
        var conformances: String
        switch subclassDepth {
        case -1:
            conformances = "BridgedToKotlin"
        case 0:
            conformances = "BridgedToKotlin, BridgedToKotlinBaseClass"
        default:
            conformances = "BridgedToKotlinSubclass\(subclassDepth)"
        }
        if classDeclaration.declarationType == .classDeclaration, classDeclaration.modifiers.isFinal || !classDeclaration.generics.isEmpty {
            conformances += ", BridgedFinalClass"
        }
        if isView {
            conformances += ", SkipUIBridging, SkipUI.View"
        }
        var swift: [String] = []
        swift.append("extension \(classDeclaration.signature.withGenerics([])): \(conformances) {")
        swift.append(1, classRef.declaration())

        if classDeclaration.declarationType == .enumDeclaration {
            swift.append(1, declareStaticLet("Java_Companion_class", ofType: "JClass", in: classDeclaration.signature, value: "try! JClass(name: \"\(classRef.className)$Companion\")"))
            swift.append(1, declareStaticLet("Java_Companion", ofType: "JObject", in: classDeclaration.signature, value: "JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: \"Companion\", sig: \"L\(classRef.className)$Companion;\")!, options: \(options.jconvertibleOptions)))"))
        }
        if isNonGenericEnum {
            swift.append(1, KotlinBridgeToSwiftVisitor.swiftForEnumJConvertibleContract(className: classRef.className, generics: classRef.generics, isSealedClassesEnum: classDeclaration.isSealedClassesEnum, caseDeclarations: enumCases, visibility: finalMemberVisibility, options: options, translator: translator))
        } else {
            let finalMemberVisibilityString = finalMemberVisibility.swift(suffix: " ")
            if subclassDepth < 1 {
                swift.append(1, "\(finalMemberVisibilityString)static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {")
                swift.append(2, "let ptr = SwiftObjectPointer.peer(of: obj!, options: options)")
                if !classDeclaration.generics.isEmpty {
                    swift.append(2, "let typeErased: \(classDeclaration.signature.typeErasedClass) = ptr.pointee()!")
                    swift.append(2, "return typeErased.genericvalue as! Self")
                } else if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
                    swift.append(2, "return ptr.pointee()!")
                } else {
                    swift.append(2, "let box: SwiftValueTypeBox<Self> = ptr.pointee()!")
                    swift.append(2, "return box.value")
                }
                swift.append(1, "}")

                let isolation = classDeclaration.declarationType == .actorDeclaration ? "nonisolated " : ""
                swift.append(1, "\(finalMemberVisibilityString)\(isolation)func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {")
                if !classDeclaration.generics.isEmpty {
                    swift.append(2, "let typeErased = toTypeErased()")
                    swift.append(2, "let Swift_peer = SwiftObjectPointer.pointer(to: typeErased, retain: true)")
                } else if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
                    swift.append(2, "let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)")
                } else {
                    swift.append(2, "let box = SwiftValueTypeBox(self)")
                    swift.append(2, "let Swift_peer = SwiftObjectPointer.pointer(to: box, retain: true)")
                }
                if classDeclaration.declarationType == .enumDeclaration {
                    let (code, declarations) = KotlinBridgeToSwiftVisitor.swiftForGenericEnumToJavaObjectSwitch(className: classRef.className, generics: classRef.generics, peerName: "Swift_peer", caseDeclarations: enumCases, visibility: finalMemberVisibility, options: options, translator: translator)
                    swift.append(2, code)
                    additionalSwiftDeclarations += declarations
                } else if subclassDepth == 0 {
                    swift.append(2, "let constructor = Java_findConstructor(base: Self.Java_class, Self.Java_constructor_methodID)")
                    swift.append(2, "return try! constructor.cls.create(ctor: constructor.ctor, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])")
                } else {
                    swift.append(2, "return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: options, args: [Swift_peer.toJavaParameter(options: options), (nil as JavaObjectPointer?).toJavaParameter(options: options)])")
                }
                swift.append(1, "}")
            }
            if classDeclaration.declarationType != .enumDeclaration {
                swift.append(1, declareStaticLet("Java_constructor_methodID", ofType: "JavaMethodID", in: classDeclaration.signature, value: "Java_class.getMethodID(name: \"<init>\", sig: \"(JLskip/bridge/kt/SwiftPeerMarker;)V\")!"))
                if subclassDepth >= 1 {
                    swift.append(1, declareStaticLet("Java_subclass\(subclassDepth)Constructor", ofType: "(JClass, JavaMethodID)", visibility: finalMemberVisibility, in: classDeclaration.signature, value: "(Java_class, Java_constructor_methodID)"))
                }
            }
        }
        swift.append(1, additionalSwiftDeclarations)
        swift.append("}")

        let swiftDefinition = SwiftDefinition(swift: swift)
        swiftDefinitions.append(swiftDefinition)

        if !classDeclaration.generics.isEmpty {
            swiftDefinitions.append(typeErasedPeerSwift(for: classDeclaration, variableDeclarations: bridgedVariableDeclarations, functionDeclarations: bridgedFunctionDeclarations, visibility: finalMemberVisibility))
        }

        let customProjection: [String]? = classDeclaration.generics.isEmpty ? nil : [
            "let ptr = SwiftObjectPointer.peer(of: Java_target, options: JConvertibleOptions(rawValue: Int(options)))",
            "let peer_swift: \(classDeclaration.signature.typeErasedClass) = ptr.pointee()!",
            "let projection = peer_swift.genericvalue"
        ]
        let cdeclFunction = KotlinBridgeToSwiftVisitor.addSwiftProjecting(to: classDeclaration, isBridgedSubclass: subclassDepth >= 1, customProjection: customProjection, options: options, translator: translator)
        cdeclFunctions.append(cdeclFunction)
        cdeclFunctions += additionalCDeclFunctions
        return true
    }

    private func typeErasedPeerSwift(for classDeclaration: KotlinClassDeclaration, variableDeclarations: [KotlinVariableDeclaration], functionDeclarations: [(KotlinFunctionDeclaration, uniquifier: Int?)], visibility: Modifiers.Visibility) -> SwiftDefinition {
        let visibilityString = visibility.swift(suffix: " ")
        var swift: [String] = []
        swift.append("extension \(classDeclaration.signature.withGenerics([])): TypeErasedConvertible {")
        swift.append(1, "\(visibilityString)func toTypeErased() -> AnyObject {")
        swift.append(2, "let typeErased = \(classDeclaration.signature.typeErasedClass)(self)")
        swift.append(2, typeErasedClosureSwift(for: classDeclaration, to: "typeErased", variableDeclarations: variableDeclarations, functionDeclarations: functionDeclarations))
        swift.append(2, "return typeErased")
        swift.append(1, "}")
        swift.append("}")

        swift.append("private final class \(classDeclaration.signature.typeErasedClass) {")
        if classDeclaration.inherits.contains(.named("MutableStruct", [])) {
            swift.append(1, "var genericvalue: Any")
        } else {
            swift.append(1, "let genericvalue: Any")
        }
        if classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
            swift.append(1, "let genericptr: SwiftObjectPointer")
            swift.append(1, "init(_ value: AnyObject) {")
            swift.append(2, "self.genericvalue = value")
            swift.append(2, "self.genericptr = SwiftObjectPointer.pointer(to: value, retain: false)")
            swift.append(1, "}")
        } else {
            swift.append(1, "init(_ value: Any) {")
            swift.append(2, "self.genericvalue = value")
            swift.append(1, "}")
        }

        for variableDeclaration in variableDeclarations {
            let getter = variableDeclaration.isAppendAsFunction ? variableDeclaration.propertyName : "get_\(variableDeclaration.propertyName)"
            let type: TypeSignature = .any.asOptional(variableDeclaration.propertyType.isOptional)
            let mainActorString = variableDeclaration.apiFlags.options.contains(.mainActor) ? "@MainActor " : ""
            let asyncString = variableDeclaration.apiFlags.options.contains(.async) ? " async" : ""
            let throwsString = variableDeclaration.apiFlags.throwsType != .none ? " throws" : ""
            swift.append(1, "var \(getter): (\(mainActorString)()\(asyncString)\(throwsString) -> \(type))!")
            if variableDeclaration.apiFlags.options.contains(.writeable) {
                swift.append(1, "var set_\(variableDeclaration.propertyName): (\(mainActorString)(\(type)) -> Void)!")
            }
        }

        var isEqualDeclaration: KotlinFunctionDeclaration? = nil
        var isLessThanDeclaration: KotlinFunctionDeclaration? = nil
        for (functionDeclaration, uniquifier) in functionDeclarations {
            guard !functionDeclaration.isMutableStructCopyConstructor else {
                continue
            }
            guard !functionDeclaration.isEqualImplementation else {
                isEqualDeclaration = functionDeclaration
                continue
            }
            guard !functionDeclaration.isLessThanImplementation else {
                isLessThanDeclaration = functionDeclaration
                continue
            }
            guard !functionDeclaration.isHashImplementation else {
                continue
            }

            let functionName = functionDeclaration.preEscapedName ?? functionDeclaration.name
            let uniquifierString = uniquifier == nil ? "" : "_\(uniquifier!)"
            let returnType: TypeSignature
            if functionDeclaration.returnType == .void {
                returnType = .void
            } else if functionDeclaration.returnType.isNamedType {
                returnType = .any.asOptional(functionDeclaration.returnType.isOptional)
            } else {
                returnType = functionDeclaration.returnType
            }
            let parametersString = functionDeclaration.parameters.map { parameter in
                let type: TypeSignature = parameter.declaredType.isNamedType ? .any.asOptional(parameter.declaredType.isOptional) : parameter.declaredType
                return type.description
            }.joined(separator: ", ")
            let mainActorString = functionDeclaration.apiFlags.options.contains(.mainActor) ? "@MainActor " : ""
            let asyncString = functionDeclaration.apiFlags.options.contains(.async) ? " async" : ""
            let throwsString = functionDeclaration.apiFlags.throwsType != .none ? " throws" : ""
            swift.append(1, "var \(functionName)\(uniquifierString): (\(mainActorString)(\(parametersString))\(asyncString)\(throwsString) -> \(returnType))!")
        }
        if let isEqualDeclaration {
            let mainActorString = isEqualDeclaration.apiFlags.options.contains(.mainActor) ? "@MainActor " : ""
            swift.append(1, "var isequal: (\(mainActorString)(Any) -> Bool)!")
        }
        if let isLessThanDeclaration {
            let mainActorString = isLessThanDeclaration.apiFlags.options.contains(.mainActor) ? "@MainActor " : ""
            swift.append(1, "var islessthan: (\(mainActorString)(Any) -> Bool)!")
        }
        swift.append("}")
        return SwiftDefinition(swift: swift)
    }

    private func typeErasedClosureSwift(for classDeclaration: KotlinClassDeclaration, to target: String, variableDeclarations: [KotlinVariableDeclaration], functionDeclarations: [(KotlinFunctionDeclaration, uniquifier: Int?)]) -> [String] {
        var swift: [String] = []
        for variableDeclaration in variableDeclarations {
            let tryString = variableDeclaration.apiFlags.throwsType != .none ? "try " : ""
            let awaitString = variableDeclaration.apiFlags.options.contains(.async) ? "await " : ""
            if variableDeclaration.isAppendAsFunction {
                swift.append("\(target).\(variableDeclaration.propertyName) = { [unowned \(target)] in \(tryString)\(awaitString)(\(target).genericvalue as! Self).\(variableDeclaration.propertyName)() }")
            } else {
                swift.append("\(target).get_\(variableDeclaration.propertyName) = { [unowned \(target)] in \(tryString)\(awaitString)(\(target).genericvalue as! Self).\(variableDeclaration.propertyName) }")
                if variableDeclaration.apiFlags.options.contains(.writeable) {
                    let castString = variableDeclaration.propertyType.isNamedType ? " as! \(variableDeclaration.propertyType)" : ""
                    if classDeclaration.declarationType == .structDeclaration {
                        swift.append("\(target).set_\(variableDeclaration.propertyName) = { [unowned \(target)] in")
                        swift.append(1, "var genericvalue = \(target).genericvalue as! Self")
                        swift.append(1, "genericvalue.\(variableDeclaration.propertyName) = $0\(castString)")
                        swift.append(1, "\(target).genericvalue = genericvalue")
                        swift.append("}")
                    } else {
                        swift.append("\(target).set_\(variableDeclaration.propertyName) = { [unowned \(target)] in (\(target).genericvalue as! Self).\(variableDeclaration.propertyName) = $0\(castString) }")
                    }
                }
            }
        }

        var hasIsEqual = false
        var hasIsLessThan = false
        for (functionDeclaration, uniquifier) in functionDeclarations {
            guard !functionDeclaration.isMutableStructCopyConstructor else {
                continue
            }
            guard !functionDeclaration.isEqualImplementation else {
                hasIsEqual = true
                continue
            }
            guard !functionDeclaration.isLessThanImplementation else {
                hasIsLessThan = true
                continue
            }
            guard !functionDeclaration.isHashImplementation else {
                continue
            }
            let functionName = functionDeclaration.preEscapedName ?? functionDeclaration.name
            let uniquifierString = uniquifier == nil ? "" : "_\(uniquifier!)"
            let tryString = functionDeclaration.apiFlags.throwsType != .none ? "try " : ""
            let awaitString = functionDeclaration.apiFlags.options.contains(.async) ? "await " : ""
            let argumentsString = functionDeclaration.parameters.enumerated().map { index, parameter in
                let label = parameter.externalLabel == nil ? "" : "\(parameter.externalLabel!): "
                let castString = parameter.declaredType.isNamedType ? " as! \(parameter.declaredType)" : ""
                return "\(label)$\(index)\(castString)"
            }.joined(separator: ", ")
            if classDeclaration.declarationType == .structDeclaration && functionDeclaration.modifiers.isMutating {
                swift.append("\(target).\(functionName)\(uniquifierString) = { [unowned \(target)] in")
                swift.append(1, "var genericvalue = \(target).genericvalue as! Self")
                if functionDeclaration.returnType == .void {
                    swift.append(1, "\(tryString)\(awaitString)genericvalue.\(functionName)(\(argumentsString))")
                } else {
                    swift.append(1, "let genericreturn = \(tryString)\(awaitString)genericvalue.\(functionName)(\(argumentsString))")
                }
                swift.append(1, "\(target).genericvalue = genericvalue")
                if functionDeclaration.returnType != .void {
                    swift.append("return genericreturn")
                }
                swift.append("}")
            } else {
                swift.append("\(target).\(functionName)\(uniquifierString) = { [unowned \(target)] in \(tryString)\(awaitString)(\(target).genericvalue as! Self).\(functionName)(\(argumentsString)) }")
            }
        }
        if hasIsEqual {
            swift.append(1, "\(target).isequal = { [unowned \(target)] in (\(target).genericvalue as! Self) == $0 as! Self }")
        }
        if hasIsLessThan {
            swift.append(1, "\(target).islessthan = { [unowned \(target)] in (\(target).genericvalue as! Self) < $0 as! Self }")
        }
        return swift
    }

    private func addViewImplementation(to classDeclaration: KotlinClassDeclaration, visibility: Modifiers.Visibility) -> (statements: [KotlinStatement], swift: [String], cdeclFunctions: [CDeclFunction]) {
        var statements: [KotlinStatement] = []
        var swift: [String] = []
        var cdeclFunctions: [CDeclFunction] = []

        let stateVariables: [(String, Attributes)] = classDeclaration.unbridgedMembers.compactMap {
            guard case .swiftUIStateProperty(let name, let attributes) = $0 else {
                return nil
            }
            return (name, attributes)
        }
        if !stateVariables.isEmpty {
            statements += viewComposeContent(for: classDeclaration, stateVariables: stateVariables)
            for (name, attributes) in stateVariables {
                var initStatements: [KotlinStatement] = []
                var syncStatements: [KotlinStatement] = []
                var initSwift: [String] = []
                var syncSwift: [String] = []
                var initCdeclFunctions: [CDeclFunction] = []
                var syncCdeclFunctions: [CDeclFunction] = []
                if attributes.stateAttribute != nil {
                    (initStatements, initSwift, initCdeclFunctions) = viewInitState(for: name, in: classDeclaration)
                    (syncStatements, syncSwift, syncCdeclFunctions) = viewSyncState(for: name, in: classDeclaration)
                } else if attributes.environmentAttribute != nil {
                    (initStatements, initSwift, initCdeclFunctions) = viewInitEnvironment(for: name, in: classDeclaration)
                    (syncStatements, syncSwift, syncCdeclFunctions) = viewSyncEnvironment(for: name, in: classDeclaration)
                }
                statements += initStatements + syncStatements
                swift += initSwift + syncSwift
                cdeclFunctions += initCdeclFunctions + syncCdeclFunctions
            }
        }

        let (bodyStatements, bodySwift, bodyCdeclFunctions) = viewBodyImplementation(for: classDeclaration, visibility: visibility)
        statements += bodyStatements
        swift += bodySwift
        cdeclFunctions += bodyCdeclFunctions

        return (statements, swift, cdeclFunctions)
    }

    private func viewComposeContent(for classDeclaration: KotlinClassDeclaration, stateVariables: [(name: String, attributes: Attributes)]) -> [KotlinStatement] {
        let functionDeclaration = KotlinFunctionDeclaration(name: "ComposeContent")
        functionDeclaration.parameters = [Parameter<KotlinExpression>(externalLabel: "composectx", declaredType: .named("skip.ui.ComposeContext", []))]
        functionDeclaration.modifiers = Modifiers(visibility: .public, isOverride: true)
        functionDeclaration.attributes.attributes.append(Attribute(signature: .named("androidx.compose.runtime.Composable", [])))
        functionDeclaration.extras = .singleNewline
        var bodyKotlin: [String] = []
        for (name, attributes) in stateVariables {
            if attributes.stateAttribute != nil {
                bodyKotlin.append("val remembered\(name) = androidx.compose.runtime.saveable.rememberSaveable(stateSaver = composectx.stateSaver as androidx.compose.runtime.saveable.Saver<skip.ui.StateSupport, Any>) { androidx.compose.runtime.mutableStateOf(Swift_initState_\(name)(Swift_peer)) }")
                bodyKotlin.append("Swift_syncState_\(name)(Swift_peer, remembered\(name).value)")
            } else if attributes.environmentAttribute != nil {
                bodyKotlin.append("val envkey\(name) = Swift_initEnvironment_\(name)(Swift_peer)")
                bodyKotlin.append("val envvalue\(name) = skip.ui.EnvironmentValues.shared.bridged(envkey\(name))")
                bodyKotlin.append("Swift_syncEnvironment_\(name)(Swift_peer, envvalue\(name))")
            }
        }
        bodyKotlin.append("super.ComposeContent(composectx)")
        functionDeclaration.body = KotlinCodeBlock(statements: bodyKotlin.map { KotlinRawStatement(sourceCode: $0) })
        return [functionDeclaration]
    }

    private func viewInitState(for name: String, in classDeclaration: KotlinClassDeclaration) -> (statements: [KotlinStatement], swift: [String], cdeclFunctions: [CDeclFunction]) {
        let externalName = "Swift_initState_\(name)"
        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: "private external fun \(externalName)(Swift_peer: skip.bridge.kt.SwiftObjectPointer): skip.ui.StateSupport")
        externalFunctionDeclaration.parent = classDeclaration

        var source: [String] = []
        source.append("func Java_initState_\(name)() -> SkipUI.StateSupport {")
        source.append(1, "return $\(name).valueBox!.Java_initStateSupport()")
        source.append("}")

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: externalFunctionDeclaration, isCompanion: false, name: externalName, translator: translator)
        let cdeclSignature: TypeSignature = .function([TypeSignature.Parameter(label: "Swift_peer", type: .swiftObjectPointer(kotlin: false))], .javaObjectPointer, APIFlags(), nil)
        let cdeclSource: [String] = [
            "let peer_swift: SwiftValueTypeBox<\(classDeclaration.signature)> = Swift_peer.pointee()!",
            "return peer_swift.value.Java_initState_\(name)().toJavaObject(options: [])!"
        ]
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclSignature, body: cdeclSource)
        return ([externalFunctionDeclaration], source, [cdeclFunction])
    }

    private func viewSyncState(for name: String, in classDeclaration: KotlinClassDeclaration) -> (statements: [KotlinStatement], swift: [String], cdeclFunctions: [CDeclFunction]) {
        let externalName = "Swift_syncState_\(name)"
        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: "private external fun \(externalName)(Swift_peer: skip.bridge.kt.SwiftObjectPointer, support: skip.ui.StateSupport)")
        externalFunctionDeclaration.parent = classDeclaration

        var source: [String] = []
        source.append("func Java_syncState_\(name)(support: SkipUI.StateSupport) {")
        source.append(1, "$\(name).valueBox!.Java_syncStateSupport(support)")
        source.append("}")

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: externalFunctionDeclaration, isCompanion: false, name: externalName, translator: translator)
        let cdeclSignature: TypeSignature = .function([TypeSignature.Parameter(label: "Swift_peer", type: .swiftObjectPointer(kotlin: false)), TypeSignature.Parameter(label: "support", type: .javaObjectPointer)], .void, APIFlags(), nil)
        let cdeclSource: [String] = [
            "let peer_swift: SwiftValueTypeBox<\(classDeclaration.signature)> = Swift_peer.pointee()!",
            "let support_swift = SkipUI.StateSupport.fromJavaObject(support, options: [])",
            "peer_swift.value.Java_syncState_\(name)(support: support_swift)"
        ]
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclSignature, body: cdeclSource)
        return ([externalFunctionDeclaration], source, [cdeclFunction])
    }

    private func viewInitEnvironment(for name: String, in classDeclaration: KotlinClassDeclaration) -> (statements: [KotlinStatement], swift: [String], cdeclFunctions: [CDeclFunction]) {
        let externalName = "Swift_initEnvironment_\(name)"
        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: "private external fun \(externalName)(Swift_peer: skip.bridge.kt.SwiftObjectPointer): String")
        externalFunctionDeclaration.parent = classDeclaration

        var source: [String] = []
        source.append("func Java_initEnvironment_\(name)() -> String {")
        source.append(1, "return $\(name).key")
        source.append("}")

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: externalFunctionDeclaration, isCompanion: false, name: externalName, translator: translator)
        let cdeclSignature: TypeSignature = .function([TypeSignature.Parameter(label: "Swift_peer", type: .swiftObjectPointer(kotlin: false))], .javaString, APIFlags(), nil)
        let cdeclSource: [String] = [
            "let peer_swift: SwiftValueTypeBox<\(classDeclaration.signature)> = Swift_peer.pointee()!",
            "return peer_swift.value.Java_initEnvironment_\(name)().toJavaObject(options: [])!"
        ]
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclSignature, body: cdeclSource)
        return ([externalFunctionDeclaration], source, [cdeclFunction])
    }

    private func viewSyncEnvironment(for name: String, in classDeclaration: KotlinClassDeclaration) -> (statements: [KotlinStatement], swift: [String], cdeclFunctions: [CDeclFunction]) {
        let externalName = "Swift_syncEnvironment_\(name)"
        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: "private external fun \(externalName)(Swift_peer: skip.bridge.kt.SwiftObjectPointer, support: skip.ui.EnvironmentSupport?)")
        externalFunctionDeclaration.parent = classDeclaration

        var source: [String] = []
        source.append("func Java_syncEnvironment_\(name)(support: SkipUI.EnvironmentSupport?) {")
        source.append(1, "$\(name).Java_syncEnvironmentSupport(support)")
        source.append("}")

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: externalFunctionDeclaration, isCompanion: false, name: externalName, translator: translator)
        let cdeclSignature: TypeSignature = .function([TypeSignature.Parameter(label: "Swift_peer", type: .swiftObjectPointer(kotlin: false)), TypeSignature.Parameter(label: "support", type: .optional(.javaObjectPointer))], .void, APIFlags(), nil)
        let cdeclSource: [String] = [
            "let peer_swift: SwiftValueTypeBox<\(classDeclaration.signature)> = Swift_peer.pointee()!",
            "let support_swift = SkipUI.EnvironmentSupport.fromJavaObject(support, options: [])",
            "peer_swift.value.Java_syncEnvironment_\(name)(support: support_swift)"
        ]
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclSignature, body: cdeclSource)
        return ([externalFunctionDeclaration], source, [cdeclFunction])
    }

    private func viewBodyImplementation(for classDeclaration: KotlinClassDeclaration, visibility: Modifiers.Visibility) -> (statements: [KotlinStatement], swift: [String], cdeclFunctions: [CDeclFunction]) {
        let externalName = "Swift_composableBody"
        let functionDeclaration = KotlinFunctionDeclaration(name: "body")
        functionDeclaration.returnType = .skipUIView
        functionDeclaration.modifiers = Modifiers(visibility: .public, isOverride: true)
        functionDeclaration.extras = .singleNewline
        let functionSource = "return skip.ui.ComposeBuilder { composectx: skip.ui.ComposeContext -> \(externalName)(Swift_peer)?.Compose(composectx) ?: skip.ui.ComposeResult.ok }"
        functionDeclaration.body = KotlinCodeBlock(statements: [KotlinRawStatement(sourceCode: functionSource)])
        functionDeclaration.body?.disallowSingleStatementAppend = true
        functionDeclaration.parent = classDeclaration

        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: "private external fun \(externalName)(Swift_peer: skip.bridge.kt.SwiftObjectPointer): skip.ui.View?")

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: functionDeclaration, isCompanion: false, name: externalName, translator: translator)
        let cdeclSignature: TypeSignature = .function([TypeSignature.Parameter(label: "Swift_peer", type: .swiftObjectPointer(kotlin: false))], .optional(.javaObjectPointer), APIFlags(), nil)
        var cdeclSource: [String] = []
        cdeclSource.append("let peer_swift: SwiftValueTypeBox<\(classDeclaration.signature)> = Swift_peer.pointee()!")
        cdeclSource.append("return MainActor.assumeIsolated {")
        cdeclSource.append(1, "let body = peer_swift.value.body")
        cdeclSource.append(1, "return ((body as? SkipUIBridging)?.Java_view as? JConvertible)?.toJavaObject(options: [])")
        cdeclSource.append("}")
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclSignature, body: cdeclSource)

        var swift: [String] = []
        let visibilityString = visibility.swift(suffix: " ")
        swift.append("\(visibilityString)var Java_view: any SkipUI.View {")
        swift.append(1, "return self")
        swift.append("}")

        return ([functionDeclaration, externalFunctionDeclaration], swift, [cdeclFunction])
    }

    private func cdeclInstanceParameter(for classDeclaration: KotlinClassDeclaration) -> TypeSignature.Parameter {
        if !classDeclaration.generics.isEmpty {
            return TypeSignature.Parameter(label: "Swift_peer", type: .swiftObjectPointer(kotlin: false))
        } else if classDeclaration.isSealedClassesEnum {
            return TypeSignature.Parameter(label: "className", type: .javaString)
        } else if classDeclaration.declarationType == .enumDeclaration {
            return TypeSignature.Parameter(label: "name", type: .javaString)
        } else {
            return TypeSignature.Parameter(label: "Swift_peer", type: .swiftObjectPointer(kotlin: false))
        }
    }

    private func appendMainActorIsolated(_ swift: inout [String], _ indentation: Indentation = 0, isolated: Bool, isThrows: Bool = false, isReturn: Bool = false, block: (inout [String], Indentation) -> Void) {
        guard isolated else {
            block(&swift, indentation)
            return
        }
        let tryString = isThrows ? "try " : ""
        let returnString = isReturn ? "return " : ""
        swift.append(indentation, "\(returnString)\(tryString)MainActor.assumeIsolated {")
        block(&swift, indentation.inc())
        swift.append(indentation, "}")
    }
}
