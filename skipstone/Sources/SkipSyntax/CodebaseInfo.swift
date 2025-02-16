/// Information about the codebase used in type inference and translation.
public final class CodebaseInfo {
    /// The current module name.
    public let moduleName: String?

    /// Target language helper.
    var languageAdditions: CodebaseInfoLanguageAdditions?
    
    /// Supply the current module name.
    public init(moduleName: String? = nil) {
        self.moduleName = moduleName
    }
    
    /// Exported information from dependent modules.
    ///
    /// - Seealso: `ModuleExport`
    public var dependentModules: [ModuleExport] = [] {
        didSet {
            assert(!isInUse)
        }
    }

    /// Map between a Swift module and the equivalent Skip module(s).
    ///
    /// When a Swift module transitively imports other modules - e.g.`SwiftUI` imports `Foundation` - put the corresponding Skip module first
    /// and any transitive modules after it - e.g. `[SkipUI, SkipFoundation]`.
    static let moduleNameMap: [String: [String]] = [
        "AVFoundation": ["SkipAV"],
        "AVKit": ["SkipAV"],
        "Combine": ["SkipModel"],
        "CoreBluetooth": ["SkipBluetooth"],
        "CoreFoundation": ["SkipFoundation"],
        "CoreGraphics": ["SkipLib"],
        "CryptoKit": ["SkipFoundation"],
        "Dispatch": ["SkipFoundation"],
        "Foundation": ["SkipFoundation"],
        "JavaScriptCore": ["SkipScript"],
        "Observation": ["SkipModel"],
        "os": ["SkipFoundation"],
        "OSLog": ["SkipFoundation"],
        "Swift": ["SkipLib"],
        "SwiftUI": ["SkipUI", "SkipFoundation", "SkipModel"],
        // Native files using SkipFuseUI might also contain transpiled code or bridge SwiftUI types to transpiled code
        "SkipFuseUI": ["SkipUI", "SkipFoundation", "SkipModel"],
        "UIKit": ["SkipUI", "SkipFoundation", "SkipModel"],
        "UserNotifications": ["SkipUI", "SkipFoundation", "SkipModel"],
        "XCTest": ["SkipUnit"],
    ]

    /// Messages for the user created during information gathering.
    func messages(for sourceFile: Source.FilePath) -> [Message] {
        return (messages[sourceFile] ?? []) + (languageAdditions?.messages(for: sourceFile) ?? [])
    }
    
    /// Gather codebase-level information from the given syntax tree.
    func gather(from syntaxTree: SyntaxTree) {
        assert(!isInUse)
        let importedModuleNames = syntaxTree.root.statements.importedModulePaths.compactMap(\.moduleName)
        var needsVariableTypeInference = false
        for statement in syntaxTree.root.statements {
            switch statement.type {
            case .actorDeclaration, .classDeclaration, .enumDeclaration, .protocolDeclaration, .structDeclaration:
                let typeInfo = TypeInfo(statement: statement as! TypeDeclaration, codebaseInfo: self, syntaxTree: syntaxTree)
                typeInfo.importedModuleNames = importedModuleNames
                rootTypes.append(typeInfo)
                needsVariableTypeInference = needsVariableTypeInference || typeInfo.needsVariableTypeInference
            case .extensionDeclaration:
                let typeInfo = TypeInfo(statement: statement as! ExtensionDeclaration, codebaseInfo: self, syntaxTree: syntaxTree)
                typeInfo.importedModuleNames = importedModuleNames
                rootExtensions.append(typeInfo)
                needsVariableTypeInference = needsVariableTypeInference || typeInfo.needsVariableTypeInference
            case .functionDeclaration, .initDeclaration, .deinitDeclaration:
                var functionInfo = FunctionInfo(statement: statement as! FunctionDeclaration, codebaseInfo: self, syntaxTree: syntaxTree)
                functionInfo.importedModuleNames = importedModuleNames
                rootFunctions.append(functionInfo)
            case .typealiasDeclaration:
                var typealiasInfo = TypealiasInfo(statement: statement as! TypealiasDeclaration, codebaseInfo: self, syntaxTree: syntaxTree)
                typealiasInfo.importedModuleNames = importedModuleNames
                rootTypealiases.append(typealiasInfo)
            case .variableDeclaration:
                var variableInfo = VariableInfo(statement: statement as! VariableDeclaration, codebaseInfo: self, syntaxTree: syntaxTree)
                variableInfo.importedModuleNames = importedModuleNames
                rootVariables.append(variableInfo)
                needsVariableTypeInference = needsVariableTypeInference || variableInfo.needsTypeInference
            default:
                break
            }
        }
        // Save the syntax trees that have members requiring additional type inference
        if needsVariableTypeInference {
            typeInferenceTrees[syntaxTree.source.file] = syntaxTree
        }
        (languageAdditions as? CodebaseInfoLanguageAdditionsGatherDelegate)?.codebaseInfo(self, didGatherFrom: syntaxTree)
    }
    
    /// Finalize codebase info and prepare for use.
    ///
    /// - Warning: Codebase info should not be used until this has been called. After calling this function, do not mutate info.
    func prepareForUse() {
        isInUse = true
        dependentModules.forEach { $0.prepareForUse() }

        buildItemsByName() // We use this for lookups in subsequent steps
        inferVariableTypes() // May need variable types to match signatures to protocol generics
        resolveTypeSignatures()
        fixupGenericsInfo()
        addGeneratedConstructors()
        addGeneratedRawValues()
        addMainActorFlags()
        buildItemsByName() // Final mappings after updates

        languageAdditions?.prepareForUse(codebaseInfo: self)
    }
    
    /// Create a context that can access the given imported modules.
    func context(importedModuleNames: [String] = [], sourceFile: Source.FilePath? = nil) -> Context {
        return context(importedModuleNames: importedModuleNames, sourceFile: sourceFile, cache: ContextCache())
    }

    private func context(importedModuleNames: [String], sourceFile: Source.FilePath?, cache: ContextCache) -> Context {
        let mappedModuleNames = importedModuleNames.flatMap { Self.moduleNameMap[$0] ?? [$0] }
        return Context(global: self, importedModuleNames: Set(mappedModuleNames), sourceFile: sourceFile, cache: cache)
    }

    /// The items for the given name.
    ///
    /// If this is a `.`-separated qualified type name, only returns types that match the full path.
    ///
    /// - Parameters:
    ///  - qualifiedMatch: If true, names without `.` separators will only match root types.
    func lookup(name: String, moduleName: String? = nil, qualifiedMatch: Bool = false) -> [CodebaseInfoItem] {
        let path = name.split(separator: ".").map { String($0) }
        guard !path.isEmpty else {
            return []
        }
        let candidates = itemsByName[path[path.count - 1], default: []]
        guard !candidates.isEmpty else {
            return []
        }
        return match(candidates: candidates, path: path.dropLast(), moduleName: moduleName, qualifiedMatch: qualifiedMatch)
    }

    private func match(candidates: [CodebaseInfoItem], path: [String], moduleName: String?, qualifiedMatch: Bool) -> [CodebaseInfoItem] {
        var matches = candidates
        if let moduleName {
            let mappedModuleName = Self.moduleNameMap[moduleName]?.first ?? moduleName
            matches = matches.filter { $0.moduleName == mappedModuleName }
        }
        if !path.isEmpty {
            let baseName = path.joined(separator: ".")
            matches = matches.filter { ($0 is TypeInfo || $0 is TypealiasInfo) && $0.declaringType?.name == baseName }
            // Only attempt to match as a module-qualified name if no unqualified matches
            if matches.isEmpty && moduleName == nil {
                matches = match(candidates: candidates, path: Array(path.dropFirst()), moduleName: path[0], qualifiedMatch: qualifiedMatch)
            }
        } else if qualifiedMatch {
            matches = matches.filter { $0.declaringType == nil }
        }
        return matches
    }

    /// Return all type infos for the given type.
    func typeInfos(forNamed type: TypeSignature) -> [TypeInfo] {
        return typeInfos(forNamed: type, candidateMap: { $0 })
    }

    /// Return the type info for the given type's primary declaration, omitting extensions.
    func primaryTypeInfo(forNamed type: TypeSignature) -> TypeInfo? {
        return typeInfos(forNamed: type).first { $0.declarationType != .extensionDeclaration }
    }

    private func typeInfos(forNamed type: TypeSignature, candidateMap: ([CodebaseInfoItem]) -> [CodebaseInfoItem], recursionDepth: Int = 0) -> [TypeInfo] {
        // Invalid Swift code containing circular typealiases can cause infinite recursion
        guard recursionDepth < 10 else {
            return []
        }
        return candidateTypeNames(for: type).flatMap { (name, moduleName) in
            let candidates = candidateMap(lookup(name: name, moduleName: moduleName, qualifiedMatch: true))
            return candidates.flatMap { candidate in
                if let typeInfo = candidate as? TypeInfo {
                    return [typeInfo]
                } else if let typealiasInfo = candidate as? TypealiasInfo {
                    return typeInfos(forNamed: typealiasInfo.targetSignature, candidateMap: candidateMap, recursionDepth: recursionDepth + 1)
                } else {
                    return []
                }
            }
        }
    }

    /// Return the concrete (i.e. non-protocol) inheritance chain for the given type.
    ///
    /// The type will be first, followed by its superclass, etc.
    ///
    /// - Note: Any generics on the given type are not applied to the result signatures.
    func inheritanceChainSignatures(forNamed type: TypeSignature) -> [TypeSignature] {
        guard let concreteTypeInfo = typeInfos(forNamed: type).first(where: { $0.declarationType != .protocolDeclaration && $0.declarationType != .extensionDeclaration }) else {
            return []
        }
        guard concreteTypeInfo.declarationType == .classDeclaration, let firstInherits = concreteTypeInfo.inherits.first else {
            return [concreteTypeInfo.signature]
        }
        return [concreteTypeInfo.signature] + inheritanceChainSignatures(forNamed: firstInherits)
    }

    // We need these in testing because SkipLib isn't available
    private static let builtinProtocols: [TypeSignature] = [
        .module("Swift", .named("CustomStringConvertible", [])),
        .module("Swift", .named("Equatable", [])),
        .module("Swift", .named("Error", [])),
        .module("Swift", .named("OptionSet", [])),
    ]
    private static let builtinEquatableSubprotocols: [TypeSignature] = [
        .module("Swift", .named("Comparable", [])),
        .module("Swift", .named("Hashable", [])),
    ]

    /// Return the protocols the given type conforms to, including inherited protocols.
    ///
    /// If the type itself is a protocol, it is included first in the list.
    func protocolSignatures(forNamed type: TypeSignature) -> [TypeSignature] {
        let type = type.asOptional(false)
        if type == .anyObject || Self.builtinProtocols.contains(where: { $0.isSameType(as: type) }) {
            return [type]
        } else if Self.builtinEquatableSubprotocols.contains(where: { $0.isSameType(as: type) }) {
            return [type, .named("Equatable", [])]
        }
        // Gather inherited signatures, then insert the given type at the front if it is also a protocol
        let typeInfos = typeInfos(forNamed: type)
        var signatures = typeInfos.flatMap { $0.inherits.flatMap { protocolSignatures(forNamed: $0) } }
        if let protocolInfo = typeInfos.first(where: { $0.declarationType == .protocolDeclaration }) {
            signatures.insert(protocolInfo.signature, at: 0)
        }
        return signatures
    }

    /// A context for accessing visible codebase information.
    struct Context {
        let global: CodebaseInfo
        let importedModuleNames: Set<String>
        let sourceFile: Source.FilePath?
        private let cache: ContextCache

        fileprivate init(global: CodebaseInfo, importedModuleNames: Set<String>, sourceFile: Source.FilePath?, cache: ContextCache) {
            self.global = global
            self.sourceFile = sourceFile
            self.importedModuleNames = importedModuleNames
            self.cache = cache
        }
        
        /// Score, sort, and filter the given items.
        ///
        /// - Returns: The items with a score > 0 in order from highest to lowest score.
        func ranked(_ items: [CodebaseInfoItem]) -> [CodebaseInfoItem] {
            return zip(items, items.map { rankScore(of: $0) })
                .filter { $0.1 > 0 } // score > 0
                .sorted { $0.1 > $1.1 } // sort on score
                .map(\.0) // return symbol
        }
        
        /// Score an item based on its visibility in this context.
        ///
        /// A score of 0 indicates that the item is not visible.
        func rankScore(of item: CodebaseInfoItem) -> Int {
            return item.rankScore(moduleName: global.moduleName, importedModuleNames: importedModuleNames, sourceFile: sourceFile)
        }
        
        /// Return all type infos visible for the given type.
        func typeInfos(forNamed type: TypeSignature) -> [TypeInfo] {
            return global.typeInfos(forNamed: type, candidateMap: ranked)
        }

        /// Return the type info for the given type's primary declaration, omitting extensions.
        func primaryTypeInfo(forNamed type: TypeSignature) -> TypeInfo? {
            // Profiling indicated that ranking typeInfos to get the primary type info can be expensive, so cache
            if let primaryTypeInfo = cache.primaryTypeInfos?[type] {
                return primaryTypeInfo
            }
            let primaryTypeInfo = typeInfos(forNamed: type).first { $0.declarationType != .extensionDeclaration }
            if let primaryTypeInfo {
                cache.primaryTypeInfos?[type] = primaryTypeInfo
            }
            return primaryTypeInfo
        }

