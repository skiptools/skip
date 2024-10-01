import Foundation

/// Generate transpiled Swift (Kotlin) to compiled Swift bridging code.
final class KotlinTranspiledBridgeTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        guard !syntaxTree.isBridgeFile, translator.codebaseInfo != nil, let outputFile = syntaxTree.source.file.bridgeOutputFile else {
            return []
        }
        var swiftDefinitions: [SwiftDefinition] = []
        var globalsJavaClasses:  Set<JavaClassRef> = []
        syntaxTree.root.visit { node in
            if let variableDeclaration = node as? KotlinVariableDeclaration, variableDeclaration.role == .global {
                if variableDeclaration.attributes.contains(directive: Directive.bridge) {
                    addSwiftDefinitions(forGlobal: variableDeclaration, to: &swiftDefinitions, globalsJavaClasses: &globalsJavaClasses, translator: translator)
                }
                return .skip
            } else if let functionDeclaration = node as? KotlinFunctionDeclaration, functionDeclaration.role == .global {
                if functionDeclaration.attributes.contains(directive: Directive.bridge) {
                    addSwiftDefinitions(forGlobal: functionDeclaration, to: &swiftDefinitions, globalsJavaClasses: &globalsJavaClasses, translator: translator)
                }
                return .skip
            } else if let classDeclaration = node as? KotlinClassDeclaration {
                if classDeclaration.attributes.contains(directive: Directive.bridge) {
                    addSwiftDefinitions(for: classDeclaration, to: &swiftDefinitions, translator: translator)
                }
                return .recurse(nil)
            } else {
                return .recurse(nil)
            }
        }
        guard !swiftDefinitions.isEmpty else {
            return []
        }

        let importDeclarations = syntaxTree.root.statements
            .compactMap { $0 as? KotlinImportDeclaration }
            .filter { !$0.isKotlinImport }
        let globalsJavaClassDescriptions = globalsJavaClasses.map(\.description).sorted()
        let outputNode = SwiftDefinition { output, indentation, _ in
            output.append("#if canImport(SkipBridge)\nimport SkipBridge\n\n")
            for importDeclaration in importDeclarations {
                let path = importDeclaration.modulePath.joined(separator: ".")
                output.append(indentation).append("import ").append(path).append("\n")
            }
            globalsJavaClassDescriptions.forEach { output.append(indentation).append($0).append("\n") }
            swiftDefinitions.forEach { output.append($0, indentation: indentation) }
            output.append("\n#endif")
        }
        let output = KotlinTransformerOutput(file: outputFile, node: outputNode)
        return [output]
    }

    private func addSwiftDefinitions(forGlobal variableDeclaration: KotlinVariableDeclaration, to swiftDefinitions: inout [SwiftDefinition], globalsJavaClasses: inout Set<JavaClassRef>, translator: KotlinTranslator) {
        guard let (type, qualifiedType, strategy) = variableDeclaration.checkBridgable(translator: translator) else {
            return
        }
        guard !addConstantDefinition(for: variableDeclaration, type: type, to: &swiftDefinitions, translator: translator) else {
            return
        }
        let classRef = globalsJavaClass(translator: translator)
        globalsJavaClasses.insert(classRef)

        let swift = swift(for: variableDeclaration, type: type, qualified: qualifiedType, strategy: strategy, targetIdentifier: classRef.identifier, classIdentifier: classRef.identifier, getMethodIdentifier: "Java_get_" + variableDeclaration.propertyName + "_methodID", setMethodIdentifier: "Java_set_" + variableDeclaration.propertyName + "_methodID", translator: translator)
        swiftDefinitions.append(SwiftDefinition(statement: variableDeclaration, swift: swift))
    }

    private func addSwiftDefinitions(for variableDeclaration: KotlinVariableDeclaration, to swiftDefinitions: inout [SwiftDefinition], translator: KotlinTranslator) {
        guard variableDeclaration.modifiers.visibility != .private && variableDeclaration.modifiers.visibility != .fileprivate && !variableDeclaration.attributes.contains(directive: Directive.nobridge) else {
            return
        }
        guard let (type, qualifiedType, strategy) = variableDeclaration.checkBridgable(translator: translator) else {
            return
        }
        guard !addConstantDefinition(for: variableDeclaration, type: type, to: &swiftDefinitions, translator: translator) else {
            return
        }

        let swift = swift(for: variableDeclaration, type: type, qualified: qualifiedType, strategy: strategy, targetIdentifier: "Java_peer", classIdentifier: "Java_class", getMethodIdentifier: "Java_get_" + variableDeclaration.propertyName + "_methodID", setMethodIdentifier: "Java_set_" + variableDeclaration.propertyName + "_methodID", translator: translator)
        swiftDefinitions.append(SwiftDefinition(statement: variableDeclaration, swift: swift))
    }

    private func swift(for variableDeclaration: KotlinVariableDeclaration, type: TypeSignature, qualified qualifiedType: TypeSignature, strategy: BridgeStrategy, targetIdentifier: String, classIdentifier: String, getMethodIdentifier: String, setMethodIdentifier: String, translator: KotlinTranslator) -> [String] {
        var swift: [String] = []
        let propertyName = variableDeclaration.propertyName
        let preEscapedPropertyName = variableDeclaration.preEscapedPropertyName
        let visibility = variableDeclaration.modifiers.visibility.swift(suffix: " ")
        swift.append(visibility + "var " + (preEscapedPropertyName ?? propertyName) + ": " + type.description + " {")

        // Getter
        let callType = variableDeclaration.role == .global ? "callStatic" : "call"
        let callGet = variableDeclaration.role == .global ? getMethodIdentifier : "Self." + getMethodIdentifier
        swift.append(1, "get {")
        swift.append(2, [
            "let value_java: " + type.java.description + " = try! " + targetIdentifier + "." + callType + "(method: " + callGet  + ", [])",
            "return " + type.convertFromJava(value: "value_java", strategy: strategy)
        ])
        swift.append(1, "}")

        // Setter
        let hasSetter = variableDeclaration.apiFlags.options.contains(.writeable) && variableDeclaration.modifiers.setVisibility != .private && variableDeclaration.modifiers.setVisibility != .fileprivate
        if hasSetter {
            let setVisibility: String
            if variableDeclaration.modifiers.setVisibility < variableDeclaration.modifiers.visibility {
                setVisibility = variableDeclaration.modifiers.setVisibility.swift(suffix: " ")
            } else {
                setVisibility = ""
            }
            let callSet = variableDeclaration.role == .global ? setMethodIdentifier : "Self." + setMethodIdentifier
            swift.append(1, setVisibility + "set {")
            swift.append(2, [
                "let value_java = " + type.convertToJava(value: "newValue", strategy: strategy) + ".toJavaParameter()",
                "try! " + targetIdentifier + "." + callType + "(method: " + callSet + ", [value_java])"
            ])
            swift.append(1, "}")
        }
        swift.append("}")

        let capitalizedPropertyName = (propertyName.first?.uppercased() ?? "") + propertyName.dropFirst()
        let declarationType = variableDeclaration.role == .global ? "let " : "static let "
        let callMethodID = variableDeclaration.role == .global ? "getStaticMethodID" : "getMethodID"
        let getMethodID = "private " + declarationType + getMethodIdentifier + " = " + classIdentifier + "." + callMethodID + "(name: \"get" + capitalizedPropertyName + "\", sig: \"()" + qualifiedType.jni + "\")!"
        swift.append(getMethodID)
        if hasSetter {
            let setMethodID = "private " + declarationType + setMethodIdentifier + " = " + classIdentifier + "." + callMethodID + "(name: \"set" + capitalizedPropertyName + "\", sig: \"(" + qualifiedType.jni + ")V\")!"
            swift.append(setMethodID)
        }
        return swift
    }

    private func addConstantDefinition(for variableDeclaration: KotlinVariableDeclaration, type: TypeSignature, to swiftDefinitions: inout [SwiftDefinition], translator: KotlinTranslator) -> Bool {
        guard variableDeclaration.isLet, let value = variableDeclaration.value else {
            return false
        }
        var assignment: String? = nil
        switch value.type {
        case .booleanLiteral:
            if type == .bool, let literal = value as? KotlinBooleanLiteral {
                assignment = " = " + literal.literal.description
            }
        case .nullLiteral:
            assignment = ": " + type.description + " = nil"
        case .numericLiteral:
            if type.isNumeric, let literal = value as? KotlinNumericLiteral {
                assignment = ": " + type.description + " = " + literal.literal
            }
        case .stringLiteral:
            if type == .string, let stringLiteral = variableDeclaration.value as? KotlinStringLiteral, let swiftString = stringLiteral.swiftString, !stringLiteral.isMultiline {
                assignment = " = \"" + swiftString + "\""
            }
        default:
            if type.isNumeric, let functionCall = value as? KotlinFunctionCall, let literal = numericLiteral(from: functionCall) {
                assignment = ": " + type.description + " = " + literal.literal
            }
        }
        guard let assignment else {
            return false
        }
        let swift = variableDeclaration.modifiers.visibility.swift(suffix: " ") + "let " + variableDeclaration.propertyName + assignment
        swiftDefinitions.append(SwiftDefinition(statement: variableDeclaration, swift: [swift]))
        return true
    }

    /// If this is a numeric literal cast - e.g. `Int64(<literal>)` - return the literal.
    private func numericLiteral(from functionCall: KotlinFunctionCall) -> KotlinNumericLiteral? {
        let arguments = functionCall.arguments
        guard arguments.count == 1, arguments[0].label == nil, let numberLiteral = arguments[0].value as? KotlinNumericLiteral else {
            return nil
        }
        let functionName: String
        if let identifier = functionCall.function as? KotlinIdentifier {
            functionName = identifier.name
        } else if let memberAccess = functionCall.function as? KotlinMemberAccess {
            guard let baseIdentifier = memberAccess.base as? KotlinIdentifier, baseIdentifier.name == "Swift" else {
                return nil
            }
            functionName = memberAccess.member
        } else {
            return nil
        }
        return TypeSignature.for(name: functionName, genericTypes: []).isNumeric ? numberLiteral : nil
    }

    private func addSwiftDefinitions(forGlobal functionDeclaration: KotlinFunctionDeclaration, to swiftDefinitions: inout [SwiftDefinition], globalsJavaClasses: inout Set<JavaClassRef>, translator: KotlinTranslator) {
        guard let qualifiedType = functionDeclaration.checkBridgable(translator: translator) else {
            return
        }

        let classRef = globalsJavaClass(translator: translator)
        globalsJavaClasses.insert(classRef)

        let swift = swift(for: functionDeclaration, qualified: qualifiedType, targetIdentifier: classRef.identifier, classIdentifier: classRef.identifier, methodIdentifier: "Java_" + functionDeclaration.name + "_methodID", translator: translator)
        swiftDefinitions.append(SwiftDefinition(statement: functionDeclaration, swift: swift))
    }

    private func addSwiftDefinitions(for functionDeclaration: KotlinFunctionDeclaration, to swiftDefinitions: inout [SwiftDefinition], translator: KotlinTranslator) {
        guard functionDeclaration.modifiers.visibility != .private && functionDeclaration.modifiers.visibility != .fileprivate && !functionDeclaration.attributes.contains(directive: Directive.nobridge) else {
            return
        }
        guard let qualifiedType = functionDeclaration.checkBridgable(translator: translator) else {
            return
        }

        let swift = swift(for: functionDeclaration, qualified: qualifiedType, targetIdentifier: "Java_peer", classIdentifier: "Java_class", methodIdentifier: "Java_" + functionDeclaration.name + "_methodID", translator: translator)
        swiftDefinitions.append(SwiftDefinition(statement: functionDeclaration, swift: swift))
    }

    private func swift(for functionDeclaration: KotlinFunctionDeclaration, qualified qualifiedType: TypeSignature, targetIdentifier: String, classIdentifier: String, methodIdentifier: String, translator: KotlinTranslator) -> [String] {
        var swift: [String] = []

        var functionType = functionDeclaration.functionType
        var qualifiedType = qualifiedType
        if functionDeclaration.type == .constructorDeclaration {
            functionType = functionType.withReturnType(.void)
            qualifiedType = qualifiedType.withReturnType(.void)
        }
        let visibility = functionDeclaration.modifiers.visibility.swift(suffix: " ")
        let parameterString = functionDeclaration.parameters.map(\.swift).joined(separator: ", ")
        let returnString = functionType.returnType == .void ? "" : " -> " + functionType.returnType.description
        swift.append(visibility + (functionDeclaration.type == .constructorDeclaration ? "init" : "func " + functionDeclaration.name) + "(" + parameterString + ")" + returnString + " {")

        var javaParameterNames: [String] = []
        for p in functionDeclaration.parameters {
            let name = p.internalLabel + "_java"
            javaParameterNames.append(name)
            swift.append(1, "let " + name + " = " + p.declaredType.convertToJava(value: p.internalLabel, strategy: .direct) + ".toJavaParameter()")
        }

        if functionDeclaration.type == .constructorDeclaration {
            swift.append(1, "let ptr = try! Self.Java_class.create(ctor: Self." + methodIdentifier + ", [" + javaParameterNames.joined(separator: ", ") + "])")
            swift.append(1, "Java_peer = JObject(ptr)")
        } else {
            let callType = functionDeclaration.role == .global ? "callStatic" : "call"
            let callMethod = functionDeclaration.role == .global ? methodIdentifier : "Self." + methodIdentifier
            let call = "try! " + targetIdentifier + "." + callType + "(method: " + callMethod + ", [" + javaParameterNames.joined(separator: ", ") + "])"
            if functionType.returnType == .void {
                swift.append(1, call)
            } else {
                swift.append(1, "let f_return_java: " + functionType.returnType.java.description + " = " + call)
                swift.append(1, "return " + functionType.returnType.convertFromJava(value: "f_return_java", strategy: .direct))
            }
        }
        swift.append("}")

        let declarationType = functionDeclaration.role == .global ? "let " : "static let "
        let getType = functionDeclaration.role == .global ? "getStaticMethodID" : "getMethodID"
        let methodID = "private " + declarationType + methodIdentifier + " = " + classIdentifier + "." + getType + "(name: \"" + (functionDeclaration.type == .constructorDeclaration ? "<init>" : functionDeclaration.name) + "\", sig: \"" + qualifiedType.jni + "\")!"
        swift.append(methodID)
        return swift
    }

    private func addSwiftDefinitions(for classDeclaration: KotlinClassDeclaration, to swiftDefinitions: inout [SwiftDefinition], translator: KotlinTranslator) {
        guard classDeclaration.checkBridgable(translator: translator) else {
            return
        }
        let classRef = typeJavaClass(classDeclaration, translator: translator)

        let visibility = classDeclaration.modifiers.visibility.swift(suffix: " ")
        var swift: [String] = []
        swift.append(visibility + "class " + classDeclaration.name + " {")

        swift.append(1, "private static let Java_class = try! JClass(name: \"" + classRef.className + "\")")
        swift.append(1, visibility + "let Java_peer: JObject")
        swift.append("")
        swift.append(1, [
            "init(Java_ptr: JavaObjectPointer) {",
            "    Java_peer = JObject(Java_ptr)",
            "}"
        ])

        if !classDeclaration.members.contains(where: { $0.type == .constructorDeclaration }) {
            swift.append("")
            swift.append(1, [
                visibility + "init() {",
                "    let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, [])",
                "    Java_peer = JObject(ptr)",
                "}",
                "private static let Java_constructor_methodID = Java_class.getMethodID(name: \"<init>\", sig: \"()V\")!"
            ])
        }

        var memberDefinitions: [SwiftDefinition] = []
        for member in classDeclaration.members {
            if let variableDeclaration = member as? KotlinVariableDeclaration {
                addSwiftDefinitions(for: variableDeclaration, to: &memberDefinitions, translator: translator)
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                addSwiftDefinitions(for: functionDeclaration, to: &memberDefinitions, translator: translator)
            }
        }

        let definition = SwiftDefinition(statement: classDeclaration, children: memberDefinitions) { output, indentation, children in
            swift.forEach { output.append(indentation).append($0).append("\n") }
            let childIndentation = indentation.inc()
            children.forEach { output.append("\n").append($0, indentation: childIndentation) }
            output.append(indentation).append("}\n")
        }
        swiftDefinitions.append(definition)
    }

    private func globalsJavaClass(translator: KotlinTranslator) -> JavaClassRef {
        let file = translator.syntaxTree.source.file
        var identifier = file.name
        let ext = file.extension
        if !ext.isEmpty {
            identifier = String(identifier.dropLast(ext.count + 1))
        }
        identifier += "Kt"
        let className: String
        if let packageName = translator.packageName {
            className = packageName.replacing(".", with: "/") + "/" + identifier
        } else {
            className = identifier
        }
        return JavaClassRef(identifier: "Java_" + identifier, className: className)
    }

    private func typeJavaClass(_ classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) -> JavaClassRef {
        let className: String
        if let packageName = translator.packageName {
            className = packageName.replacing(".", with: "/") + "/" + classDeclaration.name
        } else {
            className = classDeclaration.name
        }
        return JavaClassRef(identifier: "Java_class", className: className)
    }
}

private struct JavaClassRef: Hashable, CustomStringConvertible {
    let identifier: String
    let className: String

    var description: String {
        return "private let " + identifier + " = try! JClass(name: \"" + className + "\")"
    }
}
