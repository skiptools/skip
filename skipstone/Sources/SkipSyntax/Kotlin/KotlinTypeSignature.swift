extension TypeSignature {
    /// Kotlin description of this type.
    var kotlin: String {
        switch self {
        case .any:
            return "Any"
        case .anyObject:
            return "Any"
        case .array(let elementType):
            return "Array<\(elementType.kotlin)>"
        case .bool:
            return "Boolean"
        case .character:
            return "Char"
        case .composition:
            return "Any"
        case .dictionary(let keyType, let valueType):
            return "Dictionary<\(keyType.kotlin), \(valueType.kotlin)>"
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
            return "\(baseType.kotlin)::"
        case .named(let name, let generics):
            guard !generics.isEmpty else {
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
        case .set:
            return description
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
    func appendKotlinMessages(to node: KotlinSyntaxNode) {
        switch self {
        case .any:
            break
        case .anyObject:
            break
        case .array(let elementType):
            elementType.appendKotlinMessages(to: node)
        case .bool:
            break
        case .character:
            break
        case .composition:
            node.messages.append(.kotlinComposedTypes(node))
        case .dictionary(let keyType, let valueType):
            keyType.appendKotlinMessages(to: node)
            valueType.appendKotlinMessages(to: node)
        case .double:
            break
        case .float:
            break
        case .function(let parameters, let returnType):
            parameters.forEach { $0.type.appendKotlinMessages(to: node) }
            returnType.appendKotlinMessages(to: node)
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
            type.appendKotlinMessages(to: node)
        case .metaType(let type):
            type.appendKotlinMessages(to: node)
        case .named(_, let generics):
            generics.forEach { $0.appendKotlinMessages(to: node) }
        case .none:
            break
        case .optional(let type):
            type.appendKotlinMessages(to: node)
        case .range(let elementType):
            elementType.appendKotlinMessages(to: node)
        case .set(let elementType):
            elementType.appendKotlinMessages(to: node)
        case .string:
            break
        case .tuple(let labels, let types):
            if labels.contains(where: { $0 != nil }) {
                node.messages.append(.kotlinTupleLabels(node))
            }
            if types.count > 3 {
                node.messages.append(.kotlinTupleArity(node))
            }
            types.forEach { $0.appendKotlinMessages(to: node) }
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
            type.appendKotlinMessages(to: node)
        case .void:
            break
        }
    }

    /// Whether this type might represent a shared mutable value.
    func kotlinMayBeSharedMutableValue(codebaseInfo: KotlinCodebaseInfo.Context?) -> Bool {
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
        case .composition:
            return true
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
        case .named(let name, _):
            guard let codebaseInfo else {
                return true
            }
            return codebaseInfo.mayBeMutableValueType(qualifiedName: name)
        case .none:
            return true
        case .optional(let type):
            return type.kotlinMayBeSharedMutableValue(codebaseInfo: codebaseInfo)
        case .member(let base, let type):
            guard case .named(let name, _) = type else {
                return type.kotlinMayBeSharedMutableValue(codebaseInfo: codebaseInfo)
            }
            guard let codebaseInfo else {
                return true
            }
            return codebaseInfo.mayBeMutableValueType(qualifiedName: "\(base).\(name)")
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
            return types.contains { $0.kotlinMayBeSharedMutableValue(codebaseInfo: codebaseInfo) }
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
            return type.kotlinMayBeSharedMutableValue(codebaseInfo: codebaseInfo)
        case .void:
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
