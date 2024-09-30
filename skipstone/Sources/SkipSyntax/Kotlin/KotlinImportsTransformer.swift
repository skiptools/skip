/// Consolidate and map import statements to Skip modules.
final class KotlinImportsTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        // There's no point in running this transformer in the symbol gathering phase
        guard translator.codebaseInfo != nil else {
            return []
        }

        // Translate imports and remove redundancies
        var importPaths: Set<[String]> = []
        var additionalImportDeclarations: [KotlinImportDeclaration] = []
        var lastImportDeclaration: KotlinImportDeclaration? = nil
        for importDeclaration in syntaxTree.root.statements.compactMap({ $0 as? KotlinImportDeclaration }) {
            let modulePaths = translateImport(modulePath: importDeclaration.modulePath)
            for i in 0..<modulePaths.count {
                if importPaths.insert(modulePaths[i]).inserted {
                    if i == 0 {
                        importDeclaration.modulePath = modulePaths[i]
                        lastImportDeclaration = importDeclaration
                    } else {
                        additionalImportDeclarations.append(KotlinImportDeclaration(modulePath: modulePaths[i]))
                    }
                } else if i == 0 {
                    syntaxTree.root.remove(statement: importDeclaration)
                }
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
        for additionalModulePath in additionalModulePaths {
            let modulePaths = translateImport(modulePath: additionalModulePath)
            for modulePath in modulePaths {
                if importPaths.insert(modulePath).inserted {
                    additionalImportDeclarations.append(KotlinImportDeclaration(modulePath: modulePath))
                }
            }
        }
        syntaxTree.root.insert(statements: additionalImportDeclarations, after: lastImportDeclaration)
        return []
    }

    private func translateImport(modulePath: [String]) -> [[String]] {
        if modulePath.count == 1, let skipModuleNames = CodebaseInfo.moduleNameMap[modulePath[0]] {
            return skipModuleNames.map { [$0] }
        }
        return [modulePath]
    }
}
