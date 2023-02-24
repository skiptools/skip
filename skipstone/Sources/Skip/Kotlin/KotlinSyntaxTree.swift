/// Representation of the Kotlin syntax tree.
public class KotlinSyntaxTree {
    let sourceFile: Source.File
    let root: KotlinCodeBlock

    init(sourceFile: Source.File, root: KotlinCodeBlock) {
        self.sourceFile = sourceFile
        self.root = root
    }

    public var messages: [Message] {
        return root.subtreeMessages
    }
}
