/// Representation of the Kotlin syntax tree.
public class KotlinSyntaxTree {
    let sourceFile: Source.File
    let statements: [KotlinStatement]

    init(sourceFile: Source.File, statements: [KotlinStatement]) {
        self.sourceFile = sourceFile
        self.statements = statements
    }

    public var messages: [Message] {
        return statements.flatMap { $0.subtreeMessages }
    }
}
