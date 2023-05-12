/// Resolve module-qualified types.
struct ModuleContext {
    private let codebaseInfo: CodebaseInfo?
    private let importedModuleNames: Set<String>
    private let sourceFile: Source.FilePath?

    init(codebaseInfo: CodebaseInfo? = nil, importedModuleNames: [String] = [], sourceFile: Source.FilePath? = nil) {
        self.codebaseInfo = codebaseInfo
        self.importedModuleNames = Set(importedModuleNames)
        self.sourceFile = sourceFile
    }

    /// If the given type represents a module-qualified type, return it as such.
    func resolve(_  type: TypeSignature, in baseOrModule: TypeSignature) -> TypeSignature {
        let member: TypeSignature = .member(baseOrModule, type)
        guard case .named(let baseName, let baseGenerics) = baseOrModule, baseGenerics.isEmpty else {
            return member
        }
        // Swift.xxx builtin type?
        if baseName == "Swift" {
            let builtinType = TypeSignature.for(name: type.name, genericTypes: type.generics, allowNamed: false)
            if builtinType != .none {
                return builtinType
            }
        }
        guard let codebaseInfo else {
            return member
        }
        
        let qualifiedTypeName = "\(baseName).\(type.name)"
        guard let typeInfo = codebaseInfo.primaryTypeInfo(forNamed: .named(qualifiedTypeName, [])) else {
            return member
        }
        guard typeInfo.rankScore(moduleName: codebaseInfo.moduleName, importedModuleNames: importedModuleNames, sourceFile: sourceFile) > 0 else {
            return member
        }
        guard typeInfo.signature.name != qualifiedTypeName, typeInfo.moduleName == CodebaseInfo.moduleNameMap[baseName, default: baseName] else {
            return member
        }
        return .module(baseName, type)
    }
}
