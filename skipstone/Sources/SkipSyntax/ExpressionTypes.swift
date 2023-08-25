import SwiftSyntax

/// Supported Swift expression types.
enum ExpressionType: CaseIterable {
    case arrayLiteral
    case available
    case await
    case binaryOperator
    case binding
    case booleanLiteral
    case casePattern
    case closure
    case dictionaryLiteral
    case functionCall
    case identifier
    case `if`
    case `inout`
    case keyPathLiteral
    case matchingCase
    case memberAccess
    case nilLiteral
    case numericLiteral
    case optionalBinding
    case parenthesized
    case postfixIfDefined
    case postfixOperator
    case prefixOperator
    case stringLiteral
    case `subscript`
    case `switch`
    case switchCase
    case ternaryOperator
    case `try`
    case tupleLiteral
    case typeLiteral

    /// An expression representing raw Swift code.
    case raw

    /// The Swift data type that represents this expression type.
    var representingType: Expression.Type? {
        switch self {
        case .arrayLiteral:
            return ArrayLiteral.self
        case .available:
            return Available.self
        case .await:
            return Await.self
        case .binaryOperator:
            return BinaryOperator.self
        case .binding:
            return Binding.self
        case .booleanLiteral:
            return BooleanLiteral.self
        case .casePattern:
            return CasePattern.self
        case .closure:
            return Closure.self
        case .dictionaryLiteral:
            return DictionaryLiteral.self
        case .functionCall:
            return FunctionCall.self
        case .identifier:
            return Identifier.self
        case .if:
            return If.self
        case .inout:
            return InOut.self
        case .keyPathLiteral:
            return KeyPathLiteral.self
        case .matchingCase:
            return MatchingCase.self
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
        case .postfixIfDefined:
            return PostfixIfDefined.self
        case .postfixOperator:
            return PostfixOperator.self
        case .prefixOperator:
            return PrefixOperator.self
        case .stringLiteral:
            return StringLiteral.self
        case .subscript:
            return Subscript.self
        case .switch:
            return Switch.self
        case .switchCase:
            return SwitchCase.self
        case .ternaryOperator:
            return TernaryOperator.self
        case .try:
            return Try.self
        case .tupleLiteral:
            return TupleLiteral.self
        case .typeLiteral:
            return TypeLiteral.self

        case .raw:
            return RawExpression.self
        }
    }
}

/// `[a, b, c]`
class ArrayLiteral: Expression {
    let elements: [Expression]

    init(elements: [Expression], syntax: SyntaxProtocol?, sourceFile: Source.FilePath?, sourceRange: Source.Range? = nil) {
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
        var elementType = collectionType.elementType
        if expecting.elementType != .none {
            elementType = expecting.elementType
            elements.forEach { $0.inferTypes(context: context, expecting: elementType) }
        } else {
            switch expecting.asTypealiased(nil).withoutOptionality() {
            case .named, .member, .module:
                // An array literal that maps to a named type is likely an option set
                elementType = expecting
                elements.forEach { $0.inferTypes(context: context, expecting: expecting) }
            default:
                for element in elements {
                    element.inferTypes(context: context, expecting: elementType)
                    elementType = elementType.or(element.inferredType)
                }
            }
        }
        // We support initializing Sets from array literals
        if case .set = expecting.asTypealiased(nil).withoutOptionality() {
            collectionType = .set(elementType)
        } else {
            collectionType = .array(elementType)
        }
        return context
    }

    private var collectionType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return collectionType
    }

    override var children: [SyntaxNode] {
        return elements
    }
}

