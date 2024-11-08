/// Used in Swift code generation.
struct SwiftDefinition: OutputNode {
    let sourceFile: Source.FilePath?
    let sourceRange: Source.Range?
    var children: [SwiftDefinition] = []
    var appendTo: (OutputGenerator, Indentation, [SwiftDefinition]) -> Void = { output, indentation, children in
        children.forEach { $0.append(to: output, indentation: indentation) }
    }

    init(statement: SourceDerived? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, children: [SwiftDefinition] = [], appendTo: ((OutputGenerator, Indentation, [SwiftDefinition]) -> Void)? = nil) {
        self.sourceFile = sourceFile ?? statement?.sourceFile
        self.sourceRange = sourceRange ?? statement?.sourceRange
        self.children = children
        if let appendTo {
            self.appendTo = appendTo
        }
    }

    init(statement: SourceDerived? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, swift: [String]) {
        self = .init(statement: statement, sourceFile: sourceFile, sourceRange: sourceRange) { output, indentation, _ in
            swift.forEach { output.append(indentation).append($0).append("\n") }
        }
    }

    func leadingTrivia(indentation: Indentation) -> String {
        return ""
    }

    func trailingTrivia(indentation: Indentation) -> String {
        return ""
    }

    func append(to output: OutputGenerator, indentation: Indentation) {
        appendTo(output, indentation, children)
    }
}

/// Utilities for declaring a JNI class reference.
struct JavaClassRef {
    let identifier: String
    let className: String
    let isFileClass: Bool

    init(for classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) {
        let className: String
        if let packageName = translator.packageName {
            className = packageName.replacing(".", with: "/") + "/" + classDeclaration.name
        } else {
            className = classDeclaration.name
        }
        self.identifier = "Java_class"
        self.className = className
        self.isFileClass = false
    }

    init(forFile translator: KotlinTranslator) {
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
        self.identifier = "Java_" + identifier
        self.className = className
        self.isFileClass = true
    }

    var declaration: String {
        return (isFileClass ? "private let " : "private static let ") + identifier + " = try! JClass(name: \"\(className)\")"
    }
}

extension Source.FilePath {
    /// Return the JNI class name for this file in the given package.
    func jniClassName(packageName: String?) -> String {
        let name = self.name.dropLast(self.extension.count) + "Kt"
        guard let packageName, !packageName.isEmpty else {
            return String(name)
        }
        return packageName + "." + name
    }
}

extension String {
    /// Escape special characters for use in a `@_cdecl` declaration.
    ///
    /// - Warning: Assumes this is an identifier string that does not contain illegal identifier characters like `;`
    var cdeclEscaped: String {
        // TODO: Unicode chars
        return replacing("_", with: "_1").replacing("$", with: "_00024")
    }
}

extension TypeSignature {
    static let javaObjectPointer: TypeSignature = .named("JavaObjectPointer", [])
    static let javaString: TypeSignature = .named("JavaString", [])
    static func swiftObjectPointer(java: Bool) -> TypeSignature {
        return java ? .named("skip.bridge.SwiftObjectPointer", []) : .named("SwiftObjectPointer", [])
    }

    /// The generated native type when the bridging strategy is unknown - e.g. for protocols.
    var unknownBridgeImpl: TypeSignature {
        return withName(name + "_BridgeImpl")
    }

    /// Return the `@_cdecl` function equivalent of this type.
    func cdecl(strategy: Bridgable.Strategy) -> TypeSignature {
        switch self {
        case .function:
            return .javaObjectPointer
        case .int:
            return .int32
        case .optional(let type):
            return type == .string ? .optional(.javaString) : .optional(.javaObjectPointer)
        case .string:
            return .javaString
        case .unwrappedOptional(let type):
            return type.cdecl(strategy: strategy)
        default:
            return strategy == .direct ? self : .javaObjectPointer
        }
    }

    /// Return code that converst the given value of this type to its `@_cdecl` function form.
    func convertToCDecl(value: String, strategy: Bridgable.Strategy) -> String {
        switch self.asOptional(false) {
        case .function(let parameters, _, _, _):
            let converted = "SwiftClosure\(parameters.count).javaObject(for: \(value))"
            return isOptional ? converted : converted + "!"
        case .int:
            if isOptional {
                return value + ".toJavaObject()"
            } else {
                return "Int32(\(value))"
            }
        case .string:
            let converted = value + ".toJavaObject()"
            return isOptional ? converted : converted + "!"
        case .unwrappedOptional(let type):
            return type.convertToCDecl(value: value, strategy: strategy)
        default:
            if strategy == .direct && !isOptional {
                return value
            } else if strategy == .unknown {
                let converted = "((\(value) as? JConvertible)?.toJavaObject())"
                return isOptional ? converted : converted + "!"
            } else {
                let converted = value + ".toJavaObject()"
                return isOptional ? converted : converted + "!"
            }
        }
    }

