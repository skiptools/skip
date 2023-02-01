extension Accessor where S: Statement {
    /// Translate to an equivalent Kotlin accessor.
    func translate(translator: KotlinTranslator) -> Accessor<KotlinStatement> {
        var kstatements: [KotlinStatement]? = nil
        if let statements {
            kstatements = statements.flatMap { translator.translateStatement($0) }
        }
        return Accessor<KotlinStatement>(parameterName: parameterName, statements: kstatements)
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

extension Parameter where S: Statement {
    /// Translate to an equivalent Kotlin parameter.
    func translate(translator: KotlinTranslator) -> Parameter<KotlinStatement> {
        var kdefaultValue: KotlinStatement? = nil
        if let defaultValue {
            kdefaultValue = translator.translateStatement(defaultValue).first
        }
        return Parameter<KotlinStatement>(externalName: externalName, internalName: internalName, type: type, isVariadic: isVariadic, defaultValue: kdefaultValue)
    }
}
