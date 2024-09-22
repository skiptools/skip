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
            }
            return .recurse(nil)
        }
        if !localCdeclFunctions.isEmpty {
            lock.lock()
            cdeclFunctions += localCdeclFunctions
            lock.unlock()
        }
    }

    func apply(toSwiftBridge syntaxTree: SyntaxTree, imports: inout Set<String>, translator: KotlinTranslator) -> Bool {
        guard !cdeclFunctions.isEmpty else {
            return false
        }
        
        imports.insert("SkipJNI")
        // TODO: Update cdecls to add argument type encodings on conflicting functions
        // TODO: Imports
        let cdeclFunctionDefinitions = cdeclFunctions.map { cdeclFunctionDefinition(for: $0) }
        syntaxTree.root.statements += cdeclFunctionDefinitions
        return true
    }

    private func updateVariableDeclaration(_ variableDeclaration: KotlinVariableDeclaration, cdeclFunctions: inout [CDeclFunction], translator: KotlinTranslator) {
        guard checkNonPrivate(variableDeclaration, modifiers: variableDeclaration.modifiers, translator: translator) else {
            return
        }
        let type = variableDeclaration.propertyType
        guard type != .none else {
            variableDeclaration.messages.append(Message.kotlinBridgeUnknownType(variableDeclaration, source: translator.syntaxTree.source))
            return
        }

        // If this is a let constant with a supported literal value, we'll re-declare rather than bridge it.
        // Otherwise we update the value to a call to our external bridge function
        let externalName = "Swift_" + variableDeclaration.propertyName
        let (cdecl, cdeclName) = cdecl(for: variableDeclaration, name: externalName, translator: translator)
        if let value = variableDeclaration.value {
            guard !variableDeclaration.isLet || !(value is KotlinNullLiteral || value is KotlinNumericLiteral || value is KotlinStringLiteral) else {
                return
            }
            variableDeclaration.value = nil
            if variableDeclaration.declaredType == .none {
                variableDeclaration.declaredType = variableDeclaration.propertyType
            }
        }

        let externalType = variableDeclaration.propertyType.external
        var externalFunctionDeclarations: [String] = []

        // Getter
        let getterBody = [
            "val ret_swift = " + externalName + "()",
            "return " + variableDeclaration.propertyType.convertFromExternal(value: "ret_swift")
        ]
        variableDeclaration.getter = Accessor(body: KotlinCodeBlock(statements: getterBody.map { KotlinRawStatement(sourceCode: $0) }))
        externalFunctionDeclarations.append("private external fun " + externalName + "(): " + externalType.kotlin)

        var cdeclGetterBody: [String] = []
        if variableDeclaration.role == .property, let classDeclaration = variableDeclaration.parent as? KotlinClassDeclaration {
            cdeclGetterBody = [
                "let peer_swift: " + classDeclaration.signature.description + " = Swift_peer.toSwift()",
                "return peer_swift." + variableDeclaration.propertyName
            ]
        } else {
            cdeclGetterBody = ["return " + variableDeclaration.propertyName]
        }
        let cdeclGetter = CDeclFunction(name: cdeclName, cdecl: cdecl, signature: .function([], variableDeclaration.propertyType.cdecl, APIFlags(), nil), body: cdeclGetterBody)
        cdeclFunctions.append(cdeclGetter)

        // Setter
        if variableDeclaration.apiFlags.options.contains(.writeable) && variableDeclaration.modifiers.setVisibility != .private && variableDeclaration.modifiers.setVisibility != .fileprivate {
            let setterBody = [
                "val newValue_swift = " + variableDeclaration.propertyType.convertToExternal(value: "newValue"),
                externalName + "_set(newValue_swift)"
            ]
            variableDeclaration.setter = Accessor(parameterName: "newValue", body: KotlinCodeBlock(statements: setterBody.map { KotlinRawStatement(sourceCode: $0) }))
            externalFunctionDeclarations.append("private external fun " + externalName + "_set(value: " + externalType.kotlin + ")")

            let cdeclSetterBody: [String]
            let cdeclSetterInstance: [TypeSignature.Parameter]
            if variableDeclaration.role == .property, let classDeclaration = variableDeclaration.parent as? KotlinClassDeclaration {
                cdeclSetterBody = [
                    "let peer_swift: " + classDeclaration.signature.description + " = Swift_peer.toSwift()",
                    "peer_swift." + variableDeclaration.propertyName + " = value"
                ]
                cdeclSetterInstance = [cdeclInstanceParameter]
            } else {
                cdeclSetterBody = [variableDeclaration.propertyName + " = value"]
                cdeclSetterInstance = []
            }
            let cdeclSuffix = "_set"
            let cdeclSetter = CDeclFunction(name: cdeclName + cdeclSuffix, cdecl: cdecl + cdeclSuffix, signature: .function(cdeclSetterInstance + [TypeSignature.Parameter(label: "value", type: variableDeclaration.propertyType.cdecl)], .void, APIFlags(), nil), body: cdeclSetterBody)
            cdeclFunctions.append(cdeclSetter)
        } else {
            variableDeclaration.setter = nil
        }
        variableDeclaration.willSet = nil
        variableDeclaration.didSet = nil

        // Add function declarations to transpiled output
        (variableDeclaration.parent as? KotlinStatement)?.insert(statements: externalFunctionDeclarations.map { KotlinRawStatement(sourceCode: $0) }, after: variableDeclaration)
    }

    private func cdecl(for statement: KotlinStatement, name: String, translator: KotlinTranslator) -> (cdecl: String, cdeclFunctionName: String) {
        var cdeclPrefix = "Java_"
        if let package = translator.packageName {
            cdeclPrefix += package.cdeclEscaped.replacing(".", with: "_") + "_"
        }
        // TODO: Protocols, nesting, etc
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

    private func cdeclFunctionDefinition(`for` function: CDeclFunction) -> RawStatement {
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

    private func checkNonPrivate(_ sourceDerived: SourceDerived, modifiers: Modifiers, translator: KotlinTranslator) -> Bool {
        guard modifiers.visibility == .private || modifiers.visibility == .fileprivate else {
            return true
        }
        sourceDerived.messages.append(Message.kotlinBridgePrivate(sourceDerived, source: translator.syntaxTree.source))
        return false
    }
}

private struct CDeclFunction {
    let name: String
    let cdecl: String
    let signature: TypeSignature
    let body: [String]
}

extension String {
    fileprivate var cdeclEscaped: String {
        // TODO: Unicode chars
        return replacing("_", with: "_1")
    }
}

extension TypeSignature {
    fileprivate var external: TypeSignature {
        switch self {
        case .int:
            return .int64
        default:
            return self // TODO: All other types
        }
    }

    fileprivate func convertToExternal(value: String) -> String {
        switch self {
        case .int:
            return value + ".toLong()"
        default:
            return value // TODO: All other types
        }
    }

    fileprivate func convertFromExternal(value: String) -> String {
        switch self {
        case .int:
            return value + ".toInt()"
        default:
            return value // TODO: All other types
        }
    }

    fileprivate var cdecl: TypeSignature {
        // TODO: Object types, etc
        return external
    }
}
