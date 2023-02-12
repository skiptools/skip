/// Wholistic information about the codebase needed when transpiling Swift to Kotlin.
public class KotlinCodebaseInfo {
    /// The package being generated.
    public let packageName: String?
    let symbols: Symbols?

    public init(packageName: String? = nil, symbols: Symbols? = nil) {
        self.packageName = packageName
        self.symbols = symbols
    }

    /// Gather codebase-level information from the given syntax tree.
    func gather(from syntaxTree: SyntaxTree) {
        syntaxTree.statements.forEach { gather(from: $0) }
    }

    /// Any issues encountered during information gathering.
    func messages(for sourceFile: Source.File) -> [Message] {
        return []
    }

    private var typeInfo: [String: (type: StatementType, mayBeMutableValueType: Bool?)] = [:]
    private var extensionDeclarations: [String: [ExtensionDeclaration]] = [:]

    private func gather(from statement: Statement) {
        switch statement.type {
        case .classDeclaration:
            typeInfo[(statement as! TypeDeclaration).qualifiedName] = (.classDeclaration, false)
        case .enumDeclaration:
            typeInfo[(statement as! TypeDeclaration).qualifiedName] = (.enumDeclaration, false)
        case .protocolDeclaration:
            let typeDeclaration = statement as! TypeDeclaration
            // A protocol may not be mutable value if it extends from AnyObject, may be if it extends from nothing,
            // and we're not sure if it extends from other protocols which may themselves extend from AnyObject. We'll
            // check its symbols later
            let mayBeMutableValueType: Bool? = typeDeclaration.inherits.contains(.anyObject) ? false : typeDeclaration.inherits.isEmpty ? true : nil
            typeInfo[typeDeclaration.qualifiedName] = (.protocolDeclaration, mayBeMutableValueType)
        case .structDeclaration:
            let typeDeclaration = statement as! TypeDeclaration
            let mayBeMutableValueType = typeDeclaration.members.contains { member in
                switch member.type {
                case .variableDeclaration:
                    let variableDeclaration = member as! VariableDeclaration
                    return !variableDeclaration.isLet && (variableDeclaration.getter == nil || variableDeclaration.setter != nil)
                case .functionDeclaration:
                    return (member as! FunctionDeclaration).modifiers.isMutating
                default:
                    return false
                }
            }
            typeInfo[typeDeclaration.qualifiedName] = (.protocolDeclaration, mayBeMutableValueType)
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
        return extensionDeclarations[declaration.qualifiedName] ?? []
    }

    /// Whether the given qualified type name is a class, struct, etc *within this module*.
    func declarationType(of qualifiedName: String) -> StatementType? {
        return typeInfo[qualifiedName]?.type
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

    /// Whether the given qualified type name may map to a mutable value type.
    func mayBeMutableValueType(qualifiedName: String) -> Bool {
        if let mayBeMutableValueType = typeInfo[qualifiedName]?.mayBeMutableValueType {
            return mayBeMutableValueType
        }
        return symbols?.containsMutableValueType(name: qualifiedName) != false
    }
}
