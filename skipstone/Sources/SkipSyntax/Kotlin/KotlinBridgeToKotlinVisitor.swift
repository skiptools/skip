// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

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
        guard syntaxTree.isBridgeFile, !syntaxTree.root.isInIfSkipBlock, let codebaseInfo = translator.codebaseInfo else {
            return nil
        }
        self.syntaxTree = syntaxTree
        self.options = options
        self.translator = translator
        self.codebaseInfo = codebaseInfo
        self.includesUI = translator.syntaxTree.root.statements.compactMap({ $0 as? ImportDeclaration }).contains { $0.modulePath.first == "SwiftUI" || $0.modulePath.first == "SkipSwiftUI" || $0.modulePath.first == "SkipFuseUI" }
    }

    func visit() -> [KotlinTransformerOutput] {
        var globalFunctionCount = 0
        var hasObservables = false
        var hasSkipFuseImport = false
        var nonKotlinImports: [KotlinStatement] = []
        syntaxTree.root.visit { node in
            if let importDeclaration = node as? KotlinImportDeclaration {
                guard !importDeclaration.isInIfSkipBlock else {
                    return .skip
                }
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
                    guard !variableDeclaration.isInIfSkipBlock else {
                        return .skip
                    }
                    update(variableDeclaration)
                } else if variableDeclaration.extends != nil {
                    variableDeclaration.messages.append(.kotlinBridgeExtensionFunction(variableDeclaration, source: translator.syntaxTree.source))
                }
                return .skip
            } else if let functionDeclaration = node as? KotlinFunctionDeclaration {
                if functionDeclaration.role == .global {
                    guard !functionDeclaration.isInIfSkipBlock else {
                        return .skip
                    }
                    if update(functionDeclaration, uniquifier: globalFunctionCount) {
                        globalFunctionCount += 1
                    }
                } else if functionDeclaration.extends != nil {
                    functionDeclaration.messages.append(.kotlinBridgeExtensionFunction(functionDeclaration, source: translator.syntaxTree.source))
                }
                return .skip
            } else if let classDeclaration = node as? KotlinClassDeclaration {
                guard !classDeclaration.isInIfSkipBlock else {
                    return .skip
                }
                update(classDeclaration)
                hasObservables = hasObservables || classDeclaration.attributes.contains(.observable) || classDeclaration.unbridgedMembers.contains(where: { $0.isObservable })
                return .recurse(nil)
            } else if let interfaceDeclaration = node as? KotlinInterfaceDeclaration {
                guard !interfaceDeclaration.isInIfSkipBlock else {
                    return .skip
                }
                if update(interfaceDeclaration) {
                    if let bridgeImpl = KotlinBridgeToSwiftVisitor.protocolBridgeImplDefinition(forProtocol: interfaceDeclaration.signature, inPackage: translator.packageName, statement: interfaceDeclaration, options: options, autoBridge: syntaxTree.autoBridge, codebaseInfo: codebaseInfo) {
                        swiftDefinitions.append(bridgeImpl)
                    }
                }
                return .recurse(nil)
            } else if let codeBlock = node as? KotlinCodeBlock {
                guard !codeBlock.isInIfSkipBlock else {
                    return .skip
                }
                hasObservables = hasObservables || codeBlock.unbridgedMembers.contains(where: { $0.isObservable })
                return .recurse(nil)
            } else {
                return .recurse(nil)
            }
        }
        nonKotlinImports.forEach { syntaxTree.root.remove(statement: $0) }

        if hasObservables && !hasSkipFuseImport && !includesUI && (KotlinBridgeTransformer.testSkipAndroidBridge || codebaseInfo.global.needsAndroidBridge) {
            syntaxTree.root.messages.append(.kotlinBridgeObservableMissingImport(syntaxTree.root, source: syntaxTree.source))
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

        let importDeclarations: [ImportDeclaration] = translator.syntaxTree.root.statements.compactMap {
            guard let importDeclaration = $0 as? ImportDeclaration else {
                return nil
            }
            return importDeclaration.isInIfSkipBlock() ? nil : importDeclaration
        }
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
        variableDeclaration.extras = Self.bridgeExtras(variableDeclaration.extras)
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

        updateDeclaration(variableDeclaration, with: bridgable)

        let externalName = "Swift_" + (interfaceDeclaration == nil ? "" : interfaceDeclaration!.name + "_") + (variableDeclaration.isStatic ? "Companion_" : "") + propertyName
        var externalFunctionDeclarations: [String] = []
        let (cdecl, cdeclName) = CDeclFunction.declaration(for: variableDeclaration, isCompanion: variableDeclaration.isStatic, name: externalName, translator: translator)

        // Getter
        let isInstance = classDeclaration != nil && !variableDeclaration.isStatic
        let isProtocolInstance = interfaceDeclaration != nil && !variableDeclaration.isStatic
        let classType = ClassType(classDeclaration)
        let getterArguments: String
        let getterParameters: String
        if isInstance, let classType {
            getterArguments = "(\(classType.peerExternalArgument))"
            getterParameters = "(\(classType.peerExternalParameter))"
        } else if isProtocolInstance, let interfaceDeclaration {
            getterArguments = "(this)"
            getterParameters = "(Java_iface: \(interfaceDeclaration.name))"
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
            if isInstance, let classType {
                cdeclInstanceParameters = [classType.peerSwiftParameter]
                cdeclGetterBody.append(0, classType.peerSwiftAssignment(to: classDeclaration, optionsString: optionsString))
                switch classType {
                case .generic:
                    valueString = bridgable.type.convertToCDecl(value: "peer_swift.get_\(propertyName)()", strategy: bridgable.strategy, options: options)
                default:
                    valueString = bridgable.type.convertToCDecl(value: "\(classType.peerSwiftTarget).\(propertyName)", strategy: bridgable.strategy, options: options)
                }
            } else {
                cdeclInstanceParameters = []
                valueString = bridgable.type.convertToCDecl(value: "\(classDeclaration.signature).\(propertyName)", strategy: bridgable.strategy, options: options)
            }
        } else if let interfaceDeclaration {
            if isProtocolInstance {
                cdeclInstanceParameters = [TypeSignature.Parameter(label: "Java_iface", type: .javaObjectPointer)]
                cdeclGetterBody.append("let peer_swift = AnyBridging.fromJavaObject(Java_iface, options: \(optionsString)) as! any \(interfaceDeclaration.name)")
                valueString = bridgable.type.convertToCDecl(value: "peer_swift.\(propertyName)", strategy: bridgable.strategy, options: options)
            } else {
                cdeclInstanceParameters = []
                valueString = bridgable.type.convertToCDecl(value: "\(interfaceDeclaration.name).\(propertyName)", strategy: bridgable.strategy, options: options)
            }
        } else {
            cdeclInstanceParameters = []
            valueString = bridgable.type.convertToCDecl(value: propertyName, strategy: bridgable.strategy, options: options)
        }
        if variableDeclaration.apiFlags.throwsType == .none {
            variableDeclaration.appendMainActorIsolated(&cdeclGetterBody, in: classDeclaration, isReturn: true) { body, indentation in
                body.append(indentation, "return " + valueString)
            }
        } else {
            cdeclGetterBody.append("do {")
            variableDeclaration.appendMainActorIsolated(&cdeclGetterBody, 1, in: classDeclaration, isReturn: true) { body, indentation in
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
                setterArguments = "\(classType?.peerExternalArgument ?? ""), newValue\(castString)"
                setterInstanceParameter = "\(classType?.peerExternalParameter ?? ""), "
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
            if let annotation = variableDeclaration.preventJVMNameManglingAnnotation(name: externalName + "_set", isFunction: true) {
                externalFunctionDeclarations.append(annotation)
            }
            externalFunctionDeclarations.append("private external fun \(externalName)_set(\(setterInstanceParameter)value: \(bridgable.externalType.kotlin))")

            var cdeclSetterBody: [String] = []
            let setValueString: String
            if let classDeclaration, let classType {
                if isInstance {
                    cdeclSetterBody.append(0, classType.peerSwiftAssignment(to: classDeclaration, optionsString: optionsString))
                    switch classType {
                    case .generic:
                        setValueString = "peer_swift.set_\(propertyName)(" + bridgable.constrainedType.convertFromCDecl(value: "value", strategy: bridgable.strategy, options: options) + ")"
                    default:
                        setValueString = "\(classType.peerSwiftTarget).\(propertyName) = " + bridgable.constrainedType.convertFromCDecl(value: "value", strategy: bridgable.strategy, options: options)
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
            let cdeclParameter = TypeSignature.Parameter(label: "value", type: bridgable.type.cdecl(strategy: bridgable.strategy, options: options))
            variableDeclaration.appendMainActorIsolated(&cdeclSetterBody, in: classDeclaration, parameter: cdeclParameter) { body, indentation in
                body.append(indentation, setValueString)
            }
            let cdeclSetter = CDeclFunction(name: cdeclName + "_set", cdecl: cdecl + "_1set", signature: .function(cdeclInstanceParameters + [cdeclParameter], .void, APIFlags(), nil), body: cdeclSetterBody)
            cdeclFunctions.append(cdeclSetter)
        }
        variableDeclaration.willSet = nil
        variableDeclaration.didSet = nil

        // Add function declarations to transpiled output
        let parent = interfaceDeclaration?.parent ?? variableDeclaration.parent
        (parent as? KotlinStatement)?.insert(statements: externalFunctionDeclarations.map { KotlinRawStatement(sourceCode: $0, isStatic: variableDeclaration.isStatic) }, after: interfaceDeclaration ?? variableDeclaration)
        return true
    }

    private func updateDeclaration(_ variableDeclaration: KotlinVariableDeclaration, with bridgable: Bridgable) {
        // Remove initial value and make sure type is declared
        variableDeclaration.value = nil
        variableDeclaration.declaredType = bridgable.kotlinType
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
        updateDeclaration(functionDeclaration, with: bridgable)
        functionDeclaration.extras = Self.bridgeExtras(functionDeclaration.extras)

        let (bodyCodeBlock, externalStatements) = addDefinitions(for: functionDeclaration, bridgable: bridgable, in: classDeclaration, isBridgedSubclass: isBridgedSubclass, inExtensionOf: interfaceDeclaration, isMutableStructCopyConstructor: isMutableStructCopyConstructor, uniquifier: uniquifier)
        functionDeclaration.body = bodyCodeBlock

        let parent = interfaceDeclaration?.parent ?? functionDeclaration.parent
        (parent as? KotlinStatement)?.insert(statements: externalStatements, after: interfaceDeclaration ?? functionDeclaration)
        return true
    }

    private func updateDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, with bridgable: FunctionBridgable) {
        functionDeclaration.returnType = bridgable.return.kotlinType
        functionDeclaration.parameters = functionDeclaration.parameters.enumerated().map { index, parameter in
            var parameter = parameter
            parameter.declaredType = bridgable.parameters[index].kotlinType
            return parameter
        }
        functionDeclaration.generics = functionDeclaration.generics.compactMapBridgable(direction: .toKotlin, options: options, codebaseInfo: codebaseInfo)
    }

    private func addDefinitions(for functionDeclaration: KotlinFunctionDeclaration, bridgable: FunctionBridgable, in classDeclaration: KotlinClassDeclaration? = nil, isBridgedSubclass: Bool = false, inExtensionOf interfaceDeclaration: KotlinInterfaceDeclaration? = nil, isMutableStructCopyConstructor: Bool = false, isDeclaredByVariable: Bool = false, uniquifier: Int? = nil) -> (KotlinCodeBlock, [KotlinStatement]) {
        let functionName = functionDeclaration.preEscapedName ?? functionDeclaration.name
        let isAsync = functionDeclaration.apiFlags.options.contains(.async)
        let isThrows = functionDeclaration.apiFlags.throwsType != .none
        let isCompanionCall = functionDeclaration.isStatic || (functionDeclaration.type == .constructorDeclaration && isBridgedSubclass)
        let externalName = (isAsync ? "Swift_callback_" : "Swift_") + (interfaceDeclaration == nil ? "" : interfaceDeclaration!.name + "_") + (isCompanionCall ? "Companion_" : "") + functionName + (uniquifier == nil ? "" : "_\(uniquifier!)")

        var cdeclBodyParameters: [String] = []
        if !isMutableStructCopyConstructor || classDeclaration?.generics.isEmpty != false {
            for index in 0..<bridgable.parameters.count {
                let strategy = bridgable.parameters[index].strategy
                let parameterType = isMutableStructCopyConstructor ? classDeclaration!.signature : bridgable.parameters[index].constrainedType
                cdeclBodyParameters.append("let p_\(index)_swift = " + parameterType.convertFromCDecl(value: "p_\(index)", strategy: strategy, options: options))
            }
        }

        var cdeclBody: [String] = []
        if isAsync {
            let callbackType = bridgable.return.constrainedType.callbackClosureType(apiFlags: functionDeclaration.apiFlags, kotlin: false)
            cdeclBody.append("let f_callback_swift = " + callbackType.convertFromCDecl(value: "f_callback", strategy: .direct, options: options))
        }

        let classType = ClassType(classDeclaration)
        let swiftCallTarget: String
        var externalArgumentsString: String
        var swiftFunctionName = functionName
        let optionsString = options.jconvertibleOptions
        if let classDeclaration, let classType, functionDeclaration.type != .constructorDeclaration {
            if functionDeclaration.isStatic {
                swiftCallTarget = classDeclaration.name + "."
                externalArgumentsString = ""
            } else {
                cdeclBody.append(0, classType.peerSwiftAssignment(to: classDeclaration, optionsString: optionsString))
                swiftCallTarget = classType.peerSwiftTarget + "."
                externalArgumentsString = classType.peerExternalArgument
                if classType == .generic {
                    swiftFunctionName += uniquifier == nil ? "" : "_\(uniquifier!)"
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
            externalArgumentsString += zip(functionDeclaration.parameters, bridgable.parameters).enumerated().map { index, zipped in
                let parameter = zipped.0
                let bridgable = zipped.1
                let label = parameter.internalLabel == "_" ? "p\(index)" : parameter.internalLabel
                return bridgable.genericType == nil ? label : "\(label) as \(TypeSignature.any.asOptional(bridgable.type.isOptional).kotlin)"
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
        let cdeclParameters = bridgable.parameters.enumerated().map { (index, bridgable) in
            let strategy = bridgable.strategy
            return TypeSignature.Parameter(label: "p_\(index)", type: bridgable.type.cdecl(strategy: strategy, options: options))
        }
        if let classDeclaration, functionDeclaration.type == .constructorDeclaration {
            if isBridgedSubclass {
                functionDeclaration.delegatingConstructorCall = KotlinRawExpression(sourceCode: "super(Swift_peer = \(externalName)(\(externalArgumentsString)), marker = null)")
            } else {
                body.append("Swift_peer = \(externalName)(\(externalArgumentsString))")
            }
            if isThrows {
                cdeclBody.append("do {")
                functionDeclaration.appendMainActorIsolated(&cdeclBody, 1, in: classDeclaration, parameters: cdeclParameters, isReturn: true) { body, indentation in
                    body.append(indentation, cdeclBodyParameters)
                    if classType == .reference {
                        body.append(indentation, "let f_return_swift = try \(classDeclaration.signature)\(swiftArgumentsString)")
                    } else {
                        body.append(indentation, "let f_return_swift = try SwiftValueTypeBox(\(classDeclaration.signature)\(swiftArgumentsString))")
                    }
                    body.append(indentation, "return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)")
                }
                cdeclBody.append("} catch {")
                cdeclBody.append(1, "JThrowable.throw(error, options: \(optionsString), env: Java_env)")
                cdeclBody.append(1, "return SwiftObjectNil")
                cdeclBody.append("}")
            } else {
                functionDeclaration.appendMainActorIsolated(&cdeclBody, in: classDeclaration, parameters: cdeclParameters, isReturn: true) { body, indentation in
                    body.append(indentation, cdeclBodyParameters)
                    if classType == .reference {
                        body.append(indentation, "let f_return_swift = \(classDeclaration.signature)\(swiftArgumentsString)")
                    } else if isMutableStructCopyConstructor && classType == .generic {
                        // Create a new type-erased wrapper using the original instance
                        body.append(indentation, "let ptr = SwiftObjectPointer.peer(of: p_0, options: \(optionsString))")
                        body.append(indentation, "let peer_swift: \(classDeclaration.signature.typeErasedClass) = ptr.pointee()!")
                        body.append(indentation, "let f_return_swift = (peer_swift.genericvalue as! TypeErasedConvertible).toTypeErased()")
                    } else if isMutableStructCopyConstructor {
                        body.append(indentation, "let f_return_swift = SwiftValueTypeBox\(swiftArgumentsString)")
                    } else {
                        body.append(indentation, "let f_return_swift = SwiftValueTypeBox(\(classDeclaration.signature)\(swiftArgumentsString))")
                    }
                    body.append(indentation, "return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)")
                }
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

            cdeclBody += cdeclBodyParameters
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
                    cdeclBody.append(3, "f_callback_swift(JThrowable.toThrowable(error, options: \(optionsString))!)")
                } else {
                    cdeclBody.append(3, "f_callback_swift(nil, JThrowable.toThrowable(error, options: \(optionsString))!)")
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
                functionDeclaration.appendMainActorIsolated(&cdeclBody, 1, in: classDeclaration, parameters: cdeclParameters) { body, indentation in
                    body.append(indentation, cdeclBodyParameters)
                    body.append(indentation, "try \(swiftCallTarget)\(swiftFunctionName)\(swiftArgumentsString)")
                }
                cdeclBody.append("} catch {")
                cdeclBody.append(1, "JThrowable.throw(error, options: \(optionsString), env: Java_env)")
                cdeclBody.append("}")
            } else {
                functionDeclaration.appendMainActorIsolated(&cdeclBody, in: classDeclaration, parameters: cdeclParameters) { body, indentation in
                    body.append(indentation, cdeclBodyParameters)
                    body.append(indentation, "\(swiftCallTarget)\(swiftFunctionName)\(swiftArgumentsString)")
                }
            }
            cdeclReturnType = .void
        } else {
            let forceUnwrapString: String
            if isThrows {
                forceUnwrapString = bridgable.return.type.isOptional ? "" : "!!"
                cdeclBody.append("do {")
                functionDeclaration.appendMainActorIsolated(&cdeclBody, 1, in: classDeclaration, parameters: cdeclParameters, isReturn: true) { body, indentation in
                    body.append(indentation, cdeclBodyParameters)
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
                functionDeclaration.appendMainActorIsolated(&cdeclBody, in: classDeclaration, parameters: cdeclParameters, isReturn: true) { body, indentation in
                    body.append(indentation, cdeclBodyParameters)
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
        if let classType, functionDeclaration.type != .constructorDeclaration && !functionDeclaration.isStatic {
            externalParametersString = classType.peerExternalParameter
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
                let label = parameter.internalLabel == "_" ? "p\(index)" : parameter.internalLabel
                return label + ": " + bridgable.parameters[index].externalType.kotlin
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
            externalFunctionDeclaration += ": skip.bridge.SwiftObjectPointer"
        } else if bridgable.return.type != .void && !isAsync {
            var returnType: TypeSignature = bridgable.return.externalType
            if functionDeclaration.apiFlags.throwsType != .none {
                returnType = returnType.asOptional(true)
            }
            externalFunctionDeclaration += ": " + returnType.kotlin
        }
        var externalFunctionDeclarations: [String] = [externalFunctionDeclaration]
        if let annotation = functionDeclaration.preventJVMNameManglingAnnotation(name: externalName) {
            externalFunctionDeclarations.insert(annotation, at: 0)
        }

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: functionDeclaration, isCompanion: isCompanionCall, name: externalName, translator: translator)
        let instanceParameter: [TypeSignature.Parameter]
        if let classType, functionDeclaration.type != .constructorDeclaration && !functionDeclaration.isStatic { instanceParameter = [classType.peerSwiftParameter]
        } else if interfaceDeclaration != nil, !functionDeclaration.isStatic {
            instanceParameter = [TypeSignature.Parameter(label: "Java_iface", type: .javaObjectPointer)]
        } else {
            instanceParameter = []
        }
        let callbackParameter = isAsync ? [TypeSignature.Parameter(label: "f_callback", type: .javaObjectPointer)] : []
        let cdeclType: TypeSignature = .function(instanceParameter + cdeclParameters + callbackParameter, cdeclReturnType, APIFlags(), nil)
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclType, body: cdeclBody)
        cdeclFunctions.append(cdeclFunction)

        let bodyCodeBlock = KotlinCodeBlock(statements: body.map { KotlinRawStatement(sourceCode: $0) })
        let externalStatements = externalFunctionDeclarations.map { KotlinRawStatement(sourceCode: $0, isStatic: isCompanionCall) }
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
        functionDeclaration.extras = Self.bridgeExtras(functionDeclaration.extras)
        let classWithAnyGenerics = classDeclaration.signature.withGenerics(of: .any)
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
        functionDeclaration.appendMainActorIsolated(&cdeclBody, in: classDeclaration, isReturn: true) { body, indentation in
            body.append(indentation, retString)
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
            let externalFunctionDeclaration = KotlinRawStatement(sourceCode: "private external fun Swift_isequal(lhs: skip.bridge.SwiftObjectPointer, rhs: skip.bridge.SwiftObjectPointer): Boolean")
            statements = [equals, externalFunctionDeclaration]
            sourceCode = [
                "if (other !is skip.bridge.SwiftPeerBridged) return false",
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
                "if (other !is skip.bridge.SwiftPeerBridged) return false",
                "return Swift_peer == other.Swift_peer()"
            ]
            cdeclFunction = nil
        }
        equals.body = KotlinCodeBlock(statements: sourceCode.map { KotlinRawStatement(sourceCode: $0) })
        return (statements, cdeclFunction)
    }

    private func updateHashDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, in classDeclaration: KotlinClassDeclaration) {
        functionDeclaration.extras = Self.bridgeExtras(functionDeclaration.extras)
        let bodySourceCode: [String]
        if functionDeclaration.isKotlinHashImplementation {
            // hashCode()
            bodySourceCode = ["return Swift_hashvalue(Swift_peer).hashCode()"]
        } else {
            // hash(into:)
            bodySourceCode = ["hasher.value.combine(Swift_hashvalue(Swift_peer))"]
        }
        functionDeclaration.body = KotlinCodeBlock(statements: bodySourceCode.map { KotlinRawStatement(sourceCode: $0) })

        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: "private external fun Swift_hashvalue(Swift_peer: skip.bridge.SwiftObjectPointer): Long")
        classDeclaration.insert(statements: [externalFunctionDeclaration], after: functionDeclaration)

        let classType = ClassType(classDeclaration)
        let (cdecl, cdeclName) = CDeclFunction.declaration(for: functionDeclaration, isCompanion: false, name: "Swift_hashvalue", translator: translator)
        let cdeclType: TypeSignature = .function([classType.peerSwiftParameter], .int64, APIFlags(), nil)
        var cdeclBody = classType.peerSwiftAssignment(to: classDeclaration, optionsString: "[]")
        functionDeclaration.appendMainActorIsolated(&cdeclBody, in: classDeclaration, isReturn: true) { body, indentation in
            switch classType {
            case .generic:
                body.append(indentation, "return Int64((\(classType.peerSwiftTarget).genericvalue as! (any Hashable)).hashValue)")
            default:
                body.append(indentation, "return Int64(\(classType.peerSwiftTarget).hashValue)")
            }
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

        let classType = ClassType(classDeclaration)
        let statements: [KotlinStatement]
        let sourceCode: [String]
        let cdeclFunction: CDeclFunction?
        if classType == .generic, classDeclaration.declarationType == .classDeclaration || classDeclaration.declarationType == .actorDeclaration {
            let externalFunctionDeclaration = KotlinRawStatement(sourceCode: "private external fun Swift_hashvalue(Swift_peer: skip.bridge.SwiftObjectPointer): Long")
            statements = [hash, externalFunctionDeclaration]
            sourceCode = ["return Swift_hashvalue(Swift_peer).hashCode()"]

            let (cdecl, cdeclName) = CDeclFunction.declaration(for: hash, isCompanion: false, name: "Swift_hashvalue", translator: translator)
            let cdeclType: TypeSignature = .function([classType.peerSwiftParameter], .int64, APIFlags(), nil)
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
        functionDeclaration.extras = Self.bridgeExtras(functionDeclaration.extras)
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
        functionDeclaration.appendMainActorIsolated(&cdeclBody, in: classDeclaration, isReturn: true) { body, indentation in
            body.append(indentation, retString)
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

        interfaceDeclaration.extras = Self.bridgeExtras(interfaceDeclaration.extras)
        interfaceDeclaration.inherits = interfaceDeclaration.inherits.compactMap {
            if $0.isNamed("Comparable") {
                return $0
            } else if let bridgable = $0.checkBridgable(direction: .toKotlin, options: options, generics: interfaceDeclaration.generics, codebaseInfo: codebaseInfo) {
                return bridgable.kotlinType
            } else {
                return nil
            }
        }
        var extensionFunctionCount = 0
        for member in interfaceDeclaration.members {
            if let variableDeclaration = member as? KotlinVariableDeclaration {
                let isExtension = extensions.contains { info in
                    info.variables.contains { $0.name == (variableDeclaration.preEscapedPropertyName ?? variableDeclaration.propertyName) }
                }
                if isExtension {
                    update(variableDeclaration, inExtensionOf: interfaceDeclaration)
                } else {
                    if let bridgable = variableDeclaration.checkBridgable(direction: .toKotlin, options: options, translator: translator) {
                        updateDeclaration(variableDeclaration, with: bridgable)
                        KotlinBridgeToSwiftVisitor.appendCallbackFunction(for: variableDeclaration, bridgable: bridgable, modifiers: variableDeclaration.modifiers)
                    }
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
                    if let bridgable = functionDeclaration.checkBridgable(direction: .toKotlin, options: options, translator: translator) {
                        updateDeclaration(functionDeclaration, with: bridgable)
                        KotlinBridgeToSwiftVisitor.appendCallbackFunction(for: functionDeclaration, bridgable: bridgable, modifiers: functionDeclaration.modifiers)
                    }
                }
            }
        }

        // Must do this last after determining member generic constraints
        interfaceDeclaration.generics = interfaceDeclaration.generics.compactMapBridgable(direction: .toKotlin, options: options, codebaseInfo: codebaseInfo)
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
        let classType = ClassType(classDeclaration)
        let isNonGenericEnum = classType == .sealedClassesEnum || classType == .enum
        let superclassCall: String?
        var clearSuperclassCall = false
        if isNonGenericEnum {
            superclassCall = nil
        } else if let call = classDeclaration.superclassCall {
            if let argumentsStart = call.firstIndex(of: "(") {
                superclassCall = "super" + call[argumentsStart...]
            } else {
                superclassCall = "super()"
            }
            clearSuperclassCall = true
        } else {
            superclassCall = nil
        }

        let isError = classDeclaration.inherits.first?.isNamed("Exception") == true && classDeclaration.inherits.contains { $0.isNamed("Error", moduleName: "Swift", generics: []) }
        let mappedInherits: [TypeSignature] = classDeclaration.inherits.compactMap {
            if includesUI {
                switch $0.swiftUIType {
                case .none:
                    break
                case .view:
                    return .skipUIView
                case .viewModifier:
                    return .skipUIViewModifier
                case .toolbarContent:
                    return .skipUIToolbarContent
                }
            }
            if (classDeclaration.declarationType == .actorDeclaration && $0.isNamed("Actor"))
                || (isError && $0.isNamed("Exception"))
                || (isError && $0.isNamed("Error"))
                || $0.isNamed("Comparable")
                || $0.isNamed("MutableStruct") {
                return $0
            } else if let bridgable = $0.checkBridgable(direction: .toKotlin, options: options, generics: classDeclaration.generics, codebaseInfo: codebaseInfo) {
                return bridgable.kotlinType
            } else {
                return nil
            }
        }
        let swiftUIType = classDeclaration.swiftUIType
        if swiftUIType != .none && classDeclaration.modifiers.visibility == .private {
            classDeclaration.messages.append(.kotlinBridgeViewPrivate(classDeclaration, source: syntaxTree.source))
            return false
        }

        classDeclaration.inherits = mappedInherits
        classDeclaration.extras = Self.bridgeExtras(classDeclaration.extras)
        if clearSuperclassCall {
            classDeclaration.superclassCall = nil
        }

        var insertStatements: [KotlinStatement] = []
        if !isNonGenericEnum {
            if subclassDepth < 1 {
                classDeclaration.inherits.append(.named("skip.bridge.SwiftPeerBridged", []))

                let swiftPeerType: TypeSignature = .swiftObjectPointer(kotlin: true)
                let swiftPeer = KotlinVariableDeclaration(names: ["Swift_peer"], variableTypes: [swiftPeerType])
                swiftPeer.role = .property
                swiftPeer.modifiers.visibility = .public
                swiftPeer.apiFlags.options = .writeable
                swiftPeer.declaredType = swiftPeerType
                swiftPeer.value = KotlinRawExpression(sourceCode: "skip.bridge.SwiftObjectNil")
                swiftPeer.isGenerated = true
                insertStatements.append(swiftPeer)
            }

            if !classDeclaration.isSealedClassesEnum {
                let swiftPeerConstructor = KotlinFunctionDeclaration(name: "constructor")
                swiftPeerConstructor.modifiers.visibility = .public
                swiftPeerConstructor.parameters = [Parameter<KotlinExpression>(externalLabel: "Swift_peer", declaredType: .swiftObjectPointer(kotlin: true)), Parameter<KotlinExpression>(externalLabel: "marker", declaredType: .named("skip.bridge.SwiftPeerMarker", []).asOptional(true))]
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
                    "Swift_peer = skip.bridge.SwiftObjectNil"
                ].map { KotlinRawStatement(sourceCode: $0) })
                finalize.ensureLeadingNewlines(1)
                finalize.isGenerated = true
                insertStatements.append(finalize)

                let release = KotlinRawStatement(sourceCode: "private external fun Swift_release(Swift_peer: skip.bridge.SwiftObjectPointer)")
                insertStatements.append(release)
            }

            if swiftUIType == .none && !classDeclaration.unbridgedMembers.suppressDefaultConstructorGeneration && classType != .generic && !classDeclaration.members.contains(where: { $0.type == .constructorDeclaration }) {
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
                let externalConstructor = KotlinRawStatement(sourceCode: "private external fun \(externalConstructorName)(): skip.bridge.SwiftObjectPointer")
                externalConstructor.isStatic = subclassDepth >= 1
                insertStatements.append(externalConstructor)

                let constructorCdecl = CDeclFunction.declaration(for: classDeclaration, isCompanion: subclassDepth >= 1, name: externalConstructorName, translator: translator)
                var constructorBody: [String] = []
                appendMainActorIsolated(&constructorBody, in: classDeclaration, attributes: Attributes(), modifiers: Modifiers(), isReturn: true) { body, indentation in
                    if classType == .reference {
                        body.append("let f_return_swift = \(classDeclaration.signature)()")
                    } else {
                        body.append("let f_return_swift = SwiftValueTypeBox(\(classDeclaration.signature)())")
                    }
                    body.append("return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)")
                }
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
                switch classType {
                case .generic:
                    releaseBody.append("Swift_peer.release(as: \(classDeclaration.signature.typeErasedClass).self)")
                case .reference:
                    releaseBody.append("Swift_peer.release(as: \(classDeclaration.signature).self)")
                default:
                    releaseBody.append("Swift_peer.release(as: SwiftValueTypeBox<\(classDeclaration.signature)>.self)")
                }
                cdeclFunctions.append(CDeclFunction(name: releaseCdecl.cdeclFunctionName, cdecl: releaseCdecl.cdecl, signature: .function([classType.peerSwiftParameter], .void, APIFlags(), nil), body: releaseBody))
            }
        }

        var hasEqualsDeclaration = false
        var hasHashDeclaration = false
        var functionCount = 0
        var bridgedVariableDeclarations: [KotlinVariableDeclaration] = []
        var bridgedFunctionDeclarations: [(KotlinFunctionDeclaration, Int?)] = []
        var enumCases: [KotlinEnumCaseDeclaration] = []
        var enumCaseBridgables: [[Bridgable]] = []
        for member in classDeclaration.members {
            if let enumCaseDeclaration = member as? KotlinEnumCaseDeclaration {
                enumCases.append(enumCaseDeclaration)
                if let bridgables = enumCaseDeclaration.checkBridgable(direction: .toKotlin, options: options, translator: translator) {
                    enumCaseBridgables.append(bridgables)
                    enumCaseDeclaration.associatedValues = enumCaseDeclaration.associatedValues.enumerated().map { entry in
                        var associatedValue = entry.element
                        associatedValue.declaredType = bridgables[entry.offset].kotlinType
                        return associatedValue
                    }
                }
            } else if let variableDeclaration = member as? KotlinVariableDeclaration {
                if (swiftUIType == .view || swiftUIType == .toolbarContent), variableDeclaration.propertyName == "body" {
                    // We substitute our own body
                    classDeclaration.remove(statement: variableDeclaration)
                } else if update(variableDeclaration, in: classDeclaration) {
                    bridgedVariableDeclarations.append(variableDeclaration)
                }
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                if swiftUIType == .viewModifier && functionDeclaration.name == "body" && functionDeclaration.parameters.count == 1 && functionDeclaration.parameters[0].externalLabel == "content" {
                    // We substitute our own body
                    classDeclaration.remove(statement: functionDeclaration)
                } else if functionDeclaration.isEqualImplementation || functionDeclaration.isKotlinEqualImplementation {
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
        classDeclaration.generics = classDeclaration.generics.compactMapBridgable(direction: .toKotlin, options: options, codebaseInfo: codebaseInfo)

        let isEmptyEnum = classDeclaration.declarationType == .enumDeclaration && enumCases.isEmpty
        let finalMemberVisibility = min(classDeclaration.modifiers.visibility, .public)
        var swiftUIStateVariables: [(String, Attributes, Modifiers)] = []
        var additionalSwiftDeclarations: [String] = []
        var additionalCDeclFunctions: [CDeclFunction] = []
        if swiftUIType != .none {
            let (stateVariables, statements, swift, cdeclFunctions) = addSwiftUIImplementation(swiftUIType, to: classDeclaration, visibility: finalMemberVisibility)
            swiftUIStateVariables = stateVariables
            insertStatements += statements
            additionalSwiftDeclarations += swift
            additionalCDeclFunctions += cdeclFunctions
        }

        (classDeclaration.children.first as? KotlinStatement)?.ensureLeadingNewlines(1)
        classDeclaration.insert(statements: insertStatements, after: nil)

        let classRef: JavaClassRef?
        var conformances: String
        if isEmptyEnum {
            classRef = nil
            conformances = ""
        } else {
            // Conform to `BridgedToKotlin`
            classRef = JavaClassRef(for: classDeclaration.signature, packageName: translator.packageName)
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
            switch swiftUIType {
            case .none:
                break
            case .view:
                conformances += ", SkipUIBridging, SkipUI.View"
            case .viewModifier:
                conformances += ", SkipUI.ViewModifier"
            case .toolbarContent:
                conformances += ", SkipUIBridging, SkipUI.ToolbarContent"
            }
        }
        var swift: [String] = []
        if !conformances.isEmpty {
            conformances = ": " + conformances
        }
        swift.append("extension \(classDeclaration.signature.withGenerics([]))\(conformances) {")
        if let classRef {
            swift.append(1, classRef.declaration())
            if classDeclaration.declarationType == .enumDeclaration {
                swift.append(1, declareStaticLet("Java_Companion_class", ofType: "JClass", in: classDeclaration.signature, value: "try! JClass(name: \"\(classRef.className)$Companion\")"))
                swift.append(1, declareStaticLet("Java_Companion", ofType: "JObject", in: classDeclaration.signature, value: "JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: \"Companion\", sig: \"L\(classRef.className)$Companion;\")!, options: \(options.jconvertibleOptions)))"))
            }
            if isNonGenericEnum {
                swift.append(1, KotlinBridgeToSwiftVisitor.swiftForEnumJConvertibleContract(className: classRef.className, generics: classRef.generics, isSealedClassesEnum: classDeclaration.isSealedClassesEnum, caseDeclarations: enumCases, bridgables: enumCaseBridgables, visibility: finalMemberVisibility, options: options, translator: translator))
            } else {
                let finalMemberVisibilityString = finalMemberVisibility.swift(suffix: " ")
                if subclassDepth < 1 {
                    swift.append(1, "nonisolated \(finalMemberVisibilityString)static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {")
                    swift.append(2, "let ptr = SwiftObjectPointer.peer(of: obj!, options: options)")
                    switch classType {
                    case .generic:
                        swift.append(2, "let typeErased: \(classDeclaration.signature.typeErasedClass) = ptr.pointee()!")
                        swift.append(2, "return typeErased.genericvalue as! Self")
                    case .reference:
                        swift.append(2, "return ptr.pointee()!")
                    default:
                        swift.append(2, "let box: SwiftValueTypeBox<Self> = ptr.pointee()!")
                        swift.append(2, "return box.value")
                    }
                    swift.append(1, "}")

                    swift.append(1, "nonisolated \(finalMemberVisibilityString)func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {")
                    switch classType {
                    case .generic:
                        swift.append(2, "let typeErased = toTypeErased()")
                        swift.append(2, "let Swift_peer = SwiftObjectPointer.pointer(to: typeErased, retain: true)")
                    case .reference:
                        swift.append(2, "let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)")
                    default:
                        swift.append(2, "let box = SwiftValueTypeBox(self)")
                        swift.append(2, "let Swift_peer = SwiftObjectPointer.pointer(to: box, retain: true)")
                    }
                    if classDeclaration.declarationType == .enumDeclaration {
                        let (code, declarations) = KotlinBridgeToSwiftVisitor.swiftForGenericEnumToJavaObjectSwitch(className: classRef.className, generics: classRef.generics, peerName: "Swift_peer", caseDeclarations: enumCases, bridgables: enumCaseBridgables, visibility: finalMemberVisibility, options: options, translator: translator)
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
                    swift.append(1, declareStaticLet("Java_constructor_methodID", ofType: "JavaMethodID", in: classDeclaration.signature, value: "Java_class.getMethodID(name: \"<init>\", sig: \"(JLskip/bridge/SwiftPeerMarker;)V\")!"))
                    if subclassDepth >= 1 {
                        swift.append(1, declareStaticLet("Java_subclass\(subclassDepth)Constructor", ofType: "(JClass, JavaMethodID)", visibility: finalMemberVisibility, in: classDeclaration.signature, value: "(Java_class, Java_constructor_methodID)"))
                    }
                }
            }
        }
        swift.append(1, additionalSwiftDeclarations)
        swift.append("}")

        let swiftDefinition = SwiftDefinition(swift: swift)
        swiftDefinitions.append(swiftDefinition)

        if !classDeclaration.generics.isEmpty {
            swiftDefinitions.append(typeErasedPeerSwift(for: classDeclaration, variableDeclarations: bridgedVariableDeclarations, functionDeclarations: bridgedFunctionDeclarations, stateVariables: swiftUIStateVariables, visibility: finalMemberVisibility))
        }

        let customProjection: [String]? = classDeclaration.generics.isEmpty ? nil : [
            "let ptr = SwiftObjectPointer.peer(of: Java_target, options: JConvertibleOptions(rawValue: Int(options)))",
            "let peer_swift: \(classDeclaration.signature.typeErasedClass) = ptr.pointee()!",
            "let projection = peer_swift.genericvalue"
        ]
        if !isEmptyEnum {
            let cdeclFunction = KotlinBridgeToSwiftVisitor.addSwiftProjecting(to: classDeclaration, isBridgedSubclass: subclassDepth >= 1, customProjection: customProjection, options: options, translator: translator)
            cdeclFunctions.append(cdeclFunction)
        }
        cdeclFunctions += additionalCDeclFunctions
        return true
    }

    private static func bridgeExtras(_ extras: StatementExtras?) -> StatementExtras? {
        guard let extras else {
            return nil
        }
        // We currently only carry over .nowarn so that bridged types can suppress warnings
        guard extras.directives.contains(.nowarn) else {
            return nil
        }
        return StatementExtras(directives: [.nowarn], leadingTrivia: [], trailingTrivia: [])
    }

    private func typeErasedPeerSwift(for classDeclaration: KotlinClassDeclaration, variableDeclarations: [KotlinVariableDeclaration], functionDeclarations: [(KotlinFunctionDeclaration, uniquifier: Int?)], stateVariables: [(String, Attributes, Modifiers)], visibility: Modifiers.Visibility) -> SwiftDefinition {
        let visibilityString = visibility.swift(suffix: " ")
        var swift: [String] = []
        swift.append("extension \(classDeclaration.signature.withGenerics([])): TypeErasedConvertible {")
        swift.append(1, "nonisolated \(visibilityString)func toTypeErased() -> AnyObject {")
        swift.append(2, "let typeErased = \(classDeclaration.signature.typeErasedClass)(self)")
        swift.append(2, typeErasedClosureSwift(for: classDeclaration, to: "typeErased", variableDeclarations: variableDeclarations, functionDeclarations: functionDeclarations, stateVariables: stateVariables))
        swift.append(2, "return typeErased")
        swift.append(1, "}")
        swift.append("}")

        swift.append("private final class \(classDeclaration.signature.typeErasedClass) : @unchecked Sendable {")
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
            let getter = variableDeclaration.isAppendAsFunction ? variableDeclaration.propertyName.addingBacktickEscapingIfNeeded : "get_\(variableDeclaration.propertyName)"
            let type: TypeSignature = .any.asOptional(variableDeclaration.propertyType.isOptional)
            let mainActorString = variableDeclaration.isMainActorIsolated(in: classDeclaration) ? "@MainActor " : ""
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
            let mainActorString = functionDeclaration.isMainActorIsolated(in: classDeclaration) ? "@MainActor " : ""
            let asyncString = functionDeclaration.apiFlags.options.contains(.async) ? " async" : ""
            let throwsString = functionDeclaration.apiFlags.throwsType != .none ? " throws" : ""
            swift.append(1, "var \(functionName)\(uniquifierString): (\(mainActorString)(\(parametersString))\(asyncString)\(throwsString) -> \(returnType))!")
        }
        if let isEqualDeclaration {
            let mainActorString = isEqualDeclaration.isMainActorIsolated(in: classDeclaration) ? "@MainActor " : ""
            swift.append(1, "var isequal: (\(mainActorString)(Any) -> Bool)!")
        }
        if let isLessThanDeclaration {
            let mainActorString = isLessThanDeclaration.isMainActorIsolated(in: classDeclaration) ? "@MainActor " : ""
            swift.append(1, "var islessthan: (\(mainActorString)(Any) -> Bool)!")
        }

        let swiftUIType = classDeclaration.swiftUIType
        if swiftUIType == .view || swiftUIType == .toolbarContent {
            swift.append(1, "var body: (@MainActor () -> Any)!")
        } else if swiftUIType != .none {
            swift.append(1, "var body: (@MainActor (JavaBackedView) -> Any)!")
        }
        for (name, attributes, modifiers) in stateVariables {
            let mainActorString = isMainActorIsolated(in: classDeclaration, attributes: attributes, modifiers: modifiers) ? "@MainActor " : ""
            if attributes.stateAttribute != nil || attributes.contains(.focusState) || attributes.contains(.gestureState) || attributes.contains(.appStorage) {
                swift.append(1, "var Java_initState_\(name): (\(mainActorString)() -> SkipUI.StateSupport)!")
                swift.append(1, "var Java_syncState_\(name): (\(mainActorString)(SkipUI.StateSupport) -> Void)!")
            } else if attributes.environmentAttribute != nil {
                swift.append(1, "var Java_initEnvironment_\(name): (\(mainActorString)() -> String)!")
                swift.append(1, "var Java_syncEnvironment_\(name): (\(mainActorString)(SkipUI.EnvironmentSupport?) -> Void)!")
            }
        }
        swift.append("}")
        return SwiftDefinition(swift: swift)
    }

    private func typeErasedClosureSwift(for classDeclaration: KotlinClassDeclaration, to target: String, variableDeclarations: [KotlinVariableDeclaration], functionDeclarations: [(KotlinFunctionDeclaration, uniquifier: Int?)], stateVariables: [(String, Attributes, Modifiers)]) -> [String] {
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

        let swiftUIType = classDeclaration.swiftUIType
        if swiftUIType == .view || swiftUIType == .toolbarContent {
            swift.append("\(target).body = { [unowned \(target)] in (\(target).genericvalue as! Self).body }")
        } else if swiftUIType != .none {
            swift.append("\(target).body = { [unowned \(target)] in (\(target).genericvalue as! Self).body($0) }")
        }
        for (name, attributes, _) in stateVariables {
            if attributes.stateAttribute != nil || attributes.contains(.focusState) || attributes.contains(.gestureState) || attributes.contains(.appStorage) {
                swift.append("\(target).Java_initState_\(name) = { [unowned \(target)] in (\(target).genericvalue as! Self).Java_initState_\(name)() }")
                swift.append("\(target).Java_syncState_\(name) = { [unowned \(target)] in (\(target).genericvalue as! Self).Java_syncState_\(name)(support: $0) }")
            } else if attributes.environmentAttribute != nil {
                swift.append("\(target).Java_initEnvironment_\(name) = { [unowned \(target)] in (\(target).genericvalue as! Self).Java_initEnvironment_\(name)() }")
                swift.append("\(target).Java_syncEnvironment_\(name) = { [unowned \(target)] in (\(target).genericvalue as! Self).Java_syncEnvironment_\(name)(support: $0) }")
            }
        }
        return swift
    }

    private func addSwiftUIImplementation(_ swiftUIType: TypeSignature.SwiftUIType, to classDeclaration: KotlinClassDeclaration, visibility: Modifiers.Visibility) -> (stateVariables: [(String, Attributes, Modifiers)], statements: [KotlinStatement], swift: [String], cdeclFunctions: [CDeclFunction]) {
        var statements: [KotlinStatement] = []
        var swift: [String] = []
        var cdeclFunctions: [CDeclFunction] = []

        let stateVariables: [(String, Attributes, Modifiers)] = classDeclaration.unbridgedMembers.compactMap { (unbridged: UnbridgedMember) -> (String, Attributes, Modifiers)? in
            guard case .swiftUIStateProperty(let name, let attributes, let modifiers) = unbridged else {
                return nil
            }
            guard modifiers.visibility >= .default else {
                classDeclaration.messages.append(.kotlinBridgeStatePrivate(classDeclaration, property: name, source: syntaxTree.source))
                return nil
            }
            return (name, attributes, modifiers)
        }
        if !stateVariables.isEmpty {
            statements += swiftUIEvaluate(swiftUIType, for: classDeclaration, stateVariables: stateVariables)
            for (name, attributes, modifiers) in stateVariables {
                var initStatements: [KotlinStatement] = []
                var syncStatements: [KotlinStatement] = []
                var initSwift: [String] = []
                var syncSwift: [String] = []
                var initCdeclFunctions: [CDeclFunction] = []
                var syncCdeclFunctions: [CDeclFunction] = []
                if attributes.stateAttribute != nil || attributes.contains(.focusState) || attributes.contains(.gestureState) || attributes.contains(.appStorage) {
                    let supportTypeName: String
                    let boxName: String
                    if attributes.contains(.appStorage) {
                        supportTypeName = "AppStorageSupport"
                        boxName = "appStorageBox"
                    } else {
                        supportTypeName = "StateSupport"
                        boxName = "valueBox"
                    }
                    (initStatements, initSwift, initCdeclFunctions) = swiftUIInitState(swiftUIType, for: name, in: classDeclaration, supportTypeName: supportTypeName, boxName: boxName, attributes: attributes, modifiers: modifiers)
                    (syncStatements, syncSwift, syncCdeclFunctions) = swiftUISyncState(swiftUIType, for: name, in: classDeclaration, supportTypeName: supportTypeName, boxName: boxName, attributes: attributes, modifiers: modifiers)
                } else if attributes.environmentAttribute != nil {
                    (initStatements, initSwift, initCdeclFunctions) = swiftUIInitEnvironment(swiftUIType, for: name, in: classDeclaration, attributes: attributes, modifiers: modifiers)
                    (syncStatements, syncSwift, syncCdeclFunctions) = swiftUISyncEnvironment(swiftUIType, for: name, in: classDeclaration, attributes: attributes, modifiers: modifiers)
                }
                statements += initStatements + syncStatements
                swift += initSwift + syncSwift
                cdeclFunctions += initCdeclFunctions + syncCdeclFunctions
            }
        }

        let (bodyStatements, bodySwift, bodyCdeclFunctions) = swiftUIBodyImplementation(swiftUIType, for: classDeclaration, visibility: visibility)
        statements += bodyStatements
        swift += bodySwift
        cdeclFunctions += bodyCdeclFunctions

        return (stateVariables, statements, swift, cdeclFunctions)
    }

    private func swiftUIEvaluate(_ swiftUIType: TypeSignature.SwiftUIType, for classDeclaration: KotlinClassDeclaration, stateVariables: [(name: String, attributes: Attributes, modifiers: Modifiers)]) -> [KotlinStatement] {
        let functionDeclaration = KotlinFunctionDeclaration(name: "Evaluate")
        var functionParameters: [Parameter<KotlinExpression>] = []
        if swiftUIType != .view && swiftUIType != .toolbarContent {
            functionParameters.append(Parameter<KotlinExpression>(externalLabel: "content", declaredType: .named("skip.ui.View", [])))
        }
        functionParameters.append(Parameter<KotlinExpression>(externalLabel: "context", declaredType: .named("skip.ui.ComposeContext", [])))
        functionParameters.append(Parameter<KotlinExpression>(externalLabel: "options", declaredType: .int))
        functionDeclaration.parameters = functionParameters
        functionDeclaration.returnType = .named("kotlin.collections.List", [.named("Renderable", [])])
        functionDeclaration.modifiers = Modifiers(visibility: .public, isOverride: true)
        functionDeclaration.attributes.attributes.append(Attribute(signature: .named("androidx.compose.runtime.Composable", [])))
        functionDeclaration.extras = .singleNewline

        let classType = ClassType(classDeclaration)
        var bodyKotlin: [String] = []
        for (name, attributes, _) in stateVariables {
            if attributes.stateAttribute != nil || attributes.contains(.focusState) || attributes.contains(.gestureState) || attributes.contains(.appStorage) {
                let supportTypeName = attributes.contains(.appStorage) ? "AppStorageSupport" : "StateSupport"
                bodyKotlin.append("val remembered\(name) = androidx.compose.runtime.saveable.rememberSaveable(stateSaver = context.stateSaver as androidx.compose.runtime.saveable.Saver<skip.ui.\(supportTypeName), Any>) { androidx.compose.runtime.mutableStateOf(Swift_initState_\(name)(\(classType.peerExternalArgument))) }")
                bodyKotlin.append("Swift_syncState_\(name)(\(classType.peerExternalArgument), remembered\(name).value)")
            } else if attributes.environmentAttribute != nil {
                bodyKotlin.append("val envkey\(name) = Swift_initEnvironment_\(name)(\(classType.peerExternalArgument))")
                bodyKotlin.append("val envvalue\(name) = skip.ui.EnvironmentValues.shared.bridged(envkey\(name))")
                bodyKotlin.append("Swift_syncEnvironment_\(name)(\(classType.peerExternalArgument), envvalue\(name))")
            }
        }
        if swiftUIType != .view && swiftUIType != .toolbarContent {
            bodyKotlin.append("return super.Evaluate(content, context, options)")
        } else {
            bodyKotlin.append("return super.Evaluate(context, options)")
        }
        functionDeclaration.body = KotlinCodeBlock(statements: bodyKotlin.map { KotlinRawStatement(sourceCode: $0) })
        return [functionDeclaration]
    }

    private func swiftUIInitState(_ swiftUIType: TypeSignature.SwiftUIType, for name: String, in classDeclaration: KotlinClassDeclaration, supportTypeName: String, boxName: String, attributes: Attributes, modifiers: Modifiers) -> (statements: [KotlinStatement], swift: [String], cdeclFunctions: [CDeclFunction]) {
        let classType = ClassType(classDeclaration)
        let externalName = "Swift_initState_\(name)"
        let externalSourceCode = "private external fun \(externalName)(\(classType.peerExternalParameter)): skip.ui.\(supportTypeName)"
        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: externalSourceCode)
        externalFunctionDeclaration.parent = classDeclaration

        var source: [String] = []
        let isolationString = modifiers.isNonisolated ? "nonisolated " : ""
        source.append("\(isolationString)func Java_initState_\(name)() -> SkipUI.\(supportTypeName) {")
        source.append(1, "return $\(name).\(boxName)!.Java_initStateSupport()")
        source.append("}")

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: externalFunctionDeclaration, isCompanion: false, name: externalName, translator: translator)
        let cdeclSignature: TypeSignature = .function([classType.peerSwiftParameter], .javaObjectPointer, APIFlags(), nil)
        var cdeclSource = classType.peerSwiftAssignment(to: classDeclaration, optionsString: "[]")
        appendMainActorIsolated(&cdeclSource, in: classDeclaration, attributes: attributes, modifiers: modifiers, isReturn: true) { body, indentation in
            body.append(indentation, "return \(classType.peerSwiftTarget).Java_initState_\(name)().toJavaObject(options: [])!")
        }
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclSignature, body: cdeclSource)
        return ([externalFunctionDeclaration], source, [cdeclFunction])
    }

    private func swiftUISyncState(_ swiftUIType: TypeSignature.SwiftUIType, for name: String, in classDeclaration: KotlinClassDeclaration, supportTypeName: String, boxName: String, attributes: Attributes, modifiers: Modifiers) -> (statements: [KotlinStatement], swift: [String], cdeclFunctions: [CDeclFunction]) {
        let classType = ClassType(classDeclaration)
        let externalName = "Swift_syncState_\(name)"
        let externalSourceCode = "private external fun \(externalName)(\(classType.peerExternalParameter), support: skip.ui.\(supportTypeName))"
        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: externalSourceCode)
        externalFunctionDeclaration.parent = classDeclaration

        var source: [String] = []
        let isolationString = modifiers.isNonisolated ? "nonisolated " : ""
        source.append("\(isolationString)func Java_syncState_\(name)(support: SkipUI.\(supportTypeName)) {")
        source.append(1, "$\(name).\(boxName)!.Java_syncStateSupport(support)")
        source.append("}")

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: externalFunctionDeclaration, isCompanion: false, name: externalName, translator: translator)
        let cdeclSignature: TypeSignature = .function([classType.peerSwiftParameter, TypeSignature.Parameter(label: "support", type: .javaObjectPointer)], .void, APIFlags(), nil)
        let argumentString = classType == .generic ? "support_swift" : "support: support_swift"
        var cdeclSource = classType.peerSwiftAssignment(to: classDeclaration, optionsString: "[]")
        appendMainActorIsolated(&cdeclSource, in: classDeclaration, locals: ["support"], attributes: attributes, modifiers: modifiers) { body, indentation in
            body.append(indentation, "let support_swift = SkipUI.\(supportTypeName).fromJavaObject(support, options: [])")
            body.append(indentation, "\(classType.peerSwiftTarget).Java_syncState_\(name)(\(argumentString))")
        }
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclSignature, body: cdeclSource)
        return ([externalFunctionDeclaration], source, [cdeclFunction])
    }

    private func swiftUIInitEnvironment(_ swiftUIType: TypeSignature.SwiftUIType, for name: String, in classDeclaration: KotlinClassDeclaration, attributes: Attributes, modifiers: Modifiers) -> (statements: [KotlinStatement], swift: [String], cdeclFunctions: [CDeclFunction]) {
        let classType = ClassType(classDeclaration)
        let externalName = "Swift_initEnvironment_\(name)"
        let externalSourceCode = "private external fun \(externalName)(\(classType.peerExternalParameter)): String"
        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: externalSourceCode)
        externalFunctionDeclaration.parent = classDeclaration

        var source: [String] = []
        let isolationString = modifiers.isNonisolated ? "nonisolated " : ""
        source.append("\(isolationString)func Java_initEnvironment_\(name)() -> String {")
        source.append(1, "return $\(name).key")
        source.append("}")

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: externalFunctionDeclaration, isCompanion: false, name: externalName, translator: translator)
        let cdeclSignature: TypeSignature = .function([classType.peerSwiftParameter], .javaString, APIFlags(), nil)
        var cdeclSource = classType.peerSwiftAssignment(to: classDeclaration, optionsString: "[]")
        appendMainActorIsolated(&cdeclSource, in: classDeclaration, attributes: attributes, modifiers: modifiers, isReturn: true) { body, indentation in
            body.append(indentation, "return \(classType.peerSwiftTarget).Java_initEnvironment_\(name)().toJavaObject(options: [])!")
        }
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclSignature, body: cdeclSource)
        return ([externalFunctionDeclaration], source, [cdeclFunction])
    }

    private func swiftUISyncEnvironment(_ swiftUIType: TypeSignature.SwiftUIType, for name: String, in classDeclaration: KotlinClassDeclaration, attributes: Attributes, modifiers: Modifiers) -> (statements: [KotlinStatement], swift: [String], cdeclFunctions: [CDeclFunction]) {
        let classType = ClassType(classDeclaration)
        let externalName = "Swift_syncEnvironment_\(name)"
        let externalSourceCode = "private external fun \(externalName)(\(classType.peerExternalParameter), support: skip.ui.EnvironmentSupport?)"
        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: externalSourceCode)
        externalFunctionDeclaration.parent = classDeclaration

        var source: [String] = []
        let isolationString = modifiers.isNonisolated ? "nonisolated " : ""
        source.append("\(isolationString)func Java_syncEnvironment_\(name)(support: SkipUI.EnvironmentSupport?) {")
        source.append(1, "$\(name).Java_syncEnvironmentSupport(support)")
        source.append("}")

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: externalFunctionDeclaration, isCompanion: false, name: externalName, translator: translator)
        let cdeclSignature: TypeSignature = .function([classType.peerSwiftParameter, TypeSignature.Parameter(label: "support", type: .optional(.javaObjectPointer))], .void, APIFlags(), nil)
        let argumentString = classType == .generic ? "support_swift" : "support: support_swift"
        var cdeclSource = classType.peerSwiftAssignment(to: classDeclaration, optionsString: "[]")
        appendMainActorIsolated(&cdeclSource, in: classDeclaration, locals: ["support"], attributes: attributes, modifiers: modifiers) { body, indentation in
            body.append(indentation, "let support_swift = SkipUI.EnvironmentSupport?.fromJavaObject(support, options: [])")
            body.append(indentation, "\(classType.peerSwiftTarget).Java_syncEnvironment_\(name)(\(argumentString))")
        }
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclSignature, body: cdeclSource)
        return ([externalFunctionDeclaration], source, [cdeclFunction])
    }

    private func swiftUIBodyImplementation(_ swiftUIType: TypeSignature.SwiftUIType, for classDeclaration: KotlinClassDeclaration, visibility: Modifiers.Visibility) -> (statements: [KotlinStatement], swift: [String], cdeclFunctions: [CDeclFunction]) {
        let classType = ClassType(classDeclaration)
        let externalName = "Swift_composableBody"
        let externalParameters = swiftUIType == .view || swiftUIType == .toolbarContent ? classType.peerExternalParameter : "\(classType.peerExternalParameter), content: skip.ui.View"
        let externalArguments = swiftUIType == .view || swiftUIType == .toolbarContent ? classType.peerExternalArgument : "\(classType.peerExternalArgument), content"
        let externalSourceCode = "private external fun \(externalName)(\(externalParameters)): skip.ui.View?"
        let functionSourceCode = "return skip.ui.ComposeBuilder { composectx: skip.ui.ComposeContext -> \(externalName)(\(externalArguments))?.Compose(composectx) ?: skip.ui.ComposeResult.ok }"
        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: externalSourceCode)

        let functionDeclaration = KotlinFunctionDeclaration(name: "body")
        if swiftUIType != .view && swiftUIType != .toolbarContent {
            functionDeclaration.parameters = [Parameter<KotlinExpression>(externalLabel: "content", declaredType: .named("skip.ui.View", []))]
        }
        functionDeclaration.returnType = .skipUIView
        functionDeclaration.modifiers = Modifiers(visibility: .public, isOverride: true)
        functionDeclaration.extras = .singleNewline
        functionDeclaration.body = KotlinCodeBlock(statements: [KotlinRawStatement(sourceCode: functionSourceCode)])
        functionDeclaration.body?.disallowSingleStatementAppend = true
        functionDeclaration.parent = classDeclaration

        var swift: [String] = []
        let visibilityString = visibility.swift(suffix: " ")
        if swiftUIType == .view || swiftUIType == .toolbarContent {
            swift.append("nonisolated \(visibilityString)var Java_view: any SkipUI.View {")
        } else {
            swift.append("nonisolated \(visibilityString)var Java_modifier: any SkipUI.ViewModifier {")
        }
        swift.append(1, "return self")
        swift.append("}")

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: functionDeclaration, isCompanion: false, name: externalName, translator: translator)
        var cdeclParameters = [classType.peerSwiftParameter]
        if swiftUIType != .view && swiftUIType != .toolbarContent {
            cdeclParameters.append(TypeSignature.Parameter(label: "content", type: .javaObjectPointer))
        }
        let cdeclSignature: TypeSignature = .function(cdeclParameters, .optional(.javaObjectPointer), APIFlags(), nil)
        var cdeclSource = classType.peerSwiftAssignment(to: classDeclaration, optionsString: "[]")
        let bodyInvocation: String
        if swiftUIType == .view || swiftUIType == .toolbarContent {
            if classType == .generic {
                bodyInvocation = "let body = \(classType.peerSwiftTarget).body()"
            } else {
                bodyInvocation = "let body = \(classType.peerSwiftTarget).body"
            }
        } else {
            cdeclSource.append("let content_swift = JavaBackedView(content)!")
            if classType == .generic {
                bodyInvocation = "let body = \(classType.peerSwiftTarget).body(content_swift)"
            } else {
                bodyInvocation = "let body = \(classType.peerSwiftTarget).body(content: content_swift)"
            }
        }
        cdeclSource.append("return SkipBridge.assumeMainActorUnchecked {")
        cdeclSource.append(1, bodyInvocation)
        cdeclSource.append(1, "return ((body as? SkipUIBridging)?.Java_view as? JConvertible)?.toJavaObject(options: [])")
        cdeclSource.append("}")
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclSignature, body: cdeclSource)

        return ([functionDeclaration, externalFunctionDeclaration], swift, [cdeclFunction])
    }
}

