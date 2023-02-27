/// Update variables declared in `if` and `guard` statements to prevent shadowing locals and each other.
///
/// - Seealso: ``KotlinIf``
class KotlinIfPlugin: KotlinPlugin {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        let visitor = Visitor()
        syntaxTree.root.visit(perform: visitor.visit)
    }
}

private class Visitor {
    private var remappedIdentifierStack: [[String: String]] = []

    func visit(_ node: KotlinSyntaxNode) -> VisitResult<KotlinSyntaxNode> {
        if node is KotlinCodeBlock {
            // When entering a code block we create a remapping context. If we encounter optional bindings,
            // we can apply them to the current context. When we leave, we pop the context
            remappedIdentifierStack.append([:])
            return .recurse({ _ in self.remappedIdentifierStack.removeLast() })
        } else if let identifier = node as? KotlinIdentifier {
            if let optionalBinding = optionalBindingVariableName(for: identifier.name) {
                identifier.name = optionalBinding
            }
            return .skip
        } else if let kif = node as? KotlinIf {
            if kif.ifCheckVariable != nil {
                kif.ifCheckVariable = newIfCheckVariableName()
                return .recurse(nil)
            } else if kif.isGuard {
                // Visit the guard body without the new bindings
                kif.body.visit(perform: self.visit)
                // Visit conditions and gather bindings.
                var remappedIdentifiers: [String: String] = [:]
                for i in 0..<kif.conditionSets.count {
                    // As we evaluate each condition set we must allow it to access previous condition set bindings
                    if let optionalBindingVariable = kif.conditionSets[i].optionalBindingVariable {
                        remappedIdentifierStack.append(remappedIdentifiers)
                        optionalBindingVariable.value.visit(perform: self.visit)
                        remappedIdentifierStack.removeLast()

                        let name = newOptionalBindingVariableName(name: optionalBindingVariable.name)
                        kif.conditionSets[i].optionalBindingVariable?.name = name
                        remappedIdentifiers[optionalBindingVariable.name] = name
                    }
                    remappedIdentifierStack.append(remappedIdentifiers)
                    kif.conditionSets[i].conditions.forEach { $0.visit(perform: self.visit) }
                    remappedIdentifierStack.removeLast()
                }
                // Add bindings to current block
                if !remappedIdentifierStack.isEmpty {
                    remappedIdentifierStack[remappedIdentifierStack.count - 1].merge(remappedIdentifiers) { _, new in new }
                }
                return .skip
            } else {
                return .recurse(nil)
            }
        } else {
            return .recurse(nil)
        }
    }

    private var ifCheckCount = 0
    private var optionalBindingCount = 0

    private func newIfCheckVariableName() -> String {
        let name = "if_\(ifCheckCount)"
        ifCheckCount += 1
        return name
    }

    private func newOptionalBindingVariableName(name: String) -> String {
        let name = "\(name)_\(optionalBindingCount)"
        optionalBindingCount += 1
        return name
    }

    private func optionalBindingVariableName(for identifier: String) -> String? {
        for remappedIdentifiers in remappedIdentifierStack.reversed() {
            if let binding = remappedIdentifiers[identifier] {
                return binding
            }
        }
        return nil
    }
}
