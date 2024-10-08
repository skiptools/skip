/// Generate compiled Swift to Kotlin bridging code.
final class KotlinCompiledBridgeTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        guard syntaxTree.isBridgeFile, let codebaseInfo = translator.codebaseInfo, let outputFile = syntaxTree.source.file.bridgeOutputFile else {
            return []
        }

        var swiftDefinitions: [SwiftDefinition] = []
        var cdeclFunctions: [CDeclFunction] = []
        var nonKotlinImports: [KotlinStatement] = []
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
                updateClassDeclaration(classDeclaration, swiftDefinitions: &swiftDefinitions, cdeclFunctions: &cdeclFunctions, translator: translator)
                return .recurse(nil)
            } else {
                return .recurse(nil)
            }
        }
        nonKotlinImports.forEach { syntaxTree.root.remove(statement: $0) }
        guard !swiftDefinitions.isEmpty || !cdeclFunctions.isEmpty else {
            return []
        }

        let importDeclarations = translator.syntaxTree.root.statements.compactMap { $0 as? ImportDeclaration }
        let outputNode = SwiftDefinition { output, indentation, _ in
            output.append("#if canImport(SkipBridge)\nimport SkipBridge\n\n")
            for importDeclaration in importDeclarations {
                let path = importDeclaration.modulePath.joined(separator: ".")
                output.append(indentation).append("import ").append(path).append("\n")
            }
            swiftDefinitions.forEach { $0.append(to: output, indentation: indentation) }
            cdeclFunctions.forEach { $0.append(to: output, indentation: indentation) }
            output.append("\n#endif")
        }
        let output = KotlinTransformerOutput(file: outputFile, node: outputNode)
        return [output]
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

        let propertyName = variableDeclaration.propertyName
        let externalName = "Swift_" + propertyName
        let externalType = type.kotlinExternal(strategy: bridgable.strategy)
        var externalFunctionDeclarations: [String] = []
        let (cdecl, cdeclName) = cdecl(for: variableDeclaration, name: externalName, translator: translator)

        // Getter
        let getterArguments = classDeclaration == nil ? "()" : "(Swift_peer)"
        let getterParameters = classDeclaration == nil ? "()" : "(Swift_peer: skip.bridge.SwiftObjectPointer)"
        let getterBody = [
            "val value_swift = " + externalName + getterArguments,
            "return " + type.kotlinConvertFromExternal(value: "value_swift", strategy: bridgable.strategy)
        ]
        variableDeclaration.getter = Accessor(body: KotlinCodeBlock(statements: getterBody.map { KotlinRawStatement(sourceCode: $0) }))
        externalFunctionDeclarations.append("private external fun " + externalName + getterParameters + ": " + externalType.kotlin)

        var cdeclGetterBody: [String]
        let cdeclInstanceParameters: [TypeSignature.Parameter]
        if let classDeclaration {
            cdeclGetterBody = [
                "let peer_swift: " + classDeclaration.signature.description + " = Swift_peer.pointee()!",
                "let value_swift = peer_swift." + propertyName
            ]
            cdeclInstanceParameters = [cdeclInstanceParameter]
        } else {
            cdeclGetterBody = ["let value_swift = " + propertyName]
            cdeclInstanceParameters = []
        }
        cdeclGetterBody.append("return " + type.convertToCDecl(value: "value_swift", strategy: bridgable.strategy))
        let cdeclGetter = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: .function(cdeclInstanceParameters, type.cdecl(strategy: bridgable.strategy), APIFlags(), nil), body: cdeclGetterBody)
        cdeclFunctions.append(cdeclGetter)

        // Setter
        if variableDeclaration.apiFlags.options.contains(.writeable) {
            let setterArguments = classDeclaration == nil ? "newValue_swift" : "Swift_peer, newValue_swift"
            let setterInstanceParameter = classDeclaration == nil ? "" : "Swift_peer: skip.bridge.SwiftObjectPointer, "
            let setterBody = [
                "val newValue_swift = " + type.kotlinConvertToExternal(value: "newValue", strategy: bridgable.strategy),
                externalName + "_set(" + setterArguments + ")"
            ]
            variableDeclaration.setter = Accessor(parameterName: "newValue", body: KotlinCodeBlock(statements: setterBody.map { KotlinRawStatement(sourceCode: $0) }))
            externalFunctionDeclarations.append("private external fun " + externalName + "_set(" + setterInstanceParameter + "value: " + externalType.kotlin + ")")

            var cdeclSetterBody = ["let value_swift = " + type.convertFromCDecl(value: "value", strategy: bridgable.strategy)]
            if let classDeclaration {
                cdeclSetterBody += [
                    "let peer_swift: " + classDeclaration.signature.description + " = Swift_peer.pointee()!",
                    "peer_swift." + propertyName + " = value_swift"
                ]
            } else {
                cdeclSetterBody.append(propertyName + " = value_swift")
            }
            let cdeclSetter = CDeclFunction(name: cdeclName + "_set", cdecl: cdecl + "_1set", signature: .function(cdeclInstanceParameters + [TypeSignature.Parameter(label: "value", type: type.cdecl(strategy: bridgable.strategy))], .void, APIFlags(), nil), body: cdeclSetterBody)
            cdeclFunctions.append(cdeclSetter)
        }
        variableDeclaration.willSet = nil
        variableDeclaration.didSet = nil

        // Add function declarations to transpiled output
        (variableDeclaration.parent as? KotlinStatement)?.insert(statements: externalFunctionDeclarations.map { KotlinRawStatement(sourceCode: $0) }, after: variableDeclaration)
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
        guard let bridgables = functionDeclaration.checkBridgable(translator: translator) else {
            return
        }
        let functionType = functionDeclaration.functionType
        functionDeclaration.extras = nil

        let classDeclaration = functionDeclaration.parent as? KotlinClassDeclaration
        let functionName = functionDeclaration.name
        let externalName = "Swift_" + functionName

        var body: [String] = []
        var cdeclBody: [String] = []
        var externalParameterNames: [String] = []
        for parameter in functionDeclaration.parameters {
            let externalParameterName = parameter.internalLabel + "_swift"
            body.append("val " + externalParameterName + " = " + parameter.declaredType.kotlinConvertToExternal(value: parameter.internalLabel, strategy: .direct))
            cdeclBody.append("let " + externalParameterName + " = " + parameter.declaredType.convertFromCDecl(value: parameter.internalLabel, strategy: .direct))
            externalParameterNames.append(externalParameterName)
        }

        let swiftCallTarget: String
        var externalArgumentsString = ""
        if let classDeclaration, functionDeclaration.type != .constructorDeclaration {
            cdeclBody.append("let peer_swift: " + classDeclaration.signature.description + " = Swift_peer.pointee()!")
            swiftCallTarget = "peer_swift."

            externalArgumentsString += "Swift_peer"
            if !externalParameterNames.isEmpty {
                externalArgumentsString += ", "
            }
        } else {
            swiftCallTarget = ""
        }
        externalArgumentsString += externalParameterNames.joined(separator: ", ")
        let swiftArgumentsString = functionDeclaration.parameters.enumerated().map { index, p in
            if let externalLabel = p.externalLabel {
                return externalLabel + ": " + externalParameterNames[index]
            } else {
                return externalParameterNames[index]
            }
        }.joined(separator: ", ")
        
        if let classDeclaration, functionDeclaration.type == .constructorDeclaration {
            body.append("Swift_peer = " + externalName + "(" + externalArgumentsString + ")")
            cdeclBody.append("let f_return_swift = " + classDeclaration.signature.description + "(" + swiftArgumentsString + ")")
            cdeclBody.append("return SwiftObjectPointer.pointer(to: f_return_swift, retain: true)")
        } else if functionDeclaration.returnType == .void {
            body.append(externalName + "(" + externalArgumentsString + ")")
            cdeclBody.append(swiftCallTarget + functionName + "(" + swiftArgumentsString + ")")
        } else {
            body.append("val f_return_swift = " + externalName + "(" + externalArgumentsString + ")")
            body.append("return " + functionDeclaration.returnType.kotlinConvertFromExternal(value: "f_return_swift", strategy: .direct))

            cdeclBody.append("let f_return_swift = " + swiftCallTarget + functionName + "(" + swiftArgumentsString + ")")
            cdeclBody.append("return " + functionDeclaration.returnType.convertToCDecl(value: "f_return_swift", strategy: .direct))
        }
        functionDeclaration.body = KotlinCodeBlock(statements: body.map { KotlinRawStatement(sourceCode: $0) })

        var externalFunctionDeclaration = "private external fun " + externalName + "("
        if classDeclaration != nil, functionDeclaration.type != .constructorDeclaration {
            externalFunctionDeclaration += "Swift_peer: skip.bridge.SwiftObjectPointer"
            if !functionDeclaration.parameters.isEmpty {
                externalFunctionDeclaration += ", "
            }
        }
        externalFunctionDeclaration += functionDeclaration.parameters.map { p in
            p.internalLabel + ": " + p.declaredType.kotlinExternal(strategy: .direct).kotlin
        }.joined(separator: ", ")
        externalFunctionDeclaration += ")"
        if functionDeclaration.type == .constructorDeclaration {
            externalFunctionDeclaration += ": skip.bridge.SwiftObjectPointer"
        } else if functionDeclaration.returnType != .void {
            externalFunctionDeclaration += ": " + functionDeclaration.returnType.kotlinExternal(strategy: .direct).kotlin
        }
        (functionDeclaration.parent as? KotlinStatement)?.insert(statements: [KotlinRawStatement(sourceCode: externalFunctionDeclaration)], after: functionDeclaration)

        let (cdecl, cdeclName) = cdecl(for: functionDeclaration, name: externalName, translator: translator)
        let instanceParameter = classDeclaration != nil && functionDeclaration.type != .constructorDeclaration ? [cdeclInstanceParameter] : []
        let returnType: TypeSignature = functionDeclaration.type == .constructorDeclaration ? .swiftObjectPointer(java: false) : functionType.returnType
        let cdeclType: TypeSignature = .function(instanceParameter + functionType.parameters.map { p in
            TypeSignature.Parameter(label: p.label, type: p.type.cdecl(strategy: .direct))
        }, returnType.cdecl(strategy: .direct), APIFlags(), nil)
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclType, body: cdeclBody)
        cdeclFunctions.append(cdeclFunction)
    }

    private func updateClassDeclaration(_ classDeclaration: KotlinClassDeclaration, swiftDefinitions: inout [SwiftDefinition], cdeclFunctions: inout [CDeclFunction], translator: KotlinTranslator) {
        guard classDeclaration.checkBridgable(translator: translator) else {
            return
        }
        classDeclaration.extras = nil
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
                "let f_return_swift = " + classDeclaration.signature.description + "()",
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
            "Swift_peer.release(as: " + classDeclaration.signature.description + ".self)"
        ]
        cdeclFunctions.append(CDeclFunction(name: releaseCdecl.cdeclFunctionName, cdecl: releaseCdecl.cdecl, signature: .function([cdeclInstanceParameter], .void, APIFlags(), nil), body: releaseBody))

        for member in classDeclaration.members {
            if let variableDeclaration = member as? KotlinVariableDeclaration {
                updateVariableDeclaration(variableDeclaration, in: classDeclaration, cdeclFunctions: &cdeclFunctions, translator: translator)
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                updateFunctionDeclaration(functionDeclaration, cdeclFunctions: &cdeclFunctions, translator: translator)
            }
        }

        (classDeclaration.children.first as? KotlinStatement)?.ensureLeadingNewlines(1)
        classDeclaration.insert(statements: insertStatements, after: nil)

        // Add utility function to create a Java object from a Swift instance
        let classRef = JavaClassRef(for: classDeclaration, translator: translator)
        var swift: [String] = []
        swift.append("extension " + classDeclaration.signature.description + " {")
        swift.append(1, classRef.declaration)
        swift.append(1, classDeclaration.modifiers.visibility.swift(suffix: " ") + "func Java_swiftPeerBridged() -> JavaObjectPointer {")
        swift.append(2, "let Swift_peer = SwiftObjectPointer.pointer(to: self, retain: true)")
        swift.append(2, "return try! Self.Java_class.create(ctor: Self.Java_swiftPeerBridged_methodID, args: [Swift_peer.toJavaParameter(), (nil as JavaObjectPointer?).toJavaParameter()])")
        swift.append(1, "}")
        swift.append(1, "private static let Java_swiftPeerBridged_methodID = Java_class.getMethodID(name: \"<init>\", sig: \"(JLskip/bridge/SwiftPeerMarker;)V\")!")
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
        if let classDeclaration = statement.owningTypeDeclaration as? KotlinClassDeclaration {
            typeName = classDeclaration.signature.description
        } else {
            var file = translator.syntaxTree.source.file
            file.extension = ""
            typeName = file.name + "Kt"
        }
        return (cdeclPrefix + typeName.cdeclEscaped + "_" + name.cdeclEscaped, typeName + "_" + name)
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
