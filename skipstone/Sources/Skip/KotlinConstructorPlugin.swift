/// Migrate SwiftUI constructors to Kotlin constructors.
class KotlinConstructorPlugin: KotlinTranslatorPlugin {
    private let codebaseInfo: KotlinCodebaseInfo.Context

    init(codebaseInfo: KotlinCodebaseInfo.Context) {
        self.codebaseInfo = codebaseInfo
    }

    func apply(to syntaxTree: KotlinSyntaxTree) -> KotlinSyntaxTree {
        syntaxTree.statements.forEach { $0.visitStatements(perform: self.visit) }
        return syntaxTree
    }

    private func visit(_ statement: KotlinStatement) -> KotlinVisitResult {
        switch statement.type {
        case .classDeclaration:
            addSuperclassConstructors(to: statement as! KotlinClassDeclaration)
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

    private func addSuperclassConstructors(to classDeclaration: KotlinClassDeclaration) {
        guard !classDeclaration.members.contains(where: { $0.type == .constructorDeclaration }) else {
            return
        }
        for superclassConstructor in superclassConstructors(of: classDeclaration.qualifiedName) {
            //~~~addSuperclassConstructor(parameters: superclassConstructor.functionSignature(symbols: codebaseInfo.symbols?.symbols).0, to: classDeclaration)
        }
    }

    private func addSuperclassConstructor(parameters: [KotlinCodebaseInfo.ConstructorParameter], to classDeclaration: KotlinClassDeclaration) {

    }

    private func fixupConstructor(_ constructor: KotlinFunctionDeclaration) {

    }

    private func superclassConstructors(of qualifiedName: String) -> [Symbol] {
        return []
    }
}
