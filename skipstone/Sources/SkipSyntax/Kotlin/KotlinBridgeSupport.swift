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

    init(for signature: TypeSignature, packageName: String?) {
        let className: String
        if let packageName {
            className = packageName.replacing(".", with: "/") + "/" + signature.name
        } else {
            className = signature.name
        }
        self.identifier = "Java_class"
        self.className = className
        self.isFileClass = false
    }

    init(forFileName fileName: String, packageName: String?) {
        var identifier = fileName
        if let extensionIndex = fileName.lastIndex(of: ".") {
            let extensionCount = fileName.suffix(from: extensionIndex).count
            identifier = String(identifier.dropLast(extensionCount))
        }
        identifier += "Kt"
        let className: String
        if let packageName {
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

extension KotlinBridgeOptions {
    /// Convert these options into the source code to create the equivalent `JConvertibleOptions`.
    var jconvertibleOptions: String {
        if contains(.kotlincompat) {
            return "[.kotlincompat]"
        }
        return "[]"
    }
}

extension TypeSignature {
    static let javaObjectPointer: TypeSignature = .named("JavaObjectPointer", [])
    static let javaString: TypeSignature = .named("JavaString", [])
    static func swiftObjectPointer(kotlin: Bool) -> TypeSignature {
        return kotlin ? .named("skip.bridge.kt.SwiftObjectPointer", []) : .named("SwiftObjectPointer", [])
    }

    /// The generated native type when the bridging strategy is unknown - e.g. for protocols.
    var unknownBridgeImpl: TypeSignature {
        return withExistentialMode(.none).withName(name + "_BridgeImpl")
    }

    /// Return the `@_cdecl` function equivalent of this type.
    func cdecl(strategy: Bridgable.Strategy, options: KotlinBridgeOptions) -> TypeSignature {
        switch self {
        case .function:
            return .javaObjectPointer
        case .int:
            return .int32
        case .optional(let type):
            return type == .string ? .optional(.javaString) : .optional(.javaObjectPointer)
        case .string:
            return .javaString
        case .tuple:
            return .javaObjectPointer
        case .unwrappedOptional(let type):
            return type.cdecl(strategy: strategy, options: options)
        default:
            return strategy == .direct ? self : .javaObjectPointer
        }
    }

    /// Return code that converst the given value of this type to its `@_cdecl` function form.
    func convertToCDecl(value: String, strategy: Bridgable.Strategy, options: KotlinBridgeOptions) -> String {
        switch self.asOptional(false) {
        case .function(let parameters, _, _, _):
            let converted = "SwiftClosure\(parameters.count).javaObject(for: \(value), options: \(options.jconvertibleOptions))"
            return isOptional ? converted : converted + "!"
        case .int:
            if isOptional {
                return value + ".toJavaObject(options: \(options.jconvertibleOptions))"
            } else {
                return "Int32(\(value))"
            }
        case .string:
            let converted = value + ".toJavaObject(options: \(options.jconvertibleOptions))"
            return isOptional ? converted : converted + "!"
        case .tuple:
            let converted = "SwiftTuple.javaObject(for: \(value), options: \(options.jconvertibleOptions))"
            return isOptional ? converted : converted + "!"
        case .unwrappedOptional(let type):
            return type.convertToCDecl(value: value, strategy: strategy, options: options)
        default:
            if strategy == .direct && !isOptional {
                return value
            } else if strategy == .unknown {
                let converted = "((\(value) as? JConvertible)?.toJavaObject(options: \(options.jconvertibleOptions)))"
                return isOptional ? converted : converted + "!"
            } else {
                let converted = value + ".toJavaObject(options: \(options.jconvertibleOptions))"
                return isOptional ? converted : converted + "!"
            }
        }
    }

    /// Return code that converts the given value of our `@_cdecl` function type back to this type.
    func convertFromCDecl(value: String, strategy: Bridgable.Strategy, options: KotlinBridgeOptions) -> String {
        guard strategy != .unknown else {
            return self.unknownBridgeImpl.description + ".fromJavaObject(\(value), options: \(options.jconvertibleOptions))"
        }
        switch self.asOptional(false) {
        case .function(let parameters, _, _, _):
            let converted = "SwiftClosure\(parameters.count).closure(forJavaObject: \(value), options: \(options.jconvertibleOptions))"
            return "\(converted)\(isOptional ? "" : "!") as \(self)\(isOptional ? "?" : "")"
        case .int:
            if isOptional {
                return description + ".fromJavaObject(\(value), options: \(options.jconvertibleOptions))"
            } else {
                return "Int(\(value))"
            }
        case .string:
            return description + ".fromJavaObject(\(value), options: \(options.jconvertibleOptions))"
        case .tuple:
            let converted = "SwiftTuple.tuple(forJavaObject: \(value), options: \(options.jconvertibleOptions))"
            return "\(converted)\(isOptional ? "" : "!") as \(self)\(isOptional ? "?" : "")"
        case .unwrappedOptional(let type):
            return type.convertFromCDecl(value: value, strategy: strategy, options: options)
        default:
            if strategy == .direct && !isOptional {
                return value
            } else {
                return description + ".fromJavaObject(\(value), options: \(options.jconvertibleOptions))"
            }
        }
    }

    /// Return the Java equivalent of this type.
    func java(strategy: Bridgable.Strategy, options: KotlinBridgeOptions) -> TypeSignature {
        switch self {
        case .function:
            return .javaObjectPointer
        case .int:
            return .int32
        case .optional:
            return .optional(.javaObjectPointer)
        case .tuple:
            return .javaObjectPointer
        case .unwrappedOptional(let type):
            return type.java(strategy: strategy, options: options)
        default:
            return strategy == .direct ? self : .javaObjectPointer
        }
    }

    /// Return code that converts the given value of this type to its Java form.
    func convertToJava(value: String, strategy: Bridgable.Strategy, options: KotlinBridgeOptions) -> String {
        switch self.asOptional(false) {
        case .function(let parameters, _, _, _):
            return "SwiftClosure\(parameters.count).javaObject(for: \(value), options: \(options.jconvertibleOptions))"
        case .int:
            return isOptional ? value : "Int32(\(value))"
        case .tuple:
            return "SwiftTuple.javaObject(for: \(value), options: \(options.jconvertibleOptions))"
        case .unwrappedOptional(let type):
            return type.convertToJava(value: value, strategy: strategy, options: options)
        default:
            if strategy == .direct {
                return value
            } else if strategy == .unknown {
                let converted = "((\(value) as? JConvertible)?.toJavaObject(options: \(options.jconvertibleOptions)))"
                return isOptional ? converted : converted + "!"
            } else {
                let converted = value + ".toJavaObject(options: \(options.jconvertibleOptions))"
                return isOptional ? converted : converted + "!"
            }
        }
    }

    /// Return code that converts the given value of our Java type back to this type.
    func convertFromJava(value: String, strategy: Bridgable.Strategy, options: KotlinBridgeOptions) -> String {
        guard strategy != .unknown else {
            return self.unknownBridgeImpl.description + ".fromJavaObject(\(value), options: \(options.jconvertibleOptions))"
        }
        switch self {
        case .function:
            return convertClosureFromJava(value: value, isOptional: false, options: options)
        case .int:
            return "Int(\(value))"
        case .optional(let type):
            if case .function = type {
                return type.convertClosureFromJava(value: value, isOptional: true, options: options)
            } else if case .tuple = type {
                return "SwiftTuple.tuple(forJavaObject: \(value), options: \(options.jconvertibleOptions))"
            } else {
                return description + ".fromJavaObject(\(value), options: \(options.jconvertibleOptions))"
            }
        case .tuple:
            return "SwiftTuple.tuple(forJavaObject: \(value), options: \(options.jconvertibleOptions))!"
        case .unwrappedOptional(let type):
            return type.convertFromJava(value: value, strategy: strategy, options: options)
        default:
            if strategy == .direct {
                return value
            } else {
                return description + ".fromJavaObject(\(value), options: \(options.jconvertibleOptions))"
            }
        }
    }

    private func convertClosureFromJava(value: String, isOptional: Bool, options: KotlinBridgeOptions) -> String {
        let parametersString = (0..<parameters.count).map { "p\($0)" }.joined(separator: ", ")
        let parametersInString = parametersString.isEmpty ? parametersString : parametersString + " in "
        let handleNil = isOptional ? "\(value) == nil ? nil : " : ""
        return "\(handleNil){ let closure_swift = JavaBackedClosure<\(returnType)>(\(value), options: \(options.jconvertibleOptions)); return { \(parametersInString)try! closure_swift.invoke(\(parametersString)) } }()"
    }

    /// Return the JNI signature of this type.
    func jni(options: KotlinBridgeOptions, isFunctionDeclaration: Bool = false) -> String {
        switch self {
        case .any:
            return "Ljava/lang/Object;"
        case .anyObject:
            return "Ljava/lang/Object;"
        case .array:
            if options.contains(.kotlincompat) {
                return "Lkotlin/collections/List;"
            } else {
                return "Lskip/lib/Array;"
            }
        case .bool:
            return "Z"
        case .character:
            return "C"
        case .composition:
            return "Ljava/lang/Object;"
        case .dictionary:
            if options.contains(.kotlincompat) {
                return "Lkotlin/collections/Map;"
            } else {
                return "Lskip/lib/Dictionary;"
            }
        case .double:
            return "D"
        case .existential(_, let type):
            return type.jni(options: options)
        case .float:
            return "F"
        case .function(let parameters, let returnType, _, _):
            if isFunctionDeclaration {
                let parametersJNI = parameters.map { $0.type.jni(options: options) }.joined(separator: "")
                return "(" + parametersJNI + ")" + returnType.jni(options: options)
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
            var jni = parent.jni(options: options)
            if jni.hasSuffix(";") {
                jni = String(jni.dropLast())
            }
            return jni + "$" + type.jni(options: options)
        case .metaType:
            return "Ljava/lang/Class;"
        case .module(let name, let type):
            let typeName = type.jni(options: options)
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
                return type.jni(options: options)
            }
        case .range:
            return "Ljava/lang/Object;"
        case .set:
            if options.contains(.kotlincompat) {
                return "Lkotlin/collections/Set;"
            } else {
                return "Lskip/lib/Set;"
            }
        case .string:
            return "Ljava/lang/String;"
        case .tuple(_, let types):
            if options.contains(.kotlincompat) && types.count == 2 {
                return "Lkotlin/Pair;"
            } else if options.contains(.kotlincompat) && types.count == 3 {
                return "Lkotlin/Triple;"
            } else {
                return "Lskip/lib/Tuple" + types.count.description + ";"
            }
        case .typealiased(_, let type):
            return type.jni(options: options)
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
            return type.jni(options: options)
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
        } else if isMutating {
            if !string.isEmpty {
                string += " "
            }
            string += "mutating"
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

    var type: TypeSignature
    var kotlinType: TypeSignature
    var strategy: Strategy
}

/// Information used to bridge functions.
struct FunctionBridgable {
    var parameters: [Bridgable]
    var `return`: Bridgable
}

extension KotlinVariableDeclaration {
    /// Check that this variable is bridgable.
    ///
    /// This function will add messages about invalid modifiers or types to this variable.
    func checkBridgable(options: KotlinBridgeOptions, translator: KotlinTranslator) -> Bridgable? {
        guard checkNonStaticProtocolRequirement(self, in: parent, modifiers: modifiers, translator: translator) else {
            return nil
        }
        guard !apiFlags.options.contains(.async) else {
            messages.append(.kotlinBridgeUnsupportedFeature(self, feature: "async vars", source: translator.syntaxTree.source))
            return nil
        }
        guard checkNonTypedThrows(self, apiFlags: apiFlags, source: translator.syntaxTree.source) else {
            return nil
        }
        guard !modifiers.isLazy else {
            messages.append(.kotlinBridgeUnsupportedFeature(self, feature: "lazy vars", source: translator.syntaxTree.source))
            return nil
        }
        guard let codebaseInfo = translator.codebaseInfo else {
            return nil
        }
        let type = declaredType.or(propertyType)
        return type.checkBridgable(options: options, codebaseInfo: codebaseInfo, sourceDerived: self, source: translator.syntaxTree.source)
    }
}

extension KotlinFunctionDeclaration {
    /// Whether this function declaration matches the Kotlin `equals()` function.
    var isKotlinEqualImplementation: Bool {
        return name == "equals" && !modifiers.isStatic && parameters.count == 1 && parameters[0].declaredType == .optional(.any)
    }

    /// Whether this function declaration matches the Kotlin `hashCode()` function.
    var isKotlinHashImplementation: Bool {
        return name == "hashCode" && !modifiers.isStatic && parameters.isEmpty && returnType == .int
    }

    /// Check that this function is bridgable.
    ///
    /// This function will add messages about invalid modifiers or types to this variable.
    func checkBridgable(options: KotlinBridgeOptions, translator: KotlinTranslator) -> FunctionBridgable? {
        guard type != .finalizerDeclaration else {
            return nil
        }
        guard role != .operator else {
            messages.append(.kotlinBridgeUnsupportedFeature(self, feature: "custom subscripts and operators", source: translator.syntaxTree.source))
            return nil
        }
        guard !isOptionalInit else {
            messages.append(.kotlinBridgeUnsupportedFeature(self, feature: "optional inits", source: translator.syntaxTree.source))
            return nil
        }
        guard checkNonStaticProtocolRequirement(self, in: parent, modifiers: modifiers, translator: translator) else {
            return nil
        }
        guard checkNonTypedThrows(self, apiFlags: apiFlags, source: translator.syntaxTree.source) else {
            return nil
        }
        guard !parameters.contains(where: { $0.isVariadic }) else {
            messages.append(.kotlinBridgeUnsupportedFeature(self, feature: "variadic parameters", source: translator.syntaxTree.source))
            return nil
        }
        guard let codebaseInfo = translator.codebaseInfo else {
            return nil
        }
        return functionType.checkFunctionBridgable(isConstructor: type == .constructorDeclaration, options: options, codebaseInfo: codebaseInfo, sourceDerived: self, source: translator.syntaxTree.source)
    }
}

extension KotlinClassDeclaration {
    /// Check that this class is bridgable.
    ///
    /// This function will add messages about invalid modifiers or types to this variable.
    func checkBridgable(options: KotlinBridgeOptions, translator: KotlinTranslator) -> Bool {
        switch declarationType {
        case .enumDeclaration:
            guard !isSealedClassesEnum else {
                messages.append(.kotlinBridgeUnsupportedFeature(self, feature: "enums with additional state", source: translator.syntaxTree.source))
                return false
            }
        case .classDeclaration:
            guard !isSubclass(translator: translator) else {
                messages.append(.kotlinBridgeUnsupportedFeature(self, feature: "subclasses", source: translator.syntaxTree.source))
                return false
            }
            break
        case .structDeclaration:
            break
        default:
            messages.append(.kotlinBridgeUnsupportedFeature(self, feature: String(describing: declarationType), source: translator.syntaxTree.source))
            return false
        }
        guard checkNonGeneric(self, generics: generics, translator: translator) else {
            return false
        }
        guard !(parent is KotlinClassDeclaration) && !(parent is KotlinInterfaceDeclaration) else {
            messages.append(.kotlinBridgeUnsupportedFeature(self, feature: "inner types", source: translator.syntaxTree.source))
            return false
        }
        return true
    }

    private func isSubclass(translator: KotlinTranslator) -> Bool {
        guard let codebaseInfo = translator.codebaseInfo, let inherit = inherits.first else {
            return false
        }
        let primaryTypeInfo = codebaseInfo.primaryTypeInfo(forNamed: inherit)
        return primaryTypeInfo != nil && primaryTypeInfo?.declarationType != .protocolDeclaration
    }
}

extension KotlinInterfaceDeclaration {
    /// Check that this interface is bridgable.
    ///
    /// This function will add messages about invalid modifiers or types to this variable.
    func checkBridgable(options: KotlinBridgeOptions, translator: KotlinTranslator) -> Bool {
        guard checkNonGeneric(self, generics: generics, translator: translator) else {
            return false
        }
        return true
    }
}

extension KotlinSyntaxNode {
    final var isInIfNotSkipBridgeBlock: Bool {
        var node: KotlinSyntaxNode? = self
        while node != nil {
            if let directives = (node as? KotlinStatement)?.extras?.directives {
                for directive in directives {
                    if case .ifSkipBlock(let blockType) = directive, blockType == .ifNotSkipBridge {
                        return true
                    }
                }
            }
            node = node?.parent
        }
        return false
    }
}

extension TypeSignature {
    func callbackClosureType(apiFlags: APIFlags, kotlin: Bool) -> TypeSignature {
        let isThrows = apiFlags.throwsType != .none
        let throwsParameterType: TypeSignature = kotlin ? .named("Throwable", []).asOptional(true) : .javaObjectPointer.asOptional(true)
        if self == .void {
            if isThrows {
                return .function([TypeSignature.Parameter(type: throwsParameterType)], .void, APIFlags(), nil)
            } else {
                return .function([], .void, APIFlags(), nil)
            }
        } else {
            if isThrows {
                return .function([TypeSignature.Parameter(type: self.asOptional(true)), TypeSignature.Parameter(type: throwsParameterType)], .void, APIFlags(), nil)
            } else {
                return .function([TypeSignature.Parameter(type: self)], .void, APIFlags(), nil)
            }
        }
    }

    /// Check that this type is bridgable, adding any messages to the given source object.
    func checkBridgable(options: KotlinBridgeOptions, codebaseInfo: CodebaseInfo.Context, sourceDerived: SourceDerived? = nil, source: Source? = nil) -> Bridgable? {
        switch self {
        case .any, .anyObject:
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: description, source: source))
            }
            return nil
        case .array(let elementType):
            guard let elementBridgable = elementType?.checkBridgable(options: options, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            if options.contains(.kotlincompat) {
                let listType: TypeSignature = .module("kotlin.collections", .named("List", [elementBridgable.kotlinType]))
                return Bridgable(type: self, kotlinType: listType, strategy: .convertible)
            } else {
                return Bridgable(type: self, kotlinType: self, strategy: .convertible)
            }
        case .bool:
            return Bridgable(type: self, kotlinType: self, strategy: .direct)
        case .character:
            // TODO
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: description, source: source))
            }
            return nil
        case .composition:
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: description, source: source))
            }
            return nil
        case .dictionary(let keyType, let valueType):
            guard let keyBridgable = keyType?.checkBridgable(options: options, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source), let valueBridgable = valueType?.checkBridgable(options: options, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            if options.contains(.kotlincompat) {
                let mapType: TypeSignature = .module("kotlin.collections", .named("Map", [keyBridgable.kotlinType, valueBridgable.kotlinType]))
                return Bridgable(type: self, kotlinType: mapType, strategy: .convertible)
            } else {
                return Bridgable(type: self, kotlinType: self, strategy: .convertible)
            }
        case .double, .float:
            return Bridgable(type: self, kotlinType: self, strategy: .direct)
        case .existential(let mode, let type):
            guard var bridgable = type.checkBridgable(options: options, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            bridgable.type = bridgable.type.withExistentialMode(mode)
            return bridgable
        case .function(let parameters, let returnType, let apiFlags, let attributes):
            guard checkNonTypedThrows(sourceDerived, apiFlags: apiFlags, source: source) else {
                return nil
            }
            let bridgeReturnType: TypeSignature
            let bridgeKotlinReturnType: TypeSignature
            if returnType == .void {
                bridgeReturnType = .void
                bridgeKotlinReturnType = .void
            } else {
                guard let bridge = returnType.checkBridgable(options: options, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                    return nil
                }
                bridgeReturnType = returnType
                bridgeKotlinReturnType = bridge.kotlinType
            }
            var bridgeKotlinParameters: [TypeSignature.Parameter] = []
            for var parameter in parameters {
                guard let bridge = parameter.type.checkBridgable(options: options, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                    return nil
                }
                parameter.type = bridge.kotlinType
                bridgeKotlinParameters.append(parameter)
            }
            let bridgeType: TypeSignature = .function(parameters, bridgeReturnType, apiFlags, attributes)
            let bridgeKotlinType: TypeSignature = .function(bridgeKotlinParameters, bridgeKotlinReturnType, apiFlags, attributes)
            return Bridgable(type: bridgeType, kotlinType: bridgeKotlinType, strategy: .direct)
        case .int, .int8, .int16, .int32, .int64:
            return Bridgable(type: self, kotlinType: self, strategy: .direct)
        case .int128:
            // TODO
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: description, source: source))
            }
            return nil
        case .member, .module, .named:
            return checkNamedBridgable(options: options, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source)
        case .metaType:
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: description, source: source))
            }
            return nil
        case .none:
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnknownType(sourceDerived, type: description, source: source))
            }
            return nil
        case .optional(let type):
            guard let bridgable = type.checkBridgable(options: options, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            return Bridgable(type: self, kotlinType: bridgable.kotlinType.asOptional(true), strategy: bridgable.strategy)
        case .range:
            // TODO
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: description, source: source))
            }
            return nil
        case .set(let elementType):
            guard let elementBridgable = elementType?.checkBridgable(options: options, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            if options.contains(.kotlincompat) {
                let setType: TypeSignature = .module("kotlin.collections", .named("Set", [elementBridgable.kotlinType]))
                return Bridgable(type: self, kotlinType: setType, strategy: .convertible)
            } else {
                return Bridgable(type: self, kotlinType: self, strategy: .convertible)
            }
        case .string:
            return Bridgable(type: self, kotlinType: self, strategy: .direct)
        case .tuple(_, let types):
            let typeBridgables: [Bridgable] = types.compactMap { type in
                guard let bridgable = type.checkBridgable(options: options, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                    return nil
                }
                return bridgable
            }
            guard typeBridgables.count == types.count else {
                return nil
            }
            if types.count == 2 && options.contains(.kotlincompat) {
                let pairType: TypeSignature = .named("kotlin.Pair", typeBridgables.map(\.kotlinType))
                return Bridgable(type: self, kotlinType: pairType, strategy: .direct)
            } else if types.count == 3 && options.contains(.kotlincompat) {
                let tripleType: TypeSignature = .named("kotlin.Triple", typeBridgables.map(\.kotlinType))
                return Bridgable(type: self, kotlinType: tripleType, strategy: .direct)
            } else {
                return Bridgable(type: self, kotlinType: self, strategy: .direct)
            }
        case .typealiased(_, let type):
            return type.checkBridgable(options: options, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source)
        case .uint, .uint8, .uint16, .uint32, .uint64:
            // TODO
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: description, source: source))
            }
            return nil
        case .uint128:
            // TODO
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: description, source: source))
            }
            return nil
        case .unwrappedOptional:
            // TODO - force unwrapped properties compiled as Java fields not get/set methods
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: "force unwrapped types", source: source))
            }
            return nil
        case .void:
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: description, source: source))
            }
            return nil
        }
    }

    /// Check that this function is bridgable, adding any messages to the given source object.
    func checkFunctionBridgable(isConstructor: Bool, options: KotlinBridgeOptions, codebaseInfo: CodebaseInfo.Context, sourceDerived: SourceDerived? = nil, source: Source? = nil) -> FunctionBridgable? {
        let returnBridgable: Bridgable
        if isConstructor || returnType == .void {
            returnBridgable = Bridgable(type: .void, kotlinType: .void, strategy: .direct)
        } else {
            guard let bridgable = returnType.checkBridgable(options: options, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            returnBridgable = bridgable
        }
        var parameterBridgables: [Bridgable] = []
        for parameter in parameters {
            guard let bridgable = parameter.type.checkBridgable(options: options, codebaseInfo: codebaseInfo, sourceDerived: sourceDerived, source: source) else {
                return nil
            }
            parameterBridgables.append(bridgable)
        }
        return FunctionBridgable(parameters: parameterBridgables, return: returnBridgable)
    }

    fileprivate func checkNamedBridgable(options: KotlinBridgeOptions, codebaseInfo: CodebaseInfo.Context, sourceDerived: SourceDerived?, source: Source?) -> Bridgable? {
        guard let typeInfo = codebaseInfo.primaryTypeInfo(forNamed: self) else {
            if let sourceDerived, let source {
                sourceDerived.messages.append(.kotlinBridgeUnknownType(sourceDerived, type: description, source: source))
            }
            return nil
        }
        let strategy: Bridgable.Strategy
        var kotlinType: TypeSignature = .none
        if typeInfo.attributes.isBridgeToSwift {
            strategy = typeInfo.declarationType == .protocolDeclaration ? .unknown : .javaPeer
        } else if typeInfo.attributes.isBridgeToKotlin {
            strategy = typeInfo.declarationType == .protocolDeclaration ? .unknown : .swiftPeer
        } else if typeInfo.declarationType == .protocolDeclaration, let moduleName = typeInfo.moduleName, isSkipModule(name: moduleName) {
            // Any protocol in a built-in module will have a Swift and Kotlin representation
            strategy = .unknown
        } else {
            if typeInfo.inherits.contains(where: { $0.isNamed("SwiftCustomBridged", moduleName: "Swift") }) {
                strategy = .convertible
                if options.contains(.kotlincompat), let kotlinConverting = typeInfo.inherits.first(where: { $0.isNamed("KotlinConverting", moduleName: "Swift") }), let kotlinConvertingType = kotlinConverting.generics.first, kotlinConvertingType != .any {
                    kotlinType = kotlinConvertingType
                }
            } else {
                if let sourceDerived, let source {
                    sourceDerived.messages.append(.kotlinBridgeUnbridgedType(sourceDerived, type: description, source: source))
                }
                return nil
            }
        }
        if kotlinType == .none {
            if case .module = self {
                kotlinType = self
            } else {
                kotlinType = self.withModuleName(typeInfo.moduleName)
            }
        }
        return Bridgable(type: self, kotlinType: kotlinType, strategy: strategy)
    }

    private func isSkipModule(name: String) -> Bool {
        guard name.hasPrefix("Skip") else {
            return false
        }
        return CodebaseInfo.moduleNameMap.values.contains { $0.contains(name) }
    }
}

private func checkNonGeneric(_ sourceDerived: SourceDerived, generics: Generics, translator: KotlinTranslator) -> Bool {
    guard !generics.isEmpty else {
        return true
    }
    sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: "generic types", source: translator.syntaxTree.source))
    return false
}

private func checkNonStaticProtocolRequirement(_ sourceDerived: SourceDerived, in parent: KotlinSyntaxNode?, modifiers: Modifiers, translator: KotlinTranslator) -> Bool {
    guard modifiers.isStatic, parent is KotlinInterfaceDeclaration else {
        return true
    }
    sourceDerived.messages.append(.kotlinBridgeUnsupportedFeature(sourceDerived, feature: "static protocol requirements", source: translator.syntaxTree.source))
    return false
}

private func checkNonTypedThrows(_ sourceDerived: SourceDerived?, apiFlags: APIFlags, source: Source?) -> Bool {
    guard apiFlags.throwsType != .none && apiFlags.throwsType != .any else {
        return true
    }
    if let sourceDerived, let source {
        sourceDerived.messages.append(.kotlinBridgeTypedThrows(sourceDerived, source: source))
    }
    return false
}
