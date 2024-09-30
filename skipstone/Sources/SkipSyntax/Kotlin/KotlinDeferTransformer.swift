/// Update variables used to track `defer` actions to prevent collisions.
final class KotlinDeferTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        let visitor = DeferSuffixVisitor()
        syntaxTree.root.visit(perform: visitor.visit)
        return []
    }
}

/// Uniquify identifiers we use in defer statements.
private final class DeferSuffixVisitor {
    private var deferVariableSuffix = 0

    func visit(_ node: KotlinSyntaxNode) -> VisitResult<KotlinSyntaxNode> {
        if let codeBlock = node as? KotlinCodeBlock, codeBlock.deferCount > 0 {
            codeBlock.deferVariableSuffix = deferVariableSuffix
            deferVariableSuffix += 1
        }
        return .recurse(nil)
    }
}
