import SwiftSyntax

/// Supported Swift expression types.
enum ExpressionType: CaseIterable {
    case arrayLiteral
    case binaryOperator
    case booleanLiteral
    case functionCall
    case identifier
    case memberAccess
    case numericLiteral
    case stringLiteral
    case `subscript`
    case `try`

    /// An expression representing raw Swift code.
    case raw

    /// The Swift data type that represents this expression type.
    var representingType: Expression.Type? {
        switch self {
        case .arrayLiteral:
            return ArrayLiteral.self
        case .binaryOperator:
            return BinaryOperator.self
        case .booleanLiteral:
            return BooleanLiteral.self
        case .functionCall:
            return FunctionCall.self
        case .identifier:
            return Identifier.self
        case .memberAccess:
            return MemberAccess.self
        case .numericLiteral:
            return NumericLiteral.self
        case .stringLiteral:
            return StringLiteral.self
        case .subscript:
            return Subscript.self
        case .try:
            return Try.self

        case .raw:
            return RawExpression.self
        }
    }
}

/// `[...]`
class ArrayLiteral: Expression {
    let elements: [Expression]

    init(elements: [Expression], syntax: SyntaxProtocol?, sourceFile: Source.File?, sourceRange: Source.Range? = nil) {
        self.elements = elements
        super.init(type: .arrayLiteral, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .arrayExpr, let arrayExpr = syntax.as(ArrayExprSyntax.self) else {
            return nil
        }
        let elements = arrayExpr.elements.map {
            ExpressionDecoder.decode(syntax: $0.expression, in: syntaxTree)
        }
        return ArrayLiteral(elements: elements, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        if expecting.elementType != .none {
            elementType = expecting.elementType
            elements.forEach { $0.inferTypes(context: context, expecting: elementType) }
        } else {
            for element in elements {
                element.inferTypes(context: context, expecting: elementType)
                elementType = elementType.or(element.inferredType)
            }
        }
        return context
    }

    private var elementType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return .array(elementType)
    }

    override var children: [SyntaxNode] {
        return elements
    }
}

/// `+, -, *, ...`
class BinaryOperator: Expression {
    let op: Operator
    let lhs: Expression
    let rhs: Expression

    init(op: Operator, lhs: Expression, rhs: Expression, syntax: SyntaxProtocol?, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.op = op
        self.lhs = lhs
        self.rhs = rhs
        super.init(type: .binaryOperator, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decodeSequenceOperator(syntax: SyntaxProtocol, sequence: SyntaxProtocol, elements: [ExprSyntax], index: Int, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .binaryOperatorExpr, let binaryOperatorExpr = syntax.as(BinaryOperatorExprSyntax.self) else {
            return nil
        }
        let op = Operator.with(symbol: binaryOperatorExpr.operatorToken.text)
        let lhs = try ExpressionDecoder.decodeSequence(sequence: sequence, elements: Array(elements[..<index]), in: syntaxTree)
        let rhs = try ExpressionDecoder.decodeSequence(sequence: sequence, elements: Array(elements[(index + 1)...]), in: syntaxTree)
        return BinaryOperator(op: op, lhs: lhs, rhs: rhs, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        func doubleCheckLHS() {
            // We attempt to evaluate lhs first, but maybe we were only able to figure out rhs
            if lhs.inferredType == .none && rhs.inferredType != .none {
                lhs.inferTypes(context: context, expecting: rhs.inferredType)
            }
        }
        switch op.precedence {
        case .assignment:
            lhs.inferTypes(context: context, expecting: .none)
            rhs.inferTypes(context: context, expecting: lhs.inferredType)
            doubleCheckLHS()
            resultType = .void
        case .ternary:
            // TODO
            break
        case .unknown:
            lhs.inferTypes(context: context, expecting: expecting)
            rhs.inferTypes(context: context, expecting: expecting)
            resultType = lhs.inferredType
        case .or:
            fallthrough
        case .and:
            lhs.inferTypes(context: context, expecting: .bool)
            rhs.inferTypes(context: context, expecting: .bool)
            resultType = .bool
        case .comparison:
            lhs.inferTypes(context: context, expecting: .none)
            rhs.inferTypes(context: context, expecting: lhs.inferredType)
            doubleCheckLHS()
            resultType = .bool
        case .nilCoalescing:
            // TODO
            break
        case .cast:
            // TODO
            break
        case .range:
            lhs.inferTypes(context: context, expecting: .none)
            rhs.inferTypes(context: context, expecting: lhs.inferredType)
            doubleCheckLHS()
            resultType = context.operationResult(lhs.inferredType, rhs.inferredType)
        case .addition:
            fallthrough
        case .multiplication:
            lhs.inferTypes(context: context, expecting: .none)
            rhs.inferTypes(context: context, expecting: lhs.inferredType)
            doubleCheckLHS()
            resultType = context.operationResult(lhs.inferredType, rhs.inferredType)
        case .shift:
            lhs.inferTypes(context: context, expecting: .none)
            rhs.inferTypes(context: context, expecting: .int)
            doubleCheckLHS()
            resultType = lhs.inferredType
        }
        return context
    }

    private var resultType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return resultType
    }

    override var children: [SyntaxNode] {
        return [lhs, rhs]
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: op.symbol)]
    }
}

/// `true, false`
class BooleanLiteral: Expression {
    let literal: Bool