        /// Return the members of the given type that are visible in this context.
        func visibleMembers(of typeInfo: TypeInfo) -> [CodebaseInfoItem] {
            if let cached = cache.visibleMembers?[typeInfo] {
                return cached
            }
            let visibleMembers = typeInfo.members.filter { rankScore(of: $0) > 0 }
            cache.visibleMembers?[typeInfo] = visibleMembers
            return visibleMembers
        }

        /// Whether the given type is a class, struct, etc, optionally limiting results to this module.
        func declarationType(forNamed type: TypeSignature, resolveTypealias: Bool = true, unknownTypealiasFallback: StatementType = .classDeclaration) -> (type: StatementType, isInModule: Bool)? {
            guard type.isNamedType else {
                return nil
            }
            if !resolveTypealias {
                let members = ranked(global.lookup(name: type.name, qualifiedMatch: true))
                guard let match = members.first(where: { ($0 is TypeInfo || $0 is TypealiasInfo) }) else {
                    return nil
                }
                return (match.declarationType, match.moduleName == global.moduleName)
            }
            guard let typeInfo = primaryTypeInfo(forNamed: type) else {
                guard let typealiasInfo = crossPlatformTypealias(forUnknownNamed: type) else {
                    return nil
                }
                return (unknownTypealiasFallback, typealiasInfo.moduleName == global.moduleName)
            }
            return (typeInfo.declarationType, typeInfo.moduleName == global.moduleName)
        }

        /// Resolve typealiases in the given type.
        func resolveTypealias(for type: TypeSignature) -> TypeSignature {
            return resolveTypealias(for: type, moduleName: nil, recursionDepth: 0)
        }

        private func resolveTypealias(for type: TypeSignature, moduleName: String?, recursionDepth: Int) -> TypeSignature {
            // Invalid Swift code containing circular typealiases can cause infinite recursion
            guard recursionDepth < 10 else {
                return type
            }
            let key = ContextTypealiasKey(type: type, moduleName: moduleName)
            if let cached = cache.typealiases?[key] {
                return cached
            }
            let ret = type.mappingTypes {
                switch $0 {
                case .named, .member:
                    if let info = ranked(global.lookup(name: $0.name, moduleName: moduleName, qualifiedMatch: true)).first(where: { $0.declarationType == .typealiasDeclaration }) as? TypealiasInfo {
                        let typealiasSignature = TypeSignature.Typealias(from: info.signature, to: info.targetSignature)
                        var aliasedSignature: TypeSignature = .typealiased(typealiasSignature, info.targetSignature)
                        if !$0.generics.isEmpty {
                            aliasedSignature = aliasedSignature.withGenerics($0.generics)
                        }
                        return resolveTypealias(for: aliasedSignature, moduleName: nil, recursionDepth: recursionDepth + 1)
                    }
                    if let moduleName {
                        return $0.withModuleName(moduleName)
                    } else {
                        return $0
                    }
                case .module(let moduleName, let type):
                    return resolveTypealias(for: type, moduleName: moduleName, recursionDepth: recursionDepth)
                case .typealiased(let alias, let type):
                    return resolveTypealias(for: type, moduleName: nil, recursionDepth: recursionDepth).asTypealiased(alias)
                default:
                    break
                }
                return nil
            }
            cache.typealiases?[key] = ret
            return ret
        }

        /// Cross platform library code may create typealiases to unknown types. Return any typealias for the given unknown type.
        func crossPlatformTypealias(forUnknownNamed type: TypeSignature) -> CodebaseInfo.TypealiasInfo? {
            if let typealiasSignature = type.typealiased {
                return crossPlatformTypealias(forUnknownNamed: typealiasSignature.from)
            } else {
                let members = ranked(global.lookup(name: type.name, qualifiedMatch: true))
                return members.first(where: { $0.declarationType == .typealiasDeclaration }) as? TypealiasInfo
            }
        }

        /// Return API information for the given identifier.
        func matchIdentifier(name: String, moduleName: String? = nil) -> APIMatch? {
            let key = ContextMatchKey(name: name, moduleName: moduleName)
            if let cached = cache.matches?[key] {
                return cached.first
            }

            let lookup = global.lookup(name: name, moduleName: moduleName, qualifiedMatch: true)
            let candidates = ranked(lookup).filter { candidate in
                switch candidate.declarationType {
                case .actorDeclaration, .classDeclaration, .enumDeclaration, .protocolDeclaration, .structDeclaration, .typealiasDeclaration, .enumCaseDeclaration, .variableDeclaration, .functionDeclaration:
                    return true
                default:
                    return false
                }
            }
            let topRanked = candidates.first { $0.declarationType != .functionDeclaration } ?? candidates.first
            guard let topRanked else {
                let type = moduleName == nil || moduleName == "Swift" ? TypeSignature.for(name: name, genericTypes: [], allowNamed: false).asMetaType(true) : .none
                let apiMatch = type == .none ? nil : APIMatch(signature: type)
                cache.matches?[key] = apiMatch == nil ? [] : [apiMatch!]
                return apiMatch
            }
            var matchSignature = topRanked.signature
            if let generics = (topRanked as? TypeInfo)?.generics ?? (topRanked as? TypealiasInfo)?.generics {
                matchSignature = matchSignature.constrainedTypeWithGenerics(generics)
            }
            var match = topRanked.apiMatch
            match.signature = matchSignature.asMetaType(topRanked.declarationType != .variableDeclaration && topRanked.declarationType != .enumCaseDeclaration && topRanked.declarationType != .functionDeclaration)
            cache.matches?[key] = [match]
            return match
        }
        
        /// Return API information for the given member.
        ///
        /// - Note: Assumes that the constrained `type` has been resolved.
        func matchIdentifier(name: String, inConstrained type: TypeSignature, excludeConstrainedExtensions: Bool = false) -> APIMatch? {
            var type = type.asTypealiased(nil).asOptional(false).withExistentialMode(.none)
            if case .tuple(let labels, let types) = type {
                for (index, label) in labels.enumerated() {
                    if name == label || name == "\(index)" {
                        return APIMatch(signature: types[index])
                    }
                }
                return nil
            } else if case .module(let module, .none) = type {
                return matchIdentifier(name: name, moduleName: module)
            }

            let key = ContextMatchKey(name: name, inConstrained: type, excludeConstrainedGenerics: excludeConstrainedExtensions)
            if let cached = cache.matches?[key] {
                return cached.first
            }
            let isStatic = type.isMetaType
            type = type.asMetaType(false)

            let typeInfos = typeInfos(forNamed: type)
            let primaryTypeInfo = typeInfos.first { $0.declarationType != .extensionDeclaration }
            // We intentionally exclude extensions to unknown named types
            if primaryTypeInfo != nil || !type.isNamedType {
                if var match = matchIdentifier(name: name, in: type, primaryTypeInfo: primaryTypeInfo, typeInfos: typeInfos, isStatic: isStatic, excludeConstrainedExtensions: excludeConstrainedExtensions, functionMatch: false) ?? matchIdentifier(name: name, in: type, primaryTypeInfo: primaryTypeInfo, typeInfos: typeInfos, isStatic: isStatic, excludeConstrainedExtensions: excludeConstrainedExtensions, functionMatch: true) {
                    match.signature = match.signature.mappingSelf(to: type)
                    cache.matches?[key] = [match]
                    return match
                }
            }

            let ret: APIMatch?
            if let match = matchIdentifier(name: type.name + "." + name) {
                // Is this a nested type name?
                ret = match
            } else if case .named(let moduleName, []) = type {
                // Is it a module name?
                ret = matchIdentifier(name: name, moduleName: moduleName)
            } else {
                ret = nil
            }
            cache.matches?[key] = ret == nil ? [] : [ret!]
            return ret
        }

        /// Return API information for the possible functions being called with the given arguments.
        func matchFunction(name: String, moduleName: String? = nil, arguments: [LabeledValue<ArgumentValue>]) -> [APIMatch] {
            let key = ContextMatchKey(name: name, moduleName: moduleName, arguments: arguments)
            if let cached = cache.matches?[key] {
                return cached
            }
            let candidates = Self.dedupe(functionCandidates(name: name, moduleName: moduleName, arguments: arguments)).sorted { $0.score > $1.score }
            let ret: [APIMatch]
            if let topCandidate = candidates.first {
                ret = candidates.filter { $0.score >= topCandidate.score }.map(\.match)
            } else {
                ret = []
            }
            cache.matches?[key] = ret
            return ret
        }

        /// Return the signatures of the possible member functions being called with the given arguments.
        ///
        /// This function also works for the creation of an enum case with associated values.
        ///
        /// - Note: Assumes that the constrained `type` has been resolved.
        func matchFunction(name: String?, inConstrained type: TypeSignature, arguments: [LabeledValue<ArgumentValue>], excludeConstrainedExtensions: Bool = false) -> [APIMatch] {
            let type = type.asOptional(false).withExistentialMode(.none)
            if case .tuple(let labels, let types) = type.asTypealiased(nil) {
                for (index, label) in labels.enumerated() {
                    if name == label || name == "\(index)" {
                        let function = matchTuple(types[index], arguments: arguments)
                        return [APIMatch(signature: function)]
                    }
                }
                return []
            } else if case .module(let module, .none) = type {
                guard let name else {
                    return []
                }
                return matchFunction(name: name, moduleName: module, arguments: arguments)
            }

            let key = ContextMatchKey(name: name ?? "init", inConstrained: type, arguments: arguments, excludeConstrainedGenerics: excludeConstrainedExtensions)
            if let cached = cache.matches?[key] {
                return cached
            }

            let candidates = Self.dedupe(functionCandidates(name: name, in: type, constrainedGenerics: type.generics, arguments: arguments, excludeConstrainedExtensions: excludeConstrainedExtensions))
            let sortedCandidates = candidates.sorted { $0.score > $1.score || ($0.score == $1.score && $0.level < $1.level) }
            let ret: [APIMatch]
            if let topCandidate = sortedCandidates.first {
                ret = sortedCandidates.filter { $0.score >= topCandidate.score && $0.level <= topCandidate.level }.map {
                    var match = $0.match
                    match.signature = match.signature.mappingSelf(to: type)
                    return match
                }
            } else {
                if let name, case .named(let moduleName, []) = type {
                    // Is type a module name?
                    ret = matchFunction(name: name, moduleName: moduleName, arguments: arguments)
                } else {
                    ret = []
                }
            }
            cache.matches?[key] = ret
            return ret
        }

        /// If the given function signature can be called with the given arguments, return the call signature.
        func callableSignature(of functionSignature: TypeSignature, generics: Generics? = nil, arguments: [LabeledValue<ArgumentValue>]) -> TypeSignature? {
            return matchFunction(signature: functionSignature, generics: generics, declarationType: .functionDeclaration, availability: .available, arguments: arguments, level: 0)?.match.signature
        }
        
        /// Return the signatures of the possible subscripts being called with the given arguments.
        ///
        /// - Note: Assumes that the constrained `type` has been resolved.
        func matchSubscript(inConstrained type: TypeSignature, arguments: [LabeledValue<ArgumentValue>]) -> [APIMatch] {
            var type = type.asTypealiased(nil).asOptional(false)
            if case .array(let elementType) = type, let elementType, arguments.count == 1 {
                if case .range = arguments[0].value.type {
                    // Slice - fall through to symbols
                } else {
                    let signature: TypeSignature = .function([TypeSignature.Parameter(type: .int)], elementType.mappingSelf(to: type), APIFlags(), nil)
                    return [APIMatch(signature: signature, memberOf: (type, nil))]
                }
            } else if case .dictionary(let keyType, let valueType) = type, let keyType, let valueType, arguments.count == 1 {
                let signature: TypeSignature = .function([TypeSignature.Parameter(type: keyType)], valueType.mappingSelf(to: type).asOptional(true), APIFlags(), nil)
                return [APIMatch(signature: signature, memberOf: (type, nil))]
            }
            let isStatic = type.isMetaType
            type = type.asMetaType(false)

            var candidates: Set<FunctionCandidate> = []
            for typeInfo in typeInfos(forNamed: type) {
                subscriptCandidates(in: typeInfo, constrainedGenerics: type.generics, arguments: arguments, isStatic: isStatic).forEach { candidates.insert($0) }
            }
            let sortedCandidates = candidates.sorted { $0.score > $1.score || ($0.score == $1.score && $0.level < $1.level) }
            guard let topCandidate = sortedCandidates.first else {
                return []
            }
            return sortedCandidates.filter { $0.score >= topCandidate.score && $0.level <= topCandidate.level }.map(\.match)
        }
        
        /// Return the associated values of the given enum case.
        func associatedValueSignatures(of member: String, inConstrained type: TypeSignature) -> [TypeSignature.Parameter] {
            for typeInfo in typeInfos(forNamed: type) {
                if let types = associatedValueSignatures(of: member, in: typeInfo, constrainedGenerics: type.generics) {
                    return types
                }
            }
            return []
        }

        private func matchIdentifier(name: String, in typeInfo: TypeInfo, constrainedGenerics: [TypeSignature], isStatic: Bool) -> APIMatch? {
            guard typeInfo.isApplicable(toConstrainedGenerics: constrainedGenerics, codebaseInfo: self) else {
                return nil
            }
            // Prefer non-function identifier matches, then function matches
            if let match = matchIdentifier(name: name, in: typeInfo, constrainedGenerics: constrainedGenerics, isStatic: isStatic, functionMatch: false) {
                return match
            } else {
                return matchIdentifier(name: name, in: typeInfo, constrainedGenerics: constrainedGenerics, isStatic: isStatic, functionMatch: true)
            }
        }

