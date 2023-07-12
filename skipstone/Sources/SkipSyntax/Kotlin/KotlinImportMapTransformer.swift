/// Consolidate and map import statements to Skip modules.
final class KotlinImportMapTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        // There's no point in running this transformer in the symbol gathering phase
        guard translator.codebaseInfo != nil else {
            return
        }

        // Translate imports and remove redundancies
        var importPaths: Set<[String]> = []
        var lastImportDeclaration: KotlinImportDeclaration? = nil
        for importDeclaration in syntaxTree.root.statements.compactMap({ $0 as? KotlinImportDeclaration }) {
            importDeclaration.modulePath = translateImport(modulePath: importDeclaration.modulePath)
            if importPaths.insert(importDeclaration.modulePath).inserted {
                lastImportDeclaration = importDeclaration
            } else {
                syntaxTree.root.remove(statement: importDeclaration)
            }
        }

        // Gather imports that were added to support moved extensions
        var additionalModulePaths: [[String]] = []
        syntaxTree.root.visit {
            if let classDeclaration = $0 as? KotlinClassDeclaration {
                additionalModulePaths += classDeclaration.movedExtensionImportModulePaths
            } else if let interfaceDeclaration = $0 as? KotlinInterfaceDeclaration {
                additionalModulePaths += interfaceDeclaration.movedExtensionImportModulePaths
            }
            return .recurse(nil)
        }
        var additionalImportDeclarations: [KotlinImportDeclaration] = []
        for modulePath in additionalModulePaths {
            let modulePath = translateImport(modulePath: modulePath)
            if importPaths.insert(modulePath).inserted {
                additionalImportDeclarations.append(KotlinImportDeclaration(modulePath: modulePath))
            }
        }
        syntaxTree.root.insert(statements: additionalImportDeclarations, after: lastImportDeclaration)
    }

    private func translateImport(modulePath: [String]) -> [String] {
        var modulePath = modulePath
        if modulePath.count == 1, let skipModuleName = CodebaseInfo.moduleNameMap[modulePath[0]] {
            modulePath[0] = skipModuleName
        }
        return modulePath
    }
}
