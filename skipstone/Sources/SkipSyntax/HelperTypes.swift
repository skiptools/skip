import SwiftSyntax

/// A variable accessor.
struct Accessor<B> {
    var parameterName: String?
    var body: B? // Nil if the accessor has no body, as in a protocol { get set }
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
        Operator(symbol: "!==", associativity: .none, precedence: .comparison),
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
struct Parameter<V>: Hashable {
    var externalLabel: String?
    var internalLabel: String {
        return _internalLabel ?? externalLabel ?? "_"
    }
    private let _internalLabel: String?
    var declaredType: TypeSignature
    var isVariadic: Bool
    var isInOut: Bool
    var defaultValue: V?

    init(externalLabel: String?, internalLabel: String? = nil, declaredType: TypeSignature = .none, isVariadic: Bool = false, isInOut: Bool = false, defaultValue: V? = nil) {
        self.externalLabel = externalLabel == "" || externalLabel == "_" ? nil : externalLabel
        _internalLabel = internalLabel
        self.declaredType = declaredType
        self.isVariadic = isVariadic
        self.isInOut = isInOut
        self.defaultValue = defaultValue
    }

    var prettyPrintTree: PrettyPrintTree {
        var children: [PrettyPrintTree] = []
        if let internalLabel = _internalLabel {
            children.append(PrettyPrintTree(root: internalLabel))
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
        return PrettyPrintTree(root: externalLabel ?? "_", children: children)
    }

    func qualifiedType(in node: SyntaxNode) -> Parameter<V> {
        var parameter = self
        parameter.declaredType = declaredType.qualified(in: node)
        return parameter
    }

    static func ==(lhs: Parameter<V>, rhs: Parameter<V>) -> Bool {
        return lhs.externalLabel == rhs.externalLabel && lhs.declaredType == rhs.declaredType && lhs.isVariadic == rhs.isVariadic && lhs.isInOut == rhs.isInOut
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(externalLabel)
        hasher.combine(declaredType)
        hasher.combine(isVariadic)
        hasher.combine(isInOut)
    }
}

/// An identifier found in pattern syntax.
struct IdentifierPattern {
    var name: String?
    var isVar = false
}

/// A segment in a string literal.
enum StringLiteralSegment<E> {
    case string(String)
    case expression(E)
}

/// Member and type modifiers.
struct Modifiers: PrettyPrintable {
    /// Visibility modifier.
    enum Visibility: Equatable, Comparable {
        case `private`
        case `default`
        case `internal`
        case `public`
        case `open`
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

/// @Attributes on a declaration.
struct Attributes: PrettyPrintable {
    let attributes: [Attribute]

    init(attributes: [Attribute] = []) {
        self.attributes = attributes
    }

    /// Decode the attribute information in the given syntax.
    static func `for`(syntax: AttributeListSyntax?) -> Attributes {
        guard let syntax else {
            return Attributes()
        }
        let attributes = syntax.compactMap {
            switch $0 {
            case .attribute(let syntax):
                return Attribute.for(syntax: syntax)
            case .ifConfigDecl:
                return nil
            }
        }
        return Attributes(attributes: attributes)
    }

    var isEmpty: Bool {
        return attributes.isEmpty
    }

    var prettyPrintTree: PrettyPrintTree {
        let children = attributes.map {
            return PrettyPrintTree(root: "@\($0.signature)")
        }
        return PrettyPrintTree(root: "attributes", children: children)
    }
}

/// @Attribute on a declaration.
struct Attribute {
    let signature: TypeSignature

    /// Decode the attribute information in the given syntax.
    static func `for`(syntax: AttributeSyntax) -> Attribute? {
        let signature = TypeSignature.for(syntax: syntax.attributeName)
        return signature == .none ? nil : Attribute(signature: signature)
    }
}

extension String {
    /// If this is an implicit closure parameter - `$0`, `$1`, etc - return its index.
    var implicitClosureParameterIndex: Int? {
        if hasPrefix("$"), count > 1, let index = Int(String(self[index(after: startIndex)...])) {
            return index
        }
        return nil
    }
}
