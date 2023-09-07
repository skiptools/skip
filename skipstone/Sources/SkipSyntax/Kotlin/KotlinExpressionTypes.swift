/// Types of Kotlin expressions.
enum KotlinExpressionType {
    case arrayLiteral
    case await
    case binaryOperator
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
    var inferredType: TypeSignature = .none
    var isOptionSet = false
    var useMultilineFormatting = false

    static func translate(expression: ArrayLiteral, translator: KotlinTranslator) -> KotlinArrayLiteral {
        let kexpression = KotlinArrayLiteral(expression: expression)
        kexpression.elements = expression.elements.map { translator.translateExpression($0) }
        kexpression.inferredType = expression.inferredType.resolvingSelf(in: expression)
        if case .array(let element) = expression.inferredType {
            kexpression.isOptionSet = translator.codebaseInfo?.global.protocolSignatures(forNamed: element).contains(where: \.isOptionSet) == true
        }
        return kexpression
    }

    init(sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
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

    override func insertDependencies(into dependencies: inout KotlinDependencies) {
        if !isOptionSet {
            if case .set = inferredType {
                dependencies.insertSkipLibType(inferredType.name)
            } else if case .array = inferredType {
                dependencies.insertSkipLibType(inferredType.name)
            }
        }
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if isOptionSet {
            output.append("\(inferredType.elementType.kotlin).of(")
        } else if case .set = inferredType {
            output.append("setOf(")
        } else {
            output.append("arrayOf(")
        }
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

class KotlinAwait: KotlinExpression {
    var target: KotlinExpression

    static func translate(expression: Await, translator: KotlinTranslator) -> KotlinExpression {
        let ktarget = translator.translateExpression(expression.target)
        return KotlinAwait(target: ktarget, source: translator.syntaxTree.source)
    }

    convenience init(target: KotlinExpression, source: Source) {
        self.init(target: target)
        Self.setIsAsynchronous(target, source: source)
    }

    private init(target: KotlinExpression) {
        self.target = target
        super.init(type: .await, sourceFile: target.sourceFile, sourceRange: target.sourceRange)
    }

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        return target.mayBeSharedMutableStructExpression(orType: orType)
    }

    override var isCompoundExpression: Bool {
        return target.isCompoundExpression
    }

    override func logicalNegated() -> KotlinExpression {
        // Use private constructor that does not call setIsAsynchronous again on target
        return KotlinAwait(target: target.logicalNegated())
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append(target, indentation: indentation)
    }

    override var children: [KotlinSyntaxNode] {
        return [target]
    }

    /// Adjust the given Kotlin syntax for an asynchronous call.
    static func setIsAsynchronous(_ node: KotlinSyntaxNode, source: Source) {
        node.visit { node in
            if var mainActorTargeting = node as? (KotlinSyntaxNode & KotlinMainActorTargeting) {
                mainActorTargeting.isInAwait = true
                return node is KotlinClosure ? .skip : .recurse(nil)
            } else {
                return .recurse(nil)
            }
        }
    }
}

class KotlinBinaryOperator: KotlinExpression, KotlinSingleStatementVetoing {
    var op: Operator
    var lhs: KotlinExpression
    var rhs: KotlinExpression
    var mayBeSharedMutableStruct = false

    static func translate(expression: BinaryOperator, translator: KotlinTranslator) -> KotlinExpression {
        // Special case when assigning to _
        if expression.op.symbol == "=", let binding = expression.lhs as? Binding, binding.identifierPatterns.allSatisfy({ $0.name == nil }) {
            return translator.translateExpression(expression.rhs)
        }
        
        let klhs = translator.translateExpression(expression.lhs)
        var krhs = translator.translateExpression(expression.rhs)
        if expression.op.precedence == .assignment && assignmentRequiresSref(expression: expression) {
            krhs = krhs.sref()
        }

        let kexpression = KotlinBinaryOperator(expression: expression, lhs: klhs, rhs: krhs)
        kexpression.mayBeSharedMutableStruct = expression.inferredType.kotlinMayBeSharedMutableStruct(codebaseInfo: translator.codebaseInfo)

        switch expression.op.symbol {
        case "<<=", ">>=", "&=", "|=", "^=", "~=":
            kexpression.messages.append(.kotlinOperatorUnsupportedAssignment(kexpression, source: translator.syntaxTree.source))
        case ".==", ".!=", ".<", ".<=", ".>", ".>=", "&+", "&-", "&*":
            kexpression.messages.append(.kotlinOperatorUnsupported(kexpression, source: translator.syntaxTree.source))
        default:
            break
        }
        if expression.op.precedence == .cast, var castTarget = krhs as? KotlinCastTarget {
            // Kotlin type erases generics at runtime, so we typically can't use them in casts
            if let castGenerics = castTarget.generics, !castGenerics.isEmpty {
                if expression.op.symbol == "is" {
                    krhs.messages.append(.kotlinGenericCheck(krhs, source: translator.syntaxTree.source))
                } else if expression.op.symbol != "as!" {
                    krhs.messages.append(.kotlinGenericCast(krhs, source: translator.syntaxTree.source))
                }
            }
            castTarget.castTargetType = expression.op.symbol == "is" ? .typeErasedTarget : .target
        }
        return kexpression
    }

    private static func assignmentRequiresSref(expression: BinaryOperator) -> Bool {
        let identifier = expression.lhs as? Identifier
        let memberAccess = expression.lhs as? MemberAccess

        if expression.owningFunctionDeclaration?.type == .initDeclaration {
            // Within a constructor, look for assignments to an identifier or 'self.identifier'
            if (identifier != nil && identifier?.name != "self") || (memberAccess?.base as? Identifier)?.name == "self" {
                // If the assignment target is a 'let' member, sref() it
                if (expression.lhs as? APICallExpression)?.apiMatch?.apiFlags.contains(.writeable) != true {
                    return true
                }
            }
        }

        // Apart from constructor 'let' assignments above, we can assume that any member assignment does not
        // need an sref because the property will sref the value it gets. We have no direct detection of members
        // that are simple identifiers (e.g. 'x' rather than 'self.x'), but only members get the 'writeable' API
        // flag and we can only be assigning to something writeable, so it's a good proxy
        if memberAccess != nil {
            return false
        } else if identifier?.name == "self" || identifier?.apiMatch?.apiFlags.contains(.writeable) == true {
            return false
        } else {
            return true
        }
    }

    init(op: Operator, lhs: KotlinExpression, rhs: KotlinExpression, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
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

    func isSingleStatementAppendable(mode: KotlinSingleStatementAppendMode) -> Bool {
        return mode != .function || op.precedence != .assignment
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
        let kotlinSymbol = op.kotlinSymbol
        output.append(lhs, indentation: indentation)
        if kotlinSymbol == ".." {
            output.append(kotlinSymbol)
        } else {
            output.append(" \(kotlinSymbol) ")
        }
        output.append(rhs, indentation: indentation)
    }
}

class KotlinBooleanLiteral: KotlinExpression {
    var literal: Bool

    init(literal: Bool = false, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
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
    var caseBindingVariables: [KotlinBindingVariable] = []
    var body: KotlinCodeBlock

    static func translate(expression: SwitchCase, matchingOn: KotlinExpression, isSealedClassesEnum: Bool, caseTargetVariable: inout KotlinTargetVariable?, translator: KotlinTranslator) -> (KotlinCase, [Message]) {
        var messages: [Message] = []
        let caseValues: [(KotlinExpression?, [KotlinBindingVariable])] = expression.patterns.map { pattern in
            if let whereGuard = pattern.whereGuard {
                messages.append(.kotlinWhenCaseWhere(whereGuard, source: translator.syntaxTree.source))
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
    static func translate(expression: CasePattern, target: KotlinExpression, isSealedClassesEnum: Bool, translator: KotlinTranslator) -> (targetVariable: KotlinTargetVariable?, bindingVariables: [KotlinBindingVariable], condition: KotlinExpression?, messages: [Message]) {
        var targetVariable: KotlinTargetVariable? = nil
        var bindingVariables: [KotlinBindingVariable] = []
        var messages: [Message] = []
        func updateVariables(for identifierPatterns: [IdentifierPattern], types: [TypeSignature], member: String? = nil) {
            guard identifierPatterns.contains(where: { $0.name != nil }) else {
                return
            }
            // If we have bindings and our target is not a simple local identifier, create a new target variable so
            // that re-evaluating the target for our binding values won't cause side effects
            if targetVariable == nil, (target as? KotlinIdentifier)?.isLocalOrSelfIdentifier != true {
                targetVariable = KotlinTargetVariable(value: target)
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
        case .binaryOperator:
            // case let x as Type or case x in range
            let binaryOperator = expression.value as! BinaryOperator
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
        case .binding:
            // case let x
            let binding = expression.value as! Binding
            let identifierPatterns = binding.identifierPatterns
            let variableTypes = binding.variableTypes
            updateVariables(for: identifierPatterns, types: variableTypes)
            if expression.isNonNilMatch {
                op = .with(symbol: "!=")
                value = KotlinNullLiteral()
            } else {
                value = nil
            }
        case .functionCall:
            // case .enum(let value)
            let functionCall = expression.value as! FunctionCall
            if functionCall.function.type == .memberAccess {
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
                    if isSealedClassesEnum, let memberAccess = value as? KotlinMemberAccess {
                        // Change 'is .a' to 'is .acase' to match our sealed class names
                        memberAccess.member = KotlinEnumCaseDeclaration.sealedClassName(for: memberAccess.member)
                    }
                    if hasNonBindings {
                        messages.append(.kotlinWhenCasePartialBinding(functionCall, source: translator.syntaxTree.source))
                    }
                } else {
                    value = translator.translateExpression(expression.value)
                }
            } else {
                value = translator.translateExpression(expression.value)
            }
        case .memberAccess:
            value = translator.translateExpression(expression.value)
            if isSealedClassesEnum, let memberAccess = value as? KotlinMemberAccess {
                // Change 'is .a' to 'is .acase' to match our sealed class names
                memberAccess.member = KotlinEnumCaseDeclaration.sealedClassName(for: memberAccess.member)
            }
        case .postfixOperator:
            value = translator.translateExpression(expression.value)
            // case x...
            if (expression.value as! PostfixOperator).operatorSymbol == "..." {
                op = Operator.with(symbol: "in")
            }
        case .prefixOperator:
            let prefixOperator = expression.value as! PrefixOperator
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
        case .tupleLiteral:
            // case let (x, y)
            let tupleLiteral = expression.value as! TupleLiteral
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
                    messages.append(.kotlinWhenCasePartialBinding(tupleLiteral, source: translator.syntaxTree.source))
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

class KotlinClosure: KotlinExpression, KotlinMainActorTargeting {
    static let returnLabel = "l"

    var labeledCaptureList: [LabeledValue<KotlinExpression>] = []
    var returnType: TypeSignature = .none
    var parameters: [Parameter<Void>] = []
    var attributes = Attributes()
    var apiFlags: APIFlags? = []
    var inferredReturnType: TypeSignature = .none
    var implicitParameterLabels: [String] = []
    var isAnonymousFunction = false
    var body: KotlinCodeBlock
    var hasReturnLabel = false
    var isTaskClosure = false
    var useMultilineFormatting: Bool {
        guard labeledCaptureList.isEmpty else {
            return true
        }
        return !body.isSingleStatementAppendable(mode: isAnonymousFunction ? .function : .closure)
    }

    static func translate(expression: Closure, translator: KotlinTranslator) -> KotlinClosure {
        let labeledCaptureList = expression.captureList.compactMap { (capture: (CaptureType, LabeledValue<Expression>)) -> LabeledValue<KotlinExpression>? in
            guard let label = capture.1.label else {
                return nil
            }
            return LabeledValue(label: label, value: translator.translateExpression(capture.1.value))
        }
        // If there is an explicit return type we'll use an anonymous function rather than a closure, as Kotlin
        // closures cannot declare a return type. Kotlin does not support anonymous suspend functions, though
        let kbody = KotlinCodeBlock.translate(statement: expression.body, translator: translator)
        let isAnonymousFunction = expression.returnType != .none && !expression.apiFlags.contains(.async) && !expression.apiFlags.contains(.mainActor)
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
        // Inferred type parameters include explicit parameter info already, so use them for inout info
        let inferredParameters = expression.inferredType.parameters
        for (index, parameter) in inferredParameters.enumerated() {
            guard parameter.isInOut else {
                continue
            }
            let name = index < implicitParameterLabels.count ? "$\(index)" : parameter.label ?? "$\(index)"
            kbody.updateWithInOutParameter(name: name, source: translator.syntaxTree.source)
        }
        handleSelfAssignments(in: kbody, source: translator.syntaxTree.source)

        let kexpression = KotlinClosure(expression: expression, body: kbody)
        kexpression.labeledCaptureList = labeledCaptureList
        kexpression.returnType = expression.returnType.resolvingSelf(in: expression)
        kexpression.returnType.appendKotlinMessages(to: kexpression, source: translator.syntaxTree.source)
        kexpression.parameters = expression.parameters.map { $0.resolvingSelf(in: expression) }
        kexpression.parameters.forEach { $0.appendKotlinMessages(to: kexpression, source: translator.syntaxTree.source) }
        kexpression.attributes = expression.attributes
        // Combine inferred flags because most closures aren't declared with explicit info
        kexpression.apiFlags = expression.apiFlags.union(expression.inferredType.apiFlags)
        kexpression.isAnonymousFunction = isAnonymousFunction
        kexpression.inferredReturnType = expression.returnType != .none ? expression.returnType.resolvingSelf(in: expression) : expression.inferredType.returnType.resolvingSelf(in: expression)
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
        highestParameter = max(highestParameter, inferredType.parameters.count - 1)

        // $0 can use the special 'it' built-in, so no need to return it
        guard highestParameter >= 0 else {
            return []
        }
        return (0...highestParameter).map { KotlinIdentifier.translateName("$\($0)") }
    }

    private static func handleSelfAssignments(in codeBlock: KotlinCodeBlock, source: Source) {
        codeBlock.visit { node in
            if let binaryOperator = node as? KotlinBinaryOperator, binaryOperator.op.symbol == "=", let lhs = binaryOperator.lhs as? KotlinIdentifier, lhs.name == "self" {
                node.messages.append(.kotlinClosureSelfAssignment(node, source: source))
                return .skip
            } else if let kif = node as? KotlinIf, kif.conditionSets.contains(where: { $0.optionalBindingVariable?.names == ["self"] }) {
                node.messages.append(.kotlinClosureSelfAssignment(node, source: source))
                return .skip
            } else {
                // Let nested closures handle themselves
                return node is KotlinClosure ? .skip : .recurse(nil)
            }
        }
    }

    init(body: KotlinCodeBlock, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.body = body
        super.init(type: .closure, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(expression: Expression, body: KotlinCodeBlock) {
        self.body = body
        super.init(type: .closure, expression: expression)
    }

    var isInAwait = false
    var isInMainActorContext = false

    func mainActorMode(for child: KotlinSyntaxNode) -> KotlinMainActorMode {
        return .isolated
    }

    override var children: [KotlinSyntaxNode] {
        return labeledCaptureList.map(\.value) + [body]
    }

    override func insertDependencies(into dependencies: inout KotlinDependencies) {
        returnType.insertDependencies(into: &dependencies)
        parameters.forEach { $0.insertDependencies(into: &dependencies) }
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if isAnonymousFunction {
            appendAnonymousFunction(to: output, indentation: indentation)
        } else {
            appendClosure(to: output, indentation: indentation)
        }
    }

    private func appendAnonymousFunction(to output: OutputGenerator, indentation: Indentation) {
        output.append("fun(")
        for (index, parameter) in parameters.enumerated() {
            output.append(parameter.internalLabel).append(": ").append(parameter.declaredType.kotlin)
            if index < parameters.count - 1 {
                output.append(", ")
            }
        }
        output.append("): ").append(returnType.kotlin)
        if !useMultilineFormatting {
            output.append(" = ")
            body.appendAsSingleStatement(to: output, indentation: indentation, mode: .function)
        } else {
            output.append(" {\n")
            let bodyIndentation = indentation.inc()
            appendCaptureList(to: output, indentation: bodyIndentation)
            output.append(body, indentation: bodyIndentation)
            output.append(indentation).append("}")
        }
    }

    private func appendClosure(to output: OutputGenerator, indentation: Indentation) {
        // Tasks establish the correct async context on launch, so no need to output as async if we're a task closure.
        // Otherwise, output with the correct context if we're async or if we need to jump to the main actor
        let isAsync = !isTaskClosure && (apiFlags?.contains(.async) == true || mainActorMode.output != .none)
        let isMainActor = isAsync && apiFlags?.contains(.mainActor) == true
        let returnLabel = hasReturnLabel ? "\(Self.returnLabel)@" : ""
        if !isAsync {
            output.append(returnLabel)
        }
        output.append("{")
        let isSingleStatement = !useMultilineFormatting
        if parameters.isEmpty && implicitParameterLabels.isEmpty {
            if isMainActor {
                output.append(" MainActor.run \(returnLabel){")
            } else if isAsync {
                output.append(" Async.run \(returnLabel){")
            }
            output.append(isSingleStatement ? " " : "\n")
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
            output.append(" ->")
            if isMainActor {
                output.append(" MainActor.run \(returnLabel){")
            } else if isAsync {
                output.append(" Async.run \(returnLabel){")
            }
            output.append(isSingleStatement ? " " : "\n")
        }
        appendCaptureList(to: output, indentation: indentation.inc())
        if isSingleStatement {
            body.appendAsSingleStatement(to: output, indentation: indentation, mode: .closure)
            output.append(" }")
        } else {
            output.append(body, indentation: indentation.inc())
            output.append(indentation).append("}")
        }
        if isAsync {
            output.append(" }")
        }
    }

    private func appendCaptureList(to output: OutputGenerator, indentation: Indentation) {
        for capture in labeledCaptureList {
            guard let label = capture.label else {
                continue
            }
            output.append(indentation).append("val \(label) = ")
            output.append(capture.value, indentation: indentation).append("\n")
        }
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
            output.append("Tuple2(")
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

class KotlinFunctionCall: KotlinExpression, KotlinMainActorTargeting, APICallExpression {
    var function: KotlinExpression
    var arguments: [LabeledValue<KotlinExpression>] = []
    var isOptionalInit = false
    var inferredType: TypeSignature = .none
    var apiMatch: APIMatch?
    var mayBeSharedMutableStructType = false
    var hasTrailingClosures = false {
        didSet {
            if !hasTrailingClosures && oldValue == true, !arguments.isEmpty && arguments.last?.label == nil, let apiMatch {
                // Attempt to fill in the trailing closure argument label
                let parameters = apiMatch.signature.parameters
                if parameters.count == arguments.count {
                    arguments[arguments.count - 1].label = parameters.last?.label
                }
            }
        }
    }

    static func translate(expression: FunctionCall, translator: KotlinTranslator) -> KotlinExpression {
        let karguments = expression.arguments.map {
            let kargumentExpression = translator.translateExpression($0.value)
            return LabeledValue(label: $0.label, value: kargumentExpression)
        }
        if let numberLiteral = numberConstructorToLiteral(expression: expression, arguments: karguments) {
            return numberLiteral
        }

        let kfunction = translator.translateExpression(expression.function)
        let kexpression = KotlinFunctionCall(expression: expression, function: kfunction)
        kexpression.arguments = karguments
        kexpression.hasTrailingClosures = expression.hasTrailingClosures
        kexpression.isOptionalInit = expression.isInit && expression.inferredType.isOptional
        kexpression.inferredType = expression.inferredType.resolvingSelf(in: expression)
        kexpression.apiMatch = expression.apiMatch
        kexpression.mayBeSharedMutableStructType = expression.inferredType.kotlinMayBeSharedMutableStruct(codebaseInfo: translator.codebaseInfo)
        // If we resolved our function to a type but this function call is not a type constructor, it must be a free function with a
        // type or typealias's name. Turn off typealias mapping so that we use the function name as-is
        if !expression.isInit {
            (kfunction as? KotlinIdentifier)?.isTypealiasFor = .none
            (kfunction as? KotlinMemberAccess)?.isTypealiasFor = .none
        }
        // Give Optional function names the 'optional' prefix to avoid conflicts with other API, e.g. T?.optionalmap(...)
        if expression.isCallOnOptional, let memberAccess = kexpression.function as? KotlinMemberAccess, !memberAccess.member.hasPrefix("optional") {
            memberAccess.member = "optional" + memberAccess.member
        }
        return kexpression
    }

    private static func numberConstructorToLiteral(expression: FunctionCall, arguments: [LabeledValue<KotlinExpression>]) -> KotlinExpression? {
        guard arguments.count == 1, arguments[0].label == nil, let numberLiteral = arguments[0].value as? KotlinNumericLiteral else {
            return nil
        }
        // Kotlin supports suffixes to create literals of certain numeric types, which are more efficient than function calls:
        // f, L, U, UL
        if isFunction(expression: expression, named: "Float", moduleName: "Swift") {
            numberLiteral.suffix = "f"
            return numberLiteral
        }
        guard !numberLiteral.isFloatingPoint else {
            return nil
        }

        if isFunction(expression: expression, named: "Long", moduleName: "Swift") {
            numberLiteral.suffix = "L"
            return numberLiteral
        } else if isFunction(expression: expression, named: "UInt", moduleName: "Swift") {
            numberLiteral.suffix = "U"
            return numberLiteral
        } else if isFunction(expression: expression, named: "UInt64", moduleName: "Swift") {
            numberLiteral.suffix = "UL"
            return numberLiteral
        } else {
            return nil
        }
    }

    private static func isFunction(expression: FunctionCall, named: String, moduleName: String) -> Bool {
        if let identifier = expression.function as? Identifier {
            return identifier.name == named
        }
        if let memberAccess = expression.function as? MemberAccess {
            guard memberAccess.member == named else {
                return false
            }
            if let baseIdentifier = memberAccess.base as? Identifier {
                return baseIdentifier.name == moduleName
            }
        }
        return false
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

    var isInAwait = false
    var isInMainActorContext = false
    var apiFlags: APIFlags? {
        return apiMatch?.apiFlags
    }

    func mainActorMode(for child: KotlinSyntaxNode) -> KotlinMainActorMode {
        return child === function ? .isolatedFunctionReference : .isolated
    }

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        // The result of a function call is never a shared value because we always sref() on return
        return orType && mayBeSharedMutableStructType
    }

    override var optionalChain: KotlinOptionalChain {
        return function.optionalChain == .none ? .none : .implicit
    }

    override var children: [KotlinSyntaxNode] {
        return [function] + arguments.map { $0.value }
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        var arguments = arguments
        var argumentIndentation = indentation
        var trailingClosure: KotlinExpression? = nil
        var forceParentheses = false
        var isReduceFunction = false
        if isOptionalInit {
            output.append("(try { ")
        }
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
                if (function as? KotlinMemberAccess)?.incrementsIndentation == true {
                    argumentIndentation = argumentIndentation.inc()
                }
                // Kotlin does not support <closure>?(args); use <closure>?.invoke(args)
                if function.optionalChain == .explicit {
                    output.append(".invoke")
                } else if function.optionalChain == .implicit, let declarationType = (function as? APICallExpression)?.apiMatch?.declarationType, declarationType != .functionDeclaration {
                    output.append("?.invoke")
                }
                if let identifier = function as? KotlinIdentifier {
                    isReduceFunction = identifier.name == "reduce"
                } else if let memberAccess = function as? KotlinMemberAccess {
                    isReduceFunction = memberAccess.member == "reduce"
                }
            }
            let useTrailingClosure = hasTrailingClosures && arguments.last?.value.type == .closure && arguments.last?.label == nil && (arguments.last?.value as? KotlinClosure)?.isAnonymousFunction == false
            if useTrailingClosure {
                trailingClosure = arguments[arguments.count - 1].value
                arguments = Array(arguments[0..<(arguments.count - 1)])
            }
            // When immediately executing a closure we must add parentheses { ... }()
            if arguments.isEmpty && (!useTrailingClosure || function is KotlinClosure) {
                forceParentheses = true
            }
        }
        if forceParentheses || !arguments.isEmpty {
            output.append("(")
        }
        let parameters: [TypeSignature.Parameter]?
        if let apiMatch, apiMatch.signature.parameters.count == arguments.count {
            parameters = apiMatch.signature.parameters
        } else {
            parameters = nil
        }
        for (index, argument) in arguments.enumerated() {
            if let label = argument.label {
                // Kotlin does not label variadic lists
                if parameters?[index].isVariadic != true && parameters?[index].isVariadicContinuation != true {
                    output.append(label).append(" = ")
                }
            } else if isReduceFunction, index == 0, self.arguments.count == 2 {
                // The Kotlin compiler can't differentiate calls to the two reduce() versions without labels.
                // reduce(into:...) is always labeled, so insert a label for reduce(_ initialResult:...)
                output.append("initialResult = ")
            }
            // Handle binary operators used in place of closures
            if let identifier = argument.value as? KotlinIdentifier, identifier.isOperatorIdentifier {
                output.append("{ it, it_1 -> it \(identifier.name) it_1 }")
            } else {
                output.append(argument.value, indentation: argumentIndentation)
            }
            if index < arguments.count - 1 {
                output.append(", ")
            }
        }
        if forceParentheses || !arguments.isEmpty {
            output.append(")")
        }
        if let trailingClosure {
            output.append(" ").append(trailingClosure, indentation: argumentIndentation)
        }
        if mainActorMode.output != .none {
            // Cooperate with our function child, which will output the beginning part of the closure to execute this
            // on the main actor. We just output the closing brace
            output.append(" }")
        }
        if isOptionalInit {
            output.append(" } catch (_: NullReturnException) { null })")
        }
    }
}

class KotlinIdentifier: KotlinExpression, KotlinMainActorTargeting, KotlinCastTarget, KotlinSwiftUIBindable, APICallExpression {
    var name: String
    var apiMatch: APIMatch?
    var mayBeSharedMutableStruct = false
    var isLocalOrSelfIdentifier = false
    var isOperatorIdentifier = false
    var valueSuffix: String? // Suffix to append to extract value, e.g. '.value()'
    var isFunctionReference = false
    var isModuleNameFor: TypeSignature = .none
    var isTypealiasFor: TypeSignature = .none

    static func translate(expression: Identifier, translator: KotlinTranslator) -> KotlinIdentifier {
        let kexpression = KotlinIdentifier(expression: expression)
        kexpression.generics = expression.generics?.map { $0.resolvingSelf(in: expression) }
        kexpression.apiMatch = expression.apiMatch
        kexpression.isOperatorIdentifier = !Operator.with(symbol: expression.name).isUnknown
        kexpression.mayBeSharedMutableStruct = !kexpression.isOperatorIdentifier && expression.inferredType.kotlinMayBeSharedMutableStruct(codebaseInfo: translator.codebaseInfo)
        kexpression.isLocalOrSelfIdentifier = expression.isLocalOrSelfIdentifier
        kexpression.isModuleNameFor = expression.isModuleNameFor.resolvingSelf(in: expression)
        if case .function = expression.inferredType {
            kexpression.isFunctionReference = !expression.isLocalOrSelfIdentifier && !expression.isCalledAsFunction && translator.codebaseInfo?.isFunctionName(expression.name, in: expression.owningTypeDeclaration?.signature) == true
        } else if expression.inferredType.isMetaType && expression.apiMatch?.declarationType == .typealiasDeclaration {
            kexpression.isTypealiasFor = expression.inferredType.resolvingSelf(in: expression).asMetaType(false)
        }
        return kexpression
    }

    static func translateName(_ name: String) -> String {
        guard let implicitParameterIndex = name.implicitClosureParameterIndex else {
            return name
        }
        return implicitParameterIndex == 0 ? "it" : "it_\(implicitParameterIndex)"
    }

    init(name: String, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.name = name
        super.init(type: .identifier, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(expression: Identifier) {
        self.name = expression.name
        super.init(type: .identifier, expression: expression)
    }

    var isInAwait = false
    var isInMainActorContext = false
    var apiFlags: APIFlags? {
        return apiMatch?.apiFlags
    }

    func mainActorMode(for child: KotlinSyntaxNode) -> KotlinMainActorMode {
        return .isolated
    }

    var isSwiftUIBinding: Bool {
        return name.hasPrefix("$") && Int(name.dropFirst()) == nil
    }

    func appendSwiftUIBindingPath(to output: OutputGenerator, indentation: Indentation, appendPath: @escaping (OutputGenerator, Indentation, KotlinBindableBase) -> Void) {
        appendInstanceBinding(to: output, indentation: indentation, appendPath: appendPath) {
            appendIdentifier(to: output, indentation: indentation)
        }
    }

    var generics: [TypeSignature]?
    var castTargetType: KotlinCastTargetType = .none

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        return mayBeSharedMutableStruct
    }

    override func insertDependencies(into dependencies: inout KotlinDependencies) {
        generics?.forEach { $0.insertDependencies(into: &dependencies) }
        if TypeSignature.kotlinSkipLibImports.contains(name) {
            dependencies.insertSkipLibType(name)
        }
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if isSwiftUIBinding {
            appendBinding(to: output, indentation: indentation)
        } else {
            appendIdentifier(to: output, indentation: indentation)
        }
    }

    private func appendIdentifier(to output: OutputGenerator, indentation: Indentation) {
        var name = name
        if isSwiftUIBinding {
            name = String(name.dropFirst())
        }

        let mainActorOutputMode = mainActorMode.output
        if mainActorOutputMode != .none {
            output.append("MainActor.run { ")
        }
        if name == "self" {
            output.append("this")
        } else if name == "Self" {
            output.append("Companion")
        } else if isModuleNameFor != .none {
            if isModuleNameFor.kotlinIsNative() {
                output.append("kotlin") // Kotlin package
            } else {
                output.append(KotlinTranslator.packageName(forModule: name))
            }
        } else {
            if isFunctionReference {
                // To refer to a function rather than call it, Kotlin uses ::
                output.append("::")
            }
            var generics = self.generics
            if castTargetType != .none {
                if let specifiedGenerics = generics, !specifiedGenerics.isEmpty {
                    if castTargetType == .typeErasedTarget {
                        generics = specifiedGenerics.map { _ in TypeSignature.named("*", []) }
                    }
                } else if let apiMatch, !apiMatch.signature.generics.isEmpty {
                    generics = Array(repeating: TypeSignature.named("*", []), count: apiMatch.signature.generics.count)
                }
            }
            if isTypealiasFor != .none {
                var type = isTypealiasFor
                if let generics, !generics.isEmpty {
                    type = type.withGenerics(generics)
                }
                output.append(type.kotlin)
            } else {
                let builtinType = TypeSignature.for(name: name, genericTypes: generics ?? [], allowNamed: false)
                if builtinType != .none {
                    output.append(builtinType.kotlin)
                } else {
                    output.append(Self.translateName(name))
                    if let generics, !generics.isEmpty {
                        output.append("<\(generics.map(\.kotlin).joined(separator: ", "))>")
                    }
                    if let apiMatch, apiMatch.declarationType == .variableDeclaration, apiMatch.apiFlags.contains(.viewBuilder) || apiMatch.apiFlags.contains(.async) {
                        // View builder and async properties are converted to Kotlin functions
                        output.append("()")
                    }
                    if let valueSuffix {
                        output.append(valueSuffix)
                    }
                }
            }
        }
        if mainActorOutputMode == .isolated {
            output.append(" }")
        }
    }

    private func appendBinding(to output: OutputGenerator, indentation: Indentation) {
        output.append("Binding({ ")
        appendIdentifier(to: output, indentation: indentation)
        output.append(" }, { it -> ")
        appendIdentifier(to: output, indentation: indentation)
        output.append(" = it })")
    }
}

/// - Seealso: ``KotlinIfTransformer``
class KotlinIf: KotlinExpression {
    var conditionSets: [ConditionSet]
    var isGuard = false
    var body: KotlinCodeBlock
    var elseBody: KotlinCodeBlock?
    var requiresNestingClosure = false

    struct ConditionSet {
        var optionalBindingVariable: KotlinBindingVariable?
        var caseTargetVariable: KotlinTargetVariable?
        var caseBindingVariables: [KotlinBindingVariable]
        var conditions: [KotlinExpression]
        var targetVariable: KotlinTargetVariable?
        var isConditionBeforeBinding: Bool
    }

    static func translate(expression: If, translator: KotlinTranslator) -> KotlinIf {
        let kconditionSets = translate(conditions: expression.conditions, hasElse: expression.elseBody != nil, translator: translator)
        let kbody = KotlinCodeBlock.translate(statement: expression.body, translator: translator)
        let kexpression = KotlinIf(expression: expression, conditionSets: kconditionSets, body: kbody)
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
        return KotlinExpressionStatement(expression: kexpression)
    }

    static func translateAsLoopGuard(statement: WhileLoop, translator: KotlinTranslator) -> KotlinStatement {
        let kconditionSets = translate(conditions: statement.conditions, isGuard: true, translator: translator)
        let kbody = KotlinCodeBlock(statements: [KotlinBreak()])
        let kexpression = KotlinIf(conditionSets: kconditionSets, body: kbody)
        kexpression.isGuard = true
        return KotlinExpressionStatement(expression: kexpression)
    }

    private static func translate(conditions: [Expression], isGuard: Bool = false, hasElse: Bool = false, translator: KotlinTranslator) -> [ConditionSet] {
        var conditionSets: [ConditionSet] = []
        var currentOptionalBindingVariable: KotlinBindingVariable? = nil
        var currentCaseTargetVariable: KotlinTargetVariable? = nil
        var currentCaseBindingVariables: [KotlinBindingVariable] = []
        var currentConditions: [KotlinExpression] = []
        var currentTargetVariable: KotlinTargetVariable? = nil
        var currentIsConditionBeforeBinding = false
        func appendCurrentConditionSet() {
            guard currentOptionalBindingVariable != nil || !currentConditions.isEmpty else {
                return
            }
            var conditions = currentConditions
            if isGuard {
                conditions = conditions.map { $0.logicalNegated() }
            }
            let conditionSet = ConditionSet(optionalBindingVariable: currentOptionalBindingVariable, caseTargetVariable: currentCaseTargetVariable, caseBindingVariables: currentCaseBindingVariables, conditions: conditions, targetVariable: currentTargetVariable, isConditionBeforeBinding: currentIsConditionBeforeBinding)
            currentOptionalBindingVariable = nil
            currentCaseTargetVariable = nil
            currentCaseBindingVariables = []
            currentConditions = []
            currentTargetVariable = nil
            currentIsConditionBeforeBinding = false
            conditionSets.append(conditionSet)
        }

        for condition in conditions {
            if let optionalBinding = condition as? OptionalBinding {
                let kbinding = KotlinOptionalBinding.translate(expression: optionalBinding, isGuard: isGuard, hasElse: hasElse, translator: translator)
                if let variable = kbinding.bindingVariable {
                    // Whenever we need an optional binding variable, create a new nested condition set for it. Note that this
                    // will also catch uses of target variables, as they only exist in pairs with an optional binding
                    appendCurrentConditionSet()
                    currentOptionalBindingVariable = variable
                    currentTargetVariable = kbinding.targetVariable
                    currentIsConditionBeforeBinding = kbinding.isConditionBeforeBinding
                    if isGuard || hasElse {
                        // For ifs without elses our call to 'value?.let' filters nils; otherwise we have to add nil checks
                        currentConditions.append(kbinding.condition)
                        // If the conditions have to come before the binding, we can't include any other conditions that might use previous bindings
                        if kbinding.isConditionBeforeBinding {
                            appendCurrentConditionSet()
                        }
                    } else {
                        // for ifs our call to 'value?.let' can't include any other conditions
                        appendCurrentConditionSet()
                    }
                } else {
                    currentConditions.append(kbinding.condition)
                }
            } else if let matchingCase = condition as? MatchingCase {
                let kcase = KotlinMatchingCase.translate(expression: matchingCase, translator: translator)
                // Whenever we need a case value variable, create a new nested condition set for it.
                // Otherwise we'd have to evaluate the case value eagerly, and it should only evaluate after any
                // previous conditions have passed to match the behavior of the original code
                if kcase.targetVariable != nil {
                    appendCurrentConditionSet()
                }
                currentCaseTargetVariable = kcase.targetVariable
                currentCaseBindingVariables = kcase.bindingVariables
                currentConditions.append(kcase.condition)
                if !kcase.bindingVariables.isEmpty {
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

    init(conditionSets: [ConditionSet], body: KotlinCodeBlock, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
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
            if let targetVariable = conditionSet.targetVariable {
                children += [targetVariable.identifier, targetVariable.value]
            }
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
            if conditionSet.isConditionBeforeBinding, let optionalBindingVariable = conditionSet.optionalBindingVariable {
                output.append("\n")
                optionalBindingVariable.append(to: output, indentation: indentation)
            }
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
        var indentation = indentation
        if requiresNestingClosure {
            indentation = indentation.inc()
            output.append("linvoke \(KotlinClosure.returnLabel)@{\n").append(indentation)
        }

        // Nested conditions and their opening braces
        var hasOutput = false
        for conditionSet in conditionSets {
            if (hasOutput) {
                output.append(indentation)
            }
            indentation = appendIfConditionSet(conditionSet, to: output, indentation: indentation)
            hasOutput = true
        }
        // Body
        output.append(body, indentation: indentation)
        // Closing braces and else code. We repeat the else code for every nested if. Another option would be to create a flag that
        // gets set when all conditions are met and place the else within a flag check, but that does not allow the Kotlin compiler
        // to guarantee that both if and else branches are executed, which is required when e.g. initializing a var to different values
        for i in 0..<conditionSets.count {
            indentation = indentation.dec()
            output.append(indentation).append("}")
            appendIfElse(to: output, indentation: indentation)
            if i != conditionSets.count - 1 {
                output.append("\n")
            }
        }

        if (requiresNestingClosure) {
            output.append("\n").append(indentation.dec()).append("}")
        }
    }

    private func appendIfElse(to output: OutputGenerator, indentation: Indentation) {
        if let elseif {
            output.append(" else ")
            output.append(elseif, indentation: indentation)
        } else if let elseBody {
            output.append(" else {\n")
            output.append(elseBody, indentation: indentation.inc())
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
        if let targetVariable = conditionSet.targetVariable {
            targetVariable.append(to: output, indentation: indentation)
            output.append("\n").append(indentation)
        }
        if let caseTargetVariable = conditionSet.caseTargetVariable {
            caseTargetVariable.append(to: output, indentation: indentation)
            output.append("\n").append(indentation)
        }
        if conditionSet.isConditionBeforeBinding {
            indentation = appendIfConditions(in: conditionSet, to: output, indentation: indentation)
        }
        if let optionalBindingVariable = conditionSet.optionalBindingVariable {
            if conditionSet.isConditionBeforeBinding {
                output.append(indentation)
                optionalBindingVariable.append(to: output, indentation: indentation)
                output.append("\n")
            } else {
                if optionalBindingVariable.value.isCompoundExpression {
                    output.append("(")
                }
                output.append(optionalBindingVariable.value, indentation: indentation)
                if optionalBindingVariable.value.isCompoundExpression {
                    output.append(")")
                }
                output.append("?.let { ")
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
        }
        if !conditionSet.isConditionBeforeBinding {
            indentation = appendIfConditions(in: conditionSet, to: output, indentation: indentation)
        }
        if !conditionSet.caseBindingVariables.isEmpty {
            appendCaseBindingVariables(conditionSet.caseBindingVariables, to: output, indentation: indentation)
            output.append("\n")
        }
        return indentation
    }

    private func appendIfConditions(in conditionSet: ConditionSet, to output: OutputGenerator, indentation: Indentation) -> Indentation {
        var indentation = indentation
        if !conditionSet.conditions.isEmpty {
            output.append("if (")
            conditionSet.conditions.appendAsLogicalConditions(to: output, op: .with(symbol: "&&"), indentation: indentation)
            output.append(") {\n")
            indentation = indentation.inc()
        }
        return indentation
    }

    private func appendGuardConditionSet(_ conditionSet: ConditionSet, to output: OutputGenerator, indentation: Indentation) {
        if let targetVariable = conditionSet.targetVariable {
            targetVariable.append(to: output, indentation: indentation)
            output.append("\n").append(indentation)
        } else if !conditionSet.isConditionBeforeBinding, let optionalBindingVariable = conditionSet.optionalBindingVariable {
            optionalBindingVariable.append(to: output, indentation: indentation)
            output.append("\n").append(indentation)
        }
        if let caseTargetVariable = conditionSet.caseTargetVariable {
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
        if let identifier = target as? KotlinIdentifier, identifier.name == "self" {
            output.append("})")
        } else {
            output.append(target, indentation: indentation).append(" = it })")
        }
    }
}

class KotlinKeyPathLiteral: KotlinExpression {
    var components: [KeyPathLiteral.Component] = []
    var isWrite = false
    var keyPathType: TypeSignature = .none

    static func translate(expression: KeyPathLiteral, translator: KotlinTranslator) -> KotlinKeyPathLiteral {
        let kexpression = KotlinKeyPathLiteral(expression: expression)
        kexpression.components = expression.components
        kexpression.keyPathType = expression.inferredType
        return kexpression
    }

    init(sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        super.init(type: .keyPathLiteral, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(expression: KeyPathLiteral) {
        super.init(type: .keyPathLiteral, expression: expression)
    }

    /// The key path code, traversing from the given root.
    func pathString(root: String) -> String {
        var path = root
        for component in components {
            switch component {
            case .property(let name):
                if let tupleIndex = Int(name) {
                    path.append(".")
                    path.append(KotlinTupleLiteral.member(index: tupleIndex))
                } else if name != "self" {
                    path.append(".")
                    path.append(name)
                }
            case .optional:
                path.append("?")
            case .unwrappedOptional:
                path.append("!!")
            }
        }
        return path
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        output.append("{ ")
        if isWrite {
            output.append("it, it_1 -> ")
        }
        output.append(pathString(root: "it"))
        if isWrite {
            output.append(" = it_1")
        }
        output.append(" }")
    }
}

/// - Note: This type is used to translate the ``MatchingCase`` expression, but is not itself a `KotlinExpression`.
struct KotlinMatchingCase {
    var targetVariable: KotlinTargetVariable?
    var bindingVariables: [KotlinBindingVariable]
    var condition: KotlinExpression

    static func translate(expression: MatchingCase, translator: KotlinTranslator) -> KotlinMatchingCase {
        let ktarget = translator.translateExpression(expression.target)
        let inferredType = expression.declaredType.or(expression.target.inferredType)
        let isSealedClassesEnum = inferredType.kotlinIsSealedClassesEnum(codebaseInfo: translator.codebaseInfo)
        let (targetVariable, bindingVariables, condition, messages) = KotlinCasePattern.translate(expression: expression.pattern, target: ktarget, isSealedClassesEnum: isSealedClassesEnum, translator: translator)
        let kcondition = condition ?? KotlinBooleanLiteral(literal: true)
        kcondition.messages += messages
        return KotlinMatchingCase(targetVariable: targetVariable, bindingVariables: bindingVariables, condition: kcondition)
    }
}

class KotlinMemberAccess: KotlinExpression, KotlinMainActorTargeting, KotlinSwiftUIBindable, KotlinCastTarget, KotlinSingleStatementVetoing, APICallExpression {
    var base: KotlinExpression?
    var baseKClass: TypeSignature?
    var member: String
    var apiMatch: APIMatch?
    var useMultilineFormatting = false
    var baseType: TypeSignature = .none
    var mayBeSharedMutableStruct = false
    var isFunctionReference = false
    var isStaticReferenceOrTypeName = false
    var isTypealiasFor: TypeSignature = .none
    var incrementsIndentation: Bool {
        guard useMultilineFormatting else {
            return false
        }
        // Be consistent when chaining
        if let baseMemberAccess = base as? KotlinMemberAccess, baseMemberAccess.useMultilineFormatting {
            return baseMemberAccess.incrementsIndentation
        }
        if let baseFunctionCall = base as? KotlinFunctionCall {
            if let functionMemberAccess = baseFunctionCall.function as? KotlinMemberAccess, functionMemberAccess.useMultilineFormatting {
                return functionMemberAccess.incrementsIndentation
            }
            // Don't indent following a mutliline closure, as in:
            // Base {
            //    closure
            // }
            // .member
            if let closure = baseFunctionCall.arguments.last?.value as? KotlinClosure, closure.useMultilineFormatting {
                return false
            }
        }
        return true
    }

    static func translate(expression: MemberAccess, translator: KotlinTranslator) -> KotlinMemberAccess {
        let kexpression = KotlinMemberAccess(expression: expression)
        if let base = expression.base {
            let kbase = translator.translateExpression(base)
            kexpression.base = kbase
            kexpression.useMultilineFormatting = expression.useMultilineFormatting
            if let functionCall = kbase as? KotlinFunctionCall, functionCall.optionalChain == .implicit {
                // f({ ... })?.member is cleaner and simpler for us than (f() { ... })?.member
                functionCall.hasTrailingClosures = false
            }
            kexpression.baseKClass = kclass(for: base, accessingMember: expression.member, codebaseInfo: translator.codebaseInfo)
            if case .function = expression.inferredType {
                kexpression.isFunctionReference = !expression.isCalledAsFunction && translator.codebaseInfo?.isFunctionName(expression.member, in: base.inferredType) == true
            } else if expression.inferredType.isMetaType, expression.apiMatch?.declarationType == .typealiasDeclaration {
                kexpression.isTypealiasFor = expression.inferredType.asMetaType(false)
            }
        } else if expression.baseType == .none && translator.codebaseInfo != nil {
            kexpression.messages.append(.kotlinMemberAccessUnknownBaseType(expression, source: translator.syntaxTree.source, member: expression.member))
        } else if expression.inferredType.isOptional, expression.member == "none" || expression.member == "some" {
            kexpression.messages.append(.kotlinOptionalNoneSome(expression, source: translator.syntaxTree.source))
        }
        kexpression.generics = expression.generics?.map { $0.resolvingSelf(in: expression) }
        kexpression.apiMatch = expression.apiMatch
        kexpression.baseType = expression.baseType.resolvingSelf(in: expression).asMetaType(false)
        if case .tuple = expression.baseType {
            // Tuples sref() their members on the way out and do not set an onUpdate block, so no need to sref() again
            kexpression.mayBeSharedMutableStruct = false
        } else {
            kexpression.mayBeSharedMutableStruct = expression.inferredType.kotlinMayBeSharedMutableStruct(codebaseInfo: translator.codebaseInfo)
            if case .module(_, .none) = expression.baseType {
                kexpression.isStaticReferenceOrTypeName = true
            } else {
                kexpression.isStaticReferenceOrTypeName = expression.baseType.isMetaType
            }
        }

        // Kotlin member access never includes generics on the owning type unless we're referencing the class or a function
        if !kexpression.isFunctionReference && kexpression.member != "self" {
            kexpression.baseType = kexpression.baseType.withGenerics([])
            if let baseIdentifier = kexpression.base as? KotlinIdentifier {
                baseIdentifier.generics = []
            }
        }
        return kexpression
    }

    /// Return the `KClass` instance the given expression evaluates to, if any.
    private static func kclass(for expression: Expression, accessingMember: String, codebaseInfo: CodebaseInfo.Context?) -> TypeSignature? {
        // Must evaluate to X.Type
        guard expression.inferredType.isMetaType else {
            return nil
        }
        // We won't be accessing any Companion API on Any
        let type = expression.inferredType.asMetaType(false)
        guard type != .any else {
            return nil
        }
        // Type.self is allowed
        guard accessingMember != "self" else {
            return nil
        }
        // A type literal is not the same as KClass<Type>
        if expression is TypeLiteral {
            return nil
        }
        // Type declaration?
        if let declarationType = (expression as? APICallExpression)?.apiMatch?.declarationType {
            switch declarationType {
            case .actorDeclaration, .classDeclaration, .enumDeclaration, .protocolDeclaration, .structDeclaration, .typealiasDeclaration:
                return nil
            default:
                break
            }
        }
        // Is this a nested or module-qualified class type name?
        if let memberAccess = expression as? MemberAccess {
            let typeName = type.memberType.withModuleName(nil).name
            if memberAccess.member == typeName {
                return nil
            }
        }
        // Now that we've ruled out a type literal, any other non-Identifier must be represented by a KClass
        guard let identifier = expression as? Identifier else {
            return type.resolvingSelf(in: expression)
        }
        guard identifier.name != "Self" && identifier.name != "self" else {
            return nil
        }
        // For an Identifier, check if it's a type
        guard identifier.generics?.isEmpty != false else {
            return nil
        }
        // Nested type that is not fully qualified?
        if type.baseType != .none, type.memberType.name == identifier.name {
            return nil
        }
        // Builtin type?
        guard TypeSignature.for(name: identifier.name, genericTypes: [], allowNamed: false) == .none else {
            return nil
        }

        guard let codebaseInfo else {
            return nil
        }
        return codebaseInfo.declarationType(forNamed: .named(identifier.name, [])) == nil ? type.resolvingSelf(in: expression) : nil
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

    var isBaseSelfOrSuper: Bool {
        guard let identifier = base as? KotlinIdentifier else {
            return false
        }
        return identifier.name == "self" || identifier.name == "super"
    }

    var isBaseIncludedInMainActor: Bool {
        return isStaticReferenceOrTypeName || isBaseSelfOrSuper || base == nil
    }

    var isInAwait = false
    var isInMainActorContext = false
    var apiFlags: APIFlags? {
        return apiMatch?.apiFlags
    }

    func mainActorMode(for child: KotlinSyntaxNode) -> KotlinMainActorMode {
        return isBaseIncludedInMainActor ? .isolated : .none
    }

    var isSwiftUIBinding: Bool {
        return member.hasPrefix("$") || (base as? KotlinSwiftUIBindable)?.isSwiftUIBinding == true
    }

    func appendSwiftUIBindingPath(to output: OutputGenerator, indentation: Indentation, appendPath: @escaping (OutputGenerator, Indentation, KotlinBindableBase) -> Void) {
        if member.hasPrefix("$") {
            // Capture this member access as the base of an InstanceBinding
            appendInstanceBinding(to: output, indentation: indentation, appendPath: appendPath) {
                appendMemberAccess(to: output, indentation: indentation) { output, indentation in
                    if let base {
                        output.append(base, indentation: indentation)
                    }
                }
            }
        } else {
            // Tack this member access onto our base's existing InstanceBinding
            (base as? KotlinSwiftUIBindable)?.appendSwiftUIBindingPath(to: output, indentation: indentation) { output, indentation, appendTo in
                appendPath(output, indentation) { output, indentation in
                    self.appendMemberAccess(to: output, indentation: indentation, appendBase: appendTo)
                }
            }
        }
    }

    func isSingleStatementAppendable(mode: KotlinSingleStatementAppendMode) -> Bool {
        return !useMultilineFormatting
    }

    var generics: [TypeSignature]?
    var castTargetType: KotlinCastTargetType = .none

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        // Though we sref() when returning writable property values, any returned mutable struct may have its onUpdate block
        // set, and we need to sref() again on assignment to get an unowned copy
        return mayBeSharedMutableStruct
    }

    override var optionalChain: KotlinOptionalChain {
        guard let base else {
            return .none
        }
        return base.optionalChain == .none ? .none : .implicit
    }

    override func insertDependencies(into dependencies: inout KotlinDependencies) {
        generics?.forEach { $0.insertDependencies(into: &dependencies) }
        if baseKClass != nil {
            dependencies.insertReflectFull()
        }
    }

    override var children: [KotlinSyntaxNode] {
        return base == nil ? [] : [base!]
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if member.hasPrefix("$") {
            // Append an instance Binding where the base is our base and the path is our member
            appendInstanceBinding(to: output, indentation: indentation, appendPath: appendMemberAccess) {
                if let base {
                    output.append(base, indentation: indentation)
                }
            }
        } else if let bindable = base as? KotlinSwiftUIBindable, bindable.isSwiftUIBinding {
            // Add our member to the base binding path
            bindable.appendSwiftUIBindingPath(to: output, indentation: indentation, appendPath: appendMemberAccess)
        } else {
            appendMemberAccess(to: output, indentation: indentation) { output, indentation in
                if let base {
                    output.append(base, indentation: indentation)
                }
            }
        }
    }

    private func appendMemberAccess(to output: OutputGenerator, indentation: Indentation, appendBase: (OutputGenerator, Indentation) -> Void) {
        var member = member
        if member.hasPrefix("$") {
            member = String(member.dropFirst())
        }

        let mainActorOutputMode = mainActorMode.output
        if mainActorOutputMode != .none && isBaseIncludedInMainActor {
            // MainActor.run { self... or Type.... }
            output.append("MainActor.run { ")
        }
        if isTypealiasFor != .none {
            output.append(isTypealiasFor.kotlin)
        } else if let base {
            if baseKClass != nil {
                output.append("(")
            }
            appendBase(output, indentation)
            if base.optionalChain == .implicit {
                output.append("?")
            }
            if let baseKClass {
                output.append(".companionObjectInstance as \(baseKClass).Companion)")
                if base.optionalChain == .implicit {
                    output.append("?")
                }
            }
            if member == "self" {
                // Must be Type.self
                output.append("::class")
            } else if member != "init" {
                if isFunctionReference {
                    // To refer to a function rather than call it, Kotlin uses ::
                    output.append("::")
                } else {
                    if useMultilineFormatting {
                        output.append("\n").append(incrementsIndentation ? indentation.inc() : indentation)
                    }
                    if let baseIdentifier = base as? KotlinIdentifier,
                       TypeSignature.kotlinInnerExtensions.keys.contains(baseIdentifier.name + "." + member) {
                        output.append("") // e.g. String.Encoding to StringEncoding
                    } else {
                        output.append(".")
                        if mainActorOutputMode != .none && !isBaseIncludedInMainActor {
                            // base.mainactor { it.member...
                            output.append("mainactor { it.")
                        }
                    }
                }
                if let memberIndex = Int(member) {
                    output.append(KotlinTupleLiteral.member(index: memberIndex))
                } else {
                    output.append(member)
                }
            }
        } else if baseType != .none {
            output.append(baseType.kotlin)
            if member != "init" {
                if useMultilineFormatting {
                    output.append("\n").append(incrementsIndentation ? indentation.inc() : indentation)
                }
                output.append(".").append(member)
            }
        } else {
            output.append(member)
        }
        if var generics, !generics.isEmpty {
            if castTargetType == .typeErasedTarget {
                generics = generics.map { _ in TypeSignature.named("*", []) }
            }
            output.append("<\(generics.map(\.kotlin).joined(separator: ", "))>")
        } else if castTargetType != .none, let apiMatch, !apiMatch.signature.generics.isEmpty {
            output.append("<\(Array(repeating: "*", count: apiMatch.signature.generics.count).joined(separator: ", "))>")
        }
        if let apiMatch, apiMatch.declarationType == .variableDeclaration, apiMatch.apiFlags.contains(.viewBuilder) || apiMatch.apiFlags.contains(.async) {
            // View builder and async properties are converted to Kotlin functions
            output.append("()")
        }
        if mainActorOutputMode == .isolated {
            // If this isn't a function reference that will be invoked with () or [], end the main actor closure
            output.append(" }")
        }
    }
}

class KotlinNullLiteral: KotlinExpression {
    init(sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
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
    var suffix: String = ""

    init(literal: String, isFloatingPoint: Bool = false, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
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
        if literal.hasPrefix("0o") {
            // Swift supports octal literals but Kotlin doesn't; convert and output the decimal version
            if let decimal = Int(literal.dropFirst(2), radix: 8) {
                output.append(decimal)
            } else {
                output.append(literal) // Bad octal? Try to output the literal anyway and let Kotlin complain
            }
        } else {
            output.append(literal)
        }
        output.append(suffix)
    }
}

/// - Note: This type is used to translate the ``OptionalBinding`` expression, but is not itself a `KotlinExpression`.
struct KotlinOptionalBinding {
    var bindingVariable: KotlinBindingVariable?
    var condition: KotlinExpression
    var targetVariable: KotlinTargetVariable?
    var isConditionBeforeBinding = false

    static func translate(expression: OptionalBinding, isGuard: Bool = false, hasElse: Bool = false, translator: KotlinTranslator) -> KotlinOptionalBinding {
        var bindingValue: KotlinExpression? = nil
        let nullLiteral = KotlinNullLiteral()
        let condition: KotlinExpression
        var targetVariable: KotlinTargetVariable? = nil
        var isConditionBeforeBinding = false
        // For an 'if' without 'else' we can use x?.let { y -> ... } to bind if 'x' is stable. Else we need to check our conditions first
        if (!isGuard && hasElse) || (isGuard && expression.names.count > 1), expression.value != nil || (!isGuard && expression.nameShadowsUnstableValue) {
            let kvalue: KotlinExpression
            let canBindValue: Bool
            if let value = expression.value {
                kvalue = translator.translateExpression(value)
                // If the value is a local identifier, we can compare it directly. Otherwise we need to assign the value to a target variable
                // in order to avoid executing it more than once. This also handles checking a tuple itself against nil before destructuring it
                canBindValue = (kvalue as? KotlinIdentifier)?.isLocalOrSelfIdentifier == true
            } else { // nameShadowsUnstableValue
                kvalue = KotlinIdentifier(name: expression.names[0] ?? "_")
                // We need to assign the value to target variable to stabilize it
                canBindValue = false
            }

            if canBindValue {
                bindingValue = kvalue
            } else {
                targetVariable = KotlinTargetVariable(value: kvalue)
                bindingValue = targetVariable!.identifier
            }
            condition = KotlinBinaryOperator(op: .with(symbol: "!="), lhs: bindingValue!, rhs: nullLiteral, sourceFile: expression.sourceFile, sourceRange: expression.sourceRange)
            isConditionBeforeBinding = true
        } else {
            let comparisons: [KotlinExpression] = expression.names.compactMap {
                guard let name = $0 else {
                    return nil
                }
                // x != null
                let identifier = KotlinIdentifier(name: name)
                identifier.isLocalOrSelfIdentifier = true
                let nullLiteral = KotlinNullLiteral()
                return KotlinBinaryOperator(op: .with(symbol: "!="), lhs: identifier, rhs: nullLiteral, sourceFile: expression.sourceFile, sourceRange: expression.sourceRange)
            }
            condition = comparisons.asLogicalExpression()
            if let value = expression.value {
                bindingValue = translator.translateExpression(value)
            }
            isConditionBeforeBinding = !isGuard && hasElse
        }
        let bindingVariable = translateBindingVariable(expression: expression, value: bindingValue, codebaseInfo: translator.codebaseInfo)
        return KotlinOptionalBinding(bindingVariable: bindingVariable, condition: condition, targetVariable: targetVariable, isConditionBeforeBinding: isConditionBeforeBinding)
    }

    /// If the given optional binding requires us to declare a new Kotlin variable, return it.
    private static func translateBindingVariable(expression: OptionalBinding, value: KotlinExpression?, codebaseInfo: CodebaseInfo.Context?) -> KotlinBindingVariable? {
        guard requiresBindingVariable(expression: expression, value: value) else {
            return nil
        }

        let kvalue: KotlinExpression
        if let value {
            kvalue = value.sref()
        } else if let name = expression.names[0] {
            let identifier = KotlinIdentifier(name: name)
            identifier.mayBeSharedMutableStruct = expression.variableTypes.first?.kotlinMayBeSharedMutableStruct(codebaseInfo: codebaseInfo) == true
            identifier.isLocalOrSelfIdentifier = true
            kvalue = identifier.sref()
        } else {
            return nil
        }
        return KotlinBindingVariable(names: expression.names, value: kvalue, isLet: expression.isLet)
    }

    private static func requiresBindingVariable(expression: OptionalBinding, value: KotlinExpression?) -> Bool {
        // We need a new var to make the reference mutable
        guard expression.isLet else {
            return true
        }
        // 'let x' doesn't need a new var unless 'x' is unstable
        guard let value else {
            return expression.nameShadowsUnstableValue
        }
        // We need a new var if we're binding to anything other than 'let x = x'
        guard let identifier = value as? KotlinIdentifier else {
            return true
        }
        // 'let x = x' doesn't need a new var unless 'x' is unstable
        return expression.names.count != 1 || identifier.name != expression.names[0] || expression.nameShadowsUnstableValue
    }
}

class KotlinParenthesized: KotlinExpression {
    var content: KotlinExpression

    static func translate(expression: Parenthesized, translator: KotlinTranslator) -> KotlinParenthesized {
        let kcontent = translator.translateExpression(expression.content)
        return KotlinParenthesized(expression: expression, content: kcontent)
    }

    init(content: KotlinExpression, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
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
    var operatorSymbol: String // May be set to empty by transformers
    var target: KotlinExpression
    var targetType: TypeSignature = .none

    static func translate(expression: PostfixOperator, translator: KotlinTranslator) -> KotlinPostfixOperator {
        let ktarget = translator.translateExpression(expression.target)
        let kexpression = KotlinPostfixOperator(expression: expression, target: ktarget)
        kexpression.targetType = expression.target.inferredType
        if expression.operatorSymbol == "!" && ktarget.optionalChain != .none {
            kexpression.messages.append(.kotlinOptionalChainUnwrap(kexpression, source: translator.syntaxTree.source))
        }
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

    override var isCompoundExpression: Bool {
        return operatorSymbol == "..."
    }

    override var optionalChain: KotlinOptionalChain {
        switch operatorSymbol {
        case "?":
            return .explicit
        case "!":
            return .none
        default:
            return target.optionalChain
        }
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
            output.append("..").append(targetType.kotlin).append(".max")
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

    init(operatorSymbol: String, target: KotlinExpression, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
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
            output.append(target, indentation: indentation)
        case "in":
            // Used as unary prefix operators in when expressions
            output.append(operatorSymbol).append(" ")
            output.append(target, indentation: indentation)
        case "..<":
            output.append(targetType.kotlin).append(".min until ")
            output.append(target, indentation: indentation)
        case "...":
            output.append(targetType.kotlin).append(".min..")
            output.append(target, indentation: indentation)
        case "~":
            if target.isCompoundExpression {
                output.append("(")
            }
            output.append(target, indentation: indentation)
            if target.isCompoundExpression {
                output.append(")")
            }
            output.append(".inv()")
        default:
            output.append(operatorSymbol)
            output.append(target, indentation: indentation)
        }
    }
}

class KotlinSRef: KotlinExpression {
    var base: KotlinExpression
    var onUpdate: (() -> String)?

    init(base: KotlinExpression, onUpdate: (() -> String)? = nil) {
        self.base = base
        self.onUpdate = onUpdate
        super.init(type: .sref)
    }

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        return orType
    }

    override var optionalChain: KotlinOptionalChain {
        return base.optionalChain == .none ? .none : .implicit
    }

    override func sref(onUpdate: (() -> String)? = nil) -> KotlinExpression {
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
            output.append(onUpdate())
        }
        output.append(")")
    }
}

class KotlinStringLiteral: KotlinExpression {
    var segments: [StringLiteralSegment<KotlinExpression>] = []
    var isMultiline = false
    var isCharacter = false

    static func translate(expression: StringLiteral, translator: KotlinTranslator) -> KotlinStringLiteral {
        let kexpression = KotlinStringLiteral(expression: expression)
        var segments: [StringLiteralSegment<KotlinExpression>] = []
        for segment in expression.segments {
            switch segment {
            case .string(let string):
                let kstring = translateStringSegment(string)
                segments.append(.string(kstring))
            case .expression(let expression):
                let kexpression = translator.translateExpression(expression)
                segments.append(.expression(kexpression))
            }
        }
        kexpression.segments = segments
        kexpression.isMultiline = expression.isMultiline
        kexpression.isCharacter = expression.inferredType == .character
        return kexpression
    }

    private static func translateStringSegment(_ string: String) -> String {
        var kstring = ""
        var backslashCount = 0
        var skipNextClosingBraceCount = 0
        var index = string.startIndex
        while index != string.endIndex {
            let c = string[index]
            switch c {
            case "f":
                // Kotlin doesn't have \f
                if backslashCount % 2 == 1 {
                    kstring.append("u000C") // Leading backslash already appended
                } else {
                    kstring.append(c)
                }
            case "u":
                // Swift uses \u{####} for Unicode while Kotlin uses \u####
                if backslashCount % 2 == 1 {
                    let nextIndex = string.index(after: index)
                    if nextIndex != string.endIndex && string[nextIndex] == "{" {
                        index = nextIndex // Will skip opening brace
                        skipNextClosingBraceCount += 1
                    }
                }
                kstring.append(c)
            case "$":
                kstring.append("\\")
                kstring.append("$")
            case "}":
                if skipNextClosingBraceCount > 0 {
                    skipNextClosingBraceCount -= 1
                } else {
                    kstring.append(c)
                }
            default:
                kstring.append(c)
            }
            if c == "\\" {
                backslashCount += 1
            } else {
                backslashCount = 0
            }
            index = string.index(after: index)
        }
        return kstring
    }

    init(literal: String, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
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
        let delimiter = isCharacter ? "'" : isMultiline ? "\"\"\"" : "\""
        output.append(delimiter)
        for segment in segments {
            switch segment {
            case .string(let string):
                output.append(string)
            case .expression(let expression):
                output.append("${").append(expression, indentation: indentation).append("}")
            }
        }
        output.append(delimiter)
    }
}

class KotlinSubscript: KotlinExpression, KotlinMainActorTargeting, KotlinSwiftUIBindable, APICallExpression {
    var base: KotlinExpression
    var arguments: [LabeledValue<KotlinExpression>] = []
    var apiMatch: APIMatch?
    var mayBeSharedMutableStruct = false
    var isDictionarySubscript = false // Special case support for dict[key, default: @autoclosure]

    static func translate(expression: Subscript, translator: KotlinTranslator) -> KotlinSubscript {
        let kbase = translator.translateExpression(expression.base)
        let kexpression = KotlinSubscript(expression: expression, base: kbase)
        kexpression.arguments = expression.arguments.map {
            let kargumentExpression = translator.translateExpression($0.value)
            return LabeledValue(label: $0.label, value: kargumentExpression)
        }
        kexpression.apiMatch = expression.apiMatch
        if expression.arguments.count == 1, case .range(let elementType) =  expression.arguments[0].value.inferredType, elementType.isNumeric {
            // Special case: we don't support mutating slices
            kexpression.mayBeSharedMutableStruct = false
        } else {
            kexpression.mayBeSharedMutableStruct = expression.inferredType.kotlinMayBeSharedMutableStruct(codebaseInfo: translator.codebaseInfo)
        }
        if case .dictionary = expression.base.inferredType {
            kexpression.isDictionarySubscript = true
        }

        if expression.arguments.count == 1 && expression.arguments[0].label == "keyPath" && expression.arguments[0].value is KeyPathLiteral {
            kexpression.messages.append(.kotlinKeyPath(kexpression, source: translator.syntaxTree.source))
        }
        return kexpression
    }

    private init(expression: Subscript, base: KotlinExpression) {
        self.base = base
        super.init(type: .subscript, expression: expression)
    }

    var isInAwait = false
    var isInMainActorContext = false
    var apiFlags: APIFlags? {
        return apiMatch?.apiFlags
    }

    func mainActorMode(for child: KotlinSyntaxNode) -> KotlinMainActorMode {
        return child === base ? .isolatedFunctionReference : .isolated
    }

    var isSwiftUIBinding: Bool {
        return (base as? KotlinSwiftUIBindable)?.isSwiftUIBinding == true
    }

    func appendSwiftUIBindingPath(to output: OutputGenerator, indentation: Indentation, appendPath: @escaping (OutputGenerator, Indentation, KotlinBindableBase) -> Void) {
        (base as? KotlinSwiftUIBindable)?.appendSwiftUIBindingPath(to: output, indentation: indentation) { output, indentation, appendBase in
            appendPath(output, indentation) { output, indentation in
                appendBase(output, indentation)
                self.appendSubscript(to: output, indentation: indentation)
            }
        }
    }

    override func mayBeSharedMutableStructExpression(orType: Bool) -> Bool {
        // Subscripts sref() on the way out, but they do so with an onUpdate to support e.g. 'a[0].i += 1'. So unlike a
        // function, we do have to sref() subscript values again on assignment to erase the onUpdate action
        return mayBeSharedMutableStruct
    }

    override var optionalChain: KotlinOptionalChain {
        return base.optionalChain == .none ? .none : .implicit
    }

    override var children: [KotlinSyntaxNode] {
        return [base] + arguments.map { $0.value }
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        if let bindable = base as? KotlinSwiftUIBindable, bindable.isSwiftUIBinding {
            bindable.appendSwiftUIBindingPath(to: output, indentation: indentation) { output, indentation, appendBase in
                appendBase(output, indentation)
                self.appendSubscript(to: output, indentation: indentation)
            }
        } else {
            output.append(base, indentation: indentation)
            appendSubscript(to: output, indentation: indentation)
        }
    }

    private func appendSubscript(to output: OutputGenerator, indentation: Indentation) {
        // Kotlin can't optional chain a subscript, i.e. a?[0]
        switch base.optionalChain {
        case .none:
            output.append("[")
        case .explicit:
            output.append(".get(")
        case .implicit:
            output.append("?.get(")
        }
        for (index, argument) in arguments.enumerated() {
            // Note: Kotlin does not support labels for subscript arguments
            let isAutoclosure = isDictionarySubscript && index == 1 && argument.label == "default"
            if isAutoclosure {
                output.append("{ ")
            }
            output.append(argument.value, indentation: indentation)
            if isAutoclosure {
                output.append(" }")
            }
            if index < arguments.count - 1 {
                output.append(", ")
            }
        }
        output.append(base.optionalChain == .none ? "]" : ")")
        if mainActorMode.output != .none {
            // Cooperate with our base child, which will output the beginning part of the closure to execute this
            // on the main actor. We just output the closing brace
            output.append(" }")
        }
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

    /// Maximum support tuple elements.
    static let maximumArity = 5

    /// Return the member name for the given tuple index.
    static func member(index: Int) -> String {
        return "element\(index)"
    }

    static func translate(expression: TupleLiteral, translator: KotlinTranslator) throws -> KotlinTupleLiteral {
        guard expression.values.count <= maximumArity else {
            throw Message.kotlinTupleArity(expression, source: translator.syntaxTree.source)
        }
        // Our Kotlin Tuples are data classes which do not sref() their constructor arguments
        let kvalues = expression.values.map { translator.translateExpression($0).sref() }
        return KotlinTupleLiteral(expression: expression, values: kvalues)
    }

    init(values: [KotlinExpression], sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.values = values
        super.init(type: .tupleLiteral, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(expression: TupleLiteral, values: [KotlinExpression]) {
        self.values = values
        super.init(type: .tupleLiteral, expression: expression)
    }

    override func sref(onUpdate: (() -> String)? = nil) -> KotlinExpression {
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
            output.append("Tuple\(values.count)")
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

class KotlinTypeLiteral: KotlinExpression, KotlinCastTarget {
    var literal: TypeSignature
    var signature: TypeSignature?

    static func translate(expression: TypeLiteral, translator: KotlinTranslator) -> KotlinTypeLiteral {
        let kliteral = KotlinTypeLiteral(expression: expression)
        kliteral.signature = translator.codebaseInfo?.primaryTypeInfo(forNamed: expression.literal)?.signature
        return kliteral
    }

    private init(expression: TypeLiteral) {
        self.literal = expression.literal.resolvingSelf(in: expression)
        super.init(type: .typeLiteral, expression: expression)
    }

    var generics: [TypeSignature]? {
        return literal.generics
    }
    var castTargetType: KotlinCastTargetType = .none

    override func insertDependencies(into dependencies: inout KotlinDependencies) {
        literal.insertDependencies(into: &dependencies)
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        var literal = self.literal
        if !literal.generics.isEmpty {
            if castTargetType == .typeErasedTarget {
                literal = literal.withGenerics(literal.generics.map { _ in TypeSignature.named("*", []) })
            }
        } else if castTargetType != .none, let signature = signature, !signature.generics.isEmpty {
            literal = literal.withGenerics(Array(repeating: TypeSignature.named("*", []), count: signature.generics.count))
        }
        output.append(literal.kotlin)
    }
}

class KotlinWhen: KotlinExpression {
    static let breakLabel = "bl"

    var on: KotlinExpression
    var cases: [KotlinCase]
    var caseTargetVariable: KotlinTargetVariable?
    var hasNonNilMatches = false
    var hasBreakLabel = false
    var requiresNestingClosure = false

    static func translate(expression: Switch, translator: KotlinTranslator) -> KotlinWhen {
        var kon = translator.translateExpression(expression.on)
        let isSealedClassesEnum = expression.on.inferredType.kotlinIsSealedClassesEnum(codebaseInfo: translator.codebaseInfo)
        var caseTargetVariable: KotlinTargetVariable? = nil
        let hasNonNilMatches = expression.cases.contains { $0.patterns.contains { $0.pattern.isNonNilMatch } }
        // When we have to compare the switch expression to nil we'll be executing it repeatedly, so store it in a var
        if hasNonNilMatches && (kon as? KotlinIdentifier)?.isLocalOrSelfIdentifier != true {
            caseTargetVariable = KotlinTargetVariable(value: kon)
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
        kexpression.messages += messages
        return kexpression
    }

    init(on: KotlinExpression, cases: [KotlinCase], sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.on = on
        self.cases = cases
        super.init(type: .when, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    private init(expression: Switch, on: KotlinExpression, cases: [KotlinCase]) {
        self.on = on
        self.cases = cases
        super.init(type: .when, expression: expression)
    }

    override var children: [KotlinSyntaxNode] {
        var children: [KotlinSyntaxNode] = [on]
        if let caseTargetVariable {
            children.append(caseTargetVariable.value)
        }
        children += cases.flatMap { $0.children }
        return children
    }

    override func append(to output: OutputGenerator, indentation: Indentation) {
        var indentation = indentation
        if requiresNestingClosure {
            indentation = indentation.inc()
            output.append("linvoke \(KotlinClosure.returnLabel)@{\n").append(indentation)
        }

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

        if (requiresNestingClosure) {
            output.append("\n").append(indentation.dec()).append("}")
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
        output.append(" -> ")
        let isSingleStatement = whenCase.caseBindingVariables.isEmpty && whenCase.body.isSingleStatementAppendable(mode: .case)
        if isSingleStatement {
            whenCase.body.appendAsSingleStatement(to: output, indentation: indentation, mode: .case)
            output.append("\n")
        } else {
            output.append("{\n")
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
}
