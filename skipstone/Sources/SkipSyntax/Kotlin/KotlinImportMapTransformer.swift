/// Hande mapping from one import to another.
class KotlinImportMapTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        var importPaths: Set<[String]> = []
        for importDeclaration in syntaxTree.root.statements.compactMap({ $0 as? KotlinImportDeclaration }) {
            if importDeclaration.modulePath.first == "OSLog"
                || importDeclaration.modulePath.first == "Dispatch"
                || importDeclaration.modulePath.first == "JavaScriptCore"
                || importDeclaration.modulePath.first == "CoreFoundation"
                || importDeclaration.modulePath.first == "CryptoKit" {
                importDeclaration.modulePath[0] = "Foundation" // Will be transpiled to skip.foundation
            }
            if !importPaths.insert(importDeclaration.modulePath).inserted {
                syntaxTree.root.remove(statement: importDeclaration)
            }
        }
    }
}
