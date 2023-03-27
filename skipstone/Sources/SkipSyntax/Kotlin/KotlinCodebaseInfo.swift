import SymbolKit

/// Wholistic information about the codebase needed when transpiling Swift to Kotlin.
public class KotlinCodebaseInfo {
    /// The package being generated.
    public let packageName: String?

    /// The non-Kotlin-specific codebase info.
    public let codebaseInfo: CodebaseInfo

    /// Plugins being applied to the translation.
    private(set) var plugins: [KotlinPlugin] = []

    private let symbols: Symbols?

    public init(packageName: String? = nil, codebaseInfo: CodebaseInfo, symbols: Symbols? = nil, plugins: [KotlinPlugin] = []) {
        self.packageName = packageName
        self.codebaseInfo = codebaseInfo
        self.symbols = symbols
        // Idea: Track which plugins we might need when we come across relevant code during initial translation and save traversing the tree for unnecessary plugins
        self.plugins = [
            // NOTE: Keep the struct plugin first because it adds members that may need processing by subsequent plugins
            KotlinStructPlugin(),
            KotlinErrorToThrowablePlugin(),
            KotlinConstructorPlugin(),
            KotlinIfWhenPlugin(),
            KotlinDeferPlugin(),
            KotlinSwiftUIPlugin(),
            KotlinImportMapPlugin(), // TODO: drive this from skip.yml metadata
        ] + plugins
    }

    /// Gather codebase-level information from the given syntax tree.
    func gather(from syntaxTree: SyntaxTree) {
        codebaseInfo.gather(from: syntaxTree, delegate: self)
        plugins.forEach { $0.gather(from: syntaxTree) }
    }

    /// Finalize codebase info and prepare for use after gathering is complete.
    func prepareForUse() {
        codebaseInfo.prepareForUse()
        plugins.forEach { $0.prepareForUse() }
    }

    /// Any issues encountered during information gathering.
    func messages(for sourceFile: Source.FilePath) -> [Message] {
        return []
    }

    /// Create a context that can access the given imported modules.
    func context(importedModuleNames: [String] = [], sourceFile: Source.FilePath? = nil) -> Context {
        return Context(codebaseInfo: codebaseInfo.context(importedModuleNames: importedModuleNames, sourceFile: sourceFile), symbols: symbols?.context(importedModuleNames: importedModuleNames, sourceFile: sourceFile))
    }

    /// A context for accessing codebase information.
    struct Context {
        private let codebaseInfo: CodebaseInfo.Context
        private let symbols: Symbols.Context?

        fileprivate init(codebaseInfo: CodebaseInfo.Context, symbols: Symbols.Context?) {
            self.codebaseInfo = codebaseInfo
            self.symbols = symbols
        }

        /// Return all extensions of a given type.
        func extensions(of type: TypeSignature) -> [ExtensionDeclaration] {
            return codebaseInfo.typeInfos(for: type).compactMap { $0.languageAdditions as? ExtensionDeclaration }
        }

        /// Whether the given type is a class, struct, etc, optionally limiting results to this module.
        func declarationType(of type: TypeSignature, mustBeInModule: Bool) -> StatementType? {
            if let symbols {
                if let typeInfo = codebaseInfo.typeInfos(for: type).first(where: { $0.declarationType != .extensionDeclaration }) {
                    return typeInfo.declarationType
                }
                guard !mustBeInModule else {
                    return nil
                }
                for candidate in symbols.ranked(symbols.lookup(name: type.name)) {
                    guard let kind = candidate.kind else {
                        continue
                    }
                    switch kind {
                    case .class:
                        return .classDeclaration
                    case .enum:
                        return .enumDeclaration
                    case .struct:
                        return .structDeclaration
                    case .protocol:
                        return .protocolDeclaration
                    default:
                        continue
                    }
                }
                return nil
            } else {
                guard let typeInfo = codebaseInfo.typeInfos(for: type).first(where: { $0.declarationType != .extensionDeclaration }) else {
                    return nil
                }
                if mustBeInModule && typeInfo.moduleName != codebaseInfo.info.moduleName {
                    return nil
                }
                return typeInfo.declarationType
            }
        }

