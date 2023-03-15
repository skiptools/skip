/// Types of Kotlin expressions.
enum KotlinExpressionType {
    case arrayLiteral
    case binaryOperator
    case booleanLiteral
    case casePattern
    case closure
    case dictionaryLiteral
    case functionCall
    case identifier
    case `if`
    case `inout`
    case matchingCase
    case memberAccess
    case nullLiteral
    case numericLiteral
    case parenthesized
    case postfixOperator
    case prefixOperator
    case sharedExpressionPointer
    case sref
    case stringLiteral
    case `subscript`
    case ternaryOperator
    case `try`
    case tupleLiteral
    case typeLiteral
    case when

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

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
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
            // No need to sref() because the array already does
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
    var mayBeSharedMutableStruct = false

    static func translate(expression: BinaryOperator, translator: KotlinTranslator) -> KotlinBinaryOperator {
        let klhs = translator.translateExpression(expression.lhs)
        var krhs = translator.translateExpression(expression.rhs)
        // We need to sref() on assigning to a local var, but members sref() on assignment already.
        // This won't catch implicit members, however (i.e. 'x' in place of 'self.x')
        if expression.op.precedence == .assignment && !(klhs is KotlinMemberDeclaration) {
            krhs = krhs.sref()
        }
        let kexpression = KotlinBinaryOperator(expression: expression, lhs: klhs, rhs: krhs)
        kexpression.mayBeSharedMutableStruct = expression.inferredType.kotlinMayBeSharedMutableStruct(codebaseInfo: translator.codebaseInfo)
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
        case "in":
            negated =  KotlinBinaryOperator(op: Operator.with(symbol: "!in"), lhs: lhs, rhs: rhs, sourceFile: sourceFile, sourceRange: sourceRange)
        case "!in":
            negated =  KotlinBinaryOperator(op: Operator.with(symbol: "in"), lhs: lhs, rhs: rhs, sourceFile: sourceFile, sourceRange: sourceRange)
        case "is":
            negated =  KotlinBinaryOperator(op: Operator.with(symbol: "!is"), lhs: lhs, rhs: rhs, sourceFile: sourceFile, sourceRange: sourceRange)
        case "!is":
            negated =  KotlinBinaryOperator(op: Operator.with(symbol: "is"), lhs: lhs, rhs: rhs, sourceFile: sourceFile, sourceRange: sourceRange)
        default:
            return super.logicalNegated()
        }
        negated.mayBeSharedMutableStruct = mayBeSharedMutableStruct
        return negated
    }

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        return mayBeSharedMutableStruct
    }

    override var isCompoundExpression: Bool {
        return true
    }

    override var children: [KotlinSyntaxNode] {
        return [lhs, rhs]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(lhs, indentation: indentation).append(" \(op.kotlinSymbol) ").append(rhs, indentation: indentation)
    }
}

class KotlinBooleanLiteral: KotlinExpression {
    var literal: Bool