private enum ClassType : Equatable {
    case reference
    case value
    case generic
    case sealedClassesEnum
    case `enum`

    init(_ declaration: KotlinClassDeclaration) {
        if !declaration.generics.isEmpty {
            self = .generic
        } else if declaration.isSealedClassesEnum {
            self = .sealedClassesEnum
        } else if declaration.declarationType == .enumDeclaration {
            self = .enum
        } else if declaration.declarationType == .classDeclaration || declaration.declarationType == .actorDeclaration {
            self = .reference
        } else {
            self = .value
        }
    }

    init?(_ declaration: KotlinClassDeclaration?) {
        guard let declaration else {
            return nil
        }
        self.init(declaration)
    }

    var peerExternalArgument: String {
        switch self {
        case .sealedClassesEnum:
            return "javaClass.name"
        case .enum:
            return "name"
        default:
            return "Swift_peer"
        }
    }

    var peerExternalParameter: String {
        switch self {
        case .sealedClassesEnum:
            return "className: String"
        case .enum:
            return "name: String"
        default:
            return "Swift_peer: skip.bridge.SwiftObjectPointer"
        }
    }

    var peerSwiftParameter: TypeSignature.Parameter {
        switch self {
        case .sealedClassesEnum:
            return TypeSignature.Parameter(label: "className", type: .javaString)
        case .enum:
            return TypeSignature.Parameter(label: "name", type: .javaString)
        default:
            return TypeSignature.Parameter(label: "Swift_peer", type: .swiftObjectPointer(kotlin: false))
        }
    }