    /// Return code that converts the given value of our `@_cdecl` function type back to this type.
    func convertFromCDecl(value: String, strategy: Bridgable.Strategy) -> String {
        guard strategy != .unknown else {
            return self.unknownBridgeImpl.description + ".fromJavaObject(\(value))"
        }
        switch self.asOptional(false) {
        case .function(let parameters, _, _, _):
            let converted = "SwiftClosure\(parameters.count).closure(forJavaObject: \(value))"
            return isOptional ? converted : converted + "!"
        case .int:
            if isOptional {
                return description + ".fromJavaObject(\(value))"
            } else {
                return "Int(\(value))"
            }
        case .string:
            return description + ".fromJavaObject(\(value))"
        case .unwrappedOptional(let type):
            return type.convertFromCDecl(value: value, strategy: strategy)
        default:
            if strategy == .direct && !isOptional {
                return value
            } else {
                return description + ".fromJavaObject(\(value))"
            }
        }
    }

    /// Return the Java equivalent of this type.
    func java(strategy: Bridgable.Strategy) -> TypeSignature {
        switch self {
        case .function:
            return .javaObjectPointer
        case .int:
            return .int32
        case .optional:
            return .optional(.javaObjectPointer)
        case .unwrappedOptional(let type):
            return type.java(strategy: strategy)
        default:
            return strategy == .direct ? self : .javaObjectPointer
        }
    }

    /// Return code that converts the given value of this type to its Java form.
    func convertToJava(value: String, strategy: Bridgable.Strategy) -> String {
        switch self.asOptional(false) {
        case .function(let parameters, _, _, _):
            return "SwiftClosure\(parameters.count).javaObject(for: \(value))"
        case .int:
            return isOptional ? value : "Int32(\(value))"
        case .unwrappedOptional(let type):
            return type.convertToJava(value: value, strategy: strategy)
        default:
            if strategy == .direct {
                return value
            } else if strategy == .unknown {
                let converted = "((\(value) as? JConvertible)?.toJavaObject())"
                return isOptional ? converted : converted + "!"
            } else {
                let converted = value + ".toJavaObject()"
                return isOptional ? converted : converted + "!"
            }
        }
    }

    /// Return code that converts the given value of our Java type back to this type.
    func convertFromJava(value: String, strategy: Bridgable.Strategy) -> String {
        guard strategy != .unknown else {
            return self.unknownBridgeImpl.description + ".fromJavaObject(\(value))"
        }
        switch self {
        case .function:
            return convertClosureFromJava(value: value, isOptional: false)
        case .int:
            return "Int(\(value))"
        case .optional(let type):
            if case .function = type {
                return type.convertClosureFromJava(value: value, isOptional: true)
            } else {
                return description + ".fromJavaObject(\(value))"
            }
        case .unwrappedOptional(let type):
            return type.convertFromJava(value: value, strategy: strategy)
        default:
            if strategy == .direct {
                return value
            } else {
                return description + ".fromJavaObject(\(value))"
            }
        }
    }

    private func convertClosureFromJava(value: String, isOptional: Bool) -> String {
        let parametersString = (0..<parameters.count).map { "p\($0)" }.joined(separator: ", ")
        let parametersInString = parametersString.isEmpty ? parametersString : parametersString + " in "
        let handleNil = isOptional ? "\(value) == nil ? nil : " : ""
        return "\(handleNil){ let closure_swift = JavaBackedClosure<\(returnType)>(\(value)); return { \(parametersInString)try! closure_swift.invoke(\(parametersString)) } }()"
    }

