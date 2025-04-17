import SwiftSyntax

/// A source code type signature.
///
/// Type signatures are nested, with some types acting as modifiers to their child types. The nesting of these modifiers is:
/// `typealiased(optional(meta(module(member(T)))))`
///
/// - Warning: Use the factory methods of this enum to extract and apply modifiers rather than attempting to create enums by hand.
/// - Note: `Codable` for use in `CodebaseInfo`.
indirect enum TypeSignature: CustomStringConvertible, Hashable, Codable {
    case any
    case anyObject
    case array(TypeSignature?) // Nil means the generic type has been erased
    case bool
    case character
    case composition([TypeSignature]) // (A & B & C)
    case dictionary(TypeSignature?, TypeSignature?) // Nil means the generic type has been erased
    case existential(ExistentialMode, TypeSignature) // any A
    case double
    case float
    case function([Parameter], TypeSignature, APIFlags, Attributes?)
    case int
    case int8
    case int16
    case int32
    case int64
    case int128
    case member(TypeSignature, TypeSignature) // A.B
    case metaType(TypeSignature) // A.Type
    case module(String, TypeSignature) // Module.Type
    case named(String, [TypeSignature]) // A<B, C>
    case none
    case optional(TypeSignature)
    case range(TypeSignature?) // Nil means the generic type has been erased
    case set(TypeSignature?) // Nil means the generic type has been erased
    case string
    case tuple([String?], [TypeSignature]) // (a: A, b: B)
    case typealiased(Typealias, TypeSignature) // typealias (A = B), Type
    case uint
    case uint8
    case uint16
    case uint32
    case uint64
    case uint128
    case unwrappedOptional(TypeSignature)
    case void

    /// Whether the given signature represents the same type.
    func isSameType(as other: TypeSignature, withoutOptionality: Bool = false) -> Bool {
        let moduleName = self.moduleName
        let otherModuleName = other.moduleName
        guard moduleName == nil || otherModuleName == nil || moduleName == otherModuleName else {
            return false
        }
        guard withoutOptionality || (isOptional == other.isOptional && isUnwrappedOptional == other.isUnwrappedOptional) else {
            return false
        }
        return asTypealiased(nil).withoutOptionality().withExistentialMode(.none).withModuleName(nil).withAPIFlags(APIFlags()) == other.asTypealiased(nil).withoutOptionality().withExistentialMode(.none).withModuleName(nil).withAPIFlags(APIFlags())
    }

    /// What type this was typealiased from, if any.
    var typealiased: Typealias? {
        switch self {
        case .typealiased(let alias, _):
            return alias
        default:
            return nil
        }
    }

    /// Mark this type as typealiased from another.
    func asTypealiased(_ alias: Typealias?) -> TypeSignature {
        switch self {
        case .none:
            return self
        case .typealiased(_, let type):
            return alias == nil ? type : .typealiased(alias!, type)
        default:
            return alias == nil ? self : .typealiased(alias!, self)
        }
    }

    /// Whether this is an optional type.
    var isOptional: Bool {
        switch self {
        case .optional:
            return true
        case .typealiased(_, let type):
            return type.isOptional
        default:
            return false
        }
    }

    /// Convert this type to/from an optional.
    func asOptional(_ optional: Bool) -> TypeSignature {
        switch self {
        case .none:
            return .none
        case .optional(let type):
            return optional ? self : type
        case .typealiased(let alias, let type):
            return .typealiased(alias, type.asOptional(optional))
        case .unwrappedOptional(let type):
            return optional ? .optional(type) : self
        default:
            return optional ? .optional(self) : self
        }
    }

    /// Whether this is an unwrapped optional type.
    var isUnwrappedOptional: Bool {
        switch self {
        case .typealiased(_, let type):
            return type.isUnwrappedOptional
        case .unwrappedOptional:
            return true
        default:
            return false
        }
    }

    /// Convert this type to/from an unwrapped optional.
    func asUnwrappedOptional(_ unwrapped: Bool) -> TypeSignature {
        switch self {
        case .none:
            return .none
        case .optional(let type):
            return unwrapped ? .unwrappedOptional(type) : self
        case .typealiased(let alias, let type):
            return .typealiased(alias, type.asUnwrappedOptional(unwrapped))
        case .unwrappedOptional(let type):
            return unwrapped ? self : type
        default:
            return unwrapped ? .unwrappedOptional(self) : self
        }
    }

    /// Erase all optionality.
    func withoutOptionality() -> TypeSignature {
        switch self {
        case .optional(let type):
            return type
        case .typealiased(let alias, let type):
            return .typealiased(alias, type.withoutOptionality())
        case .unwrappedOptional(let type):
            return type
        default:
            return self
        }
    }

    /// Existential mode.
    var existentialMode: ExistentialMode {
        switch self {
        case .existential(let mode, _):
            return mode
        case .optional(let type):
            return type.existentialMode
        case .typealiased(_, let type):
            return type.existentialMode
        case .unwrappedOptional(let type):
            return type.existentialMode
        default:
            return .none
        }
    }

    /// Assign the existential mode.
    func withExistentialMode(_ mode: ExistentialMode) -> TypeSignature {
        switch self {
        case .existential(_, let type):
            return mode == .none ? type : .existential(mode, type)
        case .module, .member, .named:
            return mode == .none ? self : .existential(mode, self)
        case .metaType(let type):
            return .metaType(type.withExistentialMode(mode))
        case .optional(let type):
            return .optional(type.withExistentialMode(mode))
        case .typealiased(let alias, let type):
            return .typealiased(alias, type.withExistentialMode(mode))
        case .unwrappedOptional(let type):
            return .unwrappedOptional(type.withExistentialMode(mode))
        default:
            return self
        }
    }

    /// Whether this is a meta type.
    var isMetaType: Bool {
        switch self {
        case .existential(_, let type):
            return type.isMetaType
        case .metaType:
            return true
        case .optional(let type):
            return type.isMetaType
        case .typealiased(_, let type):
            return type.isMetaType
        case .unwrappedOptional(let type):
            return type.isMetaType
        default:
            return false
        }
    }

    /// Convert this type to/from a meta type.
    func asMetaType(_ meta: Bool, recursive: Bool = false) -> TypeSignature {
        switch self {
        case .array(var elementType):
            if recursive {
                elementType = elementType?.asMetaType(meta, recursive: true)
            }
            return meta ? .metaType(.array(elementType)) : .array(elementType)
        case .dictionary(var keyType, var valueType):
            if recursive {
                keyType = keyType?.asMetaType(meta, recursive: true)
                valueType = valueType?.asMetaType(meta, recursive: true)
            }
            return meta ? .metaType(.dictionary(keyType, valueType)) : .dictionary(keyType, valueType)
        case .metaType(let type):
            if meta {
                return self
            }
            return recursive ? type.asMetaType(false, recursive: true) : type
        case .none:
            return .none
        case .optional(let type):
            return .optional(type.asMetaType(meta, recursive: recursive))
        case .set(var elementType):
            if recursive {
                elementType = elementType?.asMetaType(meta, recursive: true)
            }
            return meta ? .metaType(.set(elementType)) : .set(elementType)
        case .typealiased(let alias, let type):
            return .typealiased(alias, type.asMetaType(meta, recursive: recursive))
        case .unwrappedOptional(let type):
            return .unwrappedOptional(type.asMetaType(meta, recursive: recursive))
        default:
            return meta ? .metaType(self) : self
        }
    }

    /// This type's module name, if specified.
    var moduleName: String? {
        switch self {
        case .existential(_, let type):
            return type.moduleName
        case .metaType(let type):
            return type.moduleName
        case .module(let moduleName, _):
            return moduleName
        case .optional(let type):
            return type.moduleName
        case .typealiased(_, let type):
            return type.moduleName
        case .unwrappedOptional(let type):
            return type.moduleName
        default:
            return nil
        }
    }

    /// Add a module name to this type.
    func withModuleName(_ moduleName: String?) -> TypeSignature {
        switch self {
        case .existential(let mode, let type):
            return .existential(mode, type.withModuleName(moduleName))
        case .member, .named:
            if let moduleName {
                return .module(moduleName, self)
            } else {
                return self
            }
        case .metaType(let type):
            return .metaType(type.withModuleName(moduleName))
        case .module(_, let type):
            return type.withModuleName(moduleName)
        case .none:
            return .none
        case .optional(let type):
            return .optional(type.withModuleName(moduleName))
        case .typealiased(let alias, let type):
            return .typealiased(alias, type.withModuleName(moduleName))
        case .unwrappedOptional(let type):
            return .unwrappedOptional(type.withModuleName(moduleName))
        default:
            return self
        }
    }

    /// The base type of this member, if any.
    var baseType: TypeSignature {
        switch self {
        case .existential(_, let type):
            return type.baseType
        case .member(let base, _):
            return base
        case .metaType(let type):
            return type.baseType.asMetaType(true)
        case .module(moduleName, let type):
            return type.baseType.withModuleName(moduleName)
        case .optional(let type):
            return type.baseType.asOptional(true)
        case .typealiased(_, let type):
            return type.baseType
        case .unwrappedOptional(let type):
            return type.baseType.asUnwrappedOptional(true)
        default:
            return .none
        }
    }

    /// The leaf type of this member, or the type itself.
    var memberType: TypeSignature {
        switch self {
        case .existential(_, let type):
            return type.memberType
        case .member(_, let type):
            return type
        case .metaType(let type):
            return type.memberType.asMetaType(true)
        case .module(_, let type):
            let member = type.memberType
            return member == type ? self : member
        case .optional(let type):
            return type.memberType.asOptional(true)
        case .typealiased(_, let type):
            let member = type.memberType
            return member == type ? self : member
        case .unwrappedOptional(let type):
            return type.memberType.asUnwrappedOptional(true)
        default:
            return self
        }
    }

    /// Make this type a member of the given type.
    func asMember(of baseType: TypeSignature) -> TypeSignature {
        if case .none = self {
            return .none
        }
        if case .none = baseType {
            return self
        }

        let isOptional = baseType.isOptional || self.isOptional
        let isUnwrappedOptional = baseType.isUnwrappedOptional || self.isUnwrappedOptional
        let isMetaType = baseType.isMetaType || self.isMetaType
        let existentialMode = baseType.existentialMode == .none ? self.existentialMode : baseType.existentialMode
        let moduleName = baseType.moduleName ?? self.moduleName

        let baseType = baseType.asTypealiased(nil).withoutOptionality().asMetaType(false).withExistentialMode(.none).withModuleName(nil)
        let memberType = self.asTypealiased(nil).withoutOptionality().asMetaType(false).withExistentialMode(.none).withModuleName(nil)
        let ret: TypeSignature
        switch memberType {
        case .member(let intermediate, let type):
            ret = type.asMember(of: intermediate.asMember(of: baseType))
        default:
            ret = .member(baseType, memberType)
        }
        return ret.withModuleName(moduleName).withExistentialMode(existentialMode).asMetaType(isMetaType).asUnwrappedOptional(isUnwrappedOptional).asOptional(isOptional)
    }

    /// The name of this type without generics and optionals.
    var name: String {
        switch self {
        case .array:
            return "Array"
        case .dictionary:
            return "Dictionary"
        case .existential(_, let type):
            return type.name
        case .named(let name, _):
            return name
        case .optional(let type):
            return type.name
        case .range:
            return "Range"
        case .set:
            return "Set"
        case .unwrappedOptional(let type):
            return type.name
        default:
            return descriptionUsing(\.name)
        }
    }

    /// Set the name of this named type.
    func withName(_ name: String) -> TypeSignature {
        switch self {
        case .existential(let mode, let type):
            return .existential(mode, type.withName(name))
        case .metaType(let type):
            return .metaType(type.withName(name))
        case .member(let owner, let type):
            return .member(owner, type.withName(name))
        case .module(let moduleName, let type):
            return .module(moduleName, type.withName(name))
        case .named(_, let generics):
            return .named(name, generics)
        case .optional(let type):
            return .optional(type.withName(name))
        case .unwrappedOptional(let type):
            return .unwrappedOptional(type.withName(name))
        default:
            return self
        }
    }

    /// The name of this type without package, outer types, generics, and optionals.
    var unqualifiedName: String {
        let name = self.name
        if let dotIndex = name.lastIndex(of: ".") {
            return String(name.suffix(from: name.index(after: dotIndex)))
        } else {
            return name
        }
    }

    /// The element type of this sequence.
    var elementType: TypeSignature {
        switch self {
        case .array(let elementType):
            return elementType ?? .none
        case .dictionary(let keyType, let valueType):
            if let keyType, let valueType {
                return .tuple(["key", "value"], [keyType, valueType])
            } else {
                return .none
            }
        case .member(_, let type):
            return type.elementType
        case .module(_, let type):
            return type.elementType
        case .optional(let type):
            return type.elementType
        case .range(let elementType):
            return elementType ?? .none
        case .set(let elementType):
            return elementType ?? .none
        case .string:
            return .character
        case .typealiased(_, let type):
            return type.elementType
        case .unwrappedOptional(let type):
            return type.elementType
        default:
            return .none
        }
    }

    /// Whether this is a function type.
    var isFunction: Bool {
        switch self {
        case .function:
            return true
        case .member(_, let type):
            return type.isFunction
        case .module(_, let type):
            return type.isFunction
        case .optional(let type):
            return type.isFunction
        case .typealiased(_, let type):
            return type.isFunction
        case .unwrappedOptional(let type):
            return type.isFunction
        default:
            return false
        }
    }

    /// The parameter types of this function.
    var parameters: [Parameter] {
        switch self {
        case .function(let parameters, _, _, _):
            return parameters
        case .member(_, let type):
            return type.parameters
        case .module(_, let type):
            return type.parameters
        case .optional(let type):
            return type.parameters
        case .typealiased(_, let type):
            return type.parameters
        case .unwrappedOptional(let type):
            return type.parameters
        default:
            return []
        }
    }

    /// Set the parameters for this function.
    func withParameters(_ parameters: [Parameter]) -> TypeSignature {
        switch self {
        case .function(_, let returnType, let apiFlags, let attributes):
            return .function(parameters, returnType, apiFlags, attributes)
        case .member(let base, let type):
            return .member(base, type.withParameters(parameters))
        case .module(let moduleName, let type):
            return .module(moduleName, type.withParameters(parameters))
        case .optional(let type):
            return .optional(type.withParameters(parameters))
        case .typealiased(let alias, let type):
            return .typealiased(alias, type.withParameters(parameters))
        case .unwrappedOptional(let type):
            return .unwrappedOptional(type.withParameters(parameters))
        default:
            return self
        }
    }

    /// The return type of this function.
    var returnType: TypeSignature {
        switch self {
        case .function(_, let returnType, _, _):
            return returnType
        case .member(_, let type):
            return type.returnType
        case .module(_, let type):
            return type.returnType
        case .optional(let type):
            return type.returnType
        case .typealiased(_, let type):
            return type.returnType
        case .unwrappedOptional(let type):
            return type.returnType
        default:
            return .none
        }
    }

    /// Set the return type for this function.
    func withReturnType(_ returnType: TypeSignature) -> TypeSignature {
        switch self {
        case .function(let parameters, _, let apiFlags, let attributes):
            return .function(parameters, returnType, apiFlags, attributes)
        case .member(let base, let type):
            return .member(base, type.withReturnType(returnType))
        case .module(let moduleName, let type):
            return .module(moduleName, type.withReturnType(returnType))
        case .optional(let type):
            return .optional(type.withReturnType(returnType))
        case .typealiased(let alias, let type):
            return .typealiased(alias, type.withReturnType(returnType))
        case .unwrappedOptional(let type):
            return .unwrappedOptional(type.withReturnType(returnType))
        default:
            return self
        }
    }

    /// The API flags for this function.
    var apiFlags: APIFlags {
        switch self {
        case .function(_, _, let apiFlags, _):
            return apiFlags
        case .member(_, let type):
            return type.apiFlags
        case .module(_, let type):
            return type.apiFlags
        case .optional(let type):
            return type.apiFlags
        case .typealiased(_, let type):
            return type.apiFlags
        case .unwrappedOptional(let type):
            return type.apiFlags
        default:
            return APIFlags()
        }
    }

    /// Set the API flags for this function.
    func withAPIFlags(_ apiFlags: APIFlags) -> TypeSignature {
        switch self {
        case .function(let parameters, let returnType, _, let attributes):
            return .function(parameters, returnType, apiFlags, attributes)
        case .member(let base, let type):
            return .member(base, type.withAPIFlags(apiFlags))
        case .module(let moduleName, let type):
            return .module(moduleName, type.withAPIFlags(apiFlags))
        case .optional(let type):
            return .optional(type.withAPIFlags(apiFlags))
        case .typealiased(let alias, let type):
            return .typealiased(alias, type.withAPIFlags(apiFlags))
        case .unwrappedOptional(let type):
            return .unwrappedOptional(type.withAPIFlags(apiFlags))
        default:
            return self
        }
    }

    /// The additional attributes for this function.
    var additionalAttributes: Attributes? {
        switch self {
        case .function(_, _, _, let attributes):
            return attributes
        case .member(_, let type):
            return type.additionalAttributes
        case .module(_, let type):
            return type.additionalAttributes
        case .optional(let type):
            return type.additionalAttributes
        case .typealiased(_, let type):
            return type.additionalAttributes
        case .unwrappedOptional(let type):
            return type.additionalAttributes
        default:
            return nil
        }
    }

    /// Set the additional attributes for this function.
    func withAdditionalAttributes(_ attributes: Attributes?) -> TypeSignature {
        switch self {
        case .function(let parameters, let returnType, let apiFlags, _):
            return .function(parameters, returnType, apiFlags, attributes)
        case .member(let base, let type):
            return .member(base, type.withAPIFlags(apiFlags))
        case .module(let moduleName, let type):
            return .module(moduleName, type.withAPIFlags(apiFlags))
        case .optional(let type):
            return .optional(type.withAPIFlags(apiFlags))
        case .typealiased(let alias, let type):
            return .typealiased(alias, type.withAPIFlags(apiFlags))
        case .unwrappedOptional(let type):
            return .unwrappedOptional(type.withAPIFlags(apiFlags))
        default:
            return self
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
        switch self {
        case .optional(let type):
            return type.tupleTypes(count: count).map { $0.asOptional(true) }
        case .tuple(_, let types):
            if types.count == count {
                return types
            }
        case .typealiased(_, let type):
            if type.isTuple {
                return type.tupleTypes(count: count)
            }
        case .unwrappedOptional(let type):
            return type.tupleTypes(count: count)
        default:
            break
        }
        return Array(repeating: self, count: count)
    }

    private var isTuple: Bool {
        switch self {
        case .optional(let type):
            return type.isTuple
        case .tuple:
            return true
        case .typealiased(_, let type):
            return type.isTuple
        case .unwrappedOptional(let type):
            return type.isTuple
        default:
            return false
        }
    }

    /// Return the generics of this type.
    var generics: [TypeSignature] {
        switch self {
        case .array(let element):
            if let element {
                return [element]
            } else {
                return []
            }
        case .dictionary(let key, let value):
            if let key, let value {
                return [key, value]
            } else {
                return []
            }
        case .existential(_, let type):
            return type.generics
        case .member(_, let type):
            return type.generics
        case .metaType(let type):
            return type.generics
        case .module(_, let type):
            return type.generics
        case .named(_, let generics):
            return generics
        case .optional(let type):
            return type.generics
        case .range(let element):
            if let element {
                return [element]
            } else {
                return []
            }
        case .set(let element):
            if let element {
                return [element]
            } else {
                return []
            }
        case .typealiased(_, let type):
            return type.generics
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
                return .array(nil)
            } else if generics.count == 1 {
                return .array(generics[0])
            }
        case .dictionary:
            if generics.isEmpty {
                return .dictionary(nil, nil)
            } else if generics.count == 2 {
                return .dictionary(generics[0], generics[1])
            }
        case .existential(let mode, let type):
            return .existential(mode, type.withGenerics(generics))
        case .member(let base, let type):
            // Special case for stripping generics
            if generics.isEmpty {
                return .member(base.withGenerics([]), type.withGenerics([]))
            }
            return .member(base, type.withGenerics(generics))
        case .metaType(let type):
            return .metaType(type.withGenerics(generics))
        case .module(let moduleName, let type):
            return .module(moduleName, type.withGenerics(generics))
        case .named(let name, _):
            return .named(name, generics)
        case .optional(let type):
            return .optional(type.withGenerics(generics))
        case .range:
            if generics.isEmpty {
                return .range(nil)
            } else if generics.count == 1 {
                return .range(generics[0])
            }
        case .set:
            if generics.isEmpty {
                return .set(nil)
            } else if generics.count == 1 {
                return .set(generics[0])
            }
        case .typealiased(let alias, let type):
            return Self.typealiasedWithGenerics(alias: alias, type: type, generics: generics)
        case .unwrappedOptional(let type):
            return .unwrappedOptional(type.withGenerics(generics))
        default:
            break
        }
        return self
    }

    /// Convert all generic types to the given type.
    func withGenerics(of type: TypeSignature) -> TypeSignature {
        let generics = self.generics
        guard !generics.isEmpty else {
            return self
        }
        return withGenerics(generics.map { _ in type })
    }

    private static func typealiasedWithGenerics(alias: Typealias, type: TypeSignature, generics: [TypeSignature]) -> TypeSignature {
        guard generics.count == alias.from.generics.count else {
            return .typealiased(alias, type.withGenerics(generics))
        }
        // Map from alias generics to result type generics
        let mappedGenerics = alias.to.generics.map { $0.mappingTypes(from: alias.from.generics, to: generics) }
        return .typealiased(alias, type.withGenerics(mappedGenerics))
    }

    /// Apply the given generic types to form a constrained type with generics replaced by their constraints.
    func constrainedTypeWithGenerics(_ generics: Generics) -> TypeSignature {
        let generic = generics.constrainedType(of: self, fallback: .any)
        if generic != .none {
            return generic
        }
        switch self {
        case .array(let element):
            return .array(element?.constrainedTypeWithGenerics(generics))
        case .composition(let types):
            return .composition(types.map { $0.constrainedTypeWithGenerics(generics) })
        case .dictionary(let key, let value):
            return .dictionary(key?.constrainedTypeWithGenerics(generics), value?.constrainedTypeWithGenerics(generics))
        case .existential(let mode, let type):
            return .existential(mode, type.constrainedTypeWithGenerics(generics))
        case .function(let parameters, let returnType, let apiFlags, let attributes):
            return .function(parameters.map { $0.constrainedTypeWithGenerics(generics) }, returnType.constrainedTypeWithGenerics(generics), APIFlags(options: apiFlags.options, throwsType: apiFlags.throwsType.constrainedTypeWithGenerics(generics)), attributes)
        case .member(let base, let type):
            return .member(base.constrainedTypeWithGenerics(generics), type.constrainedTypeWithGenerics(generics))
        case .metaType(let type):
            return .metaType(type.constrainedTypeWithGenerics(generics))
        case .module(let module, let type):
            return .module(module, type.constrainedTypeWithGenerics(generics))
        case .named(let name, let genericTypes):
            return .named(name, genericTypes.map { $0.constrainedTypeWithGenerics(generics) })
        case .optional(let type):
            return .optional(type.constrainedTypeWithGenerics(generics))
        case .range(let element):
            return .range(element?.constrainedTypeWithGenerics(generics))
        case .set(let element):
            return .set(element?.constrainedTypeWithGenerics(generics))
        case .tuple(let labels, let types):
            return .tuple(labels, types.map { $0.constrainedTypeWithGenerics(generics) })
        case .typealiased(let alias, let type):
            return .typealiased(alias, type.constrainedTypeWithGenerics(generics))
        case .unwrappedOptional(let type):
            return .unwrappedOptional(type.constrainedTypeWithGenerics(generics))
        default:
            return self
        }
    }

    /// Return the generic mappings that were made from this type to the given type.
    ///
    /// E.g. if this type is `A<T>` and the given target is `A<Int>`, adds `where T == Int`.
    func mergeGenericMappings(in target: TypeSignature, with generics: Generics) -> Generics {
        var generics = generics
        addGenericMappings(to: target, into: &generics)
        return generics
    }

    private func addGenericMappings(to: TypeSignature, into generics: inout Generics) {
        let to = to.asTypealiased(nil).withExistentialMode(.none)
        let selfType = self.withExistentialMode(.none)
        guard !to.isSameType(as: selfType) else {
            return
        }
        if case .named(let name, []) = selfType, let index = generics.entries.firstIndex(where: { $0.name == name }) {
            if let whereEqual = generics.entries[index].whereEqual {
                generics.entries[index].whereEqual = whereEqual.or(to, replaceAny: true)
            } else {
                generics.entries[index].whereEqual = to
            }
            return
        }
        switch selfType {
        case .array(let element):
            if let element {
                if case .array(let element2) = to, let element2 {
                    element.addGenericMappings(to: element2, into: &generics)
                } else if case .set(let element2) = to, let element2 {
                    element.addGenericMappings(to: element2, into: &generics)
                } else if case .range(let element2) = to, let element2 {
                    element.addGenericMappings(to: element2, into: &generics)
                } else if case .named(_, let genericTypes) = to, genericTypes.count == 1 {
                    element.addGenericMappings(to: genericTypes[0], into: &generics)
                }
            }
        case .composition(let types):
            if case .composition(let types2) = to, types.count == types2.count {
                zip(types, types2).forEach { $0.0.addGenericMappings(to: $0.1, into: &generics) }
            }
        case .dictionary(let key, let value):
            if case .dictionary(let key2, let value2) = to {
                if let key, let key2 {
                    key.addGenericMappings(to: key2, into: &generics)
                }
                if let value, let value2 {
                    value.addGenericMappings(to: value2, into: &generics)
                }
            }
        case .existential(_, let type):
            type.addGenericMappings(to: to.withExistentialMode(.none), into: &generics)
        case .function(let parameters, let returnType, let apiFlags, _):
            if case .function(let parameters2, let returnType2, let apiFlags2, _) = to, parameters.count == parameters2.count {
                zip(parameters, parameters2).forEach { $0.0.type.addGenericMappings(to: $0.1.type, into: &generics) }
                returnType.addGenericMappings(to: returnType2, into: &generics)
                apiFlags.throwsType.addGenericMappings(to: apiFlags2.throwsType, into: &generics)
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
        case .module(let module, let type):
            if case .module(let module2, let type2) = to {
                if module == module2 {
                    type.addGenericMappings(to: type2, into: &generics)
                }
            } else {
                type.addGenericMappings(to: to, into: &generics)
            }
        case .named(_, let genericTypes):
            var target = to
            if case .module(_, let type) = target {
                target = type
            } else if case .typealiased(_, let type) = target {
                target = type
            }
            if case .named(_, let genericTypes2) = target, genericTypes.count == genericTypes2.count {
                zip(genericTypes, genericTypes2).forEach { $0.0.addGenericMappings(to: $0.1, into: &generics) }
            } else if genericTypes.count == 1 {
                if case .array(let element) = target, let element {
                    genericTypes[0].addGenericMappings(to: element, into: &generics)
                } else if case .set(let element) = target, let element {
                    genericTypes[0].addGenericMappings(to: element, into: &generics)
                } else if case .range(let element) = target, let element {
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
            if let element {
                if case .range(let element2) = to, let element2 {
                    element.addGenericMappings(to: element2, into: &generics)
                } else if case .array(let element2) = to, let element2 {
                    element.addGenericMappings(to: element2, into: &generics)
                } else if case .set(let element2) = to, let element2 {
                    element.addGenericMappings(to: element2, into: &generics)
                } else if case .named(_, let genericTypes) = to, genericTypes.count == 1 {
                    element.addGenericMappings(to: genericTypes[0], into: &generics)
                }
            }
        case .set(let element):
            if let element {
                if case .set(let element2) = to, let element2 {
                    element.addGenericMappings(to: element2, into: &generics)
                } else if case .array(let element2) = to, let element2 {
                    element.addGenericMappings(to: element2, into: &generics)
                }
            }
        case .tuple(_, let types):
            if case .tuple(_, let types2) = to, types.count == types2.count {
                zip(types, types2).forEach { $0.0.addGenericMappings(to: $0.1, into: &generics) }
            }
        case .typealiased(_, let type):
            type.addGenericMappings(to: to, into: &generics)
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
            element?.visit(visitor)
        case .composition(let types):
            types.forEach { $0.visit(visitor) }
        case .dictionary(let key, let value):
            key?.visit(visitor)
            value?.visit(visitor)
        case .existential(_, let type):
            type.visit(visitor)
        case .function(let parameters, let returnType, let apiFlags, _):
            parameters.forEach { $0.type.visit(visitor) }
            returnType.visit(visitor)
            apiFlags.throwsType.visit(visitor)
        case .member(let base, let type):
            base.visit(visitor)
            type.visit(visitor)
        case .metaType(let type):
            type.visit(visitor)
        case .module(_, let type):
            type.visit(visitor)
        case .named(_, let generics):
            generics.forEach { $0.visit(visitor) }
        case .optional(let type):
            type.visit(visitor)
        case .range(let element):
            element?.visit(visitor)
        case .set(let element):
            element?.visit(visitor)
        case .typealiased(_, let type):
            type.visit(visitor)
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
        return mappingTypes {
            return $0 == .named("Self", []) ? type : nil
        }
    }

    /// Map uses of one set of types to another.
    func mappingTypes(from: [TypeSignature], to: [TypeSignature]) -> TypeSignature {
        guard !from.isEmpty, from.count == to.count else {
            return self
        }
        let dict = Dictionary(uniqueKeysWithValues: zip(from, to))
        return mappingTypes(with: { dict[$0] })
    }

    /// Map uses of one set of types to another.
    func mappingTypes(with map: (TypeSignature) -> TypeSignature?) -> TypeSignature {
        if let mapped = map(self) {
            return mapped
        }
        switch self {
        case .array(let element):
            return .array(element?.mappingTypes(with: map))
        case .composition(let types):
            return .composition(types.map { $0.mappingTypes(with: map) })
        case .dictionary(let key, let value):
            return .dictionary(key?.mappingTypes(with: map), value?.mappingTypes(with: map))
        case .existential(let mode, let type):
            return .existential(mode, type.mappingTypes(with: map))
        case .function(let parameters, let returnType, let apiFlags, let attributes):
            return .function(parameters.map { $0.mappingTypes(with: map) }, returnType.mappingTypes(with: map), APIFlags(options: apiFlags.options, throwsType: apiFlags.throwsType.mappingTypes(with: map)), attributes)
        case .member(let base, let type):
            let base = base.mappingTypes(with: map)
            // Do not map 'type' alone because it will be confused for any non-member type with the same name.
            // Only map its generics if needed
            if case .named(let name, let generics) = type {
                let type: TypeSignature = .named(name, generics.map { $0.mappingTypes(with: map) })
                return type.asMember(of: base)
            } else {
                return type.asMember(of: base)
            }
        case .metaType(let type):
            return type.mappingTypes(with: map).asMetaType(true)
        case .module(let moduleName, let type):
            // Retain the module name if the base type has not changed
            let mapped = type.mappingTypes(with: map)
            return mapped.withoutOptionality().asMetaType(false).name == type.withoutOptionality().asMetaType(false).name ? mapped.withModuleName(moduleName) : mapped
        case .named(let name, let generics):
            return .named(name, generics.map { $0.mappingTypes(with: map) })
        case .optional(let type):
            return type.mappingTypes(with: map).asOptional(true)
        case .range(let element):
            return .range(element?.mappingTypes(with: map))
        case .set(let element):
            return .set(element?.mappingTypes(with: map))
        case .tuple(let labels, let types):
            return .tuple(labels, types.map { $0.mappingTypes(with: map) })
        case .typealiased(let alias, let type):
            let mapped = type.mappingTypes(with: map)
            return mapped.isSameType(as: type, withoutOptionality: true) ? mapped.asTypealiased(alias) : mapped
        case .unwrappedOptional(let type):
            return type.mappingTypes(with: map).asUnwrappedOptional(true)
        default:
            return self
        }
    }

    /// Qualify local type names with any enclosing types, resolve typealiases and module-qualified types, add missing generics.
    func resolved(in node: SyntaxNode? = nil, declaringType: TypeSignature? = nil, moduleName: String? = nil, context: TypeResolutionContext) -> TypeSignature {
        switch self {
        case .array(let elementType):
            return .array(elementType?.resolved(in: node, declaringType: declaringType, context: context))
        case .composition(let types):
            return .composition(types.map { $0.resolved(in: node, declaringType: declaringType, context: context) })
        case .dictionary(let keyType, let valueType):
            return .dictionary(keyType?.resolved(in: node, declaringType: declaringType, context: context), valueType?.resolved(in: node, declaringType: declaringType, context: context))
        case .existential(let mode, let type):
            return .existential(mode, type.resolved(in: node, declaringType: declaringType, moduleName: moduleName, context: context))
        case .function(let parameters, let returnType, let apiFlags, let attributes):
            let resolvedParameters = parameters.map { Parameter(label: $0.label, type: $0.type.resolved(in: node, declaringType: declaringType, context: context), isInOut: $0.isInOut, isVariadic: $0.isVariadic, isVariadicContinuation: $0.isVariadicContinuation, hasDefaultValue: $0.hasDefaultValue) }
            return .function(resolvedParameters, returnType.resolved(in: node, declaringType: declaringType, context: context), APIFlags(options: apiFlags.options, throwsType: apiFlags.throwsType.resolved(in: node, declaringType: declaringType, context: context)), attributes)
        case .member(let baseType, let type):
            let resolvedBase = baseType.resolved(in: node, declaringType: declaringType, moduleName: moduleName, context: context)
            if case .named(let name, let generics) = type {
                let generics = generics.map { $0.resolved(in: node, declaringType: declaringType, context: context) }
                return context.resolve(.named(name, generics), in: resolvedBase)
            } else {
                return context.resolve(type, in: resolvedBase)
            }
        case .metaType(let type):
            return type.resolved(in: node, declaringType: declaringType, moduleName: moduleName, context: context).asMetaType(true)
        case .module(let moduleName, let type):
            // Type will already be qualified, but may need typealias resolution
            return type.resolved(moduleName: moduleName, context: context)
        case .named(let name, let generics):
            let generics = generics.map { $0.resolved(in: node, declaringType: declaringType, context: context) }
            if let node {
                let (qualified, isGenericParameter) = node.qualifyReferencedNamedType(name: name, generics: generics, context: context)
                // If we get back a typealiased type, the target type might again need qualification
                if case .typealiased = qualified {
                    return qualified.resolved(in: node, moduleName: moduleName, context: context)
                } else if isGenericParameter {
                    return qualified
                } else {
                    return qualified.resolved(moduleName: moduleName, context: context)
                }
            } else if let declaringType {
                let qualified = context.qualifyInherited(type: self, in: declaringType)
                return qualified.resolved(moduleName: moduleName, context: context)
            } else {
                return context.resolve(.named(name, generics), moduleName: moduleName)
            }
        case .optional(let type):
            return type.resolved(in: node, declaringType: declaringType, moduleName: moduleName, context: context).asOptional(true)
        case .range(let elementType):
            return .range(elementType?.resolved(in: node, declaringType: declaringType, context: context))
        case .set(let elementType):
            return .set(elementType?.resolved(in: node, declaringType: declaringType, context: context))
        case .tuple(let labels, let types):
            return .tuple(labels, types.map { $0.resolved(in: node, declaringType: declaringType, context: context) })
        case .typealiased(let alias, let type):
            return type.resolved(in: node, declaringType: declaringType, moduleName: moduleName, context: context).asTypealiased(alias)
        case .unwrappedOptional(let type):
            return type.resolved(in: node, declaringType: declaringType, moduleName: moduleName, context: context).asUnwrappedOptional(true)
        default:
            return self
        }
    }

    /// Replace uses of `Self` as a type with the owning type declaration.
    func resolvingSelf(in node: SyntaxNode?, to type: TypeSignature? = nil) -> TypeSignature {
        guard node != nil || type != nil else {
            return self
        }
        var owningType = type
        return mappingTypes {
            if $0 == .named("Self", []) {
                if owningType == nil, let owningTypeDeclaration = node?.owningTypeDeclaration {
                    if let selfType = owningTypeDeclaration.generics.selfType {
                        owningType = selfType
                    } else if owningTypeDeclaration.signature.generics.isEmpty {
                        owningType = owningTypeDeclaration.signature.withGenerics(owningTypeDeclaration.generics.entries.map { $0.constrainedType(ifEqual: true) })
                    } else {
                        owningType = owningTypeDeclaration.signature
                    }
                }
                return owningType
            }
            return nil
        }
    }

    /// Attempt to replace `.none` cases in this type signature with information from the given signature.
    func or(_ typeSignature: TypeSignature, replaceAny: Bool = false) -> TypeSignature {
        let typeModule = typeSignature.moduleName
        let strippedTypeSignature = typeSignature.asTypealiased(nil).withoutOptionality().withExistentialMode(.none).withModuleName(nil)

        switch self {
        case .any:
            if replaceAny && typeSignature.isFullySpecified {
                return typeSignature
            }
        case .array(let elementType):
            if let elementType, case .array(let elementType2) = strippedTypeSignature, let elementType2 {
                let resolvedElementType = elementType.or(elementType2, replaceAny: replaceAny)
                return .array(resolvedElementType)
            }
        case .dictionary(let keyType, let valueType):
            if case .dictionary(let keyType2, let valueType2) = strippedTypeSignature {
                let resolvedKeyType = keyType2 == nil ? keyType : keyType?.or(keyType2!, replaceAny: replaceAny)
                let resolvedValueType = valueType2 == nil ? valueType : valueType?.or(valueType2!, replaceAny: replaceAny)
                return .dictionary(resolvedKeyType, resolvedValueType)
            }
        case .existential(let mode, let type):
            let resolvedType = type.or(strippedTypeSignature)
            return .existential(mode, resolvedType)
        case .function(let parameters, let returnType, let apiFlags, let attributes):
            if case .function(let parameters2, let returnType2, let apiFlags2, _) = strippedTypeSignature {
                // We may use an empty parameters array to represent .none
                var resolvedParameters: [Parameter] = parameters
                if parameters.isEmpty {
                    resolvedParameters = parameters2
                } else if parameters.count == parameters2.count {
                    resolvedParameters = zip(parameters, parameters2).map { $0.0.or($0.1, replaceAny: replaceAny) }
                } else if parameters2.count == 1, case .tuple(let labels, let types) = parameters2[0].type, parameters.count == labels.count {
                    // Closure whose parameters deconstruct the expected tuple argument, e.g. dict.forEach { key, value in ... }
                    resolvedParameters = zip(parameters, types).map { $0.0.or(Parameter(type: $0.1), replaceAny: replaceAny) }
                }
                return .function(resolvedParameters, returnType.or(returnType2, replaceAny: replaceAny), apiFlags.union(apiFlags2), attributes)
            }
        case .member(let base, let type):
            if case .member(let base2, let type2) = strippedTypeSignature {
                if base.isSameType(as: base2) {
                    return type.or(type2, replaceAny: replaceAny).asMember(of: base)
                }
            }
        case .metaType(let type):
            if case .metaType(let type2) = strippedTypeSignature {
                return type.or(type2, replaceAny: replaceAny).asMetaType(true)
            }
        case .module(let moduleName, let type):
            if moduleName == typeModule || typeModule == nil {
                return type.or(typeSignature, replaceAny: replaceAny).withModuleName(moduleName)
            }
        case .none:
            return typeSignature
        case .optional(let type):
            return type.or(typeSignature).asOptional(true)
        case .range(let elementType):
            if case .range(let elementType2) = strippedTypeSignature {
                let resolvedElementType = elementType2 == nil ? elementType : elementType?.or(elementType2!, replaceAny: replaceAny)
                return .range(resolvedElementType)
            }
        case .set(let elementType):
            if case .set(let elementType2) = strippedTypeSignature {
                let resolvedElementType = elementType2 == nil ? elementType : elementType?.or(elementType2!, replaceAny: replaceAny)
                return .set(resolvedElementType)
            }
        case .tuple(let labels, let types):
            if case .tuple(_, let types2) = strippedTypeSignature, types.count == types2.count {
                let resolvedTypes = zip(types, types2).map { $0.0.or($0.1, replaceAny: replaceAny) }
                return .tuple(labels, resolvedTypes)
            }
        case .typealiased(let alias, let type):
            return type.or(typeSignature).asTypealiased(alias)
        case .unwrappedOptional(let type):
            return type.or(typeSignature).asUnwrappedOptional(true)
        default:
            break
        }
        return self
    }

    /// Whether this is a floating point number.
    var isFloatingPoint: Bool {
        switch self {
        case .double, .float:
            return true
        case .module(_, let type):
            return type.isFloatingPoint
        case .optional(let type):
            return type.isFloatingPoint
        case .typealiased(_, let type):
            return type.isFloatingPoint
        case .unwrappedOptional(let type):
            return type.isFloatingPoint
        default:
            return false
        }
    }

    /// Whether this is a number type.
    var isNumeric: Bool {
        switch self {
        case .double, .float:
            return true
        case .int, .int8, .int16, .int32, .int64, .int128:
            return true
        case .uint, .uint8, .uint16, .uint32, .uint64, .uint128:
            return true
        case .module(_, let type):
            return type.isNumeric
        case .optional(let type):
            return type.isNumeric
        case .typealiased(_, let type):
            return type.isNumeric
        case .unwrappedOptional(let type):
            return type.isNumeric
        default:
            return false
        }
    }

    /// Whether this is an unsigned number type.
    var isUnsigned: Bool {
        switch self {
        case .uint, .uint8, .uint16, .uint32, .uint64, .uint128:
            return true
        case .module(_, let type):
            return type.isUnsigned
        case .optional(let type):
            return type.isUnsigned
        case .typealiased(_, let type):
            return type.isUnsigned
        case .unwrappedOptional(let type):
            return type.isUnsigned
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
        case .module(_, let type):
            return type.isStringy
        case .optional(let type):
            return type.isStringy
        case .typealiased(_, let type):
            return type.isStringy
        case .unwrappedOptional(let type):
            return type.isStringy
        default:
            return false
        }
    }

    /// Whether this is any named type.
    var isNamedType: Bool {
        switch self {
        case .existential(_, let type):
            return type.isNamedType
        case .member:
            return true
        case .module(_, let type):
            return type.isNamedType
        case .named:
            return true
        case .optional(let type):
            return type.isNamedType
        case .typealiased(_, let type):
            return type.isNamedType
        case .unwrappedOptional(let type):
            return type.isNamedType
        default:
            return false
        }
    }

    /// Whether this is a named type with the given name, optionally matching a module and generics.
    func isNamed(_ name: String, moduleName: String? = nil, generics: [TypeSignature]? = nil) -> Bool {
        switch self {
        case .existential(_, let type):
            return type.isNamed(name, moduleName: moduleName, generics: generics)
        case .member(let base, let member):
            guard let dotIdx = name.lastIndex(of: ".") else {
                return false
            }
            let baseName = name.prefix(upTo: dotIdx)
            let memberName = name.suffix(from: name.index(after: dotIdx))
            return member.isNamed(String(memberName), generics: generics) && base.isNamed(String(baseName), moduleName: moduleName)
        case .module(let module2, let type):
            guard type.isNamed(name, generics: generics) else {
                return false
            }
            return moduleName == nil || moduleName == module2
        case .named(let name2, let generics2):
            guard name == name2 else {
                return false
            }
            return generics?.isSameTypes(as: generics2) != false
        case .optional(let type):
            return type.isNamed(name, moduleName: moduleName, generics: generics)
        case .typealiased(let alias, let type):
            return type.isNamed(name, moduleName: moduleName, generics: generics) || alias.from.isNamed(name, moduleName: moduleName, generics: generics)
        case .unwrappedOptional(let type):
            return type.isNamed(name, moduleName: moduleName, generics: generics)
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
    /// Compound types with multiple elements return an average of their elements' scores.
    func compatibilityScore(target: TypeSignature, codebaseInfo: CodebaseInfo.Context, isLiteral: Bool = false, isInterpolated: Bool = false) -> Double? {
        let moduleName = self.moduleName
        let type = asTypealiased(nil).withExistentialMode(.none).withModuleName(nil)
        let targetIsOptional = target.isOptional
        let targetModuleName = target.moduleName
        let maybeSameModule = moduleName == nil || targetModuleName == nil || moduleName == targetModuleName
        let strippedTarget = target.asTypealiased(nil).withoutOptionality().withExistentialMode(.none).withModuleName(nil)
        if type == strippedTarget && maybeSameModule {
            if type == .string {
                // Favor using ExpressibleByStringLiteral or ExpressibleByStringInterpolation for literals
                return isLiteral ? 1.95 : 2.0
            } else {
                return 2.0
            }
        }

        switch type {
        case .array(let element):
            if case .array(let targetElement) = strippedTarget {
                guard let elementScore = (element ?? .none).compatibilityScore(target: targetElement ?? .none, codebaseInfo: codebaseInfo) else {
                    return nil
                }
                return (2.0 + elementScore) / 2.0
            }
            if case .set(let targetElement) = strippedTarget {
                guard let elementScore = (element ?? .none).compatibilityScore(target: targetElement ?? .none, codebaseInfo: codebaseInfo) else {
                    return nil
                }
                return (2.0 + elementScore) / 2.0
            }
            // Array literal being passed as OptionSet
            if codebaseInfo.global.protocolSignatures(forNamed: target).contains(where: { $0.isNamed("OptionSet", moduleName: "Swift") }) {
                guard let elementScore = (element ?? .none).compatibilityScore(target: target, codebaseInfo: codebaseInfo) else {
                    return nil
                }
                return (2.0 + elementScore) / 2.0
            }
            if case .named(_, let generics) = strippedTarget, generics.count == 1, let inheritanceScore = inheritanceCompatibilityScore(target: target, codebaseInfo: codebaseInfo) {
                guard let elementScore = (element ?? .none).compatibilityScore(target: generics[0], codebaseInfo: codebaseInfo) else {
                    return nil
                }
                return (inheritanceScore + elementScore) / 2.0
            }
        case .character:
            if strippedTarget.isStringy {
                return 1.0
            }
        case .dictionary(let keyType, let valueType):
            if case .dictionary(let keyType2, let valueType2) = strippedTarget {
                guard let keyScore = (keyType ?? .none).compatibilityScore(target: keyType2 ?? .none, codebaseInfo: codebaseInfo), let valueScore = (valueType ?? .none).compatibilityScore(target: valueType2 ?? .none, codebaseInfo: codebaseInfo) else {
                    return nil
                }
                return (2.0 + keyScore + 2.0 + valueScore) / 4.0
            }
            // TODO: Match K, V, to superclass collections Entry<K, V> element type
            if let inheritanceScore = inheritanceCompatibilityScore(target: target, codebaseInfo: codebaseInfo) {
                return inheritanceScore / 4.0
            }
        case .double, .float:
            if strippedTarget.isFloatingPoint {
                return 1.5
            }
            if strippedTarget.isNumeric {
                return 1.0
            }
        case .int, .int8, .int16, .int32, .int64, .int128, .uint, .uint8, .uint16, .uint64, .uint128:
            if strippedTarget.isFloatingPoint {
                return 1.0
            }
            if strippedTarget.isNumeric {
                return 1.5
            }
        case .function(let parameters, _, _, _):
            // TODO: Match params and return type
            if case .function(let parameters2, _, _, _) = strippedTarget {
                return parameters.count == parameters2.count ? 1.5 : 1.0
            }
        case .member, .named:
            // TODO: Match on generics
            // Consider a match on all except generics a very close match
            if type.withGenerics([]) == strippedTarget.withGenerics([]) && maybeSameModule {
                return 1.95
            }
            if let score = inheritanceCompatibilityScore(target: target, codebaseInfo: codebaseInfo) {
                return score
            }
        case .metaType(let type):
            if target.isMetaType {
                return type.compatibilityScore(target: target.asMetaType(false), codebaseInfo: codebaseInfo)
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
            if case .range(let targetElement) = strippedTarget {
                guard let elementScore = (element ?? .none).compatibilityScore(target: targetElement ?? .none, codebaseInfo: codebaseInfo) else {
                    return nil
                }
                return (2.0 + elementScore) / 2.0
            }
        case .set(let element):
            if case .set(let targetElement) = strippedTarget {
                guard let elementScore = (element ?? .none).compatibilityScore(target: targetElement ?? .none, codebaseInfo: codebaseInfo) else {
                    return nil
                }
                return (2.0 + elementScore) / 2.0
            }
            if case .named(_, let generics) = strippedTarget, generics.count == 1, let inheritanceScore = inheritanceCompatibilityScore(target: target, codebaseInfo: codebaseInfo) {
                guard let elementScore = (element ?? .none).compatibilityScore(target: generics[0], codebaseInfo: codebaseInfo) else {
                    return nil
                }
                return (inheritanceScore + elementScore) / 2.0
            }
        case .string:
            if strippedTarget.isStringy {
                return 1.0
            }
            if isInterpolated, target.compatibilityScore(target: .named("ExpressibleByStringInterpolation", []), codebaseInfo: codebaseInfo) != nil {
                return 2.0
            } else if isLiteral, target.compatibilityScore(target: .named("ExpressibleByStringLiteral", []), codebaseInfo: codebaseInfo) != nil {
                return 2.0
            }
        case .tuple(_, let types):
            if case .tuple(_, let targetTypes) = strippedTarget {
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

        switch strippedTarget {
        case .any, .anyObject:
            return 1.0
        case .none:
            return 0.0
        default:
            return nil
        }
    }

    private func inheritanceCompatibilityScore(target: TypeSignature, codebaseInfo: CodebaseInfo.Context) -> Double? {
        // TODO: Match on generics
        let target = target.withGenerics([])

        // Perform a breadth-first search to find a matching inherited type
        var queue: [TypeSignature] = [self]
        var level = 1.0
        while !queue.isEmpty {
            let candidate = queue.removeFirst()
            for typeInfo in codebaseInfo.typeInfos(forNamed: candidate) {
                for inherit in typeInfo.inherits {
                    // Take away a tenth of a point for each level down the inheritance chain, so that less derived matches score lower.
                    // This will allow another function with a more specific parameter type to score higher
                    if inherit.withGenerics([]).isSameType(as: target, withoutOptionality: true) {
                        return 2.0 - level * 0.1
                    }
                    queue.append(inherit)
                }
            }
            level += 1.0
        }
        return nil
    }

    /// Whether this type signature does not have any `.none` values.
    var isFullySpecified: Bool {
        var isSpecified = true
        func visitor(_ typeSignature: TypeSignature) -> VisitResult<TypeSignature> {
            if !isSpecified {
                return .skip
            }
            switch typeSignature {
            case .function(let parameters, let returnType, _, _):
                // Don't include the throwsType
                parameters.forEach { $0.type.visit(visitor) }
                returnType.visit(visitor)
                return .skip
            default:
                if typeSignature == .none {
                    isSpecified = false
                    return .skip
                } else {
                    return .recurse(nil)
                }
            }
        }
        visit(visitor)
        return isSpecified
    }

    /// Whether the given syntax is an inout value.
    static func isInOut(syntax: TypeSyntax) -> Bool {
        switch syntax.kind {
        case .attributedType:
            guard let attributedType = syntax.as(AttributedTypeSyntax.self) else {
                return false
            }
            return attributedType.specifiers.contains {
                switch $0 {
                case .simpleTypeSpecifier(let syntax):
                    return syntax.specifier.text == "inout"
                default:
                    return false
                }
            }
        default:
            return false
        }
    }

    /// Create a type signature for the given syntax.
    static func `for`(syntax: TypeSyntax, in syntaxTree: SyntaxTree) -> TypeSignature {
        switch syntax.kind {
        case .arrayType:
            guard let arrayType = syntax.as(ArrayTypeSyntax.self) else {
                return .none
            }
            let elementType = self.for(syntax: arrayType.element, in: syntaxTree)
            return elementType == .none ? .none : .array(elementType)
        case .attributedType:
            guard let attributedType = syntax.as(AttributedTypeSyntax.self) else {
                return .none
            }
            let signature = self.for(syntax: attributedType.baseType, in: syntaxTree)
            let attributes = Attributes.for(syntax: attributedType.attributes, in: syntaxTree)
            return attributes.apply(toFunction: signature)
        case .identifierType:
            guard let simpleType = syntax.as(IdentifierTypeSyntax.self) else {
                return .none
            }
            let name = simpleType.name.text
            var genericTypes: [TypeSignature] = []
            if let generics = simpleType.genericArgumentClause?.arguments {
                genericTypes = generics.map { self.for(syntax: $0.argument, in: syntaxTree) }
                guard !genericTypes.contains(.none) else {
                    return .none
                }
            }
            return self.for(name: name, genericTypes: genericTypes)
        case .compositionType:
            guard let compositionType = syntax.as(CompositionTypeSyntax.self) else {
                return .none
            }
            let types = compositionType.elements.map { self.for(syntax: $0.type, in: syntaxTree) }
            guard !types.contains(.none) else {
                return .none
            }
            return .composition(types)
        case .dictionaryType:
            guard let dictionaryType = syntax.as(DictionaryTypeSyntax.self) else {
                return .none
            }
            let keyType = self.for(syntax: dictionaryType.key, in: syntaxTree)
            let valueType = self.for(syntax: dictionaryType.value, in: syntaxTree)
            guard keyType != .none, valueType != .none else {
                return .none
            }
            return .dictionary(keyType, valueType)
        case .someOrAnyType:
            guard let someOrAnyType = syntax.as(SomeOrAnyTypeSyntax.self) else {
                return .none
            }
            switch someOrAnyType.someOrAnySpecifier.text {
            case "any":
                return .existential(.any, self.for(syntax: someOrAnyType.constraint, in: syntaxTree))
            case "some":
                return .existential(.some, self.for(syntax: someOrAnyType.constraint, in: syntaxTree))
            default:
                return self.for(syntax: someOrAnyType.constraint, in: syntaxTree)
            }
        case .functionType:
            guard let functionType = syntax.as(FunctionTypeSyntax.self) else {
                return .none
            }
            var parameters: [Parameter] = []
            for parameterSyntax in functionType.parameters {
                let label = parameterSyntax.firstName?.text
                let type = self.for(syntax: parameterSyntax.type, in: syntaxTree)
                let isInOut = isInOut(syntax: parameterSyntax.type)
                let isVariadic = parameterSyntax.ellipsis != nil
                parameters.append(Parameter(label: label, type: type, isInOut: isInOut, isVariadic: isVariadic, hasDefaultValue: false))
            }
            let returnType = self.for(syntax: functionType.returnClause.type, in: syntaxTree)
            guard !parameters.contains(where: { $0.type == .none }) && returnType != .none else {
                return .none
            }
            let apiFlags = functionType.effectSpecifiers?.apiFlags(in: syntaxTree) ?? APIFlags()
            return .function(parameters, returnType, apiFlags, nil)
        case .memberType:
            guard let memberType = syntax.as(MemberTypeSyntax.self) else {
                return .none
            }
            let baseType = self.for(syntax: memberType.baseType, in: syntaxTree)
            guard baseType != .none else {
                return .none
            }
            let name = memberType.name.text
            var genericTypes: [TypeSignature] = []
            if let generics = memberType.genericArgumentClause?.arguments {
                genericTypes = generics.map { self.for(syntax: $0.argument, in: syntaxTree) }
                guard !genericTypes.contains(.none) else {
                    return .none
                }
            }
            if baseType == .named("Self", []) {
                return self.for(name: name, genericTypes: genericTypes)
            } else {
                return TypeResolutionContext().resolve(.named(name, genericTypes), in: baseType)
            }
        case .metatypeType:
            guard let metaType = syntax.as(MetatypeTypeSyntax.self) else {
                return .none
            }
            let baseType = self.for(syntax: metaType.baseType, in: syntaxTree)
            guard baseType != .none else {
                return .none
            }
            return .metaType(baseType)
        case .optionalType:
            guard let optionalType = syntax.as(OptionalTypeSyntax.self) else {
                return .none
            }
            let wrappedType = self.for(syntax: optionalType.wrappedType, in: syntaxTree)
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
                let type = self.for(syntax: syntax.type, in: syntaxTree)
                return (syntax.firstName?.text, type)
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
            let wrappedType = self.for(syntax: unwrappedOptionalType.wrappedType, in: syntaxTree)
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
        case .packElementType:
            fallthrough
        default:
            return .none
        }
    }

    static func `for`(name: String, genericTypes: [TypeSignature], allowNamed: Bool = true) -> TypeSignature {
        func swiftNamed(_ name: String, _ genericTypes: [TypeSignature]) -> TypeSignature {
            if name.hasPrefix("Swift.") {
                return .module("Swift", .named(String(name.dropFirst("Swift.".count)), genericTypes))
            } else {
                return .named(name, genericTypes)
            }
        }
        let (name, genericTypes) = genericTypes.isEmpty ? parseGenericTypes(from: name) : (name, genericTypes)
        switch name {
        case "Any", "Swift.Any":
            return genericTypes.isEmpty ? .any : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "AnyObject", "Swift.AnyObject":
            return genericTypes.isEmpty ? .anyObject : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "Any.Type", "Swift.Any.Type":
            return .metaType(.any)
        case "Array", "Swift.Array":
            return genericTypes.isEmpty ? .array(nil) : genericTypes.count == 1 ? .array(genericTypes[0]) : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "Bool", "Swift.Bool":
            return genericTypes.isEmpty ? .bool : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "Character", "Swift.Character":
            return genericTypes.isEmpty ? .character : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "Dictionary", "Swift.Dictionary":
            return genericTypes.isEmpty ? .dictionary(nil, nil) : genericTypes.count == 2 ? .dictionary(genericTypes[0], genericTypes[1]) : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "Double", "Swift.Double":
            return genericTypes.isEmpty ? .double : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "Float", "Swift.Float":
            return genericTypes.isEmpty ? .float : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "Int", "Swift.Int":
            return genericTypes.isEmpty ? .int : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "Int8", "Swift.Int8":
            return genericTypes.isEmpty ? .int8 : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "Int16", "Swift.Int16":
            return genericTypes.isEmpty ? .int16 : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "Int32", "Swift.Int32":
            return genericTypes.isEmpty ? .int32 : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "Int64", "Swift.Int64":
            return genericTypes.isEmpty ? .int64 : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "Int128", "Swift.Int128":
            return genericTypes.isEmpty ? .int128 : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "Range", "Swift.Range":
            return genericTypes.isEmpty ? .range(nil) : genericTypes.count == 1 ? .range(genericTypes[0]) : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "Set", "Swift.Set":
            return genericTypes.isEmpty ? .set(nil) : genericTypes.count == 1 ? .set(genericTypes[0]) : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "String", "Swift.String":
            return genericTypes.isEmpty ? .string : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "UInt", "Swift.UInt":
            return genericTypes.isEmpty ? .uint : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "UInt8", "Swift.UInt8":
            return genericTypes.isEmpty ? .uint8 : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "UInt16", "Swift.UInt16":
            return genericTypes.isEmpty ? .uint16 : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "UInt32", "Swift.UInt32":
            return genericTypes.isEmpty ? .uint32 : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "UInt64", "Swift.UInt64":
            return genericTypes.isEmpty ? .uint64 : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "UInt128", "Swift.UInt128":
            return genericTypes.isEmpty ? .uint128 : allowNamed ? swiftNamed(name, genericTypes) : .none
        case "Void", "Swift.Void":
            return genericTypes.isEmpty ? .void : allowNamed ? swiftNamed(name, genericTypes) : .none
        default:
            if !allowNamed {
                return .none
            }
            if let lastSeparator = name.lastIndex(of: "."), lastSeparator != name.index(before: name.endIndex) {
                let firstPart = String(name[..<lastSeparator])
                let lastName = String(name[name.index(after: lastSeparator)...])
                if lastName == "Type" || lastName == "self" {
                    return self.for(name: firstPart, genericTypes: genericTypes).asMetaType(true)
                }
                let base = self.for(name: firstPart, genericTypes: [])
                let named: TypeSignature = .named(lastName, genericTypes)
                return named.asMember(of: base)
            } else {
                return .named(name, genericTypes)
            }
        }
    }

    private static func parseGenericTypes(from name: String) -> (String, [TypeSignature]) {
        guard name.hasSuffix(">") else {
            return (name, [])
        }
        var typeNames: [String] = []
        var currentName = ""
        var depth = 0
        var strippedName = ""
        for c in name {
            switch c {
            case "<":
                depth += 1
                if depth > 1 {
                    currentName.append(c)
                }
            case ">":
                depth -= 1
                if depth == 0 {
                    typeNames.append(currentName)
                    currentName = ""
                } else {
                    currentName.append(c)
                }
            case ",":
                if depth == 1 {
                    typeNames.append(currentName)
                    currentName = ""
                } else if depth > 1 {
                    currentName.append(c)
                }
            default:
                if depth == 0 {
                    strippedName.append(c)
                } else if !c.isWhitespace && depth >= 1 {
                    currentName.append(c)
                }
            }
        }
        return (strippedName, typeNames.map { TypeSignature.for(name: $0, genericTypes: []) })
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
            if let elementType {
                return "[\(elementType[keyPath: keyPath])]"
            } else {
                return "Array"
            }
        case .bool:
            return "Bool"
        case .character:
            return "Character"
        case .composition(let types):
            return "(\(types.map { $0[keyPath: keyPath] }.joined(separator: " & ")))"
        case .dictionary(let keyType, let valueType):
            if let keyType, let valueType {
                return "[\(keyType[keyPath: keyPath]): \(valueType[keyPath: keyPath])]"
            } else {
                return "Dictionary"
            }
        case .double:
            return "Double"
        case .existential(let mode, let type):
            switch mode {
            case .none:
                return type.descriptionUsing(keyPath)
            case .any:
                return "(any \(type.descriptionUsing(keyPath)))"
            case .some:
                return "(some \(type.descriptionUsing(keyPath)))"
            }
        case .float:
            return "Float"
        case .function(let parameters, let returnType, let apiFlags, let attributes):
            var apiFlagsString = ""
            if apiFlags.options.contains(.async) {
                apiFlagsString += " async"
            }
            if apiFlags.throwsType != .none {
                apiFlagsString += " throws"
                if apiFlags.throwsType != .any {
                    apiFlagsString += "(\(apiFlags.throwsType.descriptionUsing(keyPath)))"
                }
            }
            let attributesString = attributes?.contains(.escaping) == true ? "@escaping " : ""
            return "\(attributesString)(\(parameters.map { $0.descriptionUsing(keyPath) }.joined(separator: ", ")))\(apiFlagsString) -> \(returnType[keyPath: keyPath])"
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
        case .int128:
            return "Int128"
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
        case .module(let moduleName, let type):
            return "\(moduleName).\(type[keyPath: keyPath])"
        case .named(let name, let generics):
            guard !generics.isEmpty else {
                return name
            }
            return "\(name)<\(generics.map { $0[keyPath: keyPath] }.joined(separator: ", "))>"
        case .none:
            return "?"
        case .optional(let type):
            switch type {
            case .function:
                return "(\(type[keyPath: keyPath]))?"
            default:
                return "\(type[keyPath: keyPath])?"
            }
        case .range(let type):
            if let type {
                return "Range<\(type[keyPath: keyPath])>"
            } else {
                return "Range"
            }
        case .set(let type):
            if let type {
                return "Set<\(type[keyPath: keyPath])>"
            } else {
                return "Set"
            }
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
        case .typealiased(_, let type):
            return type[keyPath: keyPath]
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
        case .uint128:
            return "UInt128"
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

    /// Existential type handling.
    enum ExistentialMode: Hashable, Codable {
        case none
        case any
        case some
    }

    /// Typealias information.
    struct Typealias: Hashable, Codable {
        var from: TypeSignature
        var to: TypeSignature
    }

    /// A parameter in a function signature.
    struct Parameter: CustomStringConvertible, Hashable, Codable {
        var label: String?
        var type: TypeSignature
        var isInOut = false
        var isVariadic = false
        var isVariadicContinuation = false
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

        func mappingTypes(with map: (TypeSignature) -> TypeSignature?) -> Parameter {
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
            return lhs.label == rhs.label && lhs.type == rhs.type && lhs.isInOut == rhs.isInOut && lhs.isVariadic == rhs.isVariadic && lhs.isVariadicContinuation == rhs.isVariadicContinuation
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(label)
            hasher.combine(type)
            hasher.combine(isInOut)
            hasher.combine(isVariadic)
        }
    }
}

extension TypeSignature {
    var isSelf: Bool {
        return isNamed("Self", generics: [])
    }

    var isComparable: Bool {
        return isNamed("Comparable", moduleName: "Swift", generics: [])
    }

    var isCustomStringConvertible: Bool {
        return isNamed("CustomStringConvertible", moduleName: "Swift", generics: [])
    }

    var isEquatable: Bool {
        return isNamed("Equatable", moduleName: "Swift", generics: [])
    }

    var isHashable: Bool {
        return isNamed("Hashable", moduleName: "Swift", generics: [])
    }

    var isSendable: Bool {
        return isNamed("Sendable", moduleName: "Swift", generics: [])
    }

    var isKeyPath: Bool {
        return isNamed("KeyPath", moduleName: "Swift")
    }

    var isOptionSet: Bool {
        return isNamed("OptionSet", moduleName: "Swift")
    }

    var isRawRepresentable: Bool {
        return isNamed("RawRepresentable", moduleName: "Swift")
    }

    var isCodable: Bool {
        return isNamed("Codable", moduleName: "Swift", generics: [])
    }

    var isDecodable: Bool {
        return isNamed("Decodable", moduleName: "Swift", generics: [])
    }

    var isEncodable: Bool {
        return isNamed("Encodable", moduleName: "Swift", generics: [])
    }

    /// Return this type as a binding.
    func asBinding() -> TypeSignature {
        return .named("Binding", [self])
    }

    /// Return this type as a publisher.
    func asPublisher() -> TypeSignature {
        return .named("Publisher", [self, .none])
    }

    /// Return this as a self-generic-typed property wrapper of the given type.
    func asPropertyWrapper(_ typeName: String) -> TypeSignature {
        return .named(typeName, [self])
    }
}

extension Array where Element == TypeSignature {
    func isSameTypes(as other: [TypeSignature]) -> Bool {
        return other.count == count && zip(self, other).contains { !$0.0.isSameType(as: $0.1) } == false
    }
}
