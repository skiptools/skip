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
    private var renamedIdentifiersStack: [[String: String]] = []

    func visit(_ node: KotlinSyntaxNode) -> VisitResult<KotlinSyntaxNode> {
        if node is KotlinCodeBlock {
            // When entering a code block we create a renaming context. If we encounter optional bindings,
            // we can apply them to the current context. When we leave, we pop the context
            renamedIdentifiersStack.append([:])
            return .recurse({ _ in self.renamedIdentifiersStack.removeLast() })
        } else if let identifier = node as? KotlinIdentifier {
            if let optionalBindingVariableName = optionalBindingVariableName(for: identifier.name) {
                identifier.name = optionalBindingVariableName
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
                var renamedIdentifiers: [String: String] = [:]
                for i in 0..<kif.conditionSets.count {
                    // As we evaluate each condition set we must allow it to access previous condition set bindings
                    if let optionalBindingVariable = kif.conditionSets[i].optionalBindingVariable {
                        renamedIdentifiersStack.append(renamedIdentifiers)
                        optionalBindingVariable.value.visit(perform: self.visit)
                        renamedIdentifiersStack.removeLast()

                        let name = newOptionalBindingVariableName(name: optionalBindingVariable.name)
                        kif.conditionSets[i].optionalBindingVariable?.name = name
                        renamedIdentifiers[optionalBindingVariable.name] = name
                    }
                    renamedIdentifiersStack.append(renamedIdentifiers)
                    kif.conditionSets[i].conditions.forEach { $0.visit(perform: self.visit) }
                    renamedIdentifiersStack.removeLast()
                }
                // Add bindings to current block
                if !renamedIdentifiersStack.isEmpty {
                    renamedIdentifiersStack[renamedIdentifiersStack.count - 1].merge(renamedIdentifiers) { _, new in new }
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
    private var optionalBindingCounts: [String: Int] = [:]

    private func newIfCheckVariableName() -> String {
        let name = "if_\(ifCheckCount)"
        ifCheckCount += 1
        return name
    }

    private func newOptionalBindingVariableName(name: String) -> String {
        if var count = optionalBindingCounts[name] {
            count += 1
            optionalBindingCounts[name] = count
            return "\(name)_\(count)"
        } else {
            optionalBindingCounts[name] = 0
            return "\(name)_0"
        }
    }

    private func optionalBindingVariableName(for identifier: String) -> String? {
        for renamedIdentifiers in renamedIdentifiersStack.reversed() {
            if let name = renamedIdentifiers[identifier] {
                return name
            }
        }
        return nil
    }
}