        /// The signatures of all visible constructors of the given type.
        ///
        /// The type must be concrete - protocol constructors are excluded.
        ///
        /// - Note: The returned parameters are only populated with the external label, declared type, and default value (when available).
        func constructorParameters(of type: TypeSignature) -> [[Parameter<Expression>]] {
            let inits = codebaseInfo.typeInfos(for: type).flatMap { (typeInfo) -> [CodebaseInfoItem] in
                guard typeInfo.declarationType != .protocolDeclaration else {
                    return []
                }
                return typeInfo.visibleMembers(context: codebaseInfo).filter { $0.declarationType == .initDeclaration }
            }
            if inits.isEmpty, let symbols {
                return symbols.constructorSignatures(in: type).map {
                    return $0.parameters.map { Parameter<Expression>(externalLabel: $0.label, declaredType: $0.type, isVariadic: $0.isVariadic, isInOut: false, defaultValue: nil) }
                }
            }
            return inits.compactMap { (initInfo) -> [Parameter<Expression>]? in
                guard let functionInfo = initInfo as? CodebaseInfo.FunctionInfo, case .function(let parameters, _) = functionInfo.signature else {
                    return nil
                }
                // Filter out generated default constructor
                guard parameters.count > 0 || !functionInfo.isGenerated || inits.count > 1 else {
                    return nil
                }
                var defaultValues: [Expression?]
                if let additions = functionInfo.languageAdditions as? [Expression?], additions.count == parameters.count {
                    defaultValues = additions
                } else {
                    defaultValues = Array<Expression?>(repeating: nil, count: parameters.count)
                }
                return parameters.enumerated().map { (index, parameter) in
                    Parameter<Expression>(externalLabel: parameter.label, declaredType: parameter.type, isVariadic: parameter.isVariadic, isInOut: false, defaultValue: defaultValues[index])
                }
            }
        }

        /// Whether a property with the given signature is implementing a protocol property.
        func isProtocolMember(declaration: VariableDeclaration, in type: TypeSignature) -> Bool {
            guard !declaration.names.isEmpty, let name = declaration.names[0] else {
                return false
            }
            if let symbols {
                return symbols.protocolOf(type, hasMember: name, kind: declaration.modifiers.isStatic ? .typeProperty : .property, type: nil) == true
            } else {
                let protocolSignatures = codebaseInfo.protocolSignatures(for: type)
                return protocolSignatures.contains { hasMember($0, name: name, type: nil, isStatic: declaration.modifiers.isStatic) }
            }
        }

        /// Whether a function with the given signature is implementing a protocol function.
        func isProtocolMember(declaration: FunctionDeclaration, in type: TypeSignature) -> Bool {
            if let symbols {
                return symbols.protocolOf(type, hasMember: declaration.name, kind: declaration.modifiers.isStatic ? .typeMethod : .method, type: declaration.functionType) == true
            } else {
                let protocolSignatures = codebaseInfo.protocolSignatures(for: type)
                return protocolSignatures.contains { hasMember($0, name: declaration.name, type: declaration.functionType, isStatic: declaration.modifiers.isStatic) }
            }
        }

        /// Whether the given type may be a mutable struct.
        func mayBeMutableStruct(type: TypeSignature) -> Bool {
            if let symbols {
                return symbols.isMutableStruct(type: type) != false
            } else {
                let typeInfos = codebaseInfo.typeInfos(for: type)
                if let structInfo = typeInfos.first(where: { $0.declarationType == .structDeclaration }) {
                    return structInfo.variables.contains(where: { !$0.isReadOnly }) || structInfo.functions.contains(where: { $0.isMutating })
                } else if typeInfos.contains(where: { $0.declarationType == .protocolDeclaration }) {
                    // If this is a protocol that is constrained to class impls, then it isn't a mutable struct. Otherwise it could be
                    return !codebaseInfo.protocolSignatures(for: type).contains(.anyObject)
                } else if typeInfos.isEmpty {
                    // Assume an unknown type could be a mutable struct
                    let type = type.asOptional(false)
                    if case .named = type {
                        return true
                    } else if type == .any {
                        return true
                    } else {
                        return false
                    }
                } else {
                    return false
                }
            }
        }

