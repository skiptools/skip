/// Handling mapping from one import to another.
///
/// TODO: this is currently hardwired with some known imports (e.g., "import XCTest" turns into "import skip.unit").
/// Eventually this should be driven by the `skip.yml` metadata.
class KotlinImportMapTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        for importDeclaration in syntaxTree.root.statements.compactMap({ $0 as? KotlinImportDeclaration }) {
            if let moduleName = importDeclaration.modulePath.first, let mappedName = CodebaseInfo.moduleNameMap[moduleName] {
                importDeclaration.modulePath[0] = mappedName
            }
            // TODO: This can cause duplicate imports
            if importDeclaration.modulePath.first == "OSLog"
                || importDeclaration.modulePath.first == "Dispatch"
                || importDeclaration.modulePath.first == "JavaScriptCore"
                || importDeclaration.modulePath.first == "CoreFoundation"
                || importDeclaration.modulePath.first == "CryptoKit" {
                importDeclaration.modulePath[0] = "SkipFoundation"
            }
        }
    }
}
