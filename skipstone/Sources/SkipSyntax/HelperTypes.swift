import SwiftSyntax

/// A variable accessor.
struct Accessor<B> {
    var parameterName: String?
    var body: B? // Nil if the accessor has no body, as in a protocol { get set }
}

/// Parsed accessors.
struct Accessors {
    var getter: Accessor<CodeBlock>?
    var setter: Accessor<CodeBlock>?
    var willSet: Accessor<CodeBlock>?
    var didSet: Accessor<CodeBlock>?
    var isAsync = false
    var isThrows = false
    var attributes: Attributes?
    var messages: [Message] = []
}

/// Match when querying identifiers, functions, and other API.
struct APIMatch {
    var signature: TypeSignature
    var apiFlags: APIFlags = []
    /// May be `nil` for bultins like tuple members.
    var declarationType: StatementType?
    var isMember = false
    var availability: Availability = .available
}

/// Flags that affect API calls.
///
/// - Note: `Codable` for use in `CodebaseInfo`.
struct APIFlags: OptionSet, Hashable, Codable {
    let rawValue: Int

    static let async = APIFlags(rawValue: 1 << 0)
    static let autoclosure = APIFlags(rawValue: 1 << 1)
    static let mainActor = APIFlags(rawValue: 1 << 2)
    static let `throws` = APIFlags(rawValue: 1 << 3)
    static let viewBuilder = APIFlags(rawValue: 1 << 4)
    static let writeable = APIFlags(rawValue: 1 << 5)
    static let swiftUIBindable = APIFlags(rawValue: 1 << 6)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(isAsync: Bool = false, isThrows: Bool = false, isMainActor: Bool = false, isSwiftUIBindable: Bool = false, isViewBuilder: Bool = false, isWriteable: Bool = false) {
        var apiFlags: APIFlags = []
        if isAsync {
            apiFlags.insert(.async)
        }
        if isThrows {
            apiFlags.insert(.throws)
        }
        if isMainActor {
            apiFlags.insert(.mainActor)
        }
        if isSwiftUIBindable {
            apiFlags.insert(.swiftUIBindable)
        }
        if isViewBuilder {
            apiFlags.insert(.viewBuilder)
        }
        if isWriteable {
            apiFlags.insert(.writeable)
        }
        self = apiFlags
    }
}

/// Function argument value information.
struct ArgumentValue: Hashable {
    var type: TypeSignature
    var isLiteral = false
    var isInterpolated = false
}

/// A variable or function's async behavior.
enum AsyncBehavior {
    case sync
    case async
    case actor
}

/// @Attributes on a declaration.
///
/// - Note: `Codable` for use in `CodebaseInfo`.
struct Attributes: Hashable, PrettyPrintable, Codable {
    var attributes: [Attribute]

    init(attributes: [Attribute] = []) {
        self.attributes = attributes
    }

    private enum CodingKeys: String, CodingKey {
        case attributes = "a"
    }

    /// Decode the attribute information in the given syntax.
    static func `for`(syntax: AttributeListSyntax?, in syntaxTree: SyntaxTree) -> Attributes {
        guard let syntax else {
            return Attributes()
        }
        let attributes = syntax.compactMap {
            switch $0 {
            case .attribute(let syntax):
                return Attribute.for(syntax: syntax, in: syntaxTree)
            case .ifConfigDecl:
                return nil
            }
        }
        return Attributes(attributes: attributes)
    }

    /// Add all the attribute directives in the given extras.
    mutating func addDirectives(from extras: StatementExtras?) {
        guard let extras else {
            return
        }
        var attrs: [Attribute] = []
        for directive in extras.directives {
            guard case .attributes(let tokens) = directive else {
                continue
            }
            attrs.append(Attribute(signature: .named("directive", []), tokens: tokens))
        }
        attributes += attrs
    }

