/// Consolidate and map import statements to Skip modules.
final class KotlinImportMapTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        var importPaths: Set<[String]> = []
        for importDeclaration in syntaxTree.root.statements.compactMap({ $0 as? KotlinImportDeclaration }) {
            if let moduleName = importDeclaration.modulePath.first, let skipModuleName = CodebaseInfo.moduleNameMap[moduleName] {
                importDeclaration.modulePath[0] = skipModuleName
            }
            if !importPaths.insert(importDeclaration.modulePath).inserted {
                syntaxTree.root.remove(statement: importDeclaration)
            }
        }
    }
}
