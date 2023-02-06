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
        var kstatements = syntaxTree.statements.flatMap { translateStatement($0) }
        kstatements = addSkipFoundationImport(to: kstatements)
        if let packageName = codebaseInfo?.packageName {
            kstatements.insert(KotlinRawStatement(sourceCode: ""), at: 0)
            kstatements.insert(KotlinPackageDeclaration(name: packageName), at: 0)
        }
        return KotlinSyntaxTree(sourceFile: syntaxTree.source.file, statements: kstatements)
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
            return [KotlinExpressionStatement.translate(statement: statement as! ExpressionStatement, translator: self)]
        case .for:
            break
        case .if:
            break
        case .ifDefined:
            // Inline the #if content
            return (statement as! IfDefined).statements.flatMap { translateStatement($0) }
        case .return:
            return [KotlinReturn.translate(statement: statement as! Return, translator: self)]
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
            let message = Message.kotlinUntranslatable(statement)
            let rawStatement = RawStatement(syntax: syntax, message: message, extras: statement.extras, in: syntaxTree)
            let krawStatement = KotlinRawStatement(statement: rawStatement)
            return [krawStatement]
        }
        return [KotlinMessageStatement(message: .kotlinUntranslatable(statement))]
    }

    func translateExpression(_ expression: Expression) -> KotlinExpression {
        switch expression.type {
        case .arrayLiteral:
            return KotlinArrayLiteral.translate(expression: expression as! ArrayLiteral, translator: self)
        case .binaryOperator:
            return KotlinBinaryOperator.translate(expression: expression as! BinaryOperator, translator: self)
        case .booleanLiteral:
            return KotlinBooleanLiteral(expression: expression as! BooleanLiteral)
        case .functionCall:
            return KotlinFunctionCall.translate(expression: expression as! FunctionCall, translator: self)
        case .identifier:
            return KotlinIdentifier(expression: expression as! Identifier)
        case .memberAccess:
            return KotlinMemberAccess.translate(expression: expression as! MemberAccess, translator: self)
        case .numericLiteral:
            return KotlinNumericLiteral(expression: expression as! NumericLiteral)
        case .stringLiteral:
            return KotlinStringLiteral.translate(expression: expression as! StringLiteral, translator: self)
        case .raw:
            return KotlinRawExpression(expression: expression as! RawExpression)
        }

        // Fall back to a raw translation and associated warning
//        let message = Message.kotlinUntranslatable(expression: expression)
//        let rawExpression: RawExpression
//        if let syntax = expression.syntax {
//            rawExpression = RawExpression(syntax: syntax, message: message, in: syntaxTree)
//        } else {
//            rawExpression = RawExpression(sourceCode: "?", message: message, range: expression.range, in: syntaxTree)
//        }
//        return KotlinRawExpression(expression: rawExpression)
    }

    /// We depend on `SkipFoundation` for core functionality, so import it in all Kotlin translations.
    private func addSkipFoundationImport(to statements: [KotlinStatement]) -> [KotlinStatement] {
        var newStatements: [KotlinStatement] = []
        var lastImportIndex: Int? = nil
        for (index, statement) in statements.enumerated() {
            guard let importStatement = statement as? KotlinImportDeclaration else {
                newStatements.append(statement)
                continue
            }
            if importStatement.modulePath == ["SkipFoundation"] {
                return statements
            }
            lastImportIndex = index
            newStatements.append(statement)
        }

        let foundationImport = KotlinImportDeclaration(modulePath: ["SkipFoundation"])
        if let lastImportIndex {
            newStatements.insert(foundationImport, at: lastImportIndex + 1)
        } else {
            newStatements.insert(KotlinRawStatement(sourceCode: ""), at: 0)
            newStatements.insert(foundationImport, at: 0)
        }
        return newStatements
    }
}