    /// Apply these attributes to the `APIFlags` and attributes of the given function type signature.
    func apply(toFunction signature: TypeSignature) -> TypeSignature {
        guard case .function(let parameters, let returnType, let initialAPIFlags, let initialAttributes) = signature else {
            return signature
        }
        var apiFlags: APIFlags = []
        var attributes: [Attribute] = []
        for attribute in self.attributes {
            switch attribute.kind {
            case .autoclosure:
                apiFlags.insert(.autoclosure)
            case .mainActor:
                apiFlags.insert(.mainActor)
            case .viewBuilder:
                apiFlags.insert(.viewBuilder)
            case .unknown:
                attributes.append(attribute)
            default:
                break
            }
        }
        let allAPIFlags = initialAPIFlags.union(apiFlags)
        var allAttributes = initialAttributes?.attributes ?? []
        for attribute in attributes {
            if !allAttributes.contains(attribute) {
                allAttributes.append(attribute)
            }
        }
        return .function(parameters, returnType, allAPIFlags, allAttributes.isEmpty ? nil : Attributes(attributes: allAttributes))
    }

    func contains(_ kind: Attribute.Kind) -> Bool {
        return attributes.contains { $0.kind == kind }
    }

    func of(kind: Attribute.Kind) -> [Attribute] {
        return attributes.filter { $0.kind == kind }
    }

    var isEmpty: Bool {
        return attributes.isEmpty
    }

    /// Some property wrappers are non-mutating.
    var isNonMutating: Bool {
        return contains(.appStorage) || contains(.bindable) || contains(.binding) || contains(.environment) || contains(.environmentObject) || contains(.nonmutating) || contains(.observedObject) || contains(.state) || contains(.stateObject)
    }

    func resolved(in node: SyntaxNode? = nil, context: TypeResolutionContext) -> Attributes {
        return Attributes(attributes: attributes.map { $0.resolved(in: node, context: context) })
    }

    var prettyPrintTree: PrettyPrintTree {
        let children = attributes.map {
            return PrettyPrintTree(root: "@\($0.signature)\($0.tokens)")
        }
        return PrettyPrintTree(root: "attributes", children: children)
    }
}

/// @Attribute on a declaration.
///
/// - Note: `Codable` for use in `CodebaseInfo`.
struct Attribute: Hashable, Codable {
    let signature: TypeSignature
    var tokens: [String] = []

    private enum CodingKeys: String, CodingKey {
        case signature = "s", tokens = "t"
    }

    /// Decode the attribute information in the given syntax.
    static func `for`(syntax: AttributeSyntax, in syntaxTree: SyntaxTree) -> Attribute? {
        let signature = TypeSignature.for(syntax: syntax.attributeName, in: syntaxTree)
        guard signature != .none else {
            return nil
        }
        guard let argument = syntax.arguments else {
            return Attribute(signature: signature)
        }
        switch argument {
        case .argumentList(let argumentListSyntax):
            let tokens = argumentListSyntax.map { $0.expression.description }
            return Attribute(signature: signature, tokens: tokens)
        case .availability(let availabilitySyntax):
            let tokens = availabilitySyntax.map { $0.argument.description }
            return Attribute(signature: signature, tokens: tokens)
        case .token(let tokenSyntax):
            return Attribute(signature: signature, tokens: [tokenSyntax.text])
        default:
            return Attribute(signature: signature)
        }
    }

    /// `nonmutating` is actually a modifier, but we treat it as an attribute.
    static let nonmutating = Attribute(signature: .named("nonmutating", []))

    /// The attribute kind, if it is recognized.
    enum Kind: Equatable {
        case appStorage
        case autoclosure
        case available
        case bindable
        case binding
        case deprecated
        case discardableResult
        /// Recorded from `StatementExtras.attributes`
        case directive
        case environment
        case environmentObject
        case escaping
        case frozen
        case indirect
        case inlinable
        case inlineAlways
        case inlineNever
        case mainActor
        case nonmutating
        case observable
        case observationIgnored
        case observedObject
        case published
        case state
        case stateObject
        case unavailable
        case unknown
        case viewBuilder
    }

