/// Wholistic information about the codebase needed when transpiling Swift to Kotlin.
class CodebaseInfo {
    func gather(from syntaxTree: SyntaxTree) throws {
    }

    func messages(for sourceFile: Source.File) -> [Message] {
        return []
    }
}
