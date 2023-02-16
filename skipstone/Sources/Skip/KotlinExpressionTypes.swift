/// Types of Kotlin expressions.
enum KotlinExpressionType {
    case arrayLiteral
    case binaryOperator
    case booleanLiteral
    case closure
    case nullLiteral
    case functionCall
    case identifier
    case memberAccess
    case numericLiteral
    case stringLiteral
    case `subscript`
    case `try`

    case raw
}

class KotlinArrayLiteral: KotlinExpression {
    var elements: [KotlinExpression] = []

    static func translate(expression: ArrayLiteral, translator: KotlinTranslator) -> KotlinArrayLiteral {
        let kexpression = KotlinArrayLiteral(expression: expression)
        kexpression.elements = expression.elements.map { translator.translateExpression($0) }
        return kexpression
    }

    private init(expression: ArrayLiteral) {
        super.init(type: .arrayLiteral, expression: expression)
    }

    override func mayBeSharedMutableValueExpression(orType: Bool) -> Bool {
        // Array literals are not shared, but if we're using this expression to determine the type, then it can be
        return orType
    }

    override var children: [KotlinSyntaxNode] {
        return elements
    }

    override func append(to output: OutputGenerator) {
        output.append("arrayOf(")
        for (index, element) in elements.enumerated() {
            output.append(element)
            if index != elements.count - 1 {
                output.append(", ")
            }
        }
        output.append(")")
    }
}

class KotlinBinaryOperator: KotlinExpression {
    var op: Operator
    var lhs: KotlinExpression
    var rhs: KotlinExpression
    var mayBeSharedMutableValue = false

    static func translate(expression: BinaryOperator, translator: KotlinTranslator) -> KotlinBinaryOperator {
        let klhs = translator.translateExpression(expression.lhs)
        var krhs = translator.translateExpression(expression.rhs)
        if expression.op.precedence == .assignment {
            krhs = krhs.valueReference
        }
        let kexpression = KotlinBinaryOperator(expression: expression, lhs: klhs, rhs: krhs)
        kexpression.mayBeSharedMutableValue = expression.inferredType.kotlinMayBeSharedMutableValue(codebaseInfo: translator.codebaseInfo)
        return kexpression
    }

    private init(expression: BinaryOperator, lhs: KotlinExpression, rhs: KotlinExpression) {
        self.op = expression.op
        self.lhs = lhs
        self.rhs = rhs
        super.init(type: .binaryOperator, expression: expression)
    }

    override func mayBeSharedMutableValueExpression(orType: Bool) -> Bool {
        return mayBeSharedMutableValue
    }

    override var isCompoundExpression: Bool {
        return true
    }

    override var children: [KotlinSyntaxNode] {
        return [lhs, rhs]
    }

    override func append(to output: OutputGenerator) {
        if lhs.isCompoundExpression {
            output.append("(").append(lhs).append(")")
        } else {
            output.append(lhs)
        }
        output.append(" \(op.symbol) ")
        if rhs.isCompoundExpression {
            output.append("(").append(rhs).append(")")
        } else {
            output.append(rhs)
        }
    }
}

class KotlinBooleanLiteral: KotlinExpression {
    var literal: Bool

    init(expression: BooleanLiteral) {
        self.literal = expression.literal
        super.init(type: .booleanLiteral, expression: expression)
    }

    override func append(to output: OutputGenerator) {
        output.append(String(describing: literal))
    }
}

class KotlinClosure: KotlinExpression {
    var returnType: TypeSignature = .none
    var parameters: [Parameter<Void>] = []
    var statements: [KotlinStatement] = []

    static func translate(expression: Closure, translator: KotlinTranslator) -> KotlinClosure {
        let kexpression = KotlinClosure(expression: expression)
        kexpression.returnType = expression.returnType
        kexpression.parameters = expression.parameters
        kexpression.statements = expression.statements.flatMap {
            return translator.translateStatement($0)
        }
        return kexpression
    }

    private init(expression: Closure) {
        super.init(type: .closure, expression: expression)
    }

    override var children: [KotlinSyntaxNode] {
        return statements
    }

    override func append(to output: OutputGenerator) {
        // TODO: Parameters, $0, $1 etc substitutions, return labels and return statements
        let indentation = output.indentationLevel
        output.append("{\n")
        output.append(statements, indentation: indentation.inc())
        output.append(indentation).append("}")
    }
}

class KotlinNullLiteral: KotlinExpression {
    init(expression: NilLiteral) {
        super.init(type: .nullLiteral, expression: expression)
    }

    override func append(to output: OutputGenerator) {
        output.append("null")
    }
}

