/// Synthesize `allCases` for `CaseIterable` enums.
class KotlinCaseIterableTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        guard let codebaseInfo = translator.codebaseInfo else {
            return
        }
        syntaxTree.root.visit { visit($0, codebaseInfo: codebaseInfo) }
    }

    private func visit(_ node: KotlinSyntaxNode, codebaseInfo: CodebaseInfo.Context) -> VisitResult<KotlinSyntaxNode> {
        if let classDeclaration = node as? KotlinClassDeclaration {
            synthesizeCaseIterable(for: classDeclaration, codebaseInfo: codebaseInfo)
        }
        return .recurse(nil)
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
        let statement = KotlinRawStatement(sourceCode: "return arrayOf(\(allCasesList)")
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