        private func matchIdentifier(name: String, in type: TypeSignature, primaryTypeInfo: TypeInfo?, typeInfos: [TypeInfo], isStatic: Bool, excludeConstrainedExtensions: Bool, functionMatch: Bool) -> APIMatch? {
            for typeInfo in typeInfos {
                if excludeConstrainedExtensions && typeInfo.declarationType == .extensionDeclaration && typeInfo.generics != primaryTypeInfo?.generics {
                    continue
                }
                if let match = matchIdentifier(name: name, in: typeInfo, constrainedGenerics: type.generics, isStatic: isStatic, functionMatch: functionMatch) {
                    return match
                }
            }
            return nil
        }

        private func matchIdentifier(name: String, in typeInfo: TypeInfo, constrainedGenerics: [TypeSignature], isStatic: Bool, functionMatch: Bool) -> APIMatch? {
            // We allow .init to be used both as a static or instance member
            if let memberInfo = visibleMembers(of: typeInfo).first(where: { $0.name == name
                && ($0.declarationType == .initDeclaration || $0.isStatic == isStatic)
                && functionMatch == ($0.declarationType == .functionDeclaration) }) {
                let availability = memberInfo.availability.least(typeInfo.availability)
                // Enum cases with associated values are modeled as functions, but can also be used as identifiers
                let signature: TypeSignature
                if memberInfo.declarationType == .enumCaseDeclaration {
                    signature = typeInfo.signature.mappingTypes(from: typeInfo.signature.generics, to: constrainedGenerics)
                } else if memberInfo is TypeInfo || memberInfo.declarationType == .typealiasDeclaration {
                    signature = memberInfo.signature.mappingTypes(from: typeInfo.signature.generics, to: constrainedGenerics).asMetaType(true)
                } else {
                    signature = memberInfo.signature.mappingTypes(from: typeInfo.signature.generics, to: constrainedGenerics)
                }
                var match = memberInfo.apiMatch
                match.signature = signature
                match.availability = availability
                if let memberOf = match.memberOf, let selfType = typeInfo.generics.selfType {
                    match.memberOf = (memberOf.declaringType, selfType)
                }
                return match
            }
            for inherits in typeInfo.inherits {
                for inheritsInfo in typeInfos(forNamed: inherits) {
                    let inheritsConstraints = inherits.mappingTypes(from: typeInfo.signature.generics, to: constrainedGenerics).generics
                    if let match = matchIdentifier(name: name, in: inheritsInfo, constrainedGenerics: inheritsConstraints, isStatic: isStatic, functionMatch: functionMatch) {
                        return match
                    }
                }
            }
            return nil
        }

        /// - Note: Returns unsorted, un-deduped results.
        private func functionCandidates(name: String, moduleName: String?, constrainedGenerics: [TypeSignature] = [], arguments: [LabeledValue<ArgumentValue>], includeTypes: Bool = true) -> [FunctionCandidate] {
            let lookup = global.lookup(name: name, moduleName: moduleName, qualifiedMatch: true)
            let items = ranked(lookup)
            let funcs = items.filter { $0.declarationType == .functionDeclaration }
            let funcsCandidates = funcs.compactMap { matchFunction($0, constrainedGenerics: constrainedGenerics, arguments: arguments, level: 0) }
            guard includeTypes else {
                return funcsCandidates
            }

            let typeInfos = items.flatMap { (item) -> [TypeInfo] in
                if let typeInfo = item as? TypeInfo {
                    return [typeInfo]
                } else if let typealiasInfo = item as? TypealiasInfo {
                    return self.typeInfos(forNamed: typealiasInfo.signature)
                } else {
                    return []
                }
            }
            let initsCandidates = initCandidates(for: typeInfos, constrainedGenerics: constrainedGenerics, arguments: arguments)
            return funcsCandidates + initsCandidates
        }

        /// - Note: Returns unsorted, un-deduped results.
        private func functionCandidates(name: String?, in type: TypeSignature, constrainedGenerics: [TypeSignature], arguments: [LabeledValue<ArgumentValue>], excludeConstrainedExtensions: Bool) -> [FunctionCandidate] {
            let isStatic = type.isMetaType
            let type = type.asMetaType(false)

            var candidates: [FunctionCandidate] = []
            let typeInfos = typeInfos(forNamed: type)
            let primaryTypeInfo = typeInfos.first { $0.declarationType != .extensionDeclaration }
            if name == nil || name == "init" {
                candidates += initCandidates(for: typeInfos, in: primaryTypeInfo, constrainedGenerics: constrainedGenerics, arguments: arguments)
                if name == nil {
                    // Look for free functions that match the type name
                    candidates += typeNameFunctionCandidates(for: type, constrainedGenerics: constrainedGenerics, arguments: arguments, excludeConstrainedExtensions: excludeConstrainedExtensions)
                }
                // If this is a typealias to an unknown type with no matching named functions, assume it's
                // a constructor of the unknown type
                if candidates.isEmpty, let typealiasSignature = type.typealiased {
                    candidates.append(syntheticInitCandidate(for: typealiasSignature.to, arguments: arguments))
                }
            } else if let name {
                for typeInfo in typeInfos {
                    if excludeConstrainedExtensions && typeInfo.declarationType == .extensionDeclaration && typeInfo.generics != primaryTypeInfo?.generics {
                        // We intentionally leave out cases where primaryTypeInfo is unknown so that extensions to unknown types are excluded
                        continue
                    }
                    candidates += functionCandidates(name: name, in: typeInfo, constrainedGenerics: constrainedGenerics, arguments: arguments, isStatic: isStatic)
                }
            }
            return candidates
        }

        /// - Note: Returns unsorted, un-deduped results.
        private func functionCandidates(name: String, in typeInfo: TypeInfo, constrainedGenerics: [TypeSignature], arguments: [LabeledValue<ArgumentValue>], isStatic: Bool, level: Int = 0) -> [FunctionCandidate] {
            guard typeInfo.isApplicable(toConstrainedGenerics: constrainedGenerics, codebaseInfo: self) else {
                return []
            }
            var candidates = visibleMembers(of: typeInfo).flatMap { (member) -> [FunctionCandidate] in
                // We allow .init to be used both as a static or instance member
                guard member.name == name && (member.declarationType == .initDeclaration || member.isStatic == isStatic) else {
                    return []
                }
                switch member.declarationType {
                case .actorDeclaration, .classDeclaration, .enumDeclaration, .extensionDeclaration, .structDeclaration, .typealiasDeclaration:
                    return initCandidates(for: typeInfos(forNamed: member.signature), in: typeInfo, constrainedGenerics: constrainedGenerics, arguments: arguments)
                case .functionDeclaration, .initDeclaration, .enumCaseDeclaration:
                    if let candidate = matchFunction(member, in: typeInfo, constrainedGenerics: constrainedGenerics, arguments: arguments, level: level) {
                        return [candidate]
                    } else {
                        return []
                    }
                default:
                    return []
                }
            }
            for inherits in typeInfo.inherits {
                for inheritsInfo in typeInfos(forNamed: inherits) {
                    let inheritsConstraints = inherits.mappingTypes(from: typeInfo.signature.generics, to: constrainedGenerics).generics
                    candidates += functionCandidates(name: name, in: inheritsInfo, constrainedGenerics: inheritsConstraints, arguments: arguments, isStatic: isStatic, level: level + 1)
                }
            }
            return candidates
        }

        /// - Note: Returns unsorted, un-deduped results.
        private func subscriptCandidates(in typeInfo: TypeInfo, constrainedGenerics: [TypeSignature], arguments: [LabeledValue<ArgumentValue>], isStatic: Bool, level: Int = 0) -> [FunctionCandidate] {
            guard typeInfo.isApplicable(toConstrainedGenerics: constrainedGenerics, codebaseInfo: self) else {
                return []
            }
            var candidates = visibleMembers(of: typeInfo).compactMap { (member) -> FunctionCandidate? in
                guard member.declarationType == .subscriptDeclaration && member.isStatic == isStatic else {
                    return nil
                }
                if let candidate = matchFunction(member, in: typeInfo, constrainedGenerics: constrainedGenerics, arguments: arguments, level: level) {
                    return candidate
                } else {
                    return nil
                }
            }
            for inherits in typeInfo.inherits {
                for inheritsInfo in typeInfos(forNamed: inherits) {
                    let inheritsConstraints = inherits.mappingTypes(from: typeInfo.signature.generics, to: constrainedGenerics).generics
                    candidates += subscriptCandidates(in: inheritsInfo, constrainedGenerics: inheritsConstraints, arguments: arguments, isStatic: isStatic, level: level + 1)
                }
            }
            return candidates
        }

        /// - Note: Returns unsorted, un-deduped results.
        private func initCandidates(for typeInfos: [TypeInfo], in contextTypeInfo: TypeInfo? = nil, constrainedGenerics: [TypeSignature] = [], arguments: [LabeledValue<ArgumentValue>]) -> [FunctionCandidate] {
            guard let primaryTypeInfo = typeInfos.first(where: { $0.declarationType != .extensionDeclaration }) else {
                return []
            }
            // Transfer any contextual generic information to this member type
            let typeInfoConstrainedGenerics: [TypeSignature]
            if contextTypeInfo?.signature == primaryTypeInfo.signature {
                typeInfoConstrainedGenerics = constrainedGenerics
            } else {
                var typeInfoGenerics = primaryTypeInfo.generics
                if let contextTypeInfo {
                    typeInfoGenerics = typeInfoGenerics.merge(overrides: Generics(contextTypeInfo.signature.generics, whereEqual: constrainedGenerics))
                }
                typeInfoConstrainedGenerics = typeInfoGenerics.entries.map { $0.constrainedType(fallback: .any) }
            }
            var initSignatures = typeInfos.flatMap { typeInfo in
                let initInfos = visibleMembers(of: typeInfo).filter { $0.declarationType == .initDeclaration }
                return initInfos.compactMap { (initInfo: CodebaseInfoItem) -> FunctionCandidate? in
                    return matchFunction(initInfo, in: typeInfo, constrainedGenerics: typeInfoConstrainedGenerics, arguments: arguments, level: 0)
                }
            }
            
            // If we don't have any matches and this appears to be a constructor, treat it as one. We take advantage of this
            // while inferring the types of variable values in prepareForUse(), before we've called generateConstructors()
            if initSignatures.isEmpty {
                initSignatures.append(syntheticInitCandidate(for: primaryTypeInfo.signature, arguments: arguments, apiFlags: primaryTypeInfo.apiFlags ?? APIFlags(), availability: primaryTypeInfo.availability))
            }
            return initSignatures
        }

        private func syntheticInitCandidate(for type: TypeSignature, arguments: [LabeledValue<ArgumentValue>], apiFlags: APIFlags = APIFlags(), availability: Availability = .available) -> FunctionCandidate {
            let initParameters = arguments.map { TypeSignature.Parameter(label: $0.label, type: $0.value.type) }
            let match = APIMatch(signature: .function(initParameters, type, apiFlags, nil), apiFlags: apiFlags, declarationType: .initDeclaration, memberOf: (type, nil), availability: availability)
            return FunctionCandidate(match: match, score: 0.0, level: 0)
        }

        /// - Note: Returns unsorted results.
        private func typeNameFunctionCandidates(for type: TypeSignature, moduleName: String? = nil, constrainedGenerics: [TypeSignature], arguments: [LabeledValue<ArgumentValue>], excludeConstrainedExtensions: Bool) -> [FunctionCandidate] {
            switch type.withoutOptionality().withExistentialMode(.none) {
            case .member(let baseType, let type):
                return functionCandidates(name: type.name, in: baseType.asMetaType(true), constrainedGenerics: constrainedGenerics, arguments: arguments, excludeConstrainedExtensions: excludeConstrainedExtensions)
            case .module(let moduleName, let type):
                return typeNameFunctionCandidates(for: type, moduleName: moduleName, constrainedGenerics: constrainedGenerics, arguments: arguments, excludeConstrainedExtensions: excludeConstrainedExtensions)
            case .typealiased(let alias, _):
                return typeNameFunctionCandidates(for: alias.from, constrainedGenerics: constrainedGenerics, arguments: arguments, excludeConstrainedExtensions: excludeConstrainedExtensions)
            default:
                // Is this a cast?
                if type.isNumeric && arguments.count == 1 && arguments[0].label == nil && arguments[0].value.type.isNumeric {
                    return [FunctionCandidate(match: APIMatch(signature: .function([.init(type: arguments[0].value.type)], type, APIFlags(), nil), apiFlags: APIFlags(), declarationType: .initDeclaration, memberOf: (type, nil), availability: .available), score: 1.0, level: 0)]
                }
                return functionCandidates(name: type.name, moduleName: moduleName, constrainedGenerics: constrainedGenerics, arguments: arguments, includeTypes: false)
            }
        }
        
        private func associatedValueSignatures(of member: String, in typeInfo: TypeInfo, constrainedGenerics: [TypeSignature]) -> [TypeSignature.Parameter]? {
            guard typeInfo.isApplicable(toConstrainedGenerics: constrainedGenerics, codebaseInfo: self) else {
                return nil
            }
            guard let memberInfo = visibleMembers(of: typeInfo).first(where: { $0.name == member && $0.declarationType == .enumCaseDeclaration }) else {
                return nil
            }
            guard case .function(let parameters, _, _, _) = memberInfo.signature else {
                return nil
            }
            return parameters.map { $0.mappingTypes(from: typeInfo.signature.generics, to: constrainedGenerics) }
        }

        private func matchTuple(_ signature: TypeSignature, arguments: [LabeledValue<ArgumentValue>]) -> TypeSignature {
            guard case .function(let parameterTypes, _, _, _) = signature, parameterTypes.count == arguments.count else {
                return .none
            }
            return signature
        }
        