    var peerSwiftTarget: String {
        switch self {
        case .value:
            return "peer_swift.value"
        default:
            return "peer_swift"
        }
    }

    func peerSwiftAssignment(to classDeclaration: KotlinClassDeclaration?, optionsString: String) -> [String] {
        guard let classDeclaration else {
            return []
        }
        switch self {
        case .generic:
            return ["let peer_swift: \(classDeclaration.signature.typeErasedClass) = Swift_peer.pointee()!"]
        case .reference:
            return ["let peer_swift: \(classDeclaration.signature) = Swift_peer.pointee()!"]
        case .sealedClassesEnum:
            return [
                "let className_swift = String.fromJavaObject(className, options: \(optionsString))",
                "let peer_swift = \(classDeclaration.signature).fromJavaClassName(className_swift, Java_target, options: \(optionsString))"
            ]
        case .enum:
            return [
                "let name_swift = String.fromJavaObject(name, options: \(optionsString))",
                "let peer_swift = \(classDeclaration.signature).fromJavaName(name_swift)"
            ]
        default:
            return ["let peer_swift: SwiftValueTypeBox<\(classDeclaration.signature)> = Swift_peer.pointee()!"]
        }
    }
}

private extension KotlinClassDeclaration {
    var swiftUIType: TypeSignature.SwiftUIType {
        for inherit in inherits {
            let swiftUIType = inherit.swiftUIType
            guard swiftUIType == .none else {
                return swiftUIType
            }
        }
        return .none
    }
}

