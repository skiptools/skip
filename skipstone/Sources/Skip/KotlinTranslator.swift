/// Translates a Swift syntax tree to Kotlin code.
struct KotlinTranslator {
    let syntaxTree: SyntaxTree
    let codebaseInfo: CodebaseInfo

    func translate() -> Transpilation {
        let kotlinSyntaxTree = translateSyntaxTree()
        let messages = codebaseInfo.messages(for: syntaxTree.source.file) + kotlinSyntaxTree.statements.flatMap { $0.allMessages }
        let outputContent = kotlinSyntaxTree.statements.map { $0.code(indentation: 0) }.joined(separator: "\n")
        let outputFile = syntaxTree.source.file.outputFile(withExtension: "kt")
        return Transpilation(sourceFile: syntaxTree.source.file, outputFile: outputFile, outputContent: outputContent, messages: messages)
    }

    func translateSyntaxTree() -> KotlinSyntaxTree {
        let statements = syntaxTree.statements.flatMap { translateStatement($0) }
        return KotlinSyntaxTree(sourceFile: syntaxTree.source.file, statements: statements)
    }

    func translateStatement(_ statement: Statement) -> [KotlinStatement] {
        if let translatable = statement as? KotlinTranslatable {
            return translatable.kotlinStatements(with: self)
        }

        // TODO

        // Fall back to a raw translation
        if let syntax = statement.syntax {
            var rawStatement = RawStatement(syntax: syntax, in: syntaxTree)!
            rawStatement.message = .untranslatableSyntax(source: syntaxTree.source, range: statement.range)
            return rawStatement.kotlinStatements(with: self)
        }
        return MessageStatement(message: .untranslatableSyntax()).kotlinStatements(with: self)
    }
}
