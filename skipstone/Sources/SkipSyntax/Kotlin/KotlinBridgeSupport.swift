/// Used in Swift code generation.
struct SwiftDefinition: OutputNode {
    static let leadingContent = "#if canImport(SkipBridge)\nimport SkipBridge\n\n"
    static let trailingContent = "\n#endif\n"

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
        return (isFileClass ? "private let " : "private static let ") + identifier + " = try! JClass(name: \"" + className + "\")"
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
        return replacing("_", with: "_1")
    }
}

extension TypeSignature {
    static let javaObjectPointer: TypeSignature = .named("JavaObjectPointer", [])
    static func swiftObjectPointer(java: Bool) -> TypeSignature {
        return java ? .named("skip.bridge.SwiftObjectPointer", []) : .named("SwiftObjectPointer", [])
    }

    /// Return the external function equivalent of this type.
    func kotlinExternal(strategy: Bridgable.Strategy) -> TypeSignature {
        switch self {
        case .int:
            return .int64
        case .optional(let type):
            let converted = type.kotlinExternal(strategy: strategy)
            return converted.asOptional(converted != .swiftObjectPointer(java: true))
        case .unwrappedOptional(let type):
            return type.kotlinExternal(strategy: strategy)
        default:
            switch strategy {
            case .javaPeer:
                return self
            case .swiftPeer:
                return .swiftObjectPointer(java: true)
            case .custom:
                return self // TODO
            case .direct:
                return self
            case .unknown:
                return self // TODO
            }
        }
    }

    /// Return code that converts the given value of this type to its external form.
    func kotlinConvertToExternal(value: String, strategy: Bridgable.Strategy) -> String {
        switch self.asOptional(false) {
        case .int:
            if isOptional {
                return value + "?.toLong()"
            } else {
                return value + ".toLong()"
            }
        case .unwrappedOptional(let type):
            return type.kotlinConvertToExternal(value: value, strategy: strategy)
        default:
            switch strategy {
            case .javaPeer:
                return value
            case .swiftPeer:
                if isOptional {
                    return value + "?.Swift_peer ?: skip.bridge.SwiftObjectNil"
                } else {
                    return value + ".Swift_peer"
                }
            case .custom:
                return value // TODO
            case .direct:
                return value
            case .unknown:
                return value // TODO
            }
        }
    }

    /// Return code that converts the given value of our external type back to this type.
    func kotlinConvertFromExternal(value: String, strategy: Bridgable.Strategy) -> String {
        switch self.asOptional(false) {
        case .int:
            if isOptional {
                return value + "?.toInt()"
            } else {
                return value + ".toInt()"
            }
        case .unwrappedOptional(let type):
            return type.kotlinConvertFromExternal(value: value, strategy: strategy)
        default:
            switch strategy {
            case .javaPeer:
                return value
            case .swiftPeer:
                let converted = description + "(Swift_peer = " + value + ", marker = null)"
                if isOptional {
                    return "if (" + value + " == skip.bridge.SwiftObjectNil) null else " + converted
                } else {
                    return converted
                }
            case .custom:
                return value // TODO
            case .direct:
                return value
            case .unknown:
                return value // TODO
            }
        }
    }

    /// Return the `@_cdecl` function equivalent of this type.
    func cdecl(strategy: Bridgable.Strategy) -> TypeSignature {
        switch self {
        case .int:
            return .int64
        case .optional:
            return .optional(.javaObjectPointer)
        case .string:
            return .named("JavaString", [])
        case .unwrappedOptional(let type):
            return type.cdecl(strategy: strategy)
        default:
            switch strategy {
            case .javaPeer:
                return .javaObjectPointer
            case .swiftPeer:
                return .swiftObjectPointer(java: false)
            case .custom:
                return self // TODO
            case .direct:
                return self
            case .unknown:
                return self // TODO
            }
        }
    }

