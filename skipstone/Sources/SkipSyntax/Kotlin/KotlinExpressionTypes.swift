/// Types of Kotlin expressions.
enum KotlinExpressionType {
    case arrayLiteral
    case binaryOperator
    case booleanLiteral
    case closure
    case functionCall
    case identifier
    case `if`
    case memberAccess
    case nullLiteral
    case numericLiteral
    case parenthesized
    case prefixOperator
    case stringLiteral
    case `subscript`
    case `try`
    case valueReference

    case raw
}

class KotlinArrayLiteral: KotlinExpression {
    var elements: [KotlinExpression] = []
    var useMultilineFormatting = false

    static func translate(expression: ArrayLiteral, translator: KotlinTranslator) -> KotlinArrayLiteral {
        let kexpression = KotlinArrayLiteral(expression: expression)
        kexpression.elements = expression.elements.map { translator.translateExpression($0) }
        return kexpression
    }

    init(sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        super.init(type: .arrayLiteral, sourceFile: sourceFile, sourceRange: sourceRange)
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

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append("arrayOf(")
        let elementIndentation = useMultilineFormatting ? indentation.inc() : indentation
        for (index, element) in elements.enumerated() {
            if (useMultilineFormatting) {
                output.append("\n").append(elementIndentation)
            }
            output.append(element, indentation: elementIndentation)
            if index != elements.count - 1 {
                output.append(", ")
            }
        }
        if (useMultilineFormatting) {
            output.append("\n").append(indentation)
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
            krhs = krhs.valueReference()
        }
        let kexpression = KotlinBinaryOperator(expression: expression, lhs: klhs, rhs: krhs)
        kexpression.mayBeSharedMutableValue = expression.inferredType.kotlinMayBeSharedMutableValue(codebaseInfo: translator.codebaseInfo)
        return kexpression
    }

