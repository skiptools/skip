/// Representation of the Kotlin syntax tree.
public class KotlinSyntaxTree {
    let sourceFile: Source.FilePath
    let root: KotlinCodeBlock
    var dependencies: KotlinDependencies
    public var messages: [Message]

    init(sourceFile: Source.FilePath, root: KotlinCodeBlock, dependencies: KotlinDependencies = KotlinDependencies()) {
        self.sourceFile = sourceFile
        self.root = root
        self.dependencies = dependencies
        self.messages = root.subtreeMessages
    }
}