    /// The attribute kind, if it is recognized.
    var kind: Kind {
        guard case .named(let name, _) = signature else {
            return .unknown
        }
        switch name {
        case "AppStorage":
            return .appStorage
        case "autoclosure":
            return .autoclosure
        case "available":
            if tokens.contains("unavailable") {
                return .unavailable
            } else if tokens.contains("deprecated") {
                return .deprecated
            } else {
                return .available
            }
        case "Bindable":
            return .bindable
        case "Binding":
            return .binding
        case "discardableResult":
            return .discardableResult
        case "directive":
            return .directive
        case "Environment":
            return .environment
        case "EnvironmentObject":
            return .environmentObject
        case "escaping":
            return .escaping
        case "frozen":
            return .frozen
        case "indirect":
            return .indirect
        case "inlinable":
            return .inlinable
        case "inline":
            if tokens.contains("__always") {
                return .inlineAlways
            } else if tokens.contains("never") {
                return .inlineNever
            } else {
                return .unknown
            }
        case "MainActor":
            return .mainActor
        case "nonmutating":
            return .nonmutating
        case "Observable":
            return .observable
        case "ObservationIgnored":
            return .observationIgnored
        case "ObservedObject":
            return .observedObject
        case "Published":
            return .published
        case "State":
            return .state
        case "StateObject":
            return .stateObject
        case "ViewBuilder":
            return .viewBuilder
        default:
            return .unknown
        }
    }

    func resolved(in node: SyntaxNode? = nil, context: TypeResolutionContext) -> Attribute {
        let kind = self.kind
        guard kind == .environment || kind == .environmentObject else {
            return self
        }
        let tokens = tokens.map { token in
            if token.hasSuffix(".self") {
                let tokenType = TypeSignature.for(name: String(token.dropLast(".self".count)), genericTypes: []).resolved(in: node, context: context)
                return tokenType.description + ".self"
            } else {
                return token
            }
        }
        return Attribute(signature: signature, tokens: tokens)
    }

    /// The string contained in any `message: "..."` token.
    var message: String? {
        guard let messageToken = tokens.first(where: { $0.hasPrefix("message: ") }) else {
            return nil
        }
        let message = messageToken.dropFirst("message: ".count)
        if message.hasPrefix("\"") && message.hasSuffix("\"") {
            return String(message.dropFirst().dropLast())
        } else {
            return String(message)
        }
    }
}

/// Availability information.
///
/// - Note: `Codable` for use in `CodebaseInfo`.
enum Availability: Codable {
    case available
    case deprecated(String?)
    case unavailable(String?)

    init(attributes: Attributes) {
        if let unavailable = attributes.attributes.first(where: { $0.kind == .unavailable }) {
            self = .unavailable(unavailable.message)
        } else if let deprecated = attributes.attributes.first(where: { $0.kind == .deprecated }) {
            self = .deprecated(deprecated.message)
        } else {
            self = .available
        }
    }

    /// Return the least available of this and the given availability.
    func least(_ other: Availability) -> Availability {
        switch self {
        case .unavailable:
            return self
        case .deprecated:
            if case .unavailable = other {
                return other
            } else {
                return self
            }
        case .available:
            if case .available = other {
                return self
            } else {
                return other
            }
        }
    }
}

/// Type of closure capture.
enum CaptureType {
    case none
    case unowned
    case weak
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

    private enum CodingKeys: String, CodingKey {
        case entries = "e"
    }

    init(_ names: [TypeSignature], whereEqual: [TypeSignature]? = nil) {
        if let whereEqual {
            self.entries = zip(names, whereEqual).map { Generic(name: $0.0.name, whereEqual: $0.1) }
        } else {
            self.entries = names.map { Generic(name: $0.name) }
        }
    }

