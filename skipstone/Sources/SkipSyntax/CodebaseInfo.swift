/// Codable information about the codebase used in type inference and translation.
public class CodebaseInfo: Codable {
    /// The current module name.
    public let moduleName: String?

    /// Target language helper.
    ///
    /// - Note: Language additions are not coded.
    var languageAdditions: CodebaseInfoLanguageAdditions?
    
    /// Supply the current module name.
    public init(moduleName: String? = nil) {
        self.moduleName = moduleName
    }
    
    /// Set dependct modules codebase info.
    ///
    /// - Note: Dependency codebase info is not encoded.
    public var dependentModules: [CodebaseInfo] = [] {
        didSet {
            assert(!isInUse)
        }
    }

    /// Messages for the user created during information gathering.
    func messages(for sourceFile: Source.FilePath) -> [Message] {
        return (messages[sourceFile] ?? []) + (languageAdditions?.messages(for: sourceFile) ?? [])
    }
    
    /// Gather codebase-level information from the given syntax tree.
    func gather(from syntaxTree: SyntaxTree) {
        assert(!isInUse)
        var needsVariableTypeInference = false
        for statement in syntaxTree.root.statements {
            switch statement.type {
            case .classDeclaration, .enumDeclaration, .protocolDeclaration, .structDeclaration:
                let typeInfo = TypeInfo(statement: statement as! TypeDeclaration, codebaseInfo: self)
                rootTypes.append(typeInfo)
                needsVariableTypeInference = needsVariableTypeInference || typeInfo.needsVariableTypeInference
            case .extensionDeclaration:
                rootExtensions.append(TypeInfo(statement: statement as! ExtensionDeclaration, codebaseInfo: self))
            case .functionDeclaration, .initDeclaration:
                rootFunctions.append(FunctionInfo(statement: statement as! FunctionDeclaration, codebaseInfo: self))
            case .typealiasDeclaration:
                rootTypealiases.append(TypealiasInfo(statement: statement as! TypealiasDeclaration, codebaseInfo: self))
            case .variableDeclaration:
                let variableInfo = VariableInfo(statement: statement as! VariableDeclaration, codebaseInfo: self)
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
        buildItemsByName() // We use this for lookups in subsequent steps
        inferVariableTypes() // May need variable types to match signatures to protocol generics
        fixupGenericsInfo()
        addGeneratedConstructors()
        buildItemsByName() // Final mappings after updates
        languageAdditions?.prepareForUse(codebaseInfo: self)
    }
    
    /// Create a context that can access the given imported modules.
    func context(importedModuleNames: [String] = [], source: Source) -> Context {
        return Context(global: self, importedModuleNames: Set(importedModuleNames), source: source)
    }

    /// The items for the given name.
    ///
    /// If this is a `.`-separated qualified type name, only returns types that match the full path.
    ///
    /// - Parameters:
    ///  - qualifiedMatch: If true, names without `.` separators will only match root types.
    func lookup(name: String, qualifiedMatch: Bool = false) -> [CodebaseInfoItem] {
        let path = name.split(separator: ".").map { String($0) }
        guard !path.isEmpty else {
            return []
        }
        var candidates = itemsByName[path[path.count - 1], default: []]
        if path.count > 1 {
            let baseName = path.dropLast().joined(separator: ".")
            candidates = candidates.filter { ($0 is TypeInfo || $0 is TypealiasInfo) && $0.declaringType?.name == baseName }
        } else if qualifiedMatch {
            candidates = candidates.filter { !($0 is TypeInfo || $0 is TypealiasInfo) || $0.declaringType == nil }
        }
        return candidates
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
        return candidateTypeNames(for: type.asOptional(false)).flatMap { name in
            let candidates = candidateMap(lookup(name: name, qualifiedMatch: true))
            return candidates.flatMap { candidate in
                if let typeInfo = candidate as? TypeInfo {
                    return [typeInfo]
                } else if let typealiasInfo = candidate as? TypealiasInfo {
                    return typeInfos(forNamed: typealiasInfo.signature, candidateMap: candidateMap, recursionDepth: recursionDepth + 1)
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
    private static let builtinProtocols: Set<TypeSignature> = [
        .named("CustomStringConvertible", []), .named("Equatable", []), .named("Error", [])
    ]
    private static let builtinEquatableSubprotocols: Set<TypeSignature> = [
        .named("Comparable", []), .named("Hashable", [])
    ]

    /// Return the protocols the given type conforms to, including inherited protocols.
    ///
    /// If the type itself is a protocol, it is included.
    func protocolSignatures(forNamed type: TypeSignature) -> [TypeSignature] {
        let type = type.asOptional(false)
        if type == .anyObject || Self.builtinProtocols.contains(type) {
            return [type]
        } else if Self.builtinEquatableSubprotocols.contains(type) {
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
        let source: Source
        private let importedModuleNames: Set<String>

        fileprivate init(global: CodebaseInfo, importedModuleNames: Set<String>, source: Source) {
            self.global = global
            self.source = source
            var importedModuleNames = importedModuleNames
            importedModuleNames.insert("SkipLib") // Contains our supported subset of the Swift builtin module
            self.importedModuleNames = importedModuleNames
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
            var score = 0
            if item.moduleName == global.moduleName {
                if let itemSourcePath = item.sourceFile?.path, itemSourcePath.hasSuffix(source.file.path) {
                    // Favor a symbol in this file
                    score += 3
                } else if item.modifiers.visibility != .private {
                    // Favor a symbol in this module
                    score += 2
                }
            } else if let itemModuleName = item.moduleName, importedModuleNames.contains(itemModuleName) {
                score += 1
            }
            return score
        }
        
        /// Return all type infos visible for the given type.
        func typeInfos(forNamed type: TypeSignature) -> [TypeInfo] {
            return global.typeInfos(forNamed: type, candidateMap: ranked)
        }

        /// Return the type info for the given type's primary declaration, omitting extensions.
        func primaryTypeInfo(forNamed type: TypeSignature) -> TypeInfo? {
            return typeInfos(forNamed: type).first { $0.declarationType != .extensionDeclaration }
        }

        /// Whether the given type is a class, struct, etc, optionally limiting results to this module.
        func declarationType(forNamed type: TypeSignature, unknownTypealiasFallback: StatementType = .classDeclaration, mustBeInModule: Bool = false) -> StatementType? {
            assert(global.kotlin != nil)
            guard let typeInfo = primaryTypeInfo(forNamed: type) else {
                guard let typealiasInfo = crossPlatformTypealias(forUnknownNamed: type) else {
                    return nil
                }
                return !mustBeInModule || typealiasInfo.moduleName == global.moduleName ? unknownTypealiasFallback : nil
            }
            if mustBeInModule && typeInfo.moduleName != global.moduleName {
                return nil
            }
            return typeInfo.declarationType
        }

        /// Cross platform library code may create typealiases to unknown types. Return any typealias for the given unknown type.
        func crossPlatformTypealias(forUnknownNamed type: TypeSignature) -> CodebaseInfo.TypealiasInfo? {
            let members = ranked(global.lookup(name: type.name, qualifiedMatch: true))
            return members.first(where: { $0.declarationType == .typealiasDeclaration }) as? CodebaseInfo.TypealiasInfo
        }
        
        /// Return the type of the given identifier.
        func identifierSignature(of identifier: String) -> (TypeSignature, Availability) {
            let topRanked = ranked(global.lookup(name: identifier, qualifiedMatch: true)).first { candidate in
                switch candidate.declarationType {
                case .classDeclaration, .enumDeclaration, .protocolDeclaration, .structDeclaration, .typealiasDeclaration, .enumCaseDeclaration, .variableDeclaration:
                    return true
                default:
                    return false
                }
            }
            guard let topRanked else {
                let type = TypeSignature.for(name: identifier, genericTypes: [], allowNamed: false).asMetaType(true)
                return (type, .available)
            }
            let type = topRanked.signature
            if let typeInfo = topRanked as? TypeInfo {
                return (type.constrainedTypeWithGenerics(typeInfo.generics).asMetaType(true), topRanked.availability)
            } else {
                return (type.asMetaType(topRanked.declarationType != .variableDeclaration && topRanked.declarationType != .enumCaseDeclaration), topRanked.availability)
            }
        }
        
        /// Return the type of the given member.
        func identifierSignature(of member: String, inConstrained type: TypeSignature, excludeConstrainedExtensions: Bool = false) -> (TypeSignature, Availability) {
            var type = type.asOptional(false)
            if case .tuple(let labels, let types) = type {
                for (index, label) in labels.enumerated() {
                    if member == label || member == "\(index)" {
                        return (types[index], .available)
                    }
                }
                return (.none, .available)
            }
            let isStatic = type.isMetaType
            type = type.asMetaType(false)

            let typeInfos = typeInfos(forNamed: type)
            let primaryTypeInfo = typeInfos.first { $0.declarationType != .extensionDeclaration }
            for typeInfo in typeInfos {
                if excludeConstrainedExtensions && typeInfo.declarationType == .extensionDeclaration, let primaryTypeInfo, typeInfo.generics != primaryTypeInfo.generics {
                    continue
                }
                let (signature, availability) = identifierSignature(of: member, in: typeInfo, constrainedGenerics: type.generics, isStatic: isStatic)
                if signature != .none {
                    return (signature.mappingSelf(to: type), availability)
                }
            }
            return (.none, .available)
        }
        
        /// Return the signatures of the possible functions being called with the given arguments.
        func functionSignature(of name: String, arguments: [LabeledValue<TypeSignature>]) -> [(TypeSignature, Availability)] {
            let items = ranked(global.lookup(name: name, qualifiedMatch: true))
            let funcs = items.filter { $0.declarationType == .functionDeclaration }
            let funcsCandidates = funcs.compactMap { matchFunction($0, arguments: arguments) }
            
            let typeInfos = items.flatMap { (item) -> [TypeInfo] in
                if let typeInfo = item as? TypeInfo {
                    return [typeInfo]
                } else if let typealiasInfo = item as? TypealiasInfo {
                    return self.typeInfos(forNamed: typealiasInfo.signature)
                } else {
                    return []
                }
            }
            let initsCandidates = initCandidates(for: typeInfos, arguments: arguments)
            let sortedCandidates = Set(funcsCandidates + initsCandidates).sorted { $0.score > $1.score }
            guard let topCandidate = sortedCandidates.first else {
                return []
            }
            return sortedCandidates.filter { $0.score >= topCandidate.score }.map { ($0.signature, $0.availability) }
        }
        
        /// Return the signatures of the possible member functions being called with the given arguments.
        ///
        /// This function also works for the creation of an enum case with associated values.
        func functionSignature(of name: String, inConstrained type: TypeSignature, arguments: [LabeledValue<TypeSignature>], excludeConstrainedExtensions: Bool = false) -> [(TypeSignature, Availability)] {
            var type = type.asOptional(false)
            if case .tuple(let labels, let types) = type {
                for (index, label) in labels.enumerated() {
                    if name == label || name == "\(index)" {
                        let function = matchTuple(types[index], arguments: arguments)
                        return [(function, .available)]
                    }
                }
                return []
            }
            let isStatic = type.isMetaType
            type = type.asMetaType(false)

            var candidates: Set<FunctionCandidate> = []
            let typeInfos = typeInfos(forNamed: type)
            let primaryTypeInfo = typeInfos.first { $0.declarationType != .extensionDeclaration }
            if name == "init" {
                initCandidates(for: typeInfos, in: primaryTypeInfo, constrainedGenerics: type.generics, arguments: arguments).forEach { candidates.insert($0) }
            } else {
                for typeInfo in typeInfos {
                    if excludeConstrainedExtensions && typeInfo.declarationType == .extensionDeclaration, let primaryTypeInfo, typeInfo.generics != primaryTypeInfo.generics {
                        continue
                    }
                    functionCandidates(for: name, in: typeInfo, constrainedGenerics: type.generics, arguments: arguments, isStatic: isStatic).forEach { candidates.insert($0) }
                }
            }
            let sortedCandidates = candidates.sorted { $0.score > $1.score }
            guard let topCandidate = sortedCandidates.first else {
                return []
            }
            return sortedCandidates.filter { $0.score >= topCandidate.score }.map { ($0.signature.mappingSelf(to: type), $0.availability) }
        }

        /// If the given function signature can be called with the given arguments, return the call signature.
        func callableSignature(of functionSignature: TypeSignature, generics: Generics? = nil, arguments: [LabeledValue<TypeSignature>]) -> TypeSignature? {
            return matchFunction(signature: functionSignature, generics: generics, availability: .available, arguments: arguments)?.signature
        }
        
        /// Return the signatures of the possible subscripts being called with the given arguments.
        func subscriptSignature(inConstrained type: TypeSignature, arguments: [LabeledValue<TypeSignature>]) -> [(TypeSignature, Availability)] {
            var type = type.asOptional(false)
            if case .array(let elementType) = type, arguments.count == 1 {
                return [(.function([TypeSignature.Parameter(type: .int)], elementType.mappingSelf(to: type)), .available)]
            } else if case .dictionary(let keyType, let valueType) = type, arguments.count == 1 {
                return [(.function([TypeSignature.Parameter(type: keyType)], valueType.mappingSelf(to: type)), .available)]
            }
            let isStatic = type.isMetaType
            type = type.asMetaType(false)

            var candidates: Set<FunctionCandidate> = []
            for typeInfo in typeInfos(forNamed: type) {
                functionCandidates(for: "subscript", in: typeInfo, constrainedGenerics: type.generics, arguments: arguments, isStatic: isStatic).forEach { candidates.insert($0) }
            }
            let sortedCandidates = candidates.sorted { $0.score > $1.score }
            guard let topCandidate = sortedCandidates.first else {
                return []
            }
            return sortedCandidates.filter { $0.score >= topCandidate.score }.map { ($0.signature, $0.availability) }
        }
        
        /// Return the associated values of the given enum case.
        func associatedValueSignatures(of member: String, inConstrained type: TypeSignature) -> [TypeSignature.Parameter] {
            let type = type.asOptional(false)
            for typeInfo in typeInfos(forNamed: type) {
                if let types = associatedValueSignatures(of: member, in: typeInfo, constrainedGenerics: type.generics) {
                    return types
                }
            }
            return []
        }
        
        private func identifierSignature(of member: String, in typeInfo: TypeInfo, constrainedGenerics: [TypeSignature], isStatic: Bool) -> (TypeSignature, Availability) {
            guard typeInfo.isApplicable(toConstrainedGenerics: constrainedGenerics, codebaseInfo: self) else {
                return (.none, .available)
            }
            // We allow .init to be used both as a static or instance member
            if let memberInfo = typeInfo.visibleMembers(context: self).first(where: { $0.name == member && ($0.declarationType == .initDeclaration || $0.isStatic == isStatic) }) {
                let availability = memberInfo.availability.least(typeInfo.availability)
                // Enum cases with associated values are modeled as functions, but can also be used as identifiers
                if memberInfo.declarationType == .enumCaseDeclaration {
                    let signature = typeInfo.signature.mappingTypes(from: typeInfo.signature.generics, to: constrainedGenerics)
                    return (signature, availability)
                } else if memberInfo is TypeInfo || memberInfo.declarationType == .typealiasDeclaration {
                    let signature = memberInfo.signature.mappingTypes(from: typeInfo.signature.generics, to: constrainedGenerics).asMetaType(true)
                    return (signature, availability)
                } else {
                    let signature = memberInfo.signature.mappingTypes(from: typeInfo.signature.generics, to: constrainedGenerics)
                    return (signature, availability)
                }
            }
            for inherits in typeInfo.inherits {
                for inheritsInfo in typeInfos(forNamed: inherits) {
                    let inheritsConstraints = inherits.mappingTypes(from: typeInfo.signature.generics, to: constrainedGenerics).generics
                    let (signature, availability) = identifierSignature(of: member, in: inheritsInfo, constrainedGenerics: inheritsConstraints, isStatic: isStatic)
                    if signature != .none {
                        return (signature, availability)
                    }
                }
            }
            return (.none, .available)
        }

        /// - Note: Returns unsorted, un-deduped results.
        private func functionCandidates(for name: String, in typeInfo: TypeInfo, constrainedGenerics: [TypeSignature], arguments: [LabeledValue<TypeSignature>], isStatic: Bool) -> [FunctionCandidate] {
            guard typeInfo.isApplicable(toConstrainedGenerics: constrainedGenerics, codebaseInfo: self) else {
                return []
            }
            var candidates = typeInfo.visibleMembers(context: self).flatMap { (member) -> [FunctionCandidate] in
                // We allow .init to be used both as a static or instance member
                guard member.name == name && (member.declarationType == .initDeclaration || member.isStatic == isStatic) else {
                    return []
                }
                switch member.declarationType {
                case .classDeclaration, .enumDeclaration, .extensionDeclaration, .structDeclaration, .typealiasDeclaration:
                    return initCandidates(for: typeInfos(forNamed: member.signature), in: typeInfo, constrainedGenerics: constrainedGenerics, arguments: arguments)
                case .functionDeclaration, .initDeclaration, .enumCaseDeclaration:
                    if let candidate = matchFunction(member, in: typeInfo, constrainedGenerics: constrainedGenerics, arguments: arguments) {
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
                    candidates += functionCandidates(for: name, in: inheritsInfo, constrainedGenerics: inheritsConstraints, arguments: arguments, isStatic: isStatic)
                }
            }
            return candidates
        }

        /// - Note: Returns unsorted, un-deduped results.
        private func initCandidates(for typeInfos: [TypeInfo], in contextTypeInfo: TypeInfo? = nil, constrainedGenerics: [TypeSignature] = [], arguments: [LabeledValue<TypeSignature>]) -> [FunctionCandidate] {
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
                let initInfos = typeInfo.visibleMembers(context: self).filter { $0.declarationType == .initDeclaration }
                return initInfos.compactMap { (initInfo: CodebaseInfoItem) -> FunctionCandidate? in
                    return matchFunction(initInfo, in: typeInfo, constrainedGenerics: typeInfoConstrainedGenerics, arguments: arguments)
                }
            }
            
            // If we don't have any matches and this appears to be a constructor, treat it as one. We take advantage of this
            // while inferring the types of variable values in prepareForUse(), before we've called generateConstructors()
            if initSignatures.isEmpty {
                let initParameters = arguments.map { TypeSignature.Parameter(label: $0.label, type: $0.value) }
                initSignatures.append(FunctionCandidate(signature: .function(initParameters, primaryTypeInfo.signature), availability: primaryTypeInfo.availability, score: 0.0))
            }
            return initSignatures
        }
        
        private func associatedValueSignatures(of member: String, in typeInfo: TypeInfo, constrainedGenerics: [TypeSignature]) -> [TypeSignature.Parameter]? {
            guard typeInfo.isApplicable(toConstrainedGenerics: constrainedGenerics, codebaseInfo: self) else {
                return nil
            }
            guard let memberInfo = typeInfo.visibleMembers(context: self).first(where: { $0.name == member && $0.declarationType == .enumCaseDeclaration }) else {
                return nil
            }
            guard case .function(let parameters, _) = memberInfo.signature else {
                return nil
            }
            return parameters.map { $0.mappingTypes(from: typeInfo.signature.generics, to: constrainedGenerics) }
        }

        private func matchTuple(_ signature: TypeSignature, arguments: [LabeledValue<TypeSignature>]) -> TypeSignature {
            guard case .function(let parameterTypes, _) = signature, parameterTypes.count == arguments.count else {
                return .none
            }
            return signature
        }
        
        private func matchFunction(_ item: CodebaseInfoItem, in typeInfo: TypeInfo? = nil, constrainedGenerics: [TypeSignature] = [], arguments: [LabeledValue<TypeSignature>]) -> FunctionCandidate? {
            let generics = (item as? FunctionInfo)?.generics
            return matchFunction(signature: item.signature, generics: generics, availability: item.availability, in: typeInfo, constrainedGenerics: constrainedGenerics, arguments: arguments)
        }

        private func matchFunction(signature: TypeSignature, generics: Generics? = nil, availability: Availability, in typeInfo: TypeInfo? = nil, constrainedGenerics: [TypeSignature] = [], arguments: [LabeledValue<TypeSignature>]) -> FunctionCandidate? {
            guard case .function(let parameters, let returnType) = signature else {
                return nil
            }
            guard parameters.count >= arguments.count else {
                return nil
            }

            // Constrain the parameters using available generic information so that we can match against them
            var constrainedParameters = parameters
            var generics = generics ?? Generics()
            var availability = availability
            if let typeInfo {
                constrainedParameters = parameters.map { $0.mappingTypes(from: typeInfo.signature.generics, to: constrainedGenerics) }
                generics = typeInfo.generics.merge(overrides: generics, addNew: true).merge(overrides: Generics(typeInfo.signature.generics, whereEqual: constrainedGenerics), addNew: true)
                availability = availability.least(typeInfo.availability)
            }
            constrainedParameters = constrainedParameters.map { $0.constrainedTypeWithGenerics(generics) }

            // Match each argument to a parameter
            var matchingParameters: [TypeSignature.Parameter] = []
            var matchingParameterIndexes: [Int] = []
            var parameterIndex = 0
            var totalScore = 0.0
            for argument in arguments {
                guard let (matchingIndex, score) = matchArgument(argument, to: constrainedParameters, startIndex: parameterIndex) else {
                    return nil
                }
                // If the parameter type was constrained (i.e. is generic), the argument value will likely be more specific
                let parameterType: TypeSignature
                if parameters[matchingIndex].type != constrainedParameters[matchingIndex].type && argument.value != .any {
                    parameterType = argument.value.or(constrainedParameters[matchingIndex].type)
                } else {
                    parameterType = constrainedParameters[matchingIndex].type.or(argument.value)
                }
                var matchingParameter = parameters[matchingIndex]
                matchingParameter.type = parameterType
                matchingParameters.append(matchingParameter)
                matchingParameterIndexes.append(matchingIndex)
                parameterIndex = matchingIndex + 1
                totalScore += score
            }
            // Make sure there are no more required parameters
            if parameterIndex < parameters.count {
                if parameters[parameterIndex...].contains(where: { !$0.hasDefaultValue }) {
                    return nil
                }
            }

            // Apply the generic types we determined from parameter matching and the given constraint information to the return type
            let matchingGenerics = signature.mergeGenericMappings(in: .function(matchingParameters, returnType), with: generics)
            let constrainedReturnType = returnType.constrainedTypeWithGenerics(matchingGenerics)
            return FunctionCandidate(signature: .function(matchingParameters, constrainedReturnType), availability: availability, score: totalScore)
        }

        private func matchArgument(_ argument: LabeledValue<TypeSignature>, to parameters: [TypeSignature.Parameter], startIndex: Int) -> (index: Int, score: Double)? {
            // Note: in the algorith below we give an extra point for matching a label (or absence of one), as opposed to
            // being a trailing closure that omits the label
            for (index, parameter) in parameters[startIndex...].enumerated() {
                if let label = argument.label {
                    // If there is a label, then it either has to match or we have to be able to skip this parameter
                    if label == parameter.label, let score = argument.value.compatibilityScore(target: parameter.type, codebaseInfo: self) {
                        return (startIndex + index, 1.0 + score)
                    } else if !parameter.hasDefaultValue {
                        return nil
                    }
                } else {
                    // If there is no label, then either this parameter has to have no label or it has to be a trailing closure
                    if parameter.label == nil, let score = argument.value.compatibilityScore(target: parameter.type, codebaseInfo: self) {
                        return (startIndex + index, 1.0 + score)
                    } else if case .function = parameter.type, let score = argument.value.compatibilityScore(target: parameter.type, codebaseInfo: self) {
                        return (startIndex + index, score)
                    } else if !parameter.hasDefaultValue {
                        return nil
                    }
                }
            }
            return nil
        }
    }

    private func candidateTypeNames(for type: TypeSignature) -> [String] {
        switch type {
        case .array:
            return ["Array"]
        case .composition(let types):
            return types.flatMap { candidateTypeNames(for: $0) }
        case .dictionary:
            return ["Dictionary"]
        case .function:
            return []
        case .member(let base, let type):
            let typeNames = candidateTypeNames(for: type)
            let baseName = base.name
            return typeNames.map { "\(baseName).\($0)" }
        case .metaType(let type):
            return candidateTypeNames(for: type)
        case .named(let name, _):
            return [name]
        case .none:
            return []
        case .optional(let type):
            return candidateTypeNames(for: type)
        case .set:
            return ["Set"]
        case .unwrappedOptional(let type):
            return candidateTypeNames(for: type)
        case .void:
            return []
        default:
            return [type.name]
        }
    }

    private struct FunctionCandidate: Hashable {
        let signature: TypeSignature
        let availability: Availability
        let score: Double

        static func ==(lhs: FunctionCandidate, rhs: FunctionCandidate) -> Bool {
            return lhs.signature == rhs.signature
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(signature)
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
    
    private enum CodingKeys: String, CodingKey {
        // Only encode moduleName and root infos
        case moduleName, rootTypes, rootTypealiases, rootVariables, rootFunctions, rootExtensions
    }
    
    private func buildItemsByName() {
        var itemsByName: [String: [CodebaseInfoItem]] = [:]
        Self.addCodebaseInfo(self, to: &itemsByName)
        dependentModules.forEach { Self.addCodebaseInfo($0, to: &itemsByName, publicOnly: true) }
        self.itemsByName = itemsByName
    }
    
    private static func addCodebaseInfo(_ info: CodebaseInfo, to itemsByName: inout [String: [CodebaseInfoItem]], publicOnly: Bool = false) {
        info.rootTypes.forEach { addTypeInfo($0, to: &itemsByName, publicOnly: publicOnly) }
        info.rootExtensions.forEach { addTypeInfo($0, to: &itemsByName, publicOnly: publicOnly) }
        let rootItems: [CodebaseInfoItem] = info.rootTypealiases + info.rootVariables + info.rootFunctions
        rootItems.forEach { addItem($0, to: &itemsByName, publicOnly: publicOnly) }
    }
    
    private static func addTypeInfo(_ typeInfo: TypeInfo, to itemsByName: inout [String: [CodebaseInfoItem]], publicOnly: Bool) {
        if publicOnly {
            guard typeInfo.modifiers.visibility == .public || typeInfo.modifiers.visibility == .open || typeInfo.declarationType == .extensionDeclaration else {
                return
            }
            typeInfo.types = typeInfo.types.filter { $0.modifiers.visibility == .public || $0.modifiers.visibility == .open }
            typeInfo.typealiases = typeInfo.typealiases.filter { $0.modifiers.visibility == .public || $0.modifiers.visibility == .open }
            typeInfo.variables = typeInfo.variables.filter { $0.modifiers.visibility == .public || $0.modifiers.visibility == .open }
            typeInfo.functions = typeInfo.functions.filter { $0.modifiers.visibility == .public || $0.modifiers.visibility == .open }
            // If this was an extension that is now empty, don't add it
            guard typeInfo.declarationType != .extensionDeclaration || !typeInfo.types.isEmpty || !typeInfo.typealiases.isEmpty || !typeInfo.variables.isEmpty || !typeInfo.functions.isEmpty else {
                return
            }
        }
        addItem(typeInfo, to: &itemsByName, publicOnly: false) // Already filtered
        typeInfo.types.forEach { addTypeInfo($0, to: &itemsByName, publicOnly: publicOnly) }
        let items: [CodebaseInfoItem] = typeInfo.typealiases + typeInfo.cases + typeInfo.variables + typeInfo.functions
        items.forEach { addItem($0, to: &itemsByName, publicOnly: false) } // Already filtered
    }
    
    private static func addItem(_ item: CodebaseInfoItem, to itemsByName: inout [String: [CodebaseInfoItem]], publicOnly: Bool) {
        guard !publicOnly || item.modifiers.visibility == .public || item.modifiers.visibility == .open else {
            return
        }
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
            let inheritGenerics = inheritInfo.generics.merge(overrides: protocolInfo.generics)
            protocolGenerics = protocolGenerics.merge(overrides: inheritInfo.generics, addNew: true)
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
            return inherit.withGenerics(protocolGenerics(for: inheritInfo, in: typeInfo))
        }
        for member in typeInfo.members {
            if let memberTypeInfo = member as? TypeInfo {
                fixupProtocolConformanceGenerics(in: memberTypeInfo)
            }
        }
    }

    private func protocolGenerics(for protocolInfo: TypeInfo, in typeInfo: TypeInfo) -> [TypeSignature] {
        var mappings = protocolInfo.signature.generics.reduce(into: [TypeSignature: TypeSignature]()) { result, generic in
            result[generic] = generic
        }
        for typealiasInfo in typeInfo.typealiases {
            let generic: TypeSignature = .named(typealiasInfo.name, [])
            if mappings.keys.contains(generic) {
                mappings[generic] = typealiasInfo.signature
            }
        }
        let unmapped = mappings.keys.filter { mappings[$0] == $0 }
        if !unmapped.isEmpty {
            // Use the type's members to collection generic mappings
            var generics = Generics(unmapped)
            for protocolInfo in protocolSignatures(forNamed: protocolInfo.signature).compactMap({ primaryTypeInfo(forNamed: $0) }) {
                for protocolMember in protocolInfo.members {
                    if let typeMember = findImplementingMember(in: typeInfo, for: protocolMember) {
                        generics = protocolMember.signature.mergeGenericMappings(in: typeMember.signature, with: generics)
                    }
                }
            }
            for entry in generics.entries {
                if let whereEqual = entry.whereEqual {
                    mappings[entry.namedType] = whereEqual
                }
            }
        }
        return protocolInfo.signature.generics.map { mappings[$0] ?? $0 }
    }

    private func findImplementingMember(in typeInfo: TypeInfo, for protocolMember: CodebaseInfoItem) -> CodebaseInfoItem? {
        if let variableInfo = protocolMember as? VariableInfo {
            return typeInfo.variables.first { $0.name == variableInfo.name }
        } else if let functionInfo = protocolMember as? FunctionInfo {
            return typeInfo.functions.first {
                guard functionInfo.name == $0.name else {
                    return false
                }
                return functionInfo.signature.parameters.map(\.label) == $0.signature.parameters.map(\.label)
            }
        } else {
            return nil
        }
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
                    context = TypeInferenceContext(codebaseInfo: self, unavailableAPI: nil, source: syntaxTree.source, statements: syntaxTree.root.statements)
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
                for rootType in rootTypes {
                    if rootType.sourceFile == sourceFile && rootType.needsVariableTypeInference {
                        if isCleanupPass {
                            rootType.cleanupTypeInference(source: syntaxTree.source, messages: &messages)
                        } else if let declaration = syntaxTree.root.statements.first(where: { ($0 as? TypeDeclaration)?.name == rootType.name }) as? TypeDeclaration {
                            needsInferenceCount += rootType.inferVariableTypes(with: context, declaration: declaration)
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

    private func addGeneratedConstructors() {
        rootTypes.forEach { addGeneratedConstructors(to: $0) }
    }

    private func addGeneratedConstructors(to typeInfo: TypeInfo) {
        // Handle nested types
        typeInfo.types.forEach { addGeneratedConstructors(to: $0) }
        guard typeInfo.declarationType == .classDeclaration || typeInfo.declarationType == .structDeclaration else {
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
                inheritInit.signature = inheritInit.signature.mappingTypes(from: inheritGenerics, to: targetGenerics)
                inheritInit.isGenerated = true
                typeInfo.functions.append(inheritInit)
            }
        }
    }

    private func addMemberwiseConstructor(to typeInfo: TypeInfo) {
        let parameters = typeInfo.variables.compactMap { (variable) -> TypeSignature.Parameter? in
            guard variable.isInitializable else {
                return nil
            }
            return TypeSignature.Parameter(label: variable.name, type: variable.signature, hasDefaultValue: variable.hasValue)
        }
        let initSignature: TypeSignature = .function(parameters, typeInfo.signature)
        var initInfo = FunctionInfo(name: "init", declarationType: .initDeclaration, signature: initSignature, moduleName: typeInfo.moduleName, sourceFile: typeInfo.sourceFile, declaringType: typeInfo.signature, modifiers: typeInfo.modifiers, availability: .available)
        initInfo.isGenerated = true
        typeInfo.functions.append(initInfo)
    }

    /// Information about a declared type.
    ///
    /// - Note: Unlike the other `CodebaseInfoItem` datastructures, types are modeled as `class` instances so that we can mutate them in place.
    class TypeInfo: CodebaseInfoItem, Codable {
        let name: String
        let declarationType: StatementType
        var signature: TypeSignature
        let moduleName: String?
        let sourceFile: Source.FilePath?
        let declaringType: TypeSignature?
        let modifiers: Modifiers
        let availability: Availability
        var isStatic: Bool {
            return true
        }
        var languageAdditions: Any?

        var generics: Generics
        var inherits: [TypeSignature]

        var types: [TypeInfo] = []
        var typealiases: [TypealiasInfo] = []
        var cases: [EnumCaseInfo] = []
        var variables: [VariableInfo] = []
        var functions: [FunctionInfo] = []
        var members: [CodebaseInfoItem] {
            return types + typealiases + cases + variables + functions
        }

        func visibleMembers(context: CodebaseInfo.Context) -> [CodebaseInfoItem] {
            return members.filter { context.rankScore(of: $0) > 0 }
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
            // Exclude language additions
            case name, declarationType, signature, moduleName, sourceFile, declaringType, modifiers, availability, generics, inherits, types, typealiases, cases, variables, functions
        }

        fileprivate init(statement: TypeDeclaration, in declaringType: TypeSignature? = nil, codebaseInfo: CodebaseInfo) {
            self.name = statement.name
            self.declarationType = statement.type
            self.signature = statement.signature
            self.moduleName = codebaseInfo.moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.modifiers = statement.modifiers
            self.availability = Availability(attributes: statement.attributes)
            self.generics = statement.generics
            self.inherits = statement.inherits
            addMembers(statement.members, codebaseInfo: codebaseInfo)
            (codebaseInfo.languageAdditions as? CodebaseInfoLanguageAdditionsGatherDelegate)?.codebaseInfo(codebaseInfo, didGather: self, from: statement)
        }

        fileprivate init(statement: ExtensionDeclaration, codebaseInfo: CodebaseInfo) {
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
            self.availability = Availability(attributes: statement.attributes)
            self.generics = statement.generics
            self.inherits = statement.inherits
            addMembers(statement.members, codebaseInfo: codebaseInfo)
            (codebaseInfo.languageAdditions as? CodebaseInfoLanguageAdditionsGatherDelegate)?.codebaseInfo(codebaseInfo, didGather: self, from: statement)
        }

        fileprivate var needsVariableTypeInference: Bool {
            return variables.contains { $0.needsTypeInference } || types.contains { $0.needsVariableTypeInference }
        }

        fileprivate func inferVariableTypes(with context: TypeInferenceContext, declaration: TypeDeclaration) -> Int {
            let memberContext = context.pushing(declaration)
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
                if let declaration = declaration.members.first(where: { ($0 as? TypeDeclaration)?.name == type.name }) as? TypeDeclaration {
                    needsInferenceCount += type.inferVariableTypes(with: memberContext, declaration: declaration)
                }
            }
            return needsInferenceCount
        }

        fileprivate func cleanupTypeInference(source: Source, messages: inout [Source.FilePath: [Message]]) {
            variables = variables.map { $0.cleanupTypeInference(source: source, messages: &messages) }
            types.forEach { $0.cleanupTypeInference(source: source, messages: &messages) }
        }

        private func addMembers(_ statements: [Statement], codebaseInfo: CodebaseInfo) {
            for statement in statements {
                switch statement.type {
                case .classDeclaration, .enumDeclaration, .structDeclaration:
                    types.append(TypeInfo(statement: statement as! TypeDeclaration, in: signature, codebaseInfo: codebaseInfo))
                case .enumCaseDeclaration:
                    cases.append(EnumCaseInfo(statement: statement as! EnumCaseDeclaration, in: signature, codebaseInfo: codebaseInfo))
                case .functionDeclaration, .initDeclaration:
                    functions.append(FunctionInfo(statement: statement as! FunctionDeclaration, in: signature, codebaseInfo: codebaseInfo))
                case .typealiasDeclaration:
                    typealiases.append(TypealiasInfo(statement: statement as! TypealiasDeclaration, in: signature, codebaseInfo: codebaseInfo))
                case .variableDeclaration:
                    variables.append(VariableInfo(statement: statement as! VariableDeclaration, in: signature, codebaseInfo: codebaseInfo))
                default:
                    break
                }
            }
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
        let sourceFile: Source.FilePath?
        let declaringType: TypeSignature?
        let modifiers: Modifiers
        let availability: Availability
        var isStatic: Bool {
            return modifiers.isStatic
        }
        var languageAdditions: Any?

        let isReadOnly: Bool
        let isInitializable: Bool
        let hasValue: Bool
        var value: Expression?

        private enum CodingKeys: String, CodingKey {
            // Exclude value expression, language additions
            case name, signature, moduleName, sourceFile, declaringType, modifiers, availability, isReadOnly, isInitializable, hasValue
        }

        fileprivate init(statement: VariableDeclaration, in declaringType: TypeSignature? = nil, codebaseInfo: CodebaseInfo) {
            self.name = (statement.names.first ?? "") ?? ""
            self.signature = statement.variableTypes.first ?? .none
            self.moduleName = codebaseInfo.moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.modifiers = statement.modifiers
            self.availability = Availability(attributes: statement.attributes)
            self.isReadOnly = statement.isLet || (statement.getter != nil && statement.setter == nil)
            self.isInitializable = !statement.modifiers.isStatic && statement.getter == nil && (!statement.isLet || statement.value == nil)
            self.hasValue = self.signature.isOptional || statement.value != nil
            if !self.signature.isFullySpecified, self.sourceFile != nil {
                // We'll try to infer the type after gathering all info
                self.value = statement.value
            }
            (codebaseInfo.languageAdditions as? CodebaseInfoLanguageAdditionsGatherDelegate)?.codebaseInfo(codebaseInfo, didGather: &self, from: statement)
        }

        fileprivate var needsTypeInference: Bool {
            return value != nil
        }

        fileprivate func inferType(with context: TypeInferenceContext) -> VariableInfo {
            var v = self
            guard let value = v.value else {
                return v
            }
            value.inferTypes(context: context, expecting: .none)
            v.signature = value.inferredType
            if v.signature.isFullySpecified {
                v.value = nil
            }
            return v
        }

        fileprivate func cleanupTypeInference(source: Source, messages: inout [Source.FilePath: [Message]]) -> VariableInfo {
            guard value != nil else {
                return self
            }
            if let sourceFile {
                var fileMessages = messages[sourceFile, default: []]
                fileMessages.append(.variableNeedsTypeDeclaration(value!, source: source))
                messages[sourceFile] = fileMessages
            }
            var v = self
            v.value = nil
            return v
        }
    }

    /// Information about a declared function.
    struct FunctionInfo: CodebaseInfoItem, Codable {
        let name: String
        let declarationType: StatementType
        var signature: TypeSignature
        var moduleName: String?
        var sourceFile: Source.FilePath?
        var declaringType: TypeSignature?
        let modifiers: Modifiers
        let availability: Availability
        var isStatic: Bool {
            return modifiers.isStatic
        }
        var languageAdditions: Any?

        let generics: Generics
        let isMutating: Bool
        var isGenerated = false

        private enum CodingKeys: String, CodingKey {
            // Exclude language additions
            case name, declarationType, signature, moduleName, sourceFile, declaringType, modifiers, availability, generics, isMutating, isGenerated
        }

        fileprivate init(statement: FunctionDeclaration, in declaringType: TypeSignature? = nil, codebaseInfo: CodebaseInfo) {
            self.name = statement.name
            self.declarationType = statement.type
            self.signature = statement.functionType
            self.moduleName = codebaseInfo.moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.modifiers = statement.modifiers
            self.availability = Availability(attributes: statement.attributes)
            self.generics = statement.generics
            self.isMutating = statement.modifiers.isMutating
            (codebaseInfo.languageAdditions as? CodebaseInfoLanguageAdditionsGatherDelegate)?.codebaseInfo(codebaseInfo, didGather: &self, from: statement)
        }

        fileprivate init(name: String, declarationType: StatementType, signature: TypeSignature, moduleName: String?, sourceFile: Source.FilePath? = nil, declaringType: TypeSignature? = nil, modifiers: Modifiers, availability: Availability, generics: Generics = Generics(), isMutating: Bool = false) {
            self.name = name
            self.declarationType = declarationType
            self.signature = signature
            self.moduleName = moduleName
            self.sourceFile = sourceFile
            self.declaringType = declaringType
            self.modifiers = modifiers
            self.availability = availability
            self.generics = generics
            self.isMutating = isMutating
        }
    }

    /// Information about a typealias.
    struct TypealiasInfo: CodebaseInfoItem, Codable {
        let name: String
        var declarationType: StatementType {
            return .typealiasDeclaration
        }
        let signature: TypeSignature
        let moduleName: String?
        let sourceFile: Source.FilePath?
        let declaringType: TypeSignature?
        let modifiers: Modifiers
        let availability: Availability
        var isStatic: Bool {
            return true
        }
        var languageAdditions: Any?

        let generics: Generics

        private enum CodingKeys: String, CodingKey {
            // Exclude language additions
            case name, signature, moduleName, sourceFile, declaringType, modifiers, availability, generics
        }

        fileprivate init(statement: TypealiasDeclaration, in declaringType: TypeSignature? = nil, codebaseInfo: CodebaseInfo) {
            self.name = statement.name
            self.signature = statement.aliasedType
            self.moduleName = codebaseInfo.moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.modifiers = statement.modifiers
            self.availability = Availability(attributes: statement.attributes)
            self.generics = statement.generics
            (codebaseInfo.languageAdditions as? CodebaseInfoLanguageAdditionsGatherDelegate)?.codebaseInfo(codebaseInfo, didGather: &self, from: statement)
        }
    }

    /// Information about an enum case.
    struct EnumCaseInfo: CodebaseInfoItem, Codable {
        let name: String
        var declarationType: StatementType {
            return .enumCaseDeclaration
        }
        let signature: TypeSignature // Owning enum or a function returning the owning enum
        let moduleName: String?
        let sourceFile: Source.FilePath?
        let declaringType: TypeSignature?
        let modifiers: Modifiers
        let availability: Availability
        var isStatic: Bool {
            return true
        }
        var languageAdditions: Any?

        private enum CodingKeys: String, CodingKey {
            // Exclude language additions
            case name, signature, moduleName, sourceFile, declaringType, modifiers, availability
        }

        fileprivate init(statement: EnumCaseDeclaration, in declaringType: TypeSignature? = nil, codebaseInfo: CodebaseInfo) {
            self.name = statement.name
            self.signature = statement.signature
            self.moduleName = codebaseInfo.moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.modifiers = statement.modifiers
            self.availability = Availability(attributes: statement.attributes)
            (codebaseInfo.languageAdditions as? CodebaseInfoLanguageAdditionsGatherDelegate)?.codebaseInfo(codebaseInfo, didGather: &self, from: statement)
        }
    }

    /// Availability information.
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
}

/// Common protocol for all codebase info items.
protocol CodebaseInfoItem {
    var name: String { get }
    var declarationType: StatementType { get }
    var signature: TypeSignature { get }
    var moduleName: String? { get }
    var sourceFile: Source.FilePath? { get }
    var declaringType: TypeSignature? { get }
    var modifiers: Modifiers { get }
    var availability: CodebaseInfo.Availability { get }
    var isStatic: Bool { get }
    var languageAdditions: Any? { get set }
}

/// Helper to track target language additions.
protocol CodebaseInfoLanguageAdditions {
    /// Any issues encountered during information gathering.
    func messages(for sourceFile: Source.FilePath) -> [Message]

    /// Prepare language additions for use.
    func prepareForUse(codebaseInfo: CodebaseInfo)
}

/// Optional protocol the `CodebaseInfoLanguageAdditions` can implement to receive info gathering callbacks.
protocol CodebaseInfoLanguageAdditionsGatherDelegate {
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGatherFrom syntaxTree: SyntaxTree)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typeInfo: CodebaseInfo.TypeInfo, from statement: TypeDeclaration)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typeInfo: CodebaseInfo.TypeInfo, from statement: ExtensionDeclaration)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather variableInfo: inout CodebaseInfo.VariableInfo, from statement: VariableDeclaration)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather functionInfo: inout CodebaseInfo.FunctionInfo, from statement: FunctionDeclaration)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typealiasInfo: inout CodebaseInfo.TypealiasInfo, from statement: TypealiasDeclaration)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather enumCaseInfo: inout CodebaseInfo.EnumCaseInfo, from statement: EnumCaseDeclaration)
}

extension CodebaseInfoLanguageAdditionsGatherDelegate {
    func messages(for sourceFile: Source.FilePath) -> [Message] {
        return []
    }

    func prepareForUse(codebaseInfo: CodebaseInfo) {
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGatherFrom syntaxTree: SyntaxTree) {
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typeInfo: CodebaseInfo.TypeInfo, from statement: TypeDeclaration) {
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typeInfo: CodebaseInfo.TypeInfo, from statement: ExtensionDeclaration) {
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather variableInfo: inout CodebaseInfo.VariableInfo, from statement: VariableDeclaration) {
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather functionInfo: inout CodebaseInfo.FunctionInfo, from statement: FunctionDeclaration) {
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typealiasInfo: inout CodebaseInfo.TypealiasInfo, from statement: TypealiasDeclaration) {
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather enumCaseInfo: inout CodebaseInfo.EnumCaseInfo, from statement: EnumCaseDeclaration) {
    }
}
