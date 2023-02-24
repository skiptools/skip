/// Translate SwiftUI to syntactically correct Kotlin.
///
/// We rely on our Kotlin UI libraries to provide the implementation of the SwiftUI-like API that this translation will result in.
class KotlinSwiftUIPlugin: KotlinTranslatorPlugin {
    private let codebaseInfo: KotlinCodebaseInfo.Context

    init(codebaseInfo: KotlinCodebaseInfo.Context) {
        self.codebaseInfo = codebaseInfo
    }

    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        // Does this file need translation?
        var needsTranslation = false
        for importDeclaration in syntaxTree.root.statements.compactMap({ $0 as? KotlinImportDeclaration }) {
            // Update SwiftUI imports to SkipUI
            if importDeclaration.modulePath.first == "SwiftUI" {
                needsTranslation = true
                importDeclaration.modulePath[0] = "SkipUI"
            } else if importDeclaration.modulePath.first == "SkipUI" {
                needsTranslation = true
            }
        }
        if needsTranslation {
            syntaxTree.root.visit(perform: self.visit)
        }
    }

    private func visit(_ node: KotlinSyntaxNode) -> VisitResult<KotlinSyntaxNode> {
        if let variableDeclaration = node as? KotlinVariableDeclaration {
            translateVariableDeclaration(variableDeclaration)
        } else if let functionCall = node as? KotlinFunctionCall {
            translateFunctionCall(functionCall)
            return .skip
        }
        return .recurse(nil)
    }

    private func translateVariableDeclaration(_ statement: KotlinVariableDeclaration) {
        guard let view = viewForBody(statement), let memberIndex = view.members.firstIndex(where: { $0 === statement }) else {
            return
        }

        // Replace 'var body' with an override of our Kotlin SkipUI body function
        let bodyMethod = KotlinFunctionDeclaration(name: "body", sourceFile: statement.sourceFile, sourceRange: statement.sourceRange)
        bodyMethod.modifiers = statement.modifiers
        bodyMethod.modifiers.isOverride = true
        bodyMethod.returnType = statement.declaredType
        bodyMethod.body = statement.getter?.body
        view.members[memberIndex] = bodyMethod

        bodyMethod.parent = view
        bodyMethod.assignParentReferences()
    }

    private func translateFunctionCall(_ functionCall: KotlinFunctionCall) {
        for viewBuilder in viewBuilderParameters(in: functionCall) {
            translateViewBuilder(viewBuilder.body)
            viewBuilder.body.assignParentReferences()
        }
    }

    private func translateViewBuilder(_ codeBlock: KotlinCodeBlock) {
        codeBlock.statements = codeBlock.statements.map { translateViewBuilderStatement($0) }
        guard codeBlock.statements.count > 1, !hasExplicitReturn(codeBlock) else {
            return
        }
        // Wrap multi-statement view builders in an array
        var elements: [KotlinExpression] = []
        for statement in codeBlock.statements {
            if statement.type != .expression {
                // TODO: We should be appending the raw code here
                statement.messages.append(.kotlinViewBuilderUnsupportedStatement(statement))
            } else if let expression = (statement as! KotlinExpressionStatement).expression {
                elements.append(expression)
            }
        }
        let arrayLiteral = KotlinArrayLiteral()
        arrayLiteral.elements = elements
        arrayLiteral.useMultilineFormatting = true
        let arrayStatement = KotlinExpressionStatement()
        arrayStatement.expression = arrayLiteral
        codeBlock.statements = [arrayStatement]
    }

    private func translateViewBuilderStatement(_ statement: KotlinStatement) -> KotlinStatement {
        // TODO: Handle 'if', 'switch'
        return statement
    }

    private func isView(_ classDeclaration: KotlinClassDeclaration) -> Bool {
        // TODO: Ask symbols
        return classDeclaration.inherits.contains(.named("View", []))
    }

    private func viewForBody(_ variableDeclaration: KotlinVariableDeclaration) -> KotlinClassDeclaration? {
        guard variableDeclaration.name == "body" && !variableDeclaration.modifiers.isStatic && variableDeclaration.getter?.body != nil else {
            return nil
        }
        guard let owningClass = variableDeclaration.parent as? KotlinClassDeclaration, isView(owningClass) else {
            return nil
        }
        return owningClass
    }

    private func viewBuilderParameters(in functionCall: KotlinFunctionCall) -> [KotlinClosure] {
        // TODO: Match up this function call to available API calls and see which params are view builders
        return []//functionCall.arguments.compactMap { $0.value as? KotlinClosure }
    }

    private func hasExplicitReturn(_ codeBlock: KotlinCodeBlock) -> Bool {
        return codeBlock.updateWithExpectedReturn(.no)
    }
}
