/// Representation of the Kotlin syntax tree.
public class KotlinSyntaxTree {
    let source: Source
    let root: KotlinCodeBlock
    var dependencies: KotlinDependencies

    init(source: Source, root: KotlinCodeBlock, dependencies: KotlinDependencies = KotlinDependencies()) {
        self.source = source
        self.root = root
        self.dependencies = dependencies
    }

    public var messages: [Message] {
        guard !root.statements.contains(where: { $0.extras?.isSymbolFile == true }) else {
            return []
        }
        return root.subtreeMessages
    }
}
