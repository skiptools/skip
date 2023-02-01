extension Accessor where S: Statement {
    /// Translate to an equivalent Kotlin accessor.
    func translate(translator: KotlinTranslator) -> Accessor<KotlinStatement> {
        var kstatements: [KotlinStatement]? = nil
        if let statements {
            kstatements = statements.flatMap { translator.translateStatement($0) }
        }
        return Accessor<KotlinStatement>(parameterName: parameterName, statements: kstatements)
    }
}

extension Modifiers {
    /// Kotlin modifier string for a member.
    func kotlinMemberString(isOpen: Bool) -> String {
        let string: String
        switch visibility {
        case .default:
            fallthrough
        case .internal:
            string = "internal"
        case .open:
            string = "public"
        case .public:
            string = "public"
        case .private:
            string = "private"
        }
        if isOverride {
            return "\(string) override"
        }
        if isOpen {
            return "\(string) open"
        }
        return string
    }
}

extension Parameter where S: Statement {
    /// Translate to an equivalent Kotlin parameter.
    func translate(translator: KotlinTranslator) -> Parameter<KotlinStatement> {
        var kdefaultValue: KotlinStatement? = nil
        if let defaultValue {
            kdefaultValue = translator.translateStatement(defaultValue).first
        }
        return Parameter<KotlinStatement>(externalName: externalName, internalName: internalName, type: type, isVariadic: isVariadic, defaultValue: kdefaultValue)
    }
}

extension TypeSignature {
    /// Convert this type signature into the equivalent Kotlin type signature.
    var kotlin: TypeSignature {
        switch self {
        case .array(let elementType):
            return .array(elementType.kotlin)
        case .base(let typeName, let qualifiedTypeName, let genericTypes):
            let kotlinQualifiedTypeName = translateQualifiedTypeName(qualifiedTypeName)
            return .base(translateTypeName(typeName), kotlinQualifiedTypeName, genericTypes.map { $0.kotlin })
        case .classRestricted:
            return .base("Any", "Any", [])
        case .composition(let types):
            return .composition(types.map { $0.kotlin })
        case .dictionary(let keyType, let valueType):
            return .dictionary(keyType.kotlin, valueType.kotlin)
        case .function(let parameterTypes, let returnType):
            return .function(parameterTypes.map { $0.kotlin }, returnType.kotlin)
        case .member(let baseType, let type):
            return .member(baseType, type.kotlin)
        case .metaType(let baseType):
            return .metaType(baseType.kotlin)
        case .optional(let wrappedType):
            return .optional(wrappedType.kotlin)
        case .tuple(let elementTypes):
            return .tuple(elementTypes.map { $0.kotlin })
        case .unwrappedOptional(let wrappedType):
            return .unwrappedOptional(wrappedType.kotlin)
        }
    }

    private func translateTypeName(_ typeName: String) -> String {
        switch typeName {
        case "AnyObject":
            return "Any"
        case "Bool":
            return "Boolean"
        case "Character":
            return "Char"
        case "Int":
            return "Long"
        case "Int8":
            return "Byte"
        case "Int16":
            return "Short"
        case "Int32":
            return "Int"
        case "Int64":
            return "Long"
        case "UInt":
            return "ULong"
        case "UInt8":
            return "UByte"
        case "UInt16":
            return "UShort"
        case "UInt32":
            return "UInt"
        case "UInt64":
            return "ULong"
        default:
            return typeName
        }
    }

    private func translateQualifiedTypeName(_ qualifiedTypeName: String?) -> String? {
        guard let qualifiedTypeName else {
            return nil
        }

        var components = qualifiedTypeName.split(separator: ".")
        let lastTypeName = String(components.removeLast())
        let kotlinTypeName = translateTypeName(lastTypeName)
        if kotlinTypeName == lastTypeName {
            return qualifiedTypeName
        }
        let kotlinComponents = components.map { String($0) } + [kotlinTypeName]
        return kotlinComponents.joined(separator: ".")
    }
}
