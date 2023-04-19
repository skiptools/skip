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

    var isUnknown: Bool {
        return precedence == .unknown
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
    internal var _internalLabel: String?
    var declaredType: TypeSignature
    var isVariadic: Bool
    var isInOut: Bool
    var defaultValue: V?
    var signature: TypeSignature.Parameter {
        return TypeSignature.Parameter(label: externalLabel, type: declaredType, isVariadic: isVariadic, hasDefaultValue: defaultValue != nil)
    }

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
///
/// - Note: `Codable` for use in `CodebaseInfo`.
struct Modifiers: PrettyPrintable, Codable {
    /// Visibility modifier.
    ///
    /// - Note: `Codable` for use in `CodebaseInfo`.
    enum Visibility: Equatable, Comparable, Codable {
        case `private`
        case `default`
        case `internal`
        case `public`
        case `open`
    }

    var visibility: Visibility
    var isStatic: Bool
    var isMutating: Bool
    var isFinal: Bool
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

/// Generic information for a type or API.
///
/// - Note: `Codable` for use in `CodebaseInfo`.
struct Generics: Equatable, Codable {
    /// Generic types and any associated inheritance type information for this type or API: `class Container<Owner, Element: Containable>`.
    var entries: [Generic]

    init(entries: [Generic] = []) {
        self.entries = entries
    }

    init(_ names: [TypeSignature], whereEqual: [TypeSignature]? = nil) {
        if let whereEqual {
            self.entries = zip(names, whereEqual).map { Generic(name: $0.0.name, whereEqual: $0.1) }
        } else {
            self.entries = names.map { Generic(name: $0.name) }
        }
    }

    /// Decode the generics information in the given syntax.
    static func `for`(syntax: GenericParameterClauseSyntax?, associatedTypeSyntax: [AssociatedtypeDeclSyntax] = [], where whereSyntax: GenericWhereClauseSyntax? = nil, in syntaxTree: SyntaxTree) -> (Generics, [Message]) {
        if syntax == nil && associatedTypeSyntax.isEmpty && whereSyntax == nil {
            return (Generics(), [])
        }
        var entries: [Generic] = []
        if let syntax {
            for parameter in syntax.genericParameterList {
                let name = parameter.name.text
                var inherits: [TypeSignature] = []
                if let inheritedType = parameter.inheritedType {
                    inherits.append(.for(syntax: inheritedType))
                }
                entries.append(Generic(name: name, inherits: inherits))
            }
        }
        for associatedType in associatedTypeSyntax {
            let name = associatedType.identifier.text
            var inherits: [TypeSignature] = []
            if let initializer = associatedType.initializer {
                inherits.append(TypeSignature.for(syntax: initializer.value))
            } else if let inheritance = associatedType.inheritanceClause {
                inherits += inheritance.inheritedTypeCollection.map {
                    TypeSignature.for(syntax: $0.typeName)
                }
            }
            entries.append(Generic(name: name, inherits: inherits))
        }
        var generics = Generics(entries: entries)
        var messages: [Message] = []
        generics.apply(syntax?.genericWhereClause, in: syntaxTree, messages: &messages)
        generics.apply(whereSyntax, in: syntaxTree, messages: &messages)
        for associatedType in associatedTypeSyntax {
            generics.apply(associatedType.genericWhereClause, in: syntaxTree, messages: &messages)
        }
        return (generics, messages)
    }

    private mutating func apply(_ whereSyntax: GenericWhereClauseSyntax?, in syntaxTree: SyntaxTree, messages: inout [Message]) {
        guard let whereSyntax else {
            return
        }
        for requirementSyntax in whereSyntax.requirementList {
            switch requirementSyntax.body {
            case .sameTypeRequirement(let syntax):
                apply(entryType: syntax.leftTypeIdentifier, constrainedTo: syntax.rightTypeIdentifier, whereEqual: true, in: syntaxTree, messages: &messages)
            case .conformanceRequirement(let syntax):
                apply(entryType: syntax.leftTypeIdentifier, constrainedTo: syntax.rightTypeIdentifier, whereEqual: false, in: syntaxTree, messages: &messages)
            case .layoutRequirement:
                messages.append(.unsupportedSyntax(requirementSyntax.body, source: syntaxTree.source))
            }
        }
    }

    private mutating func apply(entryType: TypeSyntax, constrainedTo: TypeSyntax, whereEqual: Bool, in syntaxTree: SyntaxTree, messages: inout [Message]) {
        var type = TypeSignature.for(syntax: entryType)
        var constrainedToType = TypeSignature.for(syntax: constrainedTo)
        let entryIndex: Int
        if case .named(let name, _) = type, let index = entries.firstIndex(where: { $0.name == name }) {
            entryIndex = index
        } else if whereEqual, case .named(let name, _) = constrainedToType, let index = entries.firstIndex(where: { $0.name == name }) {
            entryIndex = index
            swap(&type, &constrainedToType)
        } else {
            if case .named(let name, _) = type {
                entryIndex = entries.count
                entries.append(Generic(name: name))
            } else {
                messages.append(.genericUnsupportedWhereType(entryType, source: syntaxTree.source))
                return
            }
        }
        if whereEqual {
            entries[entryIndex].whereEqual = constrainedToType
        } else {
            entries[entryIndex].inherits.append(constrainedToType)
        }
    }

    /// Return the constrained type of the given generic parameter.
    ///
    /// - Returns: `.none` if the parameter is not found, `.composition(types)` for multiple constraints. If there are no constraints, returns itself as a `.named` type or the given fallback.
    func constrainedType(of name: String, ifEqual: Bool = false, fallback: TypeSignature? = nil) -> TypeSignature {
        return entries.first(where: { $0.name == name })?.constrainedType(ifEqual: ifEqual, fallback: fallback) ?? .none
    }

    /// Return the constrained type of the given generic parameter.
    ///
    /// - Seealso: `type(of: String)`
    func constrainedType(of signature: TypeSignature, ifEqual: Bool = false, fallback: TypeSignature? = nil) -> TypeSignature {
        guard case .named(let name, let genericTypes) = signature, genericTypes.isEmpty else {
            return .none
        }
        return constrainedType(of: name, ifEqual: ifEqual, fallback: fallback)
    }

    /// Merge the given constraints with these, allowing the given constraints to override our own.
    ///
    /// Use this to create a complete set of generics from the additional constraints declared by a function, extension, sub-protocol, etc.
    func merge(overrides generics: Generics, addNew: Bool = false) -> Generics {
        guard !generics.isEmpty else {
            return self
        }
        var result = self
        for i in 0..<generics.entries.count {
            if let ri = result.entries.firstIndex(where: { $0.name == generics.entries[i].name }) {
                result.entries[ri] = generics.entries[i]
            } else if case .named(let name, []) = generics.entries[i].whereEqual, let ri = result.entries.firstIndex(where: { $0.name == name }) {
                // If there is a constraint setting some new generic name equal to an existing name, replace the existing
                // name with the new name
                result.entries[ri] = Generic(name: generics.entries[i].name)
            } else if addNew {
                result.entries.append(generics.entries[i])
            }
        }
        return result
    }

    /// Merge an extension's generics into its extended type.
    func merge(extension signature: TypeSignature, generics: Generics) -> Generics {
        let extensionGenerics = signature.generics
        var result = self
        if extensionGenerics.count == entries.count {
            for i in 0..<entries.count {
                result.entries[i].whereEqual = extensionGenerics[i]
            }
        } else {
            result = result.merge(overrides: generics, addNew: true)
        }
        return result
    }

    func qualified(in node: SyntaxNode) -> Generics {
        var generics = self
        generics.entries = generics.entries.map { $0.qualified(in: node) }
        return generics
    }

    var isEmpty: Bool {
        return entries.isEmpty
    }

    var prettyPrintTree: PrettyPrintTree {
        let children = entries.map {
            var constraints = ""
            if let whereEqual = $0.whereEqual {
                constraints = " = \(whereEqual)"
            } else if !$0.inherits.isEmpty {
                constraints = ": \($0.inherits.map(\.description).joined(separator: ", "))"
            }
            return PrettyPrintTree(root: "\($0.name)\(constraints)")
        }
        return PrettyPrintTree(root: "generics", children: children)
    }
}

/// Information about a declared generic parameter.
struct Generic: Equatable, Codable {
    var name: String
    var inherits: [TypeSignature] = []
    var whereEqual: TypeSignature?

    /// Return this generic as a named type, e.g. `.named(T, [])`.
    var namedType: TypeSignature {
        return .named(name, [])
    }

    /// The constrained type of this generic.
    ///
    /// - Parameters:
    ///   - whereEqual: If true, only equality constraints are considered.
    /// - Returns: `.composition(types)` for multiple constraints. If there are no constraints, returns itself as a `.named` type or the given fallback.
    func constrainedType(ifEqual: Bool = false, fallback: TypeSignature? = nil) -> TypeSignature {
        if let whereEqual {
            return whereEqual
        }
        if ifEqual || inherits.isEmpty {
            return fallback ?? .named(name, [])
        } else if inherits.count == 1 {
            return inherits[0]
        } else {
            return .composition(inherits)
        }
    }

    func qualified(in node: SyntaxNode) -> Generic {
        var generic = self
        generic.whereEqual = generic.whereEqual.map { $0.qualified(in: node) }
        generic.inherits = generic.inherits.map { $0.qualified(in: node) }
        return generic
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
