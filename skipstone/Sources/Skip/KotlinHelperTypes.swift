/// The type of return statement expected from a code block.
enum ExpectedReturn {
    /// No return is expected.
    case no
    /// A return is required.
    case yes
    /// If any returns are present, given them the given label.
    case labelIfPresent(String)
    /// Call `valref` on returned values with the given `onUpdate` code.
    case valueReference(String?)
}

extension Accessor where S: Statement {
    /// Translate to an equivalent Kotlin accessor.
    func translate(translator: KotlinTranslator, expectedReturn: ExpectedReturn) -> Accessor<KotlinStatement> {
        if let body {
            return Accessor<KotlinStatement>(parameterName: parameterName, body: body.translate(translator: translator, expectedReturn: expectedReturn))
        }
        return Accessor<KotlinStatement>(parameterName: parameterName)
    }
}

extension Array where Element: KotlinStatement {
    /// Perform any necessary updates to the return statements in this block.
    ///
    /// - Returns: The updated statements and whether any return statements were found.
    func withExpectedReturn(_ expectedReturn: ExpectedReturn) -> ([KotlinStatement], Bool) {
        var label: String?
        var valref = false
        var returnRequired = false
        var onUpdate: String? = nil
        switch expectedReturn {
        case .no:
            // Don't shortcut and return here because we need to return whether any return statements were found
            break
        case .yes:
            returnRequired = true
        case .labelIfPresent(let l):
            label = l
        case .valueReference(let update):
            onUpdate = update
            valref = true
            returnRequired = true
        }

        var didFindReturn = false
        forEach {
            $0.visitStatements {
                if let returnStatement = $0 as? KotlinReturn {
                    didFindReturn = true
                    if let label {
                        returnStatement.label = label
                    }
                    if valref {
                        returnStatement.expression = returnStatement.expression?.valueReference(onUpdate: onUpdate)
                    }
                    return .skip
                }
                return .recurse(nil)
            }
        }
        if didFindReturn {
            return (self, true)
        }

        // If this was an implicit return, replace it with an explicit one if a return is required
        guard returnRequired, count == 1, self[0].type == .expression, var expression = (self[0] as! KotlinExpressionStatement).expression else {
            return (self, false)
        }
        if valref {
            expression = expression.valueReference(onUpdate: onUpdate)
        }
        return ([KotlinReturn(expression: expression)], true)
    }
}

extension CodeBlock where S: Statement {
    /// Translate to an equivalent Kotlin code block.
    func translate(translator: KotlinTranslator, expectedReturn: ExpectedReturn) -> CodeBlock<KotlinStatement> {
        var kstatements = statements.flatMap { translator.translateStatement($0) }
        switch expectedReturn {
        case .no:
            break
        default:
            let (statementsWithReturn, _) = kstatements.withExpectedReturn(expectedReturn)
            kstatements = statementsWithReturn
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
