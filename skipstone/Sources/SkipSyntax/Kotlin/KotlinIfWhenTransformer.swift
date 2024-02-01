/// Update variables declared in `if`, `guard`, and `when` statements to prevent shadowing locals and each other.
///
/// - Seealso: ``KotlinIf``, ``KotlinWhen``
final class KotlinIfWhenTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        let expressionVisitor = ValueExpressionVisitor()
        syntaxTree.root.visit(perform: expressionVisitor.visit)
        let identifiersVisitor = IdentifiersVisitor()
        syntaxTree.root.visit(perform: identifiersVisitor.visit)
    }
}

/// Detect usages as value expressions rather than as statements.
private final class ValueExpressionVisitor {
    func visit(_ node: KotlinSyntaxNode) -> VisitResult<KotlinSyntaxNode> {
        // When used as value expressions, any 'if' or 'when' that we've turned into multiple statements because it requires an if check
        // or case target variable declaration needs to be nested in its own immediately-executed closure, and its implicit return values
        // need to be made into explicit return statements
        if let kif = node as? KotlinIf {
            let type = valueExpressionType(for: kif)
            if type == .expression {
                kif.nestingClosureFunction = "linvoke"
            }
            if type != .none {
                // Make return values explicit unless we're just nesting another if/when, in which case we'll end up making its return
                // values explicit already
                if !kif.body.isSingleIfWhenExpression {
                    if kif.body.updateWithExpectedReturn(.yes) {
                        kif.body.updateWithExpectedReturn(.labelIfPresent(KotlinClosure.returnLabel))
                    }
                }
                if let elseBody = kif.elseBody, !elseBody.isSingleIfWhenExpression {
                    if elseBody.updateWithExpectedReturn(.yes) {
                        elseBody.updateWithExpectedReturn(.labelIfPresent(KotlinClosure.returnLabel))
                    }
                }
            }
        } else if let kwhen = node as? KotlinWhen {
            let type = valueExpressionType(for: kwhen)
            if type == .expression {
                kwhen.nestingClosureFunction = "linvoke"
            }
            if type != .none {
                for kcase in kwhen.cases {
                    if !kcase.body.isSingleIfWhenExpression {
                        if kcase.body.updateWithExpectedReturn(.yes) {
                            kcase.body.updateWithExpectedReturn(.labelIfPresent(KotlinClosure.returnLabel))
                        }
                    }
                }
            }
        }
        return .recurse(nil)
    }

    private func valueExpressionType(for node: KotlinSyntaxNode?) -> ValueExpressionType {
        if !(node is KotlinIf) && !(node is KotlinWhen) {
            return .none
        }
        guard let parent = node?.parent else {
            return .none
        }
        if !(parent is KotlinExpressionStatement) || parent is KotlinReturn {
            return valueExpressionType(forUsedAsExpression: node)
        }
        // Traverse through KotlinExpressionStatement parent to code block
        if let codeBlock = parent.parent as? KotlinCodeBlock, codeBlock.isSingleIfWhenExpression {
            if let kclosure = codeBlock.parent as? KotlinClosure {
                // If the closure has a return type but no return statements, we must be a value expression. We don't need
                // to do this for functions because we always make their return statements explicit
                if !kclosure.isAnonymousFunction && !kclosure.hasReturnLabel && ((kclosure.returnType != .none && kclosure.returnType != .void) || (kclosure.inferredReturnType != .none && kclosure.inferredReturnType != .void)) {
                    return valueExpressionType(forUsedAsExpression: node)
                }
            } else {
                // Handle nested if/switch expressions
                switch valueExpressionType(for: codeBlock.parent) {
                case .none:
                    return .none
                case .expression, .nestedExpression:
                    return .nestedExpression
                }
            }
        }
        return .none
    }

    private func valueExpressionType(forUsedAsExpression node: KotlinSyntaxNode?) -> ValueExpressionType {
        return (node as? KotlinIf)?.conditionSets.first?.targetVariable != nil || (node as? KotlinWhen)?.caseTargetVariable != nil ? .expression : .none
    }
}

private enum ValueExpressionType {
    case none
    case expression
    case nestedExpression
}

/// Uniquify identifiers we've added for if statements.
private final class IdentifiersVisitor {
    private var renamedIdentifiersStack: [[String: String]] = []