        private func matchFunction(_ item: CodebaseInfoItem, in typeInfo: TypeInfo? = nil, constrainedGenerics: [TypeSignature] = [], arguments: [LabeledValue<ArgumentValue>], level: Int) -> FunctionCandidate? {
            let generics = (item as? FunctionInfo)?.generics
            return matchFunction(signature: item.signature, generics: generics, isStatic: item.isStatic, declarationType: item.declarationType, availability: item.availability, in: typeInfo, constrainedGenerics: constrainedGenerics, arguments: arguments, level: level)
        }

        private func matchFunction(signature: TypeSignature, generics: Generics? = nil, isStatic: Bool = false, declarationType: StatementType, availability: Availability, in typeInfo: TypeInfo? = nil, constrainedGenerics: [TypeSignature] = [], arguments: [LabeledValue<ArgumentValue>], level: Int) -> FunctionCandidate? {
            guard case .function(let parameters, let returnType, let apiFlags, let attributes) = signature else {
                return nil
            }
            if !parameters.contains(where: { $0.isVariadic }) {
                guard parameters.count >= arguments.count else {
                    return nil
                }
            }

            // Constrain the parameters using available generic information so that we can match against them
            var constrainedParameters = parameters
            var generics = generics ?? Generics()
            var availability = availability
            if let typeInfo {
                constrainedParameters = parameters.map {
                    $0.mappingTypes(from: typeInfo.signature.generics, to: constrainedGenerics)
                }
                generics = typeInfo.generics.merge(overrides: generics, addNew: true)
                generics = generics.merge(overrides: Generics(typeInfo.signature.generics, whereEqual: constrainedGenerics), addNew: true)
                availability = availability.least(typeInfo.availability)
            }
            constrainedParameters = constrainedParameters.map { $0.constrainedTypeWithGenerics(generics) }

            // Match each argument to a parameter
            let isSubscript = declarationType == .subscriptDeclaration
            var matchingParameters: [TypeSignature.Parameter] = []
            var matchingOriginalParameters: [TypeSignature.Parameter] = []
            var parameterIndex = 0
            var argumentIndex = 0
            var totalScore = 0.0
            while argumentIndex < arguments.count {
                guard let (matchingIndex, score) = matchArgument(at: argumentIndex, in: arguments, to: constrainedParameters, isSubscript: isSubscript, startIndex: parameterIndex) else {
                    return nil
                }
                // If the parameter type was constrained (i.e. is generic), the argument value will likely be more specific
                let argument = arguments[argumentIndex]
                let parameterType: TypeSignature
                if parameters[matchingIndex].type != constrainedParameters[matchingIndex].type && argument.value.type != .any {
                    parameterType = argument.value.type.or(constrainedParameters[matchingIndex].type)
                } else {
                    parameterType = constrainedParameters[matchingIndex].type.or(argument.value.type)
                }
                var matchingParameter = parameters[matchingIndex]
                matchingOriginalParameters.append(matchingParameter)
                matchingParameter.type = parameterType
                matchingParameters.append(matchingParameter)
                argumentIndex += 1
                // Greedily consume any variadic arguments
                if matchingParameter.isVariadic {
                    while argumentIndex < arguments.count {
                        if matchArgument(at: argumentIndex, in: arguments, isVariadicContinuation: true, to: constrainedParameters, isSubscript: isSubscript, startIndex: parameterIndex) != nil {
                            argumentIndex += 1
                            // Model variadic continuation arguments as additional unlabeled parameters
                            var continuationOriginalParameter = parameters[matchingIndex]
                            continuationOriginalParameter.isVariadicContinuation = true
                            var continuationParameter = matchingParameter
                            continuationParameter.isVariadicContinuation = true
                            matchingOriginalParameters.append(continuationOriginalParameter)
                            matchingParameters.append(continuationParameter)
                        } else {
                            break
                        }
                    }
                }
                parameterIndex = matchingIndex + 1
                totalScore += score
            }
            // Make sure there are no more required parameters
            if parameterIndex < parameters.count {
                if parameters[parameterIndex...].contains(where: { !$0.hasDefaultValue }) {
                    return nil
                }
            }

            // Apply the generic types we determined from parameter matching and the given constraint information to the original function,
            // using the result to fill in generic types in the return type and matching parameters
            let matchingOriginalSignature: TypeSignature = .function(matchingOriginalParameters, signature.returnType, apiFlags, attributes)
            let matchingParameterSignature: TypeSignature = .function(matchingParameters, returnType, apiFlags, attributes)
            let matchingGenerics = matchingOriginalSignature.mergeGenericMappings(in: matchingParameterSignature, with: generics)
            let mappedSignature = matchingOriginalSignature.constrainedTypeWithGenerics(matchingGenerics)
            let mappedParameters = mappedSignature.parameters
            for i in 0..<matchingParameters.count {
                matchingParameters[i] = matchingParameters[i].or(mappedParameters[i], replaceAny: true)
            }
            let memberOf: (TypeSignature, TypeSignature?)?
            if let signature = typeInfo?.signature {
                memberOf = (signature.asMetaType(isStatic), typeInfo?.generics.selfType?.asMetaType(isStatic))
            } else {
                memberOf = nil
            }
            let match = APIMatch(signature: .function(matchingParameters, mappedSignature.returnType, apiFlags, attributes), apiFlags: apiFlags, declarationType: declarationType, memberOf: memberOf, attributes: attributes, availability: availability)
            return FunctionCandidate(match: match, score: totalScore, level: level)
        }

        private func matchArgument(at argumentIndex: Int, in arguments: [LabeledValue<ArgumentValue>], isVariadicContinuation: Bool = false, to parameters: [TypeSignature.Parameter], isSubscript: Bool = false, startIndex: Int) -> (index: Int, score: Double)? {
            // Note: in the algorith below we give an extra point for matching a label (or absence of one), as opposed to
            // being a trailing closure that omits the label
            let argument = arguments[argumentIndex]
            for (index, parameter) in parameters[startIndex...].enumerated() {
                if let label = argument.label {
                    if isVariadicContinuation {
                        return nil
                    }
                    // If there is a label, then it either has to match or we have to be able to skip this parameter
                    if label == parameter.label, let score = argument.value.type.compatibilityScore(target: parameter.type, codebaseInfo: self, isLiteral: argument.value.isLiteral, isInterpolated: argument.value.isInterpolated) {
                        return (startIndex + index, 1.0 + score)
                    } else if !parameter.hasDefaultValue {
                        return nil
                    }
                } else {
                    // If there is no label, then either this parameter has to have no label, be a variadic continuation, or be a trailing closure.
                    // We don't give the extra point for a nil label on a function parameter to avoid advantaging trailing closures on nil-labeled
                    // params over other trailing closures
                    if (isVariadicContinuation || (parameter.label == nil && !argument.value.isFirstTrailingClosure) || isSubscript), let score = argument.value.type.compatibilityScore(target: parameter.type, codebaseInfo: self, isLiteral: argument.value.isLiteral, isInterpolated: argument.value.isInterpolated) {
                        return (startIndex + index, 1.0 + score)
                    } else if argument.value.isFirstTrailingClosure, let score = argument.value.type.compatibilityScore(target: parameter.type, codebaseInfo: self, isLiteral: argument.value.isLiteral, isInterpolated: argument.value.isInterpolated) {
                        if argumentIndex == arguments.count - 1 && startIndex + index < parameters.count - 1 && parameter.hasDefaultValue && parameters[(startIndex + index + 1)...].contains(where: { !$0.hasDefaultValue }) {
                            // If this trailing closure is the last supplied argument, save it for the next required parameter
                            // even if it matches this defaulted parameter. Handles the case of a defaulted closure parameter
                            // followed by a required closure parameter
                        } else {
                            return (startIndex + index, score)
                        }
                    } else if !parameter.hasDefaultValue {
                        return nil
                    }
                }
            }
            return nil
        }

        // Maintain order rather than dumping in a Set for consistent output
        static func dedupe<T: Hashable>(_ array: [T]) -> [T] {
            if array.count <= 1 {
                return array
            }
            var uniqueElements = Set<T>()
            var result = [T]()
            for element in array {
                if uniqueElements.insert(element).inserted {
                    result.append(element)
                }
            }
            return result
        }
    }

    /// Reference-type cache so that we can mutate it within a `Context` struct.
    fileprivate final class ContextCache {
        var primaryTypeInfos: [TypeSignature: TypeInfo]?
        var typealiases: [ContextTypealiasKey: TypeSignature]?
        var visibleMembers: [TypeInfo: [CodebaseInfoItem]]?
        var matches: [ContextMatchKey: [APIMatch]]?

        init(primaryTypeInfos: [TypeSignature: TypeInfo]? = [:], typealiases: [ContextTypealiasKey: TypeSignature]? = [:], visibleMembers: [TypeInfo: [CodebaseInfoItem]]? = [:], matches: [ContextMatchKey: [APIMatch]]? = [:]) {
            self.primaryTypeInfos = primaryTypeInfos
            self.typealiases = typealiases
            self.visibleMembers = visibleMembers
            self.matches = matches
        }
    }

    fileprivate struct ContextMatchKey: Hashable {
        let name: String
        let moduleName: String?
        let inConstrained: TypeSignature?
        let arguments: [LabeledValue<ArgumentValue>]?
        let excludeConstrainedExtensions: Bool

        init(name: String, moduleName: String? = nil, inConstrained: TypeSignature? = nil, arguments: [LabeledValue<ArgumentValue>]? = nil, excludeConstrainedGenerics: Bool = false) {
            self.name = name
            self.moduleName = moduleName
            self.inConstrained = inConstrained
            self.arguments = arguments
            self.excludeConstrainedExtensions = excludeConstrainedGenerics
        }
    }

    fileprivate struct ContextTypealiasKey: Hashable {
        let type: TypeSignature
        let moduleName: String?
    }

    private func candidateTypeNames(for type: TypeSignature) -> [(String, String?)] {
        switch type {
        case .array:
            return [("Array", nil)]
        case .composition(let types):
            return types.flatMap { candidateTypeNames(for: $0) }
        case .dictionary:
            return [("Dictionary", nil)]
        case .existential(_, let type):
            return candidateTypeNames(for: type)
        case .function:
            return []
        case .member(let base, let member):
            let typeNames = candidateTypeNames(for: member)
            let baseName = base.name
            return typeNames.map { ("\(baseName).\($0.0)", nil as String?) }
        case .metaType(let type):
            return candidateTypeNames(for: type)
        case .module(let moduleName, let type):
            return candidateTypeNames(for: type).map { ($0.0, moduleName) }
        case .named(let name, _):
            return [(name, nil)]
        case .none:
            return []
        case .optional(let type):
            return candidateTypeNames(for: type)
        case .set:
            return [("Set", nil)]
        case .typealiased(_, let type):
            return candidateTypeNames(for: type)
        case .unwrappedOptional(let type):
            return candidateTypeNames(for: type)
        case .void:
            return []
        default:
            return [(type.name, nil)]
        }
    }

    private struct FunctionCandidate: Hashable {
        var match: APIMatch
        var score: Double
        var level: Int

        static func ==(lhs: FunctionCandidate, rhs: FunctionCandidate) -> Bool {
            return lhs.match.signature == rhs.match.signature
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(match.signature)
        }
    }
    
    private(set) var rootTypes: [TypeInfo] = []
    private(set) var rootTypealiases: [TypealiasInfo] = []
    private(set) var rootVariables: [VariableInfo] = []
    private(set) var rootFunctions: [FunctionInfo] = []
    private(set) var rootExtensions: [TypeInfo] = []
    private var itemsByName: [String: [CodebaseInfoItem]] = [:]
    private var messages: [Source.FilePath: [Message]] = [:]
    private var isInUse = false
    private var typeInferenceTrees: [Source.FilePath: SyntaxTree] = [:]
    
    private func buildItemsByName() {
        var itemsByName: [String: [CodebaseInfoItem]] = [:]
        rootTypes.forEach { Self.addTypeInfo($0, to: &itemsByName) }
        rootExtensions.forEach { Self.addTypeInfo($0, to: &itemsByName) }
        rootTypealiases.forEach { Self.addItem($0, to: &itemsByName) }
        rootVariables.forEach { Self.addItem($0, to: &itemsByName) }
        rootFunctions.forEach { Self.addItem($0, to: &itemsByName) }
        dependentModules.forEach { Self.addModuleExport($0, to: &itemsByName) }
        self.itemsByName = itemsByName
    }
    
    private static func addModuleExport(_ export: ModuleExport, to itemsByName: inout [String: [CodebaseInfoItem]]) {
        export.rootTypes.forEach { Self.addTypeInfo($0, to: &itemsByName) }
        export.rootExtensions.forEach { Self.addTypeInfo($0, to: &itemsByName) }
        export.rootTypealiases.forEach { Self.addItem($0, to: &itemsByName) }
        export.rootVariables.forEach { Self.addItem($0, to: &itemsByName) }
        export.rootFunctions.forEach { Self.addItem($0, to: &itemsByName) }
    }
    
    fileprivate static func addTypeInfo(_ typeInfo: TypeInfo, to itemsByName: inout [String: [CodebaseInfoItem]]) {
        addItem(typeInfo, to: &itemsByName) // Already filtered
        typeInfo.types.forEach { addTypeInfo($0, to: &itemsByName) }
        typeInfo.typealiases.forEach { addItem($0, to: &itemsByName) }
        typeInfo.cases.forEach { addItem($0, to: &itemsByName) }
        typeInfo.variables.forEach { addItem($0, to: &itemsByName) }
        typeInfo.functions.forEach { addItem($0, to: &itemsByName) }
    }
    
