/// Translates a Swift syntax tree to Kotlin code.
public class KotlinTranslator {
    let syntaxTree: SyntaxTree
    private(set) var codebaseInfo: KotlinCodebaseInfo.Context?
    private(set) var packageName: String?

    public init(syntaxTree: SyntaxTree) {
        self.syntaxTree = syntaxTree
    }

    /// Converts a `CamelCased` module name to a `lower.cased` dot-separated package name.
    /// - Parameters:
    ///   - moduleName: The module name to convert.
    ///   - fallbackPrefix: The package name to prefix if the module name doesn't result in a package name containing dots.
    /// - Returns: The dot-separated package name.
    public static func packageName(forModule moduleName: String, fallbackPrefix: String? = "skipmodule") -> String {
        var lastLower = false
        var packageName = ""
        var hasDot = false
        for c in moduleName {
            let lower = c.lowercased()
            if lower == String(c) {
                lastLower = true
            } else {
                if lastLower == true {
                    packageName += "."
                    hasDot = true
                }
                lastLower = false
            }
            packageName += lower
        }
        if !hasDot, let fallbackPrefix = fallbackPrefix {
            packageName = fallbackPrefix + "." + packageName
        }
        return packageName
    }

    /// Translate and transpile to source code.
    public func transpile(codebaseInfo: KotlinCodebaseInfo) -> Transpilation {
        let importedModuleNames: [String] = syntaxTree.root.statements.compactMap { statement in
            guard statement.type == .importDeclaration, let importDeclaration = statement as? ImportDeclaration else {
                return nil
            }
            return importDeclaration.modulePath.first
        }
        let codebaseInfoContext = codebaseInfo.context(importedModuleNames: importedModuleNames, sourceFile: syntaxTree.source.file)
        self.codebaseInfo = codebaseInfoContext
        self.packageName = codebaseInfo.packageName

        let kotlinSyntaxTree = translateSyntaxTree()
        kotlinSyntaxTree.root.assignParentReferences()
        for plugin in codebaseInfo.plugins {
            plugin.apply(to: kotlinSyntaxTree, translator: self)
        }

        let messages = codebaseInfo.messages(for: syntaxTree.source.file) + kotlinSyntaxTree.messages
        let outputFile = syntaxTree.source.file.outputFile(withExtension: "kt")
        let outputGenerator = OutputGenerator(root: kotlinSyntaxTree.root)
        let (output, outputMap) = outputGenerator.generateOutput(file: outputFile)
        return Transpilation(sourceFile: syntaxTree.source.file, output: output, outputMap: outputMap, messages: messages)
    }

    /// Translate syntax trees only.
    public func translateSyntaxTree() -> KotlinSyntaxTree {
        var packageStatements: [KotlinStatement] = []
        if let packageName {
            packageStatements = [
                KotlinRawStatement(sourceCode: "package \(packageName)"),
                KotlinRawStatement(sourceCode: ""),
            ]
        }
        let requiredImportStatements = [
            KotlinRawStatement(sourceCode: "import skip.lib.*"),
            KotlinRawStatement(sourceCode: "import skip.lib.Array"), // Override kotlin.Array
            KotlinRawStatement(sourceCode: ""),
        ]
        let translatedStatements = syntaxTree.root.statements.flatMap { translateStatement($0) }
        return KotlinSyntaxTree(sourceFile: syntaxTree.source.file, root: KotlinCodeBlock(statements: packageStatements + requiredImportStatements + translatedStatements))
    }

