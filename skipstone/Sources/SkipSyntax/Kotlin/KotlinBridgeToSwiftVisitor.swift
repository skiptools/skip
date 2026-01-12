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
        guard let codebaseInfo = translator.codebaseInfo, let outputFile = syntaxTree.source.file.bridgeOutputFile else {
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
        let isBridgeFile = syntaxTree.isBridgeFile
        var swiftDefinitions: [SwiftDefinition] = []
        var needsGlobalsJavaClass = false
        var globalFunctionCount = 0
        var hasContentComposer = false
        syntaxTree.root.visit(ifSkipBlockContent: isBridgeFile) { node in
            if let variableDeclaration = node as? KotlinVariableDeclaration {
                let variableIsBridging = {
                    return isBridging(attributes: variableDeclaration.attributes, visibility: variableDeclaration.modifiers.visibility, bridgeMemberVisibility: nil, autoBridge: isBridgeFile ? .internal : self.syntaxTree.autoBridge)
                }
                if variableDeclaration.role == .global || variableDeclaration.extends != nil, variableIsBridging() {
                    if variableDeclaration.extends != nil && variableDeclaration.isStatic {
                        variableDeclaration.messages.append(.kotlinBridgeExtensionFunctionStatic(variableDeclaration, source: syntaxTree.source))
                    } else {
                        needsGlobalsJavaClass = update(global: variableDeclaration, swiftDefinitions: &swiftDefinitions, globalsClassRef: globalsClassRef) || needsGlobalsJavaClass
                    }
                    checkIfNotSkipBridge(variableDeclaration)
                }
                return .skip
            } else if let functionDeclaration = node as? KotlinFunctionDeclaration {
                let functionIsBridging = {
                    return isBridging(attributes: functionDeclaration.attributes, visibility: functionDeclaration.modifiers.visibility, bridgeMemberVisibility: nil, autoBridge: isBridgeFile ? .internal : self.syntaxTree.autoBridge)
                }
                if functionDeclaration.role == .global || functionDeclaration.extends != nil, functionIsBridging() {
                    if functionDeclaration.extends != nil && functionDeclaration.isStatic {
                        functionDeclaration.messages.append(.kotlinBridgeExtensionFunctionStatic(functionDeclaration, source: syntaxTree.source))
                    } else {
                        if update(global: functionDeclaration, uniquifier: globalFunctionCount, swiftDefinitions: &swiftDefinitions, globalsClassRef: globalsClassRef) {
                            needsGlobalsJavaClass = true
                            globalFunctionCount += 1
                        }
                    }
                    checkIfNotSkipBridge(functionDeclaration)
                }
                return .skip
            } else if let classDeclaration = node as? KotlinClassDeclaration {
                hasContentComposer = hasContentComposer || (syntaxTree.isBridgeFile && updateContentComposer(classDeclaration))
                if isBridging(attributes: classDeclaration.attributes, visibility: classDeclaration.modifiers.visibility, bridgeMemberVisibility: nil, autoBridge: isBridgeFile ? .internal : syntaxTree.autoBridge) {
                    update(classDeclaration, swiftDefinitions: &swiftDefinitions)
                    checkIfNotSkipBridge(classDeclaration)
                }
                return .recurse(nil)
            } else if let interfaceDeclaration = node as? KotlinInterfaceDeclaration {
                if isBridging(attributes: interfaceDeclaration.attributes, visibility: interfaceDeclaration.modifiers.visibility, bridgeMemberVisibility: nil, autoBridge: isBridgeFile ? .internal : syntaxTree.autoBridge) {
                    update(interfaceDeclaration, swiftDefinitions: &swiftDefinitions)
                    checkIfNotSkipBridge(interfaceDeclaration)
                }
                return .recurse(nil)
            } else if let typealiasDeclaration = node as? KotlinTypealiasDeclaration {
                if isBridging(attributes: typealiasDeclaration.attributes, visibility: typealiasDeclaration.modifiers.visibility, bridgeMemberVisibility: nil, autoBridge: isBridgeFile ? .internal : syntaxTree.autoBridge) {
                    update(typealiasDeclaration, swiftDefinitions: &swiftDefinitions)
                    checkIfNotSkipBridge(typealiasDeclaration)
                }
                return .skip
            } else {
                return .recurse(nil)
            }
        }
        if hasContentComposer {
            syntaxTree.dependencies.imports.insert("androidx.compose.runtime.Composable")
        }
        guard !swiftDefinitions.isEmpty else {
            return []
        }

        let importDeclarations = syntaxTree.root.statements
            .compactMap { $0 as? KotlinImportDeclaration }
            .filter { !$0.isKotlinImport }
        let swiftImports = self.swiftImports(for: importDeclarations)
        let outputNode = SwiftDefinition { output, indentation, _ in
            output.append("import SkipBridge\n\n")
            swiftImports.forEach {
                output.append(indentation).append("import ").append($0).append("\n")
            }
            if needsGlobalsJavaClass {
                output.append(indentation).append(globalsClassRef.declaration()).append("\n")
            }
            swiftDefinitions.forEach { output.append($0, indentation: indentation) }
        }
        let output = KotlinTransformerOutput(file: outputFile, node: outputNode, type: .bridgeToSwift)
        return [output]
    }

    private func swiftImports(for importDeclarations: [KotlinImportDeclaration]) -> [String] {
        let mappedModules = [
            "SwiftUI": "SkipFuseUI",
            "OSLog": "SkipFuse"
        ]
        var importModulePaths: [String] = []
        var importModulePathsSet: Set<String> = []
        for importDeclaration in importDeclarations {
            guard importDeclaration.unmappedModulePath.count != 1 || importDeclaration.unmappedModulePath[0] != "SkipBridge" else {
                continue
            }
            var modulePath = importDeclaration.unmappedModulePath
            // Replace Skip transpiled library imports
            if let mappedModule = mappedModules[modulePath.first ?? ""] {
                if modulePath.count == 1 {
                    modulePath = [mappedModule]
                } else {
                    modulePath[0] = mappedModule
                }
            }
            let path = modulePath.joined(separator: ".")
            if importModulePathsSet.insert(path).inserted {
                importModulePaths.append(path)
            }
        }
        return importModulePaths
    }

    private func checkIfNotSkipBridge(_ statement: KotlinStatement) {
        guard !syntaxTree.isBridgeFile && !statement.isInIfNotSkipBridgeBlock else {
            return
        }
        statement.messages.append(.kotlinBridgeMissingIfNotSkipBridge(statement, source: syntaxTree.source))
    }

    @discardableResult private func update(member enumCaseDeclaration: KotlinEnumCaseDeclaration, swiftDefinitions: inout [SwiftDefinition]) -> Bool {
        let name = enumCaseDeclaration.preEscapedName ?? enumCaseDeclaration.name
        var swift = "case `\(name)`"
        if let value = enumCaseDeclaration.rawValueSwift {
            swift += " = " + value
        } else if !enumCaseDeclaration.associatedValues.isEmpty {
            swift += "(" + enumCaseDeclaration.associatedValues.map {
                var caseSwift = ""
                if let label = $0.externalLabel {
                    caseSwift = "\(label): "
                }
                caseSwift += $0.declaredType.description
                if let valueString = $0.defaultValueSwift {
                    caseSwift += " = \(valueString)"
                }
                return caseSwift
            }.joined(separator: ", ") + ")"
        }
        swiftDefinitions.append(SwiftDefinition(statement: enumCaseDeclaration, swift: [swift]))
        return true
    }

    private func update(global variableDeclaration: KotlinVariableDeclaration, swiftDefinitions: inout [SwiftDefinition], globalsClassRef: JavaClassRef) -> Bool {
        guard let bridgable = variableDeclaration.checkBridgable(direction: .toSwift, options: options, translator: translator) else {
            return false
        }
        guard !addConstantDefinition(for: variableDeclaration, type: bridgable.type, modifiers: variableDeclaration.modifiers, to: &swiftDefinitions) else {
            return false
        }
        let bridgableExtends: (Bridgable, Generics)?
        if let extends = variableDeclaration.extends {
            guard let bridgableExtendsType = extends.0.checkBridgable(direction: .toSwift, options: options, generics: extends.1, codebaseInfo: codebaseInfo) else {
                return false
            }
            bridgableExtends = (bridgableExtendsType, extends.1)
        } else {
            bridgableExtends = nil
        }
        if let annotation = variableDeclaration.preventJVMNameManglingAnnotation() {
            variableDeclaration.annotations.append(annotation)
        }

        let propertyName = variableDeclaration.preEscapedPropertyName ?? variableDeclaration.propertyName
        let swift: [String]
        if variableDeclaration.isAppendAsFunction {
            let functionType: TypeSignature = .function([], bridgable.type, variableDeclaration.apiFlags, variableDeclaration.attributes)
            let functionBridgable = FunctionBridgable(parameters: [], return: bridgable)
            let methodIdentifier = "Java_" + propertyName + "_methodID"
            let definitionSwift = Self.swift(forFunctionWithName: propertyName, type: functionType, generics: Generics(), parameterValues: [], disambiguatingParameterCount: 0, isDeclaredByVariable: true, bridgable: functionBridgable, extends: bridgableExtends, options: options, modifiers: variableDeclaration.modifiers, attributes: variableDeclaration.attributes, apiFlags: variableDeclaration.apiFlags, targetIdentifier: globalsClassRef.identifier, methodIdentifier: methodIdentifier)
            let javaSwift = Self.swiftJavaDeclarations(forFunctionWithName: propertyName, type: functionType, disambiguatingParameterCount: 0, bridgable: functionBridgable, extends: bridgableExtends, options: options, modifiers: variableDeclaration.modifiers, apiFlags: variableDeclaration.apiFlags, classIdentifier: globalsClassRef.identifier, methodIdentifier: methodIdentifier)
            swift = definitionSwift + javaSwift
        } else {
            let getMethodIdentifier = "Java_get_" + propertyName + "_methodID"
            let setMethodIdentifier = "Java_set_" + propertyName + "_methodID"
            let definitionSwift = Self.swift(forVariableWithName: propertyName, bridgable: bridgable, extends: bridgableExtends, options: options, modifiers: variableDeclaration.modifiers, attributes: variableDeclaration.attributes, apiFlags: variableDeclaration.apiFlags, targetIdentifier: globalsClassRef.identifier, getMethodIdentifier: getMethodIdentifier, setMethodIdentifier: setMethodIdentifier)
            let javaSwift = Self.swiftJavaDeclarations(forVariableWithName: propertyName, bridgable: bridgable, extends: bridgableExtends, options: options, modifiers: variableDeclaration.modifiers, apiFlags: variableDeclaration.apiFlags, classIdentifier: globalsClassRef.identifier, getMethodIdentifier: getMethodIdentifier, setMethodIdentifier: setMethodIdentifier)
            swift = definitionSwift + javaSwift
        }
        swiftDefinitions.append(SwiftDefinition(statement: variableDeclaration, swift: swift))
        Self.appendCallbackFunction(for: variableDeclaration, bridgable: bridgable, modifiers: variableDeclaration.modifiers)
        return true
    }

    @discardableResult private func update(member variableDeclaration: KotlinVariableDeclaration, info: CodebaseInfo.VariableInfo?, in parentStatement: KotlinStatement, swiftDefinitions: inout [SwiftDefinition]) -> Bool {
        guard let bridgable = variableDeclaration.checkBridgable(direction: .toSwift, options: options, translator: translator) else {
            return false
        }
        let modifiers = info?.modifiers ?? variableDeclaration.modifiers
        guard !addConstantDefinition(for: variableDeclaration, type: bridgable.type, modifiers: modifiers, to: &swiftDefinitions) else {
            return false
        }
        if let annotation = variableDeclaration.preventJVMNameManglingAnnotation() {
            variableDeclaration.annotations.append(annotation)
        }
        Self.appendCallbackFunction(for: variableDeclaration, bridgable: bridgable, modifiers: modifiers)
        // Don't add Swift for protocol extension members that were merged into Kotlin interface
        guard info != nil || parentStatement.type != .interfaceDeclaration else {
            return true
        }

        let (inType, inSignature) = declarationTypeInfo(for: parentStatement)
        let propertyName = info?.name ?? variableDeclaration.preEscapedPropertyName ?? variableDeclaration.propertyName
        let attributes = info?.attributes ?? variableDeclaration.attributes
        let apiFlags = info?.apiFlags ?? variableDeclaration.apiFlags
        let swift = Self.swift(forMemberVariableWithName: propertyName, isAppendAsFunction: variableDeclaration.isAppendAsFunction, inType: inType, inSignature: inSignature, bridgable: bridgable, options: options, modifiers: modifiers, attributes: attributes, apiFlags: apiFlags)
        swiftDefinitions.append(SwiftDefinition(statement: variableDeclaration, swift: swift))
        return true
    }

    private static func swift(forMemberVariableWithName propertyName: String, isAppendAsFunction: Bool, inType: StatementType, inSignature: TypeSignature, bridgable: Bridgable, options: KotlinBridgeOptions, modifiers: Modifiers, attributes: Attributes, apiFlags: APIFlags) -> [String] {
        let targetIdentifier = modifiers.isStatic ? "Java_Companion" : "Java_peer"
        let classIdentifier = modifiers.isStatic ? "Java_Companion_class" : "Java_class"
        if isAppendAsFunction {
            let functionType: TypeSignature = .function([], bridgable.type, apiFlags, attributes)
            let functionBridgable = FunctionBridgable(parameters: [], return: bridgable)
            let methodIdentifier = modifiers.isStatic ? "Java_Companion_" + propertyName + "_methodID" : "Java_" + propertyName + "_methodID"
            let definitionSwift = Self.swift(forFunctionWithName: propertyName, type: functionType, generics: Generics(), parameterValues: [], disambiguatingParameterCount: 0, isDeclaredByVariable: true, inType: inType, bridgable: functionBridgable, options: options, modifiers: modifiers, attributes: attributes, apiFlags: apiFlags, targetIdentifier: targetIdentifier, methodIdentifier: methodIdentifier)
            let javaSwift = Self.swiftJavaDeclarations(forFunctionWithName: propertyName, type: functionType, disambiguatingParameterCount: 0, inType: inType, inSignature: inSignature, bridgable: functionBridgable, options: options, modifiers: modifiers, apiFlags: apiFlags, classIdentifier: classIdentifier, methodIdentifier: methodIdentifier)
            return definitionSwift + javaSwift
        } else {
            let getMethodIdentifier = modifiers.isStatic ? "Java_Companion_get_" + propertyName + "_methodID" : "Java_get_" + propertyName + "_methodID"
            let setMethodIdentifier = modifiers.isStatic ? "Java_Companion_set_" + propertyName + "_methodID" : "Java_set_" + propertyName + "_methodID"
            let definitionSwift = Self.swift(forVariableWithName: propertyName, inType: inType, bridgable: bridgable, options: options, modifiers: modifiers, attributes: attributes, apiFlags: apiFlags, targetIdentifier: targetIdentifier, getMethodIdentifier: getMethodIdentifier, setMethodIdentifier: setMethodIdentifier)
            let javaSwift = Self.swiftJavaDeclarations(forVariableWithName: propertyName, inType: inType, inSignature: inSignature, bridgable: bridgable, options: options, modifiers: modifiers, apiFlags: apiFlags, classIdentifier: classIdentifier, getMethodIdentifier: getMethodIdentifier, setMethodIdentifier: setMethodIdentifier)
            return definitionSwift + javaSwift
        }
    }

    private static func swift(forVariableWithName propertyName: String, inType: StatementType? = nil, bridgable: Bridgable, extends: (Bridgable, Generics)? = nil, options: KotlinBridgeOptions, modifiers: Modifiers, attributes: Attributes, apiFlags: APIFlags, targetIdentifier: String, getMethodIdentifier: String, setMethodIdentifier: String) -> [String] {
        var swift: [String] = []

        let preEscapedPropertyName = propertyName
        var modifiers = modifiers
        if inType == .protocolDeclaration {
            modifiers.visibility = .default
        }
        let modifierString = modifiers.swift(isNoOverride: attributes.contains(directive: KotlinDirective.nooverride), suffix: " ")
        let optionsString = options.jconvertibleOptions
        let hasSetter = apiFlags.options.contains(.writeable) && (modifiers.setVisibility == .default || modifiers.setVisibility >= .public)
        var indentation: Indentation = 0
        let isViewExtension: Bool
        if let extends, !hasSetter {
            swift.append("extension \(extends.0.type)\(extends.1.swiftWhereString) {")
            indentation = indentation.inc()
            isViewExtension = extends.0.strategy == .view && bridgable.strategy == .view
        } else {
            isViewExtension = false
        }
        let initialIndentationLevel = indentation.level

        var declarationSuffix = " {"
        if inType == .protocolDeclaration {
            declarationSuffix += " get"
            if hasSetter {
                declarationSuffix += " set"
            }
            declarationSuffix += " }"
        }
        swift.append(indentation, "\(modifierString)var \(preEscapedPropertyName.addingBacktickEscapingIfNeeded): \(bridgable.type.description)\(declarationSuffix)")
        guard inType != .protocolDeclaration else {
            return swift
        }
        indentation = indentation.inc()

        // Getter
        let callType = inType == nil ? "callStatic" : "call"
        let callGet = inType == nil || modifiers.isStatic ? getMethodIdentifier : "Self." + getMethodIdentifier
        var getterBody: [String] = []
        let getterArguments: String
        if let extends {
            let value = isViewExtension ? "target" : "self"
            let name = isViewExtension ? "target_java" : "self_java"
            getterBody.append("let \(name) = \(extends.0.kotlinType.convertToJava(value: value, strategy: extends.0.strategy, options: options)).toJavaParameter(options: \(optionsString))")
            getterArguments = name
        } else {
            getterArguments = ""
        }
        getterBody += [
            "let value_java: \(bridgable.type.java(strategy: bridgable.strategy, options: options)) = try! \(targetIdentifier).\(callType)(method: \(callGet), options: \(optionsString), args: [\(getterArguments)])",
            "return " + bridgable.type.convertFromJava(value: "value_java", strategy: bridgable.strategy, options: options)
        ]
        if apiFlags.throwsType != .none {
            swift.append(indentation, "get throws {")
            indentation = indentation.inc()
            swift.append(indentation, "return try jniContext {")
            indentation = indentation.inc()
            swift.append(indentation, "do {")
            swift.append(indentation.inc(), getterBody)
            swift.append(indentation, "} catch let error as (Error & JConvertible) {")
            swift.append(indentation.inc(), "throw error")
            swift.append(indentation, "} catch {")
            swift.append(indentation.inc(), "fatalError(String(describing: error))")
            swift.append(indentation, "}")
        } else {
            swift.append(indentation, "get {")
            if isViewExtension {
                indentation = indentation.inc()
                swift.append(indentation, "return SkipSwiftUI.ModifierView(target: self) { target in")
            }
            indentation = indentation.inc()
            swift.append(indentation, "return jniContext {")
            swift.append(indentation.inc(), getterBody)
            swift.append(indentation, "}")
        }
        while indentation.level > initialIndentationLevel + 1 {
            indentation = indentation.dec()
            swift.append(indentation, "}")
        }

        // Setter
        if hasSetter {
            let setVisibility: String
            if modifiers.setVisibility < modifiers.visibility {
                setVisibility = modifiers.setVisibility.swift(suffix: " ")
            } else {
                setVisibility = ""
            }
            let callSet = inType == nil || modifiers.isStatic ? setMethodIdentifier : "Self." + setMethodIdentifier
            swift.append(indentation, setVisibility + "set {")
            indentation = indentation.inc()
            swift.append(indentation, "jniContext {")
            indentation = indentation.inc()
            let setterArguments: String
            if let extends {
                swift.append(indentation, "let self_java = \(extends.0.kotlinType.convertToJava(value: "self", strategy: extends.0.strategy, options: options)).toJavaParameter(options: \(optionsString))")
                setterArguments = "self_java, value_java"
            } else {
                if inType == .structDeclaration && !modifiers.isStatic {
                    swift.append(indentation, swiftToCopyJavaPeer(options: options))
                }
                setterArguments = "value_java"
            }
            swift.append(indentation, [
                "let value_java = " + bridgable.type.convertToJava(value: "newValue", strategy: bridgable.strategy, options: options) + ".toJavaParameter(options: \(optionsString))",
                "try! \(targetIdentifier).\(callType)(method: \(callSet), options: \(optionsString), args: [\(setterArguments)])"
            ])
        }
        while indentation.level > 0 {
            indentation = indentation.dec()
            swift.append(indentation, "}")
        }
        return swift
    }

    private static func swiftJavaDeclarations(forVariableWithName propertyName: String, inType: StatementType? = nil, inSignature: TypeSignature? = nil, bridgable: Bridgable, extends: (Bridgable, Generics)? = nil, options: KotlinBridgeOptions, modifiers: Modifiers, apiFlags: APIFlags, classIdentifier: String, getMethodIdentifier: String, setMethodIdentifier: String) -> [String] {
        guard inType != .protocolDeclaration else {
            return []
        }
        let preEscapedPropertyName = propertyName
        let propertyName = preEscapedPropertyName.fixingKeyword(in: KotlinIdentifier.hardKeywords)
        let callMethodID = inType == nil ? "getStaticMethodID" : "getMethodID"
        let typeString = bridgable.jni(options: options)
        let getParameterString: String
        let setParameterString: String
        if let extends {
            let extendsTypeString = extends.0.kotlinType.jni(options: options)
            getParameterString = extendsTypeString
            setParameterString = "\(extendsTypeString), \(typeString)"
        } else {
            getParameterString = ""
            setParameterString = typeString
        }
        let getMethodID = declareStaticLet(getMethodIdentifier, ofType: "JavaMethodID", in: inSignature, declarationType: inType, value: "\(classIdentifier).\(callMethodID)(name: \"\(propertyName.getterName)\", sig: \"(\(getParameterString))\(typeString)\")!")
        guard apiFlags.options.contains(.writeable) && (modifiers.setVisibility == .default || modifiers.setVisibility >= .public) else {
            return [getMethodID]
        }
        let setMethodID = declareStaticLet(setMethodIdentifier, ofType: "JavaMethodID", in: inSignature, declarationType: inType, value: "\(classIdentifier).\(callMethodID)(name: \"\(propertyName.setterName)\", sig: \"(\(setParameterString))V\")!")
        return [getMethodID, setMethodID]
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
        let swift = "\(modifierString)let \(propertyName.addingBacktickEscapingIfNeeded)\(assignment)"
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

    private func declarationTypeInfo(for statement: KotlinStatement) -> (StatementType, TypeSignature) {
        if let interfaceDeclaration = statement as? KotlinInterfaceDeclaration {
            return (.protocolDeclaration, interfaceDeclaration.signature)
        } else if let classDeclaration = statement as? KotlinClassDeclaration {
            return (classDeclaration.declarationType, classDeclaration.signature)
        } else {
            return (.classDeclaration, .anyObject)
        }
    }

    static func appendCallbackFunction(for variableDeclaration: KotlinVariableDeclaration, bridgable: Bridgable, modifiers: Modifiers) {
        guard variableDeclaration.apiFlags.options.contains(.async) else {
            return
        }
        let callbackFunction = KotlinFunctionDeclaration(name: "callback_" + (variableDeclaration.preEscapedPropertyName ?? variableDeclaration.propertyName))
        let callbackType = bridgable.kotlinType.callbackClosureType(apiFlags: variableDeclaration.apiFlags, kotlin: true)
        callbackFunction.parameters = [Parameter<KotlinExpression>(externalLabel: "f_return_callback", declaredType: callbackType)]
        callbackFunction.returnType = .void
        callbackFunction.modifiers = modifiers
        callbackFunction.role = variableDeclaration.role == .global ? .global : .member
        callbackFunction.isGenerated = true

        var taskSourceCode: [String] = []
        taskSourceCode.append("Task {")
        if variableDeclaration.apiFlags.throwsType == .none {
            taskSourceCode.append(1, "f_return_callback(\(variableDeclaration.propertyName)())")
        } else {
            taskSourceCode.append(1, "try {")
            taskSourceCode.append(2, "f_return_callback(\(variableDeclaration.propertyName)(), null)")
            taskSourceCode.append(1, "} catch(t: Throwable) {")
            taskSourceCode.append(2, "f_return_callback(null, t)")
            taskSourceCode.append(1, "}")
        }
        taskSourceCode.append("}")
        callbackFunction.body = KotlinCodeBlock(statements: taskSourceCode.map { KotlinRawStatement(sourceCode: $0) })
        (variableDeclaration.parent as? KotlinStatement)?.insert(statements: [callbackFunction], after: variableDeclaration)
    }

    private func update(global functionDeclaration: KotlinFunctionDeclaration, uniquifier: Int, swiftDefinitions: inout [SwiftDefinition], globalsClassRef: JavaClassRef) -> Bool {
        guard let bridgable = functionDeclaration.checkBridgable(direction: .toSwift, options: options, translator: translator) else {
            return false
        }
        let bridgableExtends: (Bridgable, Generics)?
        if let extends = functionDeclaration.extends {
            guard let bridgableExtendsType = extends.0.checkBridgable(direction: .toSwift, options: options, generics: extends.1, codebaseInfo: codebaseInfo) else {
                return false
            }
            bridgableExtends = (bridgableExtendsType, extends.1)
        } else {
            bridgableExtends = nil
        }
        if let annotation = functionDeclaration.preventJVMNameManglingAnnotation() {
            functionDeclaration.annotations.append(annotation)
        }

        let name = functionDeclaration.preEscapedName ?? functionDeclaration.name
        let type = functionDeclaration.preEscapedFunctionType
        let modifiers = functionDeclaration.modifiers
        let parameterValues = functionDeclaration.parameters.map(\.defaultValueSwift)
        let methodIdentifier = "Java_\(functionDeclaration.name)_\(uniquifier)_methodID"
        let definitionSwift = Self.swift(forFunctionWithName: name, type: type, generics: functionDeclaration.generics, parameterValues: parameterValues, disambiguatingParameterCount: functionDeclaration.disambiguatingParameterCount, bridgable: bridgable, extends: bridgableExtends, options: options, modifiers: modifiers, attributes: functionDeclaration.attributes, apiFlags: functionDeclaration.apiFlags, targetIdentifier: globalsClassRef.identifier, methodIdentifier: methodIdentifier)
        let javaSwift = Self.swiftJavaDeclarations(forFunctionWithName: name, type: type, disambiguatingParameterCount: functionDeclaration.disambiguatingParameterCount, bridgable: bridgable, extends: bridgableExtends, options: options, modifiers: modifiers, apiFlags: functionDeclaration.apiFlags, classIdentifier: globalsClassRef.identifier, methodIdentifier: methodIdentifier)
        swiftDefinitions.append(SwiftDefinition(statement: functionDeclaration, swift: definitionSwift + javaSwift))
        Self.appendCallbackFunction(for: functionDeclaration, bridgable: bridgable, modifiers: functionDeclaration.modifiers)
        return true
    }

    @discardableResult private func update(member functionDeclaration: KotlinFunctionDeclaration, info: CodebaseInfo.FunctionInfo?, uniquifier: Int, in parentStatement: KotlinStatement, isBridgedSubclass: Bool = false, swiftDefinitions: inout [SwiftDefinition]) -> Bool {
        guard let bridgable = functionDeclaration.checkBridgable(direction: .toSwift, options: options, translator: translator) else {
            return false
        }
        let modifiers = info?.modifiers ?? functionDeclaration.modifiers
        let attributes = info?.attributes ?? functionDeclaration.attributes
        Self.appendCallbackFunction(for: functionDeclaration, bridgable: bridgable, modifiers: modifiers)
        // Don't add Swift for protocol extension members that were merged into Kotlin interface
        guard info != nil || parentStatement.type != .interfaceDeclaration else {
            return true
        }
        if let annotation = functionDeclaration.preventJVMNameManglingAnnotation() {
            functionDeclaration.annotations.append(annotation)
        }

        let (inType, inSignature) = declarationTypeInfo(for: parentStatement)
        let name = (info != nil && info!.name != "init") ? info!.name : (functionDeclaration.preEscapedName ?? functionDeclaration.name)
        let isConstructor = info != nil ? info?.declarationType == .initDeclaration : functionDeclaration.type == .constructorDeclaration
        let isFactory = isConstructor && functionDeclaration.type != .constructorDeclaration
        let type = info?.signature ?? functionDeclaration.preEscapedFunctionType
        let apiFlags = info?.apiFlags ?? functionDeclaration.apiFlags
        let parameterValues = functionDeclaration.parameters.map(\.defaultValueSwift)
        let swift = Self.swift(forMemberFunctionWithName: name, type: type, generics: functionDeclaration.generics, parameterValues: parameterValues, uniquifier: uniquifier, disambiguatingParameterCount: functionDeclaration.disambiguatingParameterCount, isConstructor: isConstructor, isFactory: isFactory, inType: inType, inSignature: inSignature, isBridgedSubclass: isBridgedSubclass, bridgable: bridgable, options: options, modifiers: modifiers, attributes: attributes, apiFlags: apiFlags)
        swiftDefinitions.append(SwiftDefinition(statement: functionDeclaration, swift: swift))
        return true
    }

    private static func swift(forMemberFunctionWithName name: String, type: TypeSignature, generics: Generics, parameterValues: [String?]?, uniquifier: Int, disambiguatingParameterCount: Int, isConstructor: Bool, isFactory: Bool, inType: StatementType, inSignature: TypeSignature, isBridgedSubclass: Bool, bridgable: FunctionBridgable, options: KotlinBridgeOptions, modifiers: Modifiers, attributes: Attributes, apiFlags: APIFlags) -> [String] {
        let isStatic = modifiers.isStatic || isFactory
        let targetIdentifier = isStatic ? "Java_Companion" : "Java_peer"
        let classIdentifier = isStatic ? "Java_Companion_class" : "Java_class"
        let methodIdentifier = isStatic ? "Java_Companion_\(name)_\(uniquifier)_methodID" : "Java_\(name)_\(uniquifier)_methodID"
        let definitionSwift = swift(forFunctionWithName: name, type: type, generics: generics, parameterValues: parameterValues, disambiguatingParameterCount: disambiguatingParameterCount, isConstructor: isConstructor, isFactory: isFactory, inType: inType, isBridgedSubclass: isBridgedSubclass, bridgable: bridgable, options: options, modifiers: modifiers, attributes: attributes, apiFlags: apiFlags, targetIdentifier: targetIdentifier, methodIdentifier: methodIdentifier)
        let javaSwift = swiftJavaDeclarations(forFunctionWithName: name, type: type, disambiguatingParameterCount: disambiguatingParameterCount, isConstructor: isConstructor, isFactory: isFactory, inType: inType, inSignature: inSignature, bridgable: bridgable, options: options, modifiers: modifiers, apiFlags: apiFlags, classIdentifier: classIdentifier, methodIdentifier: methodIdentifier)
        return definitionSwift + javaSwift
    }

    private static func swift(forFunctionWithName name: String, type: TypeSignature, generics: Generics, parameterValues: [String?]?, disambiguatingParameterCount: Int, isDeclaredByVariable: Bool = false, isConstructor: Bool = false, isFactory: Bool = false, inType: StatementType? = nil, isBridgedSubclass: Bool = false, bridgable: FunctionBridgable, extends: (Bridgable, Generics)? = nil, options: KotlinBridgeOptions, modifiers: Modifiers, attributes: Attributes, apiFlags: APIFlags, targetIdentifier: String, methodIdentifier: String) -> [String] {
        var swift: [String] = []
        var indentation: Indentation = 0
        let isViewExtension: Bool
        if let extends {
            swift.append("extension \(extends.0.type)\(extends.1.swiftWhereString) {")
            indentation = indentation.inc()
            isViewExtension = extends.0.strategy == .view && bridgable.return.strategy == .view
        } else {
            isViewExtension = false
        }
        let initialIndentationLevel = indentation.level

        let preEscapedName = name
        let isAsync = apiFlags.options.contains(.async)
        let isThrows = apiFlags.throwsType != .none
        let optionsString = options.jconvertibleOptions

        var modifiers = modifiers
        if inType == .protocolDeclaration {
            modifiers.visibility = .default
        }
        let modifierString = modifiers.swift(isNoOverride: attributes.contains(directive: KotlinDirective.nooverride), suffix: " ")

        let parameterString = type.parameters.enumerated()
            .filter { index, _ in
                bridgable.parameters[index].type != .none
            }
            .map { index, parameter in
                var str = "\(parameter.label ?? "_") p_\(index): \(bridgable.parameters[index].type)"
                if let value = parameterValues?[index], !value.isEmpty {
                    str += " = " + value
                }
                return str
            }
        .joined(separator: ", ")
        var apiOptionsString = isAsync ? " async" : ""
        apiOptionsString += isThrows ? " throws" : ""
        if isDeclaredByVariable {
            var returnString = bridgable.return.type.description
            if inType == .protocolDeclaration {
                returnString += " { get\(apiOptionsString) }"
            } else {
                returnString += " {"
            }
            swift.append(indentation, "\(modifierString)var \(preEscapedName.addingBacktickEscapingIfNeeded): \(returnString)")
            if inType != .protocolDeclaration {
                swift.append(indentation.inc(), "get\(apiOptionsString) {")
            }
        } else {
            let returnString = bridgable.return.type == .void || isFactory ? "" : " -> " + bridgable.return.type.description
            let openBodyString = inType == .protocolDeclaration ? "" : " {"
            swift.append(indentation, modifierString + (isConstructor ? "init" : "func " + preEscapedName.addingBacktickEscapingIfNeeded) + "\(generics.swiftParametersString)(\(parameterString))\(apiOptionsString)\(returnString)\(generics.swiftWhereString)\(openBodyString)")
        }
        guard inType != .protocolDeclaration else {
            return swift
        }
        if isViewExtension {
            indentation = indentation.inc()
            swift.append(indentation, "return SkipSwiftUI.ModifierView(target: self) { target in")
        }

        var returnCallString = ""
        // withCheckedThrowingContinuation requires a 'return' even with void to compile correctly
        if (bridgable.return.type != .void && !isFactory) || (isAsync && isThrows) {
            returnCallString += "return "
        }
        if apiFlags.options.contains(.throws) {
            returnCallString += "try "
        }
        indentation = indentation.inc()
        if isDeclaredByVariable {
            indentation = indentation.inc()
        }
        if isAsync {
            if isThrows {
                swift.append(indentation, returnCallString + "await withCheckedThrowingContinuation { f_continuation in")
            } else {
                swift.append(indentation, returnCallString + "await withCheckedContinuation { f_continuation in")
            }
            let callbackType = bridgable.return.type.callbackClosureType(apiFlags: apiFlags, kotlin: false)
            indentation = indentation.inc()
            if callbackType.parameters.isEmpty {
                swift.append(indentation, "let f_return_callback: \(callbackType) = {")
                swift.append(indentation.inc(), "f_continuation.resume()")
            } else if !isThrows {
                swift.append(indentation, "let f_return_callback: \(callbackType) = { f_return in")
                swift.append(indentation.inc(), "f_continuation.resume(returning: f_return)")
            } else {
                if callbackType.parameters.count == 1 {
                    swift.append(indentation, "let f_return_callback: \(callbackType) = { f_error in")
                } else {
                    swift.append(indentation, "let f_return_callback: \(callbackType) = { f_return, f_error in")
                }
                indentation = indentation.inc()
                swift.append(indentation, "if let f_error {")
                swift.append(indentation.inc(), "f_continuation.resume(throwing: JThrowable.toError(f_error, options: \(optionsString))!)")
                swift.append(indentation, "} else {")
                if callbackType.parameters.count == 1 {
                    swift.append(indentation.inc(), "f_continuation.resume()")
                } else if bridgable.return.type.isOptional {
                    swift.append(indentation.inc(), "f_continuation.resume(returning: f_return)")
                } else {
                    swift.append(indentation.inc(), "f_continuation.resume(returning: f_return!)")
                }
                swift.append(indentation, "}")
                indentation = indentation.dec()
            }
            swift.append(indentation, "}")
            swift.append(indentation, "jniContext {")
            swift.append(indentation.inc(), "let f_return_callback_java = SwiftClosure\(callbackType.parameters.count).javaObject(for: f_return_callback, options: \(optionsString)).toJavaParameter(options: \(optionsString))")
        } else {
            returnCallString += "jniContext {"
            if isConstructor && inType == .enumDeclaration {
                swift.append(indentation, "self = " + returnCallString)
            } else if isConstructor && isBridgedSubclass {
                swift.append(indentation, "let Java_peer = " + returnCallString)
            } else if isConstructor {
                swift.append(indentation, "Java_peer = " + returnCallString)
            } else {
                swift.append(indentation, returnCallString)
            }
        }
        indentation = indentation.inc()

        if inType == .structDeclaration && modifiers.isMutating {
            swift.append(indentation, swiftToCopyJavaPeer(options: options))
        }

        var javaParameterNames: [String] = []
        if let extends {
            let value = isViewExtension ? "target" : "self"
            let name = isViewExtension ? "target_java" : "self_java"
            javaParameterNames.append(name)
            swift.append(indentation, "let \(name) = \(extends.0.kotlinType.convertToJava(value: value, strategy: extends.0.strategy, options: options)).toJavaParameter(options: \(optionsString))")
        }
        for (index, bridgable) in bridgable.parameters.enumerated() {
            let label = "p_\(index)"
            let name = label + "_java"
            javaParameterNames.append(name)
            if bridgable.type == .none {
                swift.append(indentation, "let \(name) = JavaParameter(l: nil)")
            } else {
                let strategy = bridgable.strategy
                swift.append(indentation, "let \(name) = " + bridgable.type.convertToJava(value: label, strategy: strategy, options: options) + ".toJavaParameter(options: \(optionsString))")
            }
        }
        for i in 0..<disambiguatingParameterCount {
            let name = "p_\(bridgable.parameters.count + i)_java"
            javaParameterNames.append(name)
            swift.append(indentation, "let \(name) = JavaParameter(l: nil)")
        }

        let tryType = isThrows && !isAsync ? "try" : "try!"
        if isConstructor {
            if inType == .enumDeclaration {
                swift.append(indentation, "let f_return_java: JavaObjectPointer = \(tryType) Self.Java_Companion.call(method: Self.\(methodIdentifier), options: \(optionsString), args: [" + javaParameterNames.joined(separator: ", ") + "])")
                swift.append(indentation, "return Self.fromJavaObject(f_return_java, options: \(optionsString))")
            } else {
                swift.append(indentation, "let ptr = \(tryType) Self.Java_class.create(ctor: Self.\(methodIdentifier), options: \(optionsString), args: [" + javaParameterNames.joined(separator: ", ") + "])")
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
            let call = "\(tryType) \(targetIdentifier).\(callType)(method: \(callMethod), options: \(optionsString), args: [\(argumentsString)])"
            swift.append(indentation, call)
        } else {
            let callType = inType == nil ? "callStatic" : "call"
            let callMethod = inType == nil || modifiers.isStatic ? methodIdentifier : "Self." + methodIdentifier
            let call = "\(tryType) \(targetIdentifier).\(callType)(method: \(callMethod), options: \(optionsString), args: [" + javaParameterNames.joined(separator: ", ") + "])"
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
                swift.append(indentation, "} catch let error as (Error & JConvertible) {")
                swift.append(indentation.inc(), "throw error")
                swift.append(indentation, "} catch {")
                swift.append(indentation.inc(), "fatalError(String(describing: error))")
                swift.append(indentation, "}")
            }
        }
        while indentation.level > 0 {
            if indentation.level == initialIndentationLevel + 1 && isConstructor && isBridgedSubclass {
                swift.append(1, "super.init(Java_peer: Java_peer)")
            }
            indentation = indentation.dec()
            swift.append(indentation, "}")
        }
        return swift
    }

    private static func swiftJavaDeclarations(forFunctionWithName name: String, type: TypeSignature, disambiguatingParameterCount: Int, isConstructor: Bool = false, isFactory: Bool = false, inType: StatementType? = nil, inSignature: TypeSignature? = nil, bridgable: FunctionBridgable, extends: (Bridgable, Generics)? = nil, options: KotlinBridgeOptions, modifiers: Modifiers, apiFlags: APIFlags, classIdentifier: String, methodIdentifier: String) -> [String] {
        guard inType != .protocolDeclaration else {
            return []
        }
        let preEscapedName = name
        let name = preEscapedName.fixingKeyword(in: KotlinIdentifier.hardKeywords)
        let isAsync = apiFlags.options.contains(.async)

        let getType = inType == nil ? "getStaticMethodID" : "getMethodID"
        var kotlinParameters = bridgable.parameters.map { TypeSignature.Parameter(type: $0.isGenericEntry ? TypeSignature.any : $0.kotlinType) }
        if var extendsType = extends?.0.kotlinType {
            if modifiers.isStatic {
                extendsType = .member(extendsType, .named("Companion", []))
            }
            kotlinParameters.insert(TypeSignature.Parameter(type: extendsType), at: 0)
        }
        kotlinParameters += Array(repeating: TypeSignature.Parameter(type: .javaVoid(kotlin: true)), count: disambiguatingParameterCount)
        let functionName: String
        let kotlinReturnType: TypeSignature
        if isConstructor && !isFactory {
            functionName = "<init>"
            kotlinReturnType = .void
        } else if isAsync {
            functionName = "callback_" + preEscapedName
            let callbackType = bridgable.return.isGenericEntry ? TypeSignature.any.asOptional(bridgable.return.kotlinType.isOptional) : bridgable.return.kotlinType
            kotlinParameters.append(TypeSignature.Parameter(type: callbackType.callbackClosureType(apiFlags: apiFlags, kotlin: true)))
            kotlinReturnType = .void
        } else {
            functionName = name
            kotlinReturnType = bridgable.return.isGenericEntry ? TypeSignature.any.asOptional(bridgable.return.kotlinType.isOptional) : bridgable.return.kotlinType
        }
        let kotlinType: TypeSignature = .function(kotlinParameters, kotlinReturnType, APIFlags(), nil)
        let methodID = declareStaticLet(methodIdentifier, ofType: "JavaMethodID", in: inSignature, declarationType: inType, value: "\(classIdentifier).\(getType)(name: \"\(functionName)\", sig: \"" + kotlinType.jni(options: options, isFunctionDeclaration: true) + "\")!")
        return [methodID]
    }

    static func appendCallbackFunction(for functionDeclaration: KotlinFunctionDeclaration, bridgable: FunctionBridgable, modifiers: Modifiers) {
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

    private static func invocationSourceCode(for functionDeclaration: KotlinFunctionDeclaration) -> String {
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
        let optionsString = options.jconvertibleOptions
        var sourceCode: [String] = []
        sourceCode.append("\(modifiersString)func ==(lhs: \(type), rhs: \(type)) -> Bool {")
        sourceCode.append(1, "return jniContext {")
        sourceCode.append(2, "let lhs_java = lhs.toJavaObject(options: \(optionsString))!")
        sourceCode.append(2, "let rhs_java = rhs.toJavaParameter(options: \(optionsString))")
        sourceCode.append(2, "return try! Bool.call(Java_isequal_methodID, on: lhs_java, options: \(optionsString), args: [rhs_java])")
        sourceCode.append(1, "}")
        sourceCode.append("}")
        sourceCode.append(declareStaticLet("Java_isequal_methodID", ofType: "JavaMethodID", in: type, value: "Java_class.getMethodID(name: \"equals\", sig: \"(Ljava/lang/Object;)Z\")!"))
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
        sourceCode.append(declareStaticLet("Java_hashCode_methodID", ofType: "JavaMethodID", in: type, value: "Java_class.getMethodID(name: \"hashCode\", sig: \"()I\")!"))
        return sourceCode
    }

    private func updateLessThanDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, in classDeclaration: KotlinClassDeclaration, info: CodebaseInfo.FunctionInfo?, swiftDefinitions: inout [SwiftDefinition]) {
        let modifiers = info?.modifiers ?? functionDeclaration.modifiers
        let swift = Self.swift(forLessThanDeclarationIn: classDeclaration.signature, options: options, modifiers: modifiers)
        swiftDefinitions.append(SwiftDefinition(statement: functionDeclaration, swift: swift))
    }

    private static func swift(forLessThanDeclarationIn type: TypeSignature, options: KotlinBridgeOptions, modifiers: Modifiers) -> [String] {
        let modifiersString = modifiers.swift(suffix: " ")
        let optionsString = options.jconvertibleOptions
        var sourceCode: [String] = []
        sourceCode.append("\(modifiersString)func <(lhs: \(type), rhs: \(type)) -> Bool {")
        sourceCode.append(1, "return jniContext {")
        sourceCode.append(2, "let lhs_java = lhs.toJavaObject(options: \(optionsString))!")
        sourceCode.append(2, "let rhs_java = rhs.toJavaParameter(options: \(optionsString))")
        sourceCode.append(2, "let f_return_java = try! Int32.call(Java_compareTo_methodID, on: lhs_java, options: \(optionsString), args: [rhs_java])")
        sourceCode.append(2, "return f_return_java < 0")
        sourceCode.append(1, "}")
        sourceCode.append("}")
        sourceCode.append(declareStaticLet("Java_compareTo_methodID", ofType: "JavaMethodID", in: type, value: "Java_class.getMethodID(name: \"compareTo\", sig: \"(Ljava/lang/Object;)I\")!"))
        return sourceCode
    }

    private func update(_ classDeclaration: KotlinClassDeclaration, swiftDefinitions: inout [SwiftDefinition]) {
        guard classDeclaration.checkBridgable(direction: .toSwift, options: options, translator: translator) else {
            return
        }
        let typeInfos = codebaseInfo.typeInfos(forNamed: classDeclaration.signature)
        guard let primaryTypeInfo = typeInfos.first(where: { $0.declarationType != .extensionDeclaration }) else {
            classDeclaration.messages.append(.kotlinBridgeMissingInfo(classDeclaration, source: translator.syntaxTree.source))
            return
        }
        let superclassInfo = classDeclaration.superclassInfo(translator: translator)
        let isBridgedSubclass = superclassInfo?.attributes.isBridgeToSwift == true
        if let superclassInfo {
            guard !superclassInfo.attributes.isBridgeToKotlin else {
                classDeclaration.messages.append(.kotlinBridgeSuperclassBridging(classDeclaration, source: translator.syntaxTree.source))
                return
            }
            guard !superclassInfo.attributes.isBridgeToSwift || (classDeclaration.generics.isEmpty && superclassInfo.generics.isEmpty) else {
                classDeclaration.messages.append(.kotlinBridgeUnsupportedFeature(classDeclaration, feature: "inheritance of generic classes", source: translator.syntaxTree.source))
                return
            }
        }

        var isView = false
        let inherits = typeInfos.flatMap(\.inherits).flatMap { (inherit: TypeSignature) -> [TypeSignature] in
            let inherit = inherit.withGenerics([])
            if inherit.swiftUIType == .view, codebaseInfo.global.moduleName != "SkipUI" {
                isView = true
                return [.skipUIView, .skipSwiftUIView, .skipSwiftUIBridging]
            }
            guard inherit.isEquatable || inherit.isHashable || inherit.isComparable || inherit.isSendable || inherit.checkBridgable(direction: .toSwift, options: options, generics: classDeclaration.generics, codebaseInfo: codebaseInfo) != nil else {
                return []
            }
            if inherit.isNamed("java.lang.Object") {
                return [.named("NSObject", [])]
            }
            return [inherit]
        }

        var memberDefinitions: [SwiftDefinition] = []
        var hasBridgedStaticMembers = false
        var hasEqualsDefinition = false
        var hasHashDefinition = false
        var functionCount = 0
        var enumCases: [KotlinEnumCaseDeclaration] = []
        let bridgeMemberVisibility = classDeclaration.attributes.isBridgeMembers ? classDeclaration.modifiers.visibility : nil
        for member in classDeclaration.members {
            if let enumCaseDeclaration = member as? KotlinEnumCaseDeclaration {
                if update(member: enumCaseDeclaration, swiftDefinitions: &memberDefinitions) {
                    enumCases.append(enumCaseDeclaration)
                }
            } else if let variableDeclaration = member as? KotlinVariableDeclaration {
                guard !variableDeclaration.isGenerated else {
                    continue
                }
                guard !isView || variableDeclaration.propertyName != "body" else {
                    // We add our own View contract implementation
                    continue
                }
                guard isBridging(attributes: variableDeclaration.attributes, visibility: variableDeclaration.modifiers.visibility, bridgeMemberVisibility: bridgeMemberVisibility, autoBridge: syntaxTree.isBridgeFile ? .internal : syntaxTree.autoBridge) else {
                    continue
                }
                let info = typeInfos.flatMap({ $0.variables }).first(where: { $0.name == (variableDeclaration.preEscapedPropertyName ?? variableDeclaration.propertyName) && $0.modifiers.visibility >= .fileprivate })
                if update(member: variableDeclaration, info: info, in: classDeclaration, swiftDefinitions: &memberDefinitions) {
                    if variableDeclaration.isStatic {
                        hasBridgedStaticMembers = true
                    }
                }
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                guard !functionDeclaration.isGenerated || functionDeclaration.type == .constructorDeclaration else {
                    continue
                }
                guard isBridging(attributes: functionDeclaration.attributes, visibility: functionDeclaration.modifiers.visibility, bridgeMemberVisibility: bridgeMemberVisibility, autoBridge: syntaxTree.isBridgeFile ? .internal : syntaxTree.autoBridge) else {
                    continue
                }
                // Don't attempt to bridge @Composable functions
                guard !syntaxTree.isBridgeFile || !isComposeFunction(functionDeclaration, in: classDeclaration) else {
                    continue
                }
                guard !functionDeclaration.isEncode && !functionDeclaration.isDecodableConstructor else {
                    continue
                }
                let info = typeInfos.flatMap({ $0.functions }).first(where: { (($0.declarationType == .initDeclaration && functionDeclaration.type == .constructorDeclaration) || $0.name == (functionDeclaration.preEscapedName ?? functionDeclaration.name)) && $0.signature == functionDeclaration.functionType && $0.modifiers.visibility >= .fileprivate })
                if functionDeclaration.isEqualImplementation {
                    hasEqualsDefinition = true
                    updateEqualsDeclaration(functionDeclaration, in: classDeclaration, info: info, swiftDefinitions: &memberDefinitions)
                } else if functionDeclaration.isHashImplementation {
                    hasHashDefinition = true
                    updateHashDeclaration(functionDeclaration, in: classDeclaration, info: info, swiftDefinitions: &memberDefinitions)
                } else if functionDeclaration.isLessThanImplementation {
                    updateLessThanDeclaration(functionDeclaration, in: classDeclaration, info: info, swiftDefinitions: &memberDefinitions)
                } else {
                    if update(member: functionDeclaration, info: info, uniquifier: functionCount, in: classDeclaration, isBridgedSubclass: isBridgedSubclass, swiftDefinitions: &memberDefinitions) {
                        functionCount += 1
                        if functionDeclaration.isStatic {
                            hasBridgedStaticMembers = true
                        }
                    }
                }
            }
        }

        let classRef = JavaClassRef(for: classDeclaration.signature, packageName: translator.packageName)
        let isEnum = classDeclaration.declarationType == .enumDeclaration
        let isEmptyEnum = isEnum && enumCases.isEmpty
        let isStruct = classDeclaration.declarationType == .structDeclaration
        let isActor = classDeclaration.declarationType == .actorDeclaration
        let visibilityString = primaryTypeInfo.modifiers.visibility.swift(suffix: " ")
        let modifiersString = primaryTypeInfo.declarationType == .classDeclaration && primaryTypeInfo.modifiers.isFinal ? "final " : ""
        let optionsString = options.jconvertibleOptions
        var inheritsString = inherits.map { $0.description }.joined(separator: ", ")
        if !isEmptyEnum && !isBridgedSubclass {
            if !inheritsString.isEmpty {
                inheritsString += ", "
            }
            inheritsString += "BridgedFromKotlin"
        }
        if classDeclaration.declarationType == .classDeclaration, classDeclaration.modifiers.isFinal || !classDeclaration.generics.isEmpty {
            if !inheritsString.isEmpty {
                inheritsString += ", "
            }
            inheritsString += "BridgedFinalClass"
        }
        let whereString = classDeclaration.generics.swiftWhereString
        if !inheritsString.isEmpty || !whereString.isEmpty {
            inheritsString = ": " + inheritsString
        }
        var swift: [String] = []
        swift.append("\(visibilityString)\(modifiersString)\(isEnum ? "enum" : isStruct ? "struct" : isActor ? "actor" : "class") \(classDeclaration.name)\(classDeclaration.generics.swiftParametersString)\(inheritsString)\(whereString) {")

        let finalMemberVisibility = min(primaryTypeInfo.modifiers.visibility, .public)
        let finalMemberVisibilityString = finalMemberVisibility.swift(suffix: " ")
        if !isEmptyEnum || hasBridgedStaticMembers {
            swift.append(1, classRef.declaration())
        }
        if !isEmptyEnum {
            if isEnum {
                swift.append(1, "nonisolated private var Java_peer: JavaObjectPointer {")
                swift.append(2, "return toJavaObject(options: \(optionsString))!")
                swift.append(1, "}")
            } else {
                if !isBridgedSubclass {
                    swift.append(1, "nonisolated \(finalMemberVisibilityString)\(isStruct ? "var" : "let") Java_peer: JObject")
                }
                swift.append(1, "nonisolated \(finalMemberVisibilityString)\(isStruct || isActor ? "" : "required ")init(Java_ptr: JavaObjectPointer) {")
                if isBridgedSubclass {
                    swift.append(2, "super.init(Java_ptr: Java_ptr)")
                } else {
                    swift.append(2, "Java_peer = JObject(Java_ptr)")
                }
                swift.append(1, "}")

                if primaryTypeInfo.declarationType == .classDeclaration && (isBridgedSubclass || !primaryTypeInfo.modifiers.isFinal) {
                    // Create a constructor allowing subclasses to set the peer directly
                    if isBridgedSubclass {
                        swift.append(1, "nonisolated \(finalMemberVisibilityString)override init(Java_peer: JObject) {")
                        swift.append(2, "super.init(Java_peer: Java_peer)")
                    } else {
                        swift.append(1, "nonisolated \(finalMemberVisibilityString)init(Java_peer: JObject) {")
                        swift.append(2, "self.Java_peer = Java_peer")
                    }
                    swift.append(1, "}")
                }

                let hasConstructors = classDeclaration.members.contains(where: { $0.type == .constructorDeclaration && ($0 as? KotlinFunctionDeclaration)?.isDecodableConstructor == false })
                if !hasConstructors {
                    swift.append(1, "\(finalMemberVisibilityString)init() {")
                    if isBridgedSubclass {
                        swift.append(2, "let Java_peer = jniContext {")
                    } else {
                        swift.append(2, "Java_peer = jniContext {")
                    }
                    swift.append(3, [
                        "let ptr = try! Self.Java_class.create(ctor: Self.Java_constructor_methodID, options: \(optionsString), args: [])",
                        "return JObject(ptr)"
                    ])
                    swift.append(2, "}")
                    if isBridgedSubclass {
                        swift.append(2, "super.init(Java_peer: Java_peer)")
                    }
                    swift.append(1, [
                        "}",
                        declareStaticLet("Java_constructor_methodID", ofType: "JavaMethodID", in: classDeclaration.signature, value: "Java_class.getMethodID(name: \"<init>\", sig: \"()V\")!")
                    ])
                }
            }
        }

        if classDeclaration.inherits.contains(.named("MutableStruct", [])) {
            swift.append(1, declareStaticLet("Java_scopy_methodID", ofType: "JavaMethodID", in: classDeclaration.signature, value: "Java_class.getMethodID(name: \"scopy\", sig: \"()Lskip/lib/MutableStruct;\")!"))
        }
        if hasBridgedStaticMembers || classDeclaration.isSealedClassesEnum {
            swift.append(1, declareStaticLet("Java_Companion_class", ofType: "JClass", in: classDeclaration.signature, value: "try! JClass(name: \"\(classRef.className)$Companion\")"))
            swift.append(1, declareStaticLet("Java_Companion", ofType: "JObject", in: classDeclaration.signature, value: "JObject(Java_class.getStatic(field: Java_class.getStaticFieldID(name: \"Companion\", sig: \"L\(classRef.className)$Companion;\")!, options: \(optionsString)))"))
        }
        if inherits.contains(where: { $0.isHashable }) {
            if !hasEqualsDefinition {
                swift.append(1, Self.swift(forEqualsFunctionIn: classDeclaration.signature, options: options, modifiers: Modifiers(visibility: classDeclaration.modifiers.visibility, isStatic: true)))
            }
            if !hasHashDefinition {
                swift.append(1, Self.swift(forHashFunctionIn: classDeclaration.signature, options: options, modifiers: Modifiers(visibility: classDeclaration.modifiers.visibility)))
            }
        } else if inherits.contains(where: { $0.isEquatable }) {
            if !hasEqualsDefinition {
                swift.append(1, Self.swift(forEqualsFunctionIn: classDeclaration.signature, options: options, modifiers: Modifiers(visibility: classDeclaration.modifiers.visibility, isStatic: true)))
            }
        }
        if !isEmptyEnum {
            if isEnum {
                let caseBridgables = enumCases.compactMap({ $0.checkBridgable(direction: .toSwift, options: options, translator: translator) })
                swift.append(1, Self.swiftForEnumJConvertibleContract(className: classRef.className, generics: classRef.generics, isSealedClassesEnum: classDeclaration.isSealedClassesEnum, caseDeclarations: enumCases, bridgables: caseBridgables, visibility: finalMemberVisibility, options: options, translator: translator))
            } else if !isBridgedSubclass {
                swift.append(1, Self.swiftForJConvertibleContract(in: classDeclaration.declarationType, visibility: finalMemberVisibility))
            }
        }
        if isView {
            swift.append(1, "\(finalMemberVisibilityString)typealias Body = Never")
            swift.append(1, "nonisolated \(finalMemberVisibilityString)var Java_view: any SkipUI.View {")
            swift.append(2, "return self")
            swift.append(1, "}")
        }

        let definition = swiftDefinition(of: classDeclaration.signature, statement: classDeclaration, swift: swift, members: memberDefinitions)
        swiftDefinitions.append(definition)

        if !isEmptyEnum {
            // Make bridged Kotlin types implement `SwiftProjecting`
            let cdeclFunction = Self.addSwiftProjecting(to: classDeclaration, isBridgedSubclass: isBridgedSubclass, options: options, translator: translator)
            swiftDefinitions.append(SwiftDefinition { output, indentation, _ in
                cdeclFunction.append(to: output, indentation: indentation)
            })
        }
    }

    private func isComposeFunction(_ functionDeclaration: KotlinFunctionDeclaration, in classDeclaration: KotlinClassDeclaration) -> Bool {
        guard !functionDeclaration.attributes.attributes.contains(where: { $0.signature.isNamed("Composable") }) else {
            return true
        }
        // Special case ConentModifier.modify
        guard functionDeclaration.name != "modify" || !classDeclaration.inherits.contains(where: { $0.isNamed("ContentModifier", moduleName: "SkipUI", generics: []) }) else {
            return true
        }
        return false
    }

    static func addSwiftProjecting(to classDeclaration: KotlinClassDeclaration, isBridgedSubclass: Bool, customProjection: [String]? = nil, options: KotlinBridgeOptions, translator: KotlinTranslator) -> CDeclFunction {
        if !isBridgedSubclass {
            classDeclaration.inherits.append(.named("skip.lib.SwiftProjecting", []))
        }

        // prevent renaming by R8/Proguard, which would break accessing the class by name from the Swift side
        classDeclaration.addKeepAnnotation()

        let projectionFunc = KotlinFunctionDeclaration(name: "Swift_projection")
        let externalName = "Swift_projectionImpl"
        projectionFunc.parameters = [Parameter<KotlinExpression>(externalLabel: "options", declaredType: .int)]
        projectionFunc.returnType = .function([], .any, APIFlags(), nil)
        projectionFunc.extras = .singleNewline
        projectionFunc.modifiers.visibility = .public
        projectionFunc.modifiers.isOverride = true
        projectionFunc.body = KotlinCodeBlock(statements: [
            KotlinRawStatement(sourceCode: "return \(externalName)(options)")
        ])
        classDeclaration.insert(statements: [projectionFunc], after: classDeclaration.members.last)

        let externalFunc = KotlinRawStatement(sourceCode: "private external fun \(externalName)(options: Int): () -> Any")
        classDeclaration.insert(statements: [externalFunc], after: projectionFunc)

        let (cdecl, cdeclName) = CDeclFunction.declaration(for: classDeclaration, isCompanion: false, name: externalName, translator: translator)
        let cdeclSignature: TypeSignature = .function([TypeSignature.Parameter(label: "options", type: .int32)], .javaObjectPointer, APIFlags(), nil)
        var swift: [String] = []
        if let customProjection {
            swift += customProjection
        } else {
            let constrainedSignature = classDeclaration.signature.constrainedTypeWithGenerics(classDeclaration.generics)
            swift.append("let projection = \(constrainedSignature).fromJavaObject(Java_target, options: JConvertibleOptions(rawValue: Int(options)))")
        }
        swift += [
            "let factory: () -> Any = { projection }",
            "return " + projectionFunc.returnType.convertToJava(value: "factory", strategy: .direct, options: options)
        ]
        return CDeclFunction(name: cdeclName, cdecl: cdecl, signature: cdeclSignature, body: swift)
    }

    private func updateContentComposer(_ classDeclaration: KotlinClassDeclaration) -> Bool {
        guard classDeclaration.inherits.contains(where: { $0.isNamed("ContentComposer", moduleName: "SkipUI", generics: []) }) else {
            return false
        }
        if let composeFunctionDeclaration = classDeclaration.members.first(where: {
            guard let functionDeclaration = $0 as? KotlinFunctionDeclaration else {
                return false
            }
            return functionDeclaration.name == "Compose" && functionDeclaration.parameters.count == 1 && functionDeclaration.parameters[0].externalLabel == "context" && functionDeclaration.parameters[0].declaredType.isNamed("ComposeContext")
        }) as? KotlinFunctionDeclaration {
            composeFunctionDeclaration.modifiers.isOverride = true
            composeFunctionDeclaration.modifiers.visibility = .public
        }
        return true
    }

    private func swiftDefinition(of signature: TypeSignature, statement: KotlinStatement, swift: [String], members: [SwiftDefinition]) -> SwiftDefinition {
        let definitionSwift: [String]
        let isNested: Bool
        if case .member(let parent, _) = signature {
            var extensionSwift: [String] = ["extension \(parent) {"]
            extensionSwift.append(1, swift)
            definitionSwift = extensionSwift
            isNested = true
        } else {
            definitionSwift = swift
            isNested = false
        }

        let definition = SwiftDefinition(statement: statement, children: members) { output, indentation, children in
            definitionSwift.forEach { output.append(indentation).append($0).append("\n") }
            let childIndentation = Indentation(level: indentation.level + (isNested ? 2 : 1))
            children.forEach { output.append("\n").append($0, indentation: childIndentation) }
            if isNested {
                output.append(indentation.inc()).append("}\n")
            }
            output.append(indentation).append("}\n")
        }
        return definition
    }

    private static func swiftForJConvertibleContract(in statementType: StatementType, visibility: Modifiers.Visibility) -> [String] {
        let visibilityString = visibility.swift(suffix: " ")
        var swift: [String] = []
        swift.append("nonisolated \(visibilityString)static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {")
        swift.append(1, "return .init(Java_ptr: obj!)")
        swift.append("}")
        swift.append("nonisolated \(visibilityString)func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {")
        swift.append(1, "return Java_peer.safePointer()")
        swift.append("}")
        return swift
    }

    /// Return the Swift statements implementing the `JConvertible` contract for an enum.
    ///
    /// - Warning: If this is a sealed classes enum, it will use `Java_Companion_class` and `Java_Companion`. Make sure to declare them.
    static func swiftForEnumJConvertibleContract(className: String, generics: [TypeSignature], isSealedClassesEnum: Bool, caseDeclarations: [KotlinEnumCaseDeclaration], bridgables caseBridgables: [[Bridgable]], visibility: Modifiers.Visibility, options: KotlinBridgeOptions, translator: KotlinTranslator) -> [String] {
        guard caseBridgables.count == caseDeclarations.count else {
            return []
        }

        let visibilityString = visibility.swift(suffix: " ")
        var swift: [String] = []
        var declarations: [String] = []

        swift.append("nonisolated \(visibilityString)static func fromJavaObject(_ obj: JavaObjectPointer?, options: JConvertibleOptions) -> Self {")
        if isSealedClassesEnum {
            swift.append(1, "let className = Java_className(of: obj!, options: options)")
            swift.append(1, "return fromJavaClassName(className, obj!, options: options)")
        } else {
            swift.append(1, "let name: String = try! obj!.call(method: Java_name_methodID, options: options, args: [])")
            swift.append(1, "return fromJavaName(name)")
            declarations.append(declareStaticLet("Java_name_methodID", ofType: "JavaMethodID", in: .named(className, generics), value: "Java_class.getMethodID(name: \"name\", sig: \"()Ljava/lang/String;\")!"))
        }
        swift.append("}")

        if isSealedClassesEnum {
            swift.append("nonisolated fileprivate static func fromJavaClassName(_ className: String, _ obj: JavaObjectPointer, options: JConvertibleOptions) -> Self {")
            swift.append(1, "switch className {")
            for (enumCaseDeclaration, enumCaseBridgables) in zip(caseDeclarations, caseBridgables) {
                let (enumCaseCode, enumCaseDeclarations) = sealedClassesEnumCaseFromJavaClassName(enumCaseDeclaration, bridgables: enumCaseBridgables, inClassName: className, generics: generics, options: options)
                swift.append(1, enumCaseCode)
                declarations += enumCaseDeclarations
            }
            swift.append(1, "default: fatalError()")
            swift.append(1, "}")
            swift.append("}")
        } else {
            swift.append("nonisolated fileprivate static func fromJavaName(_ name: String) -> Self {")
            if caseDeclarations.isEmpty {
                swift.append(1, "fatalError()")
            } else {
                swift.append(1, "return switch name {")
                for enumCaseDeclaration in caseDeclarations {
                    swift.append(1, "case \"\(enumCaseDeclaration.name)\": .\(enumCaseDeclaration.preEscapedName ?? enumCaseDeclaration.name)")
                }
                swift.append(1, "default: fatalError()")
                swift.append(1, "}")
            }
            swift.append("}")
        }

        swift.append("nonisolated \(visibilityString)func toJavaObject(options: JConvertibleOptions) -> JavaObjectPointer? {")
        if isSealedClassesEnum {
            swift.append(1, "switch self {")
            for (enumCaseDeclaration, enumCaseBridgables) in zip(caseDeclarations, caseBridgables) {
                let (enumCaseCode, enumCaseDeclarations) = sealedClassesEnumCaseToJavaObject(enumCaseDeclaration, bridgables: enumCaseBridgables, inClassName: className, generics: generics, options: options)
                swift.append(1, enumCaseCode)
                declarations += enumCaseDeclarations
            }
            swift.append(1, "}")
        } else {
            if caseDeclarations.isEmpty {
                swift.append(1, "fatalError()")
            } else {
                swift.append(1, "let name = switch self {")
                for enumCaseDeclaration in caseDeclarations {
                    swift.append(1, "case .\(enumCaseDeclaration.preEscapedName ?? enumCaseDeclaration.name): \"\(enumCaseDeclaration.name)\"")
                }
                swift.append(1, "}")
                swift.append(1, "return try! Self.Java_class.callStatic(method: Self.Java_valueOf_methodID, options: options, args: [name.toJavaParameter(options: options)])")
                declarations.append(declareStaticLet("Java_valueOf_methodID", ofType: "JavaMethodID", in: .named(className, generics), value: "Java_class.getStaticMethodID(name: \"valueOf\", sig: \"(Ljava/lang/String;)L\(className);\")!"))
            }
        }
        swift.append("}")

        swift += declarations
        return swift
    }

    /// Return the Swift statements implementing the `JConvertible.toJavaObject` switch on a generic sealed classes enum to
    /// pack it into a Java object.
    ///
    /// - Warning: It will use `Java_Companion_class` and `Java_Companion`. Make sure to declare them.
    static func swiftForGenericEnumToJavaObjectSwitch(className: String, generics: [TypeSignature], peerName: String, caseDeclarations: [KotlinEnumCaseDeclaration], bridgables caseBridgables: [[Bridgable]], visibility: Modifiers.Visibility, options: KotlinBridgeOptions, translator: KotlinTranslator) -> (code: [String], declarations: [String]) {
        guard caseBridgables.count == caseDeclarations.count else {
            return ([], [])
        }
        guard !caseDeclarations.isEmpty else {
            return (["fatalError()"], [])
        }

        var swift: [String] = []
        var declarations: [String] = []
        swift.append("let setSwift_peerMethodID = Self.Java_class.getMethodID(name: \"setSwift_peer\", sig: \"(J)V\")!")
        swift.append("switch self {")
        for (enumCaseDeclaration, enumCaseBridgables) in zip(caseDeclarations, caseBridgables) {
            let (enumCaseCode, enumCaseDeclarations) = sealedClassesEnumCaseToJavaObject(enumCaseDeclaration, bridgables: enumCaseBridgables, inClassName: className, generics: generics, peerName: peerName, setMethodID: "setSwift_peerMethodID", options: options)
            swift += enumCaseCode
            declarations += enumCaseDeclarations
        }
        swift.append("}")
        return (swift, declarations)
    }

    private static func sealedClassesEnumCaseFromJavaClassName(_ enumCaseDeclaration: KotlinEnumCaseDeclaration, bridgables: [Bridgable], inClassName: String, generics: [TypeSignature], options: KotlinBridgeOptions) -> (code: [String], declarations: [String]) {
        var swift: [String] = []

        let caseName = enumCaseDeclaration.preEscapedName ?? enumCaseDeclaration.name
        let caseClassName = inClassName + "$" + KotlinEnumCaseDeclaration.sealedClassName(for: enumCaseDeclaration)
        swift.append("case \"\(caseClassName.replacing("/", with: "."))\":")
        guard !enumCaseDeclaration.associatedValues.isEmpty else {
            swift.append(1, "return .\(caseName)")
            return (swift, [])
        }

        var declarations: [String] = []
        declarations.append(declareStaticLet("Java_\(caseName)_class", ofType: "JClass", in: .named(inClassName, generics), value: "try! JClass(name: \"\(caseClassName)\")"))
        for i in 0..<enumCaseDeclaration.associatedValues.count {
            let associated = "associated\(i)"
            let methodID = "Java_\(caseName)_\(associated)_methodID"
            swift.append(1, "let \(associated)_java: \(bridgables[i].type.java(strategy: bridgables[i].strategy, options: options)) = try! obj.call(method: Self.\(methodID), options: options, args: [])")
            swift.append(1, "let \(associated) = \(bridgables[i].type.convertFromJava(value: associated + "_java", strategy: bridgables[i].strategy, options: options))")
            declarations.append(declareStaticLet(methodID, ofType: "JavaMethodID", in: .named(inClassName, generics), value: "Java_\(caseName)_class.getMethodID(name: \"getAssociated\(i)\", sig: \"()\(bridgables[i].jni(options: options))\")!"))
        }
        let associatedValues = enumCaseDeclaration.associatedValues.enumerated().map { (i, parameter) in
            if let label = parameter.externalLabel {
                return "\(label): associated\(i)"
            } else {
                return "associated\(i)"
            }
        }.joined(separator: ", ")
        swift.append(1, "return .\(caseName)(\(associatedValues))")
        return (swift, declarations)
    }

    private static func sealedClassesEnumCaseToJavaObject(_ enumCaseDeclaration: KotlinEnumCaseDeclaration, bridgables: [Bridgable], inClassName: String, generics: [TypeSignature], peerName: String? = nil, setMethodID: String? = nil, options: KotlinBridgeOptions) -> (code: [String], declarations: [String]) {
        var swift: [String] = []

        let caseName = enumCaseDeclaration.preEscapedName ?? enumCaseDeclaration.name
        var caseDeclaration = "case .\(caseName)"
        if !enumCaseDeclaration.associatedValues.isEmpty {
            caseDeclaration += "(" + (0..<enumCaseDeclaration.associatedValues.count).map { "let associated\($0)" }.joined(separator: ", ") + ")"
        }
        swift.append(caseDeclaration + ":")

        for i in 0..<enumCaseDeclaration.associatedValues.count {
            let conversion = bridgables[i].type.convertToJava(value: "associated\(i)", strategy: bridgables[i].strategy, optionsString: "options")
            swift.append(1, "let associated\(i)_java = \(conversion).toJavaParameter(options: options)")
        }
        let arguments = (0..<enumCaseDeclaration.associatedValues.count).map { "associated\($0)_java" }.joined(separator: ", ")
        let companionCall = "try! Self.Java_Companion.call(method: Self.Java_Companion_\(caseName)_methodID, options: options, args: [\(arguments)])"
        if let peerName, let setMethodID {
            swift.append(1, "let ptr: JavaObjectPointer = \(companionCall)")
            swift.append(1, "try! ptr.call(method: \(setMethodID), options: options, args: [\(peerName).toJavaParameter(options: options)])")
            swift.append(1, "return ptr")
        } else {
            swift.append(1, "return \(companionCall)")
        }

        let methodName = enumCaseDeclaration.associatedValues.isEmpty ? enumCaseDeclaration.name.getterName : enumCaseDeclaration.name
        let signature = "(" + bridgables.map { $0.jni(options: options) }.joined() + ")L" + inClassName + ";"
        let declaration = declareStaticLet("Java_Companion_\(caseName)_methodID", ofType: "JavaMethodID", in: .named(inClassName, generics), value: "Java_Companion_class.getMethodID(name: \"\(methodName)\", sig: \"\(signature)\")!")
        return (swift, [declaration])
    }

    private func update(_ interfaceDeclaration: KotlinInterfaceDeclaration, swiftDefinitions: inout [SwiftDefinition]) {
        guard interfaceDeclaration.checkBridgable(direction: .toSwift, options: options, translator: translator) else {
            return
        }
        guard let primaryTypeInfo = codebaseInfo.primaryTypeInfo(forNamed: interfaceDeclaration.signature) else {
            interfaceDeclaration.messages.append(Message.kotlinBridgeMissingInfo(interfaceDeclaration, source: translator.syntaxTree.source))
            return
        }

        let visibilityString = primaryTypeInfo.modifiers.visibility.swift(suffix: " ")
        let inherits = primaryTypeInfo.inherits.compactMap {
            let inherit = $0.withGenerics([])
            return inherit.isEquatable || inherit.isHashable || inherit.isComparable || inherit.isSendable || inherit.isNamed("NSObjectProtocol") || inherit.checkBridgable(direction: .toSwift, options: options, generics: interfaceDeclaration.generics, codebaseInfo: codebaseInfo) != nil ? inherit : nil
        }
        let inheritsString = inherits.isEmpty ? "" : ": " + inherits.map { $0.description }.joined(separator: ", ")

        var swift: [String] = []
        swift.append("\(visibilityString)protocol \(interfaceDeclaration.name)\(inheritsString) {")

        for entry in interfaceDeclaration.generics.entries {
            swift.append(1, "associatedtype \(entry.name)\(entry.swiftWhereString)")
        }

        var memberDefinitions: [SwiftDefinition] = []
        var functionCount = 0
        let bridgeMemberVisibility = interfaceDeclaration.attributes.isBridgeMembers ? interfaceDeclaration.modifiers.visibility : nil
        for member in interfaceDeclaration.members {
            if let variableDeclaration = member as? KotlinVariableDeclaration {
                guard isBridging(attributes: variableDeclaration.attributes, visibility: interfaceDeclaration.modifiers.visibility, bridgeMemberVisibility: bridgeMemberVisibility, autoBridge: syntaxTree.autoBridge) else {
                    continue
                }
                let info = primaryTypeInfo.variables.first { $0.name == (variableDeclaration.preEscapedPropertyName ?? variableDeclaration.propertyName) }
                update(member: variableDeclaration, info: info, in: interfaceDeclaration, swiftDefinitions: &memberDefinitions)
            } else if let functionDeclaration = member as? KotlinFunctionDeclaration {
                guard isBridging(attributes: functionDeclaration.attributes, visibility: interfaceDeclaration.modifiers.visibility, bridgeMemberVisibility: bridgeMemberVisibility, autoBridge: syntaxTree.autoBridge) else {
                    continue
                }
                let info = primaryTypeInfo.functions.first(where: { $0.name == (functionDeclaration.preEscapedName ?? functionDeclaration.name) && $0.signature == functionDeclaration.functionType && $0.modifiers.visibility >= .fileprivate })
                if update(member: functionDeclaration, info: info, uniquifier: functionCount, in: interfaceDeclaration, swiftDefinitions: &memberDefinitions) {
                    functionCount += 1
                }
            }
        }

        let definition = swiftDefinition(of: interfaceDeclaration.signature, statement: interfaceDeclaration, swift: swift, members: memberDefinitions)
        swiftDefinitions.append(definition)

        if let bridgeImpl = Self.protocolBridgeImplDefinition(forProtocol: interfaceDeclaration.signature, inPackage: translator.packageName, statement: interfaceDeclaration, options: options, autoBridge: syntaxTree.autoBridge, codebaseInfo: codebaseInfo) {
            swiftDefinitions.append(bridgeImpl)
        }
        if let extensionImpl = Self.protocolExtensionDefinition(forProtocol: interfaceDeclaration.signature, inPackage: translator.packageName, options: options, autoBridge: syntaxTree.autoBridge, codebaseInfo: codebaseInfo) {
            swiftDefinitions.append(extensionImpl)
        }
    }

    /// Define an anonymous implementation of a bridged protocol.
    static func protocolBridgeImplDefinition(forProtocol type: TypeSignature, inPackage packageName: String?, statement: KotlinStatement?, options: KotlinBridgeOptions, autoBridge: AutoBridge, codebaseInfo: CodebaseInfo.Context) -> SwiftDefinition? {
        guard let primaryTypeInfo = codebaseInfo.primaryTypeInfo(forNamed: type) else {
            return nil
        }
        let protocolVisibility = min(primaryTypeInfo.modifiers.visibility, .public)
        let protocolSignatures = codebaseInfo.global.protocolSignatures(forNamed: type).dropFirst()
        let bridgeImpl = type.protocolBridgeImpl

        var swift: [String] = []
        let visibilityString = protocolVisibility.swift(suffix: " ")
        swift.append("\(visibilityString)final class \(bridgeImpl): \(type.withGenerics([])), BridgedFromKotlin {")

        let classRef = JavaClassRef(for: type, packageName: packageName)
        swift.append(1, classRef.declaration())
        swift.append(1, "nonisolated \(visibilityString)let Java_peer: JObject")
        swift.append(1, "nonisolated \(visibilityString)required init(Java_ptr: JavaObjectPointer) {")
        swift.append(2, "Java_peer = JObject(Java_ptr)")
        swift.append(1, "}")

        var functionCount = 0
        swift.append(1, self.swift(forProtocolBridgeImplMembers: primaryTypeInfo, visibility: protocolVisibility, options: options, codebaseInfo: codebaseInfo, autoBridge: autoBridge, functionCount: &functionCount))
        var seenProtocolSignatures: Set<TypeSignature> = []
        for protocolSignature in protocolSignatures {
            guard seenProtocolSignatures.insert(protocolSignature).inserted else {
                continue
            }
            if protocolSignature.isEquatable {
                swift.append(1, self.swift(forEqualsFunctionIn: bridgeImpl, options: options, modifiers: Modifiers(visibility: protocolVisibility, isStatic: true)))
            } else if protocolSignature.isHashable {
                swift.append(1, self.swift(forHashFunctionIn: bridgeImpl, options: options, modifiers: Modifiers(visibility: protocolVisibility)))
            } else if protocolSignature.isComparable {
                swift.append(1, self.swift(forLessThanDeclarationIn: bridgeImpl, options: options, modifiers: Modifiers(visibility: protocolVisibility, isStatic: true)))
            } else if let protocolInfo = codebaseInfo.primaryTypeInfo(forNamed: protocolSignature) {
                guard isBridging(attributes: protocolInfo.attributes, visibility: protocolInfo.modifiers.visibility, bridgeMemberVisibility: nil, autoBridge: autoBridge) else {
                    continue
                }
                swift.append(1, self.swift(forProtocolBridgeImplMembers: protocolInfo, visibility: protocolVisibility, options: options, codebaseInfo: codebaseInfo, autoBridge: autoBridge, functionCount: &functionCount))
            }
        }
        swift.append(1, swiftForJConvertibleContract(in: .protocolDeclaration, visibility: protocolVisibility))
        swift.append("}")
        return SwiftDefinition(statement: statement, swift: swift)
    }

    private static func swift(forProtocolBridgeImplMembers info: CodebaseInfo.TypeInfo, visibility: Modifiers.Visibility, options: KotlinBridgeOptions, codebaseInfo: CodebaseInfo.Context, autoBridge: AutoBridge, functionCount: inout Int) -> [String] {
        var swift: [String] = []
        for variableInfo in info.variables {
            swift += self.swift(forProtocolBridgeImplVariable: variableInfo, in: info, visibility: visibility, options: options, codebaseInfo: codebaseInfo, autoBridge: autoBridge)
        }
        for functionInfo in info.functions {
            let functionSwift = self.swift(forProtocolBridgeImplFunction: functionInfo, in: info, visibility: visibility, options: options, codebaseInfo: codebaseInfo, autoBridge: autoBridge, uniquifier: functionCount)
            if !functionSwift.isEmpty {
                swift += functionSwift
                functionCount += 1
            }
        }
        return swift
    }

    private static func swift(forProtocolBridgeImplVariable variableInfo: CodebaseInfo.VariableInfo, in info: CodebaseInfo.TypeInfo, visibility: Modifiers.Visibility, options: KotlinBridgeOptions, codebaseInfo: CodebaseInfo.Context, autoBridge: AutoBridge) -> [String] {
        let bridgeMembersVisibility = info.attributes.isBridgeMembers ? info.modifiers.visibility : nil
        guard isBridging(attributes: variableInfo.attributes, visibility: visibility, bridgeMemberVisibility: bridgeMembersVisibility, autoBridge: autoBridge) else {
            return []
        }
        guard let bridgable = variableInfo.signature.checkBridgable(direction: .any, options: options, generics: info.generics, codebaseInfo: codebaseInfo) else {
            return []
        }
        let inSignature = info.signature.protocolBridgeImpl
        var modifiers = variableInfo.modifiers
        modifiers.visibility = visibility
        return self.swift(forMemberVariableWithName: variableInfo.name, isAppendAsFunction: false, inType: .classDeclaration, inSignature: inSignature, bridgable: bridgable, options: options, modifiers: modifiers, attributes: variableInfo.attributes, apiFlags: variableInfo.apiFlags ?? APIFlags())
    }

    private static func swift(forProtocolBridgeImplFunction functionInfo: CodebaseInfo.FunctionInfo, in info: CodebaseInfo.TypeInfo, visibility: Modifiers.Visibility, options: KotlinBridgeOptions, codebaseInfo: CodebaseInfo.Context, autoBridge: AutoBridge, uniquifier: Int) -> [String] {
        let bridgeMembersVisibility = info.attributes.isBridgeMembers ? info.modifiers.visibility : nil
        guard isBridging(attributes: functionInfo.attributes, visibility: visibility, bridgeMemberVisibility: bridgeMembersVisibility, autoBridge: autoBridge) else {
            return []
        }
        guard let bridgable = functionInfo.signature.checkFunctionBridgable(direction: .any, isConstructor: functionInfo.declarationType == .initDeclaration, options: options, generics: info.generics.merge(overrides: functionInfo.generics, addNew: true), codebaseInfo: codebaseInfo) else {
            return []
        }
        let inSignature = info.signature.protocolBridgeImpl
        var modifiers = functionInfo.modifiers
        modifiers.visibility = visibility
        return self.swift(forMemberFunctionWithName: functionInfo.name, type: functionInfo.signature, generics: functionInfo.generics, parameterValues: nil, uniquifier: uniquifier, disambiguatingParameterCount: 0, isConstructor: false, isFactory: false, inType: .classDeclaration, inSignature: inSignature, isBridgedSubclass: false, bridgable: bridgable, options: options, modifiers: modifiers, attributes: functionInfo.attributes, apiFlags: functionInfo.apiFlags ?? APIFlags())
    }

    private static func protocolExtensionDefinition(forProtocol type: TypeSignature, inPackage packageName: String?, options: KotlinBridgeOptions, autoBridge: AutoBridge, codebaseInfo: CodebaseInfo.Context) -> SwiftDefinition? {
        let extensionInfos = codebaseInfo.typeInfos(forNamed: type).filter { $0.declarationType == .extensionDeclaration && $0.modifiers.visibility >= .default }
        guard !extensionInfos.isEmpty else {
            return nil
        }

        // We combine all extensions into a single definition because having multiple extensions with their own private
        // Java_class and Java_peer causes compile errors
        var swift: [String] = []
        swift.append("extension \(type.withGenerics([])) {")
        let classRef = JavaClassRef(for: type, packageName: packageName)
        swift.append(1, classRef.declaration(declarationType: .extensionDeclaration))
        swift.append(1, "private var Java_peer: JavaObjectPointer { (self as! JConvertible).toJavaObject(options: [])! }")

        var variableCount = 0
        for extensionInfo in extensionInfos {
            for variableInfo in extensionInfo.variables {
                let variableSwift = self.swift(forProtocolExtensionVariable: variableInfo, in: extensionInfo, visibility: min(variableInfo.modifiers.visibility, .public), options: options, codebaseInfo: codebaseInfo, autoBridge: autoBridge)
                if !variableSwift.isEmpty {
                    swift.append(1, variableSwift)
                    variableCount += 1
                }
            }
        }
        var functionCount = 0
        for extensionInfo in extensionInfos {
            for functionInfo in extensionInfo.functions {
                let functionSwift = self.swift(forProtocolExtensionFunction: functionInfo, in: extensionInfo, visibility: min(functionInfo.modifiers.visibility, .public), options: options, codebaseInfo: codebaseInfo, autoBridge: autoBridge, uniquifier: functionCount)
                if !functionSwift.isEmpty {
                    swift.append(1, functionSwift)
                    functionCount += 1
                }
            }
        }
        guard variableCount > 0 || functionCount > 0 else {
            return nil
        }
        swift.append("}")
        return SwiftDefinition(swift: swift)
    }

    private static func swift(forProtocolExtensionVariable variableInfo: CodebaseInfo.VariableInfo, in info: CodebaseInfo.TypeInfo, visibility: Modifiers.Visibility, options: KotlinBridgeOptions, codebaseInfo: CodebaseInfo.Context, autoBridge: AutoBridge) -> [String] {
        let bridgeMembersVisibility = info.attributes.isBridgeMembers ? info.modifiers.visibility : nil
        guard isBridging(attributes: variableInfo.attributes, visibility: visibility, bridgeMemberVisibility: bridgeMembersVisibility, autoBridge: autoBridge) else {
            return []
        }
        guard let bridgable = variableInfo.signature.checkBridgable(direction: .any, options: options, generics: info.generics, codebaseInfo: codebaseInfo) else {
            return []
        }
        var modifiers = variableInfo.modifiers
        modifiers.visibility = visibility
        return self.swift(forMemberVariableWithName: variableInfo.name, isAppendAsFunction: false, inType: .extensionDeclaration, inSignature: info.signature, bridgable: bridgable, options: options, modifiers: modifiers, attributes: variableInfo.attributes, apiFlags: variableInfo.apiFlags ?? APIFlags())
    }

    private static func swift(forProtocolExtensionFunction functionInfo: CodebaseInfo.FunctionInfo, in info: CodebaseInfo.TypeInfo, visibility: Modifiers.Visibility, options: KotlinBridgeOptions, codebaseInfo: CodebaseInfo.Context, autoBridge: AutoBridge, uniquifier: Int) -> [String] {
        let bridgeMembersVisibility = info.attributes.isBridgeMembers ? info.modifiers.visibility : nil
        guard isBridging(attributes: functionInfo.attributes, visibility: visibility, bridgeMemberVisibility: bridgeMembersVisibility, autoBridge: autoBridge) else {
            return []
        }
        guard let bridgable = functionInfo.signature.checkFunctionBridgable(direction: .any, isConstructor: functionInfo.declarationType == .initDeclaration, options: options, generics: info.generics.merge(overrides: functionInfo.generics, addNew: true), codebaseInfo: codebaseInfo) else {
            return []
        }
        var modifiers = functionInfo.modifiers
        modifiers.visibility = visibility
        return self.swift(forMemberFunctionWithName: functionInfo.name, type: functionInfo.signature, generics: functionInfo.generics, parameterValues: nil, uniquifier: uniquifier, disambiguatingParameterCount: 0, isConstructor: false, isFactory: false, inType: .extensionDeclaration, inSignature: info.signature, isBridgedSubclass: false, bridgable: bridgable, options: options, modifiers: modifiers, attributes: functionInfo.attributes, apiFlags: functionInfo.apiFlags ?? APIFlags())
    }

    private func update(_ typealiasDeclaration: KotlinTypealiasDeclaration, swiftDefinitions: inout [SwiftDefinition]) {
        guard let bridgable = typealiasDeclaration.aliasedType.checkBridgable(direction: .toSwift, options: options, generics: typealiasDeclaration.generics, codebaseInfo: codebaseInfo, sourceDerived: typealiasDeclaration, source: syntaxTree.source) else {
            return
        }

        let visibilityString = typealiasDeclaration.modifiers.visibility.swift(suffix: " ")
        let genericsString: String
        if typealiasDeclaration.generics.isEmpty {
            genericsString = ""
        } else {
            genericsString = "<" + typealiasDeclaration.generics.entries.map(\.name).joined(separator: ", ") + ">"
        }
        let swift = "\(visibilityString)typealias \(typealiasDeclaration.name)\(genericsString) = \(bridgable.type)"
        let definition = SwiftDefinition(statement: typealiasDeclaration, swift: [swift])
        swiftDefinitions.append(definition)
    }
}