        /// Whether the given type conforms to `Error` through its protocols, **not** through inheritance.
        func conformsToError(type: TypeSignature) -> Bool {
            if let symbols {
                return symbols.conformsToError(type: type) == true
            } else {
                return codebaseInfo.protocolSignatures(for: type).contains(.named("Error", []))
            }
        }

        /// Whether the given enum type has cases with associated values.
        func isSealedClassesEnum(type: TypeSignature) -> Bool {
            if let symbols {
                switch symbols.enumHasAssociatedValues(type: type) {
                case nil:
                    return false
                case true?:
                    return true
                case false?:
                    return symbols.conformsToError(type: type) == true
                }
            } else {
                guard let enumInfo = codebaseInfo.typeInfos(for: type).first(where: { $0.declarationType == .enumDeclaration }) else {
                    return false
                }
                if enumInfo.cases.contains(where: { if case .function = $0.signature { return true } else { return false } }) {
                    return true
                }
                return conformsToError(type: type)
            }
        }

        /// Whether the given name corresponds to a function in the given type.
        func isFunctionName(_ name: String, in owningType: TypeSignature?) -> Bool {
            var owningType = owningType?.asOptional(false)
            var isStatic = false
            if case .metaType(let baseType) = owningType {
                isStatic = true
                owningType = baseType
            }
            if let symbols {
                return symbols.isFunction(name: name, in: owningType, isStatic: isStatic) == true
            } else {
                if owningType != nil && !isStatic && name == "init" {
                    return true
                }
                let items = codebaseInfo.ranked(codebaseInfo.lookup(name: name))
                return items.contains { $0.declarationType == .functionDeclaration && $0.declaringType?.name == owningType?.name }
            }
        }

        private func hasMember(_ owningType: TypeSignature, name: String, type: TypeSignature?, isStatic: Bool) -> Bool {
            for typeInfo in codebaseInfo.typeInfos(for: owningType) {
                if typeInfo.visibleMembers(context: codebaseInfo).contains(where: { $0.name == name && $0.isStatic == isStatic && (type == nil || $0.signature == type) }) {
                    return true
                }
            }
            return false
        }
    }
}

// Internal for testing

extension Symbols.Context {
    /// Whether the given member name and optional type maps to a member of any protocol of the given declaring type, including inherited protocols.
    ///
    /// - Returns: true if this is a member of a protocol, false if not, and nil if there is no known type for the given name.
    func protocolOf(_ declaringType: TypeSignature, hasMember name: String, kind memberKind: SymbolGraph.Symbol.KindIdentifier, type: TypeSignature?) -> Bool? {
        let candidates = lookup(name: declaringType.name)
        var hasType = false
        for candidate in ranked(candidates) {
            guard let kind = candidate.kind else {
                continue
            }
            switch kind {
            case .class, .enum, .struct, .extension, .protocol:
                hasType = true
                if hasProtocolMember(candidate, name: name, kind: memberKind, type: type) {
                    return true
                }
            default:
                break
            }
        }
        return hasType ? false : nil
    }

    /// Whether the given type maps to a symbol that is known to be a mutable struct type.
    ///
    /// - Returns: true if a symbol exists for a mutable struct type, false if only immutable type symbols exist, and nil if no type symbol exists.
    func isMutableStruct(type: TypeSignature) -> Bool? {
        let candidates = lookup(name: type.name)
        var hasType = false
        for candidate in ranked(candidates) {
            guard let kind = candidate.kind else {
                continue
            }
            switch kind {
            case .class:
                hasType = true
            case .enum:
                hasType = true
            case .struct:
                if isMutableStruct(candidate) {
                    return true
                }
                hasType = true
            case .protocol:
                if !conformsTo(candidate, typeName: "AnyObject") {
                    return true
                }
                hasType = true
            default:
                break
            }
        }
        return hasType ? false : nil
    }

