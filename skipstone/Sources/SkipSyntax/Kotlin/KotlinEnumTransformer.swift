/// Handle `RawRepresentable` and `CaseIterable` synthesis.
class KotlinEnumTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        guard let codebaseInfo = translator.codebaseInfo else {
            return
        }
        syntaxTree.root.visit { visit($0, codebaseInfo: codebaseInfo) }
    }

    private func visit(_ node: KotlinSyntaxNode, codebaseInfo: CodebaseInfo.Context) -> VisitResult<KotlinSyntaxNode> {
        if let classDeclaration = node as? KotlinClassDeclaration {
            handleConstructors(for: classDeclaration, codebaseInfo: codebaseInfo)
            synthesizeCaseIterable(for: classDeclaration, codebaseInfo: codebaseInfo)
        }
        return .recurse(nil)
    }

    private func handleConstructors(for classDeclaration: KotlinClassDeclaration, codebaseInfo: CodebaseInfo.Context) {
        // We don't need to worry about extensions because they will have already been merged into the class
        let constructors = classDeclaration.members.compactMap { (member: KotlinStatement) -> KotlinFunctionDeclaration? in
            guard member.type == .constructorDeclaration else {
                return nil
            }
            return member as? KotlinFunctionDeclaration
        }

        // Handle RawRepresentable constructor conformance
        var rawValueType = classDeclaration.enumInheritedRawValueType
        if let rawValueConstructor = constructors.first(where: { $0.parameters.count == 1 && $0.parameters[0].externalLabel == "rawValue" }) {
            rawValueType = rawValueConstructor.parameters[0].declaredType
        } else if let rawValueType {
            addRawValueConstructor(to: classDeclaration, rawValueType: rawValueType)
        }
        if let rawValueType {
            let inherit: TypeSignature = .named("RawRepresentable", [rawValueType])
            if let rawRepresentableIndex = classDeclaration.inherits.firstIndex(of: .named("RawRepresentable", [])) {
                classDeclaration.inherits[rawRepresentableIndex] = inherit
            } else if classDeclaration.enumInheritedRawValueType != nil {
                classDeclaration.inherits.append(inherit)
            }
        }

        if classDeclaration.declarationType == .enumDeclaration {
            constructors.forEach { fixupEnumConstructor($0, for: classDeclaration) }
        }
    }

    private func addRawValueConstructor(to classDeclaration: KotlinClassDeclaration, rawValueType: TypeSignature) {
        let factory = KotlinFunctionDeclaration(name: classDeclaration.name)
        factory.modifiers = classDeclaration.modifiers
        factory.generics = classDeclaration.generics
        factory.extras = .singleNewline
        factory.isGenerated = true
        factory.returnType = classDeclaration.signature.asOptional(true)
        factory.parameters = [Parameter<KotlinExpression>(externalLabel: "rawValue", declaredType: rawValueType)]

        // We create structured expressions rather than raw source because our enum case raw values are stored as expressions
        let callString = classDeclaration.alwaysCreateNewSealedClassInstances ? "()" : ""
        var cases = classDeclaration.members
            .compactMap { $0 as? KotlinEnumCaseDeclaration }
            .compactMap { (enumCase: KotlinEnumCaseDeclaration) -> KotlinCase? in
                guard let rawValue = enumCase.rawValue else {
                    return nil
                }
                let statement = KotlinRawStatement(sourceCode: "\(classDeclaration.name).\(enumCase.name)\(callString)")
                return KotlinCase(patterns: [rawValue], body: KotlinCodeBlock(statements: [statement]))
            }
        cases.append(KotlinCase(patterns: [KotlinRawExpression(sourceCode: "else")], body: KotlinCodeBlock(statements: [KotlinRawStatement(sourceCode: "null")])))
        let when = KotlinWhen(on: KotlinIdentifier(name: "rawValue"), cases: cases)
        let ret = KotlinReturn(expression: when)
        factory.body = KotlinCodeBlock(statements: [ret])

        (classDeclaration.parent as? KotlinStatement)?.insert(statements: [factory], after: classDeclaration)
    }

    private func fixupEnumConstructor(_ constructor: KotlinFunctionDeclaration, for classDeclaration: KotlinClassDeclaration) {
        let factory = KotlinFunctionDeclaration(name: classDeclaration.name, sourceFile: constructor.sourceFile, sourceRange: constructor.sourceRange)
        factory.modifiers = classDeclaration.modifiers
        factory.generics = classDeclaration.generics.merge(overrides: constructor.generics, addNew: true)
        factory.annotations = constructor.annotations
        factory.extras = constructor.extras
        factory.returnType = classDeclaration.signature.asOptional(constructor.isOptionalInit)
        factory.parameters = constructor.parameters
        factory.disambiguatingParameterCount = constructor.disambiguatingParameterCount
        factory.isGenerated = constructor.isGenerated
        factory.body = constructor.body
        factory.body?.updateWithExpectedReturn(.assignToSelf)

        classDeclaration.remove(statement: constructor)
        (classDeclaration.parent as? KotlinStatement)?.insert(statements: [factory], after: classDeclaration)
    }

    private func synthesizeCaseIterable(for classDeclaration: KotlinClassDeclaration, codebaseInfo: CodebaseInfo.Context) {
        guard classDeclaration.declarationType == .enumDeclaration, codebaseInfo.global.protocolSignatures(forNamed: classDeclaration.signature).contains(.named("CaseIterable", [])) else {
            return
        }
        let typeInfos = codebaseInfo.typeInfos(forNamed: classDeclaration.signature)
        guard !typeInfos.contains(where: { $0.members.contains(where: { $0.isAllCasesVar }) }) else {
            return
        }

        let allCasesVar = KotlinVariableDeclaration(names: ["allCases"], variableTypes: [.array(classDeclaration.signature)])
        allCasesVar.modifiers.isStatic = true
        allCasesVar.declaredType = .array(classDeclaration.signature)
        allCasesVar.isReadOnly = true
        allCasesVar.isGenerated = true

        let caseSuffix = classDeclaration.alwaysCreateNewSealedClassInstances ? "()" : ""
        let allCasesList = classDeclaration.members
            .compactMap { $0 as? KotlinEnumCaseDeclaration }
            .map { $0.name + caseSuffix }
            .joined(separator: ", ")
        let statement = KotlinRawStatement(sourceCode: "return arrayOf(\(allCasesList))")
        allCasesVar.getter = Accessor(body: KotlinCodeBlock(statements: [statement]))
        
        classDeclaration.members.append(allCasesVar)
        allCasesVar.parent = classDeclaration
        allCasesVar.assignParentReferences()
    }
}

private extension CodebaseInfoItem {
    var isAllCasesVar: Bool {
        return declarationType == .variableDeclaration && name == "allCases" && modifiers.isStatic
    }
}