    /// Return the JNI signature of this type.
    func jni(isFunctionDeclaration: Bool = false) -> String {
        switch self {
        case .any:
            return "Ljava/lang/Object;"
        case .anyObject:
            return "Ljava/lang/Object;"
        case .array:
            return "Lskip/lib/Array;"
        case .bool:
            return "Z"
        case .character:
            return "C"
        case .composition:
            return "Ljava/lang/Object;"
        case .dictionary:
            return "Lskip/lib/Dictionary;"
        case .double:
            return "D"
        case .float:
            return "F"
        case .function(let parameters, let returnType, _, _):
            if isFunctionDeclaration {
                let parametersJNI = parameters.map { $0.type.jni() }.joined(separator: "")
                return "(" + parametersJNI + ")" + returnType.jni()
            } else {
                return "Lkotlin/jvm/functions/Function\(parameters.count);"
            }
        case .int:
            return "I"
        case .int8:
            return "B"
        case .int16:
            return "S"
        case .int32:
            return "I"
        case .int64:
            return "J"
        case .int128:
            return "Ljava/math/BigInteger;"
        case .member(let parent, let type):
            var jni = parent.jni()
            if jni.hasSuffix(";") {
                jni = String(jni.dropLast())
            }
            return jni + "$" + type.jni()
        case .metaType:
            return "Ljava/lang/Class;"
        case .module(let name, let type):
            let typeName = type.jni()
            if typeName.hasPrefix("L") && typeName.hasSuffix(";") {
                let packageName = KotlinTranslator.packageName(forModule: name).replacing(".", with: "/")
                return "L" + packageName + "/" + typeName.dropFirst()
            } else {
                return typeName
            }
        case .named(let name, _):
            return "L" + name.replacing(".", with: "/") + ";"
        case .none:
            return "Ljava/lang/Object;"
        case .optional(let type):
            switch type {
            case .bool:
                return "Ljava/lang/Boolean;"
            case .character:
                return "Ljava/lang/Character;"
            case .double:
                return "Ljava/lang/Double;"
            case .float:
                return "Ljava/lang/Float;"
            case .int:
                return "Ljava/lang/Integer;"
            case .int8:
                return "Ljava/lang/Byte;"
            case .int16:
                return "Ljava/lang/Short;"
            case .int32:
                return "Ljava/lang/Integer;"
            case .int64:
                return "Ljava/lang/Long;"
            // TODO: Unsigned types
            default:
                return type.jni()
            }
        case .range:
            return "Ljava/lang/Object;"
        case .set:
            return "Lskip/lib/Set;"
        case .string:
            return "Ljava/lang/String;"
        case .tuple(_, let types):
            return "Lskip/lib/Tuple" + types.count.description + ";"
        case .typealiased(_, let type):
            return type.jni()
        case .uint:
            return "Ljava/lang/Object;"
        case .uint8:
            return "Ljava/lang/Object;"
        case .uint16:
            return "Ljava/lang/Object;"
        case .uint32:
            return "Ljava/lang/Object;"
        case .uint64:
            return "Ljava/lang/Object;"
        case .uint128:
            return "Ljava/lang/Object;"
        case .unwrappedOptional(let type):
            return type.jni()
        case .void:
            return "V"
        }
    }
}

extension Modifiers {
    func swift(suffix: String = "") -> String {
        var string = visibility.swift()
        if isStatic {
            if !string.isEmpty {
                string += " "
            }
            string += "static"
        }
        return string.isEmpty ? "" : string + suffix
    }
}

extension Modifiers.Visibility {
    func swift(suffix: String = "") -> String {
        switch self {
        case .private:
            return "private" + suffix
        case .public:
            return "public" + suffix
        case .fileprivate:
            return "fileprivate" + suffix
        case .open:
            return "open" + suffix
        default:
            return ""
        }
    }
}

/// Information used to bridge values.
struct Bridgable {
    /// Strategies for bridging values.
    enum Strategy {
        case direct
        case convertible
        case javaPeer
        case swiftPeer
        case unknown
    }

    let type: TypeSignature
    let qualifiedType: TypeSignature
    let strategy: Strategy
}

/// Information used to bridge functions.
struct FunctionBridgable {
    let parameters: [Bridgable]
    let `return`: Bridgable
}

extension KotlinVariableDeclaration {
    /// Check that this variable is bridgable.
    ///
    /// This function will add messages about invalid modifiers or types to this variable.
    func checkBridgable(translator: KotlinTranslator) -> Bridgable? {
        guard checkNonPrivate(self, modifiers: modifiers, translator: translator) else {
            return nil
        }
        guard checkNonTypedThrows(apiFlags: apiFlags, sourceDerived: self, source: translator.syntaxTree.source) else {
            return nil
        }
        guard let codebaseInfo = translator.codebaseInfo else {
            return nil
        }
        let type = declaredType.or(propertyType)
        return type.checkBridgable(codebaseInfo: codebaseInfo, sourceDerived: self, source: translator.syntaxTree.source)
    }
}

