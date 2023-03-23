import SymbolKit

/// Wholistic information about the codebase needed when transpiling Swift to Kotlin.
public class KotlinCodebaseInfo {
    /// The package being generated.
    public let packageName: String?
    /// Plugins being applied to the translation.
    private(set) var plugins: [KotlinPlugin] = []
    private let symbols: Symbols?

    public init(packageName: String? = nil, symbols: Symbols? = nil, plugins: [KotlinPlugin] = []) {
        self.packageName = packageName
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
        syntaxTree.root.visit(perform: self.visit)
        plugins.forEach { $0.gather(from: syntaxTree) }
    }

    /// Finalize codebase info after gathering is complete.
    func didGather() {
        mergeExtensionInfo()
        plugins.forEach { $0.didGather() }
    }

    /// Any issues encountered during information gathering.
    func messages(for sourceFile: Source.File) -> [Message] {
        return []
    }

    fileprivate var typeInfo: [String: [TypeInfo]] = [:]
    fileprivate var extensionInfo: [String: [ExtensionInfo]] = [:]

    private func visit(node: SyntaxNode) -> VisitResult<SyntaxNode> {
        guard let statement = node as? Statement else {
            // Recurse to find nested declarations
            return .recurse(nil)
        }
        switch statement.type {
        case .classDeclaration:
            addTypeInfo(for: statement as! TypeDeclaration, mayBeMutableStructType: false)
            return .recurse(nil)
        case .enumDeclaration:
            addTypeInfo(for: statement as! TypeDeclaration, mayBeMutableStructType: false)
            return .recurse(nil)
        case .protocolDeclaration:
            let typeDeclaration = statement as! TypeDeclaration
            // A protocol may not be mutable struct if it extends from AnyObject, may be if it extends from nothing,
            // and we're not sure if it extends from other protocols which may themselves extend from AnyObject. We'll
            // check its symbols later
            let mayBeMutableStructType: Bool? = typeDeclaration.inherits.contains(.anyObject) ? false : typeDeclaration.inherits.isEmpty ? true : nil
            addTypeInfo(for: typeDeclaration, mayBeMutableStructType: mayBeMutableStructType)
            return .skip
        case .structDeclaration:
            let typeDeclaration = statement as! TypeDeclaration
            let mayBeMutableStructType = typeDeclaration.members.contains { member in
                switch member.type {
                case .variableDeclaration:
                    let variableDeclaration = member as! VariableDeclaration
                    return !variableDeclaration.isLet && (variableDeclaration.getter == nil || variableDeclaration.setter != nil)
                case .functionDeclaration:
                    return (member as! FunctionDeclaration).modifiers.isMutating
                default:
                    return false
                }
            }
            addTypeInfo(for: typeDeclaration, mayBeMutableStructType: mayBeMutableStructType)
        case .extensionDeclaration:
            let declaration = statement as! ExtensionDeclaration
            let key = declaration.extends.name
            var infos = extensionInfo[key, default: []]
            infos.append(ExtensionInfo(declaration: declaration, sourceFile: statement.sourceFile))
            extensionInfo[key] = infos
        default:
            break
        }
        return .recurse(nil)
    }

    /// Create a context that can access the given imported modules.
    func context(importedModuleNames: [String] = [], sourceFile: Source.File? = nil) -> Context {
        return Context(codebaseInfo: self, symbols: symbols?.context(importedModuleNames: importedModuleNames, sourceFile: sourceFile), sourceFile: sourceFile)
    }

    /// A context for accessing codebase information.
    struct Context {
        private let symbols: Symbols.Context?
        private let codebaseInfo: KotlinCodebaseInfo
        private let sourceFile: Source.File?

        fileprivate init(codebaseInfo: KotlinCodebaseInfo, symbols: Symbols.Context?, sourceFile: Source.File?) {
            self.codebaseInfo = codebaseInfo
            self.symbols = symbols
            self.sourceFile = sourceFile
        }

