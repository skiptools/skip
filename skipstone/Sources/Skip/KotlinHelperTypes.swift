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
        case .base(_, _, let generics):
            generics.forEach { $0.appendKotlinMessages(to: statement) }
        case .classRestricted:
            break
        case .composition:
            statement.messages.append(.kotlinComposedTypes(statement))
        case .dictionary(let keyType, let valueType):
            keyType.appendKotlinMessages(to: statement)
            valueType.appendKotlinMessages(to: statement)
        case .function(let parameterTypes, let returnType):
            parameterTypes.forEach { $0.appendKotlinMessages(to: statement) }
            returnType.appendKotlinMessages(to: statement)
        case .member(_, let type):
            type.appendKotlinMessages(to: statement)
        case .metaType(let type):
            type.appendKotlinMessages(to: statement)
        case .optional(let type):
            type.appendKotlinMessages(to: statement)
        case .tuple(let labels, let types):
            if labels.contains(where: { $0 != nil }) {
                statement.messages.append(.kotlinTupleLabels(statement))
            }
            if types.count > 3 {
                statement.messages.append(.kotlinTupleArity(statement))
            }
            types.forEach { $0.appendKotlinMessages(to: statement) }
        case .unwrappedOptional(let type):
            type.appendKotlinMessages(to: statement)
        }
    }

    var kotlinMayBeSharedMutableValue: Bool {
        switch self {
        case .array:
            return true
        case .base(let name, let qualifiedName, _):
            let name = qualifiedName ?? name
            if let typeInfo = Self.builtinTypeInfo[name] {
                return typeInfo.mayBeSharedMutableValue
            }
            return true
        case .classRestricted:
            return false
        case .composition:
            return false
        case .dictionary:
            return true
        case .function:
            return false
        case .optional(let type):
            return type.kotlinMayBeSharedMutableValue
        case .member:
            return true
        case .metaType:
            return false
        case .tuple:
            return false
        case .unwrappedOptional(let type):
            return type.kotlinMayBeSharedMutableValue
        }
    }

    private func kotlin(isQualified: Bool) -> String {
        switch self {
        case .array(let elementType):
            return "Array<\(elementType.kotlin(isQualified: isQualified))>"
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
            return "Dictionary<\(keyType.kotlin(isQualified: isQualified)), \(valueType.kotlin(isQualified: isQualified))>"
        case .function(let paramTypes, let returnType):
            return "(\(paramTypes.map { $0.kotlin(isQualified: isQualified) }.joined(separator: ", "))) -> \(returnType.kotlin(isQualified: isQualified))"
        case .optional(let type):
            return "\(type.kotlin(isQualified: isQualified))?"
        case .member(let baseType, let type):
            return "\(baseType.kotlin(isQualified: isQualified)).\(type.kotlin(isQualified: false))"
        case .metaType(let baseType):
            return "\(baseType.kotlin(isQualified: isQualified))::"
        case .tuple(_, let types):
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
            return translateSwiftTypeName(typeName, isQualified: false)
        }
        let typeNameQualification = String(typeName[..<lastSeparator])
        guard typeNameQualification == "Swift" else {
            return typeName
        }
        let lastTypeName = String(typeName[typeName.index(after: lastSeparator)...])
        return translateSwiftTypeName(lastTypeName, isQualified: true)
    }

    private func translateSwiftTypeName(_ typeName: String, isQualified: Bool) -> String {
        guard let typeInfo = Self.builtinTypeInfo[typeName] else {
            return isQualified ? "Swift.\(typeName)" : typeName
        }
        return isQualified ? "\(typeInfo.package).\(typeInfo.name)" : typeInfo.name
    }

    private static let builtinTypeInfo: [String: (name: String, package: String, mayBeSharedMutableValue: Bool)] = [
        "Any": ("Any", "kotlin", true),
        "AnyObject": ("Any", "kotlin", false),
        "Array": ("Array", "SkipFoundation", true),
        "Bool": ("Boolean", "kotlin", false),
        "Character": ("Char", "kotlin", false),
        "Dictionary": ("Dictionary", "SkipFoundation", true),
        "Int": ("Int", "kotlin", false),
        "Int8": ("Byte", "kotlin", false),
        "Int16": ("Short", "kotlin", false),
        "Int32": ("Int", "kotlin", false),
        "Int64": ("Long", "kotlin", false),
        "Set": ("Set", "SkipFoundation", true),
        "String": ("String", "kotlin", false),
        "UInt": ("UInt", "kotlin", false),
        "UInt8": ("UByte", "kotlin", false),
        "UInt16": ("UShort", "kotlin", false),
        "UInt32": ("UInt", "kotlin", false),
        "UInt64": ("ULong", "kotlin", false),
        "Void": ("Unit", "kotlin", false),
    ]
}
