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
        let cdeclStatements = cdeclFunctions.map { cdeclFunctionStatement(for: $0) }
        syntaxTree.root.statements += cdeclStatements
        return true
    }

    private func updateVariableDeclaration(_ variableDeclaration: KotlinVariableDeclaration, cdeclFunctions: inout [CDeclFunction], translator: KotlinTranslator) {
        guard checkNonPrivate(variableDeclaration, modifiers: variableDeclaration.modifiers, translator: translator) else {
            return
        }
        let type = variableDeclaration.declaredType.or(variableDeclaration.propertyType)
        guard type != .none else {
            variableDeclaration.messages.append(Message.kotlinBridgeUnknownType(variableDeclaration, source: translator.syntaxTree.source))
            return
        }
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
        let externalType = type.external
        var externalFunctionDeclarations: [String] = []
        let (cdecl, cdeclName) = cdecl(for: variableDeclaration, name: externalName, translator: translator)

        // Getter
        let getterBody = [
            "val value_swift = " + externalName + "()",
            "return " + type.convertFromExternal(value: "value_swift")
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
                "val newValue_swift = " + type.convertToExternal(value: "newValue"),
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
            return variableDeclaration.value is KotlinBooleanLiteral
        case .double, .int, .int32:
            return variableDeclaration.value is KotlinNumericLiteral
        case .string:
            return variableDeclaration.value is KotlinStringLiteral
        default:
            return false
        }
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
        switch self {
        case .string:
            return .named("JavaString", [])
        default:
            return self.external
        }
    }

    fileprivate func convertToCDecl(value: String) -> String {
        switch self {
        case .string:
            return value + ".toJavaObject()!"
        default:
            return value // TODO: All other types
        }
    }

    fileprivate func convertFromCDecl(value: String) -> String {
        switch self {
        case .string:
            return "try! String.fromJavaObject(" + value + ")"
        default:
            return value // TODO: All other types
        }
    }
}