        /// Return all extensions of a given type.
        func extensions(of declaration: TypeDeclaration) -> [ExtensionDeclaration] {
            return codebaseInfo.extensionInfo[declaration.signature.name, default: []].compactMap { info in
                guard declaration.modifiers.visibility != .private || declaration.sourceFile == info.sourceFile else {
                    return nil
                }
                return info.declaration
            }
        }

        /// Whether the given type is a class, struct, etc, optionally limiting results to this module.
        func declarationType(of type: TypeSignature, mustBeInModule: Bool) -> StatementType? {
            let qualifiedName = type.name
            for info in codebaseInfo.typeInfo[qualifiedName, default: []] {
                if !info.isPrivate || info.sourceFile == sourceFile {
                    return info.declarationType
                }
            }
            guard !mustBeInModule, let symbols else {
                return nil
            }
            for candidate in symbols.ranked(symbols.lookup(name: qualifiedName)) {
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
        }

        /// The signatures of all visible constructors of the given type, including inherited constructors.
        func constructorParameters(of type: TypeSignature) -> [[ConstructorParameter]] {
            for info in codebaseInfo.typeInfo[type.name, default: []] {
                if !info.isPrivate || info.sourceFile == sourceFile {
                    if info.constructorParameters.isEmpty, let firstInherits = info.inherits.first {
                        return constructorParameters(of: firstInherits)
                    } else {
                        // If we've recursed on super types, map the declared generics to the supertype generics, e.g.:
                        // class A<T>; class B: A<Int>; map any uses of T => Int
                        return info.constructorParameters.map { parameters in
                            return parameters.map {
                                var p = $0
                                p.type = p.type.mappingGenerics(from: info.signature.generics, to: type.generics)
                                return p
                            }
                        }
                    }
                }
            }
            // If this is not a type within this module, fall back to using symbols. Note that symbols will be
            // missing any parameter default value expressions
            guard let symbols else {
                return []
            }
            return symbols.constructorSignatures(in: type).map {
                return $0.parameters.map { ConstructorParameter(label: $0.label, type: $0.type, isVariadic: $0.isVariadic, defaultValue: nil) }
            }
        }

        /// Whether a property with the given signature is implementing a protocol property.
        func isProtocolMember(declaration: VariableDeclaration, in type: TypeSignature) -> Bool {
            guard !declaration.names.isEmpty, let name = declaration.names[0] else {
                return false
            }
            return symbols?.protocolOf(type, hasMember: name, kind: declaration.modifiers.isStatic ? .typeProperty : .property, type: nil) == true
        }

        /// Whether a function with the given signature is implementing a protocol function.
        func isProtocolMember(declaration: FunctionDeclaration, in type: TypeSignature) -> Bool {
            return symbols?.protocolOf(type, hasMember: declaration.name, kind: declaration.modifiers.isStatic ? .typeMethod : .method, type: declaration.functionType) == true
        }

        /// Whether the given type may be a mutable struct.
        func mayBeMutableStruct(type: TypeSignature) -> Bool {
            for info in codebaseInfo.typeInfo[type.name, default: []] {
                if !info.isPrivate || info.sourceFile == sourceFile, let mayBeMutableStructType = info.mayBeMutableStructType {
                    return mayBeMutableStructType
                }
            }
            return symbols?.isMutableStruct(type: type) != false
        }

        /// Whether the given type conforms to `Error` through its protocols, **not** through inheritance.
        func conformsToError(type: TypeSignature) -> Bool {
            let qualifiedName = type.name
            guard qualifiedName != "Error" else {
                return true
            }
            for info in codebaseInfo.typeInfo[qualifiedName, default: []] {
                if !info.isPrivate || info.sourceFile == sourceFile {
                    if info.inherits.isEmpty {
                        return false
                    } else if info.inherits.contains(.named("Error", [])) {
                        return true
                    } else {
                        break // Unknown; check symbols below
                    }
                }
            }
            return symbols?.conformsToError(type: type) == true
        }

        /// Whether the given enum type has cases with associated values.
        func isSealedClassesEnum(type: TypeSignature) -> Bool {
            for info in codebaseInfo.typeInfo[type.name, default: []] {
                if !info.isPrivate || info.sourceFile == sourceFile {
                    if info.declarationType != .enumDeclaration {
                        return false
                    }
                    return info.hasAssociatedValues || conformsToError(type: type)
                }
            }
            guard let symbols else {
                return false
            }
            switch symbols.enumHasAssociatedValues(type: type) {
            case nil:
                return false
            case true?:
                return true
            case false?:
                return symbols.conformsToError(type: type) == true
            }
        }

        /// Whether the given name corresponds to a function in the given type.
        func isFunction(name: String, type: TypeSignature, in owningType: TypeSignature?) -> Bool {
            guard let symbols, case .function = type else {
                return false
            }
            var owningType = owningType
            var isStatic = false
            if case .metaType(let baseType) = owningType {
                isStatic = true
                owningType = baseType
            }
            return symbols.isFunction(name: name, in: owningType, isStatic: isStatic) == true
        }
    }

