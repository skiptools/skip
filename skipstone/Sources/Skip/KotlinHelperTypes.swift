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

extension Accessor where B: CodeBlockStatement {
    /// Translate to an equivalent Kotlin accessor.
    func translate(translator: KotlinTranslator, expectedReturn: ExpectedReturn) -> Accessor<KotlinCodeBlockStatement> {
        if let body {
            let kbody = KotlinCodeBlockStatement.translate(statement: body, translator: translator)
            kbody.updateWithExpectedReturn(expectedReturn)
            return Accessor<KotlinCodeBlockStatement>(parameterName: parameterName, body: kbody)
        }
        return Accessor<KotlinCodeBlockStatement>(parameterName: parameterName)
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

extension Parameter where V: Expression {
    /// Translate to an equivalent Kotlin parameter.
    func translate(translator: KotlinTranslator) -> Parameter<KotlinExpression> {
        var kdefaultValue: KotlinExpression? = nil
        if let defaultValue {
            kdefaultValue = translator.translateExpression(defaultValue)
        }
        return Parameter<KotlinExpression>(externalLabel: externalLabel, internalLabel: internalLabel, declaredType: declaredType, isVariadic: isVariadic, defaultValue: kdefaultValue)
    }
}
