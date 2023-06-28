/// Resolve typealiases and module-qualified types.
struct TypeResolutionContext {
    private let codebaseInfo: CodebaseInfo.Context?

    init(codebaseInfo: CodebaseInfo.Context? = nil) {
        self.codebaseInfo = codebaseInfo
    }

    /// If the given type represents a typealias and/or module-qualified type, return it as such.
    func resolve(name: String, generics: [TypeSignature], in baseOrModule: TypeSignature? = nil) -> TypeSignature {
        let type = resolveModuleQualifiedType(name: name, generics: generics, in: baseOrModule)
        guard let codebaseInfo, codebaseInfo.global.languageAdditions?.shouldResolveTypealiases == true else {
            return type
        }
        return codebaseInfo.resolveTypealias(for: type)
    }

    private func resolveModuleQualifiedType(name: String, generics: [TypeSignature], in baseOrModule: TypeSignature?) -> TypeSignature {
        let type: TypeSignature = .named(name, generics)
        guard let baseOrModule else {
            return type
        }
        if case .module(let moduleName, let base) = baseOrModule {
            return .module(moduleName, .member(base, type))
        }

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
        guard typeInfo.signature.name != qualifiedTypeName, typeInfo.moduleName == CodebaseInfo.moduleNameMap[baseName, default: baseName] else {
            return member
        }
        return .module(baseName, type)
    }
}
