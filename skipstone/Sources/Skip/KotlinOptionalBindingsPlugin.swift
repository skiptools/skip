/// Update variables declared for optional bindings in `if` and `guard` statements to prevent shadowing locals and each other.
///
/// Because Kotlin does not allow introducing a new variable within the conditional clause of an `if`, we have to declare the variable in the parent code block.
/// This may shadow an existing variable for the remainder of the block (in fact it certainly will when we use the same name as the optional identifier), when the
/// new variable should only apply to its owning if body. Additionally, multiple `if` or `else if` blocks may declare the same optional binding, which causes
/// us to create multiple var declarations with the same identifier.
class KotlinOptionalBindingsPlugin: KotlinTranslatorPlugin {
    var bindingCount = 0
    var remappedIdentifierStack: [[String: String]] = []

    init() {
    }

    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        bindingCount = 0
        remappedIdentifierStack = [[:]]
        syntaxTree.root.visit(perform: { visit($0) })
    }

    private func visit(_ node: KotlinSyntaxNode) -> VisitResult<KotlinSyntaxNode> {
//        if let statement = node as? KotlinStatement {
//            switch statement.type {
//            case .if:
//                let ifstatement = statement as! KotlinIf
//                break
//            case .functionDeclaration:
//                break
//            case .variableDeclaration:
//                let variableDeclaration = statement as! KotlinVariableDeclaration
//                if variableDeclaration.isProperty || variableDeclaration.isGlobal {
//                    visitCodeBlock(variableDeclaration.getter?.body)
//                    visitCodeBlock(variableDeclaration.setter?.body)
//                    visitCodeBlock(variableDeclaration.willSet?.body)
//                    visitCodeBlock(variableDeclaration.didSet?.body)
//                    if let value = variableDeclaration.value {
//                        let _ = visit(value)
//                    }
//                    return .skip
//                }
//            default:
//                break
//            }
//        } else if let expression = node as? KotlinExpression {
//            switch expression.type {
//            case .closure:
//                let closure = expression as! KotlinClosure
//                visitCodeBlock(closure.body)
//                return .skip
//            case .identifier:
//                let identifier = expression as! KotlinIdentifier
//                if let binding = binding(for: identifier.name) {
//                    identifier.name = binding
//                }
//            default:
//                break
//            }
//        }
        return .recurse(nil)
    }

    private func binding(for identifier: String) -> String? {
        for remappedIdentifiers in remappedIdentifierStack.reversed() {
            if let binding = remappedIdentifiers[identifier] {
                return binding
            }
        }
        return nil
    }
}
