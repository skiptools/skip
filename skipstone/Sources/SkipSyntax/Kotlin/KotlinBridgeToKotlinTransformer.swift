/// Generate compiled Swift to Kotlin bridging code.
final class KotlinBridgeToKotlinTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        guard syntaxTree.isBridgeFile, let codebaseInfo = translator.codebaseInfo else {
            return []
        }

        var swiftDefinitions: [SwiftDefinition] = []
        var cdeclFunctions: [CDeclFunction] = []
        var nonKotlinImports: [KotlinStatement] = []
        var hasBridgedObservables = false
        syntaxTree.root.visit { node in
            if let importDeclaration = node as? KotlinImportDeclaration {
                // Filter compiled-only imports from the transpiled output
                if !isKotlinImport(importDeclaration, codebaseInfo: codebaseInfo) {
                    nonKotlinImports.append(importDeclaration)
                }
                return .skip
            } else if let variableDeclaration = node as? KotlinVariableDeclaration, variableDeclaration.role == .global {
                updateVariableDeclaration(variableDeclaration, cdeclFunctions: &cdeclFunctions, translator: translator)
                return .skip
            } else if let functionDeclaration = node as? KotlinFunctionDeclaration, functionDeclaration.role == .global {
                updateFunctionDeclaration(functionDeclaration, cdeclFunctions: &cdeclFunctions, translator: translator)
                return .skip
            } else if let classDeclaration = node as? KotlinClassDeclaration {
                if updateClassDeclaration(classDeclaration, swiftDefinitions: &swiftDefinitions, cdeclFunctions: &cdeclFunctions, translator: translator) {
                    hasBridgedObservables = hasBridgedObservables || classDeclaration.attributes.contains(.observable)
                }
                return .recurse(nil)
            } else if let interfaceDeclaration = node as? KotlinInterfaceDeclaration {
                if updateInterfaceDeclaration(interfaceDeclaration, translator: translator) {
                    if let bridgeImplDefinition = KotlinBridgeToSwiftTransformer.unknownBridgeImplDefinition(forProtocol: interfaceDeclaration.signature, statement: interfaceDeclaration, codebaseInfo: codebaseInfo) {
                        swiftDefinitions.append(bridgeImplDefinition)
                    }
                }
                return .recurse(nil)
            } else {
                return .recurse(nil)
            }
        }
        nonKotlinImports.forEach { syntaxTree.root.remove(statement: $0) }

        var outputs: [KotlinTransformerOutput] = []
        if let bridgeOutput = bridgeOutput(for: syntaxTree, swiftDefinitions: swiftDefinitions, cdeclFunctions: cdeclFunctions, translator: translator) {
            outputs.append(bridgeOutput)
        }
        if hasBridgedObservables {
            outputs.append(importObservationOutput(for: syntaxTree))
        }
        return outputs
    }

    private func bridgeOutput(for syntaxTree: KotlinSyntaxTree, swiftDefinitions: [SwiftDefinition], cdeclFunctions: [CDeclFunction], translator: KotlinTranslator) -> KotlinTransformerOutput? {
        guard !swiftDefinitions.isEmpty || !cdeclFunctions.isEmpty else {
            return nil
        }
        guard let outputFile = syntaxTree.source.file.bridgeOutputFile else {
            return nil
        }

        let importDeclarations = translator.syntaxTree.root.statements.compactMap { $0 as? ImportDeclaration }
        let outputNode = SwiftDefinition { output, indentation, _ in
            output.append("import SkipBridge\n\n")
            for importDeclaration in importDeclarations {
                let path = importDeclaration.modulePath.joined(separator: ".")
                output.append(indentation).append("import ").append(path).append("\n")
            }
            swiftDefinitions.forEach { $0.append(to: output, indentation: indentation) }
            cdeclFunctions.forEach { $0.append(to: output, indentation: indentation) }
        }
        return KotlinTransformerOutput(file: outputFile, node: outputNode, type: .bridgeToKotlin)
    }

    private func importObservationOutput(for syntaxTree: KotlinSyntaxTree) -> KotlinTransformerOutput {
        let outputNode = SwiftDefinition(swift: ["import struct SkipBridge.Observation"])
        return KotlinTransformerOutput(file: syntaxTree.source.file, node: outputNode, type: .appendToSource)
    }

    private func isKotlinImport(_ importDeclaration: KotlinImportDeclaration, codebaseInfo: CodebaseInfo.Context) -> Bool {
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

    private func updateVariableDeclaration(_ variableDeclaration: KotlinVariableDeclaration, in classDeclaration: KotlinClassDeclaration? = nil, cdeclFunctions: inout [CDeclFunction], translator: KotlinTranslator) {
        guard classDeclaration != nil || !variableDeclaration.attributes.isBridgeToSwift else {
            variableDeclaration.messages.append(Message.kotlinBridgeSwiftToSwift(variableDeclaration, source: translator.syntaxTree.source))
            return
        }
        guard let bridgable = variableDeclaration.checkBridgable(translator: translator) else {
            return
        }
        let type = bridgable.type
        variableDeclaration.extras = nil
        // If this is a let constant with a supported literal value, we'll re-declare rather than bridge it
        guard !isSupportedConstant(variableDeclaration, type: type) else {
            return
        }

        // Remove initial value and make sure type is declared
        variableDeclaration.value = nil
        if variableDeclaration.declaredType == .none {
            variableDeclaration.declaredType = type
        }
        // Bridged types will always be copied, so they can't be shared
        variableDeclaration.mayBeSharedMutableStruct = false

        let propertyName = variableDeclaration.propertyName
        let externalName = "Swift_" + ((variableDeclaration.isStatic) ? "Companion_" + propertyName : propertyName)
        var externalFunctionDeclarations: [String] = []
        let (cdecl, cdeclName) = cdecl(for: variableDeclaration, name: externalName, translator: translator)

        // Getter
        let isInstance = classDeclaration != nil && !variableDeclaration.isStatic
        let getterArguments = isInstance ? "(Swift_peer)" : "()"
        let getterParameters = isInstance ? "(Swift_peer: skip.bridge.SwiftObjectPointer)" : "()"
        let getterSref: String
        if let onUpdate = variableDeclaration.onUpdate?(), !onUpdate.isEmpty {
            getterSref = ".sref(\(onUpdate))"
        } else {
            getterSref = ""
        }
        let getterBody = [
            "return " + externalName + getterArguments + getterSref
        ]
        variableDeclaration.getter = Accessor(body: KotlinCodeBlock(statements: getterBody.map { KotlinRawStatement(sourceCode: $0) }))
        externalFunctionDeclarations.append("private external fun \(externalName)\(getterParameters): \(type.kotlin)")

        let cdeclInstanceParameters: [TypeSignature.Parameter]
        let cdeclGetterBody: [String]
        if let classDeclaration {
            if isInstance {
                cdeclGetterBody = [
                    "let peer_swift: \(classDeclaration.signature) = Swift_peer.pointee()!",
                    "return " + type.convertToCDecl(value: "peer_swift.\(propertyName)", strategy: bridgable.strategy)
                ]
                cdeclInstanceParameters = [cdeclInstanceParameter]
            } else {
                cdeclGetterBody = ["return " + type.convertToCDecl(value: "\(classDeclaration.signature).\(propertyName)", strategy: bridgable.strategy)]
                cdeclInstanceParameters = []
            }
        } else {
            cdeclGetterBody = ["return " + type.convertToCDecl(value: propertyName, strategy: bridgable.strategy)]
            cdeclInstanceParameters = []
        }
        let cdeclGetter = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: .function(cdeclInstanceParameters, type.cdecl(strategy: bridgable.strategy), APIFlags(), nil), body: cdeclGetterBody)
        cdeclFunctions.append(cdeclGetter)

        // Setter
        if variableDeclaration.apiFlags.options.contains(.writeable) {
            let setterArguments = isInstance ? "Swift_peer, newValue" : "newValue"
            let setterInstanceParameter = isInstance ? "Swift_peer: skip.bridge.SwiftObjectPointer, " : ""
            let setterBody = [
                externalName + "_set(" + setterArguments + ")"
            ]
            variableDeclaration.setter = Accessor(parameterName: "newValue", body: KotlinCodeBlock(statements: setterBody.map { KotlinRawStatement(sourceCode: $0) }))
            externalFunctionDeclarations.append("private external fun \(externalName)_set(\(setterInstanceParameter)value: \(type.kotlin))")

            let cdeclSetterBody: [String]
            if let classDeclaration {
                if isInstance {
                    cdeclSetterBody = [
                        "let peer_swift: \(classDeclaration.signature) = Swift_peer.pointee()!",
                        "peer_swift.\(propertyName) = " + type.convertFromCDecl(value: "value", strategy: bridgable.strategy)
                    ]
                } else {
                    cdeclSetterBody = ["\(classDeclaration.signature).\(propertyName) = " + type.convertFromCDecl(value: "value", strategy: bridgable.strategy)]
                }
            } else {
                cdeclSetterBody = [propertyName + " = " + type.convertFromCDecl(value: "value", strategy: bridgable.strategy)]
            }
            let cdeclSetter = CDeclFunction(name: cdeclName + "_set", cdecl: cdecl + "_1set", signature: .function(cdeclInstanceParameters + [TypeSignature.Parameter(label: "value", type: type.cdecl(strategy: bridgable.strategy))], .void, APIFlags(), nil), body: cdeclSetterBody)
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

    private func updateFunctionDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, in classDeclaration: KotlinClassDeclaration? = nil, cdeclFunctions: inout [CDeclFunction], translator: KotlinTranslator) {
        guard classDeclaration != nil || !functionDeclaration.attributes.isBridgeToSwift else {
            functionDeclaration.messages.append(Message.kotlinBridgeSwiftToSwift(functionDeclaration, source: translator.syntaxTree.source))
            return
        }
        guard let bridgable = functionDeclaration.checkBridgable(translator: translator) else {
            return
        }
        let functionType = functionDeclaration.functionType.functionType(with: bridgable, isConstructor: functionDeclaration.type == .constructorDeclaration)
        let functionTypeParameters = functionType.parameters
        functionDeclaration.extras = nil

        let classDeclaration = functionDeclaration.parent as? KotlinClassDeclaration
        let functionName = functionDeclaration.name
        let isAsync = functionDeclaration.apiFlags.options.contains(.async)
        let isThrows = functionDeclaration.apiFlags.throwsType != .none
        let externalName = (isAsync ? "Swift_callback_" : "Swift_") + ((functionDeclaration.isStatic) ? "Companion_" + functionName : functionName)

        var cdeclBody: [String] = []
        for (index, parameter) in functionDeclaration.parameters.enumerated() {
            let strategy = bridgable.parameters[index].strategy
            cdeclBody.append("let \(parameter.internalLabel)_swift = " + functionTypeParameters[index].type.convertFromCDecl(value: parameter.internalLabel, strategy: strategy))
        }

        let callbackType = functionType.callbackClosureType(apiFlags: functionDeclaration.apiFlags, java: false)
        if isAsync {
            cdeclBody.append("let f_callback_swift = " + callbackType.convertFromCDecl(value: "f_callback", strategy: .direct) + " as " + callbackType.description)
        }

        let swiftCallTarget: String
        var externalArgumentsString: String
        if let classDeclaration, functionDeclaration.type != .constructorDeclaration {
            if functionDeclaration.isStatic {
                swiftCallTarget = classDeclaration.name + "."
                externalArgumentsString = ""
            } else {
                cdeclBody.append("let peer_swift: \(classDeclaration.signature) = Swift_peer.pointee()!")
                swiftCallTarget = "peer_swift."
                externalArgumentsString = "Swift_peer"
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
        let swiftArgumentsString = functionDeclaration.parameters.map { parameter in
            let swiftArgument = parameter.internalLabel + "_swift"
            if let externalLabel = parameter.externalLabel {
                return externalLabel + ": " + swiftArgument
            } else {
                return swiftArgument
            }
        }.joined(separator: ", ")

        var body: [String] = []
        let cdeclReturnType: TypeSignature
        if let classDeclaration, functionDeclaration.type == .constructorDeclaration {
            body.append("Swift_peer = \(externalName)(\(externalArgumentsString))")
            cdeclBody.append("let f_return_swift = \(classDeclaration.signature)(\(swiftArgumentsString))")
            cdeclBody.append("return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)")
            cdeclReturnType = .swiftObjectPointer(java: false)
        } else if isAsync {
            body.append("kotlin.coroutines.suspendCoroutine { f_continuation ->")
            if isThrows {
                if functionType.returnType == .void {
                    body.append(1, externalName + "(\(externalArgumentsString)) { f_error ->")
                } else {
                    body.append(1, externalName + "(\(externalArgumentsString)) { f_return, f_error ->")
                }
                body.append(2, "if (f_error != null) {")
                body.append(3, "f_continuation.resumeWith(kotlin.Result.failure(f_error))")
                body.append(2, "} else {")
                if functionType.returnType == .void {
                    body.append(3, "f_continuation.resumeWith(kotlin.Result.success(Unit))")
                } else {
                    let forceUnwrapString = functionType.returnType.isOptional ? "" : "!!"
                    body.append(3, "f_continuation.resumeWith(kotlin.Result.success(f_return\(forceUnwrapString)))")
                }
                body.append(2, "}")
            } else {
                if functionType.returnType == .void {
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
                if functionType.returnType == .void {
                    cdeclBody.append(2, "try await \(swiftCallTarget)\(functionName)(\(swiftArgumentsString))")
                    cdeclBody.append(2, "f_callback_swift(nil)")
                } else {
                    cdeclBody.append(2, "let f_return_swift = try await \(swiftCallTarget)\(functionName)(\(swiftArgumentsString))")
                    cdeclBody.append(2, "f_callback_swift(f_return_swift, nil)")
                }
                cdeclBody.append(1, "} catch {")
                cdeclBody.append(2, "jniContext {")
                if functionType.returnType == .void {
                    cdeclBody.append(3, "f_callback_swift(JavaErrorThrowable(error, env: Java_env))")
                } else {
                    cdeclBody.append(3, "f_callback_swift(nil, JavaErrorThrowable(error, env: Java_env))")
                }
                cdeclBody.append(2, "}")
                cdeclBody.append(1, "}")
            } else if functionType.returnType == .void {
                cdeclBody.append(1, "await \(swiftCallTarget)\(functionName)(\(swiftArgumentsString))")
                cdeclBody.append(1, "f_callback_swift()")
            } else {
                cdeclBody.append(1, "let f_return_swift = await \(swiftCallTarget)\(functionName)(\(swiftArgumentsString))")
                cdeclBody.append(1, "f_callback_swift(f_return_swift)")
            }
            cdeclBody.append("}")
            cdeclReturnType = .void
        } else if functionType.returnType == .void {
            body.append(externalName + "(\(externalArgumentsString))")
            if isThrows {
                cdeclBody.append("do {")
                cdeclBody.append(1, "try \(swiftCallTarget)\(functionName)(\(swiftArgumentsString))")
                cdeclBody.append("} catch {")
                cdeclBody.append(1, "JavaThrowError(error, env: Java_env)")
                cdeclBody.append("}")
            } else {
                cdeclBody.append(swiftCallTarget + functionName + "(\(swiftArgumentsString))")
            }
            cdeclReturnType = .void
        } else {
            let forceUnwrapString: String
            if isThrows {
                forceUnwrapString = functionType.returnType.isOptional ? "" : "!!"
                cdeclBody.append("do {")
                cdeclBody.append(1, "let f_return_swift = try \(swiftCallTarget)\(functionName)(\(swiftArgumentsString))")
                cdeclBody.append(1, "return " + functionType.returnType.asOptional(true).convertToCDecl(value: "f_return_swift", strategy: bridgable.return.strategy))
                cdeclBody.append("} catch {")
                cdeclBody.append(1, "JavaThrowError(error, env: Java_env)")
                cdeclBody.append(1, "return nil")
                cdeclBody.append("}")
                cdeclReturnType = functionType.returnType.asOptional(true).cdecl(strategy: bridgable.return.strategy)
            } else {
                forceUnwrapString = ""
                cdeclBody.append("let f_return_swift = \(swiftCallTarget)\(functionName)(\(swiftArgumentsString))")
                cdeclBody.append("return " + functionDeclaration.returnType.convertToCDecl(value: "f_return_swift", strategy: bridgable.return.strategy))
                cdeclReturnType = functionType.returnType.cdecl(strategy: bridgable.return.strategy)
            }
            body.append("return \(externalName)(\(externalArgumentsString))\(forceUnwrapString)")
        }
        functionDeclaration.body = KotlinCodeBlock(statements: body.map { KotlinRawStatement(sourceCode: $0) })

        var externalFunctionDeclaration = "private external fun \(externalName)("
        var externalParametersString: String
        if classDeclaration != nil, functionDeclaration.type != .constructorDeclaration && !functionDeclaration.isStatic {
            externalParametersString = "Swift_peer: skip.bridge.SwiftObjectPointer"
        } else {
            externalParametersString = ""
        }
        if !functionDeclaration.parameters.isEmpty {
            if !externalParametersString.isEmpty {
                externalParametersString += ", "
            }
            externalParametersString += functionDeclaration.parameters.enumerated().map { index, parameter in
                return parameter.internalLabel + ": " + functionTypeParameters[index].type.kotlin
            }.joined(separator: ", ")
        }
        if isAsync {
            if !externalParametersString.isEmpty {
                externalParametersString += ", "
            }
            externalParametersString += "f_callback: " + functionType.callbackClosureType(apiFlags: functionDeclaration.apiFlags, java: true).kotlin
        }
        externalFunctionDeclaration += externalParametersString
        externalFunctionDeclaration += ")"
        if functionDeclaration.type == .constructorDeclaration {
            externalFunctionDeclaration += ": skip.bridge.SwiftObjectPointer"
        } else if functionType.returnType != .void && !isAsync {
            var returnType = functionType.returnType
            if functionDeclaration.apiFlags.throwsType != .none {
                returnType = returnType.asOptional(true)
            }
            externalFunctionDeclaration += ": " + returnType.kotlin
        }
        (functionDeclaration.parent as? KotlinStatement)?.insert(statements: [KotlinRawStatement(sourceCode: externalFunctionDeclaration, isStatic: functionDeclaration.isStatic)], after: functionDeclaration)

        let (cdecl, cdeclName) = cdecl(for: functionDeclaration, name: externalName, translator: translator)
        let instanceParameter = classDeclaration != nil && functionDeclaration.type != .constructorDeclaration && !functionDeclaration.isStatic ? [cdeclInstanceParameter] : []
        let callbackParameter = isAsync ? [TypeSignature.Parameter(label: "f_callback", type: .javaObjectPointer)] : []
        let cdeclType: TypeSignature = .function(instanceParameter + functionTypeParameters.enumerated().map { (index, parameter) in
            let strategy = bridgable.parameters[index].strategy
            return TypeSignature.Parameter(label: functionDeclaration.parameters[index].internalLabel, type: parameter.type.cdecl(strategy: strategy))
        } + callbackParameter, cdeclReturnType, APIFlags(), nil)
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclType, body: cdeclBody)
        cdeclFunctions.append(cdeclFunction)
    }

    private func updateEqualsDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, in classDeclaration: KotlinClassDeclaration, cdeclFunctions: inout [CDeclFunction], translator: KotlinTranslator) {
        functionDeclaration.extras = nil
        functionDeclaration.body = KotlinCodeBlock(statements: [
            "return Swift_isequal(lhs, rhs)"
        ].map { KotlinRawStatement(sourceCode: $0) })

        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: "private external fun Swift_isequal(lhs: \(classDeclaration.signature), rhs: \(classDeclaration.signature)): Boolean")
        classDeclaration.insert(statements: [externalFunctionDeclaration], after: functionDeclaration)

        let (cdecl, cdeclName) = cdecl(for: functionDeclaration, name: "Swift_isequal", translator: translator)
        let cdeclType: TypeSignature = .function([TypeSignature.Parameter(label: "lhs", type: .javaObjectPointer), TypeSignature.Parameter(label: "rhs", type: .javaObjectPointer)], .bool, APIFlags(), nil)
        let cdeclBody: [String] = [
            "let lhs_swift = \(classDeclaration.signature).fromJavaObject(lhs)",
            "let rhs_swift = \(classDeclaration.signature).fromJavaObject(rhs)",
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
            "if (other !is skip.bridge.SwiftPeerBridged) return false",
            "return Swift_peer == other.Swift_bridgedPeer()"
        ]
        equals.body = KotlinCodeBlock(statements: sourceCode.map { KotlinRawStatement(sourceCode: $0) })
        return equals
    }

    private func updateHashDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, in classDeclaration: KotlinClassDeclaration, cdeclFunctions: inout [CDeclFunction], translator: KotlinTranslator) {
        functionDeclaration.extras = nil
        functionDeclaration.body = KotlinCodeBlock(statements: [
            "hasher.value.combine(Swift_hashvalue(Swift_peer))"
        ].map { KotlinRawStatement(sourceCode: $0) })

        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: "private external fun Swift_hashvalue(Swift_peer: skip.bridge.SwiftObjectPointer): Long")
        classDeclaration.insert(statements: [externalFunctionDeclaration], after: functionDeclaration)

        let (cdecl, cdeclName) = cdecl(for: functionDeclaration, name: "Swift_hashvalue", translator: translator)
        let cdeclType: TypeSignature = .function([cdeclInstanceParameter], .int64, APIFlags(), nil)
        let cdeclBody: [String] = [
            "let peer_swift: \(classDeclaration.signature) = Swift_peer.pointee()!",
            "return Int64(peer_swift.hashValue)"
        ]
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

    private func updateLessThanDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, in classDeclaration: KotlinClassDeclaration, cdeclFunctions: inout [CDeclFunction], translator: KotlinTranslator) {
        functionDeclaration.extras = nil
        functionDeclaration.body = KotlinCodeBlock(statements: [
            "return Swift_islessthan(lhs, rhs)"
        ].map { KotlinRawStatement(sourceCode: $0) })

        let externalFunctionDeclaration = KotlinRawStatement(sourceCode: "private external fun Swift_islessthan(lhs: \(classDeclaration.signature), rhs: \(classDeclaration.signature)): Boolean")
        classDeclaration.insert(statements: [externalFunctionDeclaration], after: functionDeclaration)

        let (cdecl, cdeclName) = cdecl(for: functionDeclaration, name: "Swift_islessthan", translator: translator)
        let cdeclType: TypeSignature = .function([TypeSignature.Parameter(label: "lhs", type: .javaObjectPointer), TypeSignature.Parameter(label: "rhs", type: .javaObjectPointer)], .bool, APIFlags(), nil)
        let cdeclBody: [String] = [
            "let lhs_swift = \(classDeclaration.signature).fromJavaObject(lhs)",
            "let rhs_swift = \(classDeclaration.signature).fromJavaObject(rhs)",
            "return lhs_swift < rhs_swift"
        ]
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclType, body: cdeclBody)
        cdeclFunctions.append(cdeclFunction)
    }

    @discardableResult private func updateInterfaceDeclaration(_ interfaceDeclaration: KotlinInterfaceDeclaration, translator: KotlinTranslator) -> Bool {
        guard !interfaceDeclaration.attributes.isBridgeToSwift else {
            interfaceDeclaration.messages.append(Message.kotlinBridgeSwiftToSwift(interfaceDeclaration, source: translator.syntaxTree.source))
            return false
        }
        guard interfaceDeclaration.checkBridgable(translator: translator) else {
            return false
        }
        guard let codebaseInfo = translator.codebaseInfo else {
            return false
        }
        interfaceDeclaration.extras = nil
        interfaceDeclaration.inherits = interfaceDeclaration.inherits.filter { $0.isNamed("Comparable") || $0.checkBridgable(codebaseInfo: codebaseInfo) != nil }
        return true
    }

    @discardableResult private func updateClassDeclaration(_ classDeclaration: KotlinClassDeclaration, swiftDefinitions: inout [SwiftDefinition], cdeclFunctions: inout [CDeclFunction], translator: KotlinTranslator) -> Bool {
        guard !classDeclaration.attributes.isBridgeToSwift else {
            classDeclaration.messages.append(Message.kotlinBridgeSwiftToSwift(classDeclaration, source: translator.syntaxTree.source))
            return false
        }
        guard classDeclaration.checkBridgable(translator: translator) else {
            return false
        }
        guard let codebaseInfo = translator.codebaseInfo else {
            return false
        }
        classDeclaration.extras = nil
        classDeclaration.inherits = classDeclaration.inherits.filter { $0.isNamed("Comparable") || $0.checkBridgable(codebaseInfo: codebaseInfo) != nil }
        switch classDeclaration.declarationType {
        case .classDeclaration:
            updateClass(classDeclaration, swiftDefinitions: &swiftDefinitions, cdeclFunctions: &cdeclFunctions, translator: translator)
            return true
        default:
            classDeclaration.messages.append(.kotlinBridgeUnsupportedDeclaration(classDeclaration, source: translator.syntaxTree.source))
            return false
        }
    }

    private func updateClass(_ classDeclaration: KotlinClassDeclaration, swiftDefinitions: inout [SwiftDefinition], cdeclFunctions: inout [CDeclFunction], translator: KotlinTranslator) {
        classDeclaration.inherits.append(.named("skip.bridge.SwiftPeerBridged", []))

        var insertStatements: [KotlinStatement] = []
        let swiftPeer = KotlinVariableDeclaration(names: ["Swift_peer"], variableTypes: [.swiftObjectPointer(java: true)])
        swiftPeer.role = .property
        swiftPeer.modifiers.visibility = .public
        swiftPeer.apiFlags.options = .writeable
        swiftPeer.declaredType = .swiftObjectPointer(java: true)
        swiftPeer.isGenerated = true
        insertStatements.append(swiftPeer)

        let swiftPeerConstructor = KotlinFunctionDeclaration(name: "constructor")
        swiftPeerConstructor.modifiers.visibility = .public
        swiftPeerConstructor.parameters = [Parameter<KotlinExpression>(externalLabel: "Swift_peer", declaredType: .swiftObjectPointer(java: true)), Parameter<KotlinExpression>(externalLabel: "marker", declaredType: .named("skip.bridge.SwiftPeerMarker", []).asOptional(true))]
        swiftPeerConstructor.body = KotlinCodeBlock(statements: [KotlinRawStatement(sourceCode: "this.Swift_peer = Swift_peer")])
        swiftPeerConstructor.ensureLeadingNewlines(1)
        swiftPeerConstructor.isGenerated = true
        insertStatements.append(swiftPeerConstructor)

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

        if !classDeclaration.members.contains(where: { $0.type == .constructorDeclaration }) {
            let constructor = KotlinFunctionDeclaration(name: "constructor")
            constructor.modifiers.visibility = .public
            constructor.body = KotlinCodeBlock(statements: [KotlinRawStatement(sourceCode: "Swift_peer = Swift_constructor()")])
            constructor.ensureLeadingNewlines(1)
            constructor.isGenerated = true
            insertStatements.append(constructor)
            let externalConstructor = KotlinRawStatement(sourceCode: "private external fun Swift_constructor(): skip.bridge.SwiftObjectPointer")
            insertStatements.append(externalConstructor)

            let constructorCdecl = cdecl(for: classDeclaration, name: "Swift_constructor", translator: translator)
            let constructorBody = [
                "let f_return_swift = \(classDeclaration.signature)()",
                "return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)"
            ]
            cdeclFunctions.append(CDeclFunction(name: constructorCdecl.cdeclFunctionName, cdecl: constructorCdecl.cdecl, signature: .function([], .swiftObjectPointer(java: false), APIFlags(), nil), body: constructorBody))
        }

        let bridgedPeer = KotlinFunctionDeclaration(name: "Swift_bridgedPeer")
        bridgedPeer.returnType = .swiftObjectPointer(java: true)
        bridgedPeer.modifiers.visibility = .public
        bridgedPeer.modifiers.isOverride = true
        bridgedPeer.body = KotlinCodeBlock(statements: [
            KotlinReturn(expression: KotlinIdentifier(name: "Swift_peer"))
        ])
        bridgedPeer.ensureLeadingNewlines(1)
        bridgedPeer.isGenerated = true
        insertStatements.append(bridgedPeer)

        let releaseCdecl = cdecl(for: classDeclaration, name: "Swift_release", translator: translator)
        let releaseBody = [
            "Swift_peer.release(as: \(classDeclaration.signature).self)"
        ]
        cdeclFunctions.append(CDeclFunction(name: releaseCdecl.cdeclFunctionName, cdecl: releaseCdecl.cdecl, signature: .function([cdeclInstanceParameter], .void, APIFlags(), nil), body: releaseBody))

        var hasEqualsDeclaration = false
        var hasHashDeclaration = false
        for member in classDeclaration.members {
            if let variableDeclaration = member as? KotlinVariableDeclaration {
                updateVariableDeclaration(variableDeclaration, in: classDeclaration, cdeclFunctions: &cdeclFunctions, translator: translator)
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                if functionDeclaration.isEqualImplementation {
                    updateEqualsDeclaration(functionDeclaration, in: classDeclaration, cdeclFunctions: &cdeclFunctions, translator: translator)
                    hasEqualsDeclaration = true
                } else if functionDeclaration.isHashImplementation {
                    updateHashDeclaration(functionDeclaration, in: classDeclaration, cdeclFunctions: &cdeclFunctions, translator: translator)
                    hasHashDeclaration = true
                } else if functionDeclaration.isLessThanImplementation {
                    updateLessThanDeclaration(functionDeclaration, in: classDeclaration, cdeclFunctions: &cdeclFunctions, translator: translator)
                } else {
                    updateFunctionDeclaration(functionDeclaration, in: classDeclaration, cdeclFunctions: &cdeclFunctions, translator: translator)
                }
            }
        }
        if !hasEqualsDeclaration {
            let equalsDeclaration = defaultEqualsDeclaration()
            insertStatements.append(equalsDeclaration)
        }
        if !hasHashDeclaration {
            let hashDeclaration = defaultHashDeclaration()
            insertStatements.append(hashDeclaration)
        }

        (classDeclaration.children.first as? KotlinStatement)?.ensureLeadingNewlines(1)
        classDeclaration.insert(statements: insertStatements, after: nil)

        // Conform to `BridgedToKotlin`
        let classRef = JavaClassRef(for: classDeclaration, translator: translator)
        var swift: [String] = []
        swift.append("extension \(classDeclaration.signature): BridgedToKotlin {")
        swift.append(1, classRef.declaration)
        swift.append(1, classDeclaration.modifiers.visibility.swift(suffix: " ") + "static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {")
        swift.append(2, [
            "let ptr = SwiftObjectPointer.peer(of: obj!)",
            "return ptr.pointee()!"
        ])
        swift.append(1, "}")
        swift.append(1, classDeclaration.modifiers.visibility.swift(suffix: " ") + "func toJavaObject() -> JavaObjectPointer? {")
        swift.append(2, [
            "let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)",
            "return try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])"
        ])
        swift.append(1, "}")
        swift.append(1, "private static let Java_constructor_methodID = Java_class.getMethodID(name: \"<init>\", sig: \"(JLskip/bridge/SwiftPeerMarker;)V\")!")
        swift.append("}")

        let swiftDefinition = SwiftDefinition(swift: swift)
        swiftDefinitions.append(swiftDefinition)
    }

    private func cdecl(for statement: KotlinStatement, name: String, translator: KotlinTranslator) -> (cdecl: String, cdeclFunctionName: String) {
        var cdeclPrefix = "Java_"
        if let package = translator.packageName {
            cdeclPrefix += package.cdeclEscaped.replacing(".", with: "_") + "_"
        }
        let typeName: String
        let cdeclTypeName: String
        if let classDeclaration = statement.owningTypeDeclaration as? KotlinClassDeclaration {
            typeName = classDeclaration.signature.description
            if (statement as? KotlinMemberDeclaration)?.isStatic == true {
                cdeclTypeName = typeName + "$Companion"
            } else {
                cdeclTypeName = typeName
            }
        } else {
            var file = translator.syntaxTree.source.file
            file.extension = ""
            typeName = file.name + "Kt"
            cdeclTypeName = typeName
        }
        return (cdeclPrefix + cdeclTypeName.cdeclEscaped + "_" + name.cdeclEscaped, typeName + "_" + name)
    }

    private var cdeclInstanceParameter: TypeSignature.Parameter {
        return TypeSignature.Parameter(label: "Swift_peer", type: .swiftObjectPointer(java: false))
    }
}

private struct CDeclFunction {
    let name: String
    let cdecl: String
    let signature: TypeSignature
    let body: [String]

    func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation).append("@_cdecl(\"").append(cdecl).append("\")\n")
        output.append(indentation).append("func ").append(name).append("(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer")
        for parameter in signature.parameters {
            output.append(", _")
            if let label = parameter.label {
                output.append(" ").append(label)
            }
            output.append(": ").append(parameter.type.description)
        }
        output.append(")")
        if signature.returnType != .void {
            output.append(" -> ").append(signature.returnType.description)
        }
        output.append(" {\n")

        let bodyIndentation = indentation.inc()
        body.forEach { output.append(bodyIndentation).append($0).append("\n") }

        output.append(indentation).append("}\n")
    }
}
