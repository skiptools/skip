import SwiftSyntax

/// A block of code.
struct CodeBlock<S> {
    var statements: [S]
}

/// A variable accessor.
struct Accessor<S> {
    var parameterName: String?
    var body: CodeBlock<S>? // Nil if the accessor has no body, as in a protocol { get set }
}

/// A labeled value, as used in function call parameters.
struct LabeledValue<V> {
    var label: String?
    var value: V
}

/// Operator information.
struct Operator: Equatable {
    let symbol: String
    let associativity: Associativity
    let precedence: Precedence

    /// Left associativity means `(a + b + c) == ((a + b) + c)`.
    enum Associativity: Equatable {
        case none
        case left
        case right
    }

    /// Return an operator for the given symbol.
    static func with(symbol: String) -> Operator {
        if let op = allBySymbol[symbol] {
            return op
        }
        return Operator(symbol: symbol, associativity: .left, precedence: .unknown)
    }

    enum Precedence: Int {
        case assignment = 0
        case ternary
        case unknown
        case or
        case and
        case comparison
        case nilCoalescing
        case cast
        case range
        case addition
        case multiplication
        case shift
    }

    /// This information was obtained from https://developer.apple.com/documentation/swift/swift_standard_library/operator_declarations
    private static let all: [Operator] = [
        Operator(symbol: "=", associativity: .right, precedence: .assignment),
        Operator(symbol: "*=", associativity: .right, precedence: .assignment),
        Operator(symbol: "/=", associativity: .right, precedence: .assignment),
        Operator(symbol: "%=", associativity: .right, precedence: .assignment),
        Operator(symbol: "+=", associativity: .right, precedence: .assignment),
        Operator(symbol: "-=", associativity: .right, precedence: .assignment),
        Operator(symbol: "<<=", associativity: .right, precedence: .assignment),
        Operator(symbol: ">>=", associativity: .right, precedence: .assignment),
        Operator(symbol: "&=", associativity: .right, precedence: .assignment),
        Operator(symbol: "|=", associativity: .right, precedence: .assignment),
        Operator(symbol: "^=", associativity: .right, precedence: .assignment),

        Operator(symbol: "?:", associativity: .right, precedence: .ternary),

        Operator(symbol: "||", associativity: .left, precedence: .or),

        Operator(symbol: "&&", associativity: .left, precedence: .and),

        Operator(symbol: "<", associativity: .none, precedence: .comparison),
        Operator(symbol: "<=", associativity: .none, precedence: .comparison),
        Operator(symbol: ">", associativity: .none, precedence: .comparison),
        Operator(symbol: ">=", associativity: .none, precedence: .comparison),
        Operator(symbol: "==", associativity: .none, precedence: .comparison),
        Operator(symbol: "!=", associativity: .none, precedence: .comparison),
        Operator(symbol: "===", associativity: .none, precedence: .comparison),
        Operator(symbol: "~=", associativity: .none, precedence: .comparison),
        Operator(symbol: ".==", associativity: .none, precedence: .comparison),
        Operator(symbol: ".!=", associativity: .none, precedence: .comparison),
        Operator(symbol: ".<", associativity: .none, precedence: .comparison),
        Operator(symbol: ".<=", associativity: .none, precedence: .comparison),
        Operator(symbol: ".>", associativity: .none, precedence: .comparison),
        Operator(symbol: ".>=", associativity: .none, precedence: .comparison),

        Operator(symbol: "??", associativity: .right, precedence: .nilCoalescing),

        Operator(symbol: "is", associativity: .left, precedence: .cast),
        Operator(symbol: "as", associativity: .left, precedence: .cast),
        Operator(symbol: "as?", associativity: .left, precedence: .cast),
        Operator(symbol: "as!", associativity: .left, precedence: .cast),

        Operator(symbol: "..<", associativity: .none, precedence: .range),
        Operator(symbol: "...", associativity: .none, precedence: .range),

        Operator(symbol: "+", associativity: .left, precedence: .addition),
        Operator(symbol: "-", associativity: .left, precedence: .addition),
        Operator(symbol: "&+", associativity: .left, precedence: .addition),
        Operator(symbol: "&-", associativity: .left, precedence: .addition),
        Operator(symbol: "|", associativity: .left, precedence: .addition),
        Operator(symbol: "^", associativity: .left, precedence: .addition),

        Operator(symbol: "*", associativity: .left, precedence: .multiplication),
        Operator(symbol: "/", associativity: .left, precedence: .multiplication),
        Operator(symbol: "%", associativity: .left, precedence: .multiplication),
        Operator(symbol: "&*", associativity: .left, precedence: .multiplication),
        Operator(symbol: "&", associativity: .left, precedence: .multiplication),

        Operator(symbol: "<<", associativity: .none, precedence: .shift),
        Operator(symbol: ">>", associativity: .none, precedence: .shift),
    ]

    private static let allBySymbol: [String: Operator] = {
        return all.reduce(into: [String: Operator]()) { result, op in
            result[op.symbol] = op
        }
    }()
}