extension KotlinFunctionDeclaration {
    /// Check that this function is bridgable.
    ///
    /// This function will add messages about invalid modifiers or types to this variable.
    func checkBridgable(translator: KotlinTranslator) -> FunctionBridgable? {
        guard type != .finalizerDeclaration else {
            return nil
        }
        guard checkNonPrivate(self, modifiers: modifiers, translator: translator) else {
            return nil
        }
        guard checkNonTypedThrows(apiFlags: apiFlags, sourceDerived: self, source: translator.syntaxTree.source) else {
            return nil
        }
        guard let codebaseInfo = translator.codebaseInfo else {
            return nil
        }
        return functionType.checkFunctionBridgable(codebaseInfo: codebaseInfo, sourceDerived: self, source: translator.syntaxTree.source)
    }
}

extension KotlinClassDeclaration {
    /// Check that this class is bridgable.
    ///
    /// This function will add messages about invalid modifiers or types to this variable.
    func checkBridgable(translator: KotlinTranslator) -> Bool {
        guard checkNonPrivate(self, modifiers: modifiers, translator: translator) else {
            return false
        }
        return true
    }
}

extension KotlinInterfaceDeclaration {
    /// Check that this interface is bridgable.
    ///
    /// This function will add messages about invalid modifiers or types to this variable.
    func checkBridgable(translator: KotlinTranslator) -> Bool {
        guard checkNonPrivate(self, modifiers: modifiers, translator: translator) else {
            return false
        }
        return true
    }
}

extension TypeSignature {
    func functionType(with bridgable: FunctionBridgable, isConstructor: Bool) -> TypeSignature {
        var functionType = self
        if isConstructor {
            functionType = functionType.withReturnType(.void)
        } else {
            functionType = functionType.withReturnType(bridgable.return.type)
        }
        let functionTypeParameters = functionType.parameters.enumerated().map {
            var parameter = $0.element
            parameter.type = bridgable.parameters[$0.offset].type
            return parameter
        }
        return functionType.withParameters(functionTypeParameters)
    }

    func callbackClosureType(apiFlags: APIFlags, java: Bool) -> TypeSignature {
        let isThrows = apiFlags.throwsType != .none
        let throwsParameterType: TypeSignature = java ? .named("Throwable", []).asOptional(true) : .javaObjectPointer.asOptional(true)
        if returnType == .void {
            if isThrows {
                return .function([TypeSignature.Parameter(type: throwsParameterType)], .void, APIFlags(), nil)
            } else {
                return .function([], .void, APIFlags(), nil)
            }
        } else {
            if isThrows {
                return .function([TypeSignature.Parameter(type: returnType.asOptional(true)), TypeSignature.Parameter(type: throwsParameterType)], .void, APIFlags(), nil)
            } else {
                return .function([TypeSignature.Parameter(type: returnType)], .void, APIFlags(), nil)
            }
        }
    }

