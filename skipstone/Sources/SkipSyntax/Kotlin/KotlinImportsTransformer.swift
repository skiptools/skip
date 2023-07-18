/// Consolidate and map import statements to Skip modules.
final class KotlinImportsTransformer: KotlinTransformer {
    // Same-named types that are implicitly imported by both Swift and Kotlin
    private static let conflictingTypes: Set<String> = [
        "Array",
        "Collection",
        "Sequence",
        "Set",
    ]


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
        var additionalImportDependencies: Set<String> = []
        syntaxTree.root.visit {
            if let classDeclaration = $0 as? KotlinClassDeclaration {
                additionalModulePaths += classDeclaration.movedExtensionImportModulePaths
            } else if let interfaceDeclaration = $0 as? KotlinInterfaceDeclaration {
                additionalModulePaths += interfaceDeclaration.movedExtensionImportModulePaths
            }
            addImportDependencies(for: $0, to: &additionalImportDependencies)
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
        syntaxTree.dependencies.imports.formUnion(additionalImportDependencies)
    }

    private func translateImport(modulePath: [String]) -> [String] {
        var modulePath = modulePath
        if modulePath.count == 1, let skipModuleName = CodebaseInfo.moduleNameMap[modulePath[0]] {
            modulePath[0] = skipModuleName
        }
        return modulePath
    }

    private func addImportDependencies(for node: KotlinSyntaxNode, to set: inout Set<String>) {
        //~~~
        // identifiers, memberaccess,
        // extends signature on members
        // variable types, type literals, cast targets, function params, function return type, function generics, class generics, protocol generics, extends generics
        // Watch out for e.g. Array<T>.self
    }
}
