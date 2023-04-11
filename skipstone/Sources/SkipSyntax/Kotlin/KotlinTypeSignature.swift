extension TypeSignature {
    /// Kotlin description of this type.
    var kotlin: String {
        switch self {
        case .any:
            return "Any"
        case .anyObject:
            return "Any"
        case .array(let elementType):
            if elementType == .none {
                return "Array"
            }
            return "Array<\(elementType.kotlin)>"
        case .bool:
            return "Boolean"
        case .character:
            return "Char"
        case .composition:
            return "Any"
        case .dictionary(let keyType, let valueType):
            if keyType == .none && valueType == .none {
                return "Dictionary"
            }
            return "Dictionary<\(keyType.or(.any).kotlin), \(valueType.or(.any).kotlin)>"
        case .double:
            return "Double"
        case .float:
            return "Float"
        case .function(let parameters, let returnType):
            return "(\(parameters.map { $0.kotlin }.joined(separator: ", "))) -> \(returnType.kotlin)"
        case .int:
            return "Int"
        case .int8:
            return "Byte"
        case .int16:
            return "Short"
        case .int32:
            return "Int"
        case .int64:
            return "Long"
        case .member(let baseType, let type):
            return "\(baseType.kotlin).\(type.kotlin)"
        case .metaType(let baseType):
            return "KClass<\(baseType.kotlin)>"
        case .named(let name, let generics):
            guard !generics.isEmpty && generics.contains(where: { $0 != .none }) else {
                return name
            }
            return "\(name)<\(generics.map { $0.kotlin }.joined(separator: ", "))>"
        case .none:
            return description
        case .optional(let type):
            switch type {
            case .function:
                return "(\(type.kotlin))?"
            default:
                return "\(type.kotlin)?"
            }
        case .range(let elementType):
            switch elementType {
            case .character:
                return "CharRange"
            case .int64:
                return "LongRange"
            default:
                return "IntRange"
            }
        case .set(let elementType):
            if elementType == .none {
                return "Set"
            }
            return "Set<\(elementType.kotlin)>"
        case .string:
            return "String"
        case .tuple(_, let types):
            if types.isEmpty {
                return "Unit"
            }
            let generics = types.map { $0.kotlin }.joined(separator: ", ")
            if types.count == 2 {
                return "Pair<\(generics)>"
            } else if types.count == 3 {
                return "Triple<\(generics)>"
            } else {
                return "Any"
            }
        case .uint:
            return "UInt"
        case .uint8:
            return "UByte"
        case .uint16:
            return "UShort"
        case .uint32:
            return "UInt"
        case .uint64:
            return "ULong"
        case .unwrappedOptional(let type):
            return type.kotlin
        case .void:
            return "Unit"
        }
    }

    /// Add appropriate messages if this type is not supported.
    func appendKotlinMessages(to node: KotlinSyntaxNode, source: Source) {
        switch self {
        case .any:
            break
        case .anyObject:
            break
        case .array(let elementType):
            elementType.appendKotlinMessages(to: node, source: source)
        case .bool:
            break
        case .character:
            break
        case .composition:
            node.messages.append(.kotlinComposedTypes(node, source: source))
        case .dictionary(let keyType, let valueType):
            keyType.appendKotlinMessages(to: node, source: source)
            valueType.appendKotlinMessages(to: node, source: source)
        case .double:
            break
        case .float:
            break
        case .function(let parameters, let returnType):
            parameters.forEach { $0.type.appendKotlinMessages(to: node, source: source) }
            returnType.appendKotlinMessages(to: node, source: source)
        case .int:
            break
        case .int8:
            break
        case .int16:
            break
        case .int32:
            break
        case .int64:
            break
        case .member(_, let type):
            type.appendKotlinMessages(to: node, source: source)
        case .metaType(let type):
            type.appendKotlinMessages(to: node, source: source)
        case .named(_, let generics):
            generics.forEach { $0.appendKotlinMessages(to: node, source: source) }
        case .none:
            break
        case .optional(let type):
            type.appendKotlinMessages(to: node, source: source)
        case .range(let elementType):
            elementType.appendKotlinMessages(to: node, source: source)
        case .set(let elementType):
            elementType.appendKotlinMessages(to: node, source: source)
        case .string:
            break
        case .tuple(let labels, let types):
            if labels.contains(where: { $0 != nil }) {
                node.messages.append(.kotlinTupleLabels(node, source: source))
            }
            if types.count > 3 {
                node.messages.append(.kotlinTupleArity(node, source: source))
            }
            types.forEach { $0.appendKotlinMessages(to: node, source: source) }
        case .uint:
            break
        case .uint8:
            break
        case .uint16:
            break
        case .uint32:
            break
        case .uint64:
            break
        case .unwrappedOptional(let type):
            type.appendKotlinMessages(to: node, source: source)
        case .void:
            break
        }
    }

    /// Whether this type might represent a shared mutable struct.
    func kotlinMayBeSharedMutableStruct(codebaseInfo: CodebaseInfo.Context?) -> Bool {
        switch self {
        case .any:
            return true
        case .anyObject:
            return false
        case .array:
            return true
        case .bool:
            return false
        case .character:
            return false
        case .composition(let types):
            return !types.contains { $0.kotlinMayBeSharedMutableStruct(codebaseInfo: codebaseInfo) == false }
        case .dictionary:
            return true
        case .double:
            return false
        case .float:
            return false
        case .function:
            return false
        case .int:
            return false
        case .int8:
            return false
        case .int16:
            return false
        case .int32:
            return false
        case .int64:
            return false
        case .named:
            guard let codebaseInfo else {
                return true
            }
            return codebaseInfo.mayBeMutableStruct(type: self)
        case .none:
            return true
        case .optional(let type):
            return type.kotlinMayBeSharedMutableStruct(codebaseInfo: codebaseInfo)
        case .member:
            guard let codebaseInfo else {
                return true
            }
            return codebaseInfo.mayBeMutableStruct(type: self)
        case .metaType:
            return false
        case .range:
            return false
        case .set:
            return true
        case .string:
            return false
        case .tuple(_, let types):
            // We consider a tuple with a shared mutable type to itself be a shared mutable type because code may
            // use destructuring assignment to extract values without copying them, so we have to copy the whole tuple
            return types.contains { $0.kotlinMayBeSharedMutableStruct(codebaseInfo: codebaseInfo) }
        case .uint:
            return false
        case .uint8:
            return false
        case .uint16:
            return false
        case .uint32:
            return false
        case .uint64:
            return false
        case .unwrappedOptional(let type):
            return type.kotlinMayBeSharedMutableStruct(codebaseInfo: codebaseInfo)
        case .void:
            return false
        }
    }

    /// Whether this type represents an enum modeled with sealed classes.
    func kotlinIsSealedClassesEnum(codebaseInfo: CodebaseInfo.Context?) -> Bool {
        guard case .named = asOptional(false) else {
            return false
        }
        return codebaseInfo?.isSealedClassesEnum(type: self) == true
    }

    /// Whether this type uses `KClass`, which requires additional imports.
    var kotlinReferencesKClass: Bool {
        switch self {
        case .array(let elementType):
            return elementType.kotlinReferencesKClass
        case .composition(let types):
            return types.contains { $0.kotlinReferencesKClass }
        case .dictionary(let keyType, let valueType):
            return keyType.kotlinReferencesKClass || valueType.kotlinReferencesKClass
        case .function(let parameters, let returnType):
            return returnType.kotlinReferencesKClass || parameters.contains { $0.type.kotlinReferencesKClass }
        case .named(_, let genericTypes):
            return genericTypes.contains { $0.kotlinReferencesKClass }
        case .optional(let type):
            return type.kotlinReferencesKClass
        case .member(let base, let type):
            return base.kotlinReferencesKClass || type.kotlinReferencesKClass
        case .metaType:
            return true
        case .range(let elementType):
            return elementType.kotlinReferencesKClass
        case .set(let elementType):
            return elementType.kotlinReferencesKClass
        case .tuple(_, let types):
            return types.contains { $0.kotlinReferencesKClass }
        case .unwrappedOptional(let type):
            return type.kotlinReferencesKClass
        default:
            return false
        }
    }
}

extension TypeSignature.Parameter {
    /// Kotlin description of this parameter.
    var kotlin: String {
        return type.kotlin
    }
}
