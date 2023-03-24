/// Codable information about the codebase used in type inference and translation.
public class CodebaseInfo: Codable {
    /// The current module name.
    public let moduleName: String

    /// Supply the current module name.
    public init(moduleName: String) {
        self.moduleName = moduleName
    }

    /// - Note: Remove this when we complete the transition away from SymbolKit.
    public var symbolsFallback: Symbols?

    /// Add the contents of the given codebase info to our own info.
    public func add(_ info: CodebaseInfo) {
        types += info.types
        typealiases += info.typealiases
        variables += info.variables
        functions += info.functions
        extensions += info.extensions
        rebuildItemsByName()
    }

    /// Gather codebase-level information from the given syntax tree.
    func gather(from syntaxTree: SyntaxTree) {
        syntaxTree.root.visit(perform: self.visit)
    }

    /// Finalize codebase info after gathering is complete.
    func didGather() {
        mergeExtensions()
        inferVariableTypes()
        rebuildItemsByName()
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
        /// - Warning: This function does not take symbol visibility into account. See `ranked`.
        func lookup(qualifiedName: String) -> [CodebaseInfoItem] {
            let path = qualifiedName.split(separator: ".").map { String($0) }
            guard !path.isEmpty else {
                return []
            }
            var candidates = info.itemsByName[path[path.count - 1], default: []]
            if path.count > 1 {
                let baseName = path.dropLast().joined(separator: ".")
                candidates = candidates.filter { $0.declaringType?.name == baseName }
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
            return candidateTypeNames(for: type).flatMap { qualifiedName in
                let candidates = ranked(lookup(qualifiedName: qualifiedName))
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
            let topRanked = ranked(lookup(qualifiedName: identifier)).first { candidate in
                guard candidate.declaringType == nil else {
                    return false
                }
                switch candidate.declarationType {
                case .classDeclaration, .enumDeclaration, .protocolDeclaration, .structDeclaration, .typealiasDeclaration, .variableDeclaration:
                    return true
                default:
                    return false
                }
            }
            guard let topRanked else {
                return .none
            }
            let type = topRanked.signature
            return topRanked.declarationType == .variableDeclaration ? type : .metaType(type)
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
            let items = ranked(lookup(qualifiedName: name))
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

    private var types: [TypeInfo] = []
    private var typealiases: [TypealiasInfo] = []
    private var variables: [VariableInfo] = []
    private var functions: [FunctionInfo] = []
    private var extensions: [TypeInfo] = []
    private var itemsByName: [String: [CodebaseInfoItem]] = [:]

    private enum CodingKeys: String, CodingKey {
        // Exclude itemsByName
        case moduleName, types, typealiases, variables, functions, extensions
    }

    private func rebuildItemsByName() {
        let items: [CodebaseInfoItem] = types + typealiases + variables + functions
        var itemsByName: [String: [CodebaseInfoItem]] = [:]
        for item in items {
            var itemsWithName = itemsByName[item.name, default: []]
            itemsWithName.append(item)
            itemsByName[item.name] = itemsWithName
        }
        self.itemsByName = itemsByName
    }

    private func mergeExtensions() {
        //~~~
    }

    private func inferVariableTypes() {
        //~~~
    }

    private func visit(node: SyntaxNode) -> VisitResult<SyntaxNode> {
        guard let statement = node as? Statement else {
            // Recurse to find nested declarations
            return .recurse(nil)
        }
        switch statement.type {
        case .classDeclaration, .enumDeclaration, .protocolDeclaration, .structDeclaration:
            types.append(TypeInfo(statement: statement as! TypeDeclaration, moduleName: moduleName))
        case .extensionDeclaration:
            extensions.append(TypeInfo(statement: statement as! ExtensionDeclaration, moduleName: moduleName))
        case .functionDeclaration:
            if statement.isGlobal {
                functions.append(FunctionInfo(statement: statement as! FunctionDeclaration, moduleName: moduleName))
            }
        case .typealiasDeclaration:
            if statement.isGlobal {
                typealiases.append(TypealiasInfo(statement: statement as! TypealiasDeclaration, moduleName: moduleName))
            }
        case .variableDeclaration:
            if statement.isGlobal {
                variables.append(VariableInfo(statement: statement as! VariableDeclaration, moduleName: moduleName))
            }
        default:
            break
        }
        return .recurse(nil)
    }

    //~~~ We have to add synthesized constructors ourselves
    /// Information about a declared type.
    struct TypeInfo: CodebaseInfoItem, Codable {
        let name: String
        let declarationType: StatementType
        let signature: TypeSignature
        let moduleName: String
        let sourceFile: Source.FilePath?
        var declaringType: TypeSignature? {
            if case .member(let base, _) = signature {
                return base
            } else {
                return nil
            }
        }
        let visibility: Modifiers.Visibility
        var isStatic: Bool {
            return true
        }

        let generics: Generics
        var inherits: [TypeSignature]

        var types: [TypeInfo] = []
        var typealiases: [TypealiasInfo] = []
        var cases: [EnumCaseInfo] = []
        var properties: [VariableInfo] = []
        var functions: [FunctionInfo] = []
        var members: [CodebaseInfoItem] {
            return types + typealiases + cases + properties + functions
        }

        init(statement: TypeDeclaration, moduleName: String) {
            self.name = statement.name
            self.declarationType = statement.type
            self.signature = statement.signature
            self.moduleName = moduleName
            self.sourceFile = statement.sourceFile
            self.visibility = statement.modifiers.visibility
            self.generics = statement.generics
            self.inherits = statement.inherits
            addMembers(statement.members)
        }

        init(statement: ExtensionDeclaration, moduleName: String) {
            self.name = statement.name
            self.declarationType = statement.type
            self.signature = statement.signature
            self.moduleName = moduleName
            self.sourceFile = statement.sourceFile
            self.visibility = statement.modifiers.visibility
            self.generics = statement.generics
            self.inherits = statement.inherits
            addMembers(statement.members)
        }

        private func addMembers(_ statements: [Statement]) {
            //~~~
        }
    }

    /// Information about a declared global or property.
    struct VariableInfo: CodebaseInfoItem, Codable {
        let name: String
        var declarationType: StatementType {
            return .variableDeclaration
        }
        let signature: TypeSignature
        let moduleName: String
        let sourceFile: Source.FilePath?
        let declaringType: TypeSignature?
        let visibility: Modifiers.Visibility
        let isStatic: Bool

        let generics: Generics
        let isReadOnly: Bool

        init(statement: VariableDeclaration, in declaringType: TypeSignature? = nil, moduleName: String) {
            self.name = (statement.names.first ?? "") ?? ""
            self.signature = statement.variableTypes.first ?? .none
            self.moduleName = moduleName
            self.sourceFile = statement.sourceFile
            self.declaringType = declaringType
            self.visibility = statement.modifiers.visibility
            self.isStatic = statement.modifiers.isStatic
            self.generics = Generics() //~~~
            self.isReadOnly = statement.isLet || (statement.getter != nil && statement.setter == nil)
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

        init(statement: FunctionDeclaration, in declaringType: TypeSignature? = nil, moduleName: String) {
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

        init(statement: TypealiasDeclaration, in declaringType: TypeSignature? = nil, moduleName: String) {
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

        init(statement: EnumCaseDeclaration, in declaringType: TypeSignature? = nil, moduleName: String) {
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
