/// Handle enum constructors and `CaseIterable` synthesis.
class KotlinEnumTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        guard let codebaseInfo = translator.codebaseInfo else {
            return
        }
        syntaxTree.root.visit { visit($0, codebaseInfo: codebaseInfo) }
    }

    private func visit(_ node: KotlinSyntaxNode, codebaseInfo: CodebaseInfo.Context) -> VisitResult<KotlinSyntaxNode> {
        if let classDeclaration = node as? KotlinClassDeclaration, classDeclaration.declarationType == .enumDeclaration {
            handleConstructors(for: classDeclaration)
            synthesizeCaseIterable(for: classDeclaration, codebaseInfo: codebaseInfo)
        } else if let functionCall = node as? KotlinFunctionCall, functionCall.isOptionalInit {
            // We change enum constructors to factory functions
            if codebaseInfo.declarationType(forNamed: functionCall.inferredType) == .enumDeclaration {
                functionCall.isOptionalInit = false
            }
        }
        return .recurse(nil)
    }

    private func handleConstructors(for classDeclaration: KotlinClassDeclaration) {
        for constructor in classDeclaration.members where constructor.type == .constructorDeclaration {
            convertConstructorToFactory(constructor as! KotlinFunctionDeclaration, for: classDeclaration)
        }
    }

    private func convertConstructorToFactory(_ constructor: KotlinFunctionDeclaration, for classDeclaration: KotlinClassDeclaration) {
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
        guard codebaseInfo.global.protocolSignatures(forNamed: classDeclaration.signature).contains(.caseIterable) else {
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
