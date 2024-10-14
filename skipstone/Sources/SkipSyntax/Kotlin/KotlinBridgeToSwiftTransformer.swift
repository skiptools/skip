import Foundation

/// Generate transpiled Swift (Kotlin) to compiled Swift bridging code.
final class KotlinBridgeToSwiftTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        guard !syntaxTree.isBridgeFile, translator.codebaseInfo != nil, let outputFile = syntaxTree.source.file.bridgeOutputFile else {
            return []
        }
        let globalsClassRef = JavaClassRef(forFile: translator)
        var swiftDefinitions: [SwiftDefinition] = []
        var needsGlobalsJavaClass = false
        syntaxTree.root.visit { node in
            if let variableDeclaration = node as? KotlinVariableDeclaration, variableDeclaration.role == .global {
                if variableDeclaration.attributes.contains(directive: Directive.bridgeToSwift) {
                    needsGlobalsJavaClass = addSwiftDefinitions(forGlobal: variableDeclaration, to: &swiftDefinitions, globalsClassRef: globalsClassRef, translator: translator) || needsGlobalsJavaClass
                } else if variableDeclaration.attributes.contains(directive: Directive.bridgeToKotlin) {
                    variableDeclaration.messages.append(Message.kotlinBridgeKotlinToKotlin(variableDeclaration, source: translator.syntaxTree.source))
                }
                return .skip
            } else if let functionDeclaration = node as? KotlinFunctionDeclaration, functionDeclaration.role == .global {
                if functionDeclaration.attributes.contains(directive: Directive.bridgeToSwift) {
                    needsGlobalsJavaClass = addSwiftDefinitions(forGlobal: functionDeclaration, to: &swiftDefinitions, globalsClassRef: globalsClassRef, translator: translator) || needsGlobalsJavaClass
                } else if functionDeclaration.attributes.contains(directive: Directive.bridgeToKotlin) {
                    functionDeclaration.messages.append(Message.kotlinBridgeKotlinToKotlin(functionDeclaration, source: translator.syntaxTree.source))
                }
                return .skip
            } else if let classDeclaration = node as? KotlinClassDeclaration {
                if classDeclaration.attributes.contains(directive: Directive.bridgeToSwift) {
                    addSwiftDefinitions(for: classDeclaration, to: &swiftDefinitions, translator: translator)
                } else if classDeclaration.attributes.contains(directive: Directive.bridgeToKotlin) {
                    classDeclaration.messages.append(Message.kotlinBridgeKotlinToKotlin(classDeclaration, source: translator.syntaxTree.source))
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
        let outputNode = SwiftDefinition { output, indentation, _ in
            output.append("import SkipBridge\n\n")
            for importDeclaration in importDeclarations {
                let path = importDeclaration.modulePath.joined(separator: ".")
                output.append(indentation).append("import ").append(path).append("\n")
            }
            if needsGlobalsJavaClass {
                output.append(indentation).append(globalsClassRef.declaration).append("\n")
            }
            swiftDefinitions.forEach { output.append($0, indentation: indentation) }
        }
        let output = KotlinTransformerOutput(file: outputFile, node: outputNode, type: .bridgeToSwift)
        return [output]
    }

    private func addSwiftDefinitions(forGlobal variableDeclaration: KotlinVariableDeclaration, to swiftDefinitions: inout [SwiftDefinition], globalsClassRef: JavaClassRef, translator: KotlinTranslator) -> Bool {
        guard let bridgable = variableDeclaration.checkBridgable(translator: translator) else {
            return false
        }
        guard !addConstantDefinition(for: variableDeclaration, type: bridgable.type, to: &swiftDefinitions, translator: translator) else {
            return false
        }
        let swift = swift(for: variableDeclaration, bridgable: bridgable, targetIdentifier: globalsClassRef.identifier, classIdentifier: globalsClassRef.identifier, getMethodIdentifier: "Java_get_" + variableDeclaration.propertyName + "_methodID", setMethodIdentifier: "Java_set_" + variableDeclaration.propertyName + "_methodID", translator: translator)
        swiftDefinitions.append(SwiftDefinition(statement: variableDeclaration, swift: swift))
        return true
    }

    private func addSwiftDefinitions(for variableDeclaration: KotlinVariableDeclaration, to swiftDefinitions: inout [SwiftDefinition], translator: KotlinTranslator) {
        guard variableDeclaration.modifiers.visibility != .private && variableDeclaration.modifiers.visibility != .fileprivate && !variableDeclaration.attributes.contains(directive: Directive.nobridge) else {
            return
        }
        guard let bridgable = variableDeclaration.checkBridgable(translator: translator) else {
            return
        }
        guard !addConstantDefinition(for: variableDeclaration, type: bridgable.type, to: &swiftDefinitions, translator: translator) else {
            return
        }

        let swift = swift(for: variableDeclaration, bridgable: bridgable, targetIdentifier: "Java_peer", classIdentifier: "Java_class", getMethodIdentifier: "Java_get_" + variableDeclaration.propertyName + "_methodID", setMethodIdentifier: "Java_set_" + variableDeclaration.propertyName + "_methodID", translator: translator)
        swiftDefinitions.append(SwiftDefinition(statement: variableDeclaration, swift: swift))
    }

    private func swift(for variableDeclaration: KotlinVariableDeclaration, bridgable: Bridgable, targetIdentifier: String, classIdentifier: String, getMethodIdentifier: String, setMethodIdentifier: String, translator: KotlinTranslator) -> [String] {
        var swift: [String] = []
        let type = bridgable.type
        let propertyName = variableDeclaration.propertyName
        let preEscapedPropertyName = variableDeclaration.preEscapedPropertyName
        let visibility = variableDeclaration.modifiers.visibility.swift(suffix: " ")
        swift.append(visibility + "var " + (preEscapedPropertyName ?? propertyName) + ": " + type.description + " {")

        // Getter
        let callType = variableDeclaration.role == .global ? "callStatic" : "call"
        let callGet = variableDeclaration.role == .global ? getMethodIdentifier : "Self." + getMethodIdentifier
        swift.append(1, "get {")
        swift.append(2, "return jniContext {")
        swift.append(3, [
            "let value_java: " + type.java(strategy: bridgable.strategy).description + " = try! " + targetIdentifier + "." + callType + "(method: " + callGet  + ", args: [])",
            "return " + type.convertFromJava(value: "value_java", strategy: bridgable.strategy)
        ])
        swift.append(2, "}")
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
            swift.append(2, "jniContext {")
            swift.append(3, [
                "let value_java = " + type.convertToJava(value: "newValue", strategy: bridgable.strategy) + ".toJavaParameter()",
                "try! " + targetIdentifier + "." + callType + "(method: " + callSet + ", args: [value_java])"
            ])
            swift.append(2, "}")
            swift.append(1, "}")
        }
        swift.append("}")

        let capitalizedPropertyName = (propertyName.first?.uppercased() ?? "") + propertyName.dropFirst()
        let declarationType = variableDeclaration.role == .global ? "let " : "static let "
        let callMethodID = variableDeclaration.role == .global ? "getStaticMethodID" : "getMethodID"
        let getMethodID = "private " + declarationType + getMethodIdentifier + " = " + classIdentifier + "." + callMethodID + "(name: \"get" + capitalizedPropertyName + "\", sig: \"()" + bridgable.qualifiedType.jni() + "\")!"
        swift.append(getMethodID)
        if hasSetter {
            let setMethodID = "private " + declarationType + setMethodIdentifier + " = " + classIdentifier + "." + callMethodID + "(name: \"set" + capitalizedPropertyName + "\", sig: \"(" + bridgable.qualifiedType.jni() + ")V\")!"
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

    private func addSwiftDefinitions(forGlobal functionDeclaration: KotlinFunctionDeclaration, to swiftDefinitions: inout [SwiftDefinition], globalsClassRef: JavaClassRef, translator: KotlinTranslator) -> Bool {
        guard let bridgables = functionDeclaration.checkBridgable(translator: translator) else {
            return false
        }

        let swift = swift(for: functionDeclaration, bridgables: bridgables, targetIdentifier: globalsClassRef.identifier, classIdentifier: globalsClassRef.identifier, methodIdentifier: "Java_" + functionDeclaration.name + "_methodID", translator: translator)
        swiftDefinitions.append(SwiftDefinition(statement: functionDeclaration, swift: swift))
        return true
    }

    private func addSwiftDefinitions(for functionDeclaration: KotlinFunctionDeclaration, to swiftDefinitions: inout [SwiftDefinition], translator: KotlinTranslator) {
        guard functionDeclaration.modifiers.visibility != .private && functionDeclaration.modifiers.visibility != .fileprivate && !functionDeclaration.attributes.contains(directive: Directive.nobridge) else {
            return
        }
        guard let bridgables = functionDeclaration.checkBridgable(translator: translator) else {
            return
        }

        let swift = swift(for: functionDeclaration, bridgables: bridgables, targetIdentifier: "Java_peer", classIdentifier: "Java_class", methodIdentifier: "Java_" + functionDeclaration.name + "_methodID", translator: translator)
        swiftDefinitions.append(SwiftDefinition(statement: functionDeclaration, swift: swift))
    }

    private func swift(for functionDeclaration: KotlinFunctionDeclaration, bridgables: (parameters: [Bridgable], return: Bridgable), targetIdentifier: String, classIdentifier: String, methodIdentifier: String, translator: KotlinTranslator) -> [String] {
        var swift: [String] = []

        var functionType = functionDeclaration.functionType
        if functionDeclaration.type == .constructorDeclaration {
            functionType = functionType.withReturnType(.void)
        }
        let visibility = functionDeclaration.modifiers.visibility.swift(suffix: " ")
        let parameterString = functionDeclaration.parameters.map(\.swift).joined(separator: ", ")
        let returnString = functionType.returnType == .void ? "" : " -> " + functionType.returnType.description
        swift.append(visibility + (functionDeclaration.type == .constructorDeclaration ? "init" : "func " + functionDeclaration.name) + "(" + parameterString + ")" + returnString + " {")

        var jniReturnType = functionDeclaration.type == .constructorDeclaration ? "Java_peer = " : ""
        if functionType.returnType != .void {
            jniReturnType += "return "
        }
        if functionDeclaration.apiFlags.options.contains(.throws) {
            jniReturnType += "try "
        }
        swift.append(1, jniReturnType + "jniContext {")

        var javaParameterNames: [String] = []
        for (index, parameter) in functionDeclaration.parameters.enumerated() {
            let name = parameter.internalLabel + "_java"
            javaParameterNames.append(name)
            let strategy = bridgables.parameters[index].strategy
            swift.append(2, "let " + name + " = " + parameter.declaredType.convertToJava(value: parameter.internalLabel, strategy: strategy) + ".toJavaParameter()")
        }

        if functionDeclaration.type == .constructorDeclaration {
            swift.append(2, "let ptr = try! Self.Java_class.create(ctor: Self." + methodIdentifier + ", args: [" + javaParameterNames.joined(separator: ", ") + "])")
            swift.append(2, "return JObject(ptr)")
        } else {
            let callType = functionDeclaration.role == .global ? "callStatic" : "call"
            let callMethod = functionDeclaration.role == .global ? methodIdentifier : "Self." + methodIdentifier
            let call = "try! " + targetIdentifier + "." + callType + "(method: " + callMethod + ", args: [" + javaParameterNames.joined(separator: ", ") + "])"
            if functionType.returnType == .void {
                swift.append(1, call)
            } else {
                swift.append(2, "let f_return_java: " + functionType.returnType.java(strategy: bridgables.return.strategy).description + " = " + call)
                swift.append(2, "return " + functionType.returnType.convertFromJava(value: "f_return_java", strategy: bridgables.return.strategy))
            }
        }
        swift.append(1, "}")
        swift.append("}")

        let declarationType = functionDeclaration.role == .global ? "let " : "static let "
        let getType = functionDeclaration.role == .global ? "getStaticMethodID" : "getMethodID"
        let qualifiedParameters = bridgables.parameters.map { TypeSignature.Parameter(type: $0.qualifiedType) }
        let functionName: String
        let qualifiedReturnType: TypeSignature
        if functionDeclaration.type == .constructorDeclaration {
            functionName = "<init>"
            qualifiedReturnType = .void
        } else {
            functionName = functionDeclaration.name
            qualifiedReturnType = bridgables.return.qualifiedType
        }
        let qualifiedType: TypeSignature = .function(qualifiedParameters, qualifiedReturnType, APIFlags(), nil)
        let methodID = "private " + declarationType + methodIdentifier + " = " + classIdentifier + "." + getType + "(name: \"" + functionName + "\", sig: \"" + qualifiedType.jni(isFunctionDeclaration: true) + "\")!"
        swift.append(methodID)
        return swift
    }

    private func addSwiftDefinitions(for classDeclaration: KotlinClassDeclaration, to swiftDefinitions: inout [SwiftDefinition], translator: KotlinTranslator) {
        guard classDeclaration.checkBridgable(translator: translator) else {
            return
        }
        let classRef = JavaClassRef(for: classDeclaration, translator: translator)

        let visibility = classDeclaration.modifiers.visibility.swift(suffix: " ")
        var swift: [String] = []
        swift.append(visibility + "class " + classDeclaration.name + ": BridgedFromKotlin {")

        swift.append(1, classRef.declaration)
        swift.append(1, visibility + "let Java_peer: JObject")
        swift.append(1, "required init(Java_ptr: JavaObjectPointer) {")
        swift.append(2, "Java_peer = JObject(Java_ptr)")
        swift.append(1, "}")

        if !classDeclaration.members.contains(where: { $0.type == .constructorDeclaration }) {
            swift.append(1, visibility + "init() {")
            swift.append(2, "Java_peer = jniContext {")
            swift.append(3, [
                "let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, args: [])",
                "return JObject(ptr)"
            ])
            swift.append(2, "}")
            swift.append(1, [
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

        swift.append(1, visibility + "static func fromJavaObject(_ obj: JavaObjectPointer?) -> Self {")
        swift.append(2, "return .init(Java_ptr: obj!)")
        swift.append(1, "}")
        swift.append(1, visibility + "func toJavaObject() -> JavaObjectPointer? {")
        swift.append(2, "return Java_peer.safePointer()")
        swift.append(1, "}")

        let definition = SwiftDefinition(statement: classDeclaration, children: memberDefinitions) { output, indentation, children in
            swift.forEach { output.append(indentation).append($0).append("\n") }
            let childIndentation = indentation.inc()
            children.forEach { output.append("\n").append($0, indentation: childIndentation) }
            output.append(indentation).append("}\n")
        }
        swiftDefinitions.append(definition)
    }
}
