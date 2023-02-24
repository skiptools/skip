/// Representation of the Kotlin syntax tree.
public class KotlinSyntaxTree {
    let sourceFile: Source.File
    let root: KotlinCodeBlockStatement

    init(sourceFile: Source.File, root: KotlinCodeBlockStatement) {
        self.sourceFile = sourceFile
        self.root = root
    }

    public var messages: [Message] {
        return root.subtreeMessages
    }
}
