/// Wholistic information about the codebase needed when transpiling Swift to Kotlin.
public class KotlinCodebaseInfo {
    /// The package being generated.
    public let packageName: String?
    public let symbolInfo: SymbolInfo?

    public init(packageName: String? = nil, symbolInfo: SymbolInfo? = nil) {
        self.packageName = packageName
        self.symbolInfo = symbolInfo
    }

    /// Gather codebase-level information from the given syntax tree.
    func gather(from syntaxTree: SyntaxTree) {
        syntaxTree.statements.forEach { gather(from: $0) }
    }

    /// Any issues encountered during information gathering.
    func messages(for sourceFile: Source.File) -> [Message] {
        return []
    }

    private var typeInfo: [String: StatementType] = [:]
    private var extensionDeclarations: [String: [ExtensionDeclaration]] = [:]

    private func gather(from statement: Statement) {
        switch statement.type {
        case .classDeclaration:
            fallthrough
        case .enumDeclaration:
            fallthrough
        case .protocolDeclaration:
            fallthrough
        case .structDeclaration:
            typeInfo[(statement as! TypeDeclaration).name] = statement.type
        case .extensionDeclaration:
            let declaration = statement as! ExtensionDeclaration
            let key = declaration.extends.description
            if var declarations = extensionDeclarations[key] {
                declarations.append(declaration)
                extensionDeclarations[key] = declarations
            } else {
                extensionDeclarations[key] = [declaration]
            }
        default:
            break
        }
    }

    /// Return all extensions of a given type.
    func extensions(of declaration: TypeDeclaration) -> [ExtensionDeclaration] {
        return extensionDeclarations[declaration.name] ?? []
    }

    /// Whether the given qualified type name is a class, struct, etc *within this module*.
    func declarationType(of typeName: String) -> StatementType? {
        return typeInfo[typeName]
    }

    /// Whether a function with the given signature is implementing an inherited protocol function of the given type.
    func isProtocolMember(declaration: FunctionDeclaration, in typeDeclaration: TypeDeclaration) -> Bool {
        // TODO: Needs to check all protocol conformances of the given type, including protocols of protocols, etc
        return false
    }

    /// Whether a property with the given signature is implementing an inherited protocol property of the given type.
    func isProtocolMember(declaration: VariableDeclaration, in typeDeclaration: TypeDeclaration) -> Bool {
        // TODO: Needs to check all protocol conformances of the given type, including protocols of protocols, etc
        return false
    }

    /// Whether the given type name may map to a mutable value type.
    func mayBeMutableValueType(name: String) -> Bool {
        // TODO
        return true
    }
}