    func translateStatement(_ statement: Statement) -> [KotlinStatement] {
        switch statement.type {
        case .break:
            return [KotlinBreak(statement: statement as! Break)]
        case .catch:
            break
        case .codeBlock:
            return [KotlinCodeBlock.translate(statement: statement as! CodeBlock, translator: self)]
        case .continue:
            return [KotlinContinue(statement: statement as! Continue)]
        case .defer:
            return [KotlinDefer.translate(statement: statement as! Defer, translator: self)]
        case .do:
            break
        case .expression:
            return [KotlinExpressionStatement.translate(statement: statement as! ExpressionStatement, translator: self)]
        case .fallthrough:
            return [KotlinMessageStatement(message: .kotlinSwitchFallthrough(statement))]
        case .forLoop:
            return [KotlinForLoop.translate(statement: statement as! ForLoop, translator: self)]
        case .guard:
            return [KotlinIf.translate(statement: statement as! Guard, translator: self)]
        case .ifDefined:
            // This should never happen, as we never make the IfDefined statement part of the syntax tree
            return []
        case .labeled:
            return [KotlinLabeledStatement.translate(statement: statement as! LabeledStatement, translator: self)]
        case .return:
            return [KotlinReturn.translate(statement: statement as! Return, translator: self)]
        case .throw:
            break
        case .whileLoop:
            return [KotlinWhileLoop.translate(statement: statement as! WhileLoop, translator: self)]
        case .classDeclaration:
            return [KotlinClassDeclaration.translate(statement: statement as! TypeDeclaration, translator: self)]
        case .enumCaseDeclaration:
            return [KotlinEnumCaseDeclaration.translate(statement: statement as! EnumCaseDeclaration, translator: self)]
        case .enumDeclaration:
            return [KotlinClassDeclaration.translate(statement: statement as! TypeDeclaration, translator: self)]
        case .extensionDeclaration:
            return KotlinExtensionDeclaration.translate(statement: statement as! ExtensionDeclaration, translator: self)
        case .functionDeclaration:
            return [KotlinFunctionDeclaration.translate(statement: statement as! FunctionDeclaration, translator: self)]
        case .importDeclaration:
            return [KotlinImportDeclaration(statement: statement as! ImportDeclaration)]
        case .initDeclaration:
            return [KotlinFunctionDeclaration.translate(statement: statement as! FunctionDeclaration, translator: self)]
        case .protocolDeclaration:
            return [KotlinInterfaceDeclaration.translate(statement: statement as! TypeDeclaration, translator: self)]
        case .structDeclaration:
            return [KotlinClassDeclaration.translate(statement: statement as! TypeDeclaration, translator: self)]
        case .typealiasDeclaration:
            return [KotlinTypealiasDeclaration(statement: statement as! TypealiasDeclaration)]
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
        do {
            switch expression.type {
            case .arrayLiteral:
                return KotlinArrayLiteral.translate(expression: expression as! ArrayLiteral, translator: self)
            case .binaryOperator:
                return KotlinBinaryOperator.translate(expression: expression as! BinaryOperator, translator: self)
            case .booleanLiteral:
                return KotlinBooleanLiteral(expression: expression as! BooleanLiteral)
            case .closure:
                return KotlinClosure.translate(expression: expression as! Closure, translator: self)
            case .dictionaryLiteral:
                return KotlinDictionaryLiteral.translate(expression: expression as! DictionaryLiteral, translator: self)
            case .functionCall:
                return KotlinFunctionCall.translate(expression: expression as! FunctionCall, translator: self)
            case .identifier:
                return KotlinIdentifier.translate(expression: expression as! Identifier, translator: self)
            case .if:
                return KotlinIf.translate(expression: expression as! If, translator: self)
            case .inout:
                return KotlinInOut.translate(expression: expression as! InOut, translator: self)
            case .matchingPattern:
                //~~~
                throw Message.kotlinUntranslatable(expression, source: syntaxTree.source)
            case .memberAccess:
                return KotlinMemberAccess.translate(expression: expression as! MemberAccess, translator: self)
            case .nilLiteral:
                return KotlinNullLiteral(expression: expression as! NilLiteral)
            case .numericLiteral:
                return KotlinNumericLiteral(expression: expression as! NumericLiteral)
            case .optionalBinding:
                return KotlinOptionalBinding.translateCondition(expression: expression as! OptionalBinding, translator: self)
            case .parenthesized:
                return KotlinParenthesized.translate(expression: expression as! Parenthesized, translator: self)
            case .prefixOperator:
                return KotlinPrefixOperator.translate(expression: expression as! PrefixOperator, translator: self)
            case .postfixOptionalOperator:
                return KotlinPostfixOptionalOperator.translate(expression: expression as! PostfixOptionalOperator, translator: self)
            case .stringLiteral:
                return KotlinStringLiteral.translate(expression: expression as! StringLiteral, translator: self)
            case .subscript:
                return KotlinSubscript.translate(expression: expression as! Subscript, translator: self)
            case .switch:
                //~~~
                throw Message.kotlinUntranslatable(expression, source: syntaxTree.source)
            case .switchCase:
                //~~~
                throw Message.kotlinUntranslatable(expression, source: syntaxTree.source)
            case .ternaryOperator:
                return KotlinTernaryOperator.translate(expression: expression as! TernaryOperator, translator: self)
            case .try:
                return KotlinTry.translate(expression: expression as! Try, translator: self)
            case .tupleLiteral:
                return try KotlinTupleLiteral.translate(expression: expression as! TupleLiteral, translator: self)
            case .typeLiteral:
                return KotlinTypeLiteral(expression: expression as! TypeLiteral)
            case .raw:
                return KotlinRawExpression(expression: expression as! RawExpression)
            }
        } catch {
            let message = error as? Message ?? Message.kotlinUntranslatable(expression)
            let rawExpression: RawExpression
            if let syntax = expression.syntax {
                rawExpression = RawExpression(syntax: syntax, message: message, in: syntaxTree)
            } else {
                rawExpression = RawExpression(sourceCode: "?", message: message, range: expression.sourceRange, in: syntaxTree)
            }
            return KotlinRawExpression(expression: rawExpression)
        }
    }
}