    init(literal: Bool, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.literal = literal
        super.init(type: .booleanLiteral, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) -> Expression? {
        guard syntax.kind == .booleanLiteralExpr, let booleanLiteralExpr = syntax.as(BooleanLiteralExprSyntax.self) else {
            return nil
        }
        let literal = booleanLiteralExpr.booleanLiteral.text == "true"
        return BooleanLiteral(literal: literal, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override var inferredType: TypeSignature {
        return .bool
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: String(describing: literal))]
    }
}

/// `function(...)`
class FunctionCall: Expression {
    let function: Expression
    let arguments: [LabeledValue<Expression>]

    init(function: Expression, arguments: [LabeledValue<Expression>], syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.function = function
        self.arguments = arguments
        super.init(type: .functionCall, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .functionCallExpr, let functionCallExpr = syntax.as(FunctionCallExprSyntax.self) else {
            return nil
        }
        let function = ExpressionDecoder.decode(syntax: functionCallExpr.calledExpression, in: syntaxTree)
        var labeledExpressions = functionCallExpr.argumentList.map {
            let label = $0.label?.text
            let expression = ExpressionDecoder.decode(syntax: $0.expression, in: syntaxTree)
            return LabeledValue(label: label, value: expression)
        }
        if let trailingClosure = functionCallExpr.trailingClosure {
            let expression = ExpressionDecoder.decode(syntax: trailingClosure, in: syntaxTree)
            labeledExpressions.append(LabeledValue(value: expression))
        }
        if let multipleTrailingClosures = functionCallExpr.additionalTrailingClosures {
            labeledExpressions += multipleTrailingClosures.map {
                let label = $0.label.text
                let expression = ExpressionDecoder.decode(syntax: $0.closure, in: syntaxTree)
                return LabeledValue(label: label, value: expression)
            }
        }
        return FunctionCall(function: function, arguments: labeledExpressions)
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        let baseType: TypeSignature
        let isMember: Bool
        let name: String
        switch function.type {
        case .identifier:
            baseType = .none
            isMember = false
            name = (function as! Identifier).name
        case .memberAccess:
            let memberAccess = function as! MemberAccess
            memberAccess.base?.inferTypes(context: context, expecting: .none)
            baseType = memberAccess.base?.inferredType ?? expecting
            isMember = true
            name = memberAccess.member
        default:
            function.inferTypes(context: context, expecting: .none)
            returnType = expecting
            return context
        }

        // First we infer argument types without knowing the function, so we expect .none
        arguments.forEach { $0.value.inferTypes(context: context, expecting: .none) }
        let parameters = arguments.map { LabeledValue<TypeSignature>(label: $0.label, value: $0.value.inferredType) }
        let (candidateFunction, message) = context.function(name, in: isMember ? baseType : nil, parameters: parameters)
        if candidateFunction != .none {
            // Re-infer arguments now that we know the parameter types
            for (index, argument) in arguments.enumerated() {
                argument.value.inferTypes(context: context, expecting: candidateFunction.parameterTypes[index])
            }
            returnType = candidateFunction.returnType
        } else {
            returnType = expecting
        }
        if let message {
            messages.append(message)
        }
        return context
    }

    private var returnType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return returnType
    }

