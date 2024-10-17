/// Generate the `Bundle.module` extension if it is needed within the module.
final class KotlinModuleBundleTransformer: KotlinTransformer {
    private var needsModuleBundle = false

    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        guard !needsModuleBundle else {
            return []
        }
        guard !translator.syntaxTree.isBridgeFile else {
            return []
        }
        // No need to add Bundle.module if not a full build
        guard translator.codebaseInfo != nil else {
            return []
        }
        guard syntaxTree.root.statements.compactMap({ $0 as? KotlinImportDeclaration }).contains(where: { $0.modulePath.first == "Foundation" || $0.modulePath.first == "SkipFoundation" || $0.modulePath.first == "SwiftUI" || $0.modulePath.first == "SkipUI" }) else {
            return []
        }

        syntaxTree.root.visit { node in
            if !needsModuleBundle, let memberAccess = node as? KotlinMemberAccess, memberAccess.member == "module" {
                needsModuleBundle = memberAccess.isBaseType(named: "Bundle", moduleName: "Foundation")
            }
            return .recurse(nil)
        }
        return []
    }

    func apply(toPackage syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> Bool {
        guard needsModuleBundle else {
            return false
        }
        
        let declarations = [
            "internal val skip.foundation.Bundle.Companion.module: skip.foundation.Bundle",
            "    get() = _moduleBundle",
            "private val _moduleBundle : skip.foundation.Bundle by lazy { skip.foundation.Bundle(_ModuleBundleLocator::class) }",
            "internal class _ModuleBundleLocator {}"
        ]
        let statements = declarations.map { KotlinRawStatement(sourceCode: $0) }
        statements[0].extras = .singleNewline
        syntaxTree.root.insert(statements: statements, after: syntaxTree.root.statements.last)
        return true
    }
}
