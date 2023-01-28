/// Translates a Swift syntax tree to Kotlin code.
public struct KotlinTranslator {
    public let syntaxTree: SyntaxTree
    public let codebaseInfo: CodebaseInfo

    public init(syntaxTree: SyntaxTree, codebaseInfo: CodebaseInfo) {
        self.syntaxTree = syntaxTree
        self.codebaseInfo = codebaseInfo
    }

    /// Translate and transpile to source code.
    public func transpile() -> Transpilation {
        let kotlinSyntaxTree = translateSyntaxTree()
        let messages = codebaseInfo.messages(for: syntaxTree.source.file) + kotlinSyntaxTree.messages
        let outputFile = syntaxTree.source.file.outputFile(withExtension: "kt")
        let outputGenerator = OutputGenerator(roots: kotlinSyntaxTree.statements)
        let (output, outputMap) = outputGenerator.generateOutput(file: outputFile)
        return Transpilation(sourceFile: syntaxTree.source.file, output: output, outputMap: outputMap, messages: messages)
    }

    /// Translate syntax trees only.
    public func translateSyntaxTree() -> KotlinSyntaxTree {
        let statements = syntaxTree.statements.flatMap { translateStatement($0, parent: nil) }
        return KotlinSyntaxTree(sourceFile: syntaxTree.source.file, statements: statements)
    }

    func translateStatement(_ statement: Statement, parent: KotlinStatement?) -> [KotlinStatement] {
        if let translatable = statement as? KotlinTranslatable {
            return translatable.kotlinStatements(with: self, parent: parent)
        }

        // Fall back to a raw translation
        if let syntax = statement.syntax {
            var rawStatement = RawStatement(syntax: syntax, extras: statement.extras, in: syntaxTree)
            rawStatement.message = .untranslatableSyntax(source: syntaxTree.source, range: statement.range)
            return rawStatement.kotlinStatements(with: self, parent: parent)
        }
        return MessageStatement(message: .untranslatableSyntax()).kotlinStatements(with: self, parent: parent)
    }
}