class KotlinFunctionCall: KotlinExpression {
    var function: KotlinExpression
    var arguments: [LabeledValue<KotlinExpression>] = []
    var mayBeSharedMutableValue = false

    static func translate(expression: FunctionCall, translator: KotlinTranslator) -> KotlinFunctionCall {
        let kfunction = translator.translateExpression(expression.function)
        let kexpression = KotlinFunctionCall(expression: expression, function: kfunction)
        kexpression.arguments = expression.arguments.map {
            let kargumentExpression = translator.translateExpression($0.value).valueReference
            return LabeledValue(label: $0.label, value: kargumentExpression)
        }
        kexpression.mayBeSharedMutableValue = expression.inferredType.kotlinMayBeSharedMutableValue(codebaseInfo: translator.codebaseInfo)
        return kexpression
    }

    init(function: KotlinExpression, arguments: [LabeledValue<KotlinExpression>]) {
        self.function = function
        self.arguments = arguments
        super.init(type: .functionCall)
    }

    private init(expression: FunctionCall, function: KotlinExpression) {
        self.function = function
        super.init(type: .functionCall, expression: expression)
    }

    override func mayBeSharedMutableValueExpression(orType: Bool) -> Bool {
        return mayBeSharedMutableValue
    }

    override var children: [KotlinSyntaxNode] {
        return [function] + arguments.map { $0.value }
    }

    override func append(to output: OutputGenerator) {
        let hasTrailingClosure = arguments.last?.value.type == .closure
        let lastParenthesizedIndex = hasTrailingClosure ? arguments.count - 2 : arguments.count - 1
        output.append(function)
        if !hasTrailingClosure || arguments.count > 1 {
            output.append("(")
        }
        if lastParenthesizedIndex >= 0 {
            for (index, argument) in arguments[0...lastParenthesizedIndex].enumerated() {
                if let label = argument.label {
                    output.append(label).append(" = ")
                }
                output.append(argument.value)
                if index < lastParenthesizedIndex {
                    output.append(", ")
                }
            }
        }
        if !hasTrailingClosure || arguments.count > 1 {
            output.append(")")
        }
        if hasTrailingClosure {
            output.append(" ").append(arguments.last!.value)
        }
    }
}

class KotlinIdentifier: KotlinExpression {
    var name: String
    var mayBeSharedMutableValue = false

    static func translate(expression: Identifier, translator: KotlinTranslator) -> KotlinIdentifier {
        let kexpression = KotlinIdentifier(expression: expression)
        kexpression.mayBeSharedMutableValue = expression.inferredType.kotlinMayBeSharedMutableValue(codebaseInfo: translator.codebaseInfo)
        return kexpression
    }

    private init(expression: Identifier) {
        self.name = expression.name
        super.init(type: .identifier, expression: expression)
    }

    override func mayBeSharedMutableValueExpression(orType: Bool) -> Bool {
        return mayBeSharedMutableValue
    }

    override func append(to output: OutputGenerator) {
        if name == "self" {
            output.append("this")
        } else {
            output.append(name)
        }
    }
}

class KotlinMemberAccess: KotlinExpression {
    var base: KotlinExpression?
    var member: String
    var isMemberContinuedOnNextLine = false
    var inferredType: TypeSignature = .none
    var mayBeSharedMutableValue = false

    static func translate(expression: MemberAccess, translator: KotlinTranslator) -> KotlinMemberAccess {
        let kexpression = KotlinMemberAccess(expression: expression)
        if let base = expression.base {
            kexpression.base = translator.translateExpression(base)
            kexpression.isMemberContinuedOnNextLine = expression.isMemberContinuedOnNextLine
        }
        kexpression.inferredType = expression.inferredType
        kexpression.mayBeSharedMutableValue = expression.inferredType.kotlinMayBeSharedMutableValue(codebaseInfo: translator.codebaseInfo)
        return kexpression
    }

    init(base: KotlinExpression, member: String) {
        self.base = base
        self.member = member
        super.init(type: .memberAccess)
    }

    private init(expression: MemberAccess) {
        self.member = expression.member
        super.init(type: .memberAccess, expression: expression)
    }

    override func mayBeSharedMutableValueExpression(orType: Bool) -> Bool {
        return mayBeSharedMutableValue
    }

    override var children: [KotlinSyntaxNode] {
        return base == nil ? [] : [base!]
    }

    override func append(to output: OutputGenerator) {
        if let base {
            if base.isCompoundExpression {
                output.append("(").append(base).append(")")
            } else {
                output.append(base)
            }
            if isMemberContinuedOnNextLine {
                output.append("\n").append(output.indentationLevel.inc())
            }
            output.append(".")
        } else if inferredType != .none {
            output.append(inferredType).append(".")
        }
        output.append(member)
    }
}

