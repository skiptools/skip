/// Wholistic information about the codebase needed when transpiling Swift to Kotlin.
public class KotlinCodebaseInfo {
    init() {
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
            typeInfo[(statement as! TypeDeclaration).qualifiedName] = statement.type
        case .extensionDeclaration:
            let declaration = statement as! ExtensionDeclaration
            let key = declaration.extends.qualifiedDescription
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
    func declarationType(of typeName: String) -> StatementType? {
        return typeInfo[typeName]
    }

    /// Whether a function with the given signature is implementing an inherited protocol function of the given type.
    func isProtocolFunction(declaration: FunctionDeclaration, in typeDeclaration: TypeDeclaration) -> Bool {
        // TODO: Needs to check all protocol conformances of the given type, including protocols of protocols, etc
        return false
    }
}

//private struct FunctionInfo: Hashable {
//    let name: String
//    let returnType: TypeSignature
//    let parameters: [Parameter<Statement>]
//
//    init(declaration: FunctionDeclaration) {
//        self.name = declaration.name
//        self.returnType = declaration.returnType ?? .base("Void", nil, [])
//        self.parameters = declaration.parameters.map {
//            Parameter(externalName: $0.externalName, type: $0.type, isVariadic: $0.isVariadic)
//        }
//    }
//}