    /// Return code that converst the given value of this type to its `@_cdecl` function form.
    func convertToCDecl(value: String, strategy: Bridgable.Strategy) -> String {
        switch self.asOptional(false) {
        case .int:
            if isOptional {
                return value + ".toJavaObject()"
            } else {
                return "Int64(" + value + ")"
            }
        case .string:
            let converted = value + ".toJavaObject()"
            return isOptional ? converted : converted + "!"
        case .unwrappedOptional(let type):
            return type.convertToCDecl(value: value, strategy: strategy)
        default:
            switch strategy {
            case .javaPeer:
                if isOptional {
                    return value + "?.Java_peer.safePointer()"
                } else {
                    return value + ".Java_peer.safePointer()"
                }
            case .swiftPeer:
                return "SwiftObjectPointer.pointer(to: " + value + ", retain: true)"
            case .custom:
                return value // TODO
            case .direct:
                if isOptional {
                    return value + ".toJavaObject()"
                } else {
                    return value
                }
            case .unknown:
                return value // TODO
            }
        }
    }

    /// Return code that converts the given value of our `@_cdecl` function type back to this type.
    func convertFromCDecl(value: String, strategy: Bridgable.Strategy) -> String {
        switch self.asOptional(false) {
        case .int:
            if isOptional {
                return "try! " + description + ".fromJavaObject(" + value + ")"
            } else {
                return "Int(" + value + ")"
            }
        case .string:
            return "try! " + description + ".fromJavaObject(" + value + ")"
        case .unwrappedOptional(let type):
            return type.convertFromCDecl(value: value, strategy: strategy)
        default:
            switch strategy {
            case .javaPeer:
                if isOptional {
                    return value + " == nil ? nil : " + description + "(Java_ptr: " + value + "!)"
                } else {
                    return description + "(Java_ptr: " + value + ")"
                }
            case .swiftPeer:
                if isOptional {
                    return value + ".pointee() as " + description
                } else {
                    return value + ".pointee()! as " + description
                }
            case .custom:
                return value // TODO
            case .direct:
                if isOptional {
                    return "try! " + description + ".fromJavaObject(" + value + ")"
                } else {
                    return value
                }
            case .unknown:
                return value // TODO
            }
        }
    }

    /// Return the Java equivalent of this type.
    var java: TypeSignature {
        switch self {
        case .int:
            return .int32
        case .optional:
            return .optional(.javaObjectPointer)
        case .unwrappedOptional(let type):
            return type.java
        default:
            return isNamedType ? .javaObjectPointer : self // TODO: All other types
        }
    }

    /// Return code that converts the given value of this type to its Java form.
    func convertToJava(value: String, strategy: Bridgable.Strategy) -> String {
        switch self {
        case .int:
            return "Int32(" + value + ")"
        case .unwrappedOptional(let type):
            return type.convertToJava(value: value, strategy: strategy)
        default:
            switch strategy {
            case .javaPeer:
                return value + ".Java_peer.safePointer()"
            case .swiftPeer:
                return value + ".Java_swiftPeerBridged()"
            case .custom:
                return value // TODO
            case .direct:
                return value
            case .unknown:
                return value // TODO
            }
        }
    }

    /// Return code that converts the given value of our Java type back to this type.
    func convertFromJava(value: String, strategy: Bridgable.Strategy) -> String {
        switch self {
        case .int:
            return "Int(" + value + ")"
        case .optional:
            return "try! " + description + ".fromJavaObject(" + value + ")"
        case .unwrappedOptional(let type):
            return type.convertFromJava(value: value, strategy: strategy)
        default:
            switch strategy {
            case .javaPeer:
                return description + "(Java_ptr: " + value + ")"
            case .swiftPeer:
                return "SwiftObjectPointer.peer(of: " + value + ").pointee()!"
            case .custom:
                return value // TODO
            case .direct:
                return value
            case .unknown:
                return value
            }
        }
    }

    /// Return the JNI signature of this type.
    var jni: String {
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
        case .function(let arguments, let returnType, _, _):
            let argumentsJNI = arguments.map(\.type.jni).joined(separator: "")
            return "(" + argumentsJNI + ")" + returnType.jni
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
            var jni = parent.jni
            if jni.hasSuffix(";") {
                jni = String(jni.dropLast())
            }
            return jni + "$" + type.jni
        case .metaType:
            return "Ljava/lang/Class;"
        case .module(let name, let type):
            let typeName = type.jni
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
                return type.jni
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
            return type.jni
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
            return type.jni
        case .void:
            return "V"
        }
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

extension Parameter {
    var swift: String {
        var str = ""
        if let externalLabel {
            str += externalLabel
        } else {
            str += "_"
        }
        if let internalLabel = _internalLabel {
            str += " " + internalLabel
        }
        str += ": " + declaredType.description
        if let defaultValueSwift, !defaultValueSwift.isEmpty {
            str += " " + defaultValueSwift
        }
        return str
    }
}

/// Information used to bridge values.
struct Bridgable {
    /// Strategies for bridging values.
    enum Strategy {
        case direct
        case javaPeer
        case swiftPeer
        case custom
        case unknown
    }

