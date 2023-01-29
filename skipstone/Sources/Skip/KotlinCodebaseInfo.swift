/// Wholistic information about the codebase needed when transpiling Swift to Kotlin.
class KotlinCodebaseInfo {
    init() {
    }

    func gather(from syntaxTree: SyntaxTree) {
        syntaxTree.statements.forEach { gather(from: $0) }
    }

    func messages(for sourceFile: Source.File) -> [Message] {
        return []
    }

    // TODO
    private var concreteTypeNames: Set<String> = []
    private var extensionDeclarations: [String: [ExtensionDeclaration]] = [:]

    private func gather(from statement: Statement) {
        switch statement.type {
        case .classDeclaration:
            concreteTypeNames.insert((statement as! ClassDeclaration).name)
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

    func extensions(ofConcreteType typeName: String) -> [ExtensionDeclaration] {
        return extensionDeclarations[typeName] ?? []
    }

    func isConcreteType(_ typeName: String) -> Bool {
        return concreteTypeNames.contains(typeName)
    }
}