    fileprivate static func addItem(_ item: CodebaseInfoItem, to itemsByName: inout [String: [CodebaseInfoItem]]) {
        var itemsWithName = itemsByName[item.name, default: []]
        itemsWithName.append(item)
        itemsByName[item.name] = itemsWithName
    }

    private func fixupGenericsInfo() {
        // Update protocol info to add any generics to inherited protocols and collect their generic info in the generics object
        var fixedupProtocolNames: Set<String> = []
        for protocolInfo in rootTypes where protocolInfo.declarationType == .protocolDeclaration {
            fixupProtocolGenericsInfo(protocolInfo, fixedupProtocolNames: &fixedupProtocolNames)
        }
        // Update extension info so that extensions have the same signature as the extended type, moving any generic info to the generics object
        for extensionInfo in rootExtensions {
            guard let primaryInfo = primaryTypeInfo(forNamed: extensionInfo.signature) else {
                continue
            }
            extensionInfo.generics = primaryInfo.generics.merge(extension: extensionInfo.signature, generics: extensionInfo.generics)
            extensionInfo.signature = primaryInfo.signature
        }
        // Update concrete types' inherits lists to include the generic types used for each implemented protocol
        for typeInfo in rootTypes where typeInfo.declarationType != .protocolDeclaration {
            fixupProtocolConformanceGenerics(in: typeInfo)
        }
        rootExtensions.forEach { fixupProtocolConformanceGenerics(in: $0) }
    }

    private func fixupProtocolGenericsInfo(_ protocolInfo: TypeInfo, fixedupProtocolNames: inout Set<String>) {
        guard fixedupProtocolNames.insert(protocolInfo.signature.name).inserted else {
            return
        }
        var protocolGenerics = Generics()
        protocolInfo.inherits = protocolInfo.inherits.map { inherit in
            guard let inheritInfo = primaryTypeInfo(forNamed: inherit) else {
                return inherit
            }
            fixupProtocolGenericsInfo(inheritInfo, fixedupProtocolNames: &fixedupProtocolNames)
            guard !inheritInfo.generics.isEmpty else {
                return inherit
            }
            let conformanceMappings = protocolGenericsMappings(for: inheritInfo, in: protocolInfo)
            var inheritGenerics = inheritInfo.generics
            for (i, generic) in inheritGenerics.entries.enumerated() {
                if let mapping = conformanceMappings.first(where: { $0.0 == generic.namedType }), let whereEqual = mapping.1 {
                    inheritGenerics.entries[i].whereEqual = whereEqual
                }
            }
            protocolGenerics = protocolGenerics.merge(overrides: inheritGenerics, addNew: true)
            inheritGenerics = inheritGenerics.merge(overrides: protocolInfo.generics)
            return inherit.withGenerics(inheritGenerics.entries.map { $0.constrainedType(ifEqual: true) })
        }
        protocolInfo.generics = protocolGenerics.merge(overrides: protocolInfo.generics, addNew: true).filterWhereEqual()
        protocolInfo.signature = protocolInfo.signature.withGenerics(protocolInfo.generics.entries.map(\.namedType))
    }

    private func fixupProtocolConformanceGenerics(in typeInfo: TypeInfo) {
        typeInfo.inherits = typeInfo.inherits.map { inherit in
            guard let inheritInfo = primaryTypeInfo(forNamed: inherit), inheritInfo.declarationType == .protocolDeclaration, !inheritInfo.generics.isEmpty else {
                return inherit
            }
            let mappings = protocolGenericsMappings(for: inheritInfo, in: typeInfo)
            return inherit.withGenerics(mappings.map { $0.1 ?? $0.0 })
        }
        for member in typeInfo.members {
            if let memberTypeInfo = member as? TypeInfo {
                fixupProtocolConformanceGenerics(in: memberTypeInfo)
            }
        }
    }

    private func protocolGenericsMappings(for protocolInfo: TypeInfo, in typeInfo: TypeInfo) -> [(TypeSignature, TypeSignature?)] {
        var mappings: [TypeSignature: TypeSignature] = [:]
        let keys = Set(protocolInfo.signature.generics)
        for typealiasInfo in typeInfo.typealiases {
            let generic: TypeSignature = .named(typealiasInfo.name, [])
            if keys.contains(generic) {
                mappings[generic] = typealiasInfo.targetSignature
            }
        }
        var hasIDMember = false
        if mappings.count < keys.count {
            // Use the type's members to collect generic mappings
            var generics = Generics(keys.filter { !mappings.keys.contains($0) })
            for protocolInfo in protocolSignatures(forNamed: protocolInfo.signature).compactMap({ primaryTypeInfo(forNamed: $0) }) {
                for protocolMember in protocolInfo.members {
                    if let typeMember = findImplementingMember(in: typeInfo, for: protocolMember, searchExtensions: typeInfo.declarationType != .protocolDeclaration) {
                        generics = protocolMember.signature.mergeGenericMappings(in: typeMember.signature, with: generics)
                        hasIDMember = hasIDMember || protocolMember.declarationType == .variableDeclaration && protocolMember.name == "id"
                    }
                }
            }
            for entry in generics.entries {
                if let whereEqual = entry.whereEqual {
                    mappings[entry.namedType] = whereEqual
                }
            }
            // Identifiable has an extension to allow any class to auto-conform with ObjectIdentifier. We track whether
            // or not we found an "id" member explicitly just in case the user has her own `ID` type
            if !hasIDMember && typeInfo.declarationType != .protocolDeclaration && protocolInfo.signature.isNamed("Identifiable", moduleName: "Swift") {
                let idGeneric = TypeSignature.named("ID", [])
                if !mappings.keys.contains(idGeneric) {
                    mappings[idGeneric] = .named("ObjectIdentifier", [])
                }
            }
        }
        return protocolInfo.generics.entries.map {
            let namedType = $0.namedType
            return (namedType, mappings[namedType])
        }
    }

    private func findImplementingMember(in typeInfo: TypeInfo, for protocolMember: CodebaseInfoItem, searchExtensions: Bool) -> CodebaseInfoItem? {
        if let variableInfo = protocolMember as? VariableInfo {
            if let member = typeInfo.variables.first(where: { $0.name == variableInfo.name }) {
                return member
            }
        } else if let functionInfo = protocolMember as? FunctionInfo {
            let member = typeInfo.functions.first {
                guard functionInfo.name == $0.name else {
                    return false
                }
                return functionInfo.signature.parameters.map(\.label) == $0.signature.parameters.map(\.label)
            }
            if let member {
                return member
            }
        }
        if searchExtensions {
            for extensionInfo in typeInfos(forNamed: typeInfo.signature) {
                if extensionInfo !== typeInfo, let member = findImplementingMember(in: extensionInfo, for: protocolMember, searchExtensions: false) {
                    return member
                }
            }
        }
        return nil
    }

    private func inferVariableTypes() {
        guard !typeInferenceTrees.isEmpty else {
            return
        }
        // We don't need our trees after inferring types
        let typeInferenceTrees = self.typeInferenceTrees
        self.typeInferenceTrees = [:]

        var typeInferenceContexts: [Source.FilePath: TypeInferenceContext] = [:]
        var lastNeedsInferenceCount: Int? = nil
        var needsInferenceCount = 0
        var isCleanupPass = false
        while true {
            for (sourceFile, syntaxTree) in typeInferenceTrees {
                let context: TypeInferenceContext
                if let existingContext = typeInferenceContexts[sourceFile] {
                    context = existingContext
                } else {
                    // Create a context without match + member caches so lookups can see the changes we make as we infer variable types
                    let codebaseInfoContext = self.context(importedModuleNames: syntaxTree.root.statements.importedModulePaths.compactMap(\.moduleName), sourceFile: syntaxTree.source.file, cache: ContextCache(visibleMembers: nil, matches: nil))
                    context = TypeInferenceContext(codebaseInfo: codebaseInfoContext, unavailableAPI: nil, source: syntaxTree.source)
                    typeInferenceContexts[sourceFile] = context
                }
                for i in 0..<rootVariables.count {
                    if rootVariables[i].sourceFile == sourceFile && rootVariables[i].needsTypeInference {
                        if isCleanupPass {
                            rootVariables[i] = rootVariables[i].cleanupTypeInference(source: syntaxTree.source, messages: &messages)
                        } else {
                            rootVariables[i] = rootVariables[i].inferType(with: context)
                            if rootVariables[i].needsTypeInference {
                                needsInferenceCount += 1
                            }
                        }
                    }
                }
                for rootType in rootTypes + rootExtensions {
                    if rootType.sourceFile == sourceFile && rootType.needsVariableTypeInference {
                        if isCleanupPass {
                            rootType.cleanupTypeInference(source: syntaxTree.source, messages: &messages)
                        } else {
                            needsInferenceCount += rootType.inferVariableTypes(with: context)
                        }
                    }
                }
            }
            // We continue to do type inference passes until we resolve all variable types or until we perform a pass that doesn't
            // infer any additional types, at which point we do an additional cleanup pass to release references to the syntax tree
            if isCleanupPass || needsInferenceCount == 0 {
                break
            } else if needsInferenceCount == lastNeedsInferenceCount {
                isCleanupPass = true
            } else {
                lastNeedsInferenceCount = needsInferenceCount
                needsInferenceCount = 0
            }
        }
    }

    private func resolveTypeSignatures() {
        // Now that we've gathered complete type information, we can recognize typealiases and differentiate
        // between nested and module-qualified types
        for i in 0..<rootTypes.count { rootTypes[i].resolveTypeSignatures(codebaseInfo: self) }
        for i in 0..<rootTypealiases.count { rootTypealiases[i].resolveTypeSignatures(codebaseInfo: self) }
        for i in 0..<rootVariables.count { rootVariables[i].resolveTypeSignatures(codebaseInfo: self) }
        for i in 0..<rootFunctions.count { rootFunctions[i].resolveTypeSignatures(codebaseInfo: self) }
        for i in 0..<rootExtensions.count { rootExtensions[i].resolveTypeSignatures(codebaseInfo: self) }
    }

    private func addGeneratedConstructors() {
        rootTypes.forEach { addGeneratedConstructors(to: $0) }
    }

    private func addGeneratedConstructors(to typeInfo: TypeInfo) {
        // Handle nested types
        typeInfo.types.forEach { addGeneratedConstructors(to: $0) }
        guard typeInfo.declarationType == .actorDeclaration || typeInfo.declarationType == .classDeclaration || typeInfo.declarationType == .structDeclaration else {
            return
        }

        // The compiler only generates if there are no declared constructors
        let inits = typeInfo.functions.filter { $0.declarationType == .initDeclaration }
        guard inits.isEmpty else {
            return
        }
        var inheritInits: [FunctionInfo] = []
        var inheritGenerics: [TypeSignature] = []
        var targetGenerics: [TypeSignature] = []
        if typeInfo.declarationType == .classDeclaration, let inheritSignature = typeInfo.inherits.first {
            let inheritInfos = typeInfos(forNamed: inheritSignature)
            if let primaryInheritInfo = inheritInfos.first(where: { $0.declarationType == .classDeclaration }) {
                inheritGenerics = primaryInheritInfo.signature.generics
                targetGenerics = inheritSignature.generics
                // Filter out extensions with additional generic constraints
                let candidateInheritInfos = inheritInfos.filter { $0.declarationType != .extensionDeclaration || $0.generics == primaryInheritInfo.generics }
                inheritInits = candidateInheritInfos.flatMap { $0.functions.filter { $0.declarationType == .initDeclaration && ($0.modifiers.visibility != .private || $0.sourceFile == typeInfo.sourceFile) } }
            }
        }
        if inheritInits.isEmpty {
            addMemberwiseConstructor(to: typeInfo)
        } else {
            for var inheritInit in inheritInits {
                inheritInit.moduleName = typeInfo.moduleName
                inheritInit.sourceFile = typeInfo.sourceFile
                inheritInit.declaringType = typeInfo.signature
                inheritInit.signature = inheritInit.signature.withReturnType(typeInfo.signature).mappingTypes(from: inheritGenerics, to: targetGenerics)
                inheritInit.isGenerated = true
                typeInfo.functions.append(inheritInit)
            }
        }
    }

    private func addMemberwiseConstructor(to typeInfo: TypeInfo) {
        let parameters = typeInfo.declarationType != .structDeclaration ? [] : typeInfo.variables.compactMap { (variable) -> TypeSignature.Parameter? in
            guard variable.isInitializable else {
                return nil
            }
            var parameterType = variable.signature
            if variable.attributes.contains(.binding) {
                parameterType = parameterType.asBinding()
            } else if variable.attributes.contains(.viewBuilder), !variable.signature.isFunction, variable.apiFlags?.options.contains(.computed) == false {
                // Swift generates a closure parameter that returns a view for stored @ViewBuilder variables
                parameterType = .function([], variable.signature, APIFlags(), nil)
            }
            // Transfer attributes if variable is a closure, e.g. @ViewBuilder
            parameterType = variable.attributes.apply(toFunction: parameterType)
            return TypeSignature.Parameter(label: variable.name, type: parameterType, hasDefaultValue: variable.hasValue)
        }
        let initSignature: TypeSignature = .function(parameters, typeInfo.signature, typeInfo.apiFlags ?? APIFlags(), nil)
        var initInfo = FunctionInfo(name: "init", declarationType: .initDeclaration, signature: initSignature, moduleName: typeInfo.moduleName, sourceFile: typeInfo.sourceFile, declaringType: typeInfo.signature, modifiers: typeInfo.modifiers, attributes: Attributes(), availability: .available)
        initInfo.isGenerated = true
        typeInfo.functions.append(initInfo)
    }

