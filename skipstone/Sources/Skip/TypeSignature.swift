import SwiftSyntax

/// A source code type signature.
indirect enum TypeSignature: CustomStringConvertible, Hashable {
    case any
    case anyObject
    case array(TypeSignature)
    case bool
    case character
    case composition([TypeSignature]) // (A & B & C)
    case dictionary(TypeSignature, TypeSignature)
    case double
    case float
    case function([Parameter], TypeSignature)
    case int
    case int8
    case int16
    case int32
    case int64
    case member(TypeSignature, TypeSignature) // A.B
    case metaType(TypeSignature) // A.Type
    case named(String, [TypeSignature]) // A<B, C>
    case none
    case optional(TypeSignature)
    case set(TypeSignature)
    case string
    case tuple([String?], [TypeSignature]) // (a: A, b: B)
    case uint
    case uint8
    case uint16
    case uint32
    case uint64
    case unwrappedOptional(TypeSignature)
    case void

    /// The element type of this array.
    var elementType: TypeSignature {
        switch self {
        case .array(let elementType):
            return elementType
        default:
            return .none
        }
    }

    /// The parameter types of this function.
    var parameters: [Parameter] {
        switch self {
        case .function(let parameters, _):
            return parameters
        default:
            return []
        }
    }

    /// The return type of this function.
    var returnType: TypeSignature {
        switch self {
        case .function(_, let returnType):
            return returnType
        default:
            return .none
        }
    }

    /// Attempt to replace `.none` cases in this type signature with information from the given signature.
    func or(_ typeSignature: TypeSignature) -> TypeSignature {
        switch self {
        case .array(.none):
            if case .array = typeSignature {
                return typeSignature
            }
        case .dictionary(let keyType, let valueType):
            if case .dictionary(let keyType2, let valueType2) = typeSignature {
                let resolvedKeyType = keyType.or(keyType2)
                let resolvedValueType = valueType.or(valueType2)
                return .dictionary(resolvedKeyType, resolvedValueType)
            }
        case .function(let parameters, let returnType):
            if case .function(let parameters2, let returnType2) = typeSignature {
                // We may use an empty parameters array to represent .none
                var resolvedParameters: [Parameter] = parameters
                if parameters.isEmpty {
                    resolvedParameters = parameters2
                } else if parameters.count == parameters2.count {
                    resolvedParameters = zip(parameters, parameters2).map { $0.0.or($0.1.type) }
                }
                return .function(resolvedParameters, returnType.or(returnType2))
            }
        case .none:
            return typeSignature
        case .optional(.none):
            if case .optional = typeSignature {
                return typeSignature
            }
            if case .unwrappedOptional(let type) = typeSignature {
                return .optional(type)
            }
            return .optional(typeSignature)
        case .set(.none):
            if case .set = typeSignature {
                return typeSignature
            }
        case .tuple(let labels, let types):
            if case .tuple(_, let types2) = typeSignature, types.count == types2.count {
                let resolvedTypes = zip(types, types2).map { $0.0.or($0.1) }
                return .tuple(labels, resolvedTypes)
            }
        case .unwrappedOptional(.none):
            if case .unwrappedOptional = typeSignature {
                return typeSignature
            }
            if case .optional(let type) = typeSignature {
                return .unwrappedOptional(type)
            }
            return .unwrappedOptional(typeSignature)
        default:
            break
        }
        return self
    }

    /// Whether this is a floating point number.
    var isFloatingPoint: Bool {
        switch self {
        case .double:
            return true
        case .float:
            return true
        default:
            return false
        }
    }

    /// Whether this is a number type.
    var isNumeric: Bool {
        switch self {
        case .double:
            return true
        case .float:
            return true
        case .int:
            return true
        case .int8:
            return true
        case .int16:
            return true
        case .int32:
            return true
        case .int64:
            return true
        case .uint:
            return true
        case .uint8:
            return true
        case .uint16:
            return true
        case .uint32:
            return true
        case .uint64:
            return true
        default:
            return false
        }
    }

    /// Whether this is a string type.
    var isStringy: Bool {
        switch self {
        case .array(let elementType):
            return elementType == .character
        case .character:
            return true
        case .string:
            return true
        default:
            return false
        }
    }

    /// Whether this type may be represented by the given type using fuzzy matching.
    func isCompatible(with type: TypeSignature) -> Bool {
        if type == self {
            return true
        }

        var type = type
        if case .optional(let wrappedType) = type {
            type = wrappedType
        } else if case .unwrappedOptional(let wrappedType) = type {
            type = wrappedType
        }
        if type == self {
            return true
        }

        switch self {
        case .any:
            return true
        case .anyObject:
            return true
        case .array(let elementType):
            if case .array(let elementType2) = type {
                return elementType.isCompatible(with: elementType2)
            }
            if case .set(let elementType2) = type {
                return elementType.isCompatible(with: elementType2)
            }
        case .character:
            if type.isStringy {
                return true
            }
        case .dictionary(let keyType, let valueType):
            if case .dictionary(let keyType2, let valueType2) = type {
                return keyType.isCompatible(with: keyType2) && valueType.isCompatible(with: valueType2)
            }
        case .double:
            fallthrough
        case .float:
            fallthrough
        case .int:
            fallthrough
        case .int8:
            fallthrough
        case .int16:
            fallthrough
        case .int32:
            fallthrough
        case .int64:
            fallthrough
        case .uint:
            fallthrough
        case .uint8:
            fallthrough
        case .uint16:
            fallthrough
        case .uint32:
            fallthrough
        case .uint64:
            if type.isNumeric {
                return true
            }
        case .function:
            if case .function = type {
                return true
            }
        case .named(let name, _):
            if case .named(let name2, _) = type {
                return name == name2
            }
        case .none:
            return true
        case .optional(let wrappedType):
            return wrappedType.isCompatible(with: type)
        case .set(let elementType):
            if case .array(let elementType2) = type {
                return elementType.isCompatible(with: elementType2)
            }
            if case .set(let elementType2) = type {
                return elementType.isCompatible(with: elementType2)
            }
        case .string:
            if type.isStringy {
                return true
            }
        case .tuple(_, let types):
            if case .tuple(_, let types2) = type {
                return types.count == types2.count && !zip(types, types2).contains(where: { !$0.0.isCompatible(with: $0.1) })
            }
        case .unwrappedOptional(let wrappedType):
            return wrappedType.isCompatible(with: type)
        case .void:
            return type == .none
        default:
            break
        }
        return type == .none || type == .any || type == .anyObject
    }

    /// Create a type signature for the given syntax.
    static func `for`(syntax: TypeSyntax) -> TypeSignature {
        switch syntax.kind {
        case .arrayType:
            guard let arrayType = syntax.as(ArrayTypeSyntax.self) else {
                return .none
            }
            let elementType = self.for(syntax: arrayType.elementType)
            return elementType == .none ? .none : .array(elementType)
        case .attributedType:
            guard let attributedType = syntax.as(AttributedTypeSyntax.self) else {
                return .none
            }
            return self.for(syntax: attributedType.baseType)
        case .simpleTypeIdentifier:
            guard let simpleType = syntax.as(SimpleTypeIdentifierSyntax.self) else {
                return .none
            }
            let name = simpleType.name.text
            var genericTypes: [TypeSignature] = []
            if let generics = simpleType.genericArgumentClause?.arguments {
                genericTypes = generics.map { self.for(syntax: $0.argumentType) }
                guard !genericTypes.contains(.none) else {
                    return .none
                }
            }
            return self.for(name: name, genericTypes: genericTypes)
        case .compositionType:
            guard let compositionType = syntax.as(CompositionTypeSyntax.self) else {
                return .none
            }
            let types = compositionType.elements.map { self.for(syntax: $0.type) }
            guard !types.contains(.none) else {
                return .none
            }
            return .composition(types)
        case .dictionaryType:
            guard let dictionaryType = syntax.as(DictionaryTypeSyntax.self) else {
                return .none
            }
            let keyType = self.for(syntax: dictionaryType.keyType)
            let valueType = self.for(syntax: dictionaryType.valueType)
            guard keyType != .none, valueType != .none else {
                return .none
            }
            return .dictionary(keyType, valueType)
        case .constrainedSugarType:
            guard let constrainedSugarType = syntax.as(ConstrainedSugarTypeSyntax.self) else {
                return .none
            }
            return self.for(syntax: constrainedSugarType.baseType)
        case .functionType:
            guard let functionType = syntax.as(FunctionTypeSyntax.self) else {
                return .none
            }
            var parameters: [Parameter] = []
            for argumentSyntax in functionType.arguments {
                let label = argumentSyntax.name?.text
                let type = self.for(syntax: argumentSyntax.type)
                let isVariadic = argumentSyntax.ellipsis != nil
                let hasDefaultValue = argumentSyntax.initializer != nil
                parameters.append(Parameter(label: label, type: type, isVariadic: isVariadic, hasDefaultValue: hasDefaultValue))
            }
            let returnType = self.for(syntax: functionType.returnType)
            guard !parameters.contains(where: { $0.type == .none }) && returnType != .none else {
                return .none
            }
            return .function(parameters, returnType)
        case .memberTypeIdentifier:
            guard let memberType = syntax.as(MemberTypeIdentifierSyntax.self) else {
                return .none
            }
            let baseType = self.for(syntax: memberType.baseType)
            guard baseType != .none else {
                return .none
            }
            let name = memberType.name.text
            var genericTypes: [TypeSignature] = []
            if let generics = memberType.genericArgumentClause?.arguments {
                genericTypes = generics.map { self.for(syntax: $0.argumentType) }
                guard !genericTypes.contains(.none) else {
                    return .none
                }
            }
            return .member(baseType, .named(name, genericTypes))
        case .metatypeType:
            guard let metaType = syntax.as(MetatypeTypeSyntax.self) else {
                return .none
            }
            let baseType = self.for(syntax: metaType.baseType)
            guard baseType != .none else {
                return .none
            }
            return .metaType(baseType)
        case .optionalType:
            guard let optionalType = syntax.as(OptionalTypeSyntax.self) else {
                return .none
            }
            let wrappedType = self.for(syntax: optionalType.wrappedType)
            guard wrappedType != .none else {
                return .none
            }
            return .optional(wrappedType)
        case .tupleType:
            guard let tupleType = syntax.as(TupleTypeSyntax.self) else {
                return .none
            }
            let elementsSyntax = tupleType.elements
            let elements = elementsSyntax.map { (syntax: TupleTypeElementSyntax) -> (String?, TypeSignature) in
                let type = self.for(syntax: syntax.type)
                return (syntax.name?.text, type)
            }
            guard !elements.isEmpty else {
                return .void
            }
            guard !elements.contains(where: { $0.1 == .none }) else {
                return .none
            }
            return .tuple(elements.map(\.0), elements.map(\.1))
        case .implicitlyUnwrappedOptionalType:
            guard let unwrappedOptionalType = syntax.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) else {
                return .none
            }
            let wrappedType = self.for(syntax: unwrappedOptionalType.wrappedType)
            guard wrappedType != .none else {
                return .none
            }
            return .unwrappedOptional(wrappedType)

        // Unsupported
        case .missingType:
            fallthrough
        case .namedOpaqueReturnType:
            fallthrough
        case .packExpansionType:
            fallthrough
        case .packReferenceType:
            fallthrough
        default:
            return .none
        }
    }

    static func `for`(name: String, genericTypes: [TypeSignature]) -> TypeSignature {
        switch name {
        case "Any":
            return genericTypes.isEmpty ? .any : .named(name, genericTypes)
        case "AnyObject":
            return genericTypes.isEmpty ? .anyObject : .named(name, genericTypes)
        case "Array":
            return genericTypes.count == 1 ? .array(genericTypes[0]) : .named(name, genericTypes)
        case "Bool":
            return genericTypes.isEmpty ? .bool : .named(name, genericTypes)
        case "Character":
            return genericTypes.isEmpty ? .character : .named(name, genericTypes)
        case "Dictionary":
            return genericTypes.count == 2 ? .dictionary(genericTypes[0], genericTypes[1]) : .named(name, genericTypes)
        case "Double":
            return genericTypes.isEmpty ? .double : .named(name, genericTypes)
        case "Float":
            return genericTypes.isEmpty ? .float : .named(name, genericTypes)
        case "Int":
            return genericTypes.isEmpty ? .int : .named(name, genericTypes)
        case "Int8":
            return genericTypes.isEmpty ? .int8 : .named(name, genericTypes)
        case "Int16":
            return genericTypes.isEmpty ? .int16 : .named(name, genericTypes)
        case "Int32":
            return genericTypes.isEmpty ? .int32 : .named(name, genericTypes)
        case "Int64":
            return genericTypes.isEmpty ? .int64 : .named(name, genericTypes)
        case "Set":
            return genericTypes.count == 1 ? .set(genericTypes[0]) : .named(name, genericTypes)
        case "String":
            return genericTypes.isEmpty ? .string : .named(name, genericTypes)
        case "UInt":
            return genericTypes.isEmpty ? .uint : .named(name, genericTypes)
        case "UInt8":
            return genericTypes.isEmpty ? .uint8 : .named(name, genericTypes)
        case "UInt16":
            return genericTypes.isEmpty ? .uint16 : .named(name, genericTypes)
        case "UInt32":
            return genericTypes.isEmpty ? .uint32 : .named(name, genericTypes)
        case "UInt64":
            return genericTypes.isEmpty ? .uint64 : .named(name, genericTypes)
        case "Void":
            return genericTypes.isEmpty ? .void : .named(name, genericTypes)
        default:
            return .named(name, genericTypes)
        }
    }

    /// Qualify local type names with any enclosing types.
    func qualified(in node: SyntaxNode) -> TypeSignature {
        switch self {
        case .any:
            return self
        case .anyObject:
            return self
        case .array(let elementType):
            return .array(elementType.qualified(in: node))
        case .bool:
            return self
        case .character:
            return self
        case .composition(let types):
            return .composition(types.map { $0.qualified(in: node) })
        case .dictionary(let keyType, let valueType):
            return .dictionary(keyType.qualified(in: node), valueType.qualified(in: node))
        case .double:
            return self
        case .float:
            return self
        case .function(let parameters, let returnType):
            let qualifiedParameters = parameters.map { Parameter(label: $0.label, type: $0.type.qualified(in: node), isVariadic: $0.isVariadic, hasDefaultValue: $0.hasDefaultValue) }
            return .function(qualifiedParameters, returnType.qualified(in: node))
        case .int:
            return self
        case .int8:
            return self
        case .int16:
            return self
        case .int32:
            return self
        case .int64:
            return self
        case .member(let baseType, let type):
            return .member(baseType.qualified(in: node), type)
        case .metaType(let type):
            return .metaType(type.qualified(in: node))
        case .named(let name, let generics):
            return .named(node.qualifyReferencedTypeName(name), generics.map { $0.qualified(in: node) })
        case .none:
            return self
        case .optional(let type):
            return .optional(type.qualified(in: node))
        case .set(let elementType):
            return .set(elementType.qualified(in: node))
        case .string:
            return self
        case .tuple(let labels, let types):
            return .tuple(labels, types.map { $0.qualified(in: node) })
        case .uint:
            return self
        case .uint8:
            return self
        case .uint16:
            return self
        case .uint32:
            return self
        case .uint64:
            return self
        case .unwrappedOptional(let type):
            return .unwrappedOptional(type.qualified(in: node))
        case .void:
            return self
        }
    }

    var description: String {
        switch self {
        case .any:
            return "Any"
        case .anyObject:
            return "AnyObject"
        case .array(let elementType):
            return "[\(elementType.description)]"
        case .bool:
            return "Bool"
        case .character:
            return "Character"
        case .composition(let types):
            return "(\(types.map { $0.description }.joined(separator: " & ")))"
        case .dictionary(let keyType, let valueType):
            return "[\(keyType.description): \(valueType.description)]"
        case .double:
            return "Double"
        case .float:
            return "Float"
        case .function(let paramTypes, let returnType):
            return "(\(paramTypes.map { $0.description }.joined(separator: ", "))) -> \(returnType.description)"
        case .int:
            return "Int"
        case .int8:
            return "Int8"
        case .int16:
            return "Int16"
        case .int32:
            return "Int32"
        case .int64:
            return "Int64"
        case .member(let baseType, let type):
            return "\(baseType.description).\(type)"
        case .metaType(let baseType):
            switch baseType {
            case .function:
                return "(\(baseType.description)).Type"
            default:
                return "\(baseType.description).Type"
            }
        case .named(let name, let generics):
            guard !generics.isEmpty else {
                return name
            }
            return "\(name)<\(generics.map { $0.description }.joined(separator: ", "))>"
        case .none:
            return "<none>"
        case .optional(let type):
            switch type {
            case .function:
                return "(\(type.description))?"
            default:
                return "\(type.description)?"
            }
        case .set(let type):
            return "Set<\(type.description)>"
        case .string:
            return "String"
        case .tuple(let labels, let types):
            let descriptions = zip(labels, types).map {
                let typeDescription = $0.1.description
                guard let label = $0.0 else {
                    return typeDescription
                }
                return "\(label): \(typeDescription)"
            }
            return "(\(descriptions.joined(separator: ", ")))"
        case .uint:
            return "UInt"
        case .uint8:
            return "UInt8"
        case .uint16:
            return "UInt16"
        case .uint32:
            return "UInt32"
        case .uint64:
            return "UInt64"
        case .unwrappedOptional(let type):
            switch type {
            case .function:
                return "(\(type.description))!"
            default:
                return "\(type.description)!"
            }
        case .void:
            return "Void"
        }
    }

    /// A parameter in a function signature.
    struct Parameter: CustomStringConvertible, Hashable {
        var label: String?
        var type: TypeSignature
        var isVariadic = false
        var hasDefaultValue = false

        func or(_ typeSignature: TypeSignature) -> Parameter {
            var parameter = self
            parameter.type = parameter.type.or(typeSignature)
            return parameter
        }

        var description: String {
            var description = ""
            if let label {
                description += "\(label): "
            }
            description += type.description
            if isVariadic {
                description += "..."
            }
            return description
        }
    }
}
