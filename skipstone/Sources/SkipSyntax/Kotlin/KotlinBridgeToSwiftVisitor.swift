import Foundation

/// Generate transpiled Swift (Kotlin) to compiled Swift bridging code.
final class KotlinBridgeToSwiftVisitor {
    private let syntaxTree: KotlinSyntaxTree
    private let options: KotlinBridgeOptions
    private let translator: KotlinTranslator
    private let codebaseInfo: CodebaseInfo.Context
    private let outputFile: Source.FilePath
    private var swiftDefinitions: [SwiftDefinition] = []

    init?(for syntaxTree: KotlinSyntaxTree, options: KotlinBridgeOptions, translator: KotlinTranslator) {
        guard !syntaxTree.isBridgeFile, let codebaseInfo = translator.codebaseInfo, let outputFile = syntaxTree.source.file.bridgeOutputFile else {
            return nil
        }
        self.syntaxTree = syntaxTree
        self.options = options
        self.translator = translator
        self.codebaseInfo = codebaseInfo
        self.outputFile = outputFile
    }

    func visit() -> [KotlinTransformerOutput] {
        let globalsClassRef = JavaClassRef(forFileName: translator.syntaxTree.source.file.name, packageName: translator.packageName)
        var swiftDefinitions: [SwiftDefinition] = []
        var needsGlobalsJavaClass = false
        var globalFunctionCount = 0
        syntaxTree.root.visit { node in
            if let variableDeclaration = node as? KotlinVariableDeclaration, variableDeclaration.role == .global {
                if variableDeclaration.modifiers.visibility >= .public, !variableDeclaration.attributes.isBridgeIgnored {
                    needsGlobalsJavaClass = update(global: variableDeclaration, swiftDefinitions: &swiftDefinitions, globalsClassRef: globalsClassRef) || needsGlobalsJavaClass
                    checkIfNotSkipBridge(variableDeclaration)
                }
                return .skip
            } else if let functionDeclaration = node as? KotlinFunctionDeclaration, functionDeclaration.role == .global {
                if functionDeclaration.modifiers.visibility >= .public, !functionDeclaration.attributes.isBridgeIgnored {
                    if update(global: functionDeclaration, uniquifier: globalFunctionCount, swiftDefinitions: &swiftDefinitions, globalsClassRef: globalsClassRef) {
                        needsGlobalsJavaClass = true
                        globalFunctionCount += 1
                    }
                    checkIfNotSkipBridge(functionDeclaration)
                }
                return .skip
            } else if let classDeclaration = node as? KotlinClassDeclaration {
                if classDeclaration.modifiers.visibility >= .public, !classDeclaration.attributes.isBridgeIgnored {
                    update(classDeclaration, swiftDefinitions: &swiftDefinitions)
                    checkIfNotSkipBridge(classDeclaration)
                }
                return .recurse(nil)
            } else if let interfaceDeclaration = node as? KotlinInterfaceDeclaration {
                if interfaceDeclaration.modifiers.visibility >= .public, !interfaceDeclaration.attributes.isBridgeIgnored {
                    update(interfaceDeclaration, swiftDefinitions: &swiftDefinitions)
                    checkIfNotSkipBridge(interfaceDeclaration)
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

    private func checkIfNotSkipBridge(_ statement: KotlinStatement) {
        guard !statement.isInIfNotSkipBridgeBlock else {
            return
        }
        statement.messages.append(.kotlinBridgeMissingIfNotSkipBridge(statement, source: syntaxTree.source))
    }

    @discardableResult private func update(member enumCaseDeclaration: KotlinEnumCaseDeclaration, swiftDefinitions: inout [SwiftDefinition]) -> Bool {
        let name = enumCaseDeclaration.preEscapedName ?? enumCaseDeclaration.name
        var swift = "case `\(name)`"
        if let value = enumCaseDeclaration.rawValueSwift {
            swift += " = " + value
        }
        swiftDefinitions.append(SwiftDefinition(statement: enumCaseDeclaration, swift: [swift]))
        return true
    }

    private func update(global variableDeclaration: KotlinVariableDeclaration, swiftDefinitions: inout [SwiftDefinition], globalsClassRef: JavaClassRef) -> Bool {
        guard let bridgable = variableDeclaration.checkBridgable(options: options, translator: translator) else {
            return false
        }
        guard !addConstantDefinition(for: variableDeclaration, type: bridgable.type, modifiers: variableDeclaration.modifiers, to: &swiftDefinitions) else {
            return false
        }
        let propertyName = variableDeclaration.preEscapedPropertyName ?? variableDeclaration.propertyName
        let swift = Self.swift(forVariableWithName: propertyName, bridgable: bridgable, options: options, modifiers: variableDeclaration.modifiers, attributes: variableDeclaration.attributes, apiFlags: variableDeclaration.apiFlags, targetIdentifier: globalsClassRef.identifier, classIdentifier: globalsClassRef.identifier, getMethodIdentifier: "Java_get_" + variableDeclaration.propertyName + "_methodID", setMethodIdentifier: "Java_set_" + variableDeclaration.propertyName + "_methodID")
        swiftDefinitions.append(SwiftDefinition(statement: variableDeclaration, swift: swift))
        return true
    }

    @discardableResult private func update(member variableDeclaration: KotlinVariableDeclaration, info: CodebaseInfo.VariableInfo?, swiftDefinitions: inout [SwiftDefinition]) -> Bool {
        guard let bridgable = variableDeclaration.checkBridgable(options: options, translator: translator) else {
            return false
        }
        let modifiers = info?.modifiers ?? variableDeclaration.modifiers
        guard !addConstantDefinition(for: variableDeclaration, type: bridgable.type, modifiers: modifiers, to: &swiftDefinitions) else {
            return false
        }
        let inType: StatementType = variableDeclaration.parent is KotlinInterfaceDeclaration ? .protocolDeclaration : (variableDeclaration.parent as? KotlinClassDeclaration)?.declarationType ?? .classDeclaration
        let propertyName = info?.name ?? variableDeclaration.preEscapedPropertyName ?? variableDeclaration.propertyName
        let attributes = info?.attributes ?? variableDeclaration.attributes
        let apiFlags = info?.apiFlags ?? variableDeclaration.apiFlags
        let swift = Self.swift(forMemberVariableWithName: propertyName, inType: inType, bridgable: bridgable, options: options, modifiers: modifiers, attributes: attributes, apiFlags: apiFlags)
        swiftDefinitions.append(SwiftDefinition(statement: variableDeclaration, swift: swift))
        return true
    }

    private static func swift(forMemberVariableWithName propertyName: String, inType: StatementType, bridgable: Bridgable, options: KotlinBridgeOptions, modifiers: Modifiers, attributes: Attributes, apiFlags: APIFlags) -> [String] {
        if modifiers.isStatic {
            return swift(forVariableWithName: propertyName, inType: inType, bridgable: bridgable, options: options, modifiers: modifiers, attributes: attributes, apiFlags: apiFlags, targetIdentifier: "Java_Companion", classIdentifier: "Java_Companion_class", getMethodIdentifier: "Java_Companion_get_" + propertyName + "_methodID", setMethodIdentifier: "Java_Companion_set_" + propertyName + "_methodID")
        } else {
            return swift(forVariableWithName: propertyName, inType: inType, bridgable: bridgable, options: options, modifiers: modifiers, attributes: attributes, apiFlags: apiFlags, targetIdentifier: "Java_peer", classIdentifier: "Java_class", getMethodIdentifier: "Java_get_" + propertyName + "_methodID", setMethodIdentifier: "Java_set_" + propertyName + "_methodID")
        }
    }

    private static func swift(forVariableWithName propertyName: String, inType: StatementType? = nil, bridgable: Bridgable, options: KotlinBridgeOptions, modifiers: Modifiers, attributes: Attributes, apiFlags: APIFlags, targetIdentifier: String, classIdentifier: String, getMethodIdentifier: String, setMethodIdentifier: String) -> [String] {
        var swift: [String] = []
        let preEscapedPropertyName = propertyName
        let propertyName = propertyName.fixingKeyword(in: KotlinIdentifier.hardKeywords)

        var modifiers = modifiers
        if inType == .protocolDeclaration {
            modifiers.visibility = .default
        }
        let modifierString = modifiers.swift(suffix: " ")
        let hasSetter = apiFlags.options.contains(.writeable) && modifiers.setVisibility != .private && modifiers.setVisibility != .fileprivate
        var declarationSuffix = " {"
        if inType == .protocolDeclaration {
            declarationSuffix += " get"
            if hasSetter {
                declarationSuffix += " set"
            }
            declarationSuffix += " }"
        }
        swift.append("\(modifierString)var \(preEscapedPropertyName): \(bridgable.type.description)\(declarationSuffix)")
        guard inType != .protocolDeclaration else {
            return swift
        }

        // Getter
        let callType = inType == nil ? "callStatic" : "call"
        let callGet = inType == nil || modifiers.isStatic ? getMethodIdentifier : "Self." + getMethodIdentifier
        swift.append(1, "get {")
        swift.append(2, "return jniContext {")
        swift.append(3, [
            "let value_java: " + bridgable.type.java(strategy: bridgable.strategy, options: options).description + " = try! \(targetIdentifier).\(callType)(method: \(callGet), options: \(options.jconvertibleOptions), args: [])",
            "return " + bridgable.type.convertFromJava(value: "value_java", strategy: bridgable.strategy, options: options)
        ])
        swift.append(2, "}")
        swift.append(1, "}")

        // Setter
        if hasSetter {
            let setVisibility: String
            if modifiers.setVisibility < modifiers.visibility {
                setVisibility = modifiers.setVisibility.swift(suffix: " ")
            } else {
                setVisibility = ""
            }
            let callSet = inType == nil || modifiers.isStatic ? setMethodIdentifier : "Self." + setMethodIdentifier
            swift.append(1, setVisibility + "set {")
            swift.append(2, "jniContext {")
            if inType == .structDeclaration && !modifiers.isStatic {
                swift.append(3, swiftToCopyJavaPeer(options: options))
            }
            swift.append(3, [
                "let value_java = " + bridgable.type.convertToJava(value: "newValue", strategy: bridgable.strategy, options: options) + ".toJavaParameter(options: \(options.jconvertibleOptions))",
                "try! \(targetIdentifier).\(callType)(method: \(callSet), options: \(options.jconvertibleOptions), args: [value_java])"
            ])
            swift.append(2, "}")
            swift.append(1, "}")
        }
        swift.append("}")

        let capitalizedPropertyName = (propertyName.first?.uppercased() ?? "") + propertyName.dropFirst()
        let declarationType = inType == nil ? "let " : "static let "
        let callMethodID = inType == nil ? "getStaticMethodID" : "getMethodID"
        let getMethodID = "private \(declarationType )\(getMethodIdentifier) = \(classIdentifier).\(callMethodID)(name: \"get\(capitalizedPropertyName)\", sig: \"()\(bridgable.kotlinType.jni(options: options))\")!"
        swift.append(getMethodID)
        if hasSetter {
            let setMethodID = "private \(declarationType)\(setMethodIdentifier) = \(classIdentifier).\(callMethodID)(name: \"set\(capitalizedPropertyName)\", sig: \"(\(bridgable.kotlinType.jni(options: options)))V\")!"
            swift.append(setMethodID)
        }
        return swift
    }

    private static func swiftToCopyJavaPeer(options: KotlinBridgeOptions) -> String {
        return "Java_peer = try! JObject(Java_peer.call(method: Self.Java_scopy_methodID, options: \(options.jconvertibleOptions), args: []))"
    }

    private func addConstantDefinition(for variableDeclaration: KotlinVariableDeclaration, type: TypeSignature, modifiers: Modifiers, to swiftDefinitions: inout [SwiftDefinition]) -> Bool {
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
        let propertyName = variableDeclaration.preEscapedPropertyName ?? variableDeclaration.propertyName
        let modifierString = modifiers.swift(suffix: " ")
        let swift = "\(modifierString)let \(propertyName)\(assignment)"
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

    private func update(global functionDeclaration: KotlinFunctionDeclaration, uniquifier: Int, swiftDefinitions: inout [SwiftDefinition], globalsClassRef: JavaClassRef) -> Bool {
        guard let bridgable = functionDeclaration.checkBridgable(options: options, translator: translator) else {
            return false
        }
        let name = functionDeclaration.preEscapedName ?? functionDeclaration.name
        let type = functionDeclaration.preEscapedFunctionType
        let modifiers = functionDeclaration.modifiers
        let parameterValues = functionDeclaration.parameters.map(\.defaultValueSwift)
        let swift = Self.swift(forFunctionWithName: name, type: type, parameterValues: parameterValues, disambiguatingParameterCount: functionDeclaration.disambiguatingParameterCount, bridgable: bridgable, options: options, modifiers: modifiers, apiFlags: functionDeclaration.apiFlags, targetIdentifier: globalsClassRef.identifier, classIdentifier: globalsClassRef.identifier, methodIdentifier: "Java_\(functionDeclaration.name)_\(uniquifier)_methodID")
        swiftDefinitions.append(SwiftDefinition(statement: functionDeclaration, swift: swift))
        appendCallbackFunction(for: functionDeclaration, bridgable: bridgable, modifiers: functionDeclaration.modifiers)
        return true
    }

    @discardableResult private func update(member functionDeclaration: KotlinFunctionDeclaration, info: CodebaseInfo.FunctionInfo?, uniquifier: Int, swiftDefinitions: inout [SwiftDefinition]) -> Bool {
        guard var bridgable = functionDeclaration.checkBridgable(options: options, translator: translator) else {
            return false
        }
        let inType: StatementType = functionDeclaration.parent is KotlinInterfaceDeclaration ? .protocolDeclaration : (functionDeclaration.parent as? KotlinClassDeclaration)?.declarationType ?? .classDeclaration
        let name = info?.name ?? functionDeclaration.preEscapedName ?? functionDeclaration.name
        let isConstructor = info != nil ? info?.declarationType == .initDeclaration : functionDeclaration.type == .constructorDeclaration
        let isFactory = isConstructor && functionDeclaration.type != .constructorDeclaration
        let type = info?.signature ?? functionDeclaration.preEscapedFunctionType
        let modifiers = info?.modifiers ?? functionDeclaration.modifiers
        let apiFlags = info?.apiFlags ?? functionDeclaration.apiFlags
        let parameterValues = functionDeclaration.parameters.map(\.defaultValueSwift)
        let swift = Self.swift(forMemberFunctionWithName: name, type: type, parameterValues: parameterValues, uniquifier: uniquifier, disambiguatingParameterCount: functionDeclaration.disambiguatingParameterCount, isConstructor: isConstructor, isFactory: isFactory, inType: inType, bridgable: bridgable, options: options, modifiers: modifiers, apiFlags: apiFlags)
        swiftDefinitions.append(SwiftDefinition(statement: functionDeclaration, swift: swift))
        appendCallbackFunction(for: functionDeclaration, bridgable: bridgable, modifiers: modifiers)
        return true
    }

    private static func swift(forMemberFunctionWithName name: String, type: TypeSignature, parameterValues: [String?]?, uniquifier: Int, disambiguatingParameterCount: Int, isConstructor: Bool, isFactory: Bool, inType: StatementType, bridgable: FunctionBridgable, options: KotlinBridgeOptions, modifiers: Modifiers, apiFlags: APIFlags) -> [String] {
        if modifiers.isStatic || isFactory {
            return swift(forFunctionWithName: name, type: type, parameterValues: parameterValues, disambiguatingParameterCount: disambiguatingParameterCount, isConstructor: isConstructor, isFactory: isFactory, inType: inType, bridgable: bridgable, options: options, modifiers: modifiers, apiFlags: apiFlags, targetIdentifier: "Java_Companion", classIdentifier: "Java_Companion_class", methodIdentifier: "Java_Companion_\(name)_\(uniquifier)_methodID")
        } else {
            return swift(forFunctionWithName: name, type: type, parameterValues: parameterValues, disambiguatingParameterCount: disambiguatingParameterCount, isConstructor: isConstructor, isFactory: isFactory, inType: inType, bridgable: bridgable, options: options, modifiers: modifiers, apiFlags: apiFlags, targetIdentifier: "Java_peer", classIdentifier: "Java_class", methodIdentifier: "Java_\(name)_\(uniquifier)_methodID")
        }
    }

    private static func swift(forFunctionWithName name: String, type: TypeSignature, parameterValues: [String?]?, disambiguatingParameterCount: Int, isConstructor: Bool = false, isFactory: Bool = false, inType: StatementType? = nil, bridgable: FunctionBridgable, options: KotlinBridgeOptions, modifiers: Modifiers, apiFlags: APIFlags, targetIdentifier: String, classIdentifier: String, methodIdentifier: String) -> [String] {
        var swift: [String] = []

        let preEscapedName = name
        let name = preEscapedName.fixingKeyword(in: KotlinIdentifier.hardKeywords)
        let isAsync = apiFlags.options.contains(.async)
        let isThrows = apiFlags.throwsType != .none

        var modifiers = modifiers
        if inType == .protocolDeclaration {
            modifiers.visibility = .default
        }
        let modifierString = modifiers.swift(suffix: " ")

        let parameterString = type.parameters.enumerated().map { index, parameter in
            var str = "\(parameter.label ?? "_") p_\(index): \(bridgable.parameters[index].type)"
            if let value = parameterValues?[index], !value.isEmpty {
                str += " = " + value
            }
            return str
        }
        .joined(separator: ", ")
        var optionsString = isAsync ? " async" : ""
        optionsString += isThrows ? " throws" : ""
        var returnString = bridgable.return.type == .void || isFactory ? "" : " -> " + bridgable.return.type.description
        if inType != .protocolDeclaration {
            returnString += " {"
        }
        swift.append(modifierString + (isConstructor ? "init" : "func " + preEscapedName) + "(\(parameterString))\(optionsString)\(returnString)")
        guard inType != .protocolDeclaration else {
            return swift
        }

        var returnCallString = isConstructor ? (inType == .enumDeclaration ? "self = " : "Java_peer = ") : ""
        // withCheckedThrowingContinuation requires a 'return' even with void to compile correctly
        if (bridgable.return.type != .void && !isFactory) || (isAsync && isThrows) {
            returnCallString += "return "
        }
        if apiFlags.options.contains(.throws) {
            returnCallString += "try "
        }
        var indentation: Indentation = 2
        if isAsync {
            if isThrows {
                swift.append(1, returnCallString + "await withCheckedThrowingContinuation { f_continuation in")
            } else {
                swift.append(1, returnCallString + "await withCheckedContinuation { f_continuation in")
            }
            let callbackType = bridgable.return.type.callbackClosureType(apiFlags: apiFlags, kotlin: false)
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
                } else if bridgable.return.type.isOptional {
                    swift.append(4, "f_continuation.resume(returning: f_return)")
                } else {
                    swift.append(4, "f_continuation.resume(returning: f_return!)")
                }
                swift.append(3, "}")
            }
            swift.append(2, "}")
            swift.append(2, "jniContext {")
            swift.append(3, "let f_return_callback_java = SwiftClosure\(callbackType.parameters.count).javaObject(for: f_return_callback, options: \(options.jconvertibleOptions)).toJavaParameter(options: \(options.jconvertibleOptions))")
            indentation = indentation.inc()
        } else {
            swift.append(1, returnCallString + "jniContext {")
        }

        if inType == .structDeclaration && modifiers.isMutating {
            swift.append(indentation, swiftToCopyJavaPeer(options: options))
        }

        var javaParameterNames: [String] = []
        for (index, bridgable) in bridgable.parameters.enumerated() {
            let label = "p_\(index)"
            let name = label + "_java"
            javaParameterNames.append(name)
            let strategy = bridgable.strategy
            swift.append(indentation, "let \(name) = " + bridgable.type.convertToJava(value: label, strategy: strategy, options: options) + ".toJavaParameter(options: \(options.jconvertibleOptions))")
        }
        for i in 0..<disambiguatingParameterCount {
            let name = "p_\(bridgable.parameters.count + i)_java"
            javaParameterNames.append(name)
            swift.append(indentation, "let \(name) = JavaParameter(l: nil)")
        }

        let tryType = isThrows && !isAsync ? "try" : "try!"
        if isConstructor {
            if inType == .enumDeclaration {
                swift.append(indentation, "let f_return_java: JavaObjectPointer = \(tryType) Self.Java_Companion.call(method: Self.\(methodIdentifier), options: \(options.jconvertibleOptions), args: [" + javaParameterNames.joined(separator: ", ") + "])")
                swift.append(indentation, "return Self.fromJavaObject(f_return_java, options: \(options.jconvertibleOptions))")
            } else {
                swift.append(indentation, "let ptr = \(tryType) Self.Java_class.create(ctor: Self.\(methodIdentifier), args: [" + javaParameterNames.joined(separator: ", ") + "])")
                swift.append(indentation, "return JObject(ptr)")
            }
        } else if isAsync {
            let callType = inType == nil ? "callStatic" : "call"
            let callMethod = inType == nil || modifiers.isStatic ? methodIdentifier : "Self." + methodIdentifier
            var argumentsString = javaParameterNames.joined(separator: ", ")
            if !argumentsString.isEmpty {
                argumentsString += ", "
            }
            argumentsString += "f_return_callback_java"
            let call = "\(tryType) \(targetIdentifier).\(callType)(method: \(callMethod), options: \(options.jconvertibleOptions), args: [\(argumentsString)])"
            swift.append(indentation, call)
        } else {
            let callType = inType == nil ? "callStatic" : "call"
            let callMethod = inType == nil || modifiers.isStatic ? methodIdentifier : "Self." + methodIdentifier
            let call = "\(tryType) \(targetIdentifier).\(callType)(method: \(callMethod), options: \(options.jconvertibleOptions), args: [" + javaParameterNames.joined(separator: ", ") + "])"
            if isThrows {
                swift.append(indentation, "do {")
                indentation = indentation.inc()
            }
            if bridgable.return.type == .void {
                swift.append(indentation, call)
            } else {
                swift.append(indentation, "let f_return_java: " + bridgable.return.type.java(strategy: bridgable.return.strategy, options: options).description + " = \(call)")
                swift.append(indentation, "return " + bridgable.return.type.convertFromJava(value: "f_return_java", strategy: bridgable.return.strategy, options: options))
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

        let declarationType = inType == nil ? "let " : "static let "
        let getType = inType == nil ? "getStaticMethodID" : "getMethodID"
        var kotlinParameters = bridgable.parameters.map { TypeSignature.Parameter(type: $0.kotlinType) }
        kotlinParameters += Array(repeating: TypeSignature.Parameter(type: .module("java.lang", .named("Void", []))), count: disambiguatingParameterCount)
        let functionName: String
        let kotlinReturnType: TypeSignature
        if isConstructor && !isFactory {
            functionName = "<init>"
            kotlinReturnType = .void
        } else if isAsync {
            functionName = "callback_" + preEscapedName
            kotlinParameters.append(TypeSignature.Parameter(type: bridgable.return.kotlinType.callbackClosureType(apiFlags: apiFlags, kotlin: true)))
            kotlinReturnType = .void
        } else {
            functionName = name
            kotlinReturnType = bridgable.return.kotlinType
        }
        let kotlinType: TypeSignature = .function(kotlinParameters, kotlinReturnType, APIFlags(), nil)
        let methodID = "private \(declarationType)\(methodIdentifier) = \(classIdentifier).\(getType)(name: \"\(functionName)\", sig: \"" + kotlinType.jni(options: options, isFunctionDeclaration: true) + "\")!"
        swift.append(methodID)
        return swift
    }

    private func appendCallbackFunction(for functionDeclaration: KotlinFunctionDeclaration, bridgable: FunctionBridgable, modifiers: Modifiers) {
        guard functionDeclaration.apiFlags.options.contains(.async) else {
            return
        }
        let callbackFunction = KotlinFunctionDeclaration(name: "callback_" + (functionDeclaration.preEscapedName ?? functionDeclaration.name))
        callbackFunction.parameters = functionDeclaration.parameters.map { Parameter<KotlinExpression>(externalLabel: $0.externalLabel, internalLabel: $0.internalLabel, declaredType: $0.declaredType, isInOut: $0.isInOut, isVariadic: $0.isVariadic, attributes: $0.attributes, defaultValue: nil, defaultValueSwift: nil) }
        let callbackType = bridgable.return.kotlinType.callbackClosureType(apiFlags: functionDeclaration.apiFlags, kotlin: true)
        callbackFunction.parameters.append(Parameter<KotlinExpression>(externalLabel: "f_return_callback", declaredType: callbackType))
        callbackFunction.returnType = .void
        callbackFunction.modifiers = modifiers
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

    private func updateEqualsDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, in classDeclaration: KotlinClassDeclaration, info: CodebaseInfo.FunctionInfo?, swiftDefinitions: inout [SwiftDefinition]) {
        let modifiers = info?.modifiers ?? functionDeclaration.modifiers
        let swift = Self.swift(forEqualsFunctionIn: classDeclaration.signature, options: options, modifiers: modifiers)
        swiftDefinitions.append(SwiftDefinition(statement: functionDeclaration, swift: swift))
    }

    private static func swift(forEqualsFunctionIn type: TypeSignature, options: KotlinBridgeOptions, modifiers: Modifiers) -> [String] {
        let modifiersString = modifiers.swift(suffix: " ")
        var sourceCode: [String] = []
        sourceCode.append("\(modifiersString)func ==(lhs: \(type), rhs: \(type)) -> Bool {")
        sourceCode.append(1, "return jniContext {")
        sourceCode.append(2, "let lhs_java = lhs.toJavaObject(options: \(options.jconvertibleOptions))!")
        sourceCode.append(2, "let rhs_java = rhs.toJavaParameter(options: \(options.jconvertibleOptions))")
        sourceCode.append(2, "return try! Bool.call(Java_isequal_methodID, on: lhs_java, options: \(options.jconvertibleOptions), args: [rhs_java])")
        sourceCode.append(1, "}")
        sourceCode.append("}")
        sourceCode.append("private static let Java_isequal_methodID = Java_class.getMethodID(name: \"equals\", sig: \"(Ljava/lang/Object;)Z\")!")
        return sourceCode
    }

    private func updateHashDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, in classDeclaration: KotlinClassDeclaration, info: CodebaseInfo.FunctionInfo?, swiftDefinitions: inout [SwiftDefinition]) {
        let modifiers = info?.modifiers ?? functionDeclaration.modifiers
        let swift = Self.swift(forHashFunctionIn: classDeclaration.signature, options: options, modifiers: modifiers)
        swiftDefinitions.append(SwiftDefinition(statement: functionDeclaration, swift: swift))
    }

    private static func swift(forHashFunctionIn type: TypeSignature, options: KotlinBridgeOptions, modifiers: Modifiers) -> [String] {
        let modifiersString = modifiers.swift(suffix: " ")
        var sourceCode: [String] = []
        sourceCode.append("\(modifiersString)func hash(into hasher: inout Hasher) {")
        sourceCode.append(1, "let hashCode: Int32 = jniContext {")
        sourceCode.append(2, "return try! Java_peer.call(method: Self.Java_hashCode_methodID, options: \(options.jconvertibleOptions), args: [])")
        sourceCode.append(1, "}")
        sourceCode.append(1, "hasher.combine(hashCode)")
        sourceCode.append("}")
        sourceCode.append("private static let Java_hashCode_methodID = Java_class.getMethodID(name: \"hashCode\", sig: \"()I\")!")
        return sourceCode
    }

    private func updateLessThanDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, in classDeclaration: KotlinClassDeclaration, info: CodebaseInfo.FunctionInfo?, swiftDefinitions: inout [SwiftDefinition]) {
        let modifiers = info?.modifiers ?? functionDeclaration.modifiers
        let swift = Self.swift(forLessThanDeclarationIn: classDeclaration.signature, options: options, modifiers: modifiers)
        swiftDefinitions.append(SwiftDefinition(statement: functionDeclaration, swift: swift))
    }

    private static func swift(forLessThanDeclarationIn type: TypeSignature, options: KotlinBridgeOptions, modifiers: Modifiers) -> [String] {
        let modifiersString = modifiers.swift(suffix: " ")
        var sourceCode: [String] = []
        sourceCode.append("\(modifiersString)func <(lhs: \(type), rhs: \(type)) -> Bool {")
        sourceCode.append(1, "return jniContext {")
        sourceCode.append(2, "let lhs_java = lhs.toJavaObject(options: \(options.jconvertibleOptions))!")
        sourceCode.append(2, "let rhs_java = rhs.toJavaParameter(options: \(options.jconvertibleOptions))")
        sourceCode.append(2, "let f_return_java = try! Int32.call(Java_compareTo_methodID, on: lhs_java, options: \(options.jconvertibleOptions), args: [rhs_java])")
        sourceCode.append(2, "return f_return_java < 0")
        sourceCode.append(1, "}")
        sourceCode.append("}")
        sourceCode.append("private static let Java_compareTo_methodID = Java_class.getMethodID(name: \"compareTo\", sig: \"(Ljava/lang/Object;)I\")!")
        return sourceCode
    }

    private func update(_ classDeclaration: KotlinClassDeclaration, swiftDefinitions: inout [SwiftDefinition]) {
        guard classDeclaration.checkBridgable(options: options, translator: translator) else {
            return
        }
        let typeInfos = codebaseInfo.typeInfos(forNamed: classDeclaration.signature)
        guard let primaryTypeInfo = typeInfos.first(where: { $0.declarationType != .extensionDeclaration }) else {
            classDeclaration.messages.append(Message.kotlinBridgeMissingInfo(classDeclaration, source: translator.syntaxTree.source))
            return
        }
        let classRef = JavaClassRef(for: classDeclaration.signature, packageName: translator.packageName)

        let isEnum = classDeclaration.declarationType == .enumDeclaration
        let isStruct = classDeclaration.declarationType == .structDeclaration
        let visibilityString = primaryTypeInfo.modifiers.visibility.swift(suffix: " ")
        let inherits = typeInfos.flatMap(\.inherits).compactMap {
            let inherit = $0.withGenerics([])
            return inherit.isEquatable || inherit.isHashable || inherit.isComparable || inherit.checkBridgable(options: options, codebaseInfo: codebaseInfo) != nil ? inherit : nil
        }
        var inheritsString = inherits.map { $0.description }.joined(separator: ", ")
        if !inheritsString.isEmpty {
            inheritsString += ", "
        }
        inheritsString += "BridgedFromKotlin"
        var swift: [String] = []
        swift.append("\(visibilityString)\(isEnum ? "enum" : isStruct ? "struct" : "class") \(classDeclaration.name): \(inheritsString) {")

        let finalMemberVisibility = primaryTypeInfo.modifiers.visibility > .public ? .public : primaryTypeInfo.modifiers.visibility
        let finalMemberVisibilityString = finalMemberVisibility.swift(suffix: " ")
        swift.append(1, classRef.declaration)

        if isEnum {
            swift.append(1, "private var Java_peer: JavaObjectPointer {")
            swift.append(2, "return toJavaObject(options: \(options.jconvertibleOptions))!")
            swift.append(1, "}")
        } else {
            swift.append(1, "\(finalMemberVisibilityString)\(isStruct ? "var" : "let") Java_peer: JObject")
            swift.append(1, "\(finalMemberVisibilityString)\(isStruct ? "" : "required ")init(Java_ptr: JavaObjectPointer) {")
            swift.append(2, "Java_peer = JObject(Java_ptr)")
            swift.append(1, "}")

            if !classDeclaration.members.contains(where: { $0.type == .constructorDeclaration && ($0 as? KotlinFunctionDeclaration)?.isDecodableConstructor == false }) {
                swift.append(1, "\(finalMemberVisibilityString)init() {")
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
        }

        var memberDefinitions: [SwiftDefinition] = []
        var hasBridgedStaticMembers = false
        var functionCount = 0
        var enumCases: [KotlinEnumCaseDeclaration] = []
        for member in classDeclaration.members {
            if let enumCaseDeclaration = member as? KotlinEnumCaseDeclaration {
                if update(member: enumCaseDeclaration, swiftDefinitions: &memberDefinitions) {
                    enumCases.append(enumCaseDeclaration)
                }
            } else if let variableDeclaration = member as? KotlinVariableDeclaration {
                guard variableDeclaration.modifiers.visibility >= .public, !variableDeclaration.isGenerated, !variableDeclaration.attributes.isBridgeIgnored else {
                    continue
                }
                let info = typeInfos.flatMap({ $0.variables }).first(where: { $0.name == (variableDeclaration.preEscapedPropertyName ?? variableDeclaration.propertyName) && $0.modifiers.visibility >= .fileprivate })
                if update(member: variableDeclaration, info: info, swiftDefinitions: &memberDefinitions), variableDeclaration.isStatic {
                    hasBridgedStaticMembers = true
                }
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                guard functionDeclaration.modifiers.visibility >= .public, (!functionDeclaration.isGenerated || functionDeclaration.type == .constructorDeclaration), !functionDeclaration.attributes.isBridgeIgnored else {
                    continue
                }
                guard !functionDeclaration.isEncode && !functionDeclaration.isDecodableConstructor else {
                    continue
                }
                let info = typeInfos.flatMap({ $0.functions }).first(where: { $0.name == (functionDeclaration.preEscapedName ?? functionDeclaration.name) && $0.signature == functionDeclaration.functionType && $0.modifiers.visibility >= .fileprivate })
                if functionDeclaration.isEqualImplementation {
                    updateEqualsDeclaration(functionDeclaration, in: classDeclaration, info: info, swiftDefinitions: &memberDefinitions)
                } else if functionDeclaration.isHashImplementation {
                    updateHashDeclaration(functionDeclaration, in: classDeclaration, info: info, swiftDefinitions: &memberDefinitions)
                } else if functionDeclaration.isLessThanImplementation {
                    updateLessThanDeclaration(functionDeclaration, in: classDeclaration, info: info, swiftDefinitions: &memberDefinitions)
                } else {
                    if update(member: functionDeclaration, info: info, uniquifier: functionCount, swiftDefinitions: &memberDefinitions) {
                        functionCount += 1
                        if functionDeclaration.isStatic {
                            hasBridgedStaticMembers = true
                        }
                    }
                }
            }
        }

        if classDeclaration.inherits.contains(.named("MutableStruct", [])) {
            swift.append(1, "private static let Java_scopy_methodID = Java_class.getMethodID(name: \"scopy\", sig: \"()Lskip/lib/MutableStruct;\")!")
        }
        if hasBridgedStaticMembers {
            swift.append(1, "private static let Java_Companion_class = try! JClass(name: \"\(classRef.className)$Companion\")")
            swift.append(1, "private static let Java_Companion = JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: \"Companion\", sig: \"L\(classRef.className)$Companion;\")!, options: \(options.jconvertibleOptions)))")
        }
        if isEnum {
            swift.append(1, Self.swiftForEnumJConvertibleContract(className: classRef.className, caseDeclarations: enumCases, visibility: finalMemberVisibility, options: options))
        } else {
            swift.append(1, Self.swiftForJConvertibleContract(visibility: finalMemberVisibility))
        }

        let definition = SwiftDefinition(statement: classDeclaration, children: memberDefinitions) { output, indentation, children in
            swift.forEach { output.append(indentation).append($0).append("\n") }
            let childIndentation = indentation.inc()
            children.forEach { output.append("\n").append($0, indentation: childIndentation) }
            output.append(indentation).append("}\n")
        }
        swiftDefinitions.append(definition)
    }

    private static func swiftForJConvertibleContract(visibility: Modifiers.Visibility) -> [String] {
        let visibilityString = visibility.swift(suffix: " ")
        var swift: [String] = []
        swift.append(visibilityString + "static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {")
        swift.append(1, "return .init(Java_ptr: obj!)")
        swift.append("}")
        swift.append(visibilityString + "func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {")
        swift.append(1, "return Java_peer.safePointer()")
        swift.append("}")
        return swift
    }

    /// Return the Swift statements implementing the `JConvertible` contract for an enum.
    static func swiftForEnumJConvertibleContract(className: String, caseDeclarations: [KotlinEnumCaseDeclaration], visibility: Modifiers.Visibility, options: KotlinBridgeOptions) -> [String] {
        let visibilityString = visibility.swift(suffix: " ")
        var swift: [String] = []
        swift.append(visibilityString + "static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {")
        swift.append(1, "let name: String = try! obj!.call(method: Java_name_methodID, options: options, args: [])")
        swift.append(1, "return fromJavaName(name)")
        swift.append("}")

        swift.append("fileprivate static func fromJavaName(_ name: String) -> Self {")
        swift.append(1, "return switch name {")
        for enumCaseDeclaration in caseDeclarations {
            swift.append(1, "case \"\(enumCaseDeclaration.name)\": .\(enumCaseDeclaration.preEscapedName ?? enumCaseDeclaration.name)")
        }
        swift.append(1, "default: fatalError()")
        swift.append(1, "}")
        swift.append("}")

        swift.append(visibilityString + "func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {")
        swift.append(1, "let name = switch self {")
        for enumCaseDeclaration in caseDeclarations {
            swift.append(1, "case .\(enumCaseDeclaration.preEscapedName ?? enumCaseDeclaration.name): \"\(enumCaseDeclaration.name)\"")
        }
        swift.append(1, "}")
        swift.append(1, "return try! Self.Java_class.callStatic(method: Self.Java_valueOf_methodID, options: options, args: [name.toJavaParameter(options: options)])")
        swift.append("}")

        swift.append("private static let Java_name_methodID = Java_class.getMethodID(name: \"name\", sig: \"()Ljava/lang/String;\")!")
        swift.append("private static let Java_valueOf_methodID = Java_class.getStaticMethodID(name: \"valueOf\", sig: \"(Ljava/lang/String;)L\(className);\")!")
        return swift
    }

    private func update(_ interfaceDeclaration: KotlinInterfaceDeclaration, swiftDefinitions: inout [SwiftDefinition]) {
        guard interfaceDeclaration.checkBridgable(options: options, translator: translator) else {
            return
        }
        guard let primaryTypeInfo = codebaseInfo.primaryTypeInfo(forNamed: interfaceDeclaration.signature) else {
            interfaceDeclaration.messages.append(Message.kotlinBridgeMissingInfo(interfaceDeclaration, source: translator.syntaxTree.source))
            return
        }

        let visibilityString = primaryTypeInfo.modifiers.visibility.swift(suffix: " ")
        let inherits = primaryTypeInfo.inherits.compactMap {
            let inherit = $0.withGenerics([])
            return inherit.isEquatable || inherit.isHashable || inherit.isComparable || inherit.checkBridgable(options: options, codebaseInfo: codebaseInfo) != nil ? inherit : nil
        }
        let inheritsString = inherits.isEmpty ? "" : ": " + inherits.map { $0.description }.joined(separator: ", ")

        var swift: [String] = []
        swift.append("\(visibilityString)protocol \(interfaceDeclaration.name)\(inheritsString) {")

        var memberDefinitions: [SwiftDefinition] = []
        var functionCount = 0
        for member in interfaceDeclaration.members {
            if let variableDeclaration = member as? KotlinVariableDeclaration {
                guard !variableDeclaration.attributes.isBridgeIgnored else {
                    continue
                }
                let info = primaryTypeInfo.variables.first(where: { $0.name == variableDeclaration.propertyName })
                update(member: variableDeclaration, info: info, swiftDefinitions: &memberDefinitions)
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                guard !functionDeclaration.attributes.isBridgeIgnored else {
                    continue
                }
                let info = primaryTypeInfo.functions.first(where: { $0.name == functionDeclaration.name && $0.signature == functionDeclaration.functionType && $0.modifiers.visibility >= .fileprivate })
                if update(member: functionDeclaration, info: info, uniquifier: functionCount, swiftDefinitions: &memberDefinitions) {
                    functionCount += 1
                }
            }
        }

        let definition = SwiftDefinition(statement: interfaceDeclaration, children: memberDefinitions) { output, indentation, children in
            swift.forEach { output.append(indentation).append($0).append("\n") }
            let childIndentation = indentation.inc()
            children.forEach { output.append("\n").append($0, indentation: childIndentation) }
            output.append(indentation).append("}\n")
        }
        swiftDefinitions.append(definition)

        if let bridgeImplDefinition = Self.unknownBridgeImplDefinition(forProtocol: interfaceDeclaration.signature, inPackage: translator.packageName, statement: interfaceDeclaration, options: options, codebaseInfo: codebaseInfo) {
            swiftDefinitions.append(bridgeImplDefinition)
        }
    }

    /// Define an anonymous implementation of a bridged protocol.
    static func unknownBridgeImplDefinition(forProtocol type: TypeSignature, inPackage packageName: String?, statement: KotlinStatement?, options: KotlinBridgeOptions, codebaseInfo: CodebaseInfo.Context) -> SwiftDefinition? {
        guard let primaryTypeInfo = codebaseInfo.primaryTypeInfo(forNamed: type) else {
            return nil
        }
        let protocolSignatures = codebaseInfo.global.protocolSignatures(forNamed: type).dropFirst()
        let bridgeImpl = type.unknownBridgeImpl

        var swift: [String] = []
        swift.append("public final class \(bridgeImpl): \(type), BridgedFromKotlin {")

        let classRef = JavaClassRef(for: type, packageName: packageName)
        swift.append(1, classRef.declaration)
        swift.append(1, "public let Java_peer: JObject")
        swift.append(1, "public required init(Java_ptr: JavaObjectPointer) {")
        swift.append(2, "Java_peer = JObject(Java_ptr)")
        swift.append(1, "}")

        var functionCount = 0
        swift.append(1, self.swift(forUnknownBridgeImplMembers: primaryTypeInfo, options: options, codebaseInfo: codebaseInfo, functionCount: &functionCount))
        var seenProtocolSignatures: Set<TypeSignature> = []
        for protocolSignature in protocolSignatures {
            guard seenProtocolSignatures.insert(protocolSignature).inserted else {
                continue
            }
            if protocolSignature.isEquatable {
                swift.append(1, self.swift(forEqualsFunctionIn: bridgeImpl, options: options, modifiers: Modifiers(visibility: .public, isStatic: true)))
            } else if protocolSignature.isHashable {
                swift.append(1, self.swift(forHashFunctionIn: bridgeImpl, options: options, modifiers: Modifiers(visibility: .public)))
            } else if protocolSignature.isComparable {
                swift.append(1, self.swift(forLessThanDeclarationIn: bridgeImpl, options: options, modifiers: Modifiers(visibility: .public, isStatic: true)))
            } else if let protocolInfo = codebaseInfo.primaryTypeInfo(forNamed: protocolSignature) {
                swift.append(1, self.swift(forUnknownBridgeImplMembers: protocolInfo, options: options, codebaseInfo: codebaseInfo, functionCount: &functionCount))
            }
        }
        swift.append(1, swiftForJConvertibleContract(visibility: .public))

        swift.append("}")
        return SwiftDefinition(statement: statement, swift: swift)
    }

    private static func swift(forUnknownBridgeImplMembers info: CodebaseInfo.TypeInfo, options: KotlinBridgeOptions, codebaseInfo: CodebaseInfo.Context, functionCount: inout Int) -> [String] {
        var swift: [String] = []
        for variableInfo in info.variables {
            guard !variableInfo.attributes.isBridgeIgnored else {
                continue
            }
            guard let bridgable = variableInfo.signature.checkBridgable(options: options, codebaseInfo: codebaseInfo) else {
                continue
            }
            var modifiers = variableInfo.modifiers
            modifiers.visibility = .public
            swift += self.swift(forMemberVariableWithName: variableInfo.name, inType: .classDeclaration, bridgable: bridgable, options: options, modifiers: modifiers, attributes: variableInfo.attributes, apiFlags: variableInfo.apiFlags ?? APIFlags())
        }
        for functionInfo in info.functions {
            guard !functionInfo.attributes.isBridgeIgnored else {
                continue
            }
            guard let bridgable = functionInfo.signature.checkFunctionBridgable(isConstructor: functionInfo.declarationType == .initDeclaration, options: options, codebaseInfo: codebaseInfo) else {
                continue
            }
            var modifiers = functionInfo.modifiers
            modifiers.visibility = .public
            swift += self.swift(forMemberFunctionWithName: functionInfo.name, type: functionInfo.signature, parameterValues: nil, uniquifier: functionCount, disambiguatingParameterCount: 0, isConstructor: false, isFactory: false, inType: .classDeclaration, bridgable: bridgable, options: options, modifiers: modifiers, apiFlags: functionInfo.apiFlags ?? APIFlags())
            functionCount += 1
        }
        return swift
    }
}