    private func addGeneratedRawValues() {
        rootTypes.forEach { addGeneratedRawValues(to: $0) }
    }

    private func addGeneratedRawValues(to typeInfo: TypeInfo) {
        // Handle nested types
        typeInfo.types.forEach { addGeneratedRawValues(to: $0) }
        guard typeInfo.declarationType == .enumDeclaration, let inherits = typeInfo.inherits.first, (inherits.isStringy || inherits.isNumeric) else {
            return
        }

        if !typeInfo.inherits.contains(where: { $0.isNamed("RawRepresentable", moduleName: "Swift") }) {
            typeInfo.inherits.append(.named("RawRepresentable", [inherits]))
        }
        if typeInfo.variables.first(where: { $0.name == "rawValue" }) == nil {
            var rawValueInfo = VariableInfo(name: "rawValue", signature: inherits, moduleName: typeInfo.moduleName, sourceFile: typeInfo.sourceFile, declaringType: typeInfo.signature, modifiers: typeInfo.modifiers, attributes: Attributes(), availability: .available)
            rawValueInfo.isGenerated = true
            typeInfo.variables.append(rawValueInfo)
        }
    }

    private func addMainActorFlags() {
        // First add type-level flags
        for i in 0..<rootTypes.count { rootTypes[i].addMainActorTypeFlags(codebaseInfo: self) }
        for i in 0..<rootExtensions.count { rootExtensions[i].addMainActorTypeFlags(codebaseInfo: self) }

        // Then add individual member flags as needed
        for i in 0..<rootTypes.count { rootTypes[i].addMainActorMemberFlags(codebaseInfo: self) }
        for i in 0..<rootExtensions.count { rootExtensions[i].addMainActorMemberFlags(codebaseInfo: self) }
    }

    public final class ModuleExport: Codable {
        public let moduleName: String?

        // Default visibility for testing
        var rootTypes: [TypeInfo] = []
        var rootTypealiases: [TypealiasInfo] = []
        var rootVariables: [VariableInfo] = []
        var rootFunctions: [FunctionInfo] = []
        var rootExtensions: [TypeInfo] = []

        private var sourceFileTable: [String] = []
        private var sourceFileMapping: [String: Int] = [:]
        private var isPrepared = false

        private enum CodingKeys: String, CodingKey {
            case moduleName = "m", rootTypes = "t", rootTypealiases = "a", rootVariables = "v", rootFunctions = "f", rootExtensions = "e", sourceFileTable = "stable"
        }

        public init(of codebaseInfo: CodebaseInfo) {
            self.moduleName = codebaseInfo.moduleName

            // We want to always produce the same encoded output for the same input, because new output from one module might be a signal
            // that modules depending on it have to re-transpile. Sort for stability. API within a file will always have been added in the
            // same order, so we only need to sort by file
            let sortBy: (CodebaseInfoItem, CodebaseInfoItem) -> Bool = { ($0.sourceFile?.path ?? "") < ($1.sourceFile?.path ?? "") }
            let filter: (CodebaseInfoItem) -> Bool = { $0.modifiers.visibility == .public || $0.modifiers.visibility == .open || $0.declarationType == .extensionDeclaration }
            
            // Sort types before applying `export` so that the source file table that export builds is in stable order
            self.rootTypes = codebaseInfo.rootTypes.sorted(by: sortBy).compactMap { export(typeInfo: $0, filter: filter) }
            self.rootTypealiases = codebaseInfo.rootTypealiases.sorted(by: sortBy).filter(filter).map { replaceSourceFile(for: $0) }
            self.rootVariables = codebaseInfo.rootVariables.sorted(by: sortBy).filter(filter).map { replaceSourceFile(for: $0) }
            self.rootFunctions = codebaseInfo.rootFunctions.sorted(by: sortBy).filter(filter).map { replaceSourceFile(for: $0) }
            self.rootExtensions = codebaseInfo.rootExtensions.sorted(by: sortBy).compactMap { export(typeInfo: $0, filter: filter) }
        }

        private func export(typeInfo: TypeInfo, filter: (CodebaseInfoItem) -> Bool) -> TypeInfo? {
            guard filter(typeInfo) else {
                return nil
            }
            
            let copy = replaceSourceFile(for: TypeInfo(copy: typeInfo))
            copy.types = copy.types.compactMap { export(typeInfo: $0, filter: filter) }
            copy.typealiases = copy.typealiases.filter(filter).map { replaceSourceFile(for: $0) }
            copy.variables = copy.variables.filter(filter).map { replaceSourceFile(for: $0) }
            copy.functions = copy.functions.filter(filter).map { replaceSourceFile(for: $0) }
            // If this was an extension that is now empty, don't add it
            guard copy.declarationType != .extensionDeclaration || !copy.types.isEmpty || !copy.typealiases.isEmpty || !copy.variables.isEmpty || !copy.functions.isEmpty else {
                return nil
            }
            return copy
        }

        var isEmpty: Bool {
            return rootTypes.isEmpty && rootTypealiases.isEmpty && rootVariables.isEmpty && rootFunctions.isEmpty && rootExtensions.isEmpty
        }

        func prepareForUse() {
            rootTypes.forEach { prepareForUse(typeInfo: $0) }
            rootTypealiases = rootTypealiases.map { repopulateSourceFile(for: $0) }
            rootVariables = rootVariables.map { repopulateSourceFile(for: $0) }
            rootFunctions = rootFunctions.map { repopulateSourceFile(for: $0) }
            rootExtensions.forEach { prepareForUse(typeInfo: $0) }
        }

        private func prepareForUse(typeInfo: TypeInfo) {
            let typeInfo = repopulateSourceFile(for: typeInfo)
            typeInfo.types.forEach { prepareForUse(typeInfo: $0) }
            typeInfo.typealiases = typeInfo.typealiases.map { repopulateSourceFile(for: $0) }
            typeInfo.variables = typeInfo.variables.map { repopulateSourceFile(for: $0) }
            typeInfo.functions = typeInfo.functions.map { repopulateSourceFile(for: $0) }
        }

        private func replaceSourceFile<T>(for item: T) -> T where T: CodebaseInfoItem {
            guard item.sourceFileID == nil, let sourceFile = item.sourceFile else {
                return item
            }
            var item = item
            if let sid = sourceFileMapping[sourceFile.path] {
                item.sourceFileID = sid
            } else {
                let sid = sourceFileTable.count
                sourceFileTable.append(sourceFile.path)

                sourceFileMapping[sourceFile.path] = sid
                item.sourceFileID = sid
            }
            return item
        }

        private func repopulateSourceFile<T>(for item: T) -> T where T: CodebaseInfoItem {
            guard item.sourceFile == nil, let sid = item.sourceFileID, sid >= 0 && sid < sourceFileTable.count else {
                return item
            }

            var populatedItem = item
            populatedItem.sourceFile = Source.FilePath(path: sourceFileTable[sid])
            return populatedItem
        }
    }

    /// Information about a declared type.
    ///
    /// - Note: Unlike the other `CodebaseInfoItem` datastructures, types are modeled as `class` instances so that we can mutate them in place.
    final class TypeInfo: CodebaseInfoItem, Hashable, Codable {
        var name: String
        let declarationType: StatementType
        var signature: TypeSignature
        let moduleName: String?
        var sourceFile: Source.FilePath?
        var sourceFileID: Int?
        let declaringType: TypeSignature?
        let modifiers: Modifiers
        let attributes: Attributes
        let availability: Availability
        var apiFlags: APIFlags?
        var isStatic: Bool {
            return true
        }
        var languageAdditions: Any?
        var importedModuleNames: [String]? {
            didSet {
                for i in 0..<types.count { types[i].importedModuleNames = importedModuleNames }
                for i in 0..<typealiases.count { typealiases[i].importedModuleNames = importedModuleNames }
                for i in 0..<cases.count { cases[i].importedModuleNames = importedModuleNames }
                for i in 0..<variables.count { variables[i].importedModuleNames = importedModuleNames }
                for i in 0..<functions.count { functions[i].importedModuleNames = importedModuleNames }
                for i in 0..<subscripts.count { subscripts[i].importedModuleNames = importedModuleNames }
            }
        }

        var generics: Generics
        var inherits: [TypeSignature]

        var types: [TypeInfo] = []
        var typealiases: [TypealiasInfo] = []
        var cases: [EnumCaseInfo] = []
        var variables: [VariableInfo] = []
        var functions: [FunctionInfo] = []
        var subscripts: [SubscriptInfo] = []
        var members: [CodebaseInfoItem] {
            // Break up statement to satisfy compiler
            var members: [CodebaseInfoItem] = []
            members += types
            members += typealiases
            members += cases
            members += variables
            members += functions
            members += subscripts
            return members
        }

        /// Return whether this extension info applies when we have the given generics values.
        fileprivate func isApplicable(toConstrainedGenerics constrainedGenerics: [TypeSignature], codebaseInfo: CodebaseInfo.Context) -> Bool {
            guard declarationType == .extensionDeclaration, !constrainedGenerics.isEmpty else {
                return true
            }
            guard let primaryInfo = codebaseInfo.primaryTypeInfo(forNamed: signature) else {
                return generics.isEmpty
            }
            guard generics != primaryInfo.generics else {
                return true
            }
            let names = primaryInfo.signature.generics
            guard names.count == constrainedGenerics.count else {
                return true
            }
            for (index, name) in names.enumerated() {
                let constrainedType = generics.constrainedType(of: name.name)
                guard constrainedGenerics[index].compatibilityScore(target: constrainedType, codebaseInfo: codebaseInfo) != nil else {
                    return false
                }
            }
            return true
        }

        private enum CodingKeys: String, CodingKey {
            // Exclude language additions, importedModuleNames
            case name = "n", declarationType = "t", signature = "s", moduleName = "m", sourceFileID = "sid", declaringType = "d", modifiers = "z", attributes = "a", availability = "v", apiFlags = "f", generics = "g", inherits = "i", types = "mt", typealiases = "ma", cases = "mc", variables = "mv", functions = "mf", subscripts = "ms"
        }

        fileprivate init(statement: TypeDeclaration, in declaringType: TypeSignature? = nil, codebaseInfo: CodebaseInfo, syntaxTree: SyntaxTree) {
            self.name = statement.name
            self.declarationType = statement.type
            self.signature = statement.signature
            self.moduleName = codebaseInfo.moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.modifiers = statement.modifiers
            self.attributes = statement.attributes
            self.availability = Availability(attributes: statement.attributes)
            self.apiFlags = APIFlags(isMainActor: statement.attributes.contains(.mainActor))
            self.generics = statement.generics
            self.inherits = statement.inherits
            addMembers(statement.members, codebaseInfo: codebaseInfo, syntaxTree: syntaxTree)
            (codebaseInfo.languageAdditions as? CodebaseInfoLanguageAdditionsGatherDelegate)?.codebaseInfo(codebaseInfo, didGather: self, from: statement, syntaxTree: syntaxTree)
        }

        fileprivate init(statement: ExtensionDeclaration, codebaseInfo: CodebaseInfo, syntaxTree: SyntaxTree) {
            self.name = statement.name
            self.declarationType = statement.type
            self.signature = statement.signature
            self.moduleName = codebaseInfo.moduleName
            self.sourceFile = statement.sourceFile
            if case .member(let base, _) = statement.signature {
                self.declaringType = base
            } else {
                self.declaringType = nil
            }
            self.modifiers = statement.modifiers
            self.attributes = statement.attributes
            self.availability = Availability(attributes: statement.attributes)
            self.apiFlags = APIFlags(isMainActor: statement.attributes.contains(.mainActor))
            self.generics = statement.generics
            self.inherits = statement.inherits
            addMembers(statement.members, codebaseInfo: codebaseInfo, syntaxTree: syntaxTree)
            (codebaseInfo.languageAdditions as? CodebaseInfoLanguageAdditionsGatherDelegate)?.codebaseInfo(codebaseInfo, didGather: self, from: statement, syntaxTree: syntaxTree)
        }

        fileprivate init(copy: TypeInfo) {
            self.name = copy.name
            self.declarationType = copy.declarationType
            self.signature = copy.signature
            self.moduleName = copy.moduleName
            self.sourceFile = copy.sourceFile
            self.declaringType = copy.declaringType
            self.modifiers = copy.modifiers
            self.attributes = copy.attributes
            self.availability = copy.availability
            self.apiFlags = copy.apiFlags
            self.importedModuleNames = copy.importedModuleNames
            self.generics = copy.generics
            self.inherits = copy.inherits
            self.types = copy.types
            self.typealiases = copy.typealiases
            self.cases = copy.cases
            self.variables = copy.variables
            self.functions = copy.functions
            self.subscripts = copy.subscripts
        }

        fileprivate var needsVariableTypeInference: Bool {
            return variables.contains { $0.needsTypeInference } || types.contains { $0.needsVariableTypeInference }
        }

        fileprivate func inferVariableTypes(with context: TypeInferenceContext) -> Int {
            let memberContext = context.pushing(self)
            var needsInferenceCount = 0
            for i in 0..<variables.count {
                guard variables[i].needsTypeInference else {
                    continue
                }
                variables[i] = variables[i].inferType(with: memberContext)
                if variables[i].needsTypeInference {
                    needsInferenceCount += 1
                }
            }
            for type in types {
                guard type.needsVariableTypeInference else {
                    continue
                }
                needsInferenceCount += type.inferVariableTypes(with: memberContext)
            }
            return needsInferenceCount
        }

