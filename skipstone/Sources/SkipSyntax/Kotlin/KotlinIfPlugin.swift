/// Update variables declared in `if` and `guard` statements to prevent shadowing locals and each other.
///
/// - Seealso: ``KotlinIf``
class KotlinIfPlugin: KotlinPlugin {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        let identifiersVisitor = IdentifiersVisitor()
        syntaxTree.root.visit(perform: identifiersVisitor.visit)
        let unreachableVisitor = UnreachableVisitor()
        syntaxTree.root.visit(perform: unreachableVisitor.visit)
    }
}

/// Uniquify identifiers we've added for if statements.
private class IdentifiersVisitor {
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

                        let names = optionalBindingVariable.names.map { newOptionalBindingVariableName(name: $0) }
                        kif.conditionSets[i].optionalBindingVariable?.names = names
                        renamedIdentifiers.merge(zip(optionalBindingVariable.names, names)) { _, new in new }
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
        let name = "letexec_\(ifCheckCount)"
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

/// Add an unreachable error to functions and closures that the compiler may no longer be able to guarantee return a value
/// due to the complexity of some of our `if` translations.
private class UnreachableVisitor {
    func visit(_ node: KotlinSyntaxNode) -> VisitResult<KotlinSyntaxNode> {
        if let functionDeclaration = node as? KotlinFunctionDeclaration {
            // For functions a .none return type must be void, so skip it too
            if let body = functionDeclaration.body, functionDeclaration.returnType != .none && functionDeclaration.returnType != .void {
                addUnreachableErrorIfNeeded(to: body)
            }
        } else if let closure = node as? KotlinClosure {
            // For closures a .none return type is unknown, so only skip void
            if closure.returnType != .void {
                addUnreachableErrorIfNeeded(to: closure.body)
            }
        }
        return .recurse(nil)
    }

    private func addUnreachableErrorIfNeeded(to codeBlock: KotlinCodeBlock) {
        // We need to add an error if the block:
        // - Does not end with a return statement
        // - Contains an explicit return value
        // - Has an 'if' that we've restructured to use an if condition var, which may confuse the compiler
        guard !(codeBlock.statements.last is KotlinReturn) else {
            return
        }
        var hasReturnValue: Bool? = nil
        var hasIfCheckVariable = false
        codeBlock.visit { node in
            if hasReturnValue == false || (hasIfCheckVariable && hasReturnValue != nil) {
                // We can skip everything once we meet our conditions
                return .skip
            }
            if node is KotlinFunctionDeclaration {
                return .skip
            } else if node is KotlinClosure {
                return .skip
            } else if hasReturnValue == nil, let kret = node as? KotlinReturn {
                hasReturnValue = kret.expression != nil
                return .skip
            } else if !hasIfCheckVariable, let kif = node as? KotlinIf {
                hasIfCheckVariable = kif.ifCheckVariable != nil
                return .recurse(nil)
            } else {
                return .recurse(nil)
            }
        }
        guard hasReturnValue == true && hasIfCheckVariable else {
            return
        }
        let errorStatement = KotlinRawStatement(sourceCode: "error(\"Unreachable\")")
        errorStatement.parent = codeBlock
        codeBlock.statements.append(errorStatement)
    }
}