/// A function parameter.
struct Parameter<S>: Hashable {
    var externalName: String
    var internalName: String {
        return _internalName ?? externalName
    }
    private let _internalName: String?
    var declaredType: TypeSignature
    var isVariadic: Bool
    var defaultValue: S?

    init(externalName: String, internalName: String? = nil, declaredType: TypeSignature = .none, isVariadic: Bool = false, defaultValue: S? = nil) {
        self.externalName = externalName
        _internalName = internalName
        self.declaredType = declaredType
        self.isVariadic = isVariadic
        self.defaultValue = defaultValue
    }

    var prettyPrintTree: PrettyPrintTree {
        var children: [PrettyPrintTree] = []
        if let internalName = _internalName {
            children.append(PrettyPrintTree(root: internalName))
        }
        if declaredType != .none {
            var typeDescription = declaredType.description
            if isVariadic {
                typeDescription += "..."
            }
            children.append(PrettyPrintTree(root: typeDescription))
        }
        if let defaultValue = defaultValue as? PrettyPrintable {
            children.append(defaultValue.prettyPrintTree)
        }
        return PrettyPrintTree(root: externalName.isEmpty ? "_" : externalName, children: children)
    }

    func qualifiedType(in node: SyntaxNode) -> Parameter<S> {
        var parameter = self
        parameter.declaredType = declaredType.qualified(in: node)
        return parameter
    }

    static func ==(lhs: Parameter<S>, rhs: Parameter<S>) -> Bool {
        return lhs.externalName == rhs.externalName && lhs.declaredType == rhs.declaredType && lhs.isVariadic == rhs.isVariadic
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(externalName)
        hasher.combine(declaredType)
        hasher.combine(isVariadic)
    }
}

/// A segment in a string literal.
enum StringLiteralSegment<E> {
    case string(String)
    case expression(E)
}

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
    case function([TypeSignature], TypeSignature)
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
    var parameterTypes: [TypeSignature] {
        switch self {
        case .function(let parameterTypes, _):
            return parameterTypes
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

    /// Return the given type signature if `self == .none`, otherwise return `self`.
    func or(_ typeSignature: TypeSignature) -> TypeSignature {
        return self == .none ? typeSignature : self
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
            let argumentTypes = functionType.arguments.map { self.for(syntax: $0.type) }
            let returnType = self.for(syntax: functionType.returnType)
            guard !argumentTypes.contains(.none) && returnType != .none else {
                return .none
            }
            return .function(argumentTypes, returnType)
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

    private static func `for`(name: String, genericTypes: [TypeSignature]) -> TypeSignature {
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
        case .function(let parameterTypes, let returnType):
            return .function(parameterTypes.map { $0.qualified(in: node) }, returnType.qualified(in: node))
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
}

/// Member and type modifiers.
struct Modifiers: PrettyPrintable {
    /// Visibility modifier.
    enum Visibility {
        case `default`
        case `open`
        case `public`
        case `internal`
        case `private`
    }

    var visibility: Visibility
    let isStatic: Bool
    let isMutating: Bool
    let isFinal: Bool
    var isOverride: Bool

    init(visibility: Visibility = .default, isStatic: Bool = false, isMutating: Bool = false, isFinal: Bool = false, isOverride: Bool = false) {
        self.visibility = visibility
        self.isStatic = isStatic
        self.isMutating = isMutating
        self.isFinal = isFinal
        self.isOverride = isOverride
    }

    /// Decode the modifier information in the given syntax.
    static func `for`(syntax: ModifierListSyntax?) -> Modifiers {
        guard let syntax else {
            return Modifiers()
        }
        var visibility: Visibility = .default
        var isStatic = false
        var isMutating = false
        var isFinal = false
        var isOverride = false
        for modifier in syntax {
            guard modifier.detail == nil else {
                // Ignore e.g. 'private(set)' for now
                continue
            }
            switch modifier.name.text {
            case "open":
                visibility = .open
            case "public":
                visibility = .public
            case "internal":
                visibility = .internal
            case "private":
                visibility = .private
            case "static":
                isStatic = true
            case "class":
                isStatic = true
            case "mutating":
                isMutating = true
            case "final":
                isFinal = true
            case "override":
                isOverride = true
            default:
                break
            }
        }
        return Modifiers(visibility: visibility, isStatic: isStatic, isMutating: isMutating, isFinal: isFinal, isOverride: isOverride)
    }

    var isEmpty: Bool {
        return visibility == .default && !isStatic && !isFinal && !isOverride
    }

    var prettyPrintTree: PrettyPrintTree {
        var children: [PrettyPrintTree] = []
        if visibility != .default {
            children.append(PrettyPrintTree(root: String(describing: visibility)))
        }
        if isStatic {
            children.append(PrettyPrintTree(root: "static"))
        }
        if isMutating {
            children.append(PrettyPrintTree(root: "mutating"))
        }
        if isFinal {
            children.append(PrettyPrintTree(root: "final"))
        }
        if isOverride {
            children.append(PrettyPrintTree(root: "override"))
        }
        return PrettyPrintTree(root: "modifiers", children: children)
    }
}