private extension TypeSignature {
    /// Non-Sendable parameters that will be passed through to `assumeMainActorUnchecked` that need to be wrapped in an `UncheckedSendableBox`
    var shouldWrapForMainActorIsolation: Bool {
        self == .javaObjectPointer || self == .javaString || self.isOptional
    }
}

private extension KotlinVariableDeclaration {
    func isMainActorIsolated(in classDeclaration: KotlinClassDeclaration?) -> Bool {
        return SkipSyntax.isMainActorIsolated(in: classDeclaration, attributes: attributes, modifiers: modifiers, isAsync: apiFlags.options.contains(.async))
    }

    func appendMainActorIsolated(_ swift: inout [String], _ indentation: Indentation = 0, in classDeclaration: KotlinClassDeclaration?, parameter: TypeSignature.Parameter? = nil, isReturn: Bool = false, block: (inout [String], Indentation) -> Void) {
        let locals: [String]
        if let parameter, let label = parameter.label, parameter.type.shouldWrapForMainActorIsolation {
            locals = [label]
        } else {
            locals = []
        }
        SkipSyntax.appendMainActorIsolated(&swift, indentation, in: classDeclaration, locals: locals, attributes: attributes, modifiers: modifiers, isThrows: apiFlags.throwsType != .none, isAsync: apiFlags.options.contains(.async), isReturn: isReturn, block: block)
    }
}

