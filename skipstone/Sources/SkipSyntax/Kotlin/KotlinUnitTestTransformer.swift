/// Convert `XCTestCase` test functions to JUnit test functions.
///
/// - Seealso: `SkipUnit/XCTestCase.kt`
final class KotlinUnitTestTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        guard !translator.syntaxTree.isBridgeFile else {
            return []
        }
        guard let codebaseInfo = translator.codebaseInfo else {
            return []
        }
        var importPackages: Set<String> = []
        syntaxTree.root.visit { visit($0, codebaseInfo: codebaseInfo, importPackages: &importPackages) }
        syntaxTree.dependencies.imports.formUnion(importPackages)
        return []
    }

    private func visit(_ node: KotlinSyntaxNode, codebaseInfo: CodebaseInfo.Context, importPackages: inout Set<String>) -> VisitResult<KotlinSyntaxNode> {
        if let functionDeclaration = node as? KotlinFunctionDeclaration, let owningClass = functionDeclaration.parent as? KotlinClassDeclaration, Self.isTestFunction(functionDeclaration, owningClass: owningClass, codebaseInfo: codebaseInfo) {
            if functionDeclaration.apiFlags.options.contains(.async) {
                transformAsyncTest(functionDeclaration: functionDeclaration, owningClass: owningClass, importPackages: &importPackages)
            } else {
                functionDeclaration.annotations += ["@Test"]
            }
            let testRunner = "@org.junit.runner.RunWith(androidx.test.ext.junit.runners.AndroidJUnit4::class)"
            if !owningClass.annotations.contains(testRunner) {
                owningClass.annotations += [testRunner]
            }
            return .skip
        }
        return .recurse(nil)
    }

    private func transformAsyncTest(functionDeclaration: KotlinFunctionDeclaration, owningClass: KotlinClassDeclaration, importPackages: inout Set<String>) {
        importPackages.insert("kotlinx.coroutines.*")
        importPackages.insert("kotlinx.coroutines.test.*")

        // Create a wrapper @Test function that will call the original async function
        let testFunctionDeclaration = KotlinFunctionDeclaration(name: "run" + functionDeclaration.name)
        testFunctionDeclaration.annotations += [
            "@OptIn(ExperimentalCoroutinesApi::class)",
            "@Test"
        ]
        testFunctionDeclaration.extras = .singleNewline

        // This wrapper code sets up and tears down the required async test environment
        let lines = [
            "val dispatcher = StandardTestDispatcher()",
            "Dispatchers.setMain(dispatcher)",
            "try {",
            "    runTest { withContext(Dispatchers.Main) { \(functionDeclaration.name)() } }",
            "} finally {",
            "    Dispatchers.resetMain()",
            "}"
        ]
        let statements = lines.map { KotlinRawStatement(sourceCode: $0) }
        let codeBlock = KotlinCodeBlock(statements: statements)
        testFunctionDeclaration.body = codeBlock

        if let testIndex = owningClass.members.firstIndex(where: { $0 === functionDeclaration }) {
            owningClass.members.insert(testFunctionDeclaration, at: testIndex)
            testFunctionDeclaration.parent = owningClass
            testFunctionDeclaration.assignParentReferences()
        }
    }

    private static func isTestFunction(_ functionDeclaration: KotlinFunctionDeclaration, owningClass: KotlinClassDeclaration, codebaseInfo: CodebaseInfo.Context) -> Bool {
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
