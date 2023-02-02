/// Translates a Swift syntax tree to Kotlin code.
public class KotlinTranslator {
    let syntaxTree: SyntaxTree
    var codebaseInfo: KotlinCodebaseInfo?

    public init(syntaxTree: SyntaxTree) {
        self.syntaxTree = syntaxTree
    }

    /// Translate and transpile to source code.
    public func transpile(codebaseInfo: KotlinCodebaseInfo) -> Transpilation {
        self.codebaseInfo = codebaseInfo
        
        let kotlinSyntaxTree = translateSyntaxTree()
        let messages = codebaseInfo.messages(for: syntaxTree.source.file) + kotlinSyntaxTree.messages
        let outputFile = syntaxTree.source.file.outputFile(withExtension: "kt")
        let outputGenerator = OutputGenerator(roots: kotlinSyntaxTree.statements)
        let (output, outputMap) = outputGenerator.generateOutput(file: outputFile)
        return Transpilation(sourceFile: syntaxTree.source.file, output: output, outputMap: outputMap, messages: messages)
    }

    /// Translate syntax trees only.
    public func translateSyntaxTree() -> KotlinSyntaxTree {
        var statements: [KotlinStatement] = []
        if let packageName = codebaseInfo?.packageName {
            statements.append(KotlinPackageDeclaration(name: packageName))
        }
        statements += syntaxTree.statements.flatMap { translateStatement($0) }
        return KotlinSyntaxTree(sourceFile: syntaxTree.source.file, statements: statements)
    }

    func translateStatement(_ statement: Statement) -> [KotlinStatement] {
        switch statement.type {
        case .assignment:
            break
        case .break:
            break
        case .catch:
            break
        case .comment:
            break
        case .continue:
            break
        case .defer:
            break
        case .do:
            break
        case .error:
            break
        case .expression:
            break
        case .for:
            break
        case .if:
            break
        case .ifDefined:
            // Inline the #if content
            return statement.children.flatMap { translateStatement($0) }
        case .return:
            break
        case .switch:
            break
        case .throw:
            break
        case .while:
            break
        case .classDeclaration:
            return [KotlinClassDeclaration.translate(statement: statement as! TypeDeclaration, translator: self)]
        case .enumDeclaration:
            break
        case .extensionDeclaration:
            return KotlinExtensionDeclaration.translate(statement: statement as! ExtensionDeclaration, translator: self)
        case .functionDeclaration:
            return [KotlinFunctionDeclaration.translate(statement: statement as! FunctionDeclaration, translator: self)]
        case .importDeclaration:
            return [KotlinImportDeclaration(statement: statement as! ImportDeclaration)]
        case .initDeclaration:
            break
        case .protocolDeclaration:
            return [KotlinInterfaceDeclaration.translate(statement: statement as! TypeDeclaration, translator: self)]
        case .structDeclaration:
            return [KotlinClassDeclaration.translate(statement: statement as! TypeDeclaration, translator: self)]
        case .typealiasDeclaration:
            break
        case .variableDeclaration:
            return [KotlinVariableDeclaration.translate(statement: statement as! VariableDeclaration, translator: self)]
        case .raw:
            return [KotlinRawStatement(statement: statement as! RawStatement)]
        case .message:
            return [KotlinMessageStatement(statement: statement)]
        }

        // Fall back to a raw translation and associated warning
        if let syntax = statement.syntax {
            let rawStatement = RawStatement(syntax: syntax, extras: statement.extras, in: syntaxTree)
            let krawStatement = KotlinRawStatement(statement: rawStatement)
            krawStatement.statementMessages = [.kotlinUntranslatable(statement: statement, source: syntaxTree.source, range: statement.range)]
            return [krawStatement]
        }
        return [KotlinMessageStatement(message: .kotlinUntranslatable(statement: statement))]
    }
}
