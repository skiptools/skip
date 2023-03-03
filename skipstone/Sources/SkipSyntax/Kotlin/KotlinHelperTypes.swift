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

extension Accessor where B: CodeBlock {
    /// Translate to an equivalent Kotlin accessor.
    func translate(translator: KotlinTranslator, expectedReturn: ExpectedReturn) -> Accessor<KotlinCodeBlock> {
        if let body {
            let kbody = KotlinCodeBlock.translate(statement: body, translator: translator)
            kbody.updateWithExpectedReturn(expectedReturn)
            return Accessor<KotlinCodeBlock>(parameterName: parameterName, body: kbody)
        }
        return Accessor<KotlinCodeBlock>(parameterName: parameterName)
    }
}

extension Operator {
    /// Kotlin version of this operator's symbol.
    var kotlinSymbol: String {
        switch symbol {
        case "??":
            return "?:"
        case "as!":
            return "as"
        case "..<":
            return "until"
        case "...":
            return ".."
        default:
            return symbol
        }
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
            string = ""
        case .public:
            string = ""
        case .private:
            string = "private"
        }
        if isOverride {
            return string.isEmpty ? "override" : "\(string) override"
        }
        if isOpen {
            return string.isEmpty ? "open" : "\(string) open"
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

extension Array where Element == KotlinExpression {
    /// Append this expression array as combined logical conditions, e.g. for an `if`.
    func appendAsLogicalConditions(to output: OutputGenerator, op: Operator = .with(symbol: "&&"), indentation: Indentation) {
        guard count > 1 else {
            if let condition = first {
                condition.append(to: output, indentation: indentation)
            }
            return
        }

        for (index, condition) in enumerated() {
            // Special case the common !x compound expression to avoid unnecessary parentheses
            let isCompound = condition.isCompoundExpression && !(condition is KotlinPrefixOperator && (condition as! KotlinPrefixOperator).operatorSymbol == "!")
            if isCompound {
                output.append("(")
            }
            output.append(condition, indentation: indentation)
            if isCompound {
                output.append(")")
            }
            if index < count - 1 {
                output.append(" ").append(op.symbol).append(" ")
            }
        }
    }

    /// Create a single logical expression out of these expressions.
    func asLogicalExpression() -> KotlinExpression {
        if isEmpty {
            return KotlinBooleanLiteral(literal: false)
        }
        if count == 1 {
            return self[0]
        }
        return KotlinBinaryOperator(op: .with(symbol: "&&"), lhs: Array(self[0..<(count - 1)]).asLogicalExpression(), rhs: self[count - 1])
    }
}
