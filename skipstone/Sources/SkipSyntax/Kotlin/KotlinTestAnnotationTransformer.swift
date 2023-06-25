/// Add the necessary JUnit `@Test` annotation to any function named "test" in any class that extens "TestCase".
///
/// - Seealso: `SkipUnit/XCTestCase.kt`
final class KotlinTestAnnotationTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        if let codebaseInfo = translator.codebaseInfo {
            syntaxTree.root.visit { visit($0, codebaseInfo: codebaseInfo) }
        }
    }

    private func visit(_ node: KotlinSyntaxNode, codebaseInfo: CodebaseInfo.Context) -> VisitResult<KotlinSyntaxNode> {
        if let functionDeclaration = node as? KotlinFunctionDeclaration, Self.isTestFunction(functionDeclaration, owningClass: functionDeclaration.parent as? KotlinClassDeclaration, codebaseInfo: codebaseInfo) {
            functionDeclaration.annotations += ["@Test"]
            return .skip
        }
        return .recurse(nil)
    }

    static func isTestFunction(_ functionDeclaration: KotlinFunctionDeclaration, owningClass: KotlinClassDeclaration?, codebaseInfo: CodebaseInfo.Context) -> Bool {
        guard let owningClass else {
            return false
        }
        guard functionDeclaration.name.hasPrefix("test") && !functionDeclaration.isStatic && functionDeclaration.role != .global else {
            return false
        }
        if !functionDeclaration.parameters.isEmpty {
            return false
        }
        let signatures = codebaseInfo.global.inheritanceChainSignatures(forNamed: owningClass.signature)
        guard let owningType = signatures.last else {
            return false
        }
        let infos = codebaseInfo.typeInfos(forNamed: owningType)
        // check for whether the containing class inherits from `XCTestCase`
        return infos.contains { $0.inherits.contains { $0.isNamed("XCTestCase", moduleName: "XCTest", generics: []) } }
    }
}
