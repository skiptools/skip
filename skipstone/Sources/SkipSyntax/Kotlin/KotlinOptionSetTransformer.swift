/// Handle adding factory function to `OptionSet` implementations.
class KotlinOptionSetTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        syntaxTree.root.visit {
            if let classDeclaration = $0 as? KotlinClassDeclaration {
                transformOptionSet(for: classDeclaration, source: translator.syntaxTree.source)
            }
            return .recurse(nil)
        }
    }

    private func transformOptionSet(for classDeclaration: KotlinClassDeclaration, source: Source) {
        // We don't need to worry about extensions because they will have already been merged into the class.
        // See if this is an OptionSet. We may already have resolved the inherited RawRepresentable generic type
        var valueType: TypeSignature? = nil
        guard let inheritsIndex = classDeclaration.inherits.firstIndex(where: {
            if case .named(let name, let generics) = $0, name == "OptionSet" {
                valueType = generics.first
                return true
            } else {
                return false
            }
        }) else {
            return
        }
        if valueType == nil {
            valueType = rawValueType(for: classDeclaration)
        }
        guard let valueType, valueType.isNumeric else {
            classDeclaration.messages.append(.kotlinOptionSetRawValue(classDeclaration, source: source))
            return
        }

        classDeclaration.inherits[inheritsIndex] = .named("OptionSet", [classDeclaration.signature, valueType])
        addInterfaceMembers(to: classDeclaration, rawValueType: valueType)
        addVarargsFactory(to: classDeclaration, rawValueType: valueType)
    }

    private func rawValueType(for classDeclaration: KotlinClassDeclaration) -> TypeSignature? {
        let constructors = classDeclaration.members.compactMap { (member: KotlinStatement) -> KotlinFunctionDeclaration? in
            guard member.type == .constructorDeclaration else {
                return nil
            }
            return member as? KotlinFunctionDeclaration
        }
        if let rawValueConstructor = constructors.first(where: { $0.parameters.count == 1 && $0.parameters[0].externalLabel == "rawValue" }) {
            return rawValueConstructor.parameters[0].declaredType
        }
        return nil
    }

    private func addInterfaceMembers(to classDeclaration: KotlinClassDeclaration, rawValueType: TypeSignature) {
        let rawValueVar = KotlinVariableDeclaration(names: ["rawvaluelong"], variableTypes: [.int64])
        rawValueVar.extras = .singleNewline
        rawValueVar.isProperty = true
        rawValueVar.modifiers.visibility = .public
        rawValueVar.modifiers.isOverride = true
        rawValueVar.declaredType = .int64
        rawValueVar.isReadOnly = true
        rawValueVar.isGenerated = true

        let rawValueCode = rawValueType == .int64 ? "return rawValue" : "return Long(rawValue)"
        let rawValueStatement = KotlinRawStatement(sourceCode: rawValueCode)
        rawValueVar.getter = Accessor(body: KotlinCodeBlock(statements: [rawValueStatement]))

        classDeclaration.members.append(rawValueVar)
        rawValueVar.parent = classDeclaration
        rawValueVar.assignParentReferences()

        let factory = KotlinFunctionDeclaration(name: "optionset")
        factory.extras = .singleNewline
        factory.modifiers.visibility = .public
        factory.modifiers.isOverride = true
        factory.isGenerated = true
        factory.returnType = classDeclaration.signature
        factory.parameters = [Parameter<KotlinExpression>(externalLabel: "rawvaluelong", declaredType: .int64)]

        let factoryCode = rawValueType == .int64 ? "return \(classDeclaration.name)(rawValue = rawvaluelong)" : "return \(classDeclaration.name)(rawValue = \(rawValueType.kotlin)(rawvaluelong))"
        let factoryStatement = KotlinRawStatement(sourceCode: factoryCode)
        factory.body = KotlinCodeBlock(statements: [factoryStatement])

        classDeclaration.members.append(factory)
        factory.parent = classDeclaration
        factory.assignParentReferences()
    }

    private func addVarargsFactory(to classDeclaration: KotlinClassDeclaration, rawValueType: TypeSignature) {
        let factory = KotlinFunctionDeclaration(name: "of")
        factory.extras = .singleNewline
        factory.modifiers.isStatic = true
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
