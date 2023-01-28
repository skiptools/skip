/// Representation of the Kotlin syntax tree.
public class KotlinSyntaxTree {
    public let sourceFile: Source.File
    let statements: [KotlinStatement]

    init(sourceFile: Source.File, statements: [KotlinStatement]) {
        self.sourceFile = sourceFile
        self.statements = statements
    }

    public var prettyPrintTree: PrettyPrintTree {
        let root = sourceFile.outputFile(withExtension: "kt").name
        return PrettyPrintTree(root: root, children: statements.map { $0.prettyPrintTree })
    }

    public var messages: [Message] {
        return statements.flatMap { $0.messages }
    }
}
