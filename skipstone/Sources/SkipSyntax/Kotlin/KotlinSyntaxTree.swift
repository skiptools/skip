/// Representation of the Kotlin syntax tree.
public class KotlinSyntaxTree {
    let sourceFile: Source.FilePath
    let root: KotlinCodeBlock
    var dependencies: KotlinDependencies

    init(sourceFile: Source.FilePath, root: KotlinCodeBlock, dependencies: KotlinDependencies = KotlinDependencies()) {
        self.sourceFile = sourceFile
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