    /// Whether the given type conforms to `Error` through its protocols, **not** through inheritance.
    ///
    /// - Returns: true if a symbol exists for an error type, false if the type does not conform to `Error`, and nil if no type symbol exists.
    func conformsToError(type: TypeSignature) -> Bool? {
        let candidates = lookup(name: type.name)
        for candidate in ranked(candidates) {
            guard let kind = candidate.kind else {
                continue
            }
            switch kind {
            case .class, .enum, .struct, .protocol:
                return conformsTo(candidate, typeName: "Error")
            default:
                break
            }
        }
        return nil
    }

    /// Return the type signatures of all constructors for the given type name, including inherited constructors.
    func constructorSignatures(in type: TypeSignature) -> [TypeSignature] {
        let candidates = ranked(lookup(name: type.name))
        for candidate in candidates {
            guard let kind = candidate.kind, candidate.visibility != .private else {
                continue
            }
            switch kind {
            case .class:
                fallthrough
            case .enum:
                fallthrough
            case .struct:
                return constructorSignatures(candidate)
            default:
                break
            }
        }
        return []
    }

    /// Whether the given enum has cases with associated values.
    func enumHasAssociatedValues(type: TypeSignature) -> Bool? {
        let candidates = lookup(name: type.name)
        var hasType = false
        for candidate in ranked(candidates) {
            guard let kind = candidate.kind else {
                continue
            }
            switch kind {
            case .class:
                hasType = true
            case .enum:
                return hasAssociatedValues(candidate)
            case .struct:
                hasType = true
            case .protocol:
                hasType = true
            default:
                break
            }
        }
        return hasType ? false : nil
    }

    /// Whether the given name matches a function name.
    func isFunction(name: String, in type: TypeSignature?, isStatic: Bool) -> Bool? {
        if let type {
            let candidates = lookup(name: type.name)
            var hasType = false
            for candidate in ranked(candidates) {
                guard let kind = candidate.kind else {
                    continue
                }
                switch kind {
                case .class:
                    fallthrough
                case .enum:
                    fallthrough
                case .extension:
                    fallthrough
                case .struct:
                    fallthrough
                case .protocol:
                    hasType = true
                    if hasFunction(candidate, name: name, isStatic: isStatic) {
                        return true
                    }
                default:
                    break
                }
            }
            return hasType ? false : nil
        } else {
            for candidate in ranked(lookup(name: name)) {
                if candidate.kind == .func {
                    return true
                }
            }
            return false
        }
    }

