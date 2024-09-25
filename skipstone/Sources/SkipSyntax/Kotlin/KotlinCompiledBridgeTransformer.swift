import Foundation

/// Generate compiled Swift to Kotlin bridging code.
final class KotlinCompiledBridgeTransformer: KotlinTransformer {
    private var cdeclFunctions: [CDeclFunction] = []
    private var lock = NSLock()

    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        guard syntaxTree.isBridgeFile else {
            return
        }
        var localCdeclFunctions: [CDeclFunction] = []
        syntaxTree.root.visit { node in
            if let variableDeclaration = node as? KotlinVariableDeclaration, variableDeclaration.role == .global || variableDeclaration.role == .property {
                updateVariableDeclaration(variableDeclaration, cdeclFunctions: &localCdeclFunctions, translator: translator)
                return .skip
            } else if let functionDeclaration = node as? KotlinFunctionDeclaration, functionDeclaration.role == .global {
                updateFunctionDeclaration(functionDeclaration, cdeclFunctions: &localCdeclFunctions, translator: translator)
                return .skip
            }
            return .recurse(nil)
        }
        if !localCdeclFunctions.isEmpty {
            lock.lock()
            cdeclFunctions += localCdeclFunctions
            lock.unlock()
        }
    }

    func apply(toSwiftBridge syntaxTree: SyntaxTree, translator: KotlinTranslator) -> Bool {
        guard !cdeclFunctions.isEmpty else {
            return false
        }
        // TODO: Imports
        let cdeclStatements = cdeclFunctions.map { cdeclFunctionStatement(for: $0) }
        syntaxTree.root.statements += cdeclStatements
        return true
    }

    private func updateVariableDeclaration(_ variableDeclaration: KotlinVariableDeclaration, cdeclFunctions: inout [CDeclFunction], translator: KotlinTranslator) {
        guard let type = variableDeclaration.checkBridgable(translator: translator) else {
            return
        }
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
        let externalType = type.kotlinExternal
        var externalFunctionDeclarations: [String] = []
        let (cdecl, cdeclName) = cdecl(for: variableDeclaration, name: externalName, translator: translator)

        // Getter
        let getterBody = [
            "val value_swift = " + externalName + "()",
            "return " + type.kotlinConvertFromExternal(value: "value_swift")
        ]
        variableDeclaration.getter = Accessor(body: KotlinCodeBlock(statements: getterBody.map { KotlinRawStatement(sourceCode: $0) }))
        externalFunctionDeclarations.append("private external fun " + externalName + "(): " + externalType.kotlin)

        var cdeclGetterBody: [String] = []
        if variableDeclaration.role == .property, let classDeclaration = variableDeclaration.parent as? KotlinClassDeclaration {
            cdeclGetterBody = [
                "let peer_swift: " + classDeclaration.signature.description + " = Swift_peer.toSwift()",
                "let value_swift = peer_swift." + propertyName,
                "return " + type.convertToCDecl(value: "value_swift")
            ]
        } else {
            cdeclGetterBody = [
                "let value_swift = " + propertyName,
                "return " + type.convertToCDecl(value: "value_swift")
            ]
        }
        let cdeclGetter = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: .function([], type.cdecl, APIFlags(), nil), body: cdeclGetterBody)
        cdeclFunctions.append(cdeclGetter)

        // Setter
        if variableDeclaration.apiFlags.options.contains(.writeable) && variableDeclaration.modifiers.setVisibility != .private && variableDeclaration.modifiers.setVisibility != .fileprivate {
            let setterBody = [
                "val newValue_swift = " + type.kotlinConvertToExternal(value: "newValue"),
                externalName + "_set(newValue_swift)"
            ]
            variableDeclaration.setter = Accessor(parameterName: "newValue", body: KotlinCodeBlock(statements: setterBody.map { KotlinRawStatement(sourceCode: $0) }))
            externalFunctionDeclarations.append("private external fun " + externalName + "_set(value: " + externalType.kotlin + ")")

            let cdeclSetterBody: [String]
            let cdeclSetterInstance: [TypeSignature.Parameter]
            if variableDeclaration.role == .property, let classDeclaration = variableDeclaration.parent as? KotlinClassDeclaration {
                cdeclSetterBody = [
                    "let peer_swift: " + classDeclaration.signature.description + " = Swift_peer.toSwift()",
                    "let value_swift = " + type.convertFromCDecl(value: "value"),
                    "peer_swift." + propertyName + " = value_swift"
                ]
                cdeclSetterInstance = [cdeclInstanceParameter]
            } else {
                cdeclSetterBody = [
                    "let value_swift = " + type.convertFromCDecl(value: "value"),
                    propertyName + " = value_swift"
                ]
                cdeclSetterInstance = []
            }
            let cdeclSetter = CDeclFunction(name: cdeclName + "_set", cdecl: cdecl + "_1set", signature: .function(cdeclSetterInstance + [TypeSignature.Parameter(label: "value", type: type.cdecl)], .void, APIFlags(), nil), body: cdeclSetterBody)
            cdeclFunctions.append(cdeclSetter)
        } else {
            variableDeclaration.setter = nil
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

    private func updateFunctionDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, cdeclFunctions: inout [CDeclFunction], translator: KotlinTranslator) {
        guard functionDeclaration.checkBridgable(translator: translator) else {
            return
        }
        functionDeclaration.extras = nil

        let functionName = functionDeclaration.name
        let externalName = "Swift_" + functionName

        var body: [String] = []
        var cdeclBody: [String] = []
        var externalParameterNames: [String] = []
        for p in functionDeclaration.parameters {
            let externalParameterName = p.internalLabel + "_swift"
            body.append("val " + externalParameterName + " = " + p.declaredType.kotlinConvertToExternal(value: p.internalLabel))
            cdeclBody.append("let " + externalParameterName + " = " + p.declaredType.convertFromCDecl(value: p.internalLabel))
            externalParameterNames.append(externalParameterName)
        }
        let externalCall = externalName + "(" + externalParameterNames.joined(separator: ", ")  + ")"
        let cdeclCall = functionName + "(" + functionDeclaration.parameters.enumerated().map { index, p in
            if let externalLabel = p.externalLabel {
                return externalLabel + ": " + externalParameterNames[index]
            } else {
                return externalParameterNames[index]
            }
        }.joined(separator: ", ") + ")"
        if functionDeclaration.returnType == .void {
            body.append(externalCall)
            cdeclBody.append(cdeclCall)
        } else {
            body.append("val f_return_swift = " + externalCall)
            body.append("return " + functionDeclaration.returnType.kotlinConvertFromExternal(value: "f_return_swift"))

            cdeclBody.append("let f_return_swift = " + cdeclCall)
            cdeclBody.append("return " + functionDeclaration.returnType.convertToCDecl(value: "f_return_swift"))
        }
        functionDeclaration.body = KotlinCodeBlock(statements: body.map { KotlinRawStatement(sourceCode: $0) })

        var externalFunctionDeclaration = "private external fun " + externalName + "("
        externalFunctionDeclaration += functionDeclaration.parameters.map { p in
            p.internalLabel + ": " + p.declaredType.kotlinExternal.kotlin
        }.joined(separator: ", ")
        externalFunctionDeclaration += ")"
        if functionDeclaration.returnType != .void {
            externalFunctionDeclaration += ": " + functionDeclaration.returnType.kotlinExternal.kotlin
        }
        (functionDeclaration.parent as? KotlinStatement)?.insert(statements: [KotlinRawStatement(sourceCode: externalFunctionDeclaration)], after: functionDeclaration)

        let (cdecl, cdeclName) = cdecl(for: functionDeclaration, name: externalName, translator: translator)
        let functionType = functionDeclaration.functionType
        let cdeclType: TypeSignature = .function(functionType.parameters.map { p in
            TypeSignature.Parameter(label: p.label, type: p.type.cdecl)
        }, functionType.returnType.cdecl, APIFlags(), nil)
        let cdeclFunction = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclType, body: cdeclBody)
        cdeclFunctions.append(cdeclFunction)
    }

    private func cdecl(for statement: KotlinStatement, name: String, translator: KotlinTranslator) -> (cdecl: String, cdeclFunctionName: String) {
        var cdeclPrefix = "Java_"
        if let package = translator.packageName {
            cdeclPrefix += package.cdeclEscaped.replacing(".", with: "_") + "_"
        }
        let typeName: String
        if let classDeclaration = statement.parent as? KotlinClassDeclaration {
            typeName = classDeclaration.name
        } else {
            var file = translator.syntaxTree.source.file
            file.extension = ""
            typeName = file.name + "Kt"
        }
        return (cdeclPrefix + typeName.cdeclEscaped + "_" + name.cdeclEscaped, typeName + "_" + name)
    }

    private var cdeclInstanceParameter: TypeSignature.Parameter {
        return TypeSignature.Parameter(label: "Swift_Peer", type: .named("SwiftObjectPtr", []))
    }

    private func cdeclFunctionStatement(for function: CDeclFunction) -> RawStatement {
        var parameters = ""
        for parameter in function.signature.parameters {
            parameters += ", _"
            if let label = parameter.label {
                parameters += " " + label
            }
            parameters += ": " + parameter.type.description
        }
        let returnType = function.signature.returnType
        let ret = returnType == .void ? "" : " -> " + returnType.description

        let body = function.body.map { "    " + $0 }.joined(separator: "\n")
        let sourceCode = """
        @_cdecl("\(function.cdecl)")
        func \(function.name)(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer\(parameters))\(ret) {
        \(body)
        }
        """
        return RawStatement(sourceCode: sourceCode)
    }
}

private struct CDeclFunction {
    let name: String
    let cdecl: String
    let signature: TypeSignature
    let body: [String]
}
