/// Representation of the Kotlin syntax tree.
struct KotlinSyntaxTree {
    let sourceFile: Source.File
    let statements: [KotlinStatement]

    var messages: [Message] {
        return statements.flatMap { $0.messages }
    }
}
