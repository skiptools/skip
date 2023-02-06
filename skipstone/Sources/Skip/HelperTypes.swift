import SwiftSyntax

/// A block of code.
struct CodeBlock<S> {
    let statements: [S]
}

/// A variable accessor.
struct Accessor<S> {
    var parameterName: String?
    var statements: [S]? // Nil if the accessor has no body, as in a protocol { get set }
}

/// A labeled expression, as used in function call parameters.
struct LabeledExpression<E> {
    var label: String?
    var expression: E
}

/// Operator information.
struct Operator: Equatable {
    let symbol: String
    let associativity: Associativity
    let precedence: Int

    /// Left associativity means `(a + b + c) == ((a + b) + c)`.
    enum Associativity: Equatable {
        case none
        case left
        case right
    }

    /// Whether this operator symbol is unrecognized.
    var isUnknown: Bool {
        return precedence == Self.unknownOperatorPrecedence
    }

    /// Return an operator for the given symbol.
    static func with(symbol: String) -> Operator {
        if let op = allBySymbol[symbol] {
            return op
        }
        return Operator(symbol: symbol, associativity: unknownOperatorAssociativity, precedence: unknownOperatorPrecedence)
    }

    /// This information was obtained from https://developer.apple.com/documentation/swift/swift_standard_library/operator_declarations
    private static let unknownOperatorPrecedence = 2
    private static let unknownOperatorAssociativity: Associativity = .left
    private static let all: [Operator] = [
        Operator(symbol: "=", associativity: .right, precedence: 0),
        Operator(symbol: "*=", associativity: .right, precedence: 0),
        Operator(symbol: "/=", associativity: .right, precedence: 0),
        Operator(symbol: "%=", associativity: .right, precedence: 0),
        Operator(symbol: "+=", associativity: .right, precedence: 0),
        Operator(symbol: "-=", associativity: .right, precedence: 0),
        Operator(symbol: "<<=", associativity: .right, precedence: 0),
        Operator(symbol: ">>=", associativity: .right, precedence: 0),
        Operator(symbol: "&=", associativity: .right, precedence: 0),
        Operator(symbol: "|=", associativity: .right, precedence: 0),
        Operator(symbol: "^=", associativity: .right, precedence: 0),

        Operator(symbol: "?:", associativity: .right, precedence: 1),

        // Leave a gap here for unknownOperatorPrecedence

        Operator(symbol: "||", associativity: .left, precedence: 3),

        Operator(symbol: "&&", associativity: .left, precedence: 4),

        Operator(symbol: "<", associativity: .none, precedence: 5),
        Operator(symbol: "<=", associativity: .none, precedence: 5),
        Operator(symbol: ">", associativity: .none, precedence: 5),
        Operator(symbol: ">=", associativity: .none, precedence: 5),
        Operator(symbol: "==", associativity: .none, precedence: 5),
        Operator(symbol: "!=", associativity: .none, precedence: 5),
        Operator(symbol: "===", associativity: .none, precedence: 5),
        Operator(symbol: "~=", associativity: .none, precedence: 5),
        Operator(symbol: ".==", associativity: .none, precedence: 5),
        Operator(symbol: ".!=", associativity: .none, precedence: 5),
        Operator(symbol: ".<", associativity: .none, precedence: 5),
        Operator(symbol: ".<=", associativity: .none, precedence: 5),
        Operator(symbol: ".>", associativity: .none, precedence: 5),
        Operator(symbol: ".>=", associativity: .none, precedence: 5),

        Operator(symbol: "??", associativity: .right, precedence: 6),

        Operator(symbol: "is", associativity: .left, precedence: 7),
        Operator(symbol: "as", associativity: .left, precedence: 7),
        Operator(symbol: "as?", associativity: .left, precedence: 7),
        Operator(symbol: "as!", associativity: .left, precedence: 7),

        Operator(symbol: "..<", associativity: .none, precedence: 8),
        Operator(symbol: "...", associativity: .none, precedence: 8),

        Operator(symbol: "+", associativity: .left, precedence: 9),
        Operator(symbol: "-", associativity: .left, precedence: 9),
        Operator(symbol: "&+", associativity: .left, precedence: 9),
        Operator(symbol: "&-", associativity: .left, precedence: 9),
        Operator(symbol: "|", associativity: .left, precedence: 9),
        Operator(symbol: "^", associativity: .left, precedence: 9),

        Operator(symbol: "*", associativity: .left, precedence: 10),
        Operator(symbol: "/", associativity: .left, precedence: 10),
        Operator(symbol: "%", associativity: .left, precedence: 10),
        Operator(symbol: "&*", associativity: .left, precedence: 10),
        Operator(symbol: "&", associativity: .left, precedence: 10),

        Operator(symbol: "<<", associativity: .none, precedence: 11),
        Operator(symbol: ">>", associativity: .none, precedence: 11),
    ]

    private static let allBySymbol: [String: Operator] = {
        return all.reduce(into: [String: Operator]()) { result, op in
            result[op.symbol] = op
        }
    }()
}

/// A function parameter.
struct Parameter<S>: Hashable {
    let externalName: String
    var internalName: String {
        return _internalName ?? externalName
    }
    private let _internalName: String?
    private(set) var type: TypeSignature?
    let isVariadic: Bool
    let defaultValue: S?