    override var children: [SyntaxNode] {
        return [function] + arguments.map { $0.value }
    }
}

/// `x`
class Identifier: Expression {
    let name: String

    init(name: String, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.name = name
        super.init(type: .identifier, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .identifierExpr, let identifierExpr = syntax.as(IdentifierExprSyntax.self) else {
            return nil
        }
        let name = identifierExpr.identifier.text
        return Identifier(name: name, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        identifierType = context.identifier(name).or(expecting)
        return context
    }

    private var identifierType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return identifierType
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: name)]
    }
}

/// `person.name`
class MemberAccess: Expression {
    let base: Expression?
    let member: String

    init(base: Expression?, member: String, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.base = base
        self.member = member
        super.init(type: .memberAccess, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .memberAccessExpr, let memberAccessExpr = syntax.as(MemberAccessExprSyntax.self) else {
            return nil
        }
        var base: Expression? = nil
        if let baseSyntax = memberAccessExpr.base {
            base = ExpressionDecoder.decode(syntax: baseSyntax, in: syntaxTree)
        }
        let member = memberAccessExpr.name.text
        return MemberAccess(base: base, member: member, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        base?.inferTypes(context: context, expecting: expecting)
        memberType = context.member(member, in: base?.inferredType ?? expecting)
        return context
    }

    private var memberType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return memberType
    }

    override var children: [SyntaxNode] {
        return base == nil ? [] : [base!]
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: member)]
    }
}

/// `1, 1.0`
class NumericLiteral: Expression {
    let literal: String
    let isFloatingPoint: Bool

    init(literal: String, isFloatingPoint: Bool, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.literal = literal
        self.isFloatingPoint = isFloatingPoint
        super.init(type: .numericLiteral, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) -> Expression? {
        let literal: String
        let isFloatingPoint: Bool
        if syntax.kind == .floatLiteralExpr, let floatLiteralExpr = syntax.as(FloatLiteralExprSyntax.self) {
            literal = floatLiteralExpr.floatingDigits.text
            isFloatingPoint = true
        } else if syntax.kind == .integerLiteralExpr, let integerLiteralExpr = syntax.as(IntegerLiteralExprSyntax.self) {
            literal = integerLiteralExpr.digits.text
            isFloatingPoint = false
        } else {
            return nil
        }
        return NumericLiteral(literal: literal, isFloatingPoint: isFloatingPoint, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override var inferredType: TypeSignature {
        return isFloatingPoint ? .double : .int
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: literal)]
    }
}

/// `"..."`
class StringLiteral: Expression {
    let segments: [StringLiteralSegment<Expression>]
    let isMultiline: Bool