    func visit(_ node: KotlinSyntaxNode) -> VisitResult<KotlinSyntaxNode> {
        if node is KotlinCodeBlock || node is KotlinWhileLoop || node is KotlinForLoop {
            // When entering a code block we create a renaming context. If we encounter optional bindings,
            // we can apply them to the current context. When we leave, we pop the context.
            //
            // We also do this around loops because while they only use their bindings within the transpiled
            // loop body, the bindings themselves are not children of the CodeBlock and so would pollute the
            // parent stack otherwise
            renamedIdentifiersStack.append([:])
            return .recurse({ _ in self.renamedIdentifiersStack.removeLast() })
        } else if let identifier = node as? KotlinIdentifier {
            if let bindingVariableName = bindingVariableName(for: identifier.name) {
                identifier.name = bindingVariableName
            }
            return .skip
        } else if let kif = node as? KotlinIf {
            for conditionSet in kif.conditionSets {
                if let caseTargetVariable = conditionSet.caseTargetVariable {
                    caseTargetVariable.identifier.name = newTargetVariableName()
                }
                if let targetVariable = conditionSet.targetVariable {
                    targetVariable.identifier.name = newTargetVariableName()
                }
            }
            if kif.isGuard {
                // Visit the guard body without the new bindings
                kif.body.visit(perform: self.visit)
                // Visit conditions and gather bindings. Reference conditionSets[i].xxx to mutate structs without manually resetting them
                var renamedIdentifiers: [String: String] = [:]
                for i in 0..<kif.conditionSets.count {
                    // As we evaluate each condition set we must allow it to access previous condition set bindings
                    if kif.conditionSets[i].optionalBindingVariable != nil || !kif.conditionSets[i].caseBindingVariables.isEmpty {
                        renamedIdentifiersStack.append(renamedIdentifiers)
                        kif.conditionSets[i].optionalBindingVariable?.value.visit(perform: self.visit)
                        kif.conditionSets[i].caseBindingVariables.forEach { $0.value.visit(perform: self.visit) }
                        renamedIdentifiersStack.removeLast()

                        if let optionalBindingVariable = kif.conditionSets[i].optionalBindingVariable {
                            let names = optionalBindingVariable.names.map { newBindingVariableName(name: $0) }
                            kif.conditionSets[i].optionalBindingVariable?.names = names
                            renamedIdentifiers.merge(zip(optionalBindingVariable.names.compactMap { $0 }, names.compactMap { $0 })) { _, new in new }
                        }
                        for j in 0..<kif.conditionSets[i].caseBindingVariables.count {
                            let caseBindingVariable = kif.conditionSets[i].caseBindingVariables[j]
                            let names = caseBindingVariable.names.map { newBindingVariableName(name: $0) }
                            kif.conditionSets[i].caseBindingVariables[j].names = names
                            renamedIdentifiers.merge(zip(caseBindingVariable.names.compactMap { $0 }, names.compactMap { $0 })) { _, new in new }
                        }
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
        } else if let kwhen = node as? KotlinWhen {
            if let caseTargetVariable = kwhen.caseTargetVariable {
                caseTargetVariable.identifier.name = newTargetVariableName()
            }
            return .recurse(nil)
        } else {
            return .recurse(nil)
        }
    }

    private var ifCheckCount = 0
    private var caseTargetCount = 0
    private var bindingCounts: [String: Int] = [:]

    private func newIfCheckVariableName() -> String {
        let name = "letexec_\(ifCheckCount)"
        ifCheckCount += 1
        return name
    }

    private func newTargetVariableName() -> String {
        let name = "matchtarget_\(caseTargetCount)"
        caseTargetCount += 1
        return name
    }

    private func newBindingVariableName(name: String?) -> String? {
        guard let name else {
            return nil
        }
        if var count = bindingCounts[name] {
            count += 1
            bindingCounts[name] = count
            return "\(name)_\(count)"
        } else {
            bindingCounts[name] = 0
            return "\(name)_0"
        }
    }

    private func bindingVariableName(for identifier: String) -> String? {
        for renamedIdentifiers in renamedIdentifiersStack.reversed() {
            if let name = renamedIdentifiers[identifier] {
                return name
            }
        }
        return nil
    }
}

extension KotlinCodeBlock {
    fileprivate var isSingleIfWhenExpression: Bool {
        guard statements.count == 1, let expressionStatement = statements[0] as? KotlinExpressionStatement else {
            return false
        }
        return expressionStatement.expression is KotlinIf || expressionStatement.expression is KotlinWhen
    }
}
