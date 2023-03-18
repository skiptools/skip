/// Representation of the Kotlin syntax tree.
public class KotlinSyntaxTree {
    let sourceFile: Source.File
    let dependencies: KotlinDependencies
    let root: KotlinCodeBlock

    init(sourceFile: Source.File, dependencies: KotlinDependencies = KotlinDependencies(), root: KotlinCodeBlock) {
        self.sourceFile = sourceFile
        self.dependencies = dependencies
        self.root = root
    }

    public var messages: [Message] {
        return root.subtreeMessages
    }
}
