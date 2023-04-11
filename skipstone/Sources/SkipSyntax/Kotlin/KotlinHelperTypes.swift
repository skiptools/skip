/// The type of return statement expected from a code block.
enum KotlinExpectedReturn {
    /// No return is expected.
    case no
    /// A return is required.
    case yes
    /// If any returns are present, given them the given label.
    case labelIfPresent(String)
    /// Convert break statements to returns with the given label.
    case labelIfBreak(String)
    /// Call `sref` on returned values with the given `onUpdate` code.
    case sref(String?)
}

/// A variable we declare to mirror a Swift binding pattern.
struct KotlinBindingVariable {
    var names: [String?]
    var value: KotlinExpression
    var isLet: Bool

    /// - Note: Appends without leading indentation or trailing newline.
    func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(isLet ? "val " : "var ")
        if names.count > 1 {
            output.append("(")
        }
        output.append(names.map { $0 ?? "_" }.joined(separator: ", "))
        if names.count > 1 {
            output.append(")")
        }
        output.append(" = ").append(value, indentation: indentation)
    }
}

/// A variable we decoare to hold the expression we're matching on for repeated evaluation without side effects.
struct KotlinCaseTargetVariable {
    var identifier: KotlinIdentifier
    var value: KotlinExpression

    init(value: KotlinExpression) {
        self.identifier = KotlinIdentifier(name: "matchtarget")
        self.identifier.isLocalIdentifier = true
        self.value = value
    }

    func append(to output: OutputGenerator, indentation: Indentation) {
        output.append("val ").append(identifier, indentation: indentation)
        output.append(" = ").append(value, indentation: indentation)
    }
}

extension ExtensionDeclaration {
    /// Whether this extension's members can be moved into the extended type definition.
    var canMoveIntoExtendedType: Bool {
        return extends.generics.isEmpty && generics.isEmpty
    }
}

extension Accessor where B: CodeBlock {
    /// Translate to an equivalent Kotlin accessor.
    func translate(translator: KotlinTranslator, expectedReturn: KotlinExpectedReturn) -> Accessor<KotlinCodeBlock> {
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
            // Note that we construct operators with non-Swift symbols like 'in'
            return symbol
        }
    }
}

extension Modifiers {
    /// Kotlin modifier string for a member.
    func kotlinMemberString(isOpen: Bool, suffix: String) -> String {
        var string: String
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
            string = string.isEmpty ? "override" : "\(string) override"
        }
        if isOpen && !isStatic {
            string = string.isEmpty ? "open" : "\(string) open"
        }
        return string.isEmpty || suffix.isEmpty ? string : "\(string)\(suffix)"
    }
}

extension Parameter where V: Expression {
    /// Translate to an equivalent Kotlin parameter.
    func translate(translator: KotlinTranslator) -> Parameter<KotlinExpression> {
        var kdefaultValue: KotlinExpression? = nil
        if let defaultValue {
            kdefaultValue = translator.translateExpression(defaultValue)
        }
        return Parameter<KotlinExpression>(externalLabel: externalLabel, internalLabel: internalLabel, declaredType: declaredType, isVariadic: isVariadic, isInOut: isInOut, defaultValue: kdefaultValue)
    }
}

extension Generics {
    func filterWhereEqual() -> Generics {
        var generics = self
        generics.entries = generics.entries.filter { $0.whereEqual == nil }
        return generics
    }

    func append(to output: OutputGenerator, indentation: Indentation, outParameters: Bool = false) {
        if entries.isEmpty {
            return
        }
        output.append("<")
        output.append(entries.map { $0.whereEqual?.kotlin ?? (outParameters ? "out \($0.name)" : $0.name) }.joined(separator: ", "))
        output.append(">")
    }

    func appendWhere(to output: OutputGenerator, indentation: Indentation) {
        let constraints = entries.flatMap { entry in
            entry.inherits.map {
                (entry.name, $0)
            }
        }
        guard !constraints.isEmpty else {
            return
        }
        output.append(" where ")
        for (index, (name, type)) in constraints.enumerated() {
            output.append("\(name): \(type.kotlin)")
            if index != constraints.count - 1 {
                output.append(", ")
            }
        }
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
            return KotlinBooleanLiteral(literal: true)
        }
        if count == 1 {
            return self[0]
        }
        return KotlinBinaryOperator(op: .with(symbol: "&&"), lhs: Array(self[0..<(count - 1)]).asLogicalExpression(), rhs: self[count - 1])
    }
}
