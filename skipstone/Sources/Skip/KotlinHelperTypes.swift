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
    /// Kotlin description of this type.
    var kotlin: String {
        return kotlin(isQualified: false)
    }

    /// Kotlin description of the qualified form of this type.
    var qualifiedKotlin: String {
        return kotlin(isQualified: true)
    }

    /// Add appropriate messages if this type is not supported.
    func appendKotlinMessages(to statement: KotlinStatement) {
        switch self {
        case .array(let elementType):
            elementType.appendKotlinMessages(to: statement)
        case .base(_, _, let genericTypes):
            genericTypes.forEach { $0.appendKotlinMessages(to: statement) }
        case .classRestricted:
            break
        case .composition:
            statement.statementMessages.append(.kotlinComposedTypes(statement: statement))
        case .dictionary(let keyType, let valueType):
            keyType.appendKotlinMessages(to: statement)
            valueType.appendKotlinMessages(to: statement)
        case .function(let parameterTypes, let returnType):
            parameterTypes.forEach { $0.appendKotlinMessages(to: statement) }
            returnType.appendKotlinMessages(to: statement)
        case .member(_, let type):
            type.appendKotlinMessages(to: statement)
        case .metaType(let baseType):
            baseType.appendKotlinMessages(to: statement)
        case .optional(let wrappedType):
            wrappedType.appendKotlinMessages(to: statement)
        case .tuple(let elementTypes):
            // TODO: We could create larger arity classes
            if elementTypes.count > 3 {
                statement.statementMessages.append(.kotlinTupleArity(statement: statement))
            }
            elementTypes.forEach { $0.appendKotlinMessages(to: statement) }
        case .unwrappedOptional(let wrappedType):
            wrappedType.appendKotlinMessages(to: statement)
        }
    }

    private func kotlin(isQualified: Bool) -> String {
        switch self {
        case .array(let elementType):
            return "MutableList<\(elementType.kotlin(isQualified: isQualified))>"
        case .base(let name, let qualifiedName, let generics):
            let name = translateTypeName((isQualified ? qualifiedName : name) ?? name)
            guard !generics.isEmpty else {
                return name
            }
            return "\(name)<\(generics.map { $0.kotlin(isQualified: isQualified) }.joined(separator: ", "))>"
        case .classRestricted:
            return "Any"
        case .composition:
            return "Any"
        case .dictionary(let keyType, let valueType):
            return "MutableMap<\(keyType.kotlin(isQualified: isQualified)), \(valueType.kotlin(isQualified: isQualified))>"
        case .function(let paramTypes, let returnType):
            return "(\(paramTypes.map { $0.kotlin(isQualified: isQualified) }.joined(separator: ", "))) -> \(returnType.kotlin(isQualified: isQualified))"
        case .optional(let type):
            return "\(type.kotlin(isQualified: isQualified))?"
        case .member(let baseType, let type):
            return "\(baseType.kotlin(isQualified: isQualified)).\(type.kotlin(isQualified: false))"
        case .metaType(let baseType):
            return "\(baseType.kotlin(isQualified: isQualified))::"
        case .tuple(let types):
            if types.isEmpty {
                return "Unit"
            }
            let generics = types.map { $0.kotlin(isQualified: isQualified) }.joined(separator: ", ")
            if types.count == 2 {
                return "Pair<\(generics)>"
            } else if types.count == 3 {
                return "Triple<\(generics)>"
            } else {
                return "Any"
            }
        case .unwrappedOptional(let type):
            return type.kotlin(isQualified: isQualified)
        }
    }

    private func translateTypeName(_ typeName: String) -> String {
        guard let lastSeparator = typeName.lastIndex(of: ".") else {
            return translateUnqualifiedTypeName(typeName)
        }
        let lastTypeName = String(typeName[typeName.index(after: lastSeparator)...])
        let translatedLastTypeName = translateUnqualifiedTypeName(lastTypeName)
        guard translatedLastTypeName != lastTypeName else {
            return typeName
        }
        return typeName[...lastSeparator] + translatedLastTypeName
    }

    private func translateUnqualifiedTypeName(_ typeName: String) -> String {
        switch typeName {
        case "AnyObject":
            return "Any"
        case "Array":
            return "MutableList"
        case "Bool":
            return "Boolean"
        case "Character":
            return "Char"
        case "Dictionary":
            return "MutableMap"
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
        case "Set":
            return "MutableSet"
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
}