    init(op: Operator, lhs: KotlinExpression, rhs: KotlinExpression, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.op = op
        self.lhs = lhs
        self.rhs = rhs
        super.init(type: .binaryOperator, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(expression: BinaryOperator, lhs: KotlinExpression, rhs: KotlinExpression) {
        self.op = expression.op
        self.lhs = lhs
        self.rhs = rhs
        super.init(type: .binaryOperator, expression: expression)
    }

    override func logicalNegated() -> KotlinExpression {
        var negated: KotlinBinaryOperator
        switch op.symbol {
        case "&&":
            negated = KotlinBinaryOperator(op: Operator.with(symbol: "||"), lhs: lhs.logicalNegated(), rhs: rhs.logicalNegated(), sourceFile: sourceFile, sourceRange: sourceRange)
        case "||":
            negated =  KotlinBinaryOperator(op: Operator.with(symbol: "&&"), lhs: lhs.logicalNegated(), rhs: rhs.logicalNegated(), sourceFile: sourceFile, sourceRange: sourceRange)
        case "<":
            negated =  KotlinBinaryOperator(op: Operator.with(symbol: ">="), lhs: lhs, rhs: rhs, sourceFile: sourceFile, sourceRange: sourceRange)
        case "<=":
            negated =  KotlinBinaryOperator(op: Operator.with(symbol: ">"), lhs: lhs, rhs: rhs, sourceFile: sourceFile, sourceRange: sourceRange)
        case ">":
            negated =  KotlinBinaryOperator(op: Operator.with(symbol: "<="), lhs: lhs, rhs: rhs, sourceFile: sourceFile, sourceRange: sourceRange)
        case ">=":
            negated =  KotlinBinaryOperator(op: Operator.with(symbol: "<"), lhs: lhs, rhs: rhs, sourceFile: sourceFile, sourceRange: sourceRange)
        case "==":
            negated =  KotlinBinaryOperator(op: Operator.with(symbol: "!="), lhs: lhs, rhs: rhs, sourceFile: sourceFile, sourceRange: sourceRange)
        case "!=":
            negated =  KotlinBinaryOperator(op: Operator.with(symbol: "=="), lhs: lhs, rhs: rhs, sourceFile: sourceFile, sourceRange: sourceRange)
        case "===":
            negated =  KotlinBinaryOperator(op: Operator.with(symbol: "!=="), lhs: lhs, rhs: rhs, sourceFile: sourceFile, sourceRange: sourceRange)
        case "!==":
            negated =  KotlinBinaryOperator(op: Operator.with(symbol: "==="), lhs: lhs, rhs: rhs, sourceFile: sourceFile, sourceRange: sourceRange)
        default:
            return super.logicalNegated()
        }
        negated.mayBeSharedMutableValue = mayBeSharedMutableValue
        return negated
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

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(lhs, indentation: indentation).append(" \(op.symbol) ").append(rhs, indentation: indentation)
    }
}

class KotlinBooleanLiteral: KotlinExpression {
    var literal: Bool

    init(expression: BooleanLiteral) {
        self.literal = expression.literal
        super.init(type: .booleanLiteral, expression: expression)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(String(describing: literal))
    }
}

class KotlinClosure: KotlinExpression {
    var returnType: TypeSignature = .none
    var parameters: [Parameter<Void>] = []
    var implicitParameterLabels: [String] = []
    var isAnonymousFunction = false
    var body: KotlinCodeBlock
    var returnLabel: String? = nil

    static func translate(expression: Closure, translator: KotlinTranslator) -> KotlinClosure {
        // If there is an explicit return type we'll use an anonymous function rather than a closure,
        // as Kotlin closures cannot declare a return type
        let kbody = KotlinCodeBlock.translate(statement: expression.body, translator: translator)
        let isAnonymousFunction = expression.returnType != .none
        var implicitParameterLabels: [String] = []
        var returnLabel: String? = nil
        if isAnonymousFunction {
            if expression.returnType != .void {
                // A function that returns a value requires an explicit return
                kbody.updateWithExpectedReturn(.yes)
            }
        } else {
            // Closures require a label for any explicit return, or it will return from the other scope
            if kbody.updateWithExpectedReturn(.labelIfPresent("ll")) {
                returnLabel = "ll"
            }
            if expression.parameters.isEmpty {
                implicitParameterLabels = handleImplicitParameters(in: kbody, inferredType: expression.inferredType)
            }
        }
        let kexpression = KotlinClosure(expression: expression, body: kbody)
        kexpression.returnType = expression.returnType
        kexpression.parameters = expression.parameters
        kexpression.isAnonymousFunction = isAnonymousFunction
        kexpression.implicitParameterLabels = implicitParameterLabels
        kexpression.returnLabel = returnLabel
        return kexpression
    }

    private static func handleImplicitParameters(in body: KotlinCodeBlock, inferredType: TypeSignature) -> [String] {
        // Find the highest $n identifier used in the closure
        var highestParameter = -1
        body.visit { node in
            if node is KotlinClosure {
                return .skip
            } else if let identifier = node as? KotlinIdentifier {
                if let index = identifier.name.implicitClosureParameterIndex {
                    highestParameter = max(highestParameter, index)
                }
                return .skip
            } else {
                return .recurse(nil)
            }
        }

        // The closure might have more parameters than were used
        if case .function(let parameters, _) = inferredType {
            highestParameter = max(highestParameter, parameters.count - 1)
        }

        // $0 can use the special 'it' built-in, so no need to return it
        guard highestParameter > 0 else {
            return []
        }
        return (0...highestParameter).map { KotlinIdentifier.translateName("$\($0)") }
    }

    private init(expression: Closure, body: KotlinCodeBlock) {
        self.body = body
        super.init(type: .closure, expression: expression)
    }

    override var children: [KotlinSyntaxNode] {
        return [body]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if isAnonymousFunction {
            output.append("fun(")
            for (index, parameter) in parameters.enumerated() {
                output.append(parameter.internalLabel).append(": ").append(parameter.declaredType)
                if index < parameters.count - 1 {
                    output.append(", ")
                }
            }
            output.append("): ").append(returnType).append(" {\n")
        } else {
            if let returnLabel {
                output.append(returnLabel).append("@")
            }
            output.append("{")
            if parameters.isEmpty && implicitParameterLabels.isEmpty {
                output.append("\n")
            } else {
                // We never have both explicit and implicit parameters
                for (index, parameter) in parameters.enumerated() {
                    if index == 0 {
                        output.append(" ")
                    }
                    output.append(parameter.internalLabel)
                    if parameter.declaredType != .none {
                        output.append(": ").append(parameter.declaredType)
                    }
                    if index < parameters.count - 1 {
                        output.append(", ")
                    }
                }
                if !implicitParameterLabels.isEmpty {
                    output.append(" ").append(implicitParameterLabels.joined(separator: ", "))
                }
                output.append(" ->\n")
            }
        }
        output.append(body, indentation: indentation.inc())
        output.append(indentation).append("}")
    }
}

class KotlinFunctionCall: KotlinExpression {
    var function: KotlinExpression
    var arguments: [LabeledValue<KotlinExpression>] = []
    var mayBeSharedMutableValueType = false
    var useTrailingClosureFormatting = true

    static func translate(expression: FunctionCall, translator: KotlinTranslator) -> KotlinFunctionCall {
        let kfunction = translator.translateExpression(expression.function)
        let kexpression = KotlinFunctionCall(expression: expression, function: kfunction)
        kexpression.arguments = expression.arguments.map {
            let kargumentExpression = translator.translateExpression($0.value).valueReference()
            return LabeledValue(label: $0.label, value: kargumentExpression)
        }
        kexpression.mayBeSharedMutableValueType = expression.inferredType.kotlinMayBeSharedMutableValue(codebaseInfo: translator.codebaseInfo)
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
        // The result of a function call is never a shared value because we always valref() on return
        return orType && mayBeSharedMutableValueType
    }

    override var children: [KotlinSyntaxNode] {
        return [function] + arguments.map { $0.value }
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        let hasTrailingClosure = useTrailingClosureFormatting && arguments.last?.value.type == .closure && (arguments.last?.value as? KotlinClosure)?.isAnonymousFunction == false
        let lastParenthesizedIndex = hasTrailingClosure ? arguments.count - 2 : arguments.count - 1
        output.append(function, indentation: indentation)
        if !hasTrailingClosure || arguments.count > 1 {
            output.append("(")
        }
        if lastParenthesizedIndex >= 0 {
            for (index, argument) in arguments[0...lastParenthesizedIndex].enumerated() {
                if let label = argument.label {
                    output.append(label).append(" = ")
                }
                output.append(argument.value, indentation: indentation)
                if index < lastParenthesizedIndex {
                    output.append(", ")
                }
            }
        }
        if !hasTrailingClosure || arguments.count > 1 {
            output.append(")")
        }
        if hasTrailingClosure {
            output.append(" ").append(arguments.last!.value, indentation: indentation)
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

    static func translateName(_ name: String) -> String {
        guard let implicitParameterIndex = name.implicitClosureParameterIndex else {
            return name
        }
        return implicitParameterIndex == 0 ? "it" : "it\(implicitParameterIndex)"
    }

    init(name: String, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.name = name
        super.init(type: .identifier, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(expression: Identifier) {
        self.name = expression.name
        super.init(type: .identifier, expression: expression)
    }

    override func mayBeSharedMutableValueExpression(orType: Bool) -> Bool {
        return mayBeSharedMutableValue
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if name == "self" {
            output.append("this")
        } else {
            output.append(Self.translateName(name))
        }
    }
}

class KotlinIf: KotlinExpression {
    var optionalBindingVariables: [OptionalBindingVariable] = []
    var conditions: [KotlinExpression]
    var isGuard = false
    var body: KotlinCodeBlock
    var elseBody: KotlinCodeBlock?

    struct OptionalBindingVariable {
        var name: String
        var declaredType: TypeSignature?
        var value: KotlinExpression
        var isLet: Bool
        var previousConditions: [KotlinExpression]
    }

    /// The entire `if/else if/else if/...` chain.
    ///
    /// The last element may have an `else`.
    var chain: [KotlinIf] {
        var chain = [self]
        while let elseif = chain.last?.elseif {
            chain.append(elseif)
        }
        return chain
    }

    private var elseif: KotlinIf? {
        guard let elseBody, elseBody.statements.count == 1, let expressionStatement = elseBody.statements.first as? KotlinExpressionStatement else {
            return nil
        }
        return expressionStatement.expression as? KotlinIf
    }

    static func translate(expression: If, translator: KotlinTranslator) -> KotlinIf {
        let (optionalBindingVariables, conditions) = extractOptionalBindingVariables(from: expression.conditions, translator: translator)
        let kconditions = conditions.compactMap { translator.translateExpression($0) }
        let kbody = KotlinCodeBlock.translate(statement: expression.body, translator: translator)
        let kexpression = KotlinIf(expression: expression, conditions: kconditions, body: kbody)
        kexpression.optionalBindingVariables = optionalBindingVariables
        if let elseBody = expression.elseBody {
            kexpression.elseBody = KotlinCodeBlock.translate(statement: elseBody, translator: translator)
        }
        return kexpression
    }

    static func translate(statement: Guard, translator: KotlinTranslator) -> KotlinExpressionStatement {
        let (optionalBindingVariables, conditions) = extractOptionalBindingVariables(from: statement.conditions, translator: translator)
        let kconditions = conditions.compactMap { translator.translateExpression($0).logicalNegated() }
        let kbody = KotlinCodeBlock.translate(statement: statement.body, translator: translator)
        let kexpression = KotlinIf(conditions: kconditions, body: kbody, sourceFile: statement.sourceFile, sourceRange: statement.sourceRange)
        kexpression.optionalBindingVariables = optionalBindingVariables
        kexpression.isGuard = true

        let kstatement = KotlinExpressionStatement(type: .expression)
        kstatement.expression = kexpression
        return kstatement
    }

    private static func extractOptionalBindingVariables(from conditions: [Expression], translator: KotlinTranslator) -> ([OptionalBindingVariable], [Expression]) {
        var optionalBindingVariables: [OptionalBindingVariable] = []
        var updatedConditions: [Expression] = []
        for condition in conditions {
            // Extract any 'let x = y' to a separate variable and update the condition to 'x != nil'
            if let optionalBinding = condition as? OptionalBinding {
                let optionalBindingValue: KotlinExpression
                if let value = optionalBinding.value {
                    optionalBindingValue = translator.translateExpression(value)
                } else {
                    let identifier = KotlinIdentifier(name: optionalBinding.name)
                    identifier.mayBeSharedMutableValue = optionalBinding.variableType.kotlinMayBeSharedMutableValue(codebaseInfo: translator.codebaseInfo)
                    optionalBindingValue = identifier
                }
                let optionalBindingVariable = OptionalBindingVariable(name: optionalBinding.name, declaredType: optionalBinding.declaredType, value: optionalBindingValue.valueReference(), isLet: optionalBinding.isLet)
                optionalBindingVariables.append(optionalBindingVariable)
                let updatedCondition = BinaryOperator(op: .with(symbol: "!="), lhs: Identifier(name: optionalBinding.name), rhs: NilLiteral())
                updatedConditions.append(updatedCondition)
            } else {
                updatedConditions.append(condition)
            }
        }
        return (optionalBindingVariables, updatedConditions)
    }

    init(conditions: [KotlinExpression], body: KotlinCodeBlock, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.conditions = conditions
        self.body = body
        super.init(type: .if, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(expression: Expression, conditions: [KotlinExpression], body: KotlinCodeBlock) {
        self.conditions = conditions
        self.body = body
        super.init(type: .if, expression: expression)
    }

    override var children: [KotlinSyntaxNode] {
        var children: [KotlinSyntaxNode] = conditions + optionalBindingVariables.compactMap { $0.value }
        children.append(body)
        if let elseBody {
            children.append(elseBody)
        }
        return children
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        let ifChain = chain
        let optionalBindingVariables = ifChain.flatMap { $0.optionalBindingVariables }
        for (index, optionalBindingVariable) in optionalBindingVariables.enumerated() {
            if index != 0 {
                output.append(indentation)
            }
            output.append(optionalBindingVariable.isLet ? "val " : "var ").append(optionalBindingVariable.name)
            output.append(" = ").append(optionalBindingVariable.value, indentation: indentation).append("\n")
        }
        for (index, statement) in chain.enumerated() {
            if index == 0 {
                if !optionalBindingVariables.isEmpty {
                    output.append(indentation)
                }
                output.append("if (")
            } else {
                output.append(indentation).append("} else if (")
            }
            statement.appendConditions(to: output, indentation: indentation)
            output.append(") {\n")

            let bodyIndentation = indentation.inc()
            output.append(statement.body, indentation: bodyIndentation)

            if index == chain.count - 1 {
                if let elseBody = statement.elseBody {
                    output.append(indentation).append("} else {\n")
                    output.append(elseBody, indentation: bodyIndentation)
                }
                output.append(indentation).append("}")
            }
        }
    }

    private func appendConditions(to output: OutputGenerator, indentation: Indentation) {
        guard conditions.count > 1 else {
            if let condition = conditions.first {
                condition.append(to: output, indentation: indentation)
            }
            return
        }

        for (index, condition) in conditions.enumerated() {
            // Special case the common !x compound expression to avoid unnecessary parentheses
            let isCompound = condition.isCompoundExpression && !(condition is KotlinPrefixOperator && (condition as! KotlinPrefixOperator).operatorSymbol == "!")
            if isCompound {
                output.append("(")
            }
            output.append(condition, indentation: indentation)
            if isCompound {
                output.append(")")
            }
            if index < conditions.count - 1 {
                output.append(" ").append(isGuard ? "||" : "&&").append(" ")
            }
        }
    }
}

class KotlinMemberAccess: KotlinExpression {
    var base: KotlinExpression?
    var member: String
    var useMultlineFormatting = false
    var inferredType: TypeSignature = .none
    var mayBeSharedMutableValue = false

    static func translate(expression: MemberAccess, translator: KotlinTranslator) -> KotlinMemberAccess {
        let kexpression = KotlinMemberAccess(expression: expression)
        if let base = expression.base {
            kexpression.base = translator.translateExpression(base)
            kexpression.useMultlineFormatting = expression.useMultlineFormatting
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

    enum BaseKind {
        case unknown
        case `this`
        case `super`
        case identifier(String)
        case type(TypeSignature)
    }

    var baseKind: BaseKind {
        if base == nil {
            return inferredType == .none ? .unknown : .type(inferredType)
        } else if let identifier = base as? KotlinIdentifier {
            if identifier.name == "self" {
                return .this
            } else if identifier.name == "super" {
                return .super
            } else {
                return .identifier(identifier.name)
            }
        } else {
            return .unknown
        }
    }

    override func mayBeSharedMutableValueExpression(orType: Bool) -> Bool {
        return mayBeSharedMutableValue
    }

    override var children: [KotlinSyntaxNode] {
        return base == nil ? [] : [base!]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if let base {
            output.append(base, indentation: indentation)
            if member != "init" {
                if useMultlineFormatting {
                    output.append("\n").append(indentation.inc())
                }
                output.append(".").append(member)
            }
        } else if inferredType != .none {
            output.append(inferredType)
            if member != "init" {
                if useMultlineFormatting {
                    output.append("\n").append(indentation.inc())
                }
                output.append(".").append(member)
            }
        } else {
            output.append(member)
        }
    }
}

class KotlinNullLiteral: KotlinExpression {
    init(expression: NilLiteral) {
        super.init(type: .nullLiteral, expression: expression)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append("null")
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

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(literal.replacingOccurrences(of: "_", with: ""))
    }
}

class KotlinParenthesized: KotlinExpression {
    var content: KotlinExpression

    static func translate(expression: Parenthesized, translator: KotlinTranslator) -> KotlinParenthesized {
        let kcontent = translator.translateExpression(expression.content)
        return KotlinParenthesized(expression: expression, content: kcontent)
    }

    init(content: KotlinExpression, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.content = content
        super.init(type: .parenthesized, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(expression: Parenthesized, content: KotlinExpression) {
        self.content = content
        super.init(type: .parenthesized, expression: expression)
    }

    override func logicalNegated() -> KotlinExpression {
        return KotlinParenthesized(content: content.logicalNegated(), sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override func mayBeSharedMutableValueExpression(orType: Bool) -> Bool {
        return content.mayBeSharedMutableValueExpression(orType: orType)
    }

    override var isCompoundExpression: Bool {
        return false
    }

    override var children: [KotlinSyntaxNode] {
        return [content]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append("(").append(content, indentation: indentation).append(")")
    }
}

class KotlinPrefixOperator: KotlinExpression {
    var operatorSymbol: String
    var target: KotlinExpression

    static func translate(expression: PrefixOperator, translator: KotlinTranslator) -> KotlinPrefixOperator {
        let ktarget = translator.translateExpression(expression.target)
        return KotlinPrefixOperator(expression: expression, target: ktarget)
    }

    init(operatorSymbol: String, target: KotlinExpression, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.operatorSymbol = operatorSymbol
        self.target = target
        super.init(type: .prefixOperator, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(expression: PrefixOperator, target: KotlinExpression) {
        self.operatorSymbol = expression.operatorSymbol
        self.target = target
        super.init(type: .prefixOperator, expression: expression)
    }

    override func logicalNegated() -> KotlinExpression {
        if operatorSymbol == "!" {
            return target
        } else {
            return super.logicalNegated()
        }
    }

    override func mayBeSharedMutableValueExpression(orType: Bool) -> Bool {
        return target.mayBeSharedMutableValueExpression(orType: orType)
    }

    override var isCompoundExpression: Bool {
        return true
    }

    override var children: [KotlinSyntaxNode] {
        return [target]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(operatorSymbol).append(target, indentation: indentation)
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

    override func append(to output: OutputGenerator, indentation: Indentation) {
        let delimiter = isMultiline ? "\"\"\"" : "\""
        output.append(delimiter)
        for segment in segments {
            switch segment {
            case .string(let string):
                output.append(string.replacing("$", with: "\\$"))
            case .expression(let expression):
                if let identifier = expression as? KotlinIdentifier {
                    output.append("$").append(identifier, indentation: indentation)
                } else {
                    output.append("${").append(expression, indentation: indentation).append("}")
                }
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
            let kargumentExpression = translator.translateExpression($0.value).valueReference()
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

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(base, indentation: indentation).append("[")
        for (index, argument) in arguments.enumerated() {
            if let label = argument.label {
                output.append(label).append(" = ")
            }
            output.append(argument.value, indentation: indentation)
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

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if isOptional {
            output.append("try { ").append(trying, indentation: indentation).append(" } catch (_: Exception) { null }")
        } else {
            output.append(trying, indentation: indentation)
        }
    }
}

class KotlinValueReference: KotlinExpression {
    var base: KotlinExpression
    var onUpdate: String?

    init(base: KotlinExpression, onUpdate: String? = nil) {
        self.base = base
        self.onUpdate = onUpdate
        super.init(type: .valueReference)
    }

    override func mayBeSharedMutableValueExpression(orType: Bool) -> Bool {
        return orType
    }

    override func valueReference(onUpdate: String? = nil) -> KotlinExpression {
        if let onUpdate {
            self.onUpdate = onUpdate
        }
        return self
    }

    override var children: [KotlinSyntaxNode] {
        return [base]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if base.isCompoundExpression {
            output.append("(").append(base, indentation: indentation).append(")")
        } else {
            output.append(base, indentation: indentation)
        }
        output.append(".valref(")
        if let onUpdate {
            output.append(onUpdate)
        }
        output.append(")")
    }
}
