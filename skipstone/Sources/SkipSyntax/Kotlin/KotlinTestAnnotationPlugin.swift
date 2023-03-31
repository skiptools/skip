/// Add the necessary JUnit `@Test` annotation to any function named "test" in any class that extens "TestCase".
///
/// - Seealso: `SkipUnit/XCTestCase.kt`
class KotlinTestAnnotationPlugin: KotlinPlugin {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        if let codebaseInfo = translator.codebaseInfo {
            syntaxTree.root.visit { visit($0, codebaseInfo: codebaseInfo) }
        }
    }

    private func visit(_ node: KotlinSyntaxNode, codebaseInfo: CodebaseInfo.Context) -> VisitResult<KotlinSyntaxNode> {
        if let functionDeclaration = node as? KotlinFunctionDeclaration,
           let owningClass = functionDeclaration.parent as? KotlinClassDeclaration {
            if functionDeclaration.name.hasPrefix("test")
                && !functionDeclaration.isStatic
                && !functionDeclaration.isGlobal {
                let signatures = codebaseInfo.inheritanceChainSignatures(for: owningClass.signature)
                if let owningType = signatures.last {
                    let infos = codebaseInfo.typeInfos(for: owningType)
                    // check for whether the containing class inherits from `XCTestCase`
                    let extendsXCTestCase = infos.contains { $0.inherits.contains(.named("XCTestCase", [])) }
                    if extendsXCTestCase {
                        functionDeclaration.annotations += ["@Test"]
                        if functionDeclaration.isAsync {
                            // TODO: add in special support for testing coroutines: https://developer.android.com/kotlin/coroutines/test
                            // @Test fun testAsyncFunction() = runTest  {
                            //     val result = asyncFunction()
                            //     assertEquals(expectedResult, result)
                            // }
                        }
                    }
                }
            }
        }

        return .recurse(nil)
    }
}

