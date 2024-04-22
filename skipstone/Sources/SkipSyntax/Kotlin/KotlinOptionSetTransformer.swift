/// Handle `OptionSet` implementation.
final class KotlinOptionSetTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        syntaxTree.root.visit {
            // We don't need to worry about extensions because they will have already been merged into the class
            if let classDeclaration = $0 as? KotlinClassDeclaration {
                handleOptionSet(for: classDeclaration, source: translator.syntaxTree.source)
            }
            return .recurse(nil)
        }
    }

    private func handleOptionSet(for classDeclaration: KotlinClassDeclaration, source: Source) {
        // See if this is an OptionSet. We may already have resolved the inherited RawRepresentable generic type
        var valueType: TypeSignature? = nil
        guard let inheritsIndex = classDeclaration.inherits.firstIndex(where: {
            if $0.isOptionSet {
                valueType = $0.generics.first
                return true
            } else {
                return false
            }
        }) else {
            return
        }
        guard classDeclaration.declarationType == .structDeclaration else {
            classDeclaration.messages.append(.kotlinOptionSetStruct(classDeclaration, source: source))
            return
        }
        if valueType == nil {
            valueType = classDeclaration.rawValueType
        }
        guard let valueType, valueType.isNumeric else {
            classDeclaration.messages.append(.kotlinOptionSetRawValue(classDeclaration, source: source))
            return
        }

        classDeclaration.inherits[inheritsIndex] = .named("OptionSet", [classDeclaration.signature, valueType])
        addOptionSetInterfaceMembers(to: classDeclaration, rawValueType: valueType)
        addOptionSetVarargsFactory(to: classDeclaration, rawValueType: valueType)
    }

    private func addOptionSetInterfaceMembers(to classDeclaration: KotlinClassDeclaration, rawValueType: TypeSignature) {
        let rawValueVar = KotlinVariableDeclaration(names: ["rawvaluelong"], variableTypes: [.uint64])
        rawValueVar.extras = .singleNewline
        rawValueVar.role = .property
        rawValueVar.modifiers.visibility = .public
        rawValueVar.modifiers.isOverride = true
        rawValueVar.declaredType = .uint64
        rawValueVar.isGenerated = true

        let rawValueCode = rawValueType == .uint64 ? "return rawValue" : "return ULong(rawValue)"
        let rawValueStatement = KotlinRawStatement(sourceCode: rawValueCode)
        rawValueVar.getter = Accessor(body: KotlinCodeBlock(statements: [rawValueStatement]))

        classDeclaration.members.append(rawValueVar)
        rawValueVar.parent = classDeclaration
        rawValueVar.assignParentReferences()

        let make = KotlinFunctionDeclaration(name: "makeoptionset")
        make.modifiers.visibility = .public
        make.modifiers.isOverride = true
        make.isGenerated = true
        make.returnType = classDeclaration.signature
        make.parameters = [Parameter<KotlinExpression>(externalLabel: "rawvaluelong", declaredType: .uint64)]

        let makeCode = rawValueType == .uint64 ? "return \(classDeclaration.name)(rawValue = rawvaluelong)" : "return \(classDeclaration.name)(rawValue = \(rawValueType.kotlin)(rawvaluelong))"
        let makeStatement = KotlinRawStatement(sourceCode: makeCode)
        make.body = KotlinCodeBlock(statements: [makeStatement])

        classDeclaration.members.append(make)
        make.parent = classDeclaration
        make.assignParentReferences()

        let assign = KotlinFunctionDeclaration(name: "assignoptionset")
        assign.modifiers.visibility = .public
        assign.modifiers.isOverride = true
        assign.modifiers.isMutating = true
        assign.isGenerated = true
        assign.parameters = [Parameter<KotlinExpression>(externalLabel: "target", declaredType: classDeclaration.signature)]
        assign.mutationFunctionNames = KotlinStructTransformer.mutationFunctionNames

        // Use structured statements so that subsequent transformers can detect and translate the self assignment
        let selfAssignment = KotlinBinaryOperator(op: .with(symbol: "="), lhs: KotlinIdentifier(name: "self"), rhs: KotlinIdentifier(name: "target"))
        let assignStatement = KotlinExpressionStatement(expression: selfAssignment)
        assign.body = KotlinCodeBlock(statements: [assignStatement])

        classDeclaration.members.append(assign)
        assign.parent = classDeclaration
        assign.assignParentReferences()
    }

    private func addOptionSetVarargsFactory(to classDeclaration: KotlinClassDeclaration, rawValueType: TypeSignature) {
        let factory = KotlinFunctionDeclaration(name: "of")
        factory.modifiers.isStatic = true
        factory.modifiers.isFinal = true
        if classDeclaration.members.contains(where: { ($0 as? KotlinMemberDeclaration)?.isStatic == true }) {
            factory.extras = .singleNewline
        }
        factory.modifiers.visibility = .public
        factory.isGenerated = true
        factory.returnType = classDeclaration.signature
        factory.parameters = [Parameter<KotlinExpression>(externalLabel: "options", declaredType: classDeclaration.signature, isVariadic: true)]

        let valueCode = "val value = options.fold(\(rawValueType.kotlin)(0)) { result, option -> result or option.rawValue }"
        let retCode = "return \(classDeclaration.name)(rawValue = value)"
        factory.body = KotlinCodeBlock(statements: [valueCode, retCode].map { KotlinRawStatement(sourceCode: $0) })

        classDeclaration.members.append(factory)
        factory.parent = classDeclaration
        factory.assignParentReferences()
    }
}