    let type: TypeSignature
    let qualifiedType: TypeSignature
    let strategy: Strategy
}

extension KotlinVariableDeclaration {
    /// Check that this variable is bridgable.
    ///
    /// This function will add messages about invalid modifiers or types to this variable.
    func checkBridgable(translator: KotlinTranslator) -> Bridgable? {
        guard checkNonPrivate(self, modifiers: modifiers, translator: translator) else {
            return nil
        }
        let type = declaredType.or(propertyType)
        return type.checkBridgable(self, translator: translator)
    }
}

extension KotlinFunctionDeclaration {
    /// Check that this function is bridgable.
    ///
    /// This function will add messages about invalid modifiers or types to this variable.
    func checkBridgable(translator: KotlinTranslator) -> (parameters: [Bridgable], return: Bridgable)? {
        guard type != .finalizerDeclaration else {
            return nil
        }
        guard checkNonPrivate(self, modifiers: modifiers, translator: translator) else {
            return nil
        }
        guard let returnBridgable = returnType.checkBridgable(self, translator: translator) else {
            return nil
        }
        var parameterBridgables: [Bridgable] = []
        for parameter in parameters {
            guard let bridgable = parameter.declaredType.checkBridgable(self, translator: translator) else {
                return nil
            }
            parameterBridgables.append(bridgable)
        }
        return (parameterBridgables, returnBridgable)
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

extension TypeSignature {
    /// Check that this type is bridgable, adding any messages to the given source object.
    fileprivate func checkBridgable(_ sourceDerived: SourceDerived, translator: KotlinTranslator) -> Bridgable? {
        guard let codebaseInfo = translator.codebaseInfo else {
            return nil
        }
        var firstTypeInfo: CodebaseInfo.TypeInfo? = nil
        var firstMessage: Message? = nil
        let qualifiedType = self.moduleQualfied(codebaseInfo: codebaseInfo) { type, typeInfo in
            if let typeInfo {
                if firstTypeInfo == nil {
                    firstTypeInfo = typeInfo
                }
                if firstMessage == nil, !typeInfo.attributes.contains(directive: Directive.bridge) {
                    firstMessage = Message.kotlinBridgeUnbridgedType(sourceDerived, type: type.description, source: translator.syntaxTree.source)
                }
            } else if firstMessage == nil {
                firstMessage = Message.kotlinBridgeUnknownType(sourceDerived, type: type.description, source: translator.syntaxTree.source)
            }
        }
        if let firstMessage {
            sourceDerived.messages.append(firstMessage)
            return nil
        }

        let strategy = strategy(with: firstTypeInfo)
        return Bridgable(type: self, qualifiedType: qualifiedType, strategy: strategy)
    }

    /// Return the bridging strategy for this type, given its type info.
    private func strategy(with typeInfo: CodebaseInfo.TypeInfo?) -> Bridgable.Strategy {
        switch self.asOptional(false) {
        case .array, .dictionary, .range, .set, .tuple:
            return .custom
        case .typealiased(_, let type):
            return type.strategy(with: typeInfo)
        default:
            guard isNamedType else {
                return .direct
            }
            guard let typeInfo else {
                return .unknown
            }
            return typeInfo.attributes.contains(directive: Directive.bridgeFileType) ? .swiftPeer : .javaPeer
        }
    }
}

private func checkNonPrivate(_ sourceDerived: SourceDerived, modifiers: Modifiers, translator: KotlinTranslator) -> Bool {
    guard modifiers.visibility == .private || modifiers.visibility == .fileprivate else {
        return true
    }
    sourceDerived.messages.append(Message.kotlinBridgePrivate(sourceDerived, source: translator.syntaxTree.source))
    return false
}