    init(segments: [StringLiteralSegment<Expression>], isMultiline: Bool = false, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.segments = segments
        self.isMultiline = isMultiline
        super.init(type: .stringLiteral, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) -> Expression? {
        guard syntax.kind == .stringLiteralExpr, let stringLiteralExpr = syntax.as(StringLiteralExprSyntax.self) else {
            return nil
        }
        let isMultiline = stringLiteralExpr.openQuote.tokenKind == .multilineStringQuote
        var segments: [StringLiteralSegment<Expression>] = []
        for segmentSyntax in stringLiteralExpr.segments {
            switch segmentSyntax {
            case .stringSegment(let stringSyntax):
                segments.append(.string(stringSyntax.content.text))
            case .expressionSegment(let expressionSyntax):
                guard let expressionSyntax = expressionSyntax.expressions.first?.expression else {
                    break
                }
                let expression = ExpressionDecoder.decode(syntax: expressionSyntax, in: syntaxTree)
                segments.append(.expression(expression))
            }
        }
        return StringLiteral(segments: segments, isMultiline: isMultiline, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        for segment in segments {
            if case .expression(let expression) = segment {
                expression.inferTypes(context: context, expecting: .none)
            }
        }
        if expecting == .character && segments.count == 1, case .string(let string) = segments[0], string.count == 1 {
            literalType = .character
        }
        return context
    }

    private var literalType: TypeSignature = .string

    override var inferredType: TypeSignature {
        return literalType
    }

    override var children: [SyntaxNode] {
        return segments.compactMap {
            switch $0 {
            case .expression(let expression):
                return expression
            case .string:
                return nil
            }
        }
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var expressionIndex = 0
        let segmentsDescription = segments.map { (segment) -> String in
            switch segment {
            case .expression:
                expressionIndex += 1
                return "\\(\(expressionIndex - 1))"
            case .string(let string):
                return string
            }
        }.joined(separator: "")
        let quotes = isMultiline ? "\"\"\"" : "\""
        return [PrettyPrintTree(root: "\(quotes)\(segmentsDescription)\(quotes)")]
    }
}

/// `array[0]`
class Subscript: Expression {
    let base: Expression
    let arguments: [LabeledValue<Expression>]

    init(base: Expression, arguments: [LabeledValue<Expression>], syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.base = base
        self.arguments = arguments
        super.init(type: .subscript, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .subscriptExpr, let subscriptExpr = syntax.as(SubscriptExprSyntax.self) else {
            return nil
        }
        let base = ExpressionDecoder.decode(syntax: subscriptExpr.calledExpression, in: syntaxTree)
        var labeledExpressions = subscriptExpr.argumentList.map {
            let label = $0.label?.text
            let expression = ExpressionDecoder.decode(syntax: $0.expression, in: syntaxTree)
            return LabeledValue(label: label, value: expression)
        }
        if let trailingClosure = subscriptExpr.trailingClosure {
            let expression = ExpressionDecoder.decode(syntax: trailingClosure, in: syntaxTree)
            labeledExpressions.append(LabeledValue(value: expression))
        }
        if let multipleTrailingClosures = subscriptExpr.additionalTrailingClosures {
            labeledExpressions += multipleTrailingClosures.map {
                let label = $0.label.text
                let expression = ExpressionDecoder.decode(syntax: $0.closure, in: syntaxTree)
                return LabeledValue(label: label, value: expression)
            }
        }
        return Subscript(base: base, arguments: labeledExpressions)
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        base.inferTypes(context: context, expecting: .none)

        // First we infer argument types without knowing the function, so we expect .none
        arguments.forEach { $0.value.inferTypes(context: context, expecting: .none) }
        let parameters = arguments.map { LabeledValue<TypeSignature>(label: $0.label, value: $0.value.inferredType) }
        let (candidateFunction, message) = context.subscript(in: base.inferredType, parameters: parameters)
        if candidateFunction != .none {
            // Re-infer arguments now that we know the parameter types
            for (index, argument) in arguments.enumerated() {
                argument.value.inferTypes(context: context, expecting: candidateFunction.parameterTypes[index])
            }
            returnType = candidateFunction.returnType
        } else {
            returnType = expecting
        }
        if let message {
            messages.append(message)
        }
        return context
    }

    private var returnType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return returnType
    }

    override var children: [SyntaxNode] {
        return [base] + arguments.map { $0.value }
    }
}

/// `try f()`
class Try: Expression {
    let trying: Expression
    let isOptional: Bool // try?

    init(trying: Expression, isOptional: Bool = false, syntax: SyntaxProtocol?, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.trying = trying
        self.isOptional = isOptional
        super.init(type: .try, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .tryExpr, let tryExpr = syntax.as(TryExprSyntax.self) else {
            return nil
        }
        let expression = ExpressionDecoder.decode(syntax: tryExpr.expression, in: syntaxTree)
        let isOptional = tryExpr.questionOrExclamationMark?.text == "?"
        return Try(trying: expression, isOptional: isOptional, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        if isOptional, case .optional(let type) = expecting {
            return trying.inferTypes(context: context, expecting: type)
        } else {
            return trying.inferTypes(context: context, expecting: expecting)
        }
    }

    override var inferredType: TypeSignature {
        let inferredType = trying.inferredType
        guard isOptional else {
            return inferredType
        }
        switch inferredType {
        case .none:
            return .none
        case .optional:
            return inferredType
        default:
            return .optional(inferredType)
        }
    }

    override var children: [SyntaxNode] {
        return [trying]
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return isOptional ? [PrettyPrintTree(root: "try?")] : []
    }
}
