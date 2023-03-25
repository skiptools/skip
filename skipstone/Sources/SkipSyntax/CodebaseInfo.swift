/// Codable information about the codebase used in type inference and translation.
public class CodebaseInfo: Codable {
    /// The current module name.
    public let moduleName: String

    /// Supply the current module name.
    public init(moduleName: String) {
        self.moduleName = moduleName
    }

    // TODO: Remove this when we complete migration away from Symbols
    public var symbolsFallback: Symbols?

    /// Set dependcy codebase info.
    ///
    /// - Note: Dependency codebase info is not encoded.
    public var dependencies: [CodebaseInfo] = [] {
        didSet {
            assert(!isInUse)
        }
    }

    /// Gather codebase-level information from the given syntax tree.
    func gather(from syntaxTree: SyntaxTree) {
        assert(!isInUse)
        var needsVariableTypeInference = false
        for statement in syntaxTree.root.statements {
            switch statement.type {
            case .classDeclaration, .enumDeclaration, .protocolDeclaration, .structDeclaration:
                let typeInfo = TypeInfo(statement: statement as! TypeDeclaration, moduleName: moduleName)
                rootTypes.append(typeInfo)
                needsVariableTypeInference = needsVariableTypeInference || typeInfo.needsVariableTypeInference
            case .extensionDeclaration:
                rootExtensions.append(TypeInfo(statement: statement as! ExtensionDeclaration, moduleName: moduleName))
            case .functionDeclaration:
                rootFunctions.append(FunctionInfo(statement: statement as! FunctionDeclaration, moduleName: moduleName))
            case .typealiasDeclaration:
                rootTypealiases.append(TypealiasInfo(statement: statement as! TypealiasDeclaration, moduleName: moduleName))
            case .variableDeclaration:
                let variableInfo = VariableInfo(statement: statement as! VariableDeclaration, moduleName: moduleName)
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
        buildItemsByName()
        inferVariableTypes() // Requires us to be ready for use
    }

    /// Create a context that can access the given imported modules.
    func context(importedModuleNames: [String] = [], sourceFile: Source.FilePath? = nil) -> Context {
        return Context(info: self, importedModuleNames: Set(importedModuleNames), sourceFile: sourceFile)
    }

    /// A context for accessing visible codebase information.
    struct Context {
        let info: CodebaseInfo
        private let importedModuleNames: Set<String>
        private let sourceFile: Source.FilePath?

        fileprivate init(info: CodebaseInfo, importedModuleNames: Set<String>, sourceFile: Source.FilePath?) {
            self.info = info
            var importedModuleNames = importedModuleNames
            importedModuleNames.insert("SkipLib") // Contains our supported subset of the Swift builtin module
            self.importedModuleNames = importedModuleNames
            self.sourceFile = sourceFile
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
            var candidates = info.itemsByName[path[path.count - 1], default: []]
            if path.count > 1 {
                let baseName = path.dropLast().joined(separator: ".")
                candidates = candidates.filter { ($0 is TypeInfo) && $0.declaringType?.name == baseName }
            } else if qualifiedMatch {
                candidates = candidates.filter { !($0 is TypeInfo) || $0.declaringType == nil }
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
        private func rankScore(of item: CodebaseInfoItem) -> Int {
            var score = 0
            if item.moduleName == info.moduleName {
                if let itemSourcePath = item.sourceFile?.path, let sourcePath = sourceFile?.path, itemSourcePath.hasSuffix(sourcePath) {
                    // Favor a symbol in this file
                    score += 3
                } else if item.visibility != .private {
                    // Favor a symbol in this module
                    score += 2
                }
            } else if importedModuleNames.contains(item.moduleName) && (item.visibility == .public || item.visibility == .open) {
                score += 1
            }
            return score
        }

        /// Return all type infos visible for the given type.
        func typeInfos(for type: TypeSignature) -> [TypeInfo] {
            return candidateTypeNames(for: type).flatMap { name in
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

        /// Return the type of the given identifier.
        func identifierSignature(of identifier: String) -> TypeSignature {
            let topRanked = ranked(lookup(name: identifier)).first { candidate in
                guard candidate.declaringType == nil else {
                    return false
                }
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
            let items = ranked(lookup(name: name))
            let funcs = items.filter { $0.declaringType == nil && $0.declarationType == .functionDeclaration }
            let funcsCandidates = funcs.compactMap { matchFunction($0, arguments: arguments) }

            let typeInfos = items.flatMap { (item) -> [TypeInfo] in
                guard item.declaringType == nil else {
                    return []
                }
                if let typeInfo = item as? TypeInfo {
                    return [typeInfo]
                } else if let typealiasInfo = item as? TypealiasInfo {
                    return self.typeInfos(for: typealiasInfo.signature)
                } else {
                    return []
                }
            }
            let initsCandidates = typeInfos.flatMap { typeInfo in
                let initInfos = typeInfo.functions.filter { $0.name == "init" }
                return initInfos.compactMap { (initInfo: FunctionInfo) -> TypeSignature? in
                    guard let signature = matchFunction(initInfo, arguments: arguments), case .function(let argumentTypes, _) = signature else {
                        return nil
                    }
                    // Remap return type of .init from .void to owning type
                    return .function(argumentTypes, typeInfo.signature)
                }
            }
            return (funcsCandidates + initsCandidates).reduce(into: [TypeSignature]()) { result, signature in
                if !result.contains(signature) {
                    result.append(signature)
                }
            }
        }

        /// Return the signatures of the possible member functions being called with the given arguments.
        ///
        /// This function also works for the creation of an enum case with associated values.
        func functionSignature(of name: String, in type: TypeSignature, arguments: [LabeledValue<TypeSignature>]) -> [TypeSignature] {
            var type = type.asOptional(false)
            if case .tuple(let labels, let types) = type {
                for (index, label) in labels.enumerated() {
                    if name == label || name == "\(index)" {
                        let function = matchFunction(types[index], arguments: arguments)
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

            for typeInfo in typeInfos(for: type) {
                let functions = functionSignature(of: name, in: typeInfo, arguments: arguments, isStatic: isStatic)
                if !functions.isEmpty {
                    return functions
                }
            }
            return []
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

            for typeInfo in typeInfos(for: type) {
                let functions = functionSignature(of: "subscript", in: typeInfo, arguments: arguments, isStatic: isStatic)
                if !functions.isEmpty {
                    return functions
                }
            }
            return []
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

        private func identifierSignature(of member: String, in candidate: TypeInfo, isStatic: Bool) -> TypeSignature {
            if let memberInfo = candidate.members.first(where: { $0.name == member && $0.isStatic == isStatic }) {
                // Enum cases with associated values are modeled as functions, but can also be used as identifiers
                if memberInfo.declarationType == .enumCaseDeclaration {
                    return memberInfo.declaringType ?? .none
                }
                return memberInfo.signature
            }
            for inherits in candidate.inherits {
                for typeInfo in typeInfos(for: inherits) {
                    let signature = identifierSignature(of: member, in: typeInfo, isStatic: isStatic)
                    if signature != .none {
                        return signature
                    }
                }
            }
            return .none
        }

        private func functionSignature(of name: String, in candidate: TypeInfo, arguments: [LabeledValue<TypeSignature>], isStatic: Bool) -> [TypeSignature] {
            var functions: [TypeSignature] = []
            if let memberInfo = candidate.members.first(where: { $0.name == name && $0.isStatic == isStatic }) {
                if let function = matchFunction(memberInfo, arguments: arguments) {
                    functions.append(function)
                }
            }
            if !functions.isEmpty {
                return functions
            }
            for inherits in candidate.inherits {
                for typeInfo in typeInfos(for: inherits) {
                    let functions = functionSignature(of: name, in: typeInfo, arguments: arguments, isStatic: isStatic)
                    if !functions.isEmpty {
                        return functions
                    }
                }
            }
            return []
        }

        private func associatedValueSignatures(of member: String, in candidate: TypeInfo) -> [TypeSignature.Parameter]? {
            guard let memberInfo = candidate.members.first(where: { $0.name == member && $0.declarationType == .enumCaseDeclaration }) else {
                return nil
            }
            guard case .function(let parameters, _) = memberInfo.signature else {
                return nil
            }
            return parameters
        }

        private func matchFunction(_ item: CodebaseInfoItem, arguments: [LabeledValue<TypeSignature>]) -> TypeSignature? {
            guard case .function(let parameters, let returnType) = item.signature else {
                return nil
            }
            guard parameters.count >= arguments.count else {
                return nil
            }

            // Match each argument to a parameter
            var matchingParameters: [TypeSignature.Parameter] = []
            var parameterIndex = 0
            for argument in arguments {
                guard let matchingIndex = matchArgument(argument, to: parameters, startIndex: parameterIndex) else {
                    return nil
                }
                matchingParameters.append(parameters[matchingIndex].or(argument.value))
                parameterIndex = matchingIndex + 1
            }
            // Make sure there are no more required parameters
            if parameterIndex < parameters.count {
                if parameters[parameterIndex...].contains(where: { !$0.hasDefaultValue }) {
                    return nil
                }
            }
            return .function(matchingParameters, returnType)
        }

        private func matchFunction(_ signature: TypeSignature, arguments: [LabeledValue<TypeSignature>]) -> TypeSignature {
            guard case .function(let parameterTypes, _) = signature, parameterTypes.count == arguments.count else {
                return .none
            }
            return signature
        }

        private func matchArgument(_ argument: LabeledValue<TypeSignature>, to parameters: [TypeSignature.Parameter], startIndex: Int) -> Int? {
            for (index, parameter) in parameters[startIndex...].enumerated() {
                if let label = argument.label {
                    // If there is a label, then it either has to match or we have to be able to skip this parameter
                    if parameter.label == label {
                        return startIndex + index
                    } else if !parameter.hasDefaultValue {
                        return nil
                    }
                } else {
                    // If there is no label, then either this parameter has to have no label or it has to be a trailing closure
                    if parameter.label == nil && parameter.type.isCompatible(with: argument.value) {
                        return startIndex + index
                    } else if case .function = parameter.type, parameter.type.isCompatible(with: argument.value) {
                        return startIndex + index
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

    private var rootTypes: [TypeInfo] = []
    private var rootTypealiases: [TypealiasInfo] = []
    private var rootVariables: [VariableInfo] = []
    private var rootFunctions: [FunctionInfo] = []
    private var rootExtensions: [TypeInfo] = []
    private var itemsByName: [String: [CodebaseInfoItem]] = [:]
    private var isInUse = false
    private var typeInferenceTrees: [Source.FilePath: SyntaxTree] = [:]

    private enum CodingKeys: String, CodingKey {
        // Only encode moduleName and root infos
        case moduleName, rootTypes, rootTypealiases, rootVariables, rootFunctions, rootExtensions
    }

    private func buildItemsByName() {
        var itemsByName: [String: [CodebaseInfoItem]] = [:]
        Self.addCodebaseInfo(self, to: &itemsByName)
        dependencies.forEach { Self.addCodebaseInfo($0, to: &itemsByName) }
        self.itemsByName = itemsByName
    }

    private static func addCodebaseInfo(_ info: CodebaseInfo, to itemsByName: inout [String: [CodebaseInfoItem]]) {
        info.rootTypes.forEach { addTypeInfo($0, to: &itemsByName) }
        info.rootExtensions.forEach { addTypeInfo($0, to: &itemsByName) }
        let rootItems: [CodebaseInfoItem] = info.rootTypealiases + info.rootVariables + info.rootFunctions
        rootItems.forEach { addItem($0, to: &itemsByName) }
    }

    private static func addTypeInfo(_ typeInfo: TypeInfo, to itemsByName: inout [String: [CodebaseInfoItem]]) {
        addItem(typeInfo, to: &itemsByName)
        typeInfo.types.forEach { addTypeInfo($0, to: &itemsByName) }
        let items: [CodebaseInfoItem] = typeInfo.typealiases + typeInfo.cases + typeInfo.variables + typeInfo.functions
        items.forEach { addItem($0, to: &itemsByName) }
    }

    private static func addItem(_ item: CodebaseInfoItem, to itemsByName: inout [String: [CodebaseInfoItem]]) {
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
        for (sourceFile, syntaxTree) in typeInferenceTrees {
            let context: TypeInferenceContext
            if let existingContext = typeInferenceContexts[sourceFile] {
                context = existingContext
            } else {
                context = TypeInferenceContext(codebaseInfo: self, sourceFile: sourceFile, statements: syntaxTree.root.statements)
                typeInferenceContexts[sourceFile] = context
            }
            for i in 0..<rootVariables.count {
                if rootVariables[i].sourceFile == sourceFile && rootVariables[i].needsTypeInference {
                    rootVariables[i] = rootVariables[i].inferType(with: context)
                }
            }
            for rootType in rootTypes {
                if rootType.sourceFile == sourceFile && rootType.needsVariableTypeInference {
                    if let declaration = syntaxTree.root.statements.first(where: { ($0 as? TypeDeclaration)?.name == rootType.name }) as? TypeDeclaration {
                        rootType.inferVariableTypes(with: context, declaration: declaration)
                    }
                }
            }
        }
    }

    //~~~ We have to add synthesized constructors ourselves
    /// Information about a declared type.
    ///
    /// - Note: Unlike the other `CodebaseInfoItem` datastructures, types are modeled as `class` instances so that we can mutate them in place.
    class TypeInfo: CodebaseInfoItem, Codable {
        let name: String
        let declarationType: StatementType
        let signature: TypeSignature
        let moduleName: String
        let sourceFile: Source.FilePath?
        let declaringType: TypeSignature?
        let visibility: Modifiers.Visibility
        var isStatic: Bool {
            return true
        }

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

        fileprivate init(statement: TypeDeclaration, in declaringType: TypeSignature? = nil, moduleName: String) {
            self.name = statement.name
            self.declarationType = statement.type
            self.signature = statement.signature
            self.moduleName = moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.visibility = statement.modifiers.visibility
            self.generics = statement.generics
            self.inherits = statement.inherits
            addMembers(statement.members)
        }

        fileprivate init(statement: ExtensionDeclaration, moduleName: String) {
            self.name = statement.name
            self.declarationType = statement.type
            self.signature = statement.signature
            self.moduleName = moduleName
            self.sourceFile = statement.sourceFile
            if case .member(let base, _) = statement.signature {
                self.declaringType = base
            } else {
                self.declaringType = nil
            }
            self.visibility = statement.modifiers.visibility
            self.generics = statement.generics
            self.inherits = statement.inherits
            addMembers(statement.members)
        }

        private func addMembers(_ statements: [Statement]) {
            for statement in statements {
                switch statement.type {
                case .classDeclaration, .enumDeclaration, .structDeclaration:
                    types.append(TypeInfo(statement: statement as! TypeDeclaration, in: signature, moduleName: moduleName))
                case .enumCaseDeclaration:
                    cases.append(EnumCaseInfo(statement: statement as! EnumCaseDeclaration, in: signature, moduleName: moduleName))
                case .functionDeclaration:
                    functions.append(FunctionInfo(statement: statement as! FunctionDeclaration, in: signature, moduleName: moduleName))
                case .typealiasDeclaration:
                    typealiases.append(TypealiasInfo(statement: statement as! TypealiasDeclaration, in: signature, moduleName: moduleName))
                case .variableDeclaration:
                    variables.append(VariableInfo(statement: statement as! VariableDeclaration, in: signature, moduleName: moduleName))
                default:
                    break
                }
            }
        }

        fileprivate var needsVariableTypeInference: Bool {
            return variables.contains { $0.needsTypeInference } || types.contains { $0.needsVariableTypeInference }
        }

        fileprivate func inferVariableTypes(with context: TypeInferenceContext, declaration: TypeDeclaration) {
            let memberContext = context.pushing(declaration)
            variables = variables.map { $0.needsTypeInference ? $0.inferType(with: memberContext) : $0 }
            for type in types {
                guard type.needsVariableTypeInference else {
                    continue
                }
                if let declaration = declaration.members.first(where: { ($0 as? TypeDeclaration)?.name == type.name }) as? TypeDeclaration {
                    type.inferVariableTypes(with: memberContext, declaration: declaration)
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
        let moduleName: String
        let sourceFile: Source.FilePath?
        let declaringType: TypeSignature?
        let visibility: Modifiers.Visibility
        let isStatic: Bool

        let generics: Generics
        let isReadOnly: Bool
        var value: Expression?

        private enum CodingKeys: String, CodingKey {
            // Exclude value expression
            case name, signature, moduleName, sourceFile, declaringType, visibility, isStatic, generics, isReadOnly
        }

        fileprivate init(statement: VariableDeclaration, in declaringType: TypeSignature? = nil, moduleName: String) {
            self.name = (statement.names.first ?? "") ?? ""
            self.signature = statement.variableTypes.first ?? .none
            self.moduleName = moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.visibility = statement.modifiers.visibility
            self.isStatic = statement.modifiers.isStatic
            self.generics = Generics() //~~~
            self.isReadOnly = statement.isLet || (statement.getter != nil && statement.setter == nil)
            if self.signature == .none, self.sourceFile != nil {
                // We'll try to infer the type after gathering all info
                self.value = statement.value
            }
        }

        fileprivate var needsTypeInference: Bool {
            return value != nil
        }

        fileprivate func inferType(with context: TypeInferenceContext) -> VariableInfo {
            var v = self
            guard let value = v.value else {
                return v
            }
            v.value = nil // Don't hold on to Expression
            value.inferTypes(context: context, expecting: .none)
            v.signature = value.inferredType
            return v
        }
    }

    /// Information about a declared function.
    struct FunctionInfo: CodebaseInfoItem, Codable {
        let name: String
        var declarationType: StatementType {
            return .functionDeclaration
        }
        let signature: TypeSignature
        let moduleName: String
        let sourceFile: Source.FilePath?
        let declaringType: TypeSignature?
        let visibility: Modifiers.Visibility
        let isStatic: Bool

        let generics: Generics
        let isMutating: Bool

        fileprivate init(statement: FunctionDeclaration, in declaringType: TypeSignature? = nil, moduleName: String) {
            self.name = statement.name
            self.signature = statement.functionType
            self.moduleName = moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.visibility = statement.modifiers.visibility
            self.isStatic = statement.modifiers.isStatic
            self.generics = Generics() //~~~
            self.isMutating = statement.modifiers.isMutating
        }
    }

    /// Information about a typealias.
    struct TypealiasInfo: CodebaseInfoItem, Codable {
        let name: String
        var declarationType: StatementType {
            return .typealiasDeclaration
        }
        let signature: TypeSignature
        let moduleName: String
        let sourceFile: Source.FilePath?
        let declaringType: TypeSignature?
        let visibility: Modifiers.Visibility
        var isStatic: Bool {
            return true
        }

        let generics: Generics

        fileprivate init(statement: TypealiasDeclaration, in declaringType: TypeSignature? = nil, moduleName: String) {
            self.name = statement.name
            self.signature = statement.signature
            self.moduleName = moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.visibility = statement.modifiers.visibility
            self.generics = statement.generics
        }
    }

    /// Information about an enum case.
    struct EnumCaseInfo: CodebaseInfoItem, Codable {
        let name: String
        var declarationType: StatementType {
            return .enumCaseDeclaration
        }
        let signature: TypeSignature // Owning enum or a function returning the owning enum
        let moduleName: String
        let sourceFile: Source.FilePath?
        let declaringType: TypeSignature?
        let visibility: Modifiers.Visibility
        var isStatic: Bool {
            return true
        }

        fileprivate init(statement: EnumCaseDeclaration, in declaringType: TypeSignature? = nil, moduleName: String) {
            self.name = statement.name
            self.signature = statement.signature
            self.moduleName = moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.visibility = statement.modifiers.visibility
        }
    }
}

/// Common protocol for all codebase info items.
protocol CodebaseInfoItem {
    var name: String { get }
    var declarationType: StatementType { get }
    var signature: TypeSignature { get }
    var moduleName: String { get }
    var sourceFile: Source.FilePath? { get }
    var declaringType: TypeSignature? { get }
    var visibility: Modifiers.Visibility { get }
    var isStatic: Bool { get }
}
