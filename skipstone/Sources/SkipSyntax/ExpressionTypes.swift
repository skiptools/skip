import SwiftSyntax

/// Supported Swift expression types.
enum ExpressionType: CaseIterable {
    case arrayLiteral
    case binaryOperator
    case booleanLiteral
    case closure
    case functionCall
    case identifier
    case `if`
    case memberAccess
    case nilLiteral
    case numericLiteral
    case optionalBinding
    case parenthesized
    case stringLiteral
    case `subscript`
    case `try`
    case tupleLiteral
    case prefixOperator

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
        case .closure:
            return Closure.self
        case .functionCall:
            return FunctionCall.self
        case .identifier:
            return Identifier.self
        case .if:
            return If.self
        case .memberAccess:
            return MemberAccess.self
        case .nilLiteral:
            return NilLiteral.self
        case .numericLiteral:
            return NumericLiteral.self
        case .optionalBinding:
            return OptionalBinding.self
        case .parenthesized:
            return Parenthesized.self
        case .prefixOperator:
            return PrefixOperator.self
        case .stringLiteral:
            return StringLiteral.self
        case .subscript:
            return Subscript.self
        case .try:
            return Try.self
        case .tupleLiteral:
            return TupleLiteral.self

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

    init(op: Operator, lhs: Expression, rhs: Expression, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.op = op
        self.lhs = lhs
        self.rhs = rhs
        super.init(type: .binaryOperator, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decodeSequenceOperator(syntax: SyntaxProtocol, sequence: SyntaxProtocol, elements: [ExprSyntax], index: Int, in syntaxTree: SyntaxTree) throws -> Expression? {
        let op: Operator
        if syntax.kind == .binaryOperatorExpr, let binaryOperatorExpr = syntax.as(BinaryOperatorExprSyntax.self) {
            op = Operator.with(symbol: binaryOperatorExpr.operatorToken.text)
        } else if syntax.kind == .assignmentExpr, let assignmentExpr = syntax.as(AssignmentExprSyntax.self) {
            op = Operator.with(symbol: assignmentExpr.assignToken.text)
        } else {
            return nil
        }
        let lhs = try ExpressionDecoder.decodeSequence(sequence, elements: Array(elements[..<index]), in: syntaxTree)
        let rhs = try ExpressionDecoder.decodeSequence(sequence, elements: Array(elements[(index + 1)...]), in: syntaxTree)
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
            //~~~
            lhs.inferTypes(context: context, expecting: .none)
            rhs.inferTypes(context: context, expecting: lhs.inferredType)
            doubleCheckLHS()
            break
        case .cast:
            //~~~
            // TODO
            break
        case .range:
            lhs.inferTypes(context: context, expecting: .none)
            rhs.inferTypes(context: context, expecting: lhs.inferredType)
            doubleCheckLHS()
            resultType = .array(context.operationResult(lhs.inferredType, rhs.inferredType))
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

/// `{ ... }`
class Closure: Expression {
    // TODO: Capture list
    private(set) var returnType: TypeSignature
    private(set) var parameters: [Parameter<Void>]
    let isAsync: Bool
    let isThrows: Bool
    let body: CodeBlock

    init(returnType: TypeSignature = .none, parameters: [Parameter<Void>], isAsync: Bool = false, isThrows: Bool = false, body: CodeBlock, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.returnType = returnType
        self.parameters = parameters
        self.isAsync = isAsync
        self.isThrows = isThrows
        self.body = body
        super.init(type: .closure, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) -> Expression? {
        guard syntax.kind == .closureExpr, let closureExpr = syntax.as(ClosureExprSyntax.self) else {
            return nil
        }
        let (returnType, parameters, messages) = closureExpr.signature?.typeSignatures(in: syntaxTree) ?? (.none, [], [])
        let isAsync = closureExpr.signature?.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = closureExpr.signature?.effectSpecifiers?.throwsSpecifier != nil
        let statements = StatementDecoder.decode(syntaxList: closureExpr.statements, in: syntaxTree)
        let body = CodeBlock(statements: statements)
        let expression = Closure(returnType: returnType, parameters: parameters, isAsync: isAsync, isThrows: isThrows, body: body, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
        expression.messages = messages
        return expression
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        let parameterSignatures = parameters.map { parameter in
            TypeSignature.Parameter(label: parameter.externalLabel, type: parameter.declaredType, isVariadic: parameter.isVariadic, hasDefaultValue: parameter.defaultValue != nil )
        }
        functionType = .function(parameterSignatures, returnType).or(expecting)

        let bodyContext = context.pushing(self)
        let _ = body.inferTypes(context: bodyContext, expecting: .none)
        return context
    }

    var functionType: TypeSignature = .function([], .none)

    override var inferredType: TypeSignature {
        return functionType
    }

    override var children: [SyntaxNode] {
        return [body]
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var attrs: [PrettyPrintTree] = []
        if returnType != .none {
            attrs.append(PrettyPrintTree(root: returnType.description))
        }
        if !parameters.isEmpty {
            attrs.append(PrettyPrintTree(root: "parameters", children: parameters.map { $0.prettyPrintTree }))
        }
        if isAsync {
            attrs.append("async")
        }
        if isThrows {
            attrs.append("throws")
        }
        return attrs
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
        let baseType: TypeSignature?
        let name: String
        switch function.type {
        case .identifier:
            baseType = nil
            name = (function as! Identifier).name
        case .memberAccess:
            let memberAccess = function as! MemberAccess
            if memberAccess.base == nil {
                // Supply expected result type as probable base type when base is missing
                _ = memberAccess.inferTypes(context: context, expecting: expecting)
            } else {
                _ = memberAccess.inferTypes(context: context, expecting: .none)
            }
            baseType = memberAccess.baseType
            name = memberAccess.member
        default:
            function.inferTypes(context: context, expecting: .none)
            returnType = expecting
            return context
        }

        // First we infer argument types without knowing the function, so we expect .none
        arguments.forEach { $0.value.inferTypes(context: context, expecting: .none) }
        let parameters = arguments.map { LabeledValue<TypeSignature>(label: $0.label, value: $0.value.inferredType) }
        let candidateFunctions = context.function(name, in: baseType, parameters: parameters)
        if !candidateFunctions.isEmpty {
            if candidateFunctions.count > 1 {
                messages.append(.ambiguousFunctionCall(sourceFile: sourceFile, sourceRange: sourceRange))
            }
            let function = candidateFunctions.first { $0.returnType == expecting } ?? candidateFunctions[0]
            // Re-infer arguments now that we know the parameter types
            for (index, argument) in arguments.enumerated() {
                argument.value.inferTypes(context: context, expecting: function.parameters[index].type)
            }
            returnType = function.returnType.or(expecting)
        } else {
            returnType = expecting
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

/// `x`, also `this` or `super`
class Identifier: Expression {
    let name: String

    init(name: String, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.name = name
        super.init(type: .identifier, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        let name: String
        if syntax.kind == .identifierExpr, let identifierExpr = syntax.as(IdentifierExprSyntax.self) {
            name = identifierExpr.identifier.text
        } else if syntax.kind == .superRefExpr {
            name = "super"
        } else {
            return nil
        }
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

/// `if ...`
class If: Expression {
    let conditions: [Expression]
    let body: CodeBlock
    let elseBody: CodeBlock?

    init(conditions: [Expression], body: CodeBlock, elseBody: CodeBlock? = nil, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.conditions = conditions
        self.body = body
        self.elseBody = elseBody
        super.init(type: .if, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .ifExpr, let ifExpr = syntax.as(IfExprSyntax.self) else {
            return nil
        }

        let conditions = try ifExpr.conditions.map { try ExpressionDecoder.decodeCondition($0, in: syntaxTree) }
        let statements = StatementDecoder.decode(syntaxListContainer: ifExpr.body, in: syntaxTree)
        let body = CodeBlock(statements: statements)
        var elseBody: CodeBlock? = nil
        if let elseSyntax = ifExpr.elseBody {
            let statements: [Statement]
            switch elseSyntax {
            case .ifExpr(let syntax):
                statements = StatementDecoder.decode(syntax: syntax, in: syntaxTree)
            case .codeBlock(let syntax):
                statements = StatementDecoder.decode(syntaxListContainer: syntax, in: syntaxTree)
            }
            elseBody = CodeBlock(statements: statements)
        }
        return If(conditions: conditions, body: body, elseBody: elseBody, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        var conditionsContext = context
        var optionalBindings: [String: TypeSignature] = [:]
        for condition in conditions {
            conditionsContext = condition.inferTypes(context: conditionsContext, expecting: .bool)
            if let optionalBinding = condition as? OptionalBinding {
                conditionsContext = conditionsContext.addingIdentifiers(optionalBinding.names, types: optionalBinding.variableTypes)
                optionalBindings.merge(zip(optionalBinding.names, optionalBinding.variableTypes)) { _, new in new }
            }
        }
        let bodyContext = context.pushingBlock(identifiers: optionalBindings)
        let _ = body.inferTypes(context: bodyContext, expecting: .none)
        if let elseBody {
            let _ = elseBody.inferTypes(context: context, expecting: .none)
        }
        return context
    }

    override var children: [SyntaxNode] {
        var children: [SyntaxNode] = conditions
        children.append(body)
        if let elseBody {
            children.append(elseBody)
        }
        return children
    }
}

/// `person.name`
class MemberAccess: Expression {
    let base: Expression?
    private(set) var baseType: TypeSignature
    let member: String
    let useMultlineFormatting: Bool

    init(base: Expression?, baseType: TypeSignature = .none, member: String, useMultlineFormatting: Bool = false, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.base = base
        self.baseType = baseType
        self.member = member
        self.useMultlineFormatting = useMultlineFormatting
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
        let useMultlineFormatting = base != nil && memberAccessExpr.dot.leadingTrivia.contains {
            switch $0 {
            case .newlines:
                return true
            default:
                return false
            }
        }
        return MemberAccess(base: base, member: member, useMultlineFormatting: useMultlineFormatting, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        if let base {
            base.inferTypes(context: context, expecting: .none)
            baseType = baseType.or(base.inferredType)
        } else {
            baseType = baseType.or(expecting)
        }
        if baseType == .none {
            messages.append(.unknownMemberBaseType(member: member, sourceFile: sourceFile, sourceRange: sourceRange))
        }
        memberType = context.member(member, in: baseType).or(expecting)
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

/// `nil`
class NilLiteral: Expression {
    init(syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        super.init(type: .nilLiteral, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) -> Expression? {
        guard syntax.kind == .nilLiteralExpr, let _ = syntax.as(NilLiteralExprSyntax.self) else {
            return nil
        }
        return NilLiteral(syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        resultType = resultType.or(expecting)
        return context
    }

    private var resultType: TypeSignature = .optional(.none)

    override var inferredType: TypeSignature {
        return resultType
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

/// `[if/guard/for/while] let x = optional`
class OptionalBinding: Expression {
    let names: [String]
    private(set) var declaredType: TypeSignature
    let isLet: Bool
    let value: Expression?
    var variableTypes: [TypeSignature] {
        return variableType.tupleTypes(count: names.count)
    }
    private var variableType: TypeSignature = .none

    init(names: [String], declaredType: TypeSignature = .none, isLet: Bool, value: Expression? = nil, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.names = names
        self.declaredType = declaredType
        self.isLet = isLet
        self.value = value
        self.variableType = declaredType
        super.init(type: .optionalBinding, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .optionalBindingCondition, let optionalBindingExpr = syntax.as(OptionalBindingConditionSyntax.self) else {
            return nil
        }

        let isLet = optionalBindingExpr.bindingKeyword.text == "let"
        var declaredType: TypeSignature = .none
        if let typeSyntax = optionalBindingExpr.typeAnnotation?.type {
            declaredType = TypeSignature.for(syntax: typeSyntax)
        }
        var value: Expression? = nil
        if let valueSyntax = optionalBindingExpr.initializer?.value {
            value = ExpressionDecoder.decode(syntax: valueSyntax, in: syntaxTree)
        }

        let names = try optionalBindingExpr.pattern.identifierPatterns(in: syntaxTree).map(\.name)
        return OptionalBinding(names: names, declaredType: declaredType, isLet: isLet, value: value, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func resolveAttributes() {
        declaredType = declaredType.qualified(in: self)
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        value?.inferTypes(context: context, expecting: declaredType.asOptional(true))
        variableType = declaredType
        if variableType == .none {
            if let value {
                variableType = value.inferredType
            } else {
                variableType = TypeSignature.for(labels: names, types: names.map { context.identifier($0) })
            }
        }
        // Flow will only continue when the value is non-optional
        variableType = variableType.asOptional(false)
        return context.addingIdentifiers(names, types: variableTypes)
    }

    override var children: [SyntaxNode] {
        return value != nil ? [value!] : []
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var attrs = [PrettyPrintTree(root: names.joined(separator: ", "))]
        if declaredType != .none {
            attrs.append(PrettyPrintTree(root: declaredType.description))
        }
        return attrs
    }
}

/// `(...)`
class Parenthesized: Expression {
    let content: Expression

    init(content: Expression, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.content = content
        super.init(type: .parenthesized, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .tupleExpr, let tupleExpr = syntax.as(TupleExprSyntax.self), tupleExpr.elementList.count == 1, let exprSyntax = tupleExpr.elementList.first?.expression else {
            return nil
        }
        let content = ExpressionDecoder.decode(syntax: exprSyntax, in: syntaxTree)
        return Parenthesized(content: content, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        content.inferTypes(context: context, expecting: expecting)
        return context
    }

    override var inferredType: TypeSignature {
        return content.inferredType
    }

    override var children: [SyntaxNode] {
        return [content]
    }
}

/// `!x`
class PrefixOperator: Expression {
    let operatorSymbol: String
    let target: Expression

    init(operatorSymbol: String, target: Expression, syntax: SyntaxProtocol? = nil, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.operatorSymbol = operatorSymbol
        self.target = target
        super.init(type: .prefixOperator, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .prefixOperatorExpr, let prefixOperatorExpr = syntax.as(PrefixOperatorExprSyntax.self) else {
            return nil
        }
        let target = ExpressionDecoder.decode(syntax: prefixOperatorExpr.postfixExpression, in: syntaxTree)
        guard let operatorSymbol = prefixOperatorExpr.operatorToken?.text else {
            return target
        }
        return PrefixOperator(operatorSymbol: operatorSymbol, target: target, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        target.inferTypes(context: context, expecting: expecting)
        return context
    }

    override var inferredType: TypeSignature {
        return target.inferredType
    }

    override var children: [SyntaxNode] {
        return [target]
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: operatorSymbol)]
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
        let candidateFunctions = context.subscript(in: base.inferredType, parameters: parameters)
        if !candidateFunctions.isEmpty {
            if candidateFunctions.count > 1 {
                messages.append(.ambiguousFunctionCall(sourceFile: sourceFile, sourceRange: sourceRange))
            }
            let function = candidateFunctions.first { $0.returnType == expecting } ?? candidateFunctions[0]
            // Re-infer arguments now that we know the parameter types
            for (index, argument) in arguments.enumerated() {
                argument.value.inferTypes(context: context, expecting: function.parameters[index].type)
            }
            returnType = function.returnType.or(expecting)
        } else {
            returnType = expecting
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
    let kind: Kind

    enum Kind {
        case `default`
        case optional
        case unwrappedOptional
    }

    init(trying: Expression, kind: Kind = .default, syntax: SyntaxProtocol?, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.trying = trying
        self.kind = kind
        super.init(type: .try, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .tryExpr, let tryExpr = syntax.as(TryExprSyntax.self) else {
            return nil
        }
        let expression = ExpressionDecoder.decode(syntax: tryExpr.expression, in: syntaxTree)
        let kind: Kind = tryExpr.questionOrExclamationMark?.text == "?" ? .optional : tryExpr.questionOrExclamationMark?.text == "!" ? .unwrappedOptional : .default
        return Try(trying: expression, kind: kind, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        if kind == .optional, case .optional(let type) = expecting {
            return trying.inferTypes(context: context, expecting: type)
        } else {
            return trying.inferTypes(context: context, expecting: expecting)
        }
    }

    override var inferredType: TypeSignature {
        let inferredType = trying.inferredType
        switch kind {
        case .default:
            return inferredType
        case .optional:
            return inferredType.asOptional(true)
        case .unwrappedOptional:
            return inferredType
        }
    }

    override var children: [SyntaxNode] {
        return [trying]
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return kind != .default ? [PrettyPrintTree(root: String(describing: kind))] : []
    }
}

/// `(x, y, z)`
class TupleLiteral: Expression {
    let labels: [String?]
    let values: [Expression]

    init(labels: [String?], values: [Expression], syntax: SyntaxProtocol?, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.labels = labels
        self.values = values
        super.init(type: .tupleLiteral, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .tupleExpr, let tupleExpr = syntax.as(TupleExprSyntax.self) else {
            return nil
        }
        var labels: [String?] = []
        var values: [Expression] = []
        for element in tupleExpr.elementList {
            labels.append(element.label?.text)
            values.append(ExpressionDecoder.decode(syntax: element.expression, in: syntaxTree))
        }
        return TupleLiteral(labels: labels, values: values, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        let expectingTypes = expecting.tupleTypes(count: values.count)
        zip(values, expectingTypes).forEach { $0.0.inferTypes(context: context, expecting: $0.1) }
        return context
    }

    override var inferredType: TypeSignature {
        return TypeSignature.for(labels: labels, types: values.map { $0.inferredType })
    }

    override var children: [SyntaxNode] {
        return values
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        guard labels.contains(where: { $0 != nil }) else {
            return []
        }
        return [PrettyPrintTree(root: labels.map { String(describing: $0) }.joined(separator: ", "))]
    }
}
