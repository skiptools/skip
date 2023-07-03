/// Resolve typealiases and module-qualified types.
struct TypeResolutionContext {
    private let codebaseInfo: CodebaseInfo.Context?

    init(codebaseInfo: CodebaseInfo.Context? = nil) {
        self.codebaseInfo = codebaseInfo
    }

    /// If the given type represents a typealias and/or module-qualified type, resolve it to the proper `.typealiased` and/or `.module` form.
    func resolve(_ type: TypeSignature, moduleName: String? = nil, in baseOrModule: TypeSignature = .none) -> TypeSignature {
        let type = resolveModuleQualifiedType(type, moduleName: moduleName, in: baseOrModule)
        return codebaseInfo?.resolveTypealias(for: type) ?? type
    }

    private func resolveModuleQualifiedType(_ type: TypeSignature, moduleName: String?, in baseOrModule: TypeSignature = .none) -> TypeSignature {
        if let moduleName {
            if baseOrModule != .none {
                return type.asMember(of: baseOrModule.withModuleName(moduleName))
            } else {
                return type.withModuleName(moduleName)
            }
        }
        guard baseOrModule.moduleName == nil else {
            return type.asMember(of: baseOrModule)
        }
        guard case .named(let baseName, []) = baseOrModule.asTypealiased(nil) else {
            return type.asMember(of: baseOrModule)
        }
        // Swift.xxx builtin type?
        if baseName == "Swift" {
            let builtinType = TypeSignature.for(name: type.name, genericTypes: type.generics, allowNamed: false)
            if builtinType != .none {
                return builtinType
            }
        }
        guard let codebaseInfo else {
            return type.asMember(of: baseOrModule)
        }
        
        let qualifiedTypeName = "\(baseName).\(type.name)"
        for info in codebaseInfo.ranked(codebaseInfo.global.lookup(name: qualifiedTypeName)) {
            if info is CodebaseInfo.TypeInfo || info is CodebaseInfo.TypealiasInfo, info.declarationType != .extensionDeclaration {
                let signature = info.signature.withGenerics(type.generics)
                // Detect whether the lookup used the base name as a module name
                if info.moduleName == (CodebaseInfo.moduleNameMap[baseName] ?? baseName) && signature.name != qualifiedTypeName {
                    return signature.withModuleName(baseName)
                } else {
                    return signature
                }
            }
        }
        // If we can't locate type info, assume an unknown type
        return type.asMember(of: baseOrModule)
    }
}
