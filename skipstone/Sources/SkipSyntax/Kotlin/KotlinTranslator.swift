import Foundation

/// Translates a Swift syntax tree to Kotlin code.
public final class KotlinTranslator {
    let syntaxTree: SyntaxTree
    private(set) var codebaseInfo: CodebaseInfo.Context?
    private(set) var packageName: String?

    public init(syntaxTree: SyntaxTree) {
        self.syntaxTree = syntaxTree
    }

    /// Converts a `CamelCased` module name to a `lower.cased` dot-separated package name.
    /// - Parameters:
    ///   - moduleName: The module name to convert.
    /// - Returns: The dot-separated package name.
    public static func packageName(forModule moduleName: String, withDefaultPackageSuffix: String? = "module", trimTests: Bool = true) -> String {
        // Map from e.g. Foundation to SkipFoundation
        let moduleName = CodebaseInfo.moduleNameMap[moduleName]?.first ?? moduleName

        // Turn into package name
        var lastLower = false
        var packageName = ""
        for c in moduleName {
            let lower = c.lowercased()
            if lower == String(c) {
                lastLower = true
            } else {
                if lastLower == true {
                    packageName += "."
                }
                lastLower = false
            }
            packageName += lower
        }

        // Android disallows single top-level package names
        if let packageSuffix = withDefaultPackageSuffix, !packageName.contains(".") {
            packageName += "." + packageSuffix
        }

        // the "Tests" module suffix is special: in Swift XXX and XXXTest are different modules (with a @testable import to allow the tests to access internal symbols), but in Kotlin, test cases need to be in the same package in order to be able to access the symbols
        if trimTests && packageName.hasSuffix(".tests") {
            packageName = String(packageName.dropLast(".tests".count))
        }
        if trimTests && packageName.hasSuffix("tests") {
            packageName = String(packageName.dropLast("tests".count))
        }
        return packageName
    }

    /// Translate and transpile to source code.
    public func transpile(codebaseInfo: CodebaseInfo, transformers: [KotlinTransformer], startTime: TimeInterval) -> [Transpilation] {
        let importedModuleNames = syntaxTree.root.statements.importedModulePaths.compactMap(\.moduleName)
        let codebaseInfoContext = codebaseInfo.context(importedModuleNames: importedModuleNames, sourceFile: syntaxTree.source.file)
        self.codebaseInfo = codebaseInfoContext
        self.packageName = codebaseInfo.kotlin?.packageName

        let kotlinSyntaxTree = translateSyntaxTree()
        let outputs = transformers.flatMap { $0.apply(to: kotlinSyntaxTree, translator: self) }
        addPackageAndRequiredImportStatements(to: kotlinSyntaxTree)

        return transpilations(for: kotlinSyntaxTree, codebaseInfo: codebaseInfo, transformers: transformers, input: kotlinSyntaxTree.source, outputs: outputs, startTime: startTime)
    }

    /// Transpile the package support file containing any needed package-level code.
    public static func transpilePackageSupport(sourceFile: Source.FilePath, codebaseInfo: CodebaseInfo, transformers: [KotlinTransformer]) -> [Transpilation] {
        let startTime = Date().timeIntervalSinceReferenceDate
        let source = Source(file: sourceFile, content: "")
        let syntaxTree = SyntaxTree(source: source)
        let translator = KotlinTranslator(syntaxTree: syntaxTree)
        let codebaseInfoContext = codebaseInfo.context(sourceFile: sourceFile)
        translator.codebaseInfo = codebaseInfoContext
        translator.packageName = codebaseInfo.kotlin?.packageName

        let kotlinSyntaxTree = translator.translateSyntaxTree()
        let outputs = transformers.flatMap { $0.apply(toPackage: kotlinSyntaxTree, translator: translator) }
        let packageSyntaxTree: KotlinSyntaxTree? = kotlinSyntaxTree.root.statements.isEmpty ? nil : kotlinSyntaxTree
        if let packageSyntaxTree {
            translator.addPackageAndRequiredImportStatements(to: packageSyntaxTree)
        }

        let transpilations = translator.transpilations(for: packageSyntaxTree, codebaseInfo: codebaseInfo, transformers: transformers, input: source, outputs: outputs, startTime: startTime)
        return transpilations
    }

