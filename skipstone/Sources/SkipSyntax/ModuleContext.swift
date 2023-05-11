/// Resolve module-qualified types.
struct ModuleContext {
    private let codebaseInfo: CodebaseInfo.Context?
    private let source: Source?

    init() {
        self.codebaseInfo = nil
        self.source = nil
    }

    /// Create a context for using module information.
    ///
    /// - Parameters:
    ///   - codebaseInfo: Available codebase information.
    ///   - source: Source for this context.
    ///   - statements: Top-level statements from which to determine imports.
    init(codebaseInfo: CodebaseInfo? = nil, source: Source, statements: [Statement]) {
        self.source = source
        if let codebaseInfo {
            let importedModuleNames: [String] = statements.compactMap { statement in
                guard statement.type == .importDeclaration, let importDeclaration = statement as? ImportDeclaration else {
                    return nil
                }
                return importDeclaration.modulePath.first
            }
            self.codebaseInfo = codebaseInfo.context(importedModuleNames: importedModuleNames, source: source)
        } else {
            self.codebaseInfo = nil
        }
    }

    /// If the given type represents a module-qualified type, return it as such.
    func resolve(_  type: TypeSignature, in baseOrModule: TypeSignature) -> TypeSignature {
        guard case .named(let baseName, let baseGenerics) = baseOrModule, baseGenerics.isEmpty else {
            return .member(baseOrModule, type)
        }
        // Swift.xxx builtin type?
        if baseName == "Swift" {
            let builtinType = TypeSignature.for(name: type.name, genericTypes: type.generics, allowNamed: false)
            if builtinType != .none {
                return builtinType
            }
        }
        guard let codebaseInfo else {
            return .member(baseOrModule, type)
        }
        
        let qualifiedTypeName = "\(baseName).\(type.name)"
        guard let typeInfo = codebaseInfo.primaryTypeInfo(forNamed: .named(qualifiedTypeName, [])) else {
            return .member(baseOrModule, type)
        }
        guard typeInfo.signature.name != qualifiedTypeName, typeInfo.moduleName == CodebaseInfo.moduleNameMap[baseName, default: baseName] else {
            return .member(baseOrModule, type)
        }
        return .module(baseName, type)
    }
}