    private func addTypeInfo(for typeDeclaration: TypeDeclaration, mayBeMutableStructType: Bool?) {
        var info = TypeInfo(declarationType: typeDeclaration.type, signature: typeDeclaration.signature, inherits: typeDeclaration.inherits, mayBeMutableStructType: mayBeMutableStructType, isPrivate: typeDeclaration.modifiers.visibility == .private, sourceFile: typeDeclaration.sourceFile)
        if typeDeclaration.type != .protocolDeclaration {
            info.constructorParameters = constructorParameters(in: typeDeclaration.members)
        } else if typeDeclaration.type == .enumDeclaration {
            info.hasAssociatedValues = typeDeclaration.members.contains { ($0 as? EnumCaseDeclaration)?.associatedValues.isEmpty == false }
        }
        var infos = typeInfo[typeDeclaration.signature.name, default: []]
        infos.append(info)
        typeInfo[typeDeclaration.signature.name] = infos
    }

    private func mergeExtensionInfo() {
        for typeInfoEntry in typeInfo {
            typeInfo[typeInfoEntry.key] = typeInfoEntry.value.map {
                var typeInfo = $0
                extensionInfo[typeInfoEntry.key, default: []]
                    .forEach {
                        if !typeInfo.isPrivate || $0.sourceFile == typeInfo.sourceFile {
                            typeInfo.constructorParameters += constructorParameters(in: $0.declaration.members)
                        }
                    }
                return typeInfo
            }
        }
    }

    private func constructorParameters(in members: [Statement]) -> [[ConstructorParameter]] {
        var constructorParameters: [[ConstructorParameter]] = []
        for member in members {
            guard let constructor = member as? FunctionDeclaration, constructor.type == .initDeclaration && constructor.modifiers.visibility != .private else {
                continue
            }
            constructorParameters.append(constructor.parameters.map { parameter in
                ConstructorParameter(label: parameter.externalLabel, type: parameter.declaredType, isVariadic: parameter.isVariadic, defaultValue: parameter.defaultValue)
            })
        }
        return constructorParameters
    }

    /// Constructor parameter with translatable default value.
    struct ConstructorParameter {
        var label: String?
        var type: TypeSignature
        var isVariadic: Bool
        var defaultValue: Expression?
    }
}

private struct TypeInfo {
    let declarationType: StatementType
    let signature: TypeSignature
    let inherits: [TypeSignature]
    let mayBeMutableStructType: Bool?
    let isPrivate: Bool
    let sourceFile: Source.File?
    var constructorParameters: [[KotlinCodebaseInfo.ConstructorParameter]] = []
    var hasAssociatedValues = false
}

private struct ExtensionInfo {
    let declaration: ExtensionDeclaration
    let sourceFile: Source.File?
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
