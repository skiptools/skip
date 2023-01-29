/// Representation of the Kotlin syntax tree.
class KotlinSyntaxTree {
    let sourceFile: Source.File
    let statements: [KotlinStatement]

    init(sourceFile: Source.File, statements: [KotlinStatement]) {
        self.sourceFile = sourceFile
        self.statements = statements
    }

    var messages: [Message] {
        return statements.flatMap { $0.messages }
    }
}