/// `#available(...)`
class Available: Expression {
    init(syntax: SyntaxProtocol?, sourceFile: Source.FilePath?, sourceRange: Source.Range? = nil) {
        super.init(type: .available, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .availabilityCondition else {
            return nil
        }
        return Available(syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override var inferredType: TypeSignature {
        return .bool
    }
}

/// `await ...`
class Await: Expression {
    let target: Expression

    init(target: Expression, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.target = target
        super.init(type: .await, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .awaitExpr, let awaitExpr = syntax.as(AwaitExprSyntax.self) else {
            return nil
        }
        let target = ExpressionDecoder.decode(syntax: awaitExpr.expression, in: syntaxTree)
        return Await(target: target, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
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
}

/// `+, -, *, ...`
class BinaryOperator: Expression {
    let op: Operator
    let lhs: Expression
    let rhs: Expression

    init(op: Operator, lhs: Expression, rhs: Expression, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.op = op
        self.lhs = lhs
        self.rhs = rhs
        super.init(type: .binaryOperator, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decodeSequenceOperator(syntax: SyntaxProtocol, sequence: SyntaxProtocol, elements: [ExprSyntax], index: Int, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard let op = op(for: syntax) else {
            return nil
        }
        var lhs = try ExpressionDecoder.decodeSequence(sequence, elements: Array(elements[..<index]), in: syntaxTree)
        var rhs = try ExpressionDecoder.decodeSequence(sequence, elements: Array(elements[(index + 1)...]), in: syntaxTree)
        // When 'await' appears on one side of a binary expression, it actually applies to both branches, e.g. 'let x = await a + b'
        var isAwait = false
        if op.precedence != .assignment {
            if let lhsAwait = lhs as? Await {
                lhs = lhsAwait.target
                isAwait = true
            }
            if let rhsAwait = rhs as? Await {
                rhs = rhsAwait.target
                isAwait = true
            }
        }
        let binaryOperator = BinaryOperator(op: op, lhs: lhs, rhs: rhs, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
        return isAwait ? Await(target: binaryOperator) : binaryOperator
    }

    private static func op(for syntax: SyntaxProtocol) -> Operator? {
        switch syntax.kind {
        case .assignmentExpr:
            if let assignmentExpr = syntax.as(AssignmentExprSyntax.self) {
                return Operator.with(symbol: assignmentExpr.equal.text)
            }
        case .binaryOperatorExpr:
            if let binaryOperatorExpr = syntax.as(BinaryOperatorExprSyntax.self) {
                return Operator.with(symbol: binaryOperatorExpr.operator.text)
            }
        case .unresolvedAsExpr:
            if let asExpr = syntax.as(UnresolvedAsExprSyntax.self) {
                let suffix = asExpr.questionOrExclamationMark?.text ?? ""
                return Operator.with(symbol: "as\(suffix)")
            }
        case .unresolvedIsExpr:
            return Operator.with(symbol: "is")
        default:
            break
        }
        return nil
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
            // Handled by TernaryOperator
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
            lhs.inferTypes(context: context, expecting: expecting.asOptional(true))
            rhs.inferTypes(context: context, expecting: lhs.inferredType.asOptional(false))
            // Custom version of our doubleCheckLHS function above
            if lhs.inferredType == .none && rhs.inferredType != .none {
                lhs.inferTypes(context: context, expecting: rhs.inferredType.asOptional(true))
            }
            resultType = expecting.or(rhs.inferredType)
        case .cast:
            let type = (rhs as? TypeLiteral)?.literal ?? expecting
            lhs.inferTypes(context: context, expecting: type)
            rhs.inferTypes(context: context, expecting: .none)
            resultType = op.symbol == "is" ? .bool : type
        case .range:
            lhs.inferTypes(context: context, expecting: expecting.elementType)
            rhs.inferTypes(context: context, expecting: lhs.inferredType)
            doubleCheckLHS()
            resultType = expecting.or(.range(lhs.inferredType))
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

/// `[if case .a(] let x  [)]`
class Binding: Expression, BindingExpression {
    private(set) var identifierPatterns: [IdentifierPattern]
    var variableTypes: [TypeSignature] {
        return variableType.tupleTypes(count: identifierPatterns.count)
    }
    private var variableType: TypeSignature = .none

    // BindingExpression
    var bindings: [String: TypeSignature] {
        return Dictionary(uniqueKeysWithValues: zip(identifierPatterns.map(\.name), variableTypes).compactMap { $0.0 == nil ? nil : ($0.0!, $0.1) })
    }
    func bindAsVar() {
        identifierPatterns = identifierPatterns.map {
            return IdentifierPattern(name: $0.name, isVar: true)
        }
    }

    init(identifierPatterns: [IdentifierPattern], syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.identifierPatterns = identifierPatterns
        super.init(type: .binding, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        var identifierPatterns: [IdentifierPattern]? = nil
        if syntax.kind == .discardAssignmentExpr || syntax.kind == .unresolvedPatternExpr, let expr = syntax.as(ExprSyntax.self) {
            identifierPatterns = expr.identifierPatterns(in: syntaxTree)
        } else if let patternSyntax = syntax.as(PatternSyntax.self) {
            identifierPatterns = patternSyntax.identifierPatterns(in: syntaxTree)
        }
        guard let identifierPatterns else {
            return nil
        }
        return Binding(identifierPatterns: identifierPatterns, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        variableType = expecting
        return context
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return zip(identifierPatterns, variableTypes).map {
            let description = "\($0.0.isVar ? "var" : "let") \($0.0.name ?? "_"): \($0.1)"
            return PrettyPrintTree(root: description)
        }
    }
}

/// `true, false`
class BooleanLiteral: Expression {
    let literal: Bool

    init(literal: Bool, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.literal = literal
        super.init(type: .booleanLiteral, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) -> Expression? {
        guard syntax.kind == .booleanLiteralExpr, let booleanLiteralExpr = syntax.as(BooleanLiteralExprSyntax.self) else {
            return nil
        }
        let literal = booleanLiteralExpr.literal.text == "true"
        return BooleanLiteral(literal: literal, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override var inferredType: TypeSignature {
        return .bool
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: String(describing: literal))]
    }
}

/// Synthetic expression representing the pattern to match in a case expression.
class CasePattern: Expression, BindingExpression {
    let value: Expression
    private(set) var isVar: Bool
    private(set) var isNonNilMatch: Bool

    // BindingExpression
    var bindings: [String: TypeSignature] {
        var bindings: [String: TypeSignature] = [:]
        value.visit {
            if let bindingExpression = $0 as? BindingExpression {
                bindings.merge(bindingExpression.bindings) { _, new in new }
            }
            return .recurse(nil)
        }
        return bindings
    }
    func bindAsVar() {
        isVar = true
        value.visit {
            ($0 as? BindingExpression)?.bindAsVar()
            return .recurse(nil)
        }
    }

    init(syntax: PatternSyntax, in syntaxTree: SyntaxTree) {
        let (value, isVar) = syntax.expression(in: syntaxTree)
        if let postfixOperator = value as? PostfixOperator, postfixOperator.operatorSymbol == "?" {
            self.value = postfixOperator.target
            self.isNonNilMatch = true
        } else {
            self.value = value
            self.isNonNilMatch = false
        }
        self.isVar = isVar
        super.init(type: .casePattern, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
        if isVar {
            bindAsVar()
        }
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        let valueContext = value.inferTypes(context: context, expecting: expecting)
        valueType = value.inferredType
        if isNonNilMatch {
            valueType = valueType.asOptional(false)
        }
        return valueContext
    }

    private var valueType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return valueType
    }

    override var children: [SyntaxNode] {
        return [value]
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return isVar ? ["var"] : []
    }
}

/// `{ ... }`
class Closure: Expression {
    private(set) var captureList: [(CaptureType, LabeledValue<Expression>)]
    private(set) var returnType: TypeSignature
    private(set) var parameters: [Parameter<Void>]
    let attributes: Attributes
    let isAsync: Bool
    let isThrows: Bool
    let body: CodeBlock
    var apiFlags: APIFlags {
        return APIFlags(isAsync: isAsync, isThrows: isThrows, isMainActor: attributes.contains(.mainActor), isViewBuilder: attributes.contains(.viewBuilder))
    }

    init(captureList: [(CaptureType, LabeledValue<Expression>)] = [], returnType: TypeSignature = .none, parameters: [Parameter<Void>], attributes: Attributes = Attributes(), isAsync: Bool = false, isThrows: Bool = false, body: CodeBlock, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.captureList = captureList
        self.returnType = returnType
        self.parameters = parameters
        self.attributes = attributes
        self.isAsync = isAsync
        self.isThrows = isThrows
        self.body = body
        super.init(type: .closure, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) -> Expression? {
        guard syntax.kind == .closureExpr, let closureExpr = syntax.as(ClosureExprSyntax.self) else {
            return nil
        }
        let captureList = closureExpr.signature?.capture?.items.compactMap { (item: ClosureCaptureSyntax) -> (CaptureType, LabeledValue<Expression>)? in
            var type: CaptureType = .none
            if let specifier = item.specifier?.specifier.text {
                if specifier == "unowned" {
                    type = .unowned
                } else if specifier == "weak" {
                    type = .weak
                }
            }
            let expression = ExpressionDecoder.decode(syntax: item.expression, in: syntaxTree)
            let label = item.name?.text
            return (type, LabeledValue(label: label, value: expression))
        } ?? []
        let (returnType, parameters, messages) = closureExpr.signature?.typeSignatures(in: syntaxTree) ?? (.none, [], [])
        let attributes = Attributes.for(syntax: closureExpr.signature?.attributes, in: syntaxTree)
        let isAsync = closureExpr.signature?.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = closureExpr.signature?.effectSpecifiers?.throwsSpecifier != nil
        let statements = StatementDecoder.decode(syntaxList: closureExpr.statements, in: syntaxTree)
        let body = CodeBlock(statements: statements)
        let expression = Closure(captureList: captureList, returnType: returnType, parameters: parameters, attributes: attributes, isAsync: isAsync, isThrows: isThrows, body: body, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
        expression.messages = messages
        return expression
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        captureList.forEach { $0.1.value.inferTypes(context: context, expecting: .none) }
        let parameterSignatures = parameters.map { parameter in
            TypeSignature.Parameter(label: parameter.externalLabel, type: parameter.declaredType, isInOut: parameter.isInOut, isVariadic: parameter.isVariadic, hasDefaultValue: parameter.defaultValue != nil )
        }
        functionType = attributes.apply(toFunction: .function(parameterSignatures, returnType, apiFlags, nil)).or(expecting)

        let bodyContext = context.pushing(self)
        let _ = body.inferTypes(context: bodyContext, expecting: body.statements.count == 1 && bodyContext.expectedReturn != .void ? bodyContext.expectedReturn : .none)
        // Use any type information we can glean from return statements in the body
        functionType = .function(functionType.parameters, functionType.returnType.or(body.returnType, replaceAny: true), functionType.apiFlags, functionType.additionalAttributes)
        return context
    }

    var functionType: TypeSignature = .function([], .none, [], nil)

    override var inferredType: TypeSignature {
        return functionType
    }

    override var children: [SyntaxNode] {
        return captureList.map(\.1.value) + [body]
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

/// `[a: b, c: d]`
class DictionaryLiteral: Expression {
    let entries: [(key: Expression, value: Expression)]

    init(entries: [(key: Expression, value: Expression)], syntax: SyntaxProtocol?, sourceFile: Source.FilePath?, sourceRange: Source.Range? = nil) {
        self.entries = entries
        super.init(type: .dictionaryLiteral, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .dictionaryExpr, let dictionaryExpr = syntax.as(DictionaryExprSyntax.self) else {
            return nil
        }
        var entries: [(Expression, Expression)] = []
        if case .elements(let elements) = dictionaryExpr.content {
            entries = elements.map {
                let keyExpression = ExpressionDecoder.decode(syntax: $0.key, in: syntaxTree)
                let valueExpression = ExpressionDecoder.decode(syntax: $0.value, in: syntaxTree)
                return (keyExpression, valueExpression)
            }
        }
        return DictionaryLiteral(entries: entries, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        if case .dictionary(let ktype, let vtype) = expecting, ktype != .none, vtype != .none {
            keyType = ktype
            valueType = vtype
            entries.forEach {
                $0.key.inferTypes(context: context, expecting: ktype)
                $0.value.inferTypes(context: context, expecting: vtype)
            }
        } else {
            for entry in entries {
                entry.key.inferTypes(context: context, expecting: keyType)
                keyType = keyType.or(entry.key.inferredType)
                entry.value.inferTypes(context: context, expecting: valueType)
                valueType = valueType.or(entry.value.inferredType)
            }
        }
        return context
    }

    private var keyType: TypeSignature = .none
    private var valueType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return .dictionary(keyType, valueType)
    }

    override var children: [SyntaxNode] {
        return entries.flatMap { [$0.key, $0.value] }
    }
}

/// `function(...)`
class FunctionCall: Expression, APICallExpression {
    let function: Expression
    let arguments: [LabeledValue<Expression>]
    private(set) var isInit = false
    /// Whether this is a call on the `Optional` type, e.g. `Optional<T>.map`.
    private(set) var isCallOnOptional = false

    init(function: Expression, arguments: [LabeledValue<Expression>], syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.function = function
        self.arguments = arguments
        super.init(type: .functionCall, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .functionCallExpr, let functionCallExpr = syntax.as(FunctionCallExprSyntax.self) else {
            return nil
        }
        let function = ExpressionDecoder.decode(syntax: functionCallExpr.calledExpression, in: syntaxTree)
        var labeledExpressions = functionCallExpr.arguments.map {
            let label = $0.label?.text
            let expression = ExpressionDecoder.decode(syntax: $0.expression, in: syntaxTree)
            return LabeledValue(label: label, value: expression)
        }
        if let trailingClosure = functionCallExpr.trailingClosure {
            let expression = ExpressionDecoder.decode(syntax: trailingClosure, in: syntaxTree)
            labeledExpressions.append(LabeledValue(value: expression))
        }
        labeledExpressions += functionCallExpr.additionalTrailingClosures.map {
            let label = $0.label.text
            let expression = ExpressionDecoder.decode(syntax: $0.closure, in: syntaxTree)
            return LabeledValue(label: label, value: expression)
        }
        return FunctionCall(function: function, arguments: labeledExpressions, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        let baseType: TypeSignature?
        let name: String?
        var isUnchainedOptional = false
        switch function.type {
        case .arrayLiteral:
            // Must be a constructor call, e.g. [String]()
            function.inferTypes(context: context, expecting: expecting)
            if case .array(let element) = function.inferredType {
                returnType = .array(element.asMetaType(false))
            } else {
                returnType = function.inferredType.or(expecting)
            }
            isInit = true
            return context
        case .dictionaryLiteral:
            // Must be a constructor call, e.g. [String: Int]()
            function.inferTypes(context: context, expecting: expecting)
            if case .dictionary(let keyType, let valueType) = function.inferredType {
                returnType = .dictionary(keyType.asMetaType(false), valueType.asMetaType(false))
            } else {
                returnType = function.inferredType.or(expecting)
            }
            isInit = true
            return context
        case .identifier:
            let identifier = function as! Identifier
            let _ = identifier.inferTypes(context: context, expecting: .none)
            if identifier.inferredType.isMetaType {
                // Assume the call is a constructor. Do not assume return type is the same, however, as we might use the
                // constructor params to resolve generics
                baseType = identifier.inferredType.asMetaType(false)
                name = nil
            } else {
                baseType = nil
                name = identifier.name
            }
        case .memberAccess:
            let memberAccess = function as! MemberAccess
            if memberAccess.base == nil {
                // Supply expected result type as probable base type when base is missing
                _ = memberAccess.inferTypes(context: context, expecting: expecting)
            } else {
                _ = memberAccess.inferTypes(context: context, expecting: .none)
            }
            if memberAccess.inferredType.isMetaType {
                baseType = memberAccess.inferredType.asMetaType(false)
                name = nil
            } else {
                baseType = memberAccess.baseType // Note: our type inference differentiates between .none and nil
                name = memberAccess.member
                isUnchainedOptional = Self.isUnchainedOptional(expression: memberAccess.base)
            }
        default:
            function.inferTypes(context: context, expecting: .none)
            let functionType = function.inferredType.asTypealiased(nil).asOptional(false).withoutOptionality()
            if case .function(_, var returnType, let apiFlags, _) = functionType {
                if function.inferredType.isOptional {
                    returnType = returnType.asOptional(true)
                }
                self.returnType = returnType.or(expecting)
                apiMatch = APIMatch(signature: functionType, apiFlags: apiFlags)
            } else {
                returnType = expecting
            }
            return context
        }

        // First we infer argument types without knowing the function, so we expect .none
        arguments.forEach { $0.value.inferTypes(context: context, expecting: .none) }
        let argumentTypes = arguments.map { $0.value.inferredType }
        let match: (TypeSignature, APIMatch)?
        let matchBaseType: TypeSignature?
        if isUnchainedOptional, let name, let baseType, baseType.withModuleName(nil) != .none, let optionalMatch = context.function(name, in: .named("Optional", [baseType]), arguments: arguments, expectedReturn: expecting, messagesNode: nil) {
            match = optionalMatch
            matchBaseType = .named("Optional", [baseType])
        } else {
            match = context.function(name, in: baseType, arguments: arguments, expectedReturn: expecting, messagesNode: self)
            matchBaseType = baseType
        }
        if var match {
            // Re-infer arguments now that we know the parameter types
            for (index, argument) in arguments.enumerated() {
                argument.value.inferTypes(context: context, expecting: match.0.parameters[index].type)
            }
            // If any argument types changed, it could affect the return type of a generic function
            let refinedArgumentTypes = arguments.map({ $0.value.inferredType })
            if argumentTypes != refinedArgumentTypes {
                if let refinedMatch = context.function(name, in: matchBaseType, arguments: arguments, expectedReturn: expecting, messagesNode: nil) {
                    match = refinedMatch
                }
            }
            isInit = match.1.declarationType == .initDeclaration
            apiMatch = match.1
            returnType = match.0.returnType.or(expecting)
            if isUnchainedOptional {
                isCallOnOptional = true
            }
        } else {
            returnType = expecting
        }
        return context
    }

    private static func isUnchainedOptional(expression: Expression?) -> Bool {
        guard let expression else {
            return false
        }
        guard expression.inferredType.isOptional else {
            return false
        }
        guard (expression as? PostfixOperator)?.operatorSymbol != "?" else {
            return false
        }
        guard let apiCallExpression = expression as? APICallExpression else {
            return true // Any optional that isn't an identifier, member access, or function call would normally need to be chained
        }
        guard let apiMatch = apiCallExpression.apiMatch else {
            return false // Unknown defaults to false
        }
        return apiMatch.signature.isOptional || apiMatch.signature.returnType.isOptional
    }

    private var returnType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return returnType
    }
    var apiMatch: APIMatch?

    override var children: [SyntaxNode] {
        return [function] + arguments.map { $0.value }
    }
}

/// `x`, also `self` or `super`
class Identifier: Expression, APICallExpression {
    let name: String
    private(set) var generics: [TypeSignature]?
    /// Whether this appears to be a local variable or parameter.
    private(set) var isLocalOrSelfIdentifier: Bool
    var isModuleNameFor: TypeSignature = .none

    init(name: String, generics: [TypeSignature]? = nil, isLocalOrSelfIdentifier: Bool = false, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.name = name
        self.generics = generics
        self.isLocalOrSelfIdentifier = isLocalOrSelfIdentifier
        super.init(type: .identifier, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        let name: String
        var generics: [TypeSignature]? = nil
        if syntax.kind == .identifierExpr, let identifierExpr = syntax.as(DeclReferenceExprSyntax.self) {
            name = identifierExpr.baseName.text
        } else if syntax.kind == .superRefExpr {
            name = "super"
        } else if syntax.kind == .specializeExpr, let specializeExpr = syntax.as(GenericSpecializationExprSyntax.self), specializeExpr.expression.kind == .identifierExpr, let identifierExpr = specializeExpr.expression.as(DeclReferenceExprSyntax.self) {
            name = identifierExpr.baseName.text
            generics = specializeExpr.genericArgumentClause.arguments.map { TypeSignature.for(syntax: $0.argument, in: syntaxTree) }
        } else {
            return nil
        }
        return Identifier(name: name, generics: generics, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func resolveAttributes(in syntaxTree: SyntaxTree, context: TypeResolutionContext) {
        generics = generics?.map { $0.resolved(in: self, context: context) }
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        if let (signature, match) = context.identifier(name, messagesNode: self) {
            identifierType = signature
            apiMatch = match
        }
        if let generics, !generics.isEmpty {
            if identifierType == .none {
                identifierType = TypeSignature.for(name: name, genericTypes: generics).asMetaType(true)
            } else {
                identifierType = identifierType.withGenerics(generics)
            }
        }
        identifierType = identifierType.or(expecting)
        if !isLocalOrSelfIdentifier {
            isLocalOrSelfIdentifier = context.isLocalOrSelfIdentifier(name)
        }
        return context
    }

    private var identifierType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return identifierType
    }
    var apiMatch: APIMatch?

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var children: [PrettyPrintTree] = []
        if let generics, !generics.isEmpty {
            children = [PrettyPrintTree(root: "<\(generics.map(\.description).joined(separator: ", "))>" )]
        }
        return [PrettyPrintTree(root: name, children: children)]
    }
}

/// `if ...`
class If: Expression {
    let conditions: [Expression]
    let body: CodeBlock
    let elseBody: CodeBlock?

    init(conditions: [Expression], body: CodeBlock, elseBody: CodeBlock? = nil, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.conditions = conditions
        self.body = body
        self.elseBody = elseBody
        super.init(type: .if, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .ifExpr, let ifExpr = syntax.as(IfExprSyntax.self) else {
            return nil
        }

        let conditions = ifExpr.conditions.map { ExpressionDecoder.decode(syntax: $0.condition, in: syntaxTree) }
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
        var bindings: [String: TypeSignature] = [:]
        for condition in conditions {
            conditionsContext = condition.inferTypes(context: conditionsContext, expecting: .bool)
            if let bindingExpression = condition as? BindingExpression {
                let conditionBindings = bindingExpression.bindings
                conditionsContext = conditionsContext.addingIdentifiers(conditionBindings)
                bindings.merge(conditionBindings) { _, new in new }
            }
        }
        let bodyContext = context.pushingBlock(identifiers: bindings)
        let _ = body.inferTypes(context: bodyContext, expecting: expecting)
        if let elseBody {
            let _ = elseBody.inferTypes(context: context, expecting: expecting)
        }
        bodyType = bodyType.or(body.returnType)
        return context
    }

    private var bodyType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return bodyType
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

/// `&x`
class InOut: Expression {
    let target: Expression

    init(target: Expression, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.target = target
        super.init(type: .inout, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .inOutExpr, let inOutExpr = syntax.as(InOutExprSyntax.self) else {
            return nil
        }
        let target = ExpressionDecoder.decode(syntax: inOutExpr.expression, in: syntaxTree)
        return InOut(target: target, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
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
}

/// `\.x`
class KeyPathLiteral: Expression {
    private(set) var root: TypeSignature = .none
    let components: [Component]

    enum Component {
        case property(String)
        case optional
        case unwrappedOptional
    }

    init(root: TypeSignature, components: [Component], syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.root = root
        self.components = components
        super.init(type: .keyPathLiteral, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .keyPathExpr, let keyPathExpr = syntax.as(KeyPathExprSyntax.self) else {
            return nil
        }
        var root: TypeSignature = .none
        if let rootExpr = keyPathExpr.root {
            root = TypeSignature.for(syntax: rootExpr, in: syntaxTree)
        }
        var components: [Component] = []
        for componentExpr in keyPathExpr.components {
            switch componentExpr.component {
            case .property(let syntax):
                if syntax.genericArgumentClause != nil {
                    throw Message.keyPathUnsupported(syntax, source: syntaxTree.source)
                }
                let name = syntax.declName.baseName.text
                components.append(.property(name))
            case .subscript(let syntax):
                throw Message.keyPathUnsupported(syntax, source: syntaxTree.source)
            case .optional(let syntax):
                if syntax.questionOrExclamationMark.text == "?" {
                    components.append(.optional)
                } else {
                    components.append(.unwrappedOptional)
                }
            }
        }
        return KeyPathLiteral(root: root, components: components, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func resolveAttributes(in syntaxTree: SyntaxTree, context: TypeResolutionContext) {
        root = root.resolved(in: self, context: context)
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        var root = root
        var expectingLeaf: TypeSignature = .none
        var isKeyPathExpected = false
        if expecting.isKeyPath {
            isKeyPathExpected = true
            if expecting.generics.count == 2 {
                root = root.or(expecting.generics[0])
                expectingLeaf = expecting.generics[1]
            }
        } else if case .function(let parameters, let returnType, _, _) = expecting {
            if parameters.count == 1 {
                root = root.or(parameters[0].type)
            }
            expectingLeaf = returnType
        }
        var leaf = root
        for component in components {
            switch component {
            case .property(let name):
                if name != "self" {
                    if let match = context.member(name, in: leaf, messagesNode: self) {
                        leaf = match.0
                    } else {
                        leaf = .none
                        break
                    }
                }
            case .optional:
                leaf = leaf.asOptional(true)
            case .unwrappedOptional:
                leaf = leaf.asUnwrappedOptional(true)
            }
        }
        leaf = leaf.or(expectingLeaf)
        if isKeyPathExpected {
            keyPathType = .named("KeyPath", [root, leaf])
        } else {
            keyPathType = .function([.init(type: root)], leaf, [], nil).or(expecting)
        }
        return context
    }

    private var keyPathType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return keyPathType
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var string = "\\"
        if root != .none {
            string.append(root.description)
        }
        for component in components {
            string.append(".")
            switch component {
            case .property(let name):
                string.append(name)
            case .optional:
                string.append("?")
            case .unwrappedOptional:
                string.append("!")
            }
        }
        return [PrettyPrintTree(root: string)]
    }
}

/// `case .a = x`
class MatchingCase: Expression, BindingExpression {
    let pattern: CasePattern
    private(set) var declaredType: TypeSignature
    let target: Expression

    // BindingExpression
    var bindings: [String : TypeSignature] {
        return pattern.bindings
    }
    func bindAsVar() {
        pattern.bindAsVar()
    }

    init(pattern: CasePattern, declaredType: TypeSignature = .none, target: Expression, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.pattern = pattern
        self.declaredType = declaredType
        self.target = target
        super.init(type: .matchingCase, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .matchingPatternCondition, let matchingPatternExpr = syntax.as(MatchingPatternConditionSyntax.self) else {
            return nil
        }
        let pattern = CasePattern(syntax: matchingPatternExpr.pattern, in: syntaxTree)
        var declaredType: TypeSignature = .none
        if let typeSyntax = matchingPatternExpr.typeAnnotation?.type {
            declaredType = TypeSignature.for(syntax: typeSyntax, in: syntaxTree)
        }
        let target = ExpressionDecoder.decode(syntax: matchingPatternExpr.initializer.value, in: syntaxTree)
        return MatchingCase(pattern: pattern, declaredType: declaredType, target: target, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func resolveAttributes(in syntaxTree: SyntaxTree, context: TypeResolutionContext) {
        declaredType = declaredType.resolved(in: self, context: context)
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        target.inferTypes(context: context, expecting: declaredType)
        return pattern.inferTypes(context: context, expecting: target.inferredType)
    }

    override var inferredType: TypeSignature {
        return .bool
    }

    override var children: [SyntaxNode] {
        return [pattern, target]
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return declaredType == .none ? [] : [PrettyPrintTree(root: declaredType.description)]
    }
}

/// `person.name`
class MemberAccess: Expression, APICallExpression {
    var base: Expression?
    private(set) var baseType: TypeSignature // Will be .module(name, .none) for module qualifier
    let member: String
    private(set) var generics: [TypeSignature]?
    let useMultlineFormatting: Bool

    init(base: Expression?, baseType: TypeSignature = .none, member: String, generics: [TypeSignature]? = nil, useMultlineFormatting: Bool = false, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.base = base
        self.baseType = baseType
        self.member = member
        self.generics = generics
        self.useMultlineFormatting = useMultlineFormatting
        super.init(type: .memberAccess, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        var syntax = syntax
        var generics: [TypeSignature]? = nil
        if syntax.kind == .specializeExpr, let specializeExpr = syntax.as(GenericSpecializationExprSyntax.self), specializeExpr.expression.kind == .memberAccessExpr {
            syntax = specializeExpr.expression
            generics = specializeExpr.genericArgumentClause.arguments.map { TypeSignature.for(syntax: $0.argument, in: syntaxTree) }
        }
        guard syntax.kind == .memberAccessExpr, let memberAccessExpr = syntax.as(MemberAccessExprSyntax.self) else {
            return nil
        }
        var base: Expression? = nil
        if let baseSyntax = memberAccessExpr.base {
            base = ExpressionDecoder.decode(syntax: baseSyntax, in: syntaxTree)
        }
        let member = memberAccessExpr.declName.baseName.text
        let useMultlineFormatting = base != nil && memberAccessExpr.period.leadingTrivia.contains {
            switch $0 {
            case .newlines:
                return true
            default:
                return false
            }
        }
        return MemberAccess(base: base, member: member, generics: generics, useMultlineFormatting: useMultlineFormatting, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func resolveAttributes(in syntaxTree: SyntaxTree, context: TypeResolutionContext) {
        baseType = baseType.resolved(in: self, context: context)
        generics = generics?.map { $0.resolved(in: self, context: context) }
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        if let base {
            base.inferTypes(context: context, expecting: .none)
            baseType = baseType.or(base.inferredType)
        } else {
            // When the base is missing we assume it's the class of the expected result type
            baseType = baseType.or(expecting.asMetaType(true).asOptional(false))
        }
        // If we don't recognize the base type, perhaps it's a module name. Treat it as a type name and
        // context.member(_:in:) will figure it out
        let baseIdentifier = base as? Identifier
        var baseType = self.baseType
        if baseType == .none, let baseIdentifier {
            baseType = .named(baseIdentifier.name, baseIdentifier.generics ?? []).asMetaType(true)
        }
        // Don't output availability messages here if this is part of a function call. There could be other
        // member matches. The function call node will have more type information
        if let (signature, match) = context.member(member, in: baseType, messagesNode: isCalledAsFunction ? nil : self) {
            memberType = signature
            apiMatch = match
            if let generics, !generics.isEmpty {
                memberType = memberType.withGenerics(generics)
            }
            // Were we able to resolve the member by treating our unknown base identifier as a module name?
            if self.baseType == .none, memberType != .none, let baseIdentifier, baseIdentifier.generics?.isEmpty != false {
                baseIdentifier.isModuleNameFor = memberType
                self.baseType = .module(baseIdentifier.name, .none)
            }
        } else if let generics, !generics.isEmpty {
            memberType = .named(member, generics).asMember(of: self.baseType)
        }
        memberType = memberType.or(expecting)
        return context
    }

    private var memberType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return memberType
    }
    var apiMatch: APIMatch?

    override var children: [SyntaxNode] {
        return base == nil ? [] : [base!]
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: member)]
    }
}

/// `nil`
class NilLiteral: Expression {
    init(syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
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

    init(literal: String, isFloatingPoint: Bool, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.literal = literal
        self.isFloatingPoint = isFloatingPoint
        super.init(type: .numericLiteral, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) -> Expression? {
        let literal: String
        let isFloatingPoint: Bool
        if syntax.kind == .floatLiteralExpr, let floatLiteralExpr = syntax.as(FloatLiteralExprSyntax.self) {
            literal = floatLiteralExpr.literal.text
            isFloatingPoint = true
        } else if syntax.kind == .integerLiteralExpr, let integerLiteralExpr = syntax.as(IntegerLiteralExprSyntax.self) {
            literal = integerLiteralExpr.literal.text
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
class OptionalBinding: Expression, BindingExpression {
    let names: [String?]
    private(set) var declaredType: TypeSignature
    let isLet: Bool
    let value: Expression?
    // Whether this is a 'let x' or 'let x = x' binding where 'x' may be concurrently mutated (i.e. is a writeable member/global)
    private(set) var nameShadowsUnstableValue: Bool
    var variableTypes: [TypeSignature] {
        return variableType.tupleTypes(count: names.count)
    }
    private var variableType: TypeSignature = .none

    // BindingExpression
    var bindings: [String: TypeSignature] {
        return Dictionary(uniqueKeysWithValues: zip(names, variableTypes).compactMap { $0.0 == nil ? nil : ($0.0!, $0.1) })
    }
    func bindAsVar() {
    }

    init(names: [String?], declaredType: TypeSignature = .none, isLet: Bool = true, value: Expression? = nil, nameShadowsUnstableValue: Bool = false, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.names = names
        self.declaredType = declaredType
        self.isLet = isLet
        self.value = value
        self.nameShadowsUnstableValue = nameShadowsUnstableValue
        self.variableType = declaredType
        super.init(type: .optionalBinding, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .optionalBindingCondition, let optionalBindingExpr = syntax.as(OptionalBindingConditionSyntax.self) else {
            return nil
        }
        guard let names = optionalBindingExpr.pattern.identifierPatterns(in: syntaxTree)?.map(\.name) else {
            throw Message.unsupportedSyntax(optionalBindingExpr.pattern, source: syntaxTree.source)
        }
        let isLet = optionalBindingExpr.bindingSpecifier.text == "let"
        var declaredType: TypeSignature = .none
        if let typeSyntax = optionalBindingExpr.typeAnnotation?.type {
            declaredType = TypeSignature.for(syntax: typeSyntax, in: syntaxTree)
        }
        var value: Expression? = nil
        if let valueSyntax = optionalBindingExpr.initializer?.value {
            value = ExpressionDecoder.decode(syntax: valueSyntax, in: syntaxTree)
        }
        return OptionalBinding(names: names, declaredType: declaredType, isLet: isLet, value: value, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func resolveAttributes(in syntaxTree: SyntaxTree, context: TypeResolutionContext) {
        declaredType = declaredType.resolved(in: self, context: context)
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        value?.inferTypes(context: context, expecting: declaredType.asOptional(true))
        variableType = declaredType
        if variableType == .none {
            if let value {
                variableType = value.inferredType
            } else {
                variableType = TypeSignature.for(labels: names, types: names.map { $0.map { context.identifier($0, messagesNode: self)?.0 ?? .none } ?? .none })
            }
        }
        // Flow will only continue when the value is non-optional
        variableType = variableType.asOptional(false)

        if names.count == 1, let name = names[0], !context.isLocalOrSelfIdentifier(name), value == nil || (value as? Identifier)?.name == name {
            if let (_, match) = context.identifier(name, messagesNode: nil) {
                nameShadowsUnstableValue = match.apiFlags.contains(.writeable)
            } else {
                nameShadowsUnstableValue = true // Better safe than sorry
            }
        }

        return context.addingIdentifiers(bindings)
    }

    override var children: [SyntaxNode] {
        return value != nil ? [value!] : []
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        var attrs = [PrettyPrintTree(root: names.map { $0 ?? "_" }.joined(separator: ", "))]
        if declaredType != .none {
            attrs.append(PrettyPrintTree(root: declaredType.description))
        }
        return attrs
    }
}

/// `(...)`
class Parenthesized: Expression {
    let content: Expression

    init(content: Expression, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.content = content
        super.init(type: .parenthesized, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .tupleExpr, let tupleExpr = syntax.as(TupleExprSyntax.self), tupleExpr.elements.count == 1, let exprSyntax = tupleExpr.elements.first?.expression else {
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

/// `View().x()`
///     `#if SYMBOL
///     `.y()`
///     `#else`
///     `.z()`
///     `#endif`
///
/// - Note: We never instantiate this class. It is only used ot extract the statements from an `#if`.
class PostfixIfDefined: Expression {
    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .postfixIfConfigExpr, let postfixIfConfigExpr = syntax.as(PostfixIfConfigExprSyntax.self) else {
            return nil
        }
        guard let baseSyntax = postfixIfConfigExpr.base else {
            throw Message.ifDeclPlacement(syntax, source: syntaxTree.source)
        }
        let base = ExpressionDecoder.decode(syntax: baseSyntax, in: syntaxTree)
        guard let expression = IfDefined.decodePostfix(syntax: postfixIfConfigExpr.config, baseExpression: base, in: syntaxTree) else {
            throw Message.ifDeclPlacement(syntax, source: syntaxTree.source)
        }
        return expression
    }
}

/// `x?`, `x...`, etc
class PostfixOperator: Expression {
    let operatorSymbol: String
    let target: Expression

    init(operatorSymbol: String, target: Expression, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.operatorSymbol = operatorSymbol
        self.target = target
        super.init(type: .postfixOperator, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        let operatorSymbol: String
        let target: Expression
        if syntax.kind == .forcedValueExpr, let forceUnwrapExpr = syntax.as(ForceUnwrapExprSyntax.self) {
            operatorSymbol = "!"
            target = ExpressionDecoder.decode(syntax: forceUnwrapExpr.expression, in: syntaxTree)
        } else if syntax.kind == .optionalChainingExpr, let optionalChainingExpr = syntax.as(OptionalChainingExprSyntax.self) {
            operatorSymbol = "?"
            target = ExpressionDecoder.decode(syntax: optionalChainingExpr.expression, in: syntaxTree)
        } else if syntax.kind == .postfixUnaryExpr, let postfixExpr = syntax.as(PostfixOperatorExprSyntax.self) {
            operatorSymbol = postfixExpr.operator.text
            target = ExpressionDecoder.decode(syntax: postfixExpr.expression, in: syntaxTree)
        } else {
            return nil
        }
        return PostfixOperator(operatorSymbol: operatorSymbol, target: target, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        target.inferTypes(context: context, expecting: expecting.asOptional(true))
        return context
    }

    override var inferredType: TypeSignature {
        switch operatorSymbol {
        case "!":
            return target.inferredType.asOptional(false)
        case "?":
            return target.inferredType.asOptional(true)
        case "...":
            return .range(target.inferredType)
        default:
            return target.inferredType
        }
    }

    override var children: [SyntaxNode] {
        return [target]
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: operatorSymbol)]
    }
}

/// `!x`, `..<x`, etc
class PrefixOperator: Expression {
    let operatorSymbol: String
    let target: Expression

    init(operatorSymbol: String, target: Expression, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.operatorSymbol = operatorSymbol
        self.target = target
        super.init(type: .prefixOperator, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        if syntax.kind == .prefixOperatorExpr, let prefixOperatorExpr = syntax.as(PrefixOperatorExprSyntax.self) {
            let target = ExpressionDecoder.decode(syntax: prefixOperatorExpr.expression, in: syntaxTree)
            let operatorSymbol = prefixOperatorExpr.operator.text
            return PrefixOperator(operatorSymbol: operatorSymbol, target: target, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
        } else if syntax.kind == .isTypePattern, let isTypeExpr = syntax.as(IsTypePatternSyntax.self) {
            let typeSignature = TypeSignature.for(syntax: isTypeExpr.type, in: syntaxTree)
            let target = TypeLiteral(literal: typeSignature, syntax: isTypeExpr.type, sourceFile: syntaxTree.source.file, sourceRange: isTypeExpr.type.range(in: syntaxTree.source))
            return PrefixOperator(operatorSymbol: "is", target: target, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
        } else {
            return nil
        }
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        target.inferTypes(context: context, expecting: expecting)
        return context
    }

    override var inferredType: TypeSignature {
        switch operatorSymbol {
        case "..<", "...":
            return .range(target.inferredType)
        default:
            return target.inferredType
        }
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

    init(segments: [StringLiteralSegment<Expression>], isMultiline: Bool = false, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.segments = segments
        self.isMultiline = isMultiline
        super.init(type: .stringLiteral, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) -> Expression? {
        guard syntax.kind == .stringLiteralExpr, let stringLiteralExpr = syntax.as(StringLiteralExprSyntax.self) else {
            return nil
        }
        let isMultiline = stringLiteralExpr.openingPounds != nil || stringLiteralExpr.openingQuote.tokenKind == .multilineStringQuote
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
class Subscript: Expression, APICallExpression {
    let base: Expression
    let arguments: [LabeledValue<Expression>]

    init(base: Expression, arguments: [LabeledValue<Expression>], syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.base = base
        self.arguments = arguments
        super.init(type: .subscript, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .subscriptExpr, let subscriptExpr = syntax.as(SubscriptCallExprSyntax.self) else {
            return nil
        }
        let base = ExpressionDecoder.decode(syntax: subscriptExpr.calledExpression, in: syntaxTree)
        var labeledExpressions = subscriptExpr.arguments.map {
            let label = $0.label?.text
            let expression = ExpressionDecoder.decode(syntax: $0.expression, in: syntaxTree)
            return LabeledValue(label: label, value: expression)
        }
        if let trailingClosure = subscriptExpr.trailingClosure {
            let expression = ExpressionDecoder.decode(syntax: trailingClosure, in: syntaxTree)
            labeledExpressions.append(LabeledValue(value: expression))
        }
        labeledExpressions += subscriptExpr.additionalTrailingClosures.map {
            let label = $0.label.text
            let expression = ExpressionDecoder.decode(syntax: $0.closure, in: syntaxTree)
            return LabeledValue(label: label, value: expression)
        }
        return Subscript(base: base, arguments: labeledExpressions)
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        base.inferTypes(context: context, expecting: .none)

        // First we infer argument types without knowing the function, so we expect .none
        arguments.forEach { $0.value.inferTypes(context: context, expecting: .none) }
        if let match = context.subscript(in: base.inferredType, arguments: arguments, expectedReturn: expecting, messagesNode: self) {
            // Re-infer arguments now that we know the parameter types
            for (index, argument) in arguments.enumerated() {
                argument.value.inferTypes(context: context, expecting: match.0.parameters[index].type)
            }
            returnType = match.0.returnType.or(expecting)
            apiMatch = match.1
        } else {
            returnType = expecting
        }
        return context
    }

    private var returnType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return returnType
    }
    var apiMatch: APIMatch?

    override var children: [SyntaxNode] {
        return [base] + arguments.map { $0.value }
    }
}

/// `switch x { ... }`
class Switch: Expression {
    let on: Expression
    let cases: [SwitchCase]

    init(on: Expression, cases: [SwitchCase], syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.on = on
        self.cases = cases
        super.init(type: .switch, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .switchExpr, let switchExpr = syntax.as(SwitchExprSyntax.self) else {
            return nil
        }
        let on = ExpressionDecoder.decode(syntax: switchExpr.subject, in: syntaxTree)
        let (switchCases, messages) = decodeCaseList(syntax: switchExpr.cases, in: syntaxTree)
        let expression = Switch(on: on, cases: switchCases, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
        expression.messages = messages
        return expression
    }

    static func decodeCaseList(syntax: SwitchCaseListSyntax, in syntaxTree: SyntaxTree) -> ([SwitchCase], [Message]) {
        var switchCases: [SwitchCase] = []
        var messages: [Message] = []
        for caseItem in syntax {
            switch caseItem {
            case .ifConfigDecl(let syntax):
                let (ifCases, ifMessages) = IfDefined.decodeCaseList(syntax: syntax, in: syntaxTree)
                switchCases += ifCases
                messages += ifMessages
            case .switchCase(let syntax):
                if let switchCase = ExpressionDecoder.decode(syntax: syntax, in: syntaxTree) as? SwitchCase {
                    switchCases.append(switchCase)
                } else {
                    messages.append(.unsupportedSyntax(caseItem, source: syntaxTree.source))
                }
            }
        }
        return (switchCases, messages)
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        on.inferTypes(context: context, expecting: .none)
        cases.forEach { _ = $0.inferTypes(context: context, expecting: expecting) }
        if let firstCase = cases.first {
            bodyType = bodyType.or(firstCase.inferredType)
        }
        return context
    }

    private var bodyType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return bodyType
    }

    override var children: [SyntaxNode] {
        return [on] + cases
    }
}

/// `case x:` or `default:`, and also used for `catch` matching.
class SwitchCase: Expression, BindingExpression {
    let patterns: [(pattern: CasePattern, whereGuard: Expression?)] // Empty = default
    let body: CodeBlock

    // BindingExpression
    var bindings: [String : TypeSignature] {
        return patterns.reduce(into: [String: TypeSignature]()) { result, pattern in
            result.merge(pattern.pattern.bindings) { _, new in new }
        }
    }
    func bindAsVar() {
        patterns.forEach { $0.pattern.bindAsVar() }
    }

    init(patterns: [(CasePattern, Expression?)], body: CodeBlock, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.patterns = patterns
        self.body = body
        super.init(type: .switchCase, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        if syntax.kind == .switchCase, let switchCaseExpr = syntax.as(SwitchCaseSyntax.self) {
            return decodeSwitchCase(statement: switchCaseExpr, in: syntaxTree)
        } else if syntax.kind == .catchClause, let catchClause = syntax.as(CatchClauseSyntax.self) {
            return decodeCatchClause(statement: catchClause, in: syntaxTree)
        } else {
            return nil
        }
    }

    private static func decodeSwitchCase(statement: SwitchCaseSyntax, in syntaxTree: SyntaxTree) -> SwitchCase {
        let patterns: [(CasePattern, Expression?)]
        switch statement.label {
        case .case(let syntax):
            patterns = syntax.caseItems.map { item in
                let pattern = CasePattern(syntax: item.pattern, in: syntaxTree)
                let whereGuard = item.whereClause.map { ExpressionDecoder.decode(syntax: $0.condition, in: syntaxTree) }
                return (pattern, whereGuard)
            }
        case .default:
            patterns = []
            break
        }
        let body = CodeBlock(statements: StatementDecoder.decode(syntaxList: statement.statements, in: syntaxTree))
        return SwitchCase(patterns: patterns, body: body, syntax: statement, sourceFile: syntaxTree.source.file, sourceRange: statement.range(in: syntaxTree.source))
    }

    private static func decodeCatchClause(statement: CatchClauseSyntax, in syntaxTree: SyntaxTree) -> SwitchCase {
        let patterns: [(CasePattern, Expression?)] = statement.catchItems.compactMap { item in
            guard let itemPattern = item.pattern else {
                return nil
            }
            let pattern = CasePattern(syntax: itemPattern, in: syntaxTree)
            let whereGuard = item.whereClause.map { ExpressionDecoder.decode(syntax: $0.condition, in: syntaxTree) }
            return (pattern, whereGuard)
        }
        let body = CodeBlock(statements: StatementDecoder.decode(syntaxListContainer: statement.body, in: syntaxTree))
        return SwitchCase(patterns: patterns, body: body, syntax: statement, sourceFile: syntaxTree.source.file, sourceRange: statement.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        let patternsExpecting: TypeSignature
        if let switchStatement = parent as? Switch {
            patternsExpecting = switchStatement.on.inferredType
        } else if parent is DoCatch {
            patternsExpecting = .named("Error", [])
        } else {
            patternsExpecting = .none
        }
        var patternsContext = context
        var bindings: [String: TypeSignature] = [:]
        for pattern in patterns {
            patternsContext = pattern.pattern.inferTypes(context: patternsContext, expecting: patternsExpecting)
            pattern.whereGuard?.inferTypes(context: patternsContext, expecting: .bool)
            let patternBindings = pattern.pattern.bindings
            patternsContext = patternsContext.addingIdentifiers(patternBindings)
            bindings.merge(patternBindings) { _, new in new }
        }
        let bodyContext = context.pushingBlock(identifiers: bindings)
        let _ = body.inferTypes(context: bodyContext, expecting: expecting)
        bodyType = bodyType.or(body.returnType)
        return context
    }

    private var bodyType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return bodyType
    }

    override var children: [SyntaxNode] {
        var children: [SyntaxNode] = []
        for (pattern, whereGuard) in patterns {
            children.append(pattern)
            whereGuard.map { children.append($0) }
        }
        children.append(body)
        return children
    }
}

/// `b ? x : y`
class TernaryOperator: Expression {
    let condition: Expression
    let ifTrue: Expression
    let ifFalse: Expression

    init(condition: Expression, ifTrue: Expression, ifFalse: Expression, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.condition = condition
        self.ifTrue = ifTrue
        self.ifFalse = ifFalse
        super.init(type: .ternaryOperator, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decodeSequenceOperator(syntax: SyntaxProtocol, sequence: SyntaxProtocol, elements: [ExprSyntax], index: Int, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .unresolvedTernaryExpr, let ternaryExpr = syntax.as(UnresolvedTernaryExprSyntax.self) else {
            return nil
        }
        let condition = try ExpressionDecoder.decodeSequence(sequence, elements: Array(elements[..<index]), in: syntaxTree)
        let ifTrue = ExpressionDecoder.decode(syntax: ternaryExpr.thenExpression, in: syntaxTree)
        let ifFalse = try ExpressionDecoder.decodeSequence(sequence, elements: Array(elements[(index + 1)...]), in: syntaxTree)
        return TernaryOperator(condition: condition, ifTrue: ifTrue, ifFalse: ifFalse, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        condition.inferTypes(context: context, expecting: .bool)
        ifTrue.inferTypes(context: context, expecting: expecting)
        ifFalse.inferTypes(context: context, expecting: expecting.or(ifTrue.inferredType))
        // We attempt to evaluate ifTrue first, but maybe we were only able to figure out ifFalse
        if ifTrue.inferredType == .none && ifFalse.inferredType != .none {
            ifTrue.inferTypes(context: context, expecting: ifFalse.inferredType)
        }
        resultType = ifTrue.inferredType.or(ifFalse.inferredType)
        return context
    }

    private var resultType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return resultType
    }

    override var children: [SyntaxNode] {
        return [condition, ifTrue, ifFalse]
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

    init(trying: Expression, kind: Kind = .default, syntax: SyntaxProtocol?, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
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
        if kind == .optional {
            return trying.inferTypes(context: context, expecting: expecting.asOptional(false))
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

    init(labels: [String?], values: [Expression], syntax: SyntaxProtocol?, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
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
        for element in tupleExpr.elements {
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

/// `Int`
class TypeLiteral: Expression {
    private(set) var literal: TypeSignature

    init(literal: TypeSignature, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.literal = literal
        super.init(type: .typeLiteral, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override class func decode(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) throws -> Expression? {
        guard syntax.kind == .typeExpr, let typeExpr = syntax.as(TypeExprSyntax.self) else {
            return nil
        }
        return TypeLiteral(literal: TypeSignature.for(syntax: typeExpr.type, in: syntaxTree), sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source))
    }

    override func resolveAttributes(in syntaxTree: SyntaxTree, context: TypeResolutionContext) {
        literal = literal.resolved(in: self, context: context)
    }

    override var inferredType: TypeSignature {
        return literal.asMetaType(true)
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: literal.description)]
    }
}
