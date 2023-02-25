/// Update variables declared for optional bindings in `if` and `guard` statements to prevent shadowing locals and each other.
///
/// Because Kotlin does not allow introducing a new variable within the conditional clause of an `if`, we have to declare the variable in the parent code block.
/// This may shadow an existing variable for the remainder of the block (in fact it certainly will when we use the same name as the optional identifier), when the
/// new variable should only apply to its owning if body. Additionally, multiple `if` or `else if` blocks may declare the same optional binding, which causes
/// us to create multiple var declarations with the same identifier.
class KotlinOptionalBindingsPlugin: KotlinPlugin {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        let visitor = Visitor()
        syntaxTree.root.visit(perform: visitor.visit)
    }
}

private class Visitor {
    var bindingCount = 0
    var remappedIdentifierStack: [[String: String]] = []

    func visit(_ node: KotlinSyntaxNode) -> VisitResult<KotlinSyntaxNode> {
        if node is KotlinCodeBlock {
            // When entering a code block we create a remapping context. If we encounter optional bindings,
            // we can apply them to the current context. When we leave, we pop the context
            remappedIdentifierStack.append([:])
            return .recurse({ _ in self.remappedIdentifierStack.removeLast() })
        } else if let identifier = node as? KotlinIdentifier {
            if let binding = binding(for: identifier.name) {
                identifier.name = binding
            }
            return .skip
        } else if let kif = node as? KotlinIf, !kif.optionalBindingVariables.isEmpty {
            var remappedIdentifiers: [String: String] = [:]
            kif.optionalBindingVariables = kif.optionalBindingVariables.map { optionalBindingVariable in
                // As we evaluate each binding we must allow it to access previous bindings in the conditions list
                remappedIdentifierStack.append(remappedIdentifiers)
                optionalBindingVariable.value.visit(perform: self.visit)
                remappedIdentifierStack.removeLast()

                let binding = newBinding(for: optionalBindingVariable.name)
                remappedIdentifiers[optionalBindingVariable.name] = binding
                return KotlinIf.OptionalBindingVariable(name: binding, value: optionalBindingVariable.value, isLet: optionalBindingVariable.isLet)
            }
            if kif.isGuard {
                // For guards, recurse on the body without the new bindings, then apply the bindings to the conditions and current code block
                kif.body.visit(perform: self.visit)
                if !remappedIdentifierStack.isEmpty {
                    remappedIdentifierStack[remappedIdentifierStack.count - 1].merge(remappedIdentifiers, uniquingKeysWith: { s, _ in s })
                }
                kif.conditions.forEach { $0.visit(perform: self.visit) }
            } else {
                // For ifs, recurse on the else without the new bindings, then apply the bindings to conditions and the if body
                if let elseBody = kif.elseBody {
                    elseBody.visit(perform: self.visit)
                }
                remappedIdentifierStack.append(remappedIdentifiers)
                kif.conditions.forEach { $0.visit(perform: self.visit) }
                kif.body.visit(perform: self.visit)
                remappedIdentifierStack.removeLast()
            }
            return .skip
        } else {
            return .recurse(nil)
        }
    }

    private func newBinding(for name: String) -> String {
        let binding = "\(name)_\(bindingCount)"
        bindingCount += 1
        return binding
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