private extension KotlinFunctionDeclaration {
    func isMainActorIsolated(in classDeclaration: KotlinClassDeclaration?) -> Bool {
        return SkipSyntax.isMainActorIsolated(in: classDeclaration, attributes: attributes, modifiers: modifiers, isAsync: apiFlags.options.contains(.async))
    }

    func appendMainActorIsolated(_ swift: inout [String], _ indentation: Indentation = 0, in classDeclaration: KotlinClassDeclaration?, parameters: [TypeSignature.Parameter] = [], isReturn: Bool = false, block: (inout [String], Indentation) -> Void) {
        let locals = parameters.filter { $0.label != nil && $0.type.shouldWrapForMainActorIsolation }.map { $0.label! }
        SkipSyntax.appendMainActorIsolated(&swift, indentation, in: classDeclaration, locals: locals, attributes: attributes, modifiers: modifiers, isThrows: apiFlags.throwsType != .none, isAsync: apiFlags.options.contains(.async), isReturn: isReturn, block: block)
    }
}

private func appendMainActorIsolated(_ swift: inout [String], _ indentation: Indentation = 0, in classDeclaration: KotlinClassDeclaration?, locals: [String] = [], attributes: Attributes, modifiers: Modifiers, isThrows: Bool = false, isAsync: Bool = false, isReturn: Bool = false, block: (inout [String], Indentation) -> Void) {
    guard isMainActorIsolated(in: classDeclaration, attributes: attributes, modifiers: modifiers, isAsync: isAsync) else {
        block(&swift, indentation)
        return
    }
    locals.forEach { swift.append(indentation, "let \($0)_sendable = UncheckedSendableBox(\($0))") }
    let tryString = isThrows ? "try " : ""
    let returnString = isReturn ? "return " : ""
    swift.append(indentation, "\(returnString)\(tryString)SkipBridge.assumeMainActorUnchecked {")
    let bodyIndentation = indentation.inc()
    locals.forEach { swift.append(bodyIndentation, "let \($0) = \($0)_sendable.wrappedValue") }
    block(&swift, bodyIndentation)
    swift.append(indentation, "}")
}

private func isMainActorIsolated(in classDeclaration: KotlinClassDeclaration?, attributes: Attributes, modifiers: Modifiers, isAsync: Bool = false) -> Bool {
    guard !modifiers.isNonisolated else {
        return false
    }
    guard !attributes.contains(.mainActor) else {
        return true
    }
    guard !isAsync else {
        return false
    }
    guard classDeclaration?.attributes.contains(.mainActor) != true else {
        return true
    }
    guard let swiftUIType = classDeclaration?.swiftUIType else {
        return false
    }
    return swiftUIType != .none
}
