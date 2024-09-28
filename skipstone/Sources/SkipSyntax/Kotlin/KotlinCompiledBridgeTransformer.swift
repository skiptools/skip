import Foundation

/// Generate compiled Swift to Kotlin bridging code.
final class KotlinCompiledBridgeTransformer: KotlinTransformer {
    private var cdeclFunctions: [CDeclFunction] = []
    private var lock = NSLock()

    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        guard syntaxTree.isBridgeFile, translator.codebaseInfo != nil else {
            return
        }
        // TODO: ~~~ strip unrecognized imports
        var localCdeclFunctions: [CDeclFunction] = []
        syntaxTree.root.visit { node in
            if let variableDeclaration = node as? KotlinVariableDeclaration, variableDeclaration.role == .global {
                updateVariableDeclaration(variableDeclaration, cdeclFunctions: &localCdeclFunctions, translator: translator)
                return .skip
            } else if let functionDeclaration = node as? KotlinFunctionDeclaration, functionDeclaration.role == .global {
                updateFunctionDeclaration(functionDeclaration, cdeclFunctions: &localCdeclFunctions, translator: translator)
                return .skip
            } else if let classDeclaration = node as? KotlinClassDeclaration {
                updateClassDeclaration(classDeclaration, cdeclFunctions: &localCdeclFunctions, translator: translator)
                return .recurse(nil)
            } else {
                return .recurse(nil)
            }
        }
        if !localCdeclFunctions.isEmpty {
            syntaxTree.dependencies.imports.insert("skip.bridge.SwiftObjectPointer")
            lock.lock()
            cdeclFunctions += localCdeclFunctions
            lock.unlock()
        }
    }

    func swiftBridgeOutput(translator: KotlinTranslator) -> OutputNode? {
        guard !cdeclFunctions.isEmpty else {
            return nil
        }
        let cdeclFunctions = self.cdeclFunctions
        return SwiftDefinition { output, indentation, _ in
            cdeclFunctions.sorted(by: { $0.cdecl < $1.cdecl }).forEach { $0.append(to: output, indentation: indentation) }
        }
    }

    private func updateVariableDeclaration(_ variableDeclaration: KotlinVariableDeclaration, in classQualifiedType: TypeSignature? = nil, cdeclFunctions: inout [CDeclFunction], translator: KotlinTranslator) {
        guard let (type, qualifiedType, strategy) = variableDeclaration.checkBridgable(translator: translator) else {
            return
        }
        variableDeclaration.extras = nil
        // If this is a let constant with a supported literal value, we'll re-declare rather than bridge it
        guard !isSupportedConstant(variableDeclaration, type: qualifiedType) else {
            return
        }

        // Remove initial value and make sure type is declared
        variableDeclaration.value = nil
        if variableDeclaration.declaredType == .none {
            variableDeclaration.declaredType = type
        }

        let propertyName = variableDeclaration.propertyName
        let externalName = "Swift_" + propertyName
        let externalType = type.kotlinExternal
        var externalFunctionDeclarations: [String] = []
        let (cdecl, cdeclName) = cdecl(for: variableDeclaration, name: externalName, translator: translator)

        // Getter
        let getterArguments = classQualifiedType == nil ? "()" : "(Swift_peer)"
        let getterParameters = classQualifiedType == nil ? "()" : "(Swift_peer: SwiftObjectPointer)"
        let getterBody = [
            "val value_swift = " + externalName + getterArguments,
            "return " + type.kotlinConvertFromExternal(value: "value_swift")
        ]
        variableDeclaration.getter = Accessor(body: KotlinCodeBlock(statements: getterBody.map { KotlinRawStatement(sourceCode: $0) }))
        externalFunctionDeclarations.append("private external fun " + externalName + getterParameters + ": " + externalType.kotlin)

        var cdeclGetterBody: [String]
        let cdeclInstanceParameters: [TypeSignature.Parameter]
        if let classQualifiedType {
            cdeclGetterBody = [
                "let peer_swift: " + classQualifiedType.description + " = Swift_peer.toSwift()",
                "let value_swift = peer_swift." + propertyName
            ]
            cdeclInstanceParameters = [cdeclInstanceParameter]
        } else {
            cdeclGetterBody = ["let value_swift = " + propertyName]
            cdeclInstanceParameters = []
        }
        cdeclGetterBody.append("return " + qualifiedType.convertToCDecl(value: "value_swift", strategy: strategy))
        let cdeclGetter = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: .function(cdeclInstanceParameters, qualifiedType.cdecl(strategy: strategy), APIFlags(), nil), body: cdeclGetterBody)
        cdeclFunctions.append(cdeclGetter)

        // Setter
        if variableDeclaration.apiFlags.options.contains(.writeable) {
            let setterArguments = classQualifiedType == nil ? "newValue_swift" : "Swift_peer, newValue_swift"
            let setterInstanceParameter = classQualifiedType == nil ? "" : "Swift_peer: SwiftObjectPointer, "
            let setterBody = [
                "val newValue_swift = " + type.kotlinConvertToExternal(value: "newValue"),
                externalName + "_set(" + setterArguments + ")"
            ]
            variableDeclaration.setter = Accessor(parameterName: "newValue", body: KotlinCodeBlock(statements: setterBody.map { KotlinRawStatement(sourceCode: $0) }))
            externalFunctionDeclarations.append("private external fun " + externalName + "_set(" + setterInstanceParameter + "value: " + externalType.kotlin + ")")

            var cdeclSetterBody = ["let value_swift = " + qualifiedType.convertFromCDecl(value: "value", strategy: strategy)]
            if let classQualifiedType {
                cdeclSetterBody += [
                    "let peer_swift: " + classQualifiedType.description + " = Swift_peer.toSwift()",
                    "peer_swift." + propertyName + " = value_swift"
                ]
            } else {
                cdeclSetterBody.append(propertyName + " = value_swift")
            }
            let cdeclSetter = CDeclFunction(name: cdeclName + "_set", cdecl: cdecl + "_1set", signature: .function(cdeclInstanceParameters + [TypeSignature.Parameter(label: "value", type: qualifiedType.cdecl(strategy: strategy))], .void, APIFlags(), nil), body: cdeclSetterBody)
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

    private func updateFunctionDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, in classQualifiedType: TypeSignature? = nil, cdeclFunctions: inout [CDeclFunction], translator: KotlinTranslator) {
        guard let qualifiedFunctionType = functionDeclaration.checkBridgable(translator: translator) else {
            return
        }
        functionDeclaration.extras = nil

        let functionName = functionDeclaration.name
        let externalName = "Swift_" + functionName

        var body: [String] = []
        var cdeclBody: [String] = []
        var externalParameterNames: [String] = []
        //~~~ use unqualified for Kotlin
        for (p, qualifiedType) in zip(functionDeclaration.parameters, qualifiedFunctionType.parameters.map(\.type)) {
            let externalParameterName = p.internalLabel + "_swift"
            body.append("val " + externalParameterName + " = " + p.declaredType.kotlinConvertToExternal(value: p.internalLabel))
            cdeclBody.append("let " + externalParameterName + " = " + qualifiedType.convertFromCDecl(value: p.internalLabel, strategy: .direct))
            externalParameterNames.append(externalParameterName)
        }

        let swiftCallTarget: String
        var externalArgumentsString = ""
        if let classQualifiedType, functionDeclaration.type != .constructorDeclaration {
            cdeclBody.append("let peer_swift: " + classQualifiedType.description + " = Swift_peer.toSwift()")
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
        
        if let classQualifiedType, functionDeclaration.type == .constructorDeclaration {
            body.append("Swift_peer = " + externalName + "(" + externalArgumentsString + ")")
            cdeclBody.append("let f_return_swift = " + classQualifiedType.description + "(" + swiftArgumentsString + ")")
            cdeclBody.append("return SwiftObjectPointer.forSwift(f_return_swift, retain: true)")
        } else if functionDeclaration.returnType == .void {
            body.append(externalName + "(" + externalArgumentsString + ")")
            cdeclBody.append(swiftCallTarget + functionName + "(" + swiftArgumentsString + ")")
        } else {
            body.append("val f_return_swift = " + externalName + "(" + externalArgumentsString + ")")
            body.append("return " + qualifiedFunctionType.returnType.kotlinConvertFromExternal(value: "f_return_swift"))

            cdeclBody.append("let f_return_swift = " + swiftCallTarget + functionName + "(" + swiftArgumentsString + ")")
            cdeclBody.append("return " + qualifiedFunctionType.returnType.convertToCDecl(value: "f_return_swift", strategy: .direct))
        }
        functionDeclaration.body = KotlinCodeBlock(statements: body.map { KotlinRawStatement(sourceCode: $0) })

        var externalFunctionDeclaration = "private external fun " + externalName + "("
        if classQualifiedType != nil, functionDeclaration.type != .constructorDeclaration {
            externalFunctionDeclaration += "Swift_peer: SwiftObjectPointer"
            if !functionDeclaration.parameters.isEmpty {
                externalFunctionDeclaration += ", "
            }
        }
        externalFunctionDeclaration += functionDeclaration.parameters.map { p in
            p.internalLabel + ": " + p.declaredType.kotlinExternal.kotlin
        }.joined(separator: ", ")
        externalFunctionDeclaration += ")"
        if functionDeclaration.type == .constructorDeclaration {
            externalFunctionDeclaration += ": SwiftObjectPointer"
        } else if functionDeclaration.returnType != .void {
            externalFunctionDeclaration += ": " + functionDeclaration.returnType.kotlinExternal.kotlin
        }
        (functionDeclaration.parent as? KotlinStatement)?.insert(statements: [KotlinRawStatement(sourceCode: externalFunctionDeclaration)], after: functionDeclaration)

        let (cdecl, cdeclName) = cdecl(for: functionDeclaration, name: externalName, translator: translator)
        let instanceParameters = classQualifiedType != nil && functionDeclaration.type != .constructorDeclaration ? [cdeclInstanceParameter] : []
        let returnType: TypeSignature = functionDeclaration.type == .constructorDeclaration ? .swiftObjectPointer : qualifiedFunctionType.returnType
        let cdeclType: TypeSignature = .function(instanceParameters + qualifiedFunctionType.parameters.map { p in
            TypeSignature.Parameter(label: p.label, type: p.type.cdecl(strategy: .direct))
        }, returnType.cdecl(strategy: .direct), APIFlags(), nil)
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclType, body: cdeclBody)
        cdeclFunctions.append(cdeclFunction)
    }

    private func updateClassDeclaration(_ classDeclaration: KotlinClassDeclaration, cdeclFunctions: inout [CDeclFunction], translator: KotlinTranslator) {
        guard let qualifiedType = classDeclaration.checkBridgable(translator: translator) else {
            return
        }
        classDeclaration.extras = nil

        var insertStatements: [KotlinStatement] = []
        let swiftPeer = KotlinVariableDeclaration(names: ["Swift_peer"], variableTypes: [.swiftObjectPointer])
        swiftPeer.modifiers.visibility = .public
        swiftPeer.apiFlags.options = .writeable
        swiftPeer.declaredType = .swiftObjectPointer
        swiftPeer.isGenerated = true
        insertStatements.append(swiftPeer)

        let swiftPeerConstructor = KotlinFunctionDeclaration(name: "constructor")
        swiftPeerConstructor.modifiers.visibility = .public
        swiftPeerConstructor.parameters = [Parameter<KotlinExpression>(externalLabel: "Swift_peer", declaredType: .swiftObjectPointer)]
        swiftPeerConstructor.body = KotlinCodeBlock(statements: [KotlinRawStatement(sourceCode: "this.Swift_peer = Swift_ptrref(Swift_peer)")])
        swiftPeerConstructor.ensureLeadingNewlines(1)
        swiftPeerConstructor.isGenerated = true
        insertStatements.append(swiftPeerConstructor)

        let ptrref = KotlinRawStatement(sourceCode: "private external fun Swift_ptrref(Swift_peer: SwiftObjectPointer): SwiftObjectPointer")
        insertStatements.append(ptrref)

        let finalize = KotlinFunctionDeclaration(name: "finalize")
        finalize.modifiers.visibility = .public
        finalize.body = KotlinCodeBlock(statements: [
            "Swift_ptrderef(Swift_peer)",
            "Swift_peer = SwiftObjectNil"
        ].map { KotlinRawStatement(sourceCode: $0) })
        finalize.ensureLeadingNewlines(1)
        finalize.isGenerated = true
        insertStatements.append(finalize)

        let ptrderef = KotlinRawStatement(sourceCode: "private external fun Swift_ptrderef(Swift_peer: SwiftObjectPointer)")
        insertStatements.append(ptrderef)

        if !classDeclaration.members.contains(where: { $0.type == .constructorDeclaration }) {
            let constructor = KotlinFunctionDeclaration(name: "constructor")
            constructor.modifiers.visibility = .public
            constructor.body = KotlinCodeBlock(statements: [KotlinRawStatement(sourceCode: "Swift_peer = Swift_constructor()")])
            constructor.ensureLeadingNewlines(1)
            constructor.isGenerated = true
            insertStatements.append(constructor)
            let externalConstructor = KotlinRawStatement(sourceCode: "private external fun Swift_constructor(): SwiftObjectPointer")
            insertStatements.append(externalConstructor)

            let constructorCdecl = cdecl(for: classDeclaration, name: "Swift_constructor", translator: translator)
            let constructorBody = [
                "let f_return_swift = " + classDeclaration.signature.description + "()",
                "return SwiftObjectPointer.forSwift(f_return_swift, retain: true)"
            ]
            cdeclFunctions.append(CDeclFunction(name: constructorCdecl.cdeclFunctionName, cdecl: constructorCdecl.cdecl, signature: .function([], .swiftObjectPointer, APIFlags(), nil), body: constructorBody))
        }

        let ptrrefCdecl = cdecl(for: classDeclaration, name: "Swift_ptrref", translator: translator)
        let ptrrefBody = [
            "return refSwift(Swift_peer, type: " + classDeclaration.signature.description + ".self)"
        ]
        cdeclFunctions.append(CDeclFunction(name: ptrrefCdecl.cdeclFunctionName, cdecl: ptrrefCdecl.cdecl, signature: .function([cdeclInstanceParameter], .swiftObjectPointer, APIFlags(), nil), body: ptrrefBody))

        let ptrderefCdecl = cdecl(for: classDeclaration, name: "Swift_ptrderef", translator: translator)
        let ptrderefBody = [
            "derefSwift(Swift_peer, type: " + classDeclaration.signature.description + ".self)"
        ]
        cdeclFunctions.append(CDeclFunction(name: ptrderefCdecl.cdeclFunctionName, cdecl: ptrderefCdecl.cdecl, signature: .function([cdeclInstanceParameter], .void, APIFlags(), nil), body: ptrderefBody))

        for member in classDeclaration.members {
            if let variableDeclaration = member as? KotlinVariableDeclaration {
                updateVariableDeclaration(variableDeclaration, in: qualifiedType, cdeclFunctions: &cdeclFunctions, translator: translator)
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                updateFunctionDeclaration(functionDeclaration, cdeclFunctions: &cdeclFunctions, translator: translator)
            }
        }

        (classDeclaration.children.first as? KotlinStatement)?.ensureLeadingNewlines(1)
        classDeclaration.insert(statements: insertStatements, after: nil)
    }

    private func cdecl(for statement: KotlinStatement, name: String, translator: KotlinTranslator) -> (cdecl: String, cdeclFunctionName: String) {
        var cdeclPrefix = "Java_"
        if let package = translator.packageName {
            cdeclPrefix += package.cdeclEscaped.replacing(".", with: "_") + "_"
        }
        let typeName: String
        if let classDeclaration = statement.owningTypeDeclaration as? KotlinClassDeclaration {
            typeName = classDeclaration.name
        } else {
            var file = translator.syntaxTree.source.file
            file.extension = ""
            typeName = file.name + "Kt"
        }
        return (cdeclPrefix + typeName.cdeclEscaped + "_" + name.cdeclEscaped, typeName + "_" + name)
    }

    private var cdeclInstanceParameter: TypeSignature.Parameter {
        return TypeSignature.Parameter(label: "Swift_peer", type: .swiftObjectPointer)
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