    /// Decode the generics information in the given syntax.
    static func `for`(syntax: GenericParameterClauseSyntax?, associatedTypeSyntax: [AssociatedTypeDeclSyntax] = [], where whereSyntax: GenericWhereClauseSyntax? = nil, in syntaxTree: SyntaxTree) -> (Generics, [Message]) {
        if syntax == nil && associatedTypeSyntax.isEmpty && whereSyntax == nil {
            return (Generics(), [])
        }
        var entries: [Generic] = []
        if let syntax {
            for parameter in syntax.parameters {
                let name = parameter.name.text
                var inherits: [TypeSignature] = []
                if let inheritedType = parameter.inheritedType {
                    inherits.append(.for(syntax: inheritedType, in: syntaxTree))
                }
                entries.append(Generic(name: name, inherits: inherits))
            }
        }
        for associatedType in associatedTypeSyntax {
            let name = associatedType.name.text
            var inherits: [TypeSignature] = []
            if let initializer = associatedType.initializer {
                inherits.append(TypeSignature.for(syntax: initializer.value, in: syntaxTree))
            } else if let inheritance = associatedType.inheritanceClause {
                inherits += inheritance.inheritedTypes.map {
                    TypeSignature.for(syntax: $0.type, in: syntaxTree)
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
        for requirementSyntax in whereSyntax.requirements {
            switch requirementSyntax.requirement {
            case .sameTypeRequirement(let syntax):
                apply(entryType: syntax.leftType, constrainedTo: syntax.rightType, whereEqual: true, in: syntaxTree, messages: &messages)
            case .conformanceRequirement(let syntax):
                apply(entryType: syntax.leftType, constrainedTo: syntax.rightType, whereEqual: false, in: syntaxTree, messages: &messages)
            case .layoutRequirement:
                messages.append(.unsupportedSyntax(requirementSyntax.requirement, source: syntaxTree.source))
            }
        }
    }

    private mutating func apply(entryType: TypeSyntax, constrainedTo: TypeSyntax, whereEqual: Bool, in syntaxTree: SyntaxTree, messages: inout [Message]) {
        var type = TypeSignature.for(syntax: entryType, in: syntaxTree)
        var constrainedToType = TypeSignature.for(syntax: constrainedTo, in: syntaxTree)
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
                // If we found a concrete mapping, use it to populate any other generics that may be used in the entry, e.g.
                // in fun joined<RE>() -> [RE] where Element: Sequence<RE>, if we know Element we can populate RE
                if let type = generics.entries[i].whereEqual {
                    for signature in result.entries[ri].inherits {
                        result = signature.mergeGenericMappings(in: type, with: result)
                    }
                    if let signature = result.entries[ri].whereEqual {
                        result = signature.mergeGenericMappings(in: type, with: result)
                    }
                }
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
                if extensionGenerics[i].isFullySpecified {
                    result.entries[i].whereEqual = extensionGenerics[i]
                }
            }
        } else {
            result = result.merge(overrides: generics, addNew: true)
        }
        return result
    }

    func resolved(in node: SyntaxNode? = nil, context: TypeResolutionContext) -> Generics {
        var generics = self
        generics.entries = generics.entries.map { $0.resolved(in: node, context: context) }
        return generics
    }

    func resolvingSelf(in node: SyntaxNode? = nil) -> Generics {
        var generics = self
        generics.entries = generics.entries.map { $0.resolvingSelf(in: node) }
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

    private enum CodingKeys: String, CodingKey {
        case name = "n", inherits = "i", whereEqual = "w"
    }

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

    func resolved(in node: SyntaxNode? = nil, context: TypeResolutionContext) -> Generic {
        var generic = self
        generic.whereEqual = generic.whereEqual.map { $0.resolved(in: node, context: context) }
        generic.inherits = generic.inherits.map { $0.resolved(in: node, context: context) }
        return generic
    }

    func resolvingSelf(in node: SyntaxNode? = nil) -> Generic {
        var generic = self
        generic.whereEqual = generic.whereEqual.map { $0.resolvingSelf(in: node) }
        generic.inherits = generic.inherits.map { $0.resolvingSelf(in: node) }
        return generic
    }
}

/// An identifier found in pattern syntax.
struct IdentifierPattern {
    var name: String?
    var isVar = false
}

/// A labeled value, as used in function call parameters.
struct LabeledValue<V> {
    var label: String?
    var value: V
}

extension LabeledValue: Equatable, Hashable where V: Equatable, V: Hashable {
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
        case `fileprivate`
        case `default`
        case `internal`
        case `public`
        case `open`
    }

    var visibility: Visibility
    var setVisibility: Visibility
    var isStatic: Bool
    var isMutating: Bool
    var isFinal: Bool
    var isOverride: Bool
    var isLazy: Bool
    var isNonisolated: Bool

    private enum CodingKeys: String, CodingKey {
        case visibility = "v", setVisibility = "sv", isStatic = "s", isMutating = "m", isFinal = "f", isOverride = "o", isLazy = "l", isNonisolated = "n"
    }

    init(visibility: Visibility = .default, setVisibility: Visibility = .default, isStatic: Bool = false, isMutating: Bool = false, isFinal: Bool = false, isOverride: Bool = false, isLazy: Bool = false, isNonisolated: Bool = false) {
        self.visibility = visibility
        self.setVisibility = setVisibility
        self.isStatic = isStatic
        self.isMutating = isMutating
        self.isFinal = isFinal
        self.isOverride = isOverride
        self.isLazy = isLazy
        self.isNonisolated = isNonisolated
    }

    /// Decode the modifier information in the given syntax.
    static func `for`(syntax: DeclModifierListSyntax?) -> Modifiers {
        guard let syntax else {
            return Modifiers()
        }
        var visibility: Visibility = .default
        var setVisibility: Visibility = .default
        var isStatic = false
        var isMutating = false
        var isFinal = false
        var isOverride = false
        var isLazy = false
        var isNonisolated = false
        for modifier in syntax {
            switch modifier.name.text {
            case "open":
                if modifier.detail?.detail.text == "set" {
                    setVisibility = .open
                } else {
                    visibility = .open
                }
            case "public":
                if modifier.detail?.detail.text == "set" {
                    setVisibility = .public
                } else {
                    visibility = .public
                }
            case "internal":
                if modifier.detail?.detail.text == "set" {
                    setVisibility = .internal
                } else {
                    visibility = .internal
                }
            case "fileprivate":
                if modifier.detail?.detail.text == "set" {
                    setVisibility = .fileprivate
                } else {
                    visibility = .fileprivate
                }
            case "private":
                if modifier.detail?.detail.text == "set" {
                    setVisibility = .private
                } else {
                    visibility = .private
                }
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
            case "lazy":
                isLazy = true
            case "nonisolated":
                isNonisolated = true
            default:
                break
            }
        }
        return Modifiers(visibility: visibility, setVisibility: setVisibility, isStatic: isStatic, isMutating: isMutating, isFinal: isFinal, isOverride: isOverride, isLazy: isLazy, isNonisolated: isNonisolated)
    }

    var isEmpty: Bool {
        return visibility == .default && setVisibility == .default && !isStatic && !isFinal && !isOverride && !isLazy && !isNonisolated
    }

    var prettyPrintTree: PrettyPrintTree {
        var children: [PrettyPrintTree] = []
        if visibility != .default {
            children.append(PrettyPrintTree(root: String(describing: visibility)))
        }
        if setVisibility != .default {
            children.append(PrettyPrintTree(root: "\(visibility) set"))
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
        if isLazy {
            children.append(PrettyPrintTree(root: "lazy"))
        }
        if isNonisolated {
            children.append(PrettyPrintTree(root: "nonisolated"))
        }
        return PrettyPrintTree(root: "modifiers", children: children)
    }
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
    var isInOut: Bool
    var isVariadic: Bool
    var attributes: Attributes
    var defaultValue: V?
    var signature: TypeSignature.Parameter {
        return TypeSignature.Parameter(label: externalLabel, type: declaredType, isInOut: isInOut, isVariadic: isVariadic, hasDefaultValue: defaultValue != nil)
    }

    init(externalLabel: String?, internalLabel: String? = nil, declaredType: TypeSignature = .none, isInOut: Bool = false, isVariadic: Bool = false, attributes: Attributes = Attributes(), defaultValue: V? = nil) {
        self.externalLabel = externalLabel == "" || externalLabel == "_" ? nil : externalLabel
        _internalLabel = internalLabel
        self.declaredType = attributes.apply(toFunction: declaredType)
        self.isInOut = isInOut
        self.isVariadic = isVariadic
        self.attributes = attributes
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

    func resolvedType(in node: SyntaxNode? = nil, context: TypeResolutionContext) -> Parameter<V> {
        var parameter = self
        parameter.declaredType = declaredType.resolved(in: node, context: context)
        return parameter
    }

    func resolvingSelf(in node: SyntaxNode? = nil) -> Parameter<V> {
        var parameter = self
        parameter.declaredType = declaredType.resolvingSelf(in: node)
        return parameter
    }

    static func ==(lhs: Parameter<V>, rhs: Parameter<V>) -> Bool {
        return lhs.externalLabel == rhs.externalLabel && lhs.declaredType == rhs.declaredType && lhs.isInOut == rhs.isInOut && lhs.isVariadic == rhs.isVariadic && lhs.attributes == rhs.attributes
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(externalLabel)
        hasher.combine(declaredType)
        hasher.combine(isInOut)
        hasher.combine(isVariadic)
    }
}

/// A segment in a string literal.
enum StringLiteralSegment<E> {
    case string(String)
    case expression(E)
}

/// The result of visiting a syntax node.
enum VisitResult<N> {
    /// Skip the content of this node.
    case skip
    /// Recurse into the content of this node, optionally invoking the given block when leaving this node's content.
    case recurse(((N) -> Void)?)
}

extension Array where Element == Statement {
    /// Parse import statements for imports.
    var importedModulePaths: [[String]] {
        return compactMap { statement in
            guard statement.type == .importDeclaration, let importDeclaration = statement as? ImportDeclaration else {
                return nil
            }
            return importDeclaration.modulePath
        }
    }

    /// Whether these statements include a declaration of the given type (no extensions).
    func containsDeclaration(of signature: TypeSignature) -> Bool {
        let name = signature.name
        for statement in self {
            if statement.type != .extensionDeclaration, let typeDeclaration = statement as? TypeDeclaration {
                if typeDeclaration.name == name || typeDeclaration.members.containsDeclaration(of: signature) {
                    return true
                }
            }
        }
        return false
    }
}

extension Array where Element == String {
    /// Filter single-element import paths.
    var moduleName: String? {
        return count == 1 ? self[0] : nil
    }

    /// Append as separate lines.
    func appendLines(to output: OutputGenerator, indentation: Indentation) {
        for string in self {
            output.append(indentation).append(string).append("\n")
        }
    }
}

extension String {
    /// Remove backtick escaping.
    var removingBacktickEscaping: String {
        guard hasPrefix("`") && hasSuffix("`") else {
            return self
        }
        return String(dropFirst().dropLast())
    }

    /// If this is an implicit closure parameter - `$0`, `$1`, etc - return its index.
    var implicitClosureParameterIndex: Int? {
        if hasPrefix("$"), count > 1, let index = Int(String(self[index(after: startIndex)...])) {
            return index
        }
        return nil
    }

    /// Whether this identifier represents the projected value of a property wrapper.
    var isProjectedValue: Bool {
        return hasPrefix("$") && Int(dropFirst()) == nil
    }
}