    /// Check that this type is bridgable, adding any messages to the given source object.
    func checkBridgable(codebaseInfo: CodebaseInfo.Context, sourceDerived: SourceDerived? = nil, source: Source? = nil) -> Bridgable? {
        switch self {
        case .any, .anyObject:
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedType(sourceDerived, type: description, source: source))
            }
            return nil
        case .array(let elementType):
            guard elementType?.checkBridgable(codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) != nil else {
                return nil
            }
            return Bridgable(type: self, qualifiedType: self, strategy: .convertible)
        case .bool:
            return Bridgable(type: self, qualifiedType: self, strategy: .direct)
        case .character:
            // TODO
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedType(sourceDerived, type: description, source: source))
            }
            return nil
        case .composition:
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedType(sourceDerived, type: description, source: source))
            }
            return nil
        case .dictionary(let keyType, let valueType):
            guard keyType?.checkBridgable(codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) != nil, valueType?.checkBridgable(codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) != nil else {
                return nil
            }
            return Bridgable(type: self, qualifiedType: self, strategy: .convertible)
        case .double, .float:
            return Bridgable(type: self, qualifiedType: self, strategy: .direct)
        case .function(let parameters, let returnType, let apiFlags, _):
            guard checkNonTypedThrows(apiFlags: apiFlags, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            if returnType != .void && returnType.checkBridgable(codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) == nil {
                return nil
            }
            for parameter in parameters {
                if parameter.type.checkBridgable(codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) == nil {
                    return nil
                }
            }
            return Bridgable(type: self, qualifiedType: self, strategy: .direct)
        case .int, .int8, .int16, .int32, .int64:
            return Bridgable(type: self, qualifiedType: self, strategy: .direct)
        case .int128:
            // TODO
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedType(sourceDerived, type: description, source: source))
            }
            return nil
        case .member, .module, .named:
            return checkNamedBridgable(codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source)
        case .metaType:
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedType(sourceDerived, type: description, source: source))
            }
            return nil
        case .none:
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnknownType(sourceDerived, type: description, source: source))
            }
            return nil
        case .optional(let type):
            guard let bridgable = type.checkBridgable(codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            return Bridgable(type: self, qualifiedType: bridgable.qualifiedType.asOptional(true), strategy: bridgable.strategy)
        case .range:
            // TODO
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedType(sourceDerived, type: description, source: source))
            }
            return nil
        case .set:
            // TODO
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedType(sourceDerived, type: description, source: source))
            }
            return nil
        case .string:
            return Bridgable(type: self, qualifiedType: self, strategy: .direct)
        case .tuple:
            // TODO
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedType(sourceDerived, type: description, source: source))
            }
            return nil
        case .typealiased(_, let type):
            return type.checkBridgable(codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source)
        case .uint, .uint8, .uint16, .uint32, .uint64:
            // TODO
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedType(sourceDerived, type: description, source: source))
            }
            return nil
        case .uint128:
            // TODO
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedType(sourceDerived, type: description, source: source))
            }
            return nil
        case .unwrappedOptional(let type):
            return type.checkBridgable(codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source)
        case .void:
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedType(sourceDerived, type: description, source: source))
            }
            return nil
        }
    }

    /// Check that this function is bridgable, adding any messages to the given source object.
    func checkFunctionBridgable(codebaseInfo: CodebaseInfo.Context, sourceDerived: SourceDerived? = nil, source: Source? = nil) -> FunctionBridgable? {
        let returnBridgable: Bridgable
        if returnType == .void {
            returnBridgable = Bridgable(type: .void, qualifiedType: .void, strategy: .direct)
        } else {
            guard let bridgable = returnType.checkBridgable(codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            returnBridgable = bridgable
        }
        var parameterBridgables: [Bridgable] = []
        for parameter in parameters {
            guard let bridgable = parameter.type.checkBridgable(codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            parameterBridgables.append(bridgable)
        }
        return FunctionBridgable(parameters: parameterBridgables, return: returnBridgable)
    }

    fileprivate func checkNamedBridgable(codebaseInfo: CodebaseInfo.Context, sourceDerived: SourceDerived?, source: Source?) -> Bridgable? {
        guard let typeInfo = codebaseInfo.primaryTypeInfo(forNamed: self) else {
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnknownType(sourceDerived, type: description, source: source))
            }
            return nil
        }
        let strategy: Bridgable.Strategy
        if typeInfo.attributes.isBridgeToSwift {
            strategy = typeInfo.declarationType == .protocolDeclaration ? .unknown : .javaPeer
        } else if typeInfo.attributes.isBridgeToKotlin {
            strategy = typeInfo.declarationType == .protocolDeclaration ? .unknown : .swiftPeer
        } else if typeInfo.declarationType == .protocolDeclaration, let moduleName = typeInfo.moduleName, isSkipModule(name: moduleName) {
            // Any protocol in a built-in module will have a Swift and Kotlin representation
            strategy = .unknown
        } else if codebaseInfo.global.protocolSignatures(forNamed: self).contains(where: { $0.isNamed("SwiftCustomBridged", moduleName: "Swift") }) {
            strategy = .convertible
        } else {
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnbridgedType(sourceDerived, type: description, source: source))
            }
            return nil
        }
        let qualifiedType: TypeSignature
        if case .module = self {
            qualifiedType = self
        } else {
            qualifiedType = self.withModuleName(typeInfo.moduleName)
        }
        return Bridgable(type: self, qualifiedType: qualifiedType, strategy: strategy)
    }

    private func isSkipModule(name: String) -> Bool {
        guard name.hasPrefix("Skip") else {
            return false
        }
        return CodebaseInfo.moduleNameMap.values.contains { $0.contains(name) }
    }
}

private func checkNonPrivate(_ sourceDerived: SourceDerived, modifiers: Modifiers, translator: KotlinTranslator) -> Bool {
    guard modifiers.visibility == .private || modifiers.visibility == .fileprivate else {
        return true
    }
    sourceDerived.messages.append(Message.kotlinBridgePrivate(sourceDerived, source: translator.syntaxTree.source))
    return false
}

private func checkNonTypedThrows(apiFlags: APIFlags, sourceDerived: SourceDerived?, source: Source?) -> Bool {
    guard apiFlags.throwsType != .none && apiFlags.throwsType != .any else {
        return true
    }
    if let sourceDerived, let source {
        sourceDerived.messages.append(Message.kotlinBridgeTypedThrows(sourceDerived, source: source))
    }
    return false
}
