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
struct Parameter<E>: Hashable {
    var externalName: String
    var internalName: String {
        return _internalName ?? externalName
    }
    private let _internalName: String?
    var declaredType: TypeSignature
    var isVariadic: Bool
    var defaultValue: E?

    init(externalName: String, internalName: String? = nil, declaredType: TypeSignature = .none, isVariadic: Bool = false, defaultValue: E? = nil) {
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

    func qualifiedType(in node: SyntaxNode) -> Parameter<E> {
        var parameter = self
        parameter.declaredType = declaredType.qualified(in: node)
        return parameter
    }

    static func ==(lhs: Parameter<E>, rhs: Parameter<E>) -> Bool {
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