    private func hasProtocolMember(_ symbol: Symbol, name: String, kind: SymbolGraph.Symbol.KindIdentifier, type: TypeSignature?) -> Bool {
        for relationship in symbol.relationships {
            if relationship.kind == .inheritsFrom && !relationship.isInverse {
                //~~~ need to map generics
                if let inheritsFrom = lookup(identifier: relationship.targetIdentifier ?? ""), hasProtocolMember(inheritsFrom, name: name, kind: kind, type: type) {
                    return true
                }
            } else if relationship.kind == .conformsTo && !relationship.isInverse {
                //~~~ need to map generics
                if let conformsTo = lookup(identifier: relationship.targetIdentifier ?? ""), hasProtocolMember(conformsTo, name: name, kind: kind, type: type) {
                    return true
                }
            } else if relationship.kind == .requirementOf && relationship.isInverse {
                guard let member = lookup(identifier: relationship.targetIdentifier ?? ""), member.name == name, member.kind == kind else {
                    continue
                }
                guard let type else {
                    return true
                }
                if kind == .method || kind == .typeMethod {
                    if type == member.functionSignature(symbols: symbols) {
                        return true
                    }
                } else {
                    if type == member.variableType(symbols: symbols) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func constructorSignatures(_ symbol: Symbol) -> [TypeSignature] {
        var signatures: [TypeSignature] = []
        var inheritsFrom: Symbol? = nil
        for relationship in symbol.relationships {
            if relationship.kind == .inheritsFrom && !relationship.isInverse {
                inheritsFrom = lookup(identifier: relationship.targetIdentifier ?? "")
                continue
            }
            guard relationship.kind == .memberOf && relationship.isInverse else {
                continue
            }
            guard let member = lookup(identifier: relationship.targetIdentifier ?? ""), let memberKind = member.kind, case .`init` = memberKind else {
                continue
            }
            signatures.append(member.functionSignature(symbols: symbols))
        }
        if signatures.isEmpty, let inheritsFrom {
            return constructorSignatures(inheritsFrom)//~~~ needs to map to generics applied in extends list, not generics of this symbol .map { $0.mappingGenerics(from: inheritsFrom.generics, to: symbol.generics) }
        }
        return signatures
    }

    private func isMutableStruct(_ symbol: Symbol) -> Bool {
        for relationship in symbol.relationships {
            guard relationship.kind == .memberOf && relationship.isInverse else {
                continue
            }
            guard let member = lookup(identifier: relationship.targetIdentifier ?? ""), let memberKind = member.kind else {
                // Assume any unknown member might be mutating
                return true
            }
            switch memberKind {
            case .property:
                if member.isVariableReadWrite {
                    return true
                }
            case .method:
                if member.isFunctionMutating {
                    return true
                }
            default:
                break
            }
        }
        return false
    }

    private func conformsTo(_ candidate: Symbol, typeName: String) -> Bool {
        if candidate.isInDeclaredInheritanceList(typeName: typeName) {
            return true
        }
        for relationship in candidate.relationships {
            guard relationship.kind == .conformsTo, !relationship.isInverse, let targetSymbol = lookup(identifier: relationship.targetIdentifier ?? "") else {
                continue
            }
            if conformsTo(targetSymbol, typeName: typeName) {
                return true
            }
        }
        return false
    }

    private func hasAssociatedValues(_ symbol: Symbol) -> Bool {
        for relationship in symbol.relationships {
            guard relationship.kind == .memberOf && relationship.isInverse else {
                continue
            }
            guard let member = lookup(identifier: relationship.targetIdentifier ?? ""), let memberKind = member.kind, memberKind == .case else {
                continue
            }
            if !member.functionSignature(symbols: symbols).parameters.isEmpty {
                return true
            }
        }
        return false
    }

    private func hasFunction(_ symbol: Symbol, name: String, isStatic: Bool) -> Bool {
        for relationship in symbol.relationships {
            if relationship.kind == .memberOf && relationship.isInverse, let member = lookup(identifier: relationship.targetIdentifier ?? "") {
                if member.name == name, (isStatic && member.kind == .typeMethod) || (!isStatic && member.kind == .method) {
                    return true
                }
            } else if relationship.kind == .inheritsFrom, !relationship.isInverse, let inheritsFrom = lookup(identifier: relationship.targetIdentifier ?? "") {
                if hasFunction(inheritsFrom, name: name, isStatic: isStatic) {
                    return true
                }
            }
        }
        return false
    }
}

extension KotlinCodebaseInfo: CodebaseInfoGatherDelegate {
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typeInfo: CodebaseInfo.TypeInfo, from statement: ExtensionDeclaration) {
        // Keep the extension statements around so we can move it to the extended declarations
        typeInfo.languageAdditions = statement
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather functionInfo: inout CodebaseInfo.FunctionInfo, from statement: FunctionDeclaration) {
        // Track init parameter default values so that we can transfer them to subclass constructors we generate
        if functionInfo.name == "init" {
            functionInfo.languageAdditions = statement.parameters.map(\.defaultValue)
        }
    }
}