    init(externalName: String, internalName: String? = nil, type: TypeSignature?, isVariadic: Bool = false, defaultValue: S? = nil) {
        self.externalName = externalName
        _internalName = internalName
        self.type = type
        self.isVariadic = isVariadic
        self.defaultValue = defaultValue
    }

    var prettyPrintTree: PrettyPrintTree {
        var children: [PrettyPrintTree] = []
        if let internalName = _internalName {
            children.append(PrettyPrintTree(root: internalName))
        }
        if let type {
            var typeDescription = type.description
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

    func qualifiedType(in statement: Statement) -> Parameter<S> {
        var parameter = self
        parameter.type = type?.qualified(in: statement)
        return parameter
    }

    static func ==(lhs: Parameter<S>, rhs: Parameter<S>) -> Bool {
        return lhs.externalName == rhs.externalName && lhs.type == rhs.type && lhs.isVariadic == rhs.isVariadic
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(externalName)
        hasher.combine(type)
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
    case array(TypeSignature)
    case base(String, String?, [TypeSignature]) // A<B, C> (Second string is qualified name if resolved)
    case classRestricted // 'class'
    case composition([TypeSignature]) // (A & B & C)
    case dictionary(TypeSignature, TypeSignature)
    case function([TypeSignature], TypeSignature)
    case member(TypeSignature, TypeSignature) // A.B
    case metaType(TypeSignature) // A.Type
    case optional(TypeSignature)
    case tuple([String?], [TypeSignature])
    case unwrappedOptional(TypeSignature)

    var description: String {
        return description(isQualified: false)
    }

    var qualifiedDescription: String {
        return description(isQualified: true)
    }

    private func description(isQualified: Bool) -> String {
        switch self {
        case .array(let elementType):
            return "[\(elementType.description(isQualified: isQualified))]"
        case .base(let name, let qualifiedName, let generics):
            let name = (isQualified ? qualifiedName : name) ?? name
            guard !generics.isEmpty else {
                return name
            }
            return "\(name)<\(generics.map { $0.description(isQualified: isQualified) }.joined(separator: ", "))>"
        case .classRestricted:
            return "class"
        case .composition(let types):
            return "(\(types.map { $0.description(isQualified: isQualified) }.joined(separator: " & ")))"
        case .dictionary(let keyType, let valueType):
            return "[\(keyType.description(isQualified: isQualified)): \(valueType.description(isQualified: isQualified))]"
        case .function(let paramTypes, let returnType):
            return "(\(paramTypes.map { $0.description(isQualified: isQualified) }.joined(separator: ", ")) -> \(returnType.description(isQualified: isQualified))"
        case .optional(let type):
            return "\(type.description(isQualified: isQualified))?"
        case .member(let baseType, let type):
            return "\(baseType.description(isQualified: isQualified)).\(type)"
        case .metaType(let baseType):
            return "\(baseType.description(isQualified: isQualified)).Type"
        case .tuple(let labels, let types):
            let descriptions = zip(labels, types).map {
                let typeDescription = $0.1.description(isQualified: isQualified)
                guard let label = $0.0 else {
                    return typeDescription
                }
                return "\(label): \(typeDescription)"
            }
            return "(\(descriptions.joined(separator: ", ")))"
        case .unwrappedOptional(let type):
            return "\(type.description(isQualified: isQualified))!"
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
            return .base(name, nil, genericTypes)
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
            return .member(baseType, .base(name, nil, genericTypes))
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
            let elementsSyntax = tupleType.elements
            let elements = elementsSyntax.compactMap { (syntax: TupleTypeElementSyntax) -> (String?, TypeSignature)? in
                guard let type = self.for(syntax: syntax.type) else {
                    return nil
                }
                return (syntax.name?.text, type)
            }
            guard elements.count == tupleType.elements.count else {
                return nil
            }
            return .tuple(elements.map(\.0), elements.map(\.1))
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

    func qualified(in statement: Statement) -> TypeSignature {
        switch self {
        case .array(let elementType):
            return .array(elementType.qualified(in: statement))
        case .base(let name, let qualifiedName, let generics):
            if qualifiedName != nil {
                return self
            }
            return .base(name, statement.qualifyReferencedTypeName(name), generics.map { $0.qualified(in: statement) })
        case .classRestricted:
            return self
        case .composition(let types):
            return .composition(types.map { $0.qualified(in: statement) })
        case .dictionary(let keyType, let valueType):
            return .dictionary(keyType.qualified(in: statement), valueType.qualified(in: statement))
        case .function(let parameterTypes, let returnType):
            return .function(parameterTypes.map { $0.qualified(in: statement) }, returnType.qualified(in: statement))
        case .member(let baseType, let type):
            return .member(baseType.qualified(in: statement), type)
        case .metaType(let type):
            return .metaType(type.qualified(in: statement))
        case .optional(let type):
            return .optional(type.qualified(in: statement))
        case .tuple(let labels, let types):
            return .tuple(labels, types.map { $0.qualified(in: statement) })
        case .unwrappedOptional(let type):
            return .unwrappedOptional(type.qualified(in: statement))
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
