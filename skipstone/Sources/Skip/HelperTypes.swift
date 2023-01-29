import SwiftSyntax

/// A block of code.
struct CodeBlock {
    let parent: Statement

    var statements: [Statement] {
        get {
            return parent.children
        }
        set {
            parent.children = newValue
        }
    }
}

// TODO: Attributes, variadic, default value
/// A function parameter.
struct Parameter {
    let externalName: String
    var internalName: String {
        return _internalName ?? externalName
    }
    private let _internalName: String?
    let type: TypeSignature?

    init(externalName: String, internalName: String? = nil, type: TypeSignature?) {
        self.externalName = externalName
        _internalName = internalName
        self.type = type
    }

    var prettyPrintTree: PrettyPrintTree {
        var children: [PrettyPrintTree] = []
        if let internalName = _internalName {
            children.append(PrettyPrintTree(root: internalName))
        }
        if let type {
            children.append(PrettyPrintTree(root: type.description))
        }
        return PrettyPrintTree(root: externalName.isEmpty ? "_" : externalName, children: children)
    }
}

/// A source code type signature.
indirect enum TypeSignature: CustomStringConvertible {
    case array(TypeSignature)
    case base(String, [TypeSignature]) // A<B, C>
    case classRestricted // 'class'
    case composition([TypeSignature]) // (A & B & C)
    case dictionary(TypeSignature, TypeSignature)
    case function([TypeSignature], TypeSignature)
    case member(TypeSignature, TypeSignature) // A.B
    case metaType(TypeSignature) // A.Type
    case optional(TypeSignature)
    case tuple([TypeSignature])
    case unwrappedOptional(TypeSignature)


    var description: String {
        switch self {
        case .array(let type):
            return "[\(type)]"
        case .base(let string, let generics):
            guard !generics.isEmpty else {
                return string
            }
            return "\(string)<\(generics.map { $0.description }.joined(separator: ", "))>"
        case .classRestricted:
            return "class"
        case .composition(let types):
            return "(\(types.map { $0.description }.joined(separator: " & ")))"
        case .dictionary(let keyType, let valueType):
            return "[\(keyType): \(valueType)]"
        case .function(let paramTypes, let returnType):
            return "(\(paramTypes.map { $0.description }.joined(separator: ", ")) -> \(returnType)"
        case .optional(let type):
            return "\(type)?"
        case .member(let baseType, let type):
            return "\(baseType).\(type)"
        case .metaType(let baseType):
            return "\(baseType).Type"
        case .tuple(let types):
            return "(\(types.map { $0.description }.joined(separator: ", "))"
        case .unwrappedOptional(let type):
            return "\(type)!"
        }
    }

    /// Create a type signature for the given syntax.
    static func `for`(syntax: TypeSyntax) -> TypeSignature? {
        switch syntax.kind {
        case .arrayType:
            guard let arrayType = syntax.as(ArrayTypeSyntax.self), let elementType = self.for(syntax: arrayType.elementType) else {
                return nil
            }
            return .array(elementType)
        case .attributedType:
            guard let attributedType = syntax.as(AttributedTypeSyntax.self) else {
                return nil
            }
            // TODO: Attributes
            return self.for(syntax: attributedType.baseType)
        case .simpleTypeIdentifier:
            guard let simpleType = syntax.as(SimpleTypeIdentifierSyntax.self) else {
                return nil
            }
            let name = simpleType.name.text
            var genericTypes: [TypeSignature] = []
            if let generics = simpleType.genericArgumentClause?.arguments {
                genericTypes = generics.compactMap { self.for(syntax: $0.argumentType) }
                guard genericTypes.count == generics.count else {
                    return nil
                }
            }
            return .base(name, genericTypes)
        case .compositionType:
            guard let compositionType = syntax.as(CompositionTypeSyntax.self) else {
                return nil
            }
            let types = compositionType.elements.compactMap { self.for(syntax: $0.type) }
            guard types.count == compositionType.elements.count else {
                return nil
            }
            return .composition(types)
        case .dictionaryType:
            guard let dictionaryType = syntax.as(DictionaryTypeSyntax.self), let keyType = self.for(syntax: dictionaryType.keyType), let valueType = self.for(syntax: dictionaryType.valueType) else {
                return nil
            }
            return .dictionary(keyType, valueType)
        case .constrainedSugarType:
            guard let constrainedSugarType = syntax.as(ConstrainedSugarTypeSyntax.self) else {
                return nil
            }
            // TODO: any / some
            return self.for(syntax: constrainedSugarType.baseType)
        case .functionType:
            guard let functionType = syntax.as(FunctionTypeSyntax.self) else {
                return nil
            }
            let argumentTypes = functionType.arguments.compactMap { self.for(syntax: $0.type) }
            guard argumentTypes.count == functionType.arguments.count else {
                return nil
            }
            guard let returnType = self.for(syntax: functionType.returnType) else {
                return nil
            }
            return .function(argumentTypes, returnType)
        case .memberTypeIdentifier:
            guard let memberType = syntax.as(MemberTypeIdentifierSyntax.self), let baseType = self.for(syntax: memberType.baseType) else {
                return nil
            }
            let name = memberType.name.text
            var genericTypes: [TypeSignature] = []
            if let generics = memberType.genericArgumentClause?.arguments {
                genericTypes = generics.compactMap { self.for(syntax: $0.argumentType) }
                guard genericTypes.count == generics.count else {
                    return nil
                }
            }
            return .member(baseType, .base(name, genericTypes))
        case .metatypeType:
            guard let metaType = syntax.as(MetatypeTypeSyntax.self), let baseType = self.for(syntax: metaType.baseType) else {
                return nil
            }
            return .metaType(baseType)
        case .optionalType:
            guard let optionalType = syntax.as(OptionalTypeSyntax.self), let wrappedType = self.for(syntax: optionalType.wrappedType) else {
                return nil
            }
            return .optional(wrappedType)
        case .tupleType:
            guard let tupleType = syntax.as(TupleTypeSyntax.self) else {
                return nil
            }
            let elementTypes = tupleType.elements.compactMap { self.for(syntax: $0.type) }
            guard elementTypes.count == tupleType.elements.count else {
                return nil
            }
            return .tuple(elementTypes)
        case .implicitlyUnwrappedOptionalType:
            guard let unwrappedOptionalType = syntax.as(ImplicitlyUnwrappedOptionalTypeSyntax.self), let wrappedType = self.for(syntax: unwrappedOptionalType.wrappedType) else {
                return nil
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
            return nil
        }
    }
}
