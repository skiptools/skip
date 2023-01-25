/// Translates a Swift syntax tree to Kotlin code.
struct KotlinTranslator {
    let codebaseInfo: CodebaseInfo

    func translate(_ syntaxTree: SyntaxTree) -> Transpilation {
        let kotlinSyntaxTree = translateSyntaxTree(syntaxTree)
        let messages = codebaseInfo.messages(for: syntaxTree.source.file) + kotlinSyntaxTree.statements.flatMap { $0.messages }
        let outputContent = kotlinSyntaxTree.statements.map { $0.code(indentation: 0) }.joined(separator: "\n")
        let outputFile = syntaxTree.source.file.outputFile(withExtension: "kt")
        return Transpilation(sourceFile: syntaxTree.source.file, outputFile: outputFile, outputContent: outputContent, messages: messages)
    }

    func translateSyntaxTree(_ syntaxTree: SyntaxTree) -> KotlinSyntaxTree {
        let statements = syntaxTree.statements.flatMap { translateStatement($0, in: syntaxTree) }
        return KotlinSyntaxTree(sourceFile: syntaxTree.source.file, statements: statements)
    }

    private func translateStatement(_ statement: Statement, in syntaxTree: SyntaxTree) -> [KotlinStatement] {
        // TODO: Children
        if let kotlinStatement = statement as? KotlinStatement {
            return [kotlinStatement]
        }

        // TODO

        // Fall back to a raw translation
        if let syntax = statement.syntax {
            return [RawStatement(syntax: syntax, source: syntaxTree.source)!]
        }
        return [MessageStatement(message: Message(severity: .error, message: "Detected untranslatable synthetic statement: \(statement.prettyPrintTree)"))]
    }
}
