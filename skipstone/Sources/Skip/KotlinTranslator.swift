/// Translates a Swift syntax tree to Kotlin code.
struct KotlinTranslator {
    let codebaseInfo: CodebaseInfo

    func translate(_ syntaxTree: SyntaxTree) throws -> Transpilation {
        return try Transpilation(sourceFile: syntaxTree.sourceFile, outputContent: syntaxTree.sourceFile.content)
    }
}
