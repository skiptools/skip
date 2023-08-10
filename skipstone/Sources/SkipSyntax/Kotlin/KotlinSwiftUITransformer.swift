/// Translate SwiftUI to syntactically correct Kotlin.
///
/// We rely on our UI libraries to provide the implementation of the SwiftUI-like API that this translation will result in.
final class KotlinSwiftUITransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        // We need codebase info to issue any warnings, so no point in processing the code without it
        guard translator.codebaseInfo != nil else {
            return
        }

        // Does this file need translation?
        var needsTranslation = false
        if translator.packageName == "skip.ui" {
            // We need to be able to transpile the views within our own SkipUI package
            needsTranslation = true
        } else {
            for importDeclaration in syntaxTree.root.statements.compactMap({ $0 as? KotlinImportDeclaration }) {
                if importDeclaration.modulePath.first == "SwiftUI" || importDeclaration.modulePath.first == "SkipUI" {
                    needsTranslation = true
                    break
                }
            }
        }
        if needsTranslation {
            syntaxTree.root.visit { visit($0, translator: translator) }
        }
    }

    private func visit(_ node: KotlinSyntaxNode, translator: KotlinTranslator) -> VisitResult<KotlinSyntaxNode> {
        if let functionDeclaration = node as? KotlinFunctionDeclaration {
            translateFunctionDeclaration(functionDeclaration, translator: translator)
        } else if let variableDeclaration = node as? KotlinVariableDeclaration {
            translateVariableDeclaration(variableDeclaration, translator: translator)
        } else if let closure = node as? KotlinClosure {
            translateClosure(closure, translator: translator)
        } else if let functionCall = node as? KotlinFunctionCall {
            translateFunctionCallParameters(functionCall, translator: translator)
        }
        return .recurse(nil)
    }

    private func translateFunctionDeclaration(_ functionDeclaration: KotlinFunctionDeclaration, translator: KotlinTranslator) {
        guard functionDeclaration.apiFlags.contains(.viewBuilder) else {
            return
        }
        if let body = functionDeclaration.body {
            functionDeclaration.body = translateViewBuilder(codeBlock: body, translator: translator)
            functionDeclaration.body?.parent = functionDeclaration
        }
    }

    private func translateClosure(_ closure: KotlinClosure, translator: KotlinTranslator) {
        guard closure.apiFlags?.contains(.viewBuilder) == true else {
            return
        }
        closure.body = translateViewBuilder(codeBlock: closure.body, fromClosure: closure, translator: translator)
        closure.body.parent = closure
    }

    private func translateFunctionCallParameters(_ functionCall: KotlinFunctionCall, translator: KotlinTranslator) {
        // Look for closures passed as ViewBuilder arguments to function calls
        guard case .function(let parameterTypes, _, _) = functionCall.apiMatch?.signature, parameterTypes.count == functionCall.arguments.count else {
            return
        }
        for i in 0..<parameterTypes.count {
            guard case .function(_, _, let apiFlags) = parameterTypes[i].type, apiFlags.contains(.viewBuilder), let closure = functionCall.arguments[i].value as? KotlinClosure else {
                continue
            }
            // If the closure is marked as a ViewBuilder, we'll already process it
            guard closure.apiFlags?.contains(.viewBuilder) != true else {
                continue
            }
            closure.body = translateViewBuilder(codeBlock: closure.body, fromClosure: closure, translator: translator)
            closure.body.parent = closure
        }
    }

    private func translateVariableDeclaration(_ statement: KotlinVariableDeclaration, translator: KotlinTranslator) {
        var viewBuilder: KotlinCodeBlock? = nil
        if let viewDeclaration = viewForBody(statement, codebaseInfo: translator.codebaseInfo) {
            transform(view: viewDeclaration, body: statement, translator: translator)
            viewBuilder = statement.getter?.body
        } else if statement.apiFlags.contains(.viewBuilder) {
            viewBuilder = statement.getter?.body
        }
        if let viewBuilder {
            statement.getter?.body = translateViewBuilder(codeBlock: viewBuilder, translator: translator)
            statement.getter?.body?.parent = statement
        }
    }

    private func viewForBody(_ variableDeclaration: KotlinVariableDeclaration, codebaseInfo: CodebaseInfo.Context?) -> KotlinClassDeclaration? {
        guard variableDeclaration.role == .property, variableDeclaration.propertyName == "body", !variableDeclaration.isStatic, let classDeclaration = variableDeclaration.parent as? KotlinClassDeclaration else {
            return nil
        }
        guard classDeclaration.inherits.contains(where: { $0.isNamed("View", moduleName: "SwiftUI") }) || isView(type: classDeclaration.signature, codebaseInfo: codebaseInfo) else {
            return nil
        }
        return classDeclaration
    }

    private func transform(view: KotlinClassDeclaration, body: KotlinVariableDeclaration, translator: KotlinTranslator) {
        // TODO: Transformations for state handling, etc
        body.apiFlags.insert(.viewBuilder)
    }

    private func translateViewBuilder(codeBlock: KotlinCodeBlock, fromClosure closure: KotlinClosure? = nil, translator: KotlinTranslator) -> KotlinCodeBlock {
        // If the view builder returns a view explicitly, leave it as-is to support typed return values
        guard !codeBlock.updateWithExpectedReturn(.no) else {
            return codeBlock
        }

        // Add tail calls to compose the views that SwiftUI would build into a TupleView
        codeBlock.visit { node in
            if node is KotlinFunctionDeclaration || node is KotlinClosure {
                // These do not inherit our view builder context and will get processed by the top-level visitation code
                return .skip
            } else if let apiCall = node as? APICallExpression, let expressionStatement = node.parent as? KotlinExpressionStatement {
                // Add our compose tail call to expressions that evaluate to Views and are used as statements
                if let apiMatch = apiCall.apiMatch {
                    if isView(type: apiMatch.signature, codebaseInfo: translator.codebaseInfo) || isView(type: apiMatch.signature.returnType, codebaseInfo: translator.codebaseInfo) {
                        addComposeTailCall(to: node as! KotlinExpression, statement: expressionStatement)
                    }
                } else {
                    // TODO: Add warnings for unrecognized API use like for async
                }
                return .skip
            } else {
                return .recurse(nil)
            }
        }

        // Wrap the code block in 'return ComposingView { ... }' to return a single view that will compose
        // when the parent adds its tail call
        let composingClosure = KotlinClosure(body: codeBlock)
        let composingArgument = LabeledValue<KotlinExpression>(value: composingClosure)
        let composingFunction = KotlinIdentifier(name: "ComposingView")
        let composingFunctionCall = KotlinFunctionCall(function: composingFunction, arguments: [composingArgument])

        let returnStatement: KotlinStatement = closure == nil ? KotlinReturn(expression: composingFunctionCall) : KotlinExpressionStatement(expression: composingFunctionCall)
        let composingCodeBlock = KotlinCodeBlock(statements: [returnStatement])

        composingCodeBlock.assignParentReferences()
        return composingCodeBlock
    }

    private func addComposeTailCall(to expression: KotlinExpression, statement: KotlinExpressionStatement) {
        let composeMemberAccess = KotlinMemberAccess(base: expression, member: "Compose")
        let composeCall = KotlinFunctionCall(function: composeMemberAccess, arguments: [])
        statement.expression = composeCall

        composeCall.parent = statement
        composeCall.assignParentReferences()
    }

    private func isView(type: TypeSignature, codebaseInfo: CodebaseInfo.Context?) -> Bool {
        guard let codebaseInfo else {
            return false
        }
        guard case .named = type else {
            return false
        }
        return codebaseInfo.global.protocolSignatures(forNamed: type)
            .contains { $0.isNamed("View", moduleName: "SwiftUI") }
    }
}