    /// Translate syntax trees only.
    public func translateSyntaxTree() -> KotlinSyntaxTree {
        let translatedStatements = syntaxTree.root.statements.flatMap { translateStatement($0) }
        let importsFirstStatements = moveImportsToTop(statements: translatedStatements)
        let dependencies = gatherDependencies(from: importsFirstStatements)
        let kotlinRoot = KotlinCodeBlock(statements: importsFirstStatements)
        kotlinRoot.messages = syntaxTree.root.messages
        let kotlinSyntaxTree = KotlinSyntaxTree(source: syntaxTree.source, isBridgeFile: syntaxTree.isBridgeFile, autoBridge: syntaxTree.autoBridge, root: kotlinRoot, dependencies: dependencies)
        kotlinSyntaxTree.root.assignParentReferences()
        return kotlinSyntaxTree
    }

    func translateStatement(_ statement: Statement) -> [KotlinStatement] {
        do {
            switch statement.type {
            case .break:
                return [KotlinBreak(statement: statement as! Break)]
            case .codeBlock:
                return [KotlinCodeBlock.translate(statement: statement as! CodeBlock, translator: self)]
            case .continue:
                return [KotlinContinue(statement: statement as! Continue)]
            case .defer:
                return [KotlinDefer.translate(statement: statement as! Defer, translator: self)]
            case .discard:
                throw Message.kotlinDiscard(statement, source: syntaxTree.source)
            case .doCatch:
                return [KotlinTryCatch.translate(statement: statement as! DoCatch, translator: self)]
            case .empty:
                return [KotlinEmpty(statement: statement as! Empty)]
            case .expression:
                return [KotlinExpressionStatement.translate(statement: statement as! ExpressionStatement, translator: self)]
            case .fallthrough:
                return [KotlinMessageStatement(message: .kotlinSwitchFallthrough(statement, source: syntaxTree.source), statement: statement)]
            case .forLoop:
                return [KotlinForLoop.translate(statement: statement as! ForLoop, translator: self)]
            case .guard:
                return [KotlinIf.translate(statement: statement as! Guard, translator: self)]
            case .ifDefined:
                // This should never happen, as we never make the IfDefined statement part of the syntax tree
                break
            case .labeled:
                return [KotlinLabeledStatement.translate(statement: statement as! LabeledStatement, translator: self)]
            case .return:
                return [KotlinReturn.translate(statement: statement as! Return, translator: self)]
            case .throw:
                return [KotlinThrow.translate(statement: statement as! Throw, translator: self)]
            case .whileLoop:
                return [KotlinWhileLoop.translate(statement: statement as! WhileLoop, translator: self)]
            case .actorDeclaration:
                return KotlinClassDeclaration.translate(statement: statement as! TypeDeclaration, translator: self)
            case .classDeclaration:
                return KotlinClassDeclaration.translate(statement: statement as! TypeDeclaration, translator: self)
            case .deinitDeclaration:
                return [KotlinFunctionDeclaration.translate(statement: statement as! FunctionDeclaration, translator: self)]
            case .enumCaseDeclaration:
                return [KotlinEnumCaseDeclaration.translate(statement: statement as! EnumCaseDeclaration, translator: self)]
            case .enumDeclaration:
                return KotlinClassDeclaration.translate(statement: statement as! TypeDeclaration, translator: self)
            case .extensionDeclaration:
                return KotlinExtensionDeclaration.translate(statement: statement as! ExtensionDeclaration, translator: self)
            case .functionDeclaration:
                return [KotlinFunctionDeclaration.translate(statement: statement as! FunctionDeclaration, translator: self)]
            case .importDeclaration:
                return [KotlinImportDeclaration.translate(statement: statement as! ImportDeclaration, translator: self)]
            case .initDeclaration:
                return [KotlinFunctionDeclaration.translate(statement: statement as! FunctionDeclaration, translator: self)]
            case .protocolDeclaration:
                return KotlinInterfaceDeclaration.translate(statement: statement as! TypeDeclaration, translator: self)
            case .structDeclaration:
                return KotlinClassDeclaration.translate(statement: statement as! TypeDeclaration, translator: self)
            case .subscriptDeclaration:
                return KotlinFunctionDeclaration.translate(statement: statement as! SubscriptDeclaration, translator: self)
            case .typealiasDeclaration:
                return KotlinTypealiasDeclaration.translate(statement: statement as! TypealiasDeclaration, translator: self)
            case .unbridgedMemberDeclaration:
                // This should never happen
                break
            case .variableDeclaration:
                return [KotlinVariableDeclaration.translate(statement: statement as! VariableDeclaration, translator: self)]
            case .raw:
                return [KotlinRawStatement(statement: statement as! RawStatement)]
            case .message:
                return [KotlinMessageStatement(statement: statement)]
            }
            throw Message.kotlinUntranslatable(statement, source: syntaxTree.source)
        } catch {
            let message = error as? Message ?? Message.kotlinUntranslatable(statement, source: syntaxTree.source)
            let rawStatement: RawStatement
            if let syntax = statement.syntax {
                rawStatement = RawStatement(syntax: syntax, message: message, extras: statement.extras, in: syntaxTree)
            } else {
                rawStatement = RawStatement(sourceCode: "?", message: message, range: statement.sourceRange, extras: statement.extras, in: syntaxTree)
            }
            return [KotlinRawStatement(statement: rawStatement)]
        }
    }

