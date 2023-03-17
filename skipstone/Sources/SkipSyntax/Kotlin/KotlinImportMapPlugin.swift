/// Handling mapping from one import to another.
///
/// TODO: this is currently hardwired with some known imports (e.g., "import XCTest" turns into "import skip.unit").
/// Eventually this should be driven by the `skip.yml` metadata.
class KotlinImportMapPlugin: KotlinPlugin {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        // TBD: rather than replacing a module name with another name like "SkipFoundation" that will be converted to "import skip.foundation", maybe we should instead have a `importDeclaration.kotlinImportOverride` that we can set
        for importDeclaration in syntaxTree.root.statements.compactMap({ $0 as? KotlinImportDeclaration }) {
            if importDeclaration.modulePath.first == "Foundation" {
                importDeclaration.modulePath[0] = "SkipFoundation"
                //importDeclaration.kotlinImportOverride = "skip.foundation"
            }
            if importDeclaration.modulePath.first == "XCTest" {
                importDeclaration.modulePath[0] = "SkipUnit"
                //importDeclaration.kotlinImportOverride = "skip.unit"
            }
            if importDeclaration.modulePath.first == "OSLog" {
                //importDeclaration.modulePath[0] = "SkipLog"
                //importDeclaration.kotlinImportOverride = "skip.log"
            }
        }
    }
}
