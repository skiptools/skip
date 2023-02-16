extension Accessor where S: Statement {
    /// Translate to an equivalent Kotlin accessor.
    func translate(translator: KotlinTranslator, isReturnExpected: Bool) -> Accessor<KotlinStatement> {
        if let body {
            return Accessor<KotlinStatement>(parameterName: parameterName, body: body.translate(translator: translator, isReturnExpected: isReturnExpected))
        }
        return Accessor<KotlinStatement>(parameterName: parameterName)
    }
}

extension Array where Element: KotlinStatement {
    /// If this statement block is using an implicit return value, add an explicit return statement.
    ///
    /// Assumes that this block must return a value.
    func withReturn() -> [KotlinStatement] {
        guard count == 1, self[0].type == .expression, let expression = (self[0] as! KotlinExpressionStatement).expression else {
            return self
        }
        return [KotlinReturn(expression: expression)]
    }

    /// Update all return statements in this code block.
    ///
    /// - Parameters:
    ///   - Parameter label: Label all return statements: `return@label ...`.
    ///   - Parameter onValueReferenceUpdate: Modify all `valref` returns to perform the given update when the value is modified.
    /// - Returns: Whether any return statements were found.
    @discardableResult func updateReturns(label: String? = nil, onValueReferenceUpdate: String? = nil) -> Bool {
        var didFindReturn = false
        forEach {
            $0.visitStatements {
                if let returnStatement = $0 as? KotlinReturn {
                    didFindReturn = true
                    if let label {
                        returnStatement.label = label
                    }
                    if let onValueReferenceUpdate, let valueReference = returnStatement.expression as? KotlinValueReference {
                        valueReference.onUpdate = onValueReferenceUpdate
                    }
                    return false
                }
                return true
            }
        }
        return didFindReturn
    }
}

extension CodeBlock where S: Statement {
    /// Translate to an equivalent Kotlin code block.
    func translate(translator: KotlinTranslator, isReturnExpected: Bool) -> CodeBlock<KotlinStatement> {
        var kstatements = statements.flatMap { translator.translateStatement($0) }
        if isReturnExpected {
            kstatements = kstatements.withReturn()
        }
        return CodeBlock<KotlinStatement>(statements: kstatements)
    }
}

extension Modifiers {
    /// Kotlin modifier string for a member.
    func kotlinMemberString(isOpen: Bool) -> String {
        let string: String
        switch visibility {
        case .default:
            fallthrough
        case .internal:
            string = "internal"
        case .open:
            string = "public"
        case .public:
            string = "public"
        case .private:
            string = "private"
        }
        if isOverride {
            return "\(string) override"
        }
        if isOpen {
            return "\(string) open"
        }
        return string
    }
}

extension Parameter where E: Expression {
    /// Translate to an equivalent Kotlin parameter.
    func translate(translator: KotlinTranslator) -> Parameter<KotlinExpression> {
        var kdefaultValue: KotlinExpression? = nil
        if let defaultValue {
            kdefaultValue = translator.translateExpression(defaultValue)
        }
        return Parameter<KotlinExpression>(externalName: externalName, internalName: internalName, declaredType: declaredType, isVariadic: isVariadic, defaultValue: kdefaultValue)
    }
}