    func translateExpression(_ expression: Expression) -> KotlinExpression {
        do {
            switch expression.type {
            case .arrayLiteral:
                return KotlinArrayLiteral.translate(expression: expression as! ArrayLiteral, translator: self)
            case .available:
                return KotlinBooleanLiteral(literal: true, sourceFile: expression.sourceFile, sourceRange: expression.sourceRange)
            case .await:
                return KotlinAwait.translate(expression: expression as! Await, translator: self)
            case .binaryOperator:
                return KotlinBinaryOperator.translate(expression: expression as! BinaryOperator, translator: self)
            case .binding:
                break
            case .booleanLiteral:
                return KotlinBooleanLiteral(expression: expression as! BooleanLiteral)
            case .casePattern:
                break // Should be translated directly by parent expressions
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
            case .keyPathLiteral:
                return KotlinKeyPathLiteral.translate(expression: expression as! KeyPathLiteral, translator: self)
            case .macroExpansion:
                // This should never happen, as we never make the MacroExpansionExpr expression part of the syntax tree
                break
            case .matchingCase:
                break // Should be translated directly by parent expressions
            case .memberAccess:
                return KotlinMemberAccess.translate(expression: expression as! MemberAccess, translator: self)
            case .nilLiteral:
                return KotlinNullLiteral(expression: expression as! NilLiteral)
            case .numericLiteral:
                return KotlinNumericLiteral(expression: expression as! NumericLiteral)
            case .optionalBinding:
                break // Should be translated directly by parent expressions
            case .parenthesized:
                return KotlinParenthesized.translate(expression: expression as! Parenthesized, translator: self)
            case .postfixIfDefined:
                // This should never happen, as we never make the PostfixIfDefined expression part of the syntax tree
                break
            case .prefixOperator:
                return KotlinPrefixOperator.translate(expression: expression as! PrefixOperator, translator: self)
            case .postfixOperator:
                return KotlinPostfixOperator.translate(expression: expression as! PostfixOperator, translator: self)
            case .stringLiteral:
                return KotlinStringLiteral.translate(expression: expression as! StringLiteral, translator: self)
            case .subscript:
                return KotlinSubscript.translate(expression: expression as! Subscript, translator: self)
            case .switch:
                return KotlinWhen.translate(expression: expression as! Switch, translator: self)
            case .switchCase:
                break // Should be translated directly by parent expression
            case .ternaryOperator:
                return KotlinTernaryOperator.translate(expression: expression as! TernaryOperator, translator: self)
            case .try:
                return KotlinTry.translate(expression: expression as! Try, translator: self)
            case .tupleLiteral:
                return try KotlinTupleLiteral.translate(expression: expression as! TupleLiteral, translator: self)
            case .typeLiteral:
                return KotlinTypeLiteral.translate(expression: expression as! TypeLiteral, translator: self)
            case .raw:
                return KotlinRawExpression(expression: expression as! RawExpression)
            }
            throw Message.kotlinUntranslatable(expression, source: syntaxTree.source)
        } catch {
            let message = error as? Message ?? Message.kotlinUntranslatable(expression, source: syntaxTree.source)
            let rawExpression: RawExpression
            if let syntax = expression.syntax {
                rawExpression = RawExpression(syntax: syntax, message: message, in: syntaxTree)
            } else {
                rawExpression = RawExpression(sourceCode: "?", message: message, range: expression.sourceRange, in: syntaxTree)
            }
            return KotlinRawExpression(expression: rawExpression)
        }
    }