        fileprivate func cleanupTypeInference(source: Source, messages: inout [Source.FilePath: [Message]]) {
            variables = variables.map { $0.cleanupTypeInference(source: source, messages: &messages) }
            types.forEach { $0.cleanupTypeInference(source: source, messages: &messages) }
        }

        fileprivate func resolveTypeSignatures(codebaseInfo: CodebaseInfo) {
            let context = TypeResolutionContext(codebaseInfo: codebaseInfo.context(importedModuleNames: importedModuleNames ?? [], sourceFile: sourceFile))
            generics = generics.resolved(declaringType: signature, context: context)
            inherits = inherits.map { $0.resolved(declaringType: signature, context: context) }
            for i in 0..<types.count { types[i].resolveTypeSignatures(codebaseInfo: codebaseInfo) }
            for i in 0..<typealiases.count { typealiases[i].resolveTypeSignatures(codebaseInfo: codebaseInfo) }
            for i in 0..<cases.count { cases[i].resolveTypeSignatures(codebaseInfo: codebaseInfo) }
            for i in 0..<variables.count { variables[i].resolveTypeSignatures(codebaseInfo: codebaseInfo) }
            for i in 0..<functions.count { functions[i].resolveTypeSignatures(codebaseInfo: codebaseInfo) }
            for i in 0..<subscripts.count { subscripts[i].resolveTypeSignatures(codebaseInfo: codebaseInfo) }
        }

        fileprivate func addMainActorTypeFlags(codebaseInfo: CodebaseInfo) {
            for i in 0..<types.count { types[i].addMainActorTypeFlags(codebaseInfo: codebaseInfo) }
            guard isMainActorType(codebaseInfo: codebaseInfo) else {
                return
            }
            apiFlags?.options.insert(.mainActor)
            for i in 0..<variables.count { variables[i].addMainActorFlag() }
            for i in 0..<functions.count { functions[i].addMainActorFlag() }
            for i in 0..<subscripts.count { subscripts[i].addMainActorFlag() }
        }

        fileprivate func addMainActorMemberFlags(codebaseInfo: CodebaseInfo) {
            for i in 0..<types.count { types[i].addMainActorMemberFlags(codebaseInfo: codebaseInfo) }
            guard apiFlags?.options.contains(.mainActor) != true else {
                return
            }
            guard !inherits.isEmpty else {
                return
            }

            let concreteTypeInfos = codebaseInfo.inheritanceChainSignatures(forNamed: signature)
                .dropFirst() // Drop this type
                .flatMap { codebaseInfo.typeInfos(forNamed: $0) }
            let protocolTypeInfos = codebaseInfo.protocolSignatures(forNamed: signature)
                .compactMap { codebaseInfo.primaryTypeInfo(forNamed: $0) } // What are the rules for protocol extensions?
                .filter { $0.name != signature.name } // Filter this type if protocol
            let typeInfos = concreteTypeInfos + protocolTypeInfos
            for i in 0..<variables.count {
                if Self.isMainActorInferred(variables[i], in: typeInfos) {
                    variables[i].addMainActorFlag()
                }
            }
            for i in 0..<functions.count {
                if Self.isMainActorInferred(functions[i], in: typeInfos) {
                    functions[i].addMainActorFlag()
                }
            }
            for i in 0..<subscripts.count {
                if Self.isMainActorInferred(subscripts[i], in: typeInfos) {
                    subscripts[i].addMainActorFlag()
                }
            }
        }

        private func isMainActorType(codebaseInfo: CodebaseInfo) -> Bool {
            guard !modifiers.isNonisolated else {
                return false
            }
            guard apiFlags?.options.contains(.mainActor) != true else {
                return true
            }
            if declarationType == .extensionDeclaration {
                // Is extension's extended type @MainActor?
                return codebaseInfo.primaryTypeInfo(forNamed: signature)?.isMainActorType(codebaseInfo: codebaseInfo) == true
            } else {
                // Do we extend a class or conform to a protocol that is @MainActor?
                return inherits.contains { codebaseInfo.primaryTypeInfo(forNamed: $0)?.isMainActorType(codebaseInfo: codebaseInfo) == true }
            }
        }

        private static func isMainActorInferred(_ item: CodebaseInfoItem, in typeInfos: [TypeInfo]) -> Bool {
            guard !item.modifiers.isNonisolated, item.apiFlags?.options.contains(.mainActor) != true, item.modifiers.visibility != .private else {
                return false
            }
            for typeInfo in typeInfos {
                guard typeInfo.declarationType == .protocolDeclaration || item.modifiers.isOverride else {
                    // If this is a concrete type, we'd have to be an explicit override
                    continue
                }
                switch item.declarationType {
                case .variableDeclaration:
                    if typeInfo.variables.contains(where: { $0.apiFlags?.options.contains(.mainActor) == true && $0.modifiers.visibility != .private && $0.isStatic == item.isStatic && $0.name == item.name }) {
                        return true
                    }
                case .functionDeclaration, .initDeclaration:
                    if typeInfo.functions.contains(where: { $0.apiFlags?.options.contains(.mainActor) == true && $0.modifiers.visibility != .private && $0.isStatic == item.isStatic && $0.name == item.name && $0.signature.parameters.map(\.label) == item.signature.parameters.map(\.label) }) {
                        return true
                    }
                case .subscriptDeclaration:
                    if typeInfo.subscripts.contains(where: { $0.apiFlags?.options.contains(.mainActor) == true && $0.modifiers.visibility != .private && $0.isStatic == item.isStatic && $0.signature.parameters.map(\.label) == item.signature.parameters.map(\.label) }) {
                        return true
                    }
                default:
                    break
                }
            }
            return false
        }

        private func addMembers(_ statements: [Statement], codebaseInfo: CodebaseInfo, syntaxTree: SyntaxTree) {
            for statement in statements {
                switch statement.type {
                case .actorDeclaration, .classDeclaration, .enumDeclaration, .structDeclaration:
                    types.append(TypeInfo(statement: statement as! TypeDeclaration, in: signature, codebaseInfo: codebaseInfo, syntaxTree: syntaxTree))
                case .enumCaseDeclaration:
                    cases.append(EnumCaseInfo(statement: statement as! EnumCaseDeclaration, in: signature, codebaseInfo: codebaseInfo, syntaxTree: syntaxTree))
                case .functionDeclaration, .initDeclaration, .deinitDeclaration:
                    functions.append(FunctionInfo(statement: statement as! FunctionDeclaration, in: signature, codebaseInfo: codebaseInfo, syntaxTree: syntaxTree))
                case .subscriptDeclaration:
                    subscripts.append(SubscriptInfo(statement: statement as! SubscriptDeclaration, in: signature, codebaseInfo: codebaseInfo, syntaxTree: syntaxTree))
                case .typealiasDeclaration:
                    typealiases.append(TypealiasInfo(statement: statement as! TypealiasDeclaration, in: signature, codebaseInfo: codebaseInfo, syntaxTree: syntaxTree))
                case .variableDeclaration:
                    variables.append(VariableInfo(statement: statement as! VariableDeclaration, in: signature, codebaseInfo: codebaseInfo, syntaxTree: syntaxTree))
                default:
                    break
                }
            }
        }

