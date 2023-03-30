/// Codable information about the codebase used in type inference and translation.
public class CodebaseInfo: Codable {
    /// The current module name.
    public let moduleName: String?
    
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
        return messages[sourceFile] ?? []
    }
    
    /// Gather codebase-level information from the given syntax tree.
    func gather(from syntaxTree: SyntaxTree, delegate: CodebaseInfoGatherDelegate? = nil) {
        assert(!isInUse)
        var needsVariableTypeInference = false
        for statement in syntaxTree.root.statements {
            switch statement.type {
            case .classDeclaration, .enumDeclaration, .protocolDeclaration, .structDeclaration:
                let typeInfo = TypeInfo(statement: statement as! TypeDeclaration, codebaseInfo: self, delegate: delegate)
                rootTypes.append(typeInfo)
                needsVariableTypeInference = needsVariableTypeInference || typeInfo.needsVariableTypeInference
            case .extensionDeclaration:
                rootExtensions.append(TypeInfo(statement: statement as! ExtensionDeclaration, codebaseInfo: self, delegate: delegate))
            case .functionDeclaration, .initDeclaration:
                rootFunctions.append(FunctionInfo(statement: statement as! FunctionDeclaration, codebaseInfo: self, delegate: delegate))
            case .typealiasDeclaration:
                rootTypealiases.append(TypealiasInfo(statement: statement as! TypealiasDeclaration, codebaseInfo: self, delegate: delegate))
            case .variableDeclaration:
                let variableInfo = VariableInfo(statement: statement as! VariableDeclaration, codebaseInfo: self, delegate: delegate)
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
    }
    
    /// Finalize codebase info and prepare for use.
    ///
    /// - Warning: Codebase info should not be used until this has been called. After calling this function, do not mutate info.
    func prepareForUse() {
        isInUse = true
        buildItemsByName() // We use this for lookups in subsequent steps
        inferVariableTypes()
        addGeneratedConstructors()
        buildItemsByName() // Final mappings after updates
    }
    
    /// Create a context that can access the given imported modules.
    func context(importedModuleNames: [String] = [], source: Source) -> Context {
        return Context(codebaseInfo: self, importedModuleNames: Set(importedModuleNames), source: source)
    }
    
    /// A context for accessing visible codebase information.
    struct Context {
        let codebaseInfo: CodebaseInfo
        let source: Source
        private let importedModuleNames: Set<String>

        fileprivate init(codebaseInfo: CodebaseInfo, importedModuleNames: Set<String>, source: Source) {
            self.codebaseInfo = codebaseInfo
            self.source = source
            var importedModuleNames = importedModuleNames
            importedModuleNames.insert("SkipLib") // Contains our supported subset of the Swift builtin module
            self.importedModuleNames = importedModuleNames
        }
        
        /// The items for the given name.
        ///
        /// If this is a `.`-separated qualified type name, only returns types that match the full path.
        ///
        /// - Parameters:
        ///  - qualifiedMatch: If true, names without `.` separators will only match root types.
        /// - Warning: This function does not take symbol visibility into account. See `ranked`.
        func lookup(name: String, qualifiedMatch: Bool = false) -> [CodebaseInfoItem] {
            let path = name.split(separator: ".").map { String($0) }
            guard !path.isEmpty else {
                return []
            }
            var candidates = codebaseInfo.itemsByName[path[path.count - 1], default: []]
            if path.count > 1 {
                let baseName = path.dropLast().joined(separator: ".")
                candidates = candidates.filter { ($0 is TypeInfo || $0 is TypealiasInfo) && $0.declaringType?.name == baseName }
            } else if qualifiedMatch {
                candidates = candidates.filter { !($0 is TypeInfo || $0 is TypealiasInfo) || $0.declaringType == nil }
            }
            return candidates
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
            if item.moduleName == codebaseInfo.moduleName {
                if let itemSourcePath = item.sourceFile?.path, itemSourcePath.hasSuffix(source.file.path) {
                    // Favor a symbol in this file
                    score += 3
                } else if item.modifiers.visibility != .private {
                    // Favor a symbol in this module
                    score += 2
                }
            } else if let itemModuleName = item.moduleName, importedModuleNames.contains(itemModuleName) && (item.modifiers.visibility == .public || item.modifiers.visibility == .open) {
                score += 1
            }
            return score
        }
        
        /// Return all type infos visible for the given type.
        func typeInfos(for type: TypeSignature) -> [TypeInfo] {
            return candidateTypeNames(for: type.asOptional(false)).flatMap { name in
                let candidates = ranked(lookup(name: name, qualifiedMatch: true))
                return candidates.flatMap { candidate in
                    if let typeInfo = candidate as? TypeInfo {
                        return [typeInfo]
                    } else if let typealiasInfo = candidate as? TypealiasInfo {
                        return typeInfos(for: typealiasInfo.signature)
                    } else {
                        return []
                    }
                }
            }
        }

        /// Return the concrete (i.e. non-protocol inheritance chain for the given type. The type will be first, followed by its superclass, etc.
        func inheritanceChainSignatures(for type: TypeSignature) -> [TypeSignature] {
            guard let concreteTypeInfo = typeInfos(for: type).first(where: { $0.declarationType != .protocolDeclaration && $0.declarationType != .extensionDeclaration }) else {
                return []
            }
            guard concreteTypeInfo.declarationType == .classDeclaration, let firstInherits = concreteTypeInfo.inherits.first else {
                return [concreteTypeInfo.signature]
            }
            //~~~ Need to map generics
            return [concreteTypeInfo.signature] + inheritanceChainSignatures(for: firstInherits)
        }

        /// Return the protocols the given type conforms to, including inherited protocols. If the type itself is a protocol, it is included.
        func protocolSignatures(for type: TypeSignature) -> [TypeSignature] {
            // Gather inherited signatures, then insert the given type at the front if it is also a protocol
            let type = type.asOptional(false)
            let typeInfos = typeInfos(for: type)
            //~~~ Need to map generics
            var signatures = typeInfos.flatMap { $0.inherits.flatMap { protocolSignatures(for: $0) } }
            // TODO: Remove special case for Error when we add SkipLib codebase info dependency
            if type == .anyObject || type == .named("Error", []) || typeInfos.contains(where: { $0.declarationType == .protocolDeclaration }) {
                signatures.insert(type, at: 0)
            }
            return signatures
        }
        
        /// Return the type of the given identifier.
        func identifierSignature(of identifier: String) -> TypeSignature {
            let topRanked = ranked(lookup(name: identifier, qualifiedMatch: true)).first { candidate in
                switch candidate.declarationType {
                case .classDeclaration, .enumDeclaration, .protocolDeclaration, .structDeclaration, .typealiasDeclaration, .enumCaseDeclaration, .variableDeclaration:
                    return true
                default:
                    return false
                }
            }
            guard let topRanked else {
                return .none
            }
            let type = topRanked.signature
            return topRanked.declarationType == .variableDeclaration || topRanked.declarationType == .enumCaseDeclaration ? type : .metaType(type)
        }
        
        /// Return the type of the given member.
        func identifierSignature(of member: String, in type: TypeSignature) -> TypeSignature {
            var type = type.asOptional(false)
            if case .tuple(let labels, let types) = type {
                for (index, label) in labels.enumerated() {
                    if member == label || member == "\(index)" {
                        return types[index]
                    }
                }
                return .none
            }
            var isStatic = false
            if case .metaType(let base) = type {
                type = base
                isStatic = true
            }
            for typeInfo in typeInfos(for: type) {
                let type = identifierSignature(of: member, in: typeInfo, isStatic: isStatic)
                if type != .none {
                    return type
                }
            }
            return .none
        }
        
        /// Return the signatures of the possible functions being called with the given arguments.
        func functionSignature(of name: String, arguments: [LabeledValue<TypeSignature>]) -> [TypeSignature] {
            let items = ranked(lookup(name: name, qualifiedMatch: true))
            let funcs = items.filter { $0.declarationType == .functionDeclaration || $0.declarationType == .initDeclaration }
            let funcsCandidates = funcs.compactMap { matchFunction($0, arguments: arguments) }
            
            let typeInfos = items.flatMap { (item) -> [TypeInfo] in
                if let typeInfo = item as? TypeInfo {
                    return [typeInfo]
                } else if let typealiasInfo = item as? TypealiasInfo {
                    return self.typeInfos(for: typealiasInfo.signature)
                } else {
                    return []
                }
            }
            let initsCandidates = initCandidates(for: typeInfos, arguments: arguments)
            let sortedCandidates = Set(funcsCandidates + initsCandidates).sorted { $0.score > $1.score }
            guard let topCandidate = sortedCandidates.first else {
                return []
            }
            // Return all matches with the top score
            return sortedCandidates.filter { $0.score >= topCandidate.score }.map(\.signature)
        }
        
        /// Return the signatures of the possible member functions being called with the given arguments.
        ///
        /// This function also works for the creation of an enum case with associated values.
        func functionSignature(of name: String, in type: TypeSignature, arguments: [LabeledValue<TypeSignature>]) -> [TypeSignature] {
            var type = type.asOptional(false)
            if case .tuple(let labels, let types) = type {
                for (index, label) in labels.enumerated() {
                    if name == label || name == "\(index)" {
                        let function = matchTuple(types[index], arguments: arguments)
                        return function == .none ? [] : [function]
                    }
                }
                return []
            }
            var isStatic = false
            if case .metaType(let base) = type {
                type = base
                isStatic = true
            }

            var candidates: Set<FunctionCandidate> = []
            for typeInfo in typeInfos(for: type) {
                functionCandidates(for: name, in: typeInfo, arguments: arguments, isStatic: isStatic).forEach { candidates.insert($0) }
            }
            let sortedCandidates = candidates.sorted { $0.score > $1.score }
            guard let topCandidate = sortedCandidates.first else {
                return []
            }
            // Return all matches with the top score
            return sortedCandidates.filter { $0.score >= topCandidate.score }.map(\.signature)
        }
        
        /// Return the signatures of the possible subscripts being called with the given arguments.
        func subscriptSignature(in type: TypeSignature, arguments: [LabeledValue<TypeSignature>]) -> [TypeSignature] {
            var type = type.asOptional(false)
            if case .array(let elementType) = type, arguments.count == 1 {
                return [.function([TypeSignature.Parameter(type: .int)], elementType)]
            } else if case .dictionary(let keyType, let valueType) = type, arguments.count == 1 {
                return [.function([TypeSignature.Parameter(type: keyType)], valueType)]
            }
            var isStatic = false
            if case .metaType(let base) = type {
                type = base
                isStatic = true
            }

            var candidates: Set<FunctionCandidate> = []
            for typeInfo in typeInfos(for: type) {
                functionCandidates(for: "subscript", in: typeInfo, arguments: arguments, isStatic: isStatic).forEach { candidates.insert($0) }
            }
            let sortedCandidates = candidates.sorted { $0.score > $1.score }
            guard let topCandidate = sortedCandidates.first else {
                return []
            }
            // Return all matches with the top score
            return sortedCandidates.filter { $0.score >= topCandidate.score }.map(\.signature)
        }
        
        /// Return the associated values of the given enum case.
        func associatedValueSignatures(of member: String, in type: TypeSignature) -> [TypeSignature.Parameter] {
            let type = type.asOptional(false)
            for typeInfo in typeInfos(for: type) {
                if let types = associatedValueSignatures(of: member, in: typeInfo) {
                    return types
                }
            }
            return []
        }
        
        private func identifierSignature(of member: String, in typeInfo: TypeInfo, isStatic: Bool) -> TypeSignature {
            // We allow .init to be used both as a static or instance member
            if let memberInfo = typeInfo.visibleMembers(context: self).first(where: { $0.name == member && ($0.declarationType == .initDeclaration || $0.isStatic == isStatic) }) {
                // Enum cases with associated values are modeled as functions, but can also be used as identifiers
                if memberInfo.declarationType == .enumCaseDeclaration {
                    return memberInfo.declaringType ?? .none
                } else if memberInfo is TypeInfo || memberInfo.declarationType == .typealiasDeclaration {
                    return .metaType(memberInfo.signature)
                } else {
                    return memberInfo.signature
                }
            }
            for inherits in typeInfo.inherits {
                for inheritsInfo in typeInfos(for: inherits) {
                    let signature = identifierSignature(of: member, in: inheritsInfo, isStatic: isStatic)
                    if signature != .none {
                        return signature
                    }
                }
            }
            return .none
        }

        /// - Note: Returns unsorted, un-deduped results.
        private func functionCandidates(for name: String, in typeInfo: TypeInfo, arguments: [LabeledValue<TypeSignature>], isStatic: Bool) -> [FunctionCandidate] {
            var candidates = typeInfo.visibleMembers(context: self).flatMap { (member) -> [FunctionCandidate] in
                // We allow .init to be used both as a static or instance member
                guard member.name == name && (member.declarationType == .initDeclaration || member.isStatic == isStatic) else {
                    return []
                }
                if let memberTypeInfo = member as? TypeInfo {
                    return initCandidates(for: [memberTypeInfo], arguments: arguments)
                } else if member.declarationType == .typealiasDeclaration {
                    return initCandidates(for: typeInfos(for: member.signature), arguments: arguments)
                } else if let candidate = matchFunction(member, arguments: arguments) {
                    return [candidate]
                } else {
                    return []
                }
            }
            for inherits in typeInfo.inherits {
                for inheritsInfo in typeInfos(for: inherits) {
                    candidates += functionCandidates(for: name, in: inheritsInfo, arguments: arguments, isStatic: isStatic)
                }
            }
            return candidates
        }

        /// - Note: Returns unsorted, un-deduped results.
        private func initCandidates(for typeInfos: [TypeInfo], arguments: [LabeledValue<TypeSignature>]) -> [FunctionCandidate] {
            var initSignatures = typeInfos.flatMap { typeInfo in
                let initInfos = typeInfo.visibleMembers(context: self).filter { $0.declarationType == .initDeclaration }
                return initInfos.compactMap { (initInfo: CodebaseInfoItem) -> FunctionCandidate? in
                    return matchFunction(initInfo, arguments: arguments)
                }
            }
            
            // If we don't have any matches and this appears to be a constructor, treat it as one. We take advantage of this
            // while inferring the types of variable values in prepareForUse(), before we've called generateConstructors()
            if initSignatures.isEmpty && !typeInfos.isEmpty {
                let initParameters = arguments.map { TypeSignature.Parameter(label: $0.label, type: $0.value, isVariadic: false, hasDefaultValue: false) }
                initSignatures.append(FunctionCandidate(signature: .function(initParameters, typeInfos[0].signature), score: 0.0))
            }
            return initSignatures
        }
        
        private func associatedValueSignatures(of member: String, in typeInfo: TypeInfo) -> [TypeSignature.Parameter]? {
            guard let memberInfo = typeInfo.visibleMembers(context: self).first(where: { $0.name == member && $0.declarationType == .enumCaseDeclaration }) else {
                return nil
            }
            guard case .function(let parameters, _) = memberInfo.signature else {
                return nil
            }
            return parameters
        }

        private func matchTuple(_ signature: TypeSignature, arguments: [LabeledValue<TypeSignature>]) -> TypeSignature {
            guard case .function(let parameterTypes, _) = signature, parameterTypes.count == arguments.count else {
                return .none
            }
            return signature
        }
        
        private func matchFunction(_ item: CodebaseInfoItem, arguments: [LabeledValue<TypeSignature>]) -> FunctionCandidate? {
            guard case .function(let parameters, let returnType) = item.signature else {
                return nil
            }
            guard parameters.count >= arguments.count else {
                return nil
            }
            
            // Match each argument to a parameter
            var matchingParameters: [TypeSignature.Parameter] = []
            var parameterIndex = 0
            var totalScore = 0.0
            for argument in arguments {
                guard let (matchingIndex, score) = matchArgument(argument, to: parameters, startIndex: parameterIndex) else {
                    return nil
                }
                matchingParameters.append(parameters[matchingIndex].or(argument.value))
                parameterIndex = matchingIndex + 1
                totalScore += score
            }
            // Make sure there are no more required parameters
            if parameterIndex < parameters.count {
                if parameters[parameterIndex...].contains(where: { !$0.hasDefaultValue }) {
                    return nil
                }
            }
            return FunctionCandidate(signature: .function(matchingParameters, returnType), score: totalScore)
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
    }

    private struct FunctionCandidate: Hashable {
        let signature: TypeSignature
        let score: Double
    }
    
    private var rootTypes: [TypeInfo] = []
    private var rootTypealiases: [TypealiasInfo] = []
    private var rootVariables: [VariableInfo] = []
    private var rootFunctions: [FunctionInfo] = []
    private var rootExtensions: [TypeInfo] = []
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
            guard typeInfo.modifiers.visibility == .public || typeInfo.modifiers.visibility == .open else {
                return
            }
            typeInfo.types = typeInfo.types.filter { $0.modifiers.visibility == .public || $0.modifiers.visibility == .open }
            typeInfo.typealiases = typeInfo.typealiases.filter { $0.modifiers.visibility == .public || $0.modifiers.visibility == .open }
            typeInfo.variables = typeInfo.variables.filter { $0.modifiers.visibility == .public || $0.modifiers.visibility == .open }
            typeInfo.functions = typeInfo.functions.filter { $0.modifiers.visibility == .public || $0.modifiers.visibility == .open }
            typeInfo.cases = typeInfo.cases.filter { $0.modifiers.visibility == .public || $0.modifiers.visibility == .open }
        }
        addItem(typeInfo, to: &itemsByName, publicOnly: publicOnly)
        typeInfo.types.forEach { addTypeInfo($0, to: &itemsByName, publicOnly: publicOnly) }
        let items: [CodebaseInfoItem] = typeInfo.typealiases + typeInfo.cases + typeInfo.variables + typeInfo.functions
        items.forEach { addItem($0, to: &itemsByName, publicOnly: publicOnly) }
    }
    
    private static func addItem(_ item: CodebaseInfoItem, to itemsByName: inout [String: [CodebaseInfoItem]], publicOnly: Bool) {
        guard !publicOnly || item.modifiers.visibility == .public || item.modifiers.visibility == .open else {
            return
        }
        var itemsWithName = itemsByName[item.name, default: []]
        itemsWithName.append(item)
        itemsByName[item.name] = itemsWithName
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
                    context = TypeInferenceContext(codebaseInfo: self, source: syntaxTree.source, statements: syntaxTree.root.statements)
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
        let inits = typeInfo.functions.filter { $0.name == "init" }
        guard inits.isEmpty else {
            return
        }
        var superclassInits: [FunctionInfo] = []
        if typeInfo.declarationType == .classDeclaration, let superclassSignature = typeInfo.inherits.first {
            let superclassName: String
            if case .member(_, let type) = superclassSignature {
                superclassName = type.name
            } else {
                superclassName = superclassSignature.name
            }
            let superclassInfos = itemsByName[superclassName, default: []].compactMap { (item) -> TypeInfo? in
                guard let typeInfo = item as? TypeInfo else {
                    return nil
                }
                return typeInfo.signature.name == superclassSignature.name ? typeInfo : nil
            }
            // inherits.first could have been a protocol
            if superclassInfos.contains(where: { $0.declarationType == .classDeclaration }) {
                superclassInits = superclassInfos.flatMap { $0.functions.filter { $0.name == "init" && ($0.modifiers.visibility != .private || $0.sourceFile == typeInfo.sourceFile) } }
            }
        }
        if superclassInits.isEmpty {
            addMemberwiseConstructor(to: typeInfo)
        } else {
            //~~~ Need to map generic parameters
            for superclassInit in superclassInits {
                var inheritedInit = superclassInit
                inheritedInit.moduleName = typeInfo.moduleName
                inheritedInit.sourceFile = typeInfo.sourceFile
                inheritedInit.declaringType = typeInfo.signature
                inheritedInit.isGenerated = true
                typeInfo.functions.append(inheritedInit)
            }
        }
    }

    private func addMemberwiseConstructor(to typeInfo: TypeInfo) {
        let parameters = typeInfo.variables.compactMap { (variable) -> TypeSignature.Parameter? in
            guard variable.isInitializable else {
                return nil
            }
            return TypeSignature.Parameter(label: variable.name, type: variable.signature, isVariadic: false, hasDefaultValue: variable.hasValue)
        }
        let initSignature: TypeSignature = .function(parameters, typeInfo.signature)
        var initInfo = FunctionInfo(name: "init", declarationType: .initDeclaration, signature: initSignature, moduleName: typeInfo.moduleName, sourceFile: typeInfo.sourceFile, declaringType: typeInfo.signature, modifiers: typeInfo.modifiers)
        initInfo.isGenerated = true
        typeInfo.functions.append(initInfo)
    }

    /// Information about a declared type.
    ///
    /// - Note: Unlike the other `CodebaseInfoItem` datastructures, types are modeled as `class` instances so that we can mutate them in place.
    class TypeInfo: CodebaseInfoItem, Codable {
        let name: String
        let declarationType: StatementType
        let signature: TypeSignature
        let moduleName: String?
        let sourceFile: Source.FilePath?
        let declaringType: TypeSignature?
        let modifiers: Modifiers
        var isStatic: Bool {
            return true
        }
        var languageAdditions: Any?

        let generics: Generics
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

        private enum CodingKeys: String, CodingKey {
            // Exclude language additions
            case name, declarationType, signature, moduleName, sourceFile, declaringType, modifiers, generics, inherits, types, typealiases, cases, variables, functions
        }

        fileprivate init(statement: TypeDeclaration, in declaringType: TypeSignature? = nil, codebaseInfo: CodebaseInfo, delegate: CodebaseInfoGatherDelegate?) {
            self.name = statement.name
            self.declarationType = statement.type
            self.signature = statement.signature
            self.moduleName = codebaseInfo.moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.modifiers = statement.modifiers
            self.generics = statement.generics
            self.inherits = statement.inherits
            addMembers(statement.members, codebaseInfo: codebaseInfo, delegate: delegate)
            delegate?.codebaseInfo(codebaseInfo, didGather: self, from: statement)
        }

        fileprivate init(statement: ExtensionDeclaration, codebaseInfo: CodebaseInfo, delegate: CodebaseInfoGatherDelegate?) {
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
            self.generics = statement.generics
            self.inherits = statement.inherits
            addMembers(statement.members, codebaseInfo: codebaseInfo, delegate: delegate)
            delegate?.codebaseInfo(codebaseInfo, didGather: self, from: statement)
        }

        private func addMembers(_ statements: [Statement], codebaseInfo: CodebaseInfo, delegate: CodebaseInfoGatherDelegate?) {
            for statement in statements {
                switch statement.type {
                case .classDeclaration, .enumDeclaration, .structDeclaration:
                    types.append(TypeInfo(statement: statement as! TypeDeclaration, in: signature, codebaseInfo: codebaseInfo, delegate: delegate))
                case .enumCaseDeclaration:
                    cases.append(EnumCaseInfo(statement: statement as! EnumCaseDeclaration, in: signature, codebaseInfo: codebaseInfo, delegate: delegate))
                case .functionDeclaration, .initDeclaration:
                    functions.append(FunctionInfo(statement: statement as! FunctionDeclaration, in: signature, codebaseInfo: codebaseInfo, delegate: delegate))
                case .typealiasDeclaration:
                    typealiases.append(TypealiasInfo(statement: statement as! TypealiasDeclaration, in: signature, codebaseInfo: codebaseInfo, delegate: delegate))
                case .variableDeclaration:
                    variables.append(VariableInfo(statement: statement as! VariableDeclaration, in: signature, codebaseInfo: codebaseInfo, delegate: delegate))
                default:
                    break
                }
            }
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
        var isStatic: Bool {
            return modifiers.isStatic
        }
        var languageAdditions: Any?

        let generics: Generics
        let isReadOnly: Bool
        let isInitializable: Bool
        let hasValue: Bool
        var value: Expression?

        private enum CodingKeys: String, CodingKey {
            // Exclude value expression, language additions
            case name, signature, moduleName, sourceFile, declaringType, modifiers, generics, isReadOnly, isInitializable, hasValue
        }

        fileprivate init(statement: VariableDeclaration, in declaringType: TypeSignature? = nil, codebaseInfo: CodebaseInfo, delegate: CodebaseInfoGatherDelegate?) {
            self.name = (statement.names.first ?? "") ?? ""
            self.signature = statement.variableTypes.first ?? .none
            self.moduleName = codebaseInfo.moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.modifiers = statement.modifiers
            self.generics = Generics() //~~~
            self.isReadOnly = statement.isLet || (statement.getter != nil && statement.setter == nil)
            self.isInitializable = !statement.modifiers.isStatic && statement.getter == nil && (!statement.isLet || statement.value == nil)
            if case .optional = self.signature {
                self.hasValue = true
            } else {
                self.hasValue = statement.value != nil
            }
            if !self.signature.isFullySpecified, self.sourceFile != nil {
                // We'll try to infer the type after gathering all info
                self.value = statement.value
            }
            delegate?.codebaseInfo(codebaseInfo, didGather: &self, from: statement)
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
                fileMessages.append(.variableNeedsTypeDeclaration(sourceDerived: value!, source: source))
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
        let signature: TypeSignature
        var moduleName: String?
        var sourceFile: Source.FilePath?
        var declaringType: TypeSignature?
        let modifiers: Modifiers
        var isStatic: Bool {
            return modifiers.isStatic
        }
        var languageAdditions: Any?

        let generics: Generics
        let isMutating: Bool
        var isGenerated = false

        private enum CodingKeys: String, CodingKey {
            // Exclude language additions
            case name, declarationType, signature, moduleName, sourceFile, declaringType, modifiers, generics, isMutating, isGenerated
        }

        fileprivate init(statement: FunctionDeclaration, in declaringType: TypeSignature? = nil, codebaseInfo: CodebaseInfo, delegate: CodebaseInfoGatherDelegate?) {
            self.name = statement.name
            self.declarationType = statement.type
            self.signature = statement.functionType
            self.moduleName = codebaseInfo.moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.modifiers = statement.modifiers
            self.generics = Generics() //~~~
            self.isMutating = statement.modifiers.isMutating
            delegate?.codebaseInfo(codebaseInfo, didGather: &self, from: statement)
        }

        fileprivate init(name: String, declarationType: StatementType, signature: TypeSignature, moduleName: String?, sourceFile: Source.FilePath? = nil, declaringType: TypeSignature? = nil, modifiers: Modifiers, generics: Generics = Generics(), isMutating: Bool = false) {
            self.name = name
            self.declarationType = declarationType
            self.signature = signature
            self.moduleName = moduleName
            self.sourceFile = sourceFile
            self.declaringType = declaringType
            self.modifiers = modifiers
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
        var isStatic: Bool {
            return true
        }
        var languageAdditions: Any?

        let generics: Generics

        private enum CodingKeys: String, CodingKey {
            // Exclude language additions
            case name, signature, moduleName, sourceFile, declaringType, modifiers, generics
        }

        fileprivate init(statement: TypealiasDeclaration, in declaringType: TypeSignature? = nil, codebaseInfo: CodebaseInfo, delegate: CodebaseInfoGatherDelegate?) {
            self.name = statement.name
            self.signature = statement.aliasedType
            self.moduleName = codebaseInfo.moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.modifiers = statement.modifiers
            self.generics = statement.generics
            delegate?.codebaseInfo(codebaseInfo, didGather: &self, from: statement)
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
        var isStatic: Bool {
            return true
        }
        var languageAdditions: Any?

        private enum CodingKeys: String, CodingKey {
            // Exclude language additions
            case name, signature, moduleName, sourceFile, declaringType, modifiers
        }

        fileprivate init(statement: EnumCaseDeclaration, in declaringType: TypeSignature? = nil, codebaseInfo: CodebaseInfo, delegate: CodebaseInfoGatherDelegate?) {
            self.name = statement.name
            self.signature = statement.signature
            self.moduleName = codebaseInfo.moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.modifiers = statement.modifiers
            delegate?.codebaseInfo(codebaseInfo, didGather: &self, from: statement)
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
    var isStatic: Bool { get }
    var languageAdditions: Any? { get set }
}

/// Receive callbacks and add language additions during info gathering.
protocol CodebaseInfoGatherDelegate {
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typeInfo: CodebaseInfo.TypeInfo, from statement: TypeDeclaration)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typeInfo: CodebaseInfo.TypeInfo, from statement: ExtensionDeclaration)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather variableInfo: inout CodebaseInfo.VariableInfo, from statement: VariableDeclaration)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather functionInfo: inout CodebaseInfo.FunctionInfo, from statement: FunctionDeclaration)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typealiasInfo: inout CodebaseInfo.TypealiasInfo, from statement: TypealiasDeclaration)
    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather enumCaseInfo: inout CodebaseInfo.EnumCaseInfo, from statement: EnumCaseDeclaration)
}

extension CodebaseInfoGatherDelegate {
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