class KotlinNumericLiteral: KotlinExpression {
    var literal: String
    var isFloatingPoint: Bool

    init(expression: NumericLiteral) {
        self.literal = expression.literal
        self.isFloatingPoint = expression.isFloatingPoint
        super.init(type: .numericLiteral, expression: expression)
    }

    override func append(to output: OutputGenerator) {
        output.append(literal.replacingOccurrences(of: "_", with: ""))
    }
}

class KotlinStringLiteral: KotlinExpression {
    var segments: [StringLiteralSegment<KotlinExpression>] = []
    var isMultiline = false

    static func translate(expression: StringLiteral, translator: KotlinTranslator) -> KotlinStringLiteral {
        let kexpression = KotlinStringLiteral(expression: expression)
        var segments: [StringLiteralSegment<KotlinExpression>] = []
        for segment in expression.segments {
            switch segment {
            case .string(let string):
                segments.append(.string(string))
            case .expression(let expression):
                let kexpression = translator.translateExpression(expression)
                segments.append(.expression(kexpression))
            }
        }
        kexpression.segments = segments
        kexpression.isMultiline = expression.isMultiline
        return kexpression
    }

    private init(expression: StringLiteral) {
        super.init(type: .stringLiteral, expression: expression)
    }

    override var children: [KotlinSyntaxNode] {
        return segments.compactMap {
            switch $0 {
            case .expression(let kexpression):
                return kexpression
            case .string:
                return nil
            }
        }
    }

    override func append(to output: OutputGenerator) {
        let delimiter = isMultiline ? "\"\"\"" : "\""
        output.append(delimiter)
        for segment in segments {
            switch segment {
            case .string(let string):
                output.append(string)
            case .expression(let expression):
                output.append("${").append(expression).append("}")
            }
        }
        output.append(delimiter)
    }
}

class KotlinSubscript: KotlinExpression {
    var base: KotlinExpression
    var arguments: [LabeledValue<KotlinExpression>] = []
    var mayBeSharedMutableValue = false

    static func translate(expression: Subscript, translator: KotlinTranslator) -> KotlinSubscript {
        let kbase = translator.translateExpression(expression.base)
        let kexpression = KotlinSubscript(expression: expression, base: kbase)
        kexpression.arguments = expression.arguments.map {
            let kargumentExpression = translator.translateExpression($0.value).valueReference
            return LabeledValue(label: $0.label, value: kargumentExpression)
        }
        kexpression.mayBeSharedMutableValue = expression.inferredType.kotlinMayBeSharedMutableValue(codebaseInfo: translator.codebaseInfo)
        return kexpression
    }

    private init(expression: Subscript, base: KotlinExpression) {
        self.base = base
        super.init(type: .subscript, expression: expression)
    }

    override func mayBeSharedMutableValueExpression(orType: Bool) -> Bool {
        return true
    }

    override var children: [KotlinSyntaxNode] {
        return [base] + arguments.map { $0.value }
    }

    override func append(to output: OutputGenerator) {
        if base.isCompoundExpression {
            output.append("(").append(base).append(")")
        } else {
            output.append(base)
        }
        output.append("[")
        for (index, argument) in arguments.enumerated() {
            if let label = argument.label {
                output.append(label).append(" = ")
            }
            output.append(argument.value)
            if index < arguments.count - 1 {
                output.append(", ")
            }
        }
        output.append("]")
    }
}

class KotlinTry: KotlinExpression {
    var trying: KotlinExpression
    var isOptional = false

    static func translate(expression: Try, translator: KotlinTranslator) -> KotlinTry {
        let ktrying = translator.translateExpression(expression.trying)
        let kexpression = KotlinTry(expression: expression, trying: ktrying)
        kexpression.isOptional = expression.isOptional
        return kexpression
    }

    private init(expression: Try, trying: KotlinExpression) {
        self.trying = trying
        super.init(type: .try, expression: expression)
    }

    override func mayBeSharedMutableValueExpression(orType: Bool) -> Bool {
        return trying.mayBeSharedMutableValueExpression(orType: orType)
    }

    override var isCompoundExpression: Bool {
        return isOptional || trying.isCompoundExpression
    }

    override var children: [KotlinSyntaxNode] {
        return [trying]
    }

    override func append(to output: OutputGenerator) {
        if isOptional {
            output.append("try { ").append(trying).append(" } catch (_e_: Exception) { null }")
        } else {
            output.append(trying)
        }
    }
}