    private func transpilations(for kotlinSyntaxTree: KotlinSyntaxTree?, codebaseInfo: CodebaseInfo, transformers: [KotlinTransformer], input: Source, outputs: [KotlinTransformerOutput], startTime: TimeInterval) -> [Transpilation] {
        var transpilations: [Transpilation] = []
        var startTime = startTime
        if let kotlinSyntaxTree {
            let messages = kotlinSyntaxTree.messages + codebaseInfo.messages(for: syntaxTree.source.file) + transformers.flatMap { $0.messages(for: syntaxTree.source.file) }
            let outputFile = syntaxTree.source.file.outputFile(withExtension: "kt")
            let outputGenerator = OutputGenerator(root: kotlinSyntaxTree.root)
            let (output, outputMap) = outputGenerator.generateOutput(file: outputFile)
            let endTime = Date().timeIntervalSinceReferenceDate // track the duration for logging
            let transpilation = Transpilation(input: input, output: output, outputType: .default, outputMap: outputMap, messages: messages, duration: endTime - startTime)
            transpilations.append(transpilation)
            startTime = endTime
        }
        for transformerOutput in outputs {
            let outputGenerator = OutputGenerator(root: transformerOutput.node)
            let (output, outputMap) = outputGenerator.generateOutput(file: transformerOutput.file)
            let transpilation = Transpilation(input: input, output: output, outputType: transformerOutput.type, outputMap: outputMap, messages: [], duration: Date().timeIntervalSinceReferenceDate - startTime)
            transpilations.append(transpilation)
        }
        return transpilations
    }

    private func moveImportsToTop(statements: [KotlinStatement]) -> [KotlinStatement] {
        var importIndexes: IndexSet = []
        var contentStartIndex: Int? = nil
        for i in 0..<statements.count {
            switch statements[i].type {
            case .empty:
                // Keep empty statements used for comments, etc in place
                break
            case .importDeclaration:
                importIndexes.insert(i)
            default:
                if contentStartIndex == nil {
                    contentStartIndex = i
                }
            }
        }
        guard let contentStartIndex, let lastImportIndex = importIndexes.last, lastImportIndex > contentStartIndex else {
            return statements
        }

        var sortedStatements = statements
        var insertionIndex = contentStartIndex
        for importIndex in importIndexes {
            if importIndex > contentStartIndex {
                let importStatement = sortedStatements.remove(at: importIndex)
                sortedStatements.insert(importStatement, at: insertionIndex)
                insertionIndex += 1
            }
        }
        return sortedStatements
    }

    private func gatherDependencies(from translatedStatements: [KotlinStatement]) -> KotlinDependencies {
        var dependencies = KotlinDependencies()
        translatedStatements.forEach {
            $0.visit {
                $0.insertDependencies(into: &dependencies)
                return .recurse(nil)
            }
        }
        return dependencies
    }

    private func addPackageAndRequiredImportStatements(to kotlinSyntaxTree: KotlinSyntaxTree) {
        let packageStatements = packageStatements()
        let requiredImportStatements = requiredImportStatements(syntaxTree: kotlinSyntaxTree)
        
        var header: [String]? = nil
        if let firstStatement = kotlinSyntaxTree.root.statements.first {
            header = firstStatement.extras?.extractHeader(isImportStatement: firstStatement.type == .importDeclaration)
        }
        kotlinSyntaxTree.root.insert(statements: packageStatements + requiredImportStatements, after: nil)
        if let header, !header.isEmpty {
            kotlinSyntaxTree.root.insert(statements: [KotlinRawStatement(sourceCode: header.joined())], after: nil)
        }
    }

    private func packageStatements() -> [KotlinStatement] {
        guard let packageName else {
            return []
        }
        return [KotlinRawStatement(sourceCode: "package \(packageName)"), KotlinRawStatement(sourceCode: "")]
    }

    private func requiredImportStatements(syntaxTree: KotlinSyntaxTree) -> [KotlinStatement] {
        var modulePathStrings = syntaxTree.dependencies.imports
        // Manual whitelist of the packages above skip.lib
        if let packageName = packageName, ![
            "skip.unit",
            "skip.lib",
        ].contains(packageName) {
            modulePathStrings.insert("skip.lib.*")
        }
        
        // De-dupe with user imports
        syntaxTree.root.statements.forEach {
            if let importDeclaration = $0 as? KotlinImportDeclaration {
                modulePathStrings.remove(importDeclaration.modulePathString)
                importDeclaration.additionalImports.forEach { modulePathStrings.remove($0) }
            }
        }

        guard !modulePathStrings.isEmpty else {
            return []
        }
        var statements = modulePathStrings.sorted().map { KotlinRawStatement(sourceCode: "import " + $0) }
        statements.append(KotlinRawStatement(sourceCode: "")) // Spacer
        return statements
    }

    private static func bridgeSupportImports(for statements: [ImportDeclaration]) -> String {
        let imports = Set(statements.map { $0.modulePath.joined(separator: ".") }).sorted()
        return imports.map { "import " + $0 }.joined(separator: "\n")
    }
}
