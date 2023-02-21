/// Migrate SwiftUI constructors to Kotlin constructors.
class KotlinConstructorPlugin: KotlinTranslatorPlugin {
    private let codebaseInfo: KotlinCodebaseInfo.Context

    init(codebaseInfo: KotlinCodebaseInfo.Context) {
        self.codebaseInfo = codebaseInfo
    }

    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> KotlinSyntaxTree {
        syntaxTree.statements.forEach { $0.visitStatements(perform: { visit($0, translator: translator) }) }
        return syntaxTree
    }

    private func visit(_ statement: KotlinStatement, translator: KotlinTranslator) -> KotlinVisitResult {
        switch statement.type {
        case .classDeclaration:
            addSuperclassConstructors(to: statement as! KotlinClassDeclaration, translator: translator)
        case .constructorDeclaration:
            fixupConstructor(statement as! KotlinFunctionDeclaration)
            return .skip
        case .variableDeclaration:
            return .skip
        case .functionDeclaration:
            return .skip
        default:
            break
        }
        return .recurse(nil)
    }

    private func addSuperclassConstructors(to classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) {
        guard !classDeclaration.members.contains(where: { $0.type == .constructorDeclaration }) else {
            return
        }
        for constructorParameters in codebaseInfo.constructorParameters(of: classDeclaration.qualifiedName) {
            addInheritedConstructor(parameters: constructorParameters, to: classDeclaration, translator: translator)
        }
    }

    private func addInheritedConstructor(parameters: [KotlinCodebaseInfo.ConstructorParameter], to classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) {
        let constructor = KotlinFunctionDeclaration(name: "constructor")
        var superCall = "super("
        constructor.parameters = parameters.enumerated().map { (index, parameter) in
            let label = parameter.label ?? "_p\(index)_"
            if index > 0 {
                superCall += ", "
            }
            superCall += label

            var kdefaultValue: KotlinExpression? = nil
            if let defaultValue = parameter.defaultValue {
                kdefaultValue = translator.translateExpression(defaultValue)
            }
            return Parameter(externalLabel: label, declaredType: parameter.type, isVariadic: parameter.isVariadic, defaultValue: kdefaultValue)
        }
        constructor.delegatingConstructorCall = KotlinRawExpression(sourceCode: superCall)

        constructor.modifiers = classDeclaration.modifiers
        constructor.body = CodeBlock<KotlinStatement>(statements: [])

        classDeclaration.members.append(constructor)
        constructor.parent = classDeclaration
        constructor.assignParentReferences()
    }

    private func fixupConstructor(_ constructor: KotlinFunctionDeclaration) {
        guard var body = constructor.body else {
            return
        }

        // Find any call to self or super init and move it to the Kotlin delegating constructor call
        for (index, statement) in body.statements.enumerated() {
            guard let delegatingCall = delegatingConstructorCall(for: statement) else {
                continue
            }
            if index == 0 {
                body.statements.removeFirst()
                constructor.body = body
                constructor.delegatingConstructorCall = delegatingCall
                break
            } else {
                statement.messages.append(.kotlinConstructorDelegateFirstStatement(statement))
                break
            }
        }
    }

    private func delegatingConstructorCall(for statement: KotlinStatement) -> KotlinExpression? {
        guard statement.type == .expression, let expressionStatement = statement as? KotlinExpressionStatement else {
            return nil
        }
        guard expressionStatement.expression?.type == .functionCall, let functionCall = expressionStatement.expression as? KotlinFunctionCall else {
            return nil
        }
        guard functionCall.function.type == .memberAccess, let memberAccess = functionCall.function as? KotlinMemberAccess else {
            return nil
        }
        guard memberAccess.member == "init" else {
            return nil
        }
        switch memberAccess.baseType {
        case .this:
            return memberAccess
        case .super:
            return memberAccess
        default:
            return nil
        }
    }
}
