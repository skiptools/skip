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
    static let swiftObjectPtr: TypeSignature = .named("SwiftObjectPtr", [])
    
    /// Return the external function equivalent of this type.
    var kotlinExternal: TypeSignature {
        switch self {
        case .int:
            return .int64
        default:
            return self // TODO: All other types
        }
    }

    /// Return code that converts the given value of this type to its external form.
    func kotlinConvertToExternal(value: String) -> String {
        switch self {
        case .int:
            return value + ".toLong()"
        default:
            return value // TODO: All other types
        }
    }

    /// Return code that converts the given value of our external type back to this type.
    func kotlinConvertFromExternal(value: String) -> String {
        switch self {
        case .int:
            return value + ".toInt()"
        default:
            return value // TODO: All other types
        }
    }

    /// Return the `@_cdecl` function equivalent of this type.
    var cdecl: TypeSignature {
        // TODO: Object types, etc
        switch self {
        case .int:
            return .int64
        case .string:
            return .named("JavaString", [])
        default:
            return self.kotlinExternal
        }
    }

    /// Return code that converst the given value of this type to its `@_cdecl` function form.
    func convertToCDecl(value: String) -> String {
        switch self {
        case .int:
            return "Int64(" + value + ")"
        case .string:
            return value + ".toJavaObject()!"
        default:
            return value // TODO: All other types
        }
    }

    /// Return code that converts the given value of our `@_cdecl` function type back to this type.
    func convertFromCDecl(value: String) -> String {
        switch self {
        case .int:
            return "Int(" + value + ")"
        case .string:
            return "try! String.fromJavaObject(" + value + ")"
        default:
            return value // TODO: All other types
        }
    }

    /// Return the Java equivalent of this type.
    var java: TypeSignature {
        switch self {
        case .int:
            return .int32
        default:
            return self // TODO: All other types
        }
    }

    /// Return code that converts the given value of this type to its Java form.
    func convertToJava(value: String) -> String {
        switch self {
        case .int:
            return "Int32(" + value + ")"
        default:
            return value // TODO: All other types
        }
    }

    /// Return code that converts the given value of our Java type back to this type.
    func convertFromJava(value: String) -> String {
        switch self {
        case .int:
            return "Int(" + value + ")"
        default:
            return value // TODO: All other types
        }
    }

    /// Return the JNI signature of this type.
    var jni: String {
        // TODO: Fix
        switch self {
        case .any:
            return "Ljava/lang/Object;"
        case .anyObject:
            return "Ljava/lang/Object;"
        case .array(_):
            return "Ljava/lang/Object;"
        case .bool:
            return "Z"
        case .character:
            return "C"
        case .composition:
            return "Ljava/lang/Object;"
        case .dictionary:
            return "Ljava/lang/Object;"
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
            return "Ljava/lang/Object;"
        case .member:
            return "Ljava/lang/Object;"
        case .metaType(_):
            return "Ljava/lang/Class;"
        case .module(_, let type):
            return type.jni
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
            default:
                return type.jni
            }
        case .range:
            return "Ljava/lang/Object;"
        case .set:
            return "Ljava/lang/Object;"
        case .string:
            return "Ljava/lang/String;"
        case .tuple(_, _):
            return "Ljava/lang/Object;"
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

extension KotlinVariableDeclaration {
    /// Check that this variable is bridgable and return its bridgable type.
    ///
    /// This function will add messages about invalid modifiers or types to this variable.
    func checkBridgable(translator: KotlinTranslator) -> TypeSignature? {
        guard checkNonPrivate(self, modifiers: modifiers, translator: translator) else {
            return nil
        }
        let type = declaredType.or(propertyType)
        guard type != .none else {
            messages.append(Message.kotlinBridgeUnknownType(self, source: translator.syntaxTree.source))
            return nil
        }
        return type
    }
}

extension KotlinFunctionDeclaration {
    /// Check that this function is bridgable.
    ///
    /// This function will add messages about invalid modifiers or types to this variable.
    func checkBridgable(translator: KotlinTranslator) -> Bool {
        guard checkNonPrivate(self, modifiers: modifiers, translator: translator) else {
            return false
        }
        return true
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

private func checkNonPrivate(_ sourceDerived: SourceDerived, modifiers: Modifiers, translator: KotlinTranslator) -> Bool {
    guard modifiers.visibility == .private || modifiers.visibility == .fileprivate else {
        return true
    }
    sourceDerived.messages.append(Message.kotlinBridgePrivate(sourceDerived, source: translator.syntaxTree.source))
    return false
}