    init(literal: Bool = false, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.literal = literal
        super.init(type: .booleanLiteral, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    init(expression: BooleanLiteral) {
        self.literal = expression.literal
        super.init(type: .booleanLiteral, expression: expression)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(String(describing: literal))
    }
}

/// - Note: This type is used to translate the ``SwitchCase`` expression, but is not itself a `KotlinExpression`.
struct KotlinCase {
    var patterns: [KotlinExpression]
    var caseBindingVariables: [KotlinBindingVariable]
    var body: KotlinCodeBlock

    static func translate(expression: SwitchCase, matchingOn: KotlinExpression, isSealedClassesEnum: Bool, caseTargetVariable: inout KotlinCaseTargetVariable?, translator: KotlinTranslator) -> (KotlinCase, [Message]) {
        var messages: [Message] = []
        let caseValues: [(KotlinExpression?, [KotlinBindingVariable])] = expression.patterns.map { pattern in
            if let whereGuard = pattern.whereGuard {
                messages.append(.kotlinWhenCaseWhere(whereGuard))
            }
            let (targetVariable, bindingVariables, condition, caseMessages) = KotlinCasePattern.translate(expression: pattern.pattern, target: caseTargetVariable?.identifier ?? matchingOn, isSealedClassesEnum: isSealedClassesEnum, translator: translator)
            messages += caseMessages

            // If we find a case that requires a target variable, use it for the entire switch
            if caseTargetVariable == nil, let targetVariable {
                caseTargetVariable = targetVariable
            }
            return (condition, bindingVariables)
        }
        let kbody = KotlinCodeBlock.translate(statement: expression.body, translator: translator)
        return (KotlinCase(patterns: caseValues.compactMap(\.0), caseBindingVariables: caseValues.flatMap(\.1), body: kbody), messages)
    }

    var children: [KotlinSyntaxNode] {
        return patterns + caseBindingVariables.map(\.value) + [body]
    }
}

/// - Note: This type is used to translate the ``CasePattern`` expression, but is not itself a `KotlinExpression`.
struct KotlinCasePattern {
    static func translate(expression: CasePattern, target: KotlinExpression, isSealedClassesEnum: Bool, translator: KotlinTranslator) -> (targetVariable: KotlinCaseTargetVariable?, bindingVariables: [KotlinBindingVariable], condition: KotlinExpression?, messages: [Message]) {
        var targetVariable: KotlinCaseTargetVariable? = nil
        var bindingVariables: [KotlinBindingVariable] = []
        var messages: [Message] = []
        func updateVariables(for identifierPatterns: [IdentifierPattern], types: [TypeSignature], member: String? = nil) {
            guard identifierPatterns.contains(where: { $0.name != nil }) else {
                return
            }
            // If we have bindings and our target is not a simple local identifier, create a new target variable so
            // that re-evaluating the target for our binding values won't cause side effects
            if targetVariable == nil, (target as? KotlinIdentifier)?.isLocalIdentifier != true {
                targetVariable = KotlinCaseTargetVariable(value: target)
            }
            let bindingBase = targetVariable.map { KotlinSharedExpressionPointer(shared: $0.identifier) } ?? target
            var bindingValue: KotlinExpression
            if let member {
                bindingValue = KotlinMemberAccess(base: bindingBase, member: member)
            } else {
                bindingValue = bindingBase
            }
            // sref() any tuple or shared mutable type
            if types.count > 1 || types[0].kotlinMayBeSharedMutableStruct(codebaseInfo: translator.codebaseInfo) {
                bindingValue = bindingValue.sref()
            }
            let variable = KotlinBindingVariable(names: identifierPatterns.map(\.name), value: bindingValue, isLet: !(expression.isVar || identifierPatterns[0].isVar))
            bindingVariables.append(variable)
        }

        var value: KotlinExpression?
        var op = Operator.with(symbol: isSealedClassesEnum ? "is" : "==")
        switch expression.value.type {
        case .binding:
            if let binding = expression.value as? Binding {
                // case let x
                let identifierPatterns = binding.identifierPatterns
                let variableTypes = binding.variableTypes
                updateVariables(for: identifierPatterns, types: variableTypes)
                if expression.isNonNilMatch {
                    op = .with(symbol: "!=")
                    value = KotlinNullLiteral()
                } else {
                    value = nil
                }
            } else {
                value = translator.translateExpression(expression.value)
            }
        case .binaryOperator:
            if let binaryOperator = expression.value as? BinaryOperator {
                // case let x as Type
                if binaryOperator.op.symbol == "as", let binding = binaryOperator.lhs as? Binding {
                    op = Operator.with(symbol: "is")
                    value = translator.translateExpression(binaryOperator.rhs)
        
                    let identifierPatterns = binding.identifierPatterns
                    let variableTypes = binding.variableTypes
                    updateVariables(for: identifierPatterns, types: variableTypes)
                } else {
                    if binaryOperator.op.precedence == .range {
                        op = Operator.with(symbol: "in")
                    }
                    value = translator.translateExpression(expression.value)
                }
            } else {
                value = translator.translateExpression(expression.value)
            }
        case .prefixOperator:
            if let prefixOperator = expression.value as? PrefixOperator {
                if prefixOperator.operatorSymbol == "..<" || prefixOperator.operatorSymbol == "..." {
                    // case ..<x
                    op = Operator.with(symbol: "in")
                    value = translator.translateExpression(expression.value)
                } else if prefixOperator.operatorSymbol == "is" {
                    // case is x
                    op = Operator.with(symbol: "is")
                    value = translator.translateExpression(prefixOperator.target)
                } else {
                    value = translator.translateExpression(expression.value)
                }
            } else {
                value = translator.translateExpression(expression.value)
            }
        case .postfixOperator:
            value = translator.translateExpression(expression.value)
            // case x...
            if let postfixOperator = expression.value as? PostfixOperator, postfixOperator.operatorSymbol == "..." {
                op = Operator.with(symbol: "in")
            }
        case .functionCall:
            // case .enum(let value)
            if let functionCall = expression.value as? FunctionCall, functionCall.function.type == .memberAccess {
                var hasBindings = false
                var hasNonBindings = false
                for (index, argument) in functionCall.arguments.enumerated() {
                    guard let binding = argument.value as? Binding else {
                        hasNonBindings = true
                        continue
                    }
                    hasBindings = true
                    let identifierPatterns = binding.identifierPatterns
                    let variableTypes = binding.variableTypes
                    updateVariables(for: identifierPatterns, types: variableTypes, member: argument.label ?? "associated\(index)")
                }
                if hasBindings {
                    value = translator.translateExpression(functionCall.function)
                    if hasNonBindings {
                        messages.append(.kotlinWhenCasePartialBinding(functionCall))
                    }
                } else {
                    value = translator.translateExpression(expression.value)
                }
            } else {
                value = translator.translateExpression(expression.value)
            }
        case .tupleLiteral:
            // case let (x, y)
            if let tupleLiteral = expression.value as? TupleLiteral {
                var hasBindings = false
                var hasNonBindings = false
                for (index, (label, tupleValue)) in zip(tupleLiteral.labels, tupleLiteral.values).enumerated() {
                    guard let binding = tupleValue as? Binding else {
                        hasNonBindings = true
                        continue
                    }
                    hasBindings = true
                    let identifierPatterns = binding.identifierPatterns
                    let variableTypes = binding.variableTypes
                    updateVariables(for: identifierPatterns, types: variableTypes, member: label ?? KotlinTupleLiteral.member(index: index))
                }
                if hasBindings {
                    if expression.isNonNilMatch {
                        op = .with(symbol: "!=")
                        value = KotlinNullLiteral()
                    } else {
                        value = nil
                    }
                    if hasNonBindings {
                        messages.append(.kotlinWhenCasePartialBinding(tupleLiteral))
                    }
                } else {
                    value = translator.translateExpression(expression.value)
                }
            } else {
                value = translator.translateExpression(expression.value)
            }
        default:
            value = translator.translateExpression(expression.value)
        }

        guard let value else {
            return (targetVariable, bindingVariables, nil, messages)
        }
        let condition = KotlinBinaryOperator(op: op, lhs: targetVariable?.identifier ?? target, rhs: value, sourceFile: expression.sourceFile, sourceRange: expression.sourceRange)
        return (targetVariable, bindingVariables, condition, messages)
    }
}

class KotlinClosure: KotlinExpression {
    static let returnLabel = "llabel"

    var returnType: TypeSignature = .none
    var parameters: [Parameter<Void>] = []
    var implicitParameterLabels: [String] = []
    var isAnonymousFunction = false
    var body: KotlinCodeBlock
    var hasReturnLabel = false

    static func translate(expression: Closure, translator: KotlinTranslator) -> KotlinClosure {
        // If there is an explicit return type we'll use an anonymous function rather than a closure,
        // as Kotlin closures cannot declare a return type
        let kbody = KotlinCodeBlock.translate(statement: expression.body, translator: translator)
        let isAnonymousFunction = expression.returnType != .none
        var implicitParameterLabels: [String] = []
        var hasReturnLabel = false
        if isAnonymousFunction {
            if expression.returnType != .void {
                // A function that returns a value requires an explicit return
                kbody.updateWithExpectedReturn(.yes)
            }
        } else {
            // Closures require a label for any explicit return, or it will return from the other scope
            if kbody.updateWithExpectedReturn(.labelIfPresent(returnLabel)) {
                hasReturnLabel = true
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
        kexpression.hasReturnLabel = hasReturnLabel
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
            if hasReturnLabel {
                output.append(Self.returnLabel).append("@")
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

class KotlinDictionaryLiteral: KotlinExpression {
    var entries: [(key: KotlinExpression, value: KotlinExpression)] = []

    static func translate(expression: DictionaryLiteral, translator: KotlinTranslator) -> KotlinDictionaryLiteral {
        let kexpression = KotlinDictionaryLiteral(expression: expression)
        kexpression.entries = expression.entries.map {
            let keyExpression = translator.translateExpression($0.key)
            let valueExpression = translator.translateExpression($0.value)
            return (keyExpression, valueExpression)
        }
        return kexpression
    }

    private init(expression: DictionaryLiteral) {
        super.init(type: .dictionaryLiteral, expression: expression)
    }

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        // Dictionary literals are not shared, but if we're using this expression to determine the type, then it can be
        return orType
    }

    override var children: [KotlinSyntaxNode] {
        return entries.flatMap { [$0.key, $0.value] }
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append("dictionaryOf(")
        for (index, entry) in entries.enumerated() {
            // No need to sref() because the dictionary already does
            output.append("Pair(")
            output.append(entry.key, indentation: indentation)
            output.append(", ")
            output.append(entry.value, indentation: indentation)
            output.append(")")
            if index != entries.count - 1 {
                output.append(", ")
            }
        }
        output.append(")")
    }
}

class KotlinFunctionCall: KotlinExpression {
    var function: KotlinExpression
    var arguments: [LabeledValue<KotlinExpression>] = []
    var mayBeSharedMutableStructType = false
    var useTrailingClosureFormatting = true

    static func translate(expression: FunctionCall, translator: KotlinTranslator) -> KotlinFunctionCall {
        let kfunction = translator.translateExpression(expression.function)
        let kexpression = KotlinFunctionCall(expression: expression, function: kfunction)
        kexpression.arguments = expression.arguments.map {
            let kargumentExpression = translator.translateExpression($0.value).sref()
            return LabeledValue(label: $0.label, value: kargumentExpression)
        }
        kexpression.mayBeSharedMutableStructType = expression.inferredType.kotlinMayBeSharedMutableStruct(codebaseInfo: translator.codebaseInfo)
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

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        // The result of a function call is never a shared value because we always sref() on return
        return orType && mayBeSharedMutableStructType
    }

    override var children: [KotlinSyntaxNode] {
        return [function] + arguments.map { $0.value }
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        var arguments = arguments
        var trailingClosure: KotlinExpression? = nil
        var forceParentheses = false
        if let closure = function as? KotlinClosure, closure.hasReturnLabel {
            // Kotlin does not allow return labels in immediately-executed lambdas. Convert to a call to our special closure-running functions
            output.append("linvoke")
            trailingClosure = closure
        } else {
            if let arrayLiteral = function as? KotlinArrayLiteral, arrayLiteral.elements.count == 1 {
                // [Int]() syntax
                output.append("Array<").append(arrayLiteral.elements[0], indentation: indentation).append(">")
            } else if let dictionaryLiteral = function as? KotlinDictionaryLiteral, dictionaryLiteral.entries.count == 1 {
                // [Int: String]() syntax
                output.append("Dictionary<").append(dictionaryLiteral.entries[0].key, indentation: indentation).append(", ")
                output.append(dictionaryLiteral.entries[0].value, indentation: indentation).append(">")
            } else {
                output.append(function, indentation: indentation)
                // Kotlin does not support <closure>?(args); use <closure>?.invoke(args)
                if (function as? KotlinPostfixOperator)?.operatorSymbol == "?" {
                    output.append(".invoke")
                }
            }
            let hasTrailingClosure = useTrailingClosureFormatting && arguments.last?.value.type == .closure && (arguments.last?.value as? KotlinClosure)?.isAnonymousFunction == false
            if hasTrailingClosure {
                trailingClosure = arguments[arguments.count - 1].value
                arguments = Array(arguments[0..<(arguments.count - 1)])
            }
            // When immediately executing a closure we must add parentheses { ... }()
            if arguments.isEmpty && (!hasTrailingClosure || function is KotlinClosure) {
                forceParentheses = true
            }
        }
        if forceParentheses || !arguments.isEmpty {
            output.append("(")
        }
        for (index, argument) in arguments.enumerated() {
            if let label = argument.label {
                output.append(label).append(" = ")
            }
            output.append(argument.value, indentation: indentation)
            if index < arguments.count - 1 {
                output.append(", ")
            }
        }
        if forceParentheses || !arguments.isEmpty {
            output.append(")")
        }
        if let trailingClosure {
            output.append(" ").append(trailingClosure, indentation: indentation)
        }
    }
}

class KotlinIdentifier: KotlinExpression {
    var name: String
    var mayBeSharedMutableStruct = false
    var isLocalIdentifier = false
    var isInOut = false

    static func translate(expression: Identifier, translator: KotlinTranslator) -> KotlinIdentifier {
        let kexpression = KotlinIdentifier(expression: expression)
        kexpression.mayBeSharedMutableStruct = expression.inferredType.kotlinMayBeSharedMutableStruct(codebaseInfo: translator.codebaseInfo)
        kexpression.isLocalIdentifier = expression.isLocalIdentifier
        return kexpression
    }

    static func translateName(_ name: String) -> String {
        guard let implicitParameterIndex = name.implicitClosureParameterIndex else {
            return name
        }
        return implicitParameterIndex == 0 ? "it" : "it_\(implicitParameterIndex)"
    }

    init(name: String, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.name = name
        super.init(type: .identifier, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(expression: Identifier) {
        self.name = expression.name
        super.init(type: .identifier, expression: expression)
    }

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        return mayBeSharedMutableStruct
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if name == "self" {
            output.append("this")
        } else if name == "Self" {
            output.append("Companion")
        } else {
            output.append(Self.translateName(name))
            if isInOut {
                output.append(".value")
            }
        }
    }
}

/// - Seealso: ``KotlinIfPlugin``
class KotlinIf: KotlinExpression {
    var conditionSets: [ConditionSet]
    var isGuard = false
    var body: KotlinCodeBlock
    var elseBody: KotlinCodeBlock?
    var ifCheckVariable: String?

    struct ConditionSet {
        var optionalBindingVariable: KotlinBindingVariable?
        var caseTargetVariable: KotlinCaseTargetVariable?
        var caseBindingVariables: [KotlinBindingVariable]
        var conditions: [KotlinExpression]
    }

    static func translate(expression: If, translator: KotlinTranslator) -> KotlinIf {
        let kconditionSets = translate(conditions: expression.conditions, translator: translator)
        // If we have optional bindings and we have an else part, we'll need an if check variable to execute
        // the else part only if the '?.let' generated for the optional binding doesn't pass. Similarly, if
        // we have multiple condition sets representing nested conditions, we'll need an if check variable
        let ifCheckVariable = (kconditionSets.count > 1 || kconditionSets.contains(where: { $0.optionalBindingVariable != nil })) && expression.elseBody != nil ? "letexec" : nil
        let kbody = KotlinCodeBlock.translate(statement: expression.body, translator: translator)
        let kexpression = KotlinIf(expression: expression, conditionSets: kconditionSets, body: kbody)
        kexpression.ifCheckVariable = ifCheckVariable
        if let elseBody = expression.elseBody {
            kexpression.elseBody = KotlinCodeBlock.translate(statement: elseBody, translator: translator)
        }
        return kexpression
    }

    static func translate(statement: Guard, translator: KotlinTranslator) -> KotlinStatement {
        let kconditionSets = translate(conditions: statement.conditions, isGuard: true, translator: translator)
        let kbody = KotlinCodeBlock.translate(statement: statement.body, translator: translator)
        let kexpression = KotlinIf(conditionSets: kconditionSets, body: kbody, sourceFile: statement.sourceFile, sourceRange: statement.sourceRange)
        kexpression.isGuard = true

        let kstatement = KotlinExpressionStatement(type: .expression)
        kstatement.expression = kexpression
        return kstatement
    }

    private static func translate(conditions: [Expression], isGuard: Bool = false, translator: KotlinTranslator) -> [ConditionSet] {
        var conditionSets: [ConditionSet] = []
        var currentOptionalBindingVariable: KotlinBindingVariable? = nil
        var currentCaseTargetVariable: KotlinCaseTargetVariable? = nil
        var currentCaseBindingVariables: [KotlinBindingVariable] = []
        var currentConditions: [KotlinExpression] = []
        func appendCurrentConditionSet() {
            guard currentOptionalBindingVariable != nil || !currentConditions.isEmpty else {
                return
            }
            var conditions = currentConditions
            if isGuard {
                conditions = conditions.map { $0.logicalNegated() }
            }
            let conditionSet = ConditionSet(optionalBindingVariable: currentOptionalBindingVariable, caseTargetVariable: currentCaseTargetVariable, caseBindingVariables: currentCaseBindingVariables, conditions: conditions)
            currentOptionalBindingVariable = nil
            currentCaseTargetVariable = nil
            currentCaseBindingVariables = []
            currentConditions = []
            conditionSets.append(conditionSet)
        }

        for condition in conditions {
            if let optionalBinding = condition as? OptionalBinding {
                let (variable, optionalCondition) = KotlinOptionalBinding.translate(expression: optionalBinding, translator: translator)
                if let variable {
                    // Whenever we need an optional binding variable, create a new nested condition set for it
                    appendCurrentConditionSet()
                    currentOptionalBindingVariable = variable
                    if isGuard {
                        // for ifs our call to 'value?.let' filters nils; for guards we have to add nil checks
                        currentConditions.append(optionalCondition)
                    } else {
                        // for ifs our call to 'value?.let' can't include any other conditions
                        appendCurrentConditionSet()
                    }
                } else {
                    currentConditions.append(optionalCondition)
                }
            } else if let matchingCase = condition as? MatchingCase {
                let (targetVariable, bindingVariables, caseCondition) = KotlinMatchingCase.translate(expression: matchingCase, translator: translator)
                // Whenever we need a case value variable, create a new nested condition set for it.
                // Otherwise we'd have to evaluate the case value eagerly, and it should only evaluate after any
                // previous conditions have passed to match the behavior of the original code
                if targetVariable != nil {
                    appendCurrentConditionSet()
                }
                currentCaseTargetVariable = targetVariable
                currentCaseBindingVariables = bindingVariables
                currentConditions.append(caseCondition)
                if !bindingVariables.isEmpty {
                    // Whenever we need case variables, we can't include any other conditions until they're declared
                    appendCurrentConditionSet()
                }
            } else {
                currentConditions.append(translator.translateExpression(condition))
            }
        }
        appendCurrentConditionSet()
        return conditionSets
    }

    init(conditionSets: [ConditionSet], body: KotlinCodeBlock, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.conditionSets = conditionSets
        self.body = body
        super.init(type: .if, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(expression: Expression, conditionSets: [ConditionSet], body: KotlinCodeBlock) {
        self.conditionSets = conditionSets
        self.body = body
        super.init(type: .if, expression: expression)
    }

    override var children: [KotlinSyntaxNode] {
        var children = conditionSets.flatMap { conditionSet in
            var children: [KotlinSyntaxNode] = conditionSet.conditions
            if let optionalBindingValue = conditionSet.optionalBindingVariable?.value {
                children.append(optionalBindingValue)
            }
            if let caseTargetVariable = conditionSet.caseTargetVariable {
                children += [caseTargetVariable.identifier, caseTargetVariable.value]
            }
            children += conditionSet.caseBindingVariables.map(\.value)
            return children
        }
        children.append(body)
        if let elseBody {
            children.append(elseBody)
        }
        return children
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if isGuard {
            appendGuard(to: output, indentation: indentation)
        } else {
            appendIf(to: output, indentation: indentation)
        }
    }

    private func appendGuard(to output: OutputGenerator, indentation: Indentation) {
        for (index, conditionSet) in conditionSets.enumerated() {
            appendGuardConditionSet(conditionSet, to: output, indentation: indentation)
            output.append(body, indentation: indentation.inc())
            output.append(indentation).append("}")
            if !conditionSet.caseBindingVariables.isEmpty {
                output.append("\n")
                appendCaseBindingVariables(conditionSet.caseBindingVariables, to: output, indentation: indentation)
            }
            if index != conditionSets.count - 1 {
                output.append("\n").append(indentation)
            }
        }
    }

    private func appendIf(to output: OutputGenerator, indentation: Indentation) {
        // If check
        var hasOutput = false
        if let ifCheckVariable {
            output.append("var \(ifCheckVariable) = false\n")
            hasOutput = true
        }
        // Nested conditions and their opening braces
        var indentation = indentation
        for conditionSet in conditionSets {
            if (hasOutput) {
                output.append(indentation)
            }
            indentation = appendIfConditionSet(conditionSet, to: output, indentation: indentation)
            hasOutput = true
        }
        // Body
        if let ifCheckVariable {
            output.append(indentation).append(ifCheckVariable).append(" = true\n")
        }
        output.append(body, indentation: indentation)
        // Closing braces
        for i in 0..<conditionSets.count {
            indentation = indentation.dec()
            output.append(indentation).append("}")
            if i != conditionSets.count - 1 {
                output.append("\n")
            }
        }
        guard let elseBody else {
            return
        }

        if let ifCheckVariable {
            output.append("\n").append(indentation).append("if (!\(ifCheckVariable)) {\n")
            elseBody.append(to: output, indentation: indentation.inc())
            output.append(indentation).append("}")
        } else if let elseif {
            output.append(" else ")
            elseif.append(to: output, indentation: indentation)
        } else {
            output.append(" else {\n")
            elseBody.append(to: output, indentation: indentation.inc())
            output.append(indentation).append("}")
        }
    }

    private var elseif: KotlinIf? {
        guard let elseBody, elseBody.statements.count == 1, let expressionStatement = elseBody.statements.first as? KotlinExpressionStatement else {
            return nil
        }
        guard let kif = expressionStatement.expression as? KotlinIf else {
            return nil
        }
        // We can't chain an else with nested conditions or with an optional binding
        return (kif.conditionSets.count > 1 || kif.conditionSets.contains(where: { $0.optionalBindingVariable != nil })) ? nil : kif
    }

    private func appendIfConditionSet(_ conditionSet: ConditionSet, to output: OutputGenerator, indentation: Indentation) -> Indentation {
        var indentation = indentation
        if let caseTargetVariable = conditionSet.caseTargetVariable {
            caseTargetVariable.append(to: output, indentation: indentation)
            output.append("\n").append(indentation)
        }
        if let optionalBindingVariable = conditionSet.optionalBindingVariable {
            output.append(optionalBindingVariable.value, indentation: indentation).append("?.let { ")
            if optionalBindingVariable.names.count > 1 {
                output.append("(")
            }
            output.append(optionalBindingVariable.names.map { $0 ?? "_" }.joined(separator: ", "))
            if optionalBindingVariable.names.count > 1 {
                output.append(")")
            }
            output.append(" ->\n")
            indentation = indentation.inc()
            if !optionalBindingVariable.isLet {
                for case let name? in optionalBindingVariable.names {
                    output.append(indentation).append("var \(name) = \(name)\n")
                }
            }
            if !conditionSet.conditions.isEmpty {
                output.append(indentation)
            }
        }
        if !conditionSet.conditions.isEmpty {
            output.append("if (")
            conditionSet.conditions.appendAsLogicalConditions(to: output, op: .with(symbol: "&&"), indentation: indentation)
            output.append(") {\n")
            indentation = indentation.inc()
        }
        if !conditionSet.caseBindingVariables.isEmpty {
            appendCaseBindingVariables(conditionSet.caseBindingVariables, to: output, indentation: indentation)
            output.append("\n")
        }
        return indentation
    }

    private func appendGuardConditionSet(_ conditionSet: ConditionSet, to output: OutputGenerator, indentation: Indentation) {
        if let optionalBindingVariable = conditionSet.optionalBindingVariable {
            output.append(indentation)
            optionalBindingVariable.append(to: output, indentation: indentation)
            output.append("\n").append(indentation)
        }
        if let caseTargetVariable = conditionSet.caseTargetVariable {
            output.append(indentation)
            caseTargetVariable.append(to: output, indentation: indentation)
            output.append("\n").append(indentation)
        }
        output.append("if (")
        conditionSet.conditions.appendAsLogicalConditions(to: output, op: .with(symbol: "||"), indentation: indentation)
        output.append(") {\n")
    }

    private func appendCaseBindingVariables(_ caseBindingVariables: [KotlinBindingVariable], to output: OutputGenerator, indentation: Indentation) {
        for (index, variable) in caseBindingVariables.enumerated() {
            output.append(indentation)
            variable.append(to: output, indentation: indentation)
            if index != caseBindingVariables.count - 1 {
                output.append("\n")
            }
        }
    }
}

class KotlinInOut: KotlinExpression {
    var target: KotlinExpression

    static func translate(expression: InOut, translator: KotlinTranslator) -> KotlinInOut {
        let ktarget = translator.translateExpression(expression.target)
        return KotlinInOut(expression: expression, target: ktarget)
    }

    private init(expression: InOut, target: KotlinExpression) {
        self.target = target
        super.init(type: .inout, expression: expression)
    }

    override var children: [KotlinSyntaxNode] {
        return [target]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append("InOut({ ").append(target, indentation: indentation).append(" }, { ")
        output.append(target, indentation: indentation).append(" = it })")
    }
}

/// - Note: This type is used to translate the ``MatchingCase`` expression, but is not itself a `KotlinExpression`.
struct KotlinMatchingCase {
    static func translate(expression: MatchingCase, translator: KotlinTranslator) -> (targetVariable: KotlinCaseTargetVariable?, bindingVariables: [KotlinBindingVariable], condition: KotlinExpression) {
        let ktarget = translator.translateExpression(expression.target)
        let inferredType = expression.declaredType.or(expression.target.inferredType)
        let isSealedClassesEnum = inferredType.kotlinIsSealedClassesEnum(codebaseInfo: translator.codebaseInfo)
        let (targetVariable, bindingVariables, condition, messages) = KotlinCasePattern.translate(expression: expression.pattern, target: ktarget, isSealedClassesEnum: isSealedClassesEnum, translator: translator)
        let kcondition = condition ?? KotlinBooleanLiteral(literal: true)
        kcondition.messages += messages
        return (targetVariable, bindingVariables, kcondition)
    }
}

class KotlinMemberAccess: KotlinExpression {
    var base: KotlinExpression?
    var member: String
    var useMultlineFormatting = false
    var inferredType: TypeSignature = .none
    var mayBeSharedMutableStruct = false

    static func translate(expression: MemberAccess, translator: KotlinTranslator) -> KotlinMemberAccess {
        let kexpression = KotlinMemberAccess(expression: expression)
        if let base = expression.base {
            kexpression.base = translator.translateExpression(base)
            kexpression.useMultlineFormatting = expression.useMultlineFormatting
        } else if expression.inferredType == .none && translator.codebaseInfo != nil {
            kexpression.messages.append(.kotlinMemberAccessUnknownBaseType(expression, member: expression.member))
        }
        kexpression.inferredType = expression.inferredType
        kexpression.mayBeSharedMutableStruct = expression.inferredType.kotlinMayBeSharedMutableStruct(codebaseInfo: translator.codebaseInfo)
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

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        return mayBeSharedMutableStruct
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
                output.append(".")
                if let memberIndex = Int(member) {
                    output.append(KotlinTupleLiteral.member(index: memberIndex))
                } else {
                    output.append(member)
                }
            }
        } else if inferredType != .none {
            output.append(inferredType.kotlin)
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
    init(sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        super.init(type: .nullLiteral, sourceFile: sourceFile, sourceRange: sourceRange)
    }

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

    init(literal: String, isFloatingPoint: Bool = false, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.literal = literal
        self.isFloatingPoint = isFloatingPoint
        super.init(type: .numericLiteral, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    init(expression: NumericLiteral) {
        self.literal = expression.literal
        self.isFloatingPoint = expression.isFloatingPoint
        super.init(type: .numericLiteral, expression: expression)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(literal)
    }
}

/// - Note: This type is used to translate the ``OptionalBinding`` expression, but is not itself a `KotlinExpression`.
struct KotlinOptionalBinding {
    static func translate(expression: OptionalBinding, translator: KotlinTranslator) -> (bindingVariable: KotlinBindingVariable?, condition: KotlinExpression) {
        let comparisons: [KotlinExpression] = expression.names.compactMap {
            guard let name = $0 else {
                return nil
            }
            // x != null
            let identifier = KotlinIdentifier(name: name)
            identifier.isLocalIdentifier = true
            let nullLiteral = KotlinNullLiteral()
            return KotlinBinaryOperator(op: .with(symbol: "!="), lhs: identifier, rhs: nullLiteral, sourceFile: expression.sourceFile, sourceRange: expression.sourceRange)
        }
        let bindingVariable = translateVariable(expression: expression, translator: translator)
        return (bindingVariable, comparisons.asLogicalExpression())
    }

    /// If the given optional binding requires us to declare a new Kotlin variable, return it.
    private static func translateVariable(expression: OptionalBinding, translator: KotlinTranslator) -> KotlinBindingVariable? {
        guard requiresVariable(expression: expression) else {
            return nil
        }

        let kvalue: KotlinExpression
        if let value = expression.value {
            kvalue = translator.translateExpression(value).sref()
        } else if let name = expression.names[0] {
            let identifier = KotlinIdentifier(name: name)
            identifier.mayBeSharedMutableStruct = expression.variableTypes.first?.kotlinMayBeSharedMutableStruct(codebaseInfo: translator.codebaseInfo) ?? false
            identifier.isLocalIdentifier = true
            kvalue = identifier.sref()
        } else {
            return nil
        }
        return KotlinBindingVariable(names: expression.names, value: kvalue, isLet: expression.isLet)
    }

    private static func requiresVariable(expression: OptionalBinding) -> Bool {
        // We need a new var to make the reference mutable
        guard expression.isLet else {
            return true
        }
        // 'let x' doesn't need a new var
        guard let value = expression.value else {
            return false
        }
        // We need a new var if we're binding to anything other than 'let x = x'
        guard let identifier = value as? Identifier else {
            return true
        }
        return expression.names.count != 1 || identifier.name != expression.names[0]
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

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        return content.mayBeSharedMutableStructExpression(orType: orType)
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

class KotlinPostfixOperator: KotlinExpression {
    var operatorSymbol: String
    var target: KotlinExpression
    var targetType: TypeSignature = .none

    static func translate(expression: PostfixOperator, translator: KotlinTranslator) -> KotlinPostfixOperator {
        let ktarget = translator.translateExpression(expression.target)
        let kexpression = KotlinPostfixOperator(expression: expression, target: ktarget)
        kexpression.targetType = expression.target.inferredType
        return kexpression
    }

    private init(expression: PostfixOperator, target: KotlinExpression) {
        self.operatorSymbol = expression.operatorSymbol
        self.target = target
        super.init(type: .postfixOperator, expression: expression)
    }

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        return target.mayBeSharedMutableStructExpression(orType: orType)
    }

    override var children: [KotlinSyntaxNode] {
        return [target]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(target, indentation: indentation)
        switch operatorSymbol {
        case "!":
            output.append("!!")
        case "...":
            output.append(" .. ").append(targetType.kotlin).append(".max")
        default:
            output.append(operatorSymbol)
        }
    }
}

class KotlinPrefixOperator: KotlinExpression {
    var operatorSymbol: String
    var target: KotlinExpression
    var targetType: TypeSignature = .none

    static func translate(expression: PrefixOperator, translator: KotlinTranslator) -> KotlinPrefixOperator {
        let ktarget = translator.translateExpression(expression.target)
        let kexpression = KotlinPrefixOperator(expression: expression, target: ktarget)
        kexpression.targetType = expression.target.inferredType
        return kexpression
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

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        return target.mayBeSharedMutableStructExpression(orType: orType)
    }

    override var isCompoundExpression: Bool {
        return true
    }

    override var children: [KotlinSyntaxNode] {
        return [target]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        switch operatorSymbol {
        case "as", "is":
            // Kotlin will smart cast with 'is' test
            output.append("is ")
        case "in":
            // Used as unary prefix operators in when expressions
            output.append(operatorSymbol).append(" ")
        case "..<":
            output.append(targetType.kotlin).append(".min until ")
        case "...":
            output.append(targetType.kotlin).append(".min .. ")
        default:
            output.append(operatorSymbol)
        }
        output.append(target, indentation: indentation)
    }
}

class KotlinSRef: KotlinExpression {
    var base: KotlinExpression
    var onUpdate: String?

    init(base: KotlinExpression, onUpdate: String? = nil) {
        self.base = base
        self.onUpdate = onUpdate
        super.init(type: .sref)
    }

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        return orType
    }

    override func sref(onUpdate: String? = nil) -> KotlinExpression {
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
        output.append(".sref(")
        if let onUpdate {
            output.append(onUpdate)
        }
        output.append(")")
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

    init(literal: String, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        super.init(type: .stringLiteral, sourceFile: sourceFile, sourceRange: sourceRange)
        self.segments = [.string(literal)]
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
                //output.append(string.replacing("$", with: "\\$")) // macOS 13+
                output.append(string.split(separator: "$").joined(separator: "\\$"))
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
    var mayBeSharedMutableStruct = false

    static func translate(expression: Subscript, translator: KotlinTranslator) -> KotlinSubscript {
        let kbase = translator.translateExpression(expression.base)
        let kexpression = KotlinSubscript(expression: expression, base: kbase)
        kexpression.arguments = expression.arguments.map {
            let kargumentExpression = translator.translateExpression($0.value).sref()
            return LabeledValue(label: $0.label, value: kargumentExpression)
        }
        kexpression.mayBeSharedMutableStruct = expression.inferredType.kotlinMayBeSharedMutableStruct(codebaseInfo: translator.codebaseInfo)
        return kexpression
    }

    private init(expression: Subscript, base: KotlinExpression) {
        self.base = base
        super.init(type: .subscript, expression: expression)
    }

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        return mayBeSharedMutableStruct
    }

    override var children: [KotlinSyntaxNode] {
        return [base] + arguments.map { $0.value }
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(base, indentation: indentation)
        // Kotlin can't optional chain a subscript, i.e. a?[0]
        let isOptionalChain = (base as? KotlinPostfixOperator)?.operatorSymbol == "?"
        if isOptionalChain {
            output.append(".get(")
        } else {
            output.append("[")
        }
        for (index, argument) in arguments.enumerated() {
            if let label = argument.label {
                output.append(label).append(" = ")
            }
            output.append(argument.value, indentation: indentation)
            if index < arguments.count - 1 {
                output.append(", ")
            }
        }
        output.append(isOptionalChain ? ")" : "]")
    }
}

class KotlinTernaryOperator: KotlinExpression {
    var condition: KotlinExpression
    var ifTrue: KotlinExpression
    var ifFalse: KotlinExpression

    static func translate(expression: TernaryOperator, translator: KotlinTranslator) -> KotlinTernaryOperator {
        let condition = translator.translateExpression(expression.condition)
        let ifTrue = translator.translateExpression(expression.ifTrue)
        let ifFalse = translator.translateExpression(expression.ifFalse)
        return KotlinTernaryOperator(expression: expression, condition: condition, ifTrue: ifTrue, ifFalse: ifFalse)
    }

    private init(expression: TernaryOperator, condition: KotlinExpression, ifTrue: KotlinExpression, ifFalse: KotlinExpression) {
        self.condition = condition
        self.ifTrue = ifTrue
        self.ifFalse = ifFalse
        super.init(type: .ternaryOperator, expression: expression)
    }

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        return ifTrue.mayBeSharedMutableStructExpression(orType: orType) || ifFalse.mayBeSharedMutableStructExpression(orType: orType)
    }

    override var isCompoundExpression: Bool {
        return true
    }

    override var children: [KotlinSyntaxNode] {
        return [condition, ifTrue, ifFalse]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append("if (").append(condition, indentation: indentation).append(") ")
        output.append(ifTrue, indentation: indentation).append(" else ").append(ifFalse, indentation: indentation)
    }
}

class KotlinTry: KotlinExpression {
    var trying: KotlinExpression
    var isOptional = false

    static func translate(expression: Try, translator: KotlinTranslator) -> KotlinTry {
        let ktrying = translator.translateExpression(expression.trying)
        let kexpression = KotlinTry(expression: expression, trying: ktrying)
        kexpression.isOptional = expression.kind == .optional
        return kexpression
    }

    private init(expression: Try, trying: KotlinExpression) {
        self.trying = trying
        super.init(type: .try, expression: expression)
    }

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        return trying.mayBeSharedMutableStructExpression(orType: orType)
    }

    override var isCompoundExpression: Bool {
        return isOptional || trying.isCompoundExpression
    }

    override var children: [KotlinSyntaxNode] {
        return [trying]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if isOptional {
            output.append("try { ").append(trying, indentation: indentation).append(" } catch (_: Throwable) { null }")
        } else {
            output.append(trying, indentation: indentation)
        }
    }
}

class KotlinTupleLiteral: KotlinExpression {
    var values: [KotlinExpression]

    /// Return the member name for the given tuple index.
    static func member(index: Int) -> String {
        switch index {
        case 0:
            return "first"
        case 1:
            return "second"
        case 2:
            return "third"
        default:
            return String(describing: index)
        }
    }

    static func translate(expression: TupleLiteral, translator: KotlinTranslator) throws -> KotlinTupleLiteral {
        guard !expression.labels.contains(where: { $0 != nil }) else {
           throw Message.kotlinTupleLabels(expression)
        }
        guard expression.values.count <= 3 else {
            throw Message.kotlinTupleArity(expression)
        }
        let kvalues = expression.values.map { translator.translateExpression($0) }
        return KotlinTupleLiteral(expression: expression, values: kvalues)
    }

    init(values: [KotlinExpression], sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.values = values
        super.init(type: .tupleLiteral, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(expression: TupleLiteral, values: [KotlinExpression]) {
        self.values = values
        super.init(type: .tupleLiteral, expression: expression)
    }

    override func sref(onUpdate: String? = nil) -> KotlinExpression {
        let srefValues = values.map { $0.sref() }
        return KotlinTupleLiteral(values: srefValues, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    override var children: [KotlinSyntaxNode] {
        return values
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if values.isEmpty {
            output.append("Unit")
        } else {
            if values.count == 2 {
                output.append("Pair")
            } else {
                output.append("Triple")
            }
            output.append("(")
            for (index, value) in values.enumerated() {
                output.append(value, indentation: indentation)
                if index != values.count - 1 {
                    output.append(", ")
                }
            }
            output.append(")")
        }
    }
}

class KotlinTypeLiteral: KotlinExpression {
    var literal: TypeSignature

    init(expression: TypeLiteral) {
        self.literal = expression.literal
        super.init(type: .typeLiteral, expression: expression)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(literal.kotlin)
    }
}

class KotlinWhen: KotlinExpression {
    static let breakLabel = "wlabel"

    var on: KotlinExpression
    var cases: [KotlinCase]
    var caseTargetVariable: KotlinCaseTargetVariable?
    var hasNonNilMatches = false
    var hasBreakLabel = false

    static func translate(expression: Switch, translator: KotlinTranslator) -> KotlinWhen {
        var kon = translator.translateExpression(expression.on)
        let isSealedClassesEnum = expression.on.inferredType.kotlinIsSealedClassesEnum(codebaseInfo: translator.codebaseInfo)
        var caseTargetVariable: KotlinCaseTargetVariable? = nil
        let hasNonNilMatches = expression.cases.contains { $0.patterns.contains { $0.pattern.isNonNilMatch } }
        // When we have to compare the switch expression to nil we'll be executing it repeatedly, so store it in a var
        if hasNonNilMatches && (kon as? KotlinIdentifier)?.isLocalIdentifier != true {
            caseTargetVariable = KotlinCaseTargetVariable(value: kon)
        }

        var kcases: [KotlinCase] = []
        var messages: [Message] = []
        for switchCase in expression.cases {
            var (kcase, caseMessages) = KotlinCase.translate(expression: switchCase, matchingOn: kon, isSealedClassesEnum: isSealedClassesEnum, caseTargetVariable: &caseTargetVariable, translator: translator)
            kcase.patterns = kcase.patterns.map { pattern in
                // Change conditions of the form 'target == x' to just 'x', and the form 'target is/in/etc x' to just 'is/in/etc x'.
                // We only keep the binary expressions if we must compare != null, which can't be done in unary form
                guard !hasNonNilMatches, let binaryOperator = pattern as? KotlinBinaryOperator else {
                    return pattern
                }
                if binaryOperator.op.symbol == "==" {
                    return binaryOperator.rhs
                } else {
                    let prefixOperator = KotlinPrefixOperator(operatorSymbol: binaryOperator.op.symbol, target: binaryOperator.rhs)
                    prefixOperator.targetType = expression.on.inferredType
                    return prefixOperator
                }
            }
            kcases.append(kcase)
            messages += caseMessages
        }
        // If we've created a var to match against, change the switch to use the var
        if let caseTargetVariable {
            kon = caseTargetVariable.identifier
        }
        // Kotlin doesn't support break in when cases, so wrap the when in a closure and return to its label
        var hasBreakLabel = false
        for kcase in kcases {
            if kcase.body.updateWithExpectedReturn(.labelIfBreak(breakLabel)) {
                hasBreakLabel = true
            }
        }

        let kexpression = KotlinWhen(expression: expression, on: kon, cases: kcases)
        kexpression.caseTargetVariable = caseTargetVariable
        kexpression.hasNonNilMatches = hasNonNilMatches
        kexpression.hasBreakLabel = hasBreakLabel
        kexpression.messages = messages
        return kexpression
    }

    private init(expression: Switch, on: KotlinExpression, cases: [KotlinCase]) {
        self.on = on
        self.cases = cases
        super.init(type: .when, expression: expression)
    }

    override var children: [KotlinSyntaxNode] {
        return [on] + cases.flatMap { $0.children }
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if let caseTargetVariable {
            caseTargetVariable.append(to: output, indentation: indentation)
            output.append("\n").append(indentation)
        }
        var whenIndentation = indentation
        if hasBreakLabel {
            whenIndentation = whenIndentation.inc()
            output.append("linvoke ").append(Self.breakLabel).append("@{\n")
            output.append(whenIndentation)
        }
        output.append("when")
        if !hasNonNilMatches {
            output.append(" (").append(on, indentation: whenIndentation).append(")")
        }
        output.append(" {\n")
        let caseIndentation = whenIndentation.inc()
        cases.forEach { append($0, to: output, indentation: caseIndentation) }
        output.append(whenIndentation).append("}")
        if hasBreakLabel {
            output.append("\n").append(indentation).append("}")
        }
    }

    private func append(_ whenCase: KotlinCase, to output: OutputGenerator, indentation: Indentation) {
        output.append(indentation)
        if whenCase.patterns.isEmpty {
            output.append("else")
        } else {
            for (index, pattern) in whenCase.patterns.enumerated() {
                output.append(pattern, indentation: indentation)
                if index != whenCase.patterns.count - 1 {
                    output.append(", ")
                }
            }
        }
        output.append(" -> {\n")
        let bodyIndentation = indentation.inc()
        for caseBindingVariable in whenCase.caseBindingVariables {
            output.append(bodyIndentation)
            caseBindingVariable.append(to: output, indentation: bodyIndentation)
            output.append("\n")
        }
        output.append(whenCase.body, indentation: bodyIndentation)
        output.append(indentation).append("}\n")
    }
}