        static func ==(lhs: TypeInfo, rhs: TypeInfo) -> Bool {
            return lhs === rhs
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(self))
        }
    }

    /// Information about a declared global or property.
    struct VariableInfo: CodebaseInfoItem, Codable {
        let name: String
        var declarationType: StatementType {
            return .variableDeclaration
        }
        var signature: TypeSignature
        let moduleName: String?
        var sourceFile: Source.FilePath?
        var sourceFileID: Int?
        let declaringType: TypeSignature?
        let modifiers: Modifiers
        let attributes: Attributes
        let availability: Availability
        var apiFlags: APIFlags?
        var isStatic: Bool {
            return modifiers.isStatic
        }
        var languageAdditions: Any?
        var importedModuleNames: [String]?

        let isInitializable: Bool
        let hasValue: Bool
        var typeInferenceValue: Any?
        var isGenerated = false

        private enum CodingKeys: String, CodingKey {
            // Exclude value expression, language additions, importedModuleNames
            case name = "n", signature = "s", moduleName = "m", sourceFileID = "sid", declaringType = "d", modifiers = "z", attributes = "a", availability = "v", apiFlags = "f", isInitializable = "init", hasValue = "val", isGenerated = "gen"
        }

        fileprivate init(statement: VariableDeclaration, in declaringType: TypeSignature? = nil, codebaseInfo: CodebaseInfo, syntaxTree: SyntaxTree) {
            self.name = statement.propertyName
            self.signature = statement.propertyType
            self.moduleName = codebaseInfo.moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.modifiers = statement.modifiers
            self.attributes = statement.attributes
            self.availability = Availability(attributes: statement.attributes)
            self.apiFlags = statement.apiFlags
            self.isInitializable = !statement.modifiers.isStatic && !statement.modifiers.isOverride && statement.getter == nil && (!statement.isLet || statement.value == nil)
            self.hasValue = self.signature.isOptional || statement.value != nil
            if !self.signature.isFullySpecified, self.sourceFile != nil, let value = statement.value {
                // We'll try to infer the type after gathering all info
                self.typeInferenceValue = value
            } else if self.signature == .none, let environmentAttribute = attributes.environmentAttribute {
                if let environmentType = environmentAttribute.tokenTypeSignature {
                    self.signature = environmentType
                } else {
                    self.typeInferenceValue = environmentAttribute
                }
            }
            (codebaseInfo.languageAdditions as? CodebaseInfoLanguageAdditionsGatherDelegate)?.codebaseInfo(codebaseInfo, didGather: &self, from: statement, syntaxTree: syntaxTree)
        }

        fileprivate init(name: String, signature: TypeSignature, moduleName: String?, sourceFile: Source.FilePath? = nil, declaringType: TypeSignature? = nil, modifiers: Modifiers, attributes: Attributes, availability: Availability, apiFlags: APIFlags = APIFlags(), isInitializable: Bool = false, hasValue: Bool = false) {
            self.name = name
            self.signature = signature
            self.moduleName = moduleName
            self.sourceFile = sourceFile
            self.declaringType = declaringType
            self.modifiers = modifiers
            self.attributes = attributes
            self.availability = availability
            self.apiFlags = apiFlags
            self.isInitializable = isInitializable
            self.hasValue = hasValue
        }

        fileprivate var needsTypeInference: Bool {
            return typeInferenceValue != nil
        }

        fileprivate func inferType(with context: TypeInferenceContext) -> VariableInfo {
            guard typeInferenceValue != nil else {
                return self
            }
            var v = self
            let varContext = v.isStatic ? context.pushingBlock(isStatic: true) : context
            if let value = typeInferenceValue as? Expression {
                value.inferTypes(context: varContext, expecting: .none)
                v.signature = value.inferredType
                if v.signature.isFullySpecified {
                    v.typeInferenceValue = nil
                }
            } else if let environmentAttribute = typeInferenceValue as? Attribute {
                if let environmentValuesProperty = environmentAttribute.environmentValuesProperty {
                    if environmentValuesProperty == "self" {
                        v.signature = .named("EnvironmentValues", [])
                    } else {
                        v.signature = varContext.member(environmentValuesProperty, in: .named("EnvironmentValues", []), messagesNode: nil)?.0 ?? .none
                    }
                }
                v.typeInferenceValue = nil
            }
            return v
        }

        fileprivate func cleanupTypeInference(source: Source, messages: inout [Source.FilePath: [Message]]) -> VariableInfo {
            guard typeInferenceValue != nil else {
                return self
            }
            if let sourceFile, let value = typeInferenceValue as? Expression {
                var fileMessages = messages[sourceFile, default: []]
                fileMessages.append(.variableNeedsTypeDeclaration(value, source: source))
                messages[sourceFile] = fileMessages
            }
            var v = self
            v.typeInferenceValue = nil
            return v
        }

        fileprivate mutating func resolveTypeSignatures(codebaseInfo: CodebaseInfo) {
            let context = TypeResolutionContext(codebaseInfo: codebaseInfo.context(importedModuleNames: importedModuleNames ?? [], sourceFile: sourceFile))
            signature = signature.resolved(declaringType: declaringType, context: context)
        }

        fileprivate mutating func addMainActorFlag() {
            if !modifiers.isNonisolated {
                apiFlags?.options.insert(.mainActor)
            }
        }
    }

    /// Information about a declared function.
    struct FunctionInfo: CodebaseInfoItem, Codable {
        let name: String
        let declarationType: StatementType
        var signature: TypeSignature
        var moduleName: String?
        var sourceFile: Source.FilePath?
        var sourceFileID: Int?
        var declaringType: TypeSignature?
        let modifiers: Modifiers
        let attributes: Attributes
        let availability: Availability
        var apiFlags: APIFlags? {
            return signature.apiFlags
        }
        var isStatic: Bool {
            return modifiers.isStatic
        }
        var languageAdditions: Any?
        var importedModuleNames: [String]?

        var generics: Generics
        let isMutating: Bool
        var isGenerated = false

        private enum CodingKeys: String, CodingKey {
            // Exclude language additions, importedModuleNames
            case name = "n", declarationType = "t", signature = "s", moduleName = "m", sourceFileID = "sid", declaringType = "d", modifiers = "z", attributes = "a", availability = "v", generics = "g", isMutating = "mut", isGenerated = "gen"
        }

        fileprivate init(statement: FunctionDeclaration, in declaringType: TypeSignature? = nil, codebaseInfo: CodebaseInfo, syntaxTree: SyntaxTree) {
            self.name = statement.name
            self.declarationType = statement.type
            self.signature = statement.functionType
            self.moduleName = codebaseInfo.moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.modifiers = statement.modifiers
            self.attributes = statement.attributes
            self.availability = Availability(attributes: statement.attributes)
            self.generics = statement.generics
            self.isMutating = statement.modifiers.isMutating
            (codebaseInfo.languageAdditions as? CodebaseInfoLanguageAdditionsGatherDelegate)?.codebaseInfo(codebaseInfo, didGather: &self, from: statement, syntaxTree: syntaxTree)
        }

        fileprivate init(name: String, declarationType: StatementType, signature: TypeSignature, moduleName: String?, sourceFile: Source.FilePath? = nil, declaringType: TypeSignature? = nil, modifiers: Modifiers, attributes: Attributes, availability: Availability, generics: Generics = Generics(), apiFlags: APIFlags = APIFlags(), isMutating: Bool = false) {
            self.name = name
            self.declarationType = declarationType
            self.signature = signature
            self.moduleName = moduleName
            self.sourceFile = sourceFile
            self.declaringType = declaringType
            self.modifiers = modifiers
            self.attributes = attributes
            self.availability = availability
            self.generics = generics
            self.isMutating = isMutating
        }

        fileprivate mutating func resolveTypeSignatures(codebaseInfo: CodebaseInfo) {
            let context = TypeResolutionContext(codebaseInfo: codebaseInfo.context(importedModuleNames: importedModuleNames ?? [], sourceFile: sourceFile))
            generics = generics.resolved(declaringType: declaringType, context: context)
            signature = signature.resolved(declaringType: declaringType, context: context)
        }

        fileprivate mutating func addMainActorFlag() {
            if !modifiers.isNonisolated {
                var apiFlags = signature.apiFlags
                apiFlags.options.insert(.mainActor)
                signature = signature.withAPIFlags(apiFlags)
            }
        }
    }

    /// Information about a declared subscript function.
    struct SubscriptInfo: CodebaseInfoItem, Codable {
        var name: String {
            return "subscript"
        }
        var declarationType: StatementType {
            return .subscriptDeclaration
        }
        var signature: TypeSignature
        var moduleName: String?
        var sourceFile: Source.FilePath?
        var sourceFileID: Int?
        var declaringType: TypeSignature?
        let modifiers: Modifiers
        let attributes: Attributes
        let availability: Availability
        var apiFlags: APIFlags? {
            return signature.apiFlags
        }
        var isStatic: Bool {
            return modifiers.isStatic
        }
        var languageAdditions: Any?
        var importedModuleNames: [String]?

        var generics: Generics
        let isReadOnly: Bool

        private enum CodingKeys: String, CodingKey {
            // Exclude language additions, importedModuleNames
            case signature = "s", moduleName = "m", sourceFileID = "sid", declaringType = "d", modifiers = "z", attributes = "a", availability = "v", generics = "g", isReadOnly = "ro"
        }

        fileprivate init(statement: SubscriptDeclaration, in declaringType: TypeSignature? = nil, codebaseInfo: CodebaseInfo, syntaxTree: SyntaxTree) {
            self.signature = statement.getterType
            self.moduleName = codebaseInfo.moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.modifiers = statement.modifiers
            self.attributes = statement.attributes
            self.availability = Availability(attributes: statement.attributes)
            self.generics = statement.generics
            self.isReadOnly = statement.setter == nil
            (codebaseInfo.languageAdditions as? CodebaseInfoLanguageAdditionsGatherDelegate)?.codebaseInfo(codebaseInfo, didGather: &self, from: statement, syntaxTree: syntaxTree)
        }

        fileprivate mutating func resolveTypeSignatures(codebaseInfo: CodebaseInfo) {
            let context = TypeResolutionContext(codebaseInfo: codebaseInfo.context(importedModuleNames: importedModuleNames ?? [], sourceFile: sourceFile))
            generics = generics.resolved(declaringType: declaringType, context: context)
            signature = signature.resolved(declaringType: declaringType, context: context)
        }

        fileprivate mutating func addMainActorFlag() {
            if !modifiers.isNonisolated {
                var apiFlags = signature.apiFlags
                apiFlags.options.insert(.mainActor)
                signature = signature.withAPIFlags(apiFlags)
            }
        }
    }

    /// Information about a typealias.
    struct TypealiasInfo: CodebaseInfoItem, Codable {
        let name: String
        var declarationType: StatementType {
            return .typealiasDeclaration
        }
        var signature: TypeSignature
        let moduleName: String?
        var sourceFile: Source.FilePath?
        var sourceFileID: Int?
        let declaringType: TypeSignature?
        let modifiers: Modifiers
        let attributes: Attributes
        let availability: Availability
        var apiFlags: APIFlags? {
            return nil
        }
        var isStatic: Bool {
            return true
        }
        var languageAdditions: Any?
        var importedModuleNames: [String]?

        var generics: Generics
        var targetSignature: TypeSignature

        private enum CodingKeys: String, CodingKey {
            // Exclude language additions, importedModuleNames
            case name = "n", signature = "s", moduleName = "m", sourceFileID = "sid", declaringType = "d", modifiers = "z", attributes = "a", availability = "v", generics = "g", targetSignature = "tar"
        }

        fileprivate init(statement: TypealiasDeclaration, in declaringType: TypeSignature? = nil, codebaseInfo: CodebaseInfo, syntaxTree: SyntaxTree) {
            self.name = statement.name
            self.signature = statement.signature
            self.moduleName = codebaseInfo.moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.modifiers = statement.modifiers
            self.attributes = statement.attributes
            self.availability = Availability(attributes: statement.attributes)
            self.generics = statement.generics
            self.targetSignature = statement.aliasedType
            (codebaseInfo.languageAdditions as? CodebaseInfoLanguageAdditionsGatherDelegate)?.codebaseInfo(codebaseInfo, didGather: &self, from: statement, syntaxTree: syntaxTree)
        }

        fileprivate mutating func resolveTypeSignatures(codebaseInfo: CodebaseInfo) {
            let context = TypeResolutionContext(codebaseInfo: codebaseInfo.context(importedModuleNames: importedModuleNames ?? [], sourceFile: sourceFile))
            generics = generics.resolved(declaringType: declaringType, context: context)
            targetSignature = targetSignature.resolved(declaringType: declaringType, context: context)
        }
    }

    /// Information about an enum case.
    struct EnumCaseInfo: CodebaseInfoItem, Codable {
        let name: String
        var declarationType: StatementType {
            return .enumCaseDeclaration
        }
        var signature: TypeSignature // Owning enum or a function returning the owning enum
        let moduleName: String?
        var sourceFile: Source.FilePath?
        var sourceFileID: Int?
        let declaringType: TypeSignature?
        let modifiers: Modifiers
        let attributes: Attributes
        let availability: Availability
        var apiFlags: APIFlags? {
            return nil
        }
        var isStatic: Bool {
            return true
        }
        var languageAdditions: Any?
        var importedModuleNames: [String]?

        private enum CodingKeys: String, CodingKey {
            // Exclude language additions, importedModuleNames
            case name = "n", signature = "s", moduleName = "m", sourceFileID = "sid", declaringType = "d", modifiers = "z", attributes = "a", availability = "v"
        }

        fileprivate init(statement: EnumCaseDeclaration, in declaringType: TypeSignature? = nil, codebaseInfo: CodebaseInfo, syntaxTree: SyntaxTree) {
            self.name = statement.name
            self.signature = statement.signature
            self.moduleName = codebaseInfo.moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.modifiers = statement.modifiers
            self.attributes = statement.attributes
            self.availability = Availability(attributes: statement.attributes)
            (codebaseInfo.languageAdditions as? CodebaseInfoLanguageAdditionsGatherDelegate)?.codebaseInfo(codebaseInfo, didGather: &self, from: statement, syntaxTree: syntaxTree)
        }

        fileprivate mutating func resolveTypeSignatures(codebaseInfo: CodebaseInfo) {
            let context = TypeResolutionContext(codebaseInfo: codebaseInfo.context(importedModuleNames: importedModuleNames ?? [], sourceFile: sourceFile))
            signature = signature.resolved(declaringType: declaringType, context: context)
        }
    }
}

/// Common protocol for all codebase info items.
protocol CodebaseInfoItem {
    var name: String { get }
    var declarationType: StatementType { get }
    var signature: TypeSignature { get }
    var moduleName: String? { get }
    var sourceFile: Source.FilePath? { get set }
    var sourceFileID: Int? { get set }
    var declaringType: TypeSignature? { get }
    var modifiers: Modifiers { get }
    var attributes: Attributes { get }
    var availability: Availability { get }
    var apiFlags: APIFlags? { get }
    var isStatic: Bool { get }
    /// Not serialized.
    var languageAdditions: Any? { get set }
    /// Not serialized.
    var importedModuleNames: [String]? { get set }
}

extension CodebaseInfoItem {
    fileprivate var apiMatch: APIMatch {
        let memberOf: (TypeSignature, TypeSignature?)?
        if let declaringType {
            memberOf = (declaringType.asMetaType(isStatic), nil)
        } else {
            memberOf = nil
        }
        return APIMatch(signature: signature, apiFlags: apiFlags ?? APIFlags(), declarationType: declarationType, memberOf: memberOf, attributes: attributes, availability: availability)
    }
}

extension CodebaseInfoItem {
    func rankScore(moduleName: String?, importedModuleNames: Set<String>, sourceFile: Source.FilePath?) -> Int {
        var score = 0
        if self.moduleName == moduleName {
            if let itemSourcePath = self.sourceFile?.path, let sourcePath = sourceFile?.path, itemSourcePath.hasSuffix(sourcePath) {
                // Favor a symbol in this file
                score = 3
            } else if modifiers.visibility != .private {
                // Favor a symbol in this module
                score = 2
            }
        } else if let itemModuleName = self.moduleName, itemModuleName == "SkipLib" || importedModuleNames.contains(itemModuleName) {
            score = 1
        }
        if score > 0 {
            // Always favor types over other items, even overwhelming locality. This solves the issue of type-named functions that
            // act as factories compete with constructors - e.g. a call to func A(...) and a call to an A(...) constructor. We're smart
            // enough to find type-named functions when looking for constructors
            //
            // Note: Don't use "self is TypeInfo" here because it was prominent in profiles. Use declarationType instead
            switch declarationType {
            case .actorDeclaration, .classDeclaration, .enumDeclaration, .extensionDeclaration, .protocolDeclaration, .structDeclaration, .typealiasDeclaration:
                score += 3
            default:
                break
            }
        }
        return score
    }
}

/// Helper to track target language additions.
protocol CodebaseInfoLanguageAdditions {
    /// Any issues encountered during information gathering.
    func messages(for sourceFile: Source.FilePath) -> [Message]

    /// Prepare language additions for use.
    func prepareForUse(codebaseInfo: CodebaseInfo)
}

extension CodebaseInfoLanguageAdditions {
    func messages(for sourceFile: Source.FilePath) -> [Message] {
        return []
    }

    func prepareForUse(codebaseInfo: CodebaseInfo) {
    }
}

/// Optional protocol the `CodebaseInfoLanguageAdditions` can implement to receive info gathering callbacks.
protocol CodebaseInfoLanguageAdditionsGatherDelegate {
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGatherFrom syntaxTree: SyntaxTree)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typeInfo: CodebaseInfo.TypeInfo, from statement: TypeDeclaration, syntaxTree: SyntaxTree)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typeInfo: CodebaseInfo.TypeInfo, from statement: ExtensionDeclaration, syntaxTree: SyntaxTree)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather variableInfo: inout CodebaseInfo.VariableInfo, from statement: VariableDeclaration, syntaxTree: SyntaxTree)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather functionInfo: inout CodebaseInfo.FunctionInfo, from statement: FunctionDeclaration, syntaxTree: SyntaxTree)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather subscriptInfo: inout CodebaseInfo.SubscriptInfo, from statement: SubscriptDeclaration, syntaxTree: SyntaxTree)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typealiasInfo: inout CodebaseInfo.TypealiasInfo, from statement: TypealiasDeclaration, syntaxTree: SyntaxTree)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather enumCaseInfo: inout CodebaseInfo.EnumCaseInfo, from statement: EnumCaseDeclaration, syntaxTree: SyntaxTree)
}

extension CodebaseInfoLanguageAdditionsGatherDelegate {
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGatherFrom syntaxTree: SyntaxTree) {
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typeInfo: CodebaseInfo.TypeInfo, from statement: TypeDeclaration, syntaxTree: SyntaxTree) {
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typeInfo: CodebaseInfo.TypeInfo, from statement: ExtensionDeclaration, syntaxTree: SyntaxTree) {
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather variableInfo: inout CodebaseInfo.VariableInfo, from statement: VariableDeclaration, syntaxTree: SyntaxTree) {
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather functionInfo: inout CodebaseInfo.FunctionInfo, from statement: FunctionDeclaration, syntaxTree: SyntaxTree) {
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather subscriptInfo: inout CodebaseInfo.SubscriptInfo, from statement: SubscriptDeclaration, syntaxTree: SyntaxTree) {
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typealiasInfo: inout CodebaseInfo.TypealiasInfo, from statement: TypealiasDeclaration, syntaxTree: SyntaxTree) {
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather enumCaseInfo: inout CodebaseInfo.EnumCaseInfo, from statement: EnumCaseDeclaration, syntaxTree: SyntaxTree) {
    }
}
