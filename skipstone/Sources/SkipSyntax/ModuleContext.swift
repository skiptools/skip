/// Resolve module-qualified types.
struct ModuleContext {
    private let codebaseInfo: CodebaseInfo.Context
    private let source: Source

    /// Create a context for using module information.
    ///
    /// - Parameters:
    ///   - codebaseInfo: Available codebase information.
    ///   - source: Source for this context.
    ///   - statements: Top-level statements from which to determine imports.
    init?(codebaseInfo: CodebaseInfo? = nil, source: Source, statements: [Statement]) {
        guard let codebaseInfo else {
            return nil
        }
        self.source = source
        let importedModuleNames: [String] = statements.compactMap { statement in
            guard statement.type == .importDeclaration, let importDeclaration = statement as? ImportDeclaration else {
                return nil
            }
            return importDeclaration.modulePath.first
        }
        self.codebaseInfo = codebaseInfo.context(importedModuleNames: importedModuleNames, source: source)
    }

    /// If the given type represents a module-qualified type, return it as such.
    func moduleType(for type: TypeSignature, in module: TypeSignature) -> TypeSignature? {
        //~~~
        return nil
    }
}
