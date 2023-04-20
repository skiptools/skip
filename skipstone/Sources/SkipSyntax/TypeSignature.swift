import SwiftSyntax

/// A source code type signature.
///
/// - Note: `Codable` for use in `CodebaseInfo`.
indirect enum TypeSignature: CustomStringConvertible, Hashable, Codable {
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
    case range(TypeSignature)
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

    /// The name of this type without generics.
    var name: String {
        switch self {
        case .array:
            return "Array"
        case .dictionary:
            return "Dictionary"
        case .named(let name, _):
            return name
        case .range:
            return "Range"
        case .set:
            return "Set"
        default:
            return descriptionUsing(\.name)
        }
    }

    /// The element type of this sequence.
    var elementType: TypeSignature {
        switch self {
        case .array(let elementType):
            return elementType
        case .dictionary(let keyType, let valueType):
            return .tuple(["key", "value"], [keyType, valueType])
        case .range(let elementType):
            return elementType
        case .set(let elementType):
            return elementType
        case .string:
            return .character
        default:
            return .none
        }
    }

    /// The parameter types of this function.
    var parameters: [Parameter] {
        switch self {
        case .function(let parameters, _):
            return parameters
        case .member(_, let type):
            return type.parameters
        default:
            return []
        }
    }

    /// The return type of this function.
    var returnType: TypeSignature {
        switch self {
        case .function(_, let returnType):
            return returnType
        case .member(_, let type):
            return type.returnType
        default:
            return .none
        }
    }

    /// If this is a tuple with matching element count, the decomposed tuple types.
    func tupleTypes(count: Int) -> [TypeSignature] {
        guard count > 0 else {
            return []
        }
        guard count > 1 else {
            return [self]
        }
        if case .tuple(_, let types) = self, types.count == count {
            return types
        }
        return Array(repeating: self, count: count)
    }

    /// Return the generics of this type.
    var generics: [TypeSignature] {
        switch self {
        case .array(let element):
            return element == .none ? [] : [element]
        case .dictionary(let key, let value):
            return key == .none && value == .none ? [] : [key, value]
        case .member(_, let type):
            return type.generics
        case .metaType(let type):
            return type.generics
        case .named(_, let generics):
            return generics
        case .optional(let type):
            return type.generics
        case .range(let element):
            return element == .none ? [] : [element]
        case .set(let element):
            return element == .none ? [] : [element]
        case .unwrappedOptional(let type):
            return type.generics
        default:
            return []
        }
    }

    /// Apply the given generic types.
    func withGenerics(_ generics: [TypeSignature]) -> TypeSignature {
        switch self {
        case .array:
            if generics.isEmpty {
                return .array(.none)
            } else if generics.count == 1 {
                return .array(generics[0])
            }
        case .dictionary:
            if generics.isEmpty {
                return .dictionary(.none, .none)
            } else if generics.count == 2 {
                return .dictionary(generics[0], generics[1])
            }
        case .member(let base, let type):
            // Special case for stripping generics
            if generics.isEmpty {
                return .member(base.withGenerics([]), type.withGenerics([]))
            }
            return .member(base, type.withGenerics(generics))
        case .metaType(let type):
            return .metaType(type.withGenerics(generics))
        case .named(let name, _):
            return .named(name, generics)
        case .optional(let type):
            return .optional(type.withGenerics(generics))
        case .range:
            if generics.isEmpty {
                return .set(.none)
            } else if generics.count == 1 {
                return .range(generics[0])
            }
        case .set:
            if generics.isEmpty {
                return .set(.none)
            } else if generics.count == 1 {
                return .set(generics[0])
            }
        case .unwrappedOptional(let type):
            return .unwrappedOptional(type.withGenerics(generics))
        default:
            break
        }
        return self
    }

    /// Apply the given generic types to form a constrained type with generics replaced by their constraints.
    func constrainedTypeWithGenerics(_ generics: Generics) -> TypeSignature {
        let generic = generics.constrainedType(of: self, fallback: .any)
        if generic != .none {
            return generic
        }
        switch self {
        case .array(let element):
            return .array(element.constrainedTypeWithGenerics(generics))
        case .composition(let types):
            return .composition(types.map { $0.constrainedTypeWithGenerics(generics) })
        case .dictionary(let key, let value):
            return .dictionary(key.constrainedTypeWithGenerics(generics), value.constrainedTypeWithGenerics(generics))
        case .function(let parameters, let returnType):
            return .function(parameters.map { $0.constrainedTypeWithGenerics(generics) }, returnType.constrainedTypeWithGenerics(generics))
        case .member(let base, let type):
            return .member(base.constrainedTypeWithGenerics(generics), type.constrainedTypeWithGenerics(generics))
        case .metaType(let base):
            return .metaType(base.constrainedTypeWithGenerics(generics))
        case .named(let name, let genericTypes):
            return .named(name, genericTypes.map { $0.constrainedTypeWithGenerics(generics) })
        case .optional(let type):
            return .optional(type.constrainedTypeWithGenerics(generics))
        case .range(let element):
            return .range(element.constrainedTypeWithGenerics(generics))
        case .set(let element):
            return .set(element.constrainedTypeWithGenerics(generics))
        case .tuple(let labels, let types):
            return .tuple(labels, types.map { $0.constrainedTypeWithGenerics(generics) })
        case .unwrappedOptional(let type):
            return .unwrappedOptional(type.constrainedTypeWithGenerics(generics))
        default:
            return self
        }
    }

    /// Return the generic mappings that were made from this type to the given type.
    func mergeGenericMappings(in target: TypeSignature, with generics: Generics) -> Generics {
        var generics = generics
        addGenericMappings(to: target, into: &generics)
        return generics
    }

    private func addGenericMappings(to: TypeSignature, into generics: inout Generics) {
        guard to != self else {
            return
        }
        if case .named(let name, []) = self, let index = generics.entries.firstIndex(where: { $0.name == name }) {
            if let whereEqual = generics.entries[index].whereEqual {
                generics.entries[index].whereEqual = whereEqual.or(to, replaceAny: true)
            } else {
                generics.entries[index].whereEqual = to
            }
            return
        }
        switch self {
        case .array(let element):
            if case .array(let element2) = to {
                element.addGenericMappings(to: element2, into: &generics)
            } else if case .set(let element2) = to {
                element.addGenericMappings(to: element2, into: &generics)
            } else if case .range(let element2) = to {
                element.addGenericMappings(to: element2, into: &generics)
            } else if case .named(_, let genericTypes) = to, genericTypes.count == 1 {
                element.addGenericMappings(to: genericTypes[0], into: &generics)
            }
        case .composition(let types):
            if case .composition(let types2) = to, types.count == types2.count {
                zip(types, types2).forEach { $0.0.addGenericMappings(to: $0.1, into: &generics) }
            }
        case .dictionary(let key, let value):
            if case .dictionary(let key2, let value2) = to {
                key.addGenericMappings(to: key2, into: &generics)
                value.addGenericMappings(to: value2, into: &generics)
            }
        case .function(let parameters, let returnType):
            if case .function(let parameters2, let returnType2) = to, parameters.count == parameters2.count {
                zip(parameters, parameters2).forEach { $0.0.type.addGenericMappings(to: $0.1.type, into: &generics) }
                returnType.addGenericMappings(to: returnType2, into: &generics)
            }
        case .member(let base, let type):
            if case .member(let base2, let type2) = to {
                base.addGenericMappings(to: base2, into: &generics)
                type.addGenericMappings(to: type2, into: &generics)
            }
        case .metaType(let base):
            if case .metaType(let base2) = to {
                base.addGenericMappings(to: base2, into: &generics)
            }
        case .named(let name, let genericTypes):
            if case .named(let name2, let genericTypes2) = to, name == name2, genericTypes.count == genericTypes2.count {
                zip(genericTypes, genericTypes2).forEach { $0.0.addGenericMappings(to: $0.1, into: &generics) }
            } else if genericTypes.count == 1 {
                if case .array(let element) = to {
                    genericTypes[0].addGenericMappings(to: element, into: &generics)
                } else if case .set(let element) = to {
                    genericTypes[0].addGenericMappings(to: element, into: &generics)
                } else if case .range(let element) = to {
                    genericTypes[0].addGenericMappings(to: element, into: &generics)
                }
            }
        case .optional(let type):
            if case .optional(let type2) = to {
                type.addGenericMappings(to: type2, into: &generics)
            } else {
                type.addGenericMappings(to: to, into: &generics)
            }
        case .range(let element):
            if case .range(let element2) = to {
                element.addGenericMappings(to: element2, into: &generics)
            } else if case .array(let element2) = to {
                element.addGenericMappings(to: element2, into: &generics)
            } else if case .set(let element2) = to {
                element.addGenericMappings(to: element2, into: &generics)
            } else if case .named(_, let genericTypes) = to, genericTypes.count == 1 {
                element.addGenericMappings(to: genericTypes[0], into: &generics)
            }
        case .set(let element):
            if case .set(let element2) = to {
                element.addGenericMappings(to: element2, into: &generics)
            } else if case .array(let element2) = to {
                element.addGenericMappings(to: element2, into: &generics)
            }
        case .tuple(_, let types):
            if case .tuple(_, let types2) = to, types.count == types2.count {
                zip(types, types2).forEach { $0.0.addGenericMappings(to: $0.1, into: &generics) }
            }
        case .unwrappedOptional(let type):
            if case .unwrappedOptional(let type2) = to {
                type.addGenericMappings(to: type2, into: &generics)
            } else {
                type.addGenericMappings(to: to, into: &generics)
            }
        default:
            break
        }
    }

    /// Whether this is a meta type.
    var isMetaType: Bool {
        if case .metaType = self {
            return true
        } else {
            return false
        }
    }

    /// Convert this type to/from a meta type.
    func asMetaType(_ meta: Bool) -> TypeSignature {
        switch self {
        case .metaType(let type):
            return type.asMetaType(meta)
        case .none:
            return .none
        case .optional(let type):
            return .optional(type.asMetaType(meta))
        case .unwrappedOptional(let type):
            return .unwrappedOptional(type.asMetaType(meta))
        default:
            if meta {
                return .metaType(self)
            } else {
                return self
            }
        }
    }

    /// Whether this is an optional type.
    var isOptional: Bool {
        if case .optional = self {
            return true
        } else {
            return false
        }
    }

    /// Convert this type to/from an optional.
    func asOptional(_ optional: Bool) -> TypeSignature {
        switch self {
        case .none:
            return .none
        case .optional(let type):
            if optional {
                return self
            } else {
                return type
            }
        case .unwrappedOptional(let type):
            if optional {
                return .optional(type)
            } else {
                return type
            }
        default:
            return optional ? .optional(self) : self
        }
    }

    /// Visit this type and all contained types (e.g. the element type if this is an array).
    func visit(_ visitor: (TypeSignature) -> VisitResult<TypeSignature>) {
        var onExit: ((TypeSignature) -> Void)? = nil
        switch visitor(self) {
        case .skip:
            return
        case .recurse(let exit):
            onExit = exit
        }
        switch self {
        case .array(let element):
            element.visit(visitor)
        case .composition(let types):
            types.forEach { $0.visit(visitor) }
        case .dictionary(let key, let value):
            key.visit(visitor)
            value.visit(visitor)
        case .function(let parameters, let returnType):
            parameters.forEach { $0.type.visit(visitor) }
            returnType.visit(visitor)
        case .member(let base, let type):
            base.visit(visitor)
            type.visit(visitor)
        case .metaType(let type):
            type.visit(visitor)
        case .named(_, let generics):
            generics.forEach { $0.visit(visitor) }
        case .optional(let type):
            type.visit(visitor)
        case .range(let element):
            element.visit(visitor)
        case .set(let element):
            element.visit(visitor)
        case .tuple(_, let types):
            types.forEach { $0.visit(visitor) }
        case .unwrappedOptional(let type):
            type.visit(visitor)
        default:
            break
        }
        onExit?(self)
    }

    /// Whether this signature uses the given type.
    func referencesType(_ target: TypeSignature) -> Bool {
        var references = false
        visit {
            if references || $0 == target {
                references = true
                return .skip
            }
            return .recurse(nil)
        }
        return references
    }

    /// Map `Self` constraints to the given type.
    func mappingSelf(to type: TypeSignature) -> TypeSignature {
        return mappingTypes(with: [.named("Self", []): type])
    }

    /// Map uses of one set of types to another.
    func mappingTypes(from: [TypeSignature], to: [TypeSignature]) -> TypeSignature {
        guard !from.isEmpty, from.count == to.count else {
            return self
        }
        return mappingTypes(with: Dictionary(uniqueKeysWithValues: zip(from, to)))
    }

    /// Map uses of one set of types to another.
    func mappingTypes(with map: [TypeSignature: TypeSignature]) -> TypeSignature {
        guard !map.isEmpty else {
            return self
        }
        if let mapped = map[self] {
            return mapped
        }
        switch self {
        case .array(let element):
            return .array(element.mappingTypes(with: map))
        case .composition(let types):
            return .composition(types.map { $0.mappingTypes(with: map) })
        case .dictionary(let key, let value):
            return .dictionary(key.mappingTypes(with: map), value.mappingTypes(with: map))
        case .function(let parameters, let returnType):
            return .function(parameters.map { $0.mappingTypes(with: map) }, returnType.mappingTypes(with: map))
        case .member(let base, let type):
            return .member(base.mappingTypes(with: map), type.mappingTypes(with: map))
        case .metaType(let type):
            return .metaType(type.mappingTypes(with: map))
        case .named(let name, let generics):
            return .named(name, generics.map { $0.mappingTypes(with: map) })
        case .optional(let type):
            return .optional(type.mappingTypes(with: map))
        case .range(let element):
            return .range(element.mappingTypes(with: map))
        case .set(let element):
            return .set(element.mappingTypes(with: map))
        case .tuple(let labels, let types):
            return .tuple(labels, types.map { $0.mappingTypes(with: map) })
        case .unwrappedOptional(let type):
            return .unwrappedOptional(type.mappingTypes(with: map))
        default:
            return self
        }
    }

    /// Qualify local type names with any enclosing types.
    func qualified(in node: SyntaxNode) -> TypeSignature {
        switch self {
        case .array(let elementType):
            return .array(elementType.qualified(in: node))
        case .composition(let types):
            return .composition(types.map { $0.qualified(in: node) })
        case .dictionary(let keyType, let valueType):
            return .dictionary(keyType.qualified(in: node), valueType.qualified(in: node))
        case .function(let parameters, let returnType):
            let qualifiedParameters = parameters.map { Parameter(label: $0.label, type: $0.type.qualified(in: node), isInOut: $0.isInOut, isVariadic: $0.isVariadic, hasDefaultValue: $0.hasDefaultValue) }
            return .function(qualifiedParameters, returnType.qualified(in: node))
        case .member(let baseType, let type):
            let base = baseType.qualified(in: node)
            if case .named(let name, let generics) = type {
                let generics = generics.map { $0.qualified(in: node) }
                return .member(base, .named(name, generics))
            } else {
                return .member(base, type)
            }
        case .metaType(let type):
            return .metaType(type.qualified(in: node))
        case .named(let name, let generics):
            let generics = generics.map { $0.qualified(in: node) }
            return node.qualifyReferencedNamedType(name: name, generics: generics)
        case .optional(let type):
            return .optional(type.qualified(in: node))
        case .range(let elementType):
            return .range(elementType.qualified(in: node))
        case .set(let elementType):
            return .set(elementType.qualified(in: node))
        case .tuple(let labels, let types):
            return .tuple(labels, types.map { $0.qualified(in: node) })
        case .unwrappedOptional(let type):
            return .unwrappedOptional(type.qualified(in: node))
        default:
            return self
        }
    }

    /// Attempt to replace `.none` cases in this type signature with information from the given signature.
    func or(_ typeSignature: TypeSignature, replaceAny: Bool = false) -> TypeSignature {
        switch self {
        case .any:
            if replaceAny && typeSignature.isFullySpecified {
                return typeSignature
            }
        case .array(let elementType):
            if case .array(let elementType2) = typeSignature {
                let resolvedElementType = elementType.or(elementType2, replaceAny: replaceAny)
                return .array(resolvedElementType)
            }
        case .dictionary(let keyType, let valueType):
            if case .dictionary(let keyType2, let valueType2) = typeSignature {
                let resolvedKeyType = keyType.or(keyType2, replaceAny: replaceAny)
                let resolvedValueType = valueType.or(valueType2, replaceAny: replaceAny)
                return .dictionary(resolvedKeyType, resolvedValueType)
            }
        case .function(let parameters, let returnType):
            if case .function(let parameters2, let returnType2) = typeSignature {
                // We may use an empty parameters array to represent .none
                var resolvedParameters: [Parameter] = parameters
                if parameters.isEmpty {
                    resolvedParameters = parameters2
                } else if parameters.count == parameters2.count {
                    resolvedParameters = zip(parameters, parameters2).map { $0.0.or($0.1, replaceAny: replaceAny) }
                }
                return .function(resolvedParameters, returnType.or(returnType2, replaceAny: replaceAny))
            }
        case .member(let base, let type):
            if case .member(let base2, let type2) = typeSignature {
                if base == base2 {
                    return .member(base, type.or(type2, replaceAny: replaceAny))
                }
            }
        case .metaType(let type):
            if case .metaType(let type2) = typeSignature {
                return .metaType(type.or(type2, replaceAny: replaceAny))
            }
        case .none:
            return typeSignature
        case .optional(let type):
            if case .optional(let type2) = typeSignature {
                return .optional(type.or(type2, replaceAny: replaceAny))
            }
            if case .unwrappedOptional(let type2) = typeSignature {
                return .optional(type.or(type2, replaceAny: replaceAny))
            }
        case .range(let elementType):
            if case .range(let elementType2) = typeSignature {
                let resolvedElementType = elementType.or(elementType2, replaceAny: replaceAny)
                return .range(resolvedElementType)
            }
        case .set(let elementType):
            if case .set(let elementType2) = typeSignature {
                let resolvedElementType = elementType.or(elementType2, replaceAny: replaceAny)
                return .set(resolvedElementType)
            }
        case .tuple(let labels, let types):
            if case .tuple(_, let types2) = typeSignature, types.count == types2.count {
                let resolvedTypes = zip(types, types2).map { $0.0.or($0.1, replaceAny: replaceAny) }
                return .tuple(labels, resolvedTypes)
            }
        case .unwrappedOptional(let type):
            if case .unwrappedOptional(let type2) = typeSignature {
                return .unwrappedOptional(type.or(type2, replaceAny: replaceAny))
            }
            if case .optional(let type2) = typeSignature {
                return .unwrappedOptional(type.or(type2, replaceAny: replaceAny))
            }
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

    /// Score this type's compatibility for use as a parameter of the given type.
    ///
    /// 2 = Exact match
    /// 1 = Compatible
    /// 0 = Unknown match
    /// nil = Not compatible
    ///
    /// Compound type with multiple elements return an average of their elements' scores.
    func compatibilityScore(target: TypeSignature, codebaseInfo: CodebaseInfo.Context) -> Double? {
        if self == target {
            return 2.0
        }
        var target = target
        var targetIsOptional = false
        if case .optional(let type) = target {
            target = type
            targetIsOptional = true
            if self == target {
                return 2.0
            }
        }

        switch self {
        case .array(let element):
            if case .array(let targetElement) = target {
                guard let elementScore = element.compatibilityScore(target: targetElement, codebaseInfo: codebaseInfo) else {
                    return nil
                }
                return (2.0 + elementScore) / 2.0
            }
            if case .set(let targetElement) = target {
                guard let elementScore = element.compatibilityScore(target: targetElement, codebaseInfo: codebaseInfo) else {
                    return nil
                }
                return (2.0 + elementScore) / 2.0
            }
        case .character:
            if target.isStringy {
                return 1.0
            }
        case .dictionary(let keyType, let valueType):
            if case .dictionary(let keyType2, let valueType2) = target {
                guard let keyScore = keyType.compatibilityScore(target: keyType2, codebaseInfo: codebaseInfo), let valueScore = valueType.compatibilityScore(target: valueType2, codebaseInfo: codebaseInfo) else {
                    return nil
                }
                return (2.0 + keyScore + 2.0 + valueScore) / 4.0
            }
        case .double, .float:
            if target.isFloatingPoint {
                return 1.5
            }
            if target.isNumeric {
                return 1.0
            }
        case .int, .int8, .int16, .int32, .int64, .uint, .uint8, .uint16, .uint64:
            if target.isFloatingPoint {
                return 1.0
            }
            if target.isNumeric {
                return 1.5
            }
        case .function:
            // TODO: Match params and return type
            if case .function = target {
                return 1.0
            }
        case .member, .named:
            // TODO: Match on generics
            let type = withGenerics([])
            let target = target.withGenerics([])
            // Consider a match on all except generics a very close match
            if type == target {
                return 1.95
            }
            // Take away a tenth of a point for each level down the inheritance chain, so that less derived matches score lower.
            // This will allow another function with a more specific parameter type to score higher
            let inherits = codebaseInfo.global.inheritanceChainSignatures(forNamed: type)
            if inherits.count > 1 {
                for i in 1..<inherits.count {
                    if inherits[i].withGenerics([]) == target {
                        return 2.0 - (Double(i) * 0.1)
                    }
                }
            }
            let protocols = codebaseInfo.global.protocolSignatures(forNamed: type).map { $0.withGenerics([]) }
            if protocols.contains(target) {
                return 1.5
            }
        case .none:
            return 0.0
        case .optional(let type):
            guard targetIsOptional else {
                // Can't pass an optional value to a non-optional parameter
                return nil
            }
            return type.compatibilityScore(target: target, codebaseInfo: codebaseInfo)
        case .range(let element):
            if case .range(let targetElement) = target {
                guard let elementScore = element.compatibilityScore(target: targetElement, codebaseInfo: codebaseInfo) else {
                    return nil
                }
                return (2.0 + elementScore) / 2.0
            }
        case .set(let element):
            if case .set(let targetElement) = target {
                guard let elementScore = element.compatibilityScore(target: targetElement, codebaseInfo: codebaseInfo) else {
                    return nil
                }
                return (2.0 + elementScore) / 2.0
            }
        case .string:
            if target.isStringy {
                return 1.0
            }
        case .tuple(_, let types):
            if case .tuple(_, let targetTypes) = target {
                guard types.count == targetTypes.count else {
                    return nil
                }
                var totalScore = 0.0
                for (type, targetType) in zip(types, targetTypes) {
                    guard let score = type.compatibilityScore(target: targetType, codebaseInfo: codebaseInfo) else {
                        return nil
                    }
                    totalScore += score
                }
                return (2.0 + totalScore) / Double(1 + types.count)
            }
        case .unwrappedOptional(let type):
            return type.compatibilityScore(target: target, codebaseInfo: codebaseInfo)
        case .void:
            if target == .none {
                return 1.0
            }
        default:
            break
        }

        switch target {
        case .any, .anyObject:
            return 1.0
        case .none:
            return 0.0
        default:
            return nil
        }
    }

    /// Whether this type signature does not have any `.none` values.
    var isFullySpecified: Bool {
        var isSpecified = true
        visit {
            if !isSpecified || $0 == .none {
                isSpecified = false
                return .skip
            }
            return .recurse(nil)
        }
        return isSpecified
    }

    /// Whether the given syntax is an inout value.
    static func isInOut(syntax: TypeSyntax) -> Bool {
        switch syntax.kind {
        case .attributedType:
            guard let attributedType = syntax.as(AttributedTypeSyntax.self) else {
                return false
            }
            return attributedType.specifier?.text == "inout"
        default:
            return false
        }
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
                let isInOut = isInOut(syntax: argumentSyntax.type)
                let isVariadic = argumentSyntax.ellipsis != nil
                let hasDefaultValue = argumentSyntax.initializer != nil
                parameters.append(Parameter(label: label, type: type, isInOut: isInOut, isVariadic: isVariadic, hasDefaultValue: hasDefaultValue))
            }
            let returnType = self.for(syntax: functionType.output.returnType)
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
            guard elements.count > 1 else {
                return elements[0].1
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

    static func `for`(name: String, genericTypes: [TypeSignature], allowNamed: Bool = true) -> TypeSignature {
        switch name {
        case "Any":
            return genericTypes.isEmpty ? .any : allowNamed ? .named(name, genericTypes) : .none
        case "AnyObject":
            return genericTypes.isEmpty ? .anyObject : allowNamed ? .named(name, genericTypes) : .none
        case "Any.Type":
            return .metaType(.any)
        case "Array":
            return genericTypes.isEmpty ? .array(.none) : allowNamed ? genericTypes.count == 1 ? .array(genericTypes[0]) : .named(name, genericTypes) : .none
        case "Bool":
            return genericTypes.isEmpty ? .bool : allowNamed ? .named(name, genericTypes) : .none
        case "Character":
            return genericTypes.isEmpty ? .character : allowNamed ? .named(name, genericTypes) : .none
        case "Dictionary":
            return genericTypes.isEmpty ? .dictionary(.none, .none) : genericTypes.count == 2 ? .dictionary(genericTypes[0], genericTypes[1]) : allowNamed ? .named(name, genericTypes) : .none
        case "Double":
            return genericTypes.isEmpty ? .double : allowNamed ? .named(name, genericTypes) : .none
        case "Float":
            return genericTypes.isEmpty ? .float : allowNamed ? .named(name, genericTypes) : .none
        case "Int":
            return genericTypes.isEmpty ? .int : allowNamed ? .named(name, genericTypes) : .none
        case "Int8":
            return genericTypes.isEmpty ? .int8 : allowNamed ? .named(name, genericTypes) : .none
        case "Int16":
            return genericTypes.isEmpty ? .int16 : allowNamed ? .named(name, genericTypes) : .none
        case "Int32":
            return genericTypes.isEmpty ? .int32 : allowNamed ? .named(name, genericTypes) : .none
        case "Int64":
            return genericTypes.isEmpty ? .int64 : allowNamed ? .named(name, genericTypes) : .none
        case "Range":
            return genericTypes.isEmpty ? .range(.none) : genericTypes.count == 1 ? .range(genericTypes[0]) : allowNamed ? .named(name, genericTypes) : .none
        case "Set":
            return genericTypes.isEmpty ? .set(.none) : genericTypes.count == 1 ? .set(genericTypes[0]) : allowNamed ? .named(name, genericTypes) : .none
        case "String":
            return genericTypes.isEmpty ? .string : allowNamed ? .named(name, genericTypes) : .none
        case "UInt":
            return genericTypes.isEmpty ? .uint : allowNamed ? .named(name, genericTypes) : .none
        case "UInt8":
            return genericTypes.isEmpty ? .uint8 : allowNamed ? .named(name, genericTypes) : .none
        case "UInt16":
            return genericTypes.isEmpty ? .uint16 : allowNamed ? .named(name, genericTypes) : .none
        case "UInt32":
            return genericTypes.isEmpty ? .uint32 : allowNamed ? .named(name, genericTypes) : .none
        case "UInt64":
            return genericTypes.isEmpty ? .uint64 : allowNamed ? .named(name, genericTypes) : .none
        case "Void":
            return genericTypes.isEmpty ? .void : allowNamed ? .named(name, genericTypes) : .none
        default:
            if !allowNamed {
                return .none
            }
            if let lastSeparator = name.lastIndex(of: "."), lastSeparator != name.index(before: name.endIndex) {
                let firstPart = String(name[..<lastSeparator])
                let lastName = String(name[name.index(after: lastSeparator)...])
                if lastName == "Type" || lastName == "self" {
                    return .metaType(self.for(name: firstPart, genericTypes: genericTypes))
                }
                let base = self.for(name: firstPart, genericTypes: [])
                let named: TypeSignature = .named(lastName, genericTypes)
                return .member(base, named)
            } else {
                return .named(name, genericTypes)
            }
        }
    }

    /// Return a tuple type made up of the given types.
    static func `for`(labels: [String?], types: [TypeSignature]) -> TypeSignature {
        guard !types.isEmpty else {
            return .void
        }
        guard types.count > 1 else {
            return types[0]
        }
        return .tuple(labels, types)
    }

    var description: String {
        return descriptionUsing(\.description)
    }

    private func descriptionUsing(_ keyPath: KeyPath<TypeSignature, String>) -> String {
        switch self {
        case .any:
            return "Any"
        case .anyObject:
            return "AnyObject"
        case .array(let elementType):
            return "[\(elementType[keyPath: keyPath])]"
        case .bool:
            return "Bool"
        case .character:
            return "Character"
        case .composition(let types):
            return "(\(types.map { $0[keyPath: keyPath] }.joined(separator: " & ")))"
        case .dictionary(let keyType, let valueType):
            return "[\(keyType[keyPath: keyPath]): \(valueType[keyPath: keyPath])]"
        case .double:
            return "Double"
        case .float:
            return "Float"
        case .function(let parameters, let returnType):
            return "(\(parameters.map { $0.descriptionUsing(keyPath) }.joined(separator: ", "))) -> \(returnType[keyPath: keyPath])"
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
            return "\(baseType[keyPath: keyPath]).\(type[keyPath: keyPath])"
        case .metaType(let baseType):
            switch baseType {
            case .any:
                return "Any.Type"
            case .function:
                return "(\(baseType[keyPath: keyPath])).Type"
            default:
                return "\(baseType[keyPath: keyPath]).Type"
            }
        case .named(let name, let generics):
            guard !generics.isEmpty else {
                return name
            }
            return "\(name)<\(generics.map { $0[keyPath: keyPath] }.joined(separator: ", "))>"
        case .none:
            return "<none>"
        case .optional(let type):
            switch type {
            case .function:
                return "(\(type[keyPath: keyPath]))?"
            default:
                return "\(type[keyPath: keyPath])?"
            }
        case .range(let type):
            return "Range<\(type[keyPath: keyPath])>"
        case .set(let type):
            return "Set<\(type[keyPath: keyPath])>"
        case .string:
            return "String"
        case .tuple(let labels, let types):
            let descriptions = zip(labels, types).map {
                let typeDescription = $0.1[keyPath: keyPath]
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
                return "(\(type[keyPath: keyPath]))!"
            default:
                return "\(type[keyPath: keyPath])!"
            }
        case .void:
            return "Void"
        }
    }

    /// A parameter in a function signature.
    struct Parameter: CustomStringConvertible, Hashable, Codable {
        var label: String?
        var type: TypeSignature
        var isInOut = false
        var isVariadic = false
        var hasDefaultValue = false

        func or(_ parameter: Parameter, replaceAny: Bool) -> Parameter {
            var resolved = self
            resolved.type = parameter.type.or(resolved.type, replaceAny: replaceAny)
            if parameter.isInOut {
                resolved.isInOut = true
            }
            return resolved
        }

        func mappingTypes(from: [TypeSignature], to: [TypeSignature]) -> Parameter {
            var parameter = self
            parameter.type = parameter.type.mappingTypes(from: from, to: to)
            return parameter
        }

        func mappingTypes(with map: [TypeSignature: TypeSignature]) -> Parameter {
            var parameter = self
            parameter.type = parameter.type.mappingTypes(with: map)
            return parameter
        }

        func constrainedTypeWithGenerics(_ generics: Generics) -> Parameter {
            var parameter = self
            parameter.type = parameter.type.constrainedTypeWithGenerics(generics)
            return parameter
        }

        var description: String {
            return descriptionUsing(\TypeSignature.description)
        }

        fileprivate func descriptionUsing(_ keyPath: KeyPath<TypeSignature, String>) -> String {
            var description = ""
            if let label {
                description += "\(label): "
            }
            if isInOut {
                description += "inout "
            }
            description += type[keyPath: keyPath]
            if isVariadic {
                description += "..."
            }
            return description
        }

        // Leave default values out of equality and hash values, just as Swift does not include default values in type comparisons

        static func ==(lhs: Parameter, rhs: Parameter) -> Bool {
            return lhs.label == rhs.label && lhs.type == rhs.type && lhs.isInOut == rhs.isInOut && lhs.isVariadic == rhs.isVariadic
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(label)
            hasher.combine(type)
            hasher.combine(isInOut)
            hasher.combine(isVariadic)
        }
    }
}
