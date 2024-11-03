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
                if variableDeclaration.attributes.isBridgeToSwift {
                    needsGlobalsJavaClass = update(global: variableDeclaration, swiftDefinitions: &swiftDefinitions, globalsClassRef: globalsClassRef, translator: translator) || needsGlobalsJavaClass
                } else if variableDeclaration.attributes.isBridgeToKotlin {
                    variableDeclaration.messages.append(Message.kotlinBridgeKotlinToKotlin(variableDeclaration, source: translator.syntaxTree.source))
                }
                return .skip
            } else if let functionDeclaration = node as? KotlinFunctionDeclaration, functionDeclaration.role == .global {
                if functionDeclaration.attributes.isBridgeToSwift {
                    needsGlobalsJavaClass = update(global: functionDeclaration, swiftDefinitions: &swiftDefinitions, globalsClassRef: globalsClassRef, translator: translator) || needsGlobalsJavaClass
                } else if functionDeclaration.attributes.isBridgeToKotlin {
                    functionDeclaration.messages.append(Message.kotlinBridgeKotlinToKotlin(functionDeclaration, source: translator.syntaxTree.source))
                }
                return .skip
            } else if let classDeclaration = node as? KotlinClassDeclaration {
                if classDeclaration.attributes.isBridgeToSwift {
                    update(classDeclaration, swiftDefinitions: &swiftDefinitions, translator: translator)
                } else if classDeclaration.attributes.isBridgeToKotlin {
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
                guard importDeclaration.unmappedModulePath.count != 1 || importDeclaration.unmappedModulePath[0] != "SkipBridge" else {
                    continue
                }
                let path = importDeclaration.unmappedModulePath.joined(separator: ".")
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

    private func update(global variableDeclaration: KotlinVariableDeclaration, swiftDefinitions: inout [SwiftDefinition], globalsClassRef: JavaClassRef, translator: KotlinTranslator) -> Bool {
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

    private func update(_ variableDeclaration: KotlinVariableDeclaration, swiftDefinitions: inout [SwiftDefinition], translator: KotlinTranslator) -> Bool {
        guard variableDeclaration.modifiers.visibility != .private && variableDeclaration.modifiers.visibility != .fileprivate && !variableDeclaration.attributes.isBridgeIgnored else {
            return false
        }
        guard let bridgable = variableDeclaration.checkBridgable(translator: translator) else {
            return false
        }
        guard !addConstantDefinition(for: variableDeclaration, type: bridgable.type, to: &swiftDefinitions, translator: translator) else {
            return false
        }

        let sourceCode: [String]
        if variableDeclaration.isStatic {
            sourceCode = swift(for: variableDeclaration, bridgable: bridgable, targetIdentifier: "Java_Companion", classIdentifier: "Java_Companion_class", getMethodIdentifier: "Java_Companion_get_" + variableDeclaration.propertyName + "_methodID", setMethodIdentifier: "Java_Companion_set_" + variableDeclaration.propertyName + "_methodID", translator: translator)
        } else {
            sourceCode = swift(for: variableDeclaration, bridgable: bridgable, targetIdentifier: "Java_peer", classIdentifier: "Java_class", getMethodIdentifier: "Java_get_" + variableDeclaration.propertyName + "_methodID", setMethodIdentifier: "Java_set_" + variableDeclaration.propertyName + "_methodID", translator: translator)
        }
        swiftDefinitions.append(SwiftDefinition(statement: variableDeclaration, swift: sourceCode))
        return true
    }

    private func swift(for variableDeclaration: KotlinVariableDeclaration, bridgable: Bridgable, targetIdentifier: String, classIdentifier: String, getMethodIdentifier: String, setMethodIdentifier: String, translator: KotlinTranslator) -> [String] {
        var swift: [String] = []
        let type = bridgable.type
        let propertyName = variableDeclaration.propertyName
        let preEscapedPropertyName = variableDeclaration.preEscapedPropertyName
        let modifierString = variableDeclaration.modifiers.swift(suffix: " ")
        swift.append("\(modifierString)var \(preEscapedPropertyName ?? propertyName): \(type.description) {")

        // Getter
        let callType = variableDeclaration.role == .global ? "callStatic" : "call"
        let callGet = variableDeclaration.role == .global || variableDeclaration.isStatic ? getMethodIdentifier : "Self." + getMethodIdentifier
        swift.append(1, "get {")
        swift.append(2, "return jniContext {")
        swift.append(3, [
            "let value_java: " + type.java(strategy: bridgable.strategy).description + " = try! \(targetIdentifier).\(callType)(method: \(callGet), args: [])",
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
            let callSet = variableDeclaration.role == .global || variableDeclaration.isStatic ? setMethodIdentifier : "Self." + setMethodIdentifier
            swift.append(1, setVisibility + "set {")
            swift.append(2, "jniContext {")
            swift.append(3, [
                "let value_java = " + type.convertToJava(value: "newValue", strategy: bridgable.strategy) + ".toJavaParameter()",
                "try! \(targetIdentifier).\(callType)(method: \(callSet), args: [value_java])"
            ])
            swift.append(2, "}")
            swift.append(1, "}")
        }
        swift.append("}")

        let capitalizedPropertyName = (propertyName.first?.uppercased() ?? "") + propertyName.dropFirst()
        let declarationType = variableDeclaration.role == .global ? "let " : "static let "
        let callMethodID = variableDeclaration.role == .global ? "getStaticMethodID" : "getMethodID"
        let getMethodID = "private \(declarationType )\(getMethodIdentifier) = \(classIdentifier).\(callMethodID)(name: \"get\(capitalizedPropertyName)\", sig: \"()\(bridgable.qualifiedType.jni())\")!"
        swift.append(getMethodID)
        if hasSetter {
            let setMethodID = "private \(declarationType)\(setMethodIdentifier) = \(classIdentifier).\(callMethodID)(name: \"set\(capitalizedPropertyName)\", sig: \"(\(bridgable.qualifiedType.jni()))V\")!"
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
        let modifierString = variableDeclaration.modifiers.swift(suffix: " ")
        let swift = "\(modifierString)let \(variableDeclaration.propertyName)\(assignment)"
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

    private func update(global functionDeclaration: KotlinFunctionDeclaration, swiftDefinitions: inout [SwiftDefinition], globalsClassRef: JavaClassRef, translator: KotlinTranslator) -> Bool {
        guard let bridgables = functionDeclaration.checkBridgable(translator: translator) else {
            return false
        }

        let swift = swift(for: functionDeclaration, bridgables: bridgables, targetIdentifier: globalsClassRef.identifier, classIdentifier: globalsClassRef.identifier, methodIdentifier: "Java_" + functionDeclaration.name + "_methodID", translator: translator)
        swiftDefinitions.append(SwiftDefinition(statement: functionDeclaration, swift: swift))
        appendCallbackFunction(for: functionDeclaration)
        return true
    }

    private func update(_ functionDeclaration: KotlinFunctionDeclaration, swiftDefinitions: inout [SwiftDefinition], translator: KotlinTranslator) -> Bool {
        guard functionDeclaration.modifiers.visibility != .private && functionDeclaration.modifiers.visibility != .fileprivate && !functionDeclaration.attributes.isBridgeIgnored else {
            return false
        }
        guard let bridgables = functionDeclaration.checkBridgable(translator: translator) else {
            return false
        }

        let sourceCode: [String]
        if functionDeclaration.isStatic {
            sourceCode = swift(for: functionDeclaration, bridgables: bridgables, targetIdentifier: "Java_Companion", classIdentifier: "Java_Companion_class", methodIdentifier: "Java_Companion_" + functionDeclaration.name + "_methodID", translator: translator)
        } else {
            sourceCode = swift(for: functionDeclaration, bridgables: bridgables, targetIdentifier: "Java_peer", classIdentifier: "Java_class", methodIdentifier: "Java_" + functionDeclaration.name + "_methodID", translator: translator)
        }
        swiftDefinitions.append(SwiftDefinition(statement: functionDeclaration, swift: sourceCode))
        appendCallbackFunction(for: functionDeclaration)
        return true
    }

    private func swift(for functionDeclaration: KotlinFunctionDeclaration, bridgables: (parameters: [Bridgable], return: Bridgable), targetIdentifier: String, classIdentifier: String, methodIdentifier: String, translator: KotlinTranslator) -> [String] {
        var swift: [String] = []

        let isAsync = functionDeclaration.apiFlags.options.contains(.async)
        let isThrows = functionDeclaration.apiFlags.throwsType != .none
        var functionType = functionDeclaration.functionType
        if functionDeclaration.type == .constructorDeclaration {
            functionType = functionType.withReturnType(.void)
        }
        let modifierString = functionDeclaration.modifiers.swift(suffix: " ")
        let parameterString = functionDeclaration.parameters.map(\.swift).joined(separator: ", ")
        var optionsString = isAsync ? " async" : ""
        optionsString += isThrows ? " throws" : ""
        let returnString = functionType.returnType == .void ? "" : " -> " + functionType.returnType.description
        swift.append(modifierString + (functionDeclaration.type == .constructorDeclaration ? "init" : "func " + functionDeclaration.name) + "(\(parameterString))\(optionsString)\(returnString) {")

        var returnCallString = functionDeclaration.type == .constructorDeclaration ? "Java_peer = " : ""
        // withCheckedThrowingContinuation requires a 'return' even with void to compile correctly
        if functionType.returnType != .void || (isAsync && isThrows) {
            returnCallString += "return "
        }
        if functionDeclaration.apiFlags.options.contains(.throws) {
            returnCallString += "try "
        }
        var indentation: Indentation = 2
        if isAsync {
            if isThrows {
                swift.append(1, returnCallString + "await withCheckedThrowingContinuation { f_continuation in")
            } else {
                swift.append(1, returnCallString + "await withCheckedContinuation { f_continuation in")
            }
            let callbackType = functionDeclaration.callbackClosureType(java: false)
            if callbackType.parameters.isEmpty {
                swift.append(2, "let f_return_callback: \(callbackType) = {")
                swift.append(3, "f_continuation.resume()")
            } else if !isThrows {
                swift.append(2, "let f_return_callback: \(callbackType) = { f_return in")
                swift.append(3, "f_continuation.resume(returning: f_return)")
            } else {
                if callbackType.parameters.count == 1 {
                    swift.append(2, "let f_return_callback: \(callbackType) = { f_error in")
                } else {
                    swift.append(2, "let f_return_callback: \(callbackType) = { f_return, f_error in")
                }
                swift.append(3, "if let f_error {")
                swift.append(4, "f_continuation.resume(throwing: ThrowableError(throwable: f_error))")
                swift.append(3, "} else {")
                if callbackType.parameters.count == 1 {
                    swift.append(4, "f_continuation.resume()")
                } else if functionDeclaration.returnType.isOptional {
                    swift.append(4, "f_continuation.resume(returning: f_return)")
                } else {
                    swift.append(4, "f_continuation.resume(returning: f_return!)")
                }
                swift.append(3, "}")
            }
            swift.append(2, "}")
            swift.append(2, "jniContext {")
            swift.append(3, "let f_return_callback_java = SwiftClosure\(callbackType.parameters.count).javaObject(for: f_return_callback).toJavaParameter()")
            indentation = indentation.inc()
        } else {
            swift.append(1, returnCallString + "jniContext {")
        }

        var javaParameterNames: [String] = []
        for (index, parameter) in functionDeclaration.parameters.enumerated() {
            let name = parameter.internalLabel + "_java"
            javaParameterNames.append(name)
            let strategy = bridgables.parameters[index].strategy
            swift.append(indentation, "let \(name) = " + parameter.declaredType.convertToJava(value: parameter.internalLabel, strategy: strategy) + ".toJavaParameter()")
        }

        let tryType = isThrows && !isAsync ? "try" : "try!"
        if functionDeclaration.type == .constructorDeclaration {
            swift.append(indentation, "let ptr = \(tryType) Self.Java_class.create(ctor: Self.\(methodIdentifier), args: [" + javaParameterNames.joined(separator: ", ") + "])")
            swift.append(indentation, "return JObject(ptr)")
        } else if isAsync {
            let callType = functionDeclaration.role == .global ? "callStatic" : "call"
            let callMethod = functionDeclaration.role == .global || functionDeclaration.isStatic ? methodIdentifier : "Self." + methodIdentifier
            var argumentsString = javaParameterNames.joined(separator: ", ")
            if !argumentsString.isEmpty {
                argumentsString += ", "
            }
            argumentsString += "f_return_callback_java"
            let call = "\(tryType) \(targetIdentifier).\(callType)(method: \(callMethod), args: [\(argumentsString)])"
            swift.append(indentation, call)
        } else {
            let callType = functionDeclaration.role == .global ? "callStatic" : "call"
            let callMethod = functionDeclaration.role == .global || functionDeclaration.isStatic ? methodIdentifier : "Self." + methodIdentifier
            let call = "\(tryType) \(targetIdentifier).\(callType)(method: \(callMethod), args: [" + javaParameterNames.joined(separator: ", ") + "])"
            if isThrows {
                swift.append(indentation, "do {")
                indentation = indentation.inc()
            }
            if functionType.returnType == .void {
                swift.append(indentation, call)
            } else {
                swift.append(indentation, "let f_return_java: " + functionType.returnType.java(strategy: bridgables.return.strategy).description + " = \(call)")
                swift.append(indentation, "return " + functionType.returnType.convertFromJava(value: "f_return_java", strategy: bridgables.return.strategy))
            }
            if isThrows {
                indentation = indentation.dec()
                swift.append(indentation, "} catch let error as ThrowableError {")
                swift.append(indentation.inc(), "throw error")
                swift.append(indentation, "} catch {")
                swift.append(indentation.inc(), "fatalError(String(describing: error))")
                swift.append(indentation, "}")
            }
        }
        while indentation.level > 0 {
            indentation = indentation.dec()
            swift.append(indentation, "}")
        }

        let declarationType = functionDeclaration.role == .global ? "let " : "static let "
        let getType = functionDeclaration.role == .global ? "getStaticMethodID" : "getMethodID"
        var qualifiedParameters = bridgables.parameters.map { TypeSignature.Parameter(type: $0.qualifiedType) }
        let functionName: String
        let qualifiedReturnType: TypeSignature
        if functionDeclaration.type == .constructorDeclaration {
            functionName = "<init>"
            qualifiedReturnType = .void
        } else if isAsync {
            functionName = "callback_" + functionDeclaration.name
            qualifiedParameters.append(TypeSignature.Parameter(type: functionDeclaration.callbackClosureType(java: false)))
            qualifiedReturnType = .void
        } else {
            functionName = functionDeclaration.name
            qualifiedReturnType = bridgables.return.qualifiedType
        }
        let qualifiedType: TypeSignature = .function(qualifiedParameters, qualifiedReturnType, APIFlags(), nil)
        let methodID = "private \(declarationType)\(methodIdentifier) = \(classIdentifier).\(getType)(name: \"\(functionName)\", sig: \"" + qualifiedType.jni(isFunctionDeclaration: true) + "\")!"
        swift.append(methodID)
        return swift
    }

    private func appendCallbackFunction(for functionDeclaration: KotlinFunctionDeclaration) {
        guard functionDeclaration.apiFlags.options.contains(.async) else {
            return
        }
        let callbackFunction = KotlinFunctionDeclaration(name: "callback_" + functionDeclaration.name)
        callbackFunction.parameters = functionDeclaration.parameters.map { Parameter<KotlinExpression>(externalLabel: $0.externalLabel, internalLabel: $0.internalLabel, declaredType: $0.declaredType, isInOut: $0.isInOut, isVariadic: $0.isVariadic, attributes: $0.attributes, defaultValue: nil, defaultValueSwift: nil) }
        let callbackType = functionDeclaration.callbackClosureType(java: true)
        callbackFunction.parameters.append(Parameter<KotlinExpression>(externalLabel: "f_return_callback", declaredType: callbackType))
        callbackFunction.returnType = .void
        callbackFunction.modifiers = functionDeclaration.modifiers
        callbackFunction.generics = functionDeclaration.generics
        callbackFunction.role = functionDeclaration.role
        callbackFunction.disambiguatingParameterCount = functionDeclaration.disambiguatingParameterCount
        callbackFunction.isGenerated = true

        let invocationSourceCode = invocationSourceCode(for: functionDeclaration)
        var taskSourceCode: [String] = []
        taskSourceCode.append("Task {")
        if functionDeclaration.apiFlags.throwsType == .none {
            if callbackType.parameters.isEmpty {
                taskSourceCode.append(1, invocationSourceCode)
                taskSourceCode.append(1, "f_return_callback()")
            } else {
                taskSourceCode.append(1, "f_return_callback(\(invocationSourceCode))")
            }
        } else {
            taskSourceCode.append(1, "try {")
            if callbackType.parameters.count == 1 {
                taskSourceCode.append(2, invocationSourceCode)
                taskSourceCode.append(2, "f_return_callback(null)")
            } else {
                taskSourceCode.append(2, "f_return_callback(\(invocationSourceCode), null)")
            }
            taskSourceCode.append(1, "} catch(t: Throwable) {")
            if callbackType.parameters.count == 1 {
                taskSourceCode.append(2, "f_return_callback(t)")
            } else {
                taskSourceCode.append(2, "f_return_callback(null, t)")
            }
            taskSourceCode.append(1, "}")
        }
        taskSourceCode.append("}")
        callbackFunction.body = KotlinCodeBlock(statements: taskSourceCode.map { KotlinRawStatement(sourceCode: $0) })
        (functionDeclaration.parent as? KotlinStatement)?.insert(statements: [callbackFunction], after: functionDeclaration)
    }

    private func invocationSourceCode(for functionDeclaration: KotlinFunctionDeclaration) -> String {
        let argumentsString = functionDeclaration.parameters.map {
            let label = $0.externalLabel ?? $0.internalLabel
            return label + " = " + label
        }.joined(separator: ", ")
        return functionDeclaration.name + "(\(argumentsString))"
    }

    private func update(_ classDeclaration: KotlinClassDeclaration, swiftDefinitions: inout [SwiftDefinition], translator: KotlinTranslator) {
        guard classDeclaration.checkBridgable(translator: translator) else {
            return
        }
        let classRef = JavaClassRef(for: classDeclaration, translator: translator)

        let visibility = classDeclaration.modifiers.visibility.swift(suffix: " ")
        var swift: [String] = []
        swift.append(visibility + "class \(classDeclaration.name): BridgedFromKotlin {")

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
        var hasBridgedStaticMembers = false
        for member in classDeclaration.members {
            if let variableDeclaration = member as? KotlinVariableDeclaration {
                if update(variableDeclaration, swiftDefinitions: &memberDefinitions, translator: translator), variableDeclaration.isStatic {
                    hasBridgedStaticMembers = true
                }
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                if update(functionDeclaration, swiftDefinitions: &memberDefinitions, translator: translator), functionDeclaration.isStatic {
                    hasBridgedStaticMembers = true
                }
            }
        }

        if hasBridgedStaticMembers {
            swift.append(1, "private static let Java_Companion_class = try! JClass(name: \"\(classRef.className)$Companion\")")
            swift.append(1, "private static let Java_Companion = JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: \"Companion\", sig: \"L\(classRef.className)$Companion;\")!))")
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
