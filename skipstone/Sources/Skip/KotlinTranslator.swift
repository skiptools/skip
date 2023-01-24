/// Translates a Swift syntax tree to Kotlin code.
struct KotlinTranslator {
    let codebaseInfo: CodebaseInfo

    func translate(_ syntaxTree: SyntaxTree) throws -> Transpilation {
        let warnings = syntaxTree.syntax.statements.map { statement in
            let range = syntaxTree.source.range(of: statement)
            return Message(severity: .warning, message: "Unsupported syntax", source: syntaxTree.source, range: range)
        }
        return Transpilation(sourceFile: syntaxTree.source.file, messages: codebaseInfo.messages(for: syntaxTree.source.file) + warnings)
    }
}
