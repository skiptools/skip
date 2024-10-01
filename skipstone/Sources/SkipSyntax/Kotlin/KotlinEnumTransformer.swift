/// Handle enum constructors and `CaseIterable` synthesis.
final class KotlinEnumTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        guard let codebaseInfo = translator.codebaseInfo else {
            return []
        }
        syntaxTree.root.visit { visit($0, in: syntaxTree, codebaseInfo: codebaseInfo) }
        return []
    }

    private func visit(_ node: KotlinSyntaxNode, in syntaxTree: KotlinSyntaxTree, codebaseInfo: CodebaseInfo.Context) -> VisitResult<KotlinSyntaxNode> {
        if let classDeclaration = node as? KotlinClassDeclaration, classDeclaration.declarationType == .enumDeclaration {
            if !classDeclaration.isSealedClassesEnum {
                escapeCaseNames(for: classDeclaration)
            }
            handleConstructors(for: classDeclaration)
            synthesizeCaseIterable(for: classDeclaration, in: syntaxTree, codebaseInfo: codebaseInfo)
        } else if let functionCall = node as? KotlinFunctionCall, functionCall.isOptionalInit {
            // We change enum constructors to factory functions
            if codebaseInfo.declarationType(forNamed: functionCall.inferredType)?.type == .enumDeclaration {
                functionCall.isOptionalInit = false
            }
        } else if let memberAccess = node as? KotlinMemberAccess, let apiMatch = memberAccess.apiMatch, apiMatch.declarationType == .enumCaseDeclaration {
            let fixedMember = memberAccess.member.fixingKeyword(in: KotlinEnumCaseDeclaration.disallowedCaseNames)
            if memberAccess.member != fixedMember, !codebaseInfo.isSealedClassesEnum(type: memberAccess.baseType).0 {
                memberAccess.member = fixedMember
            }
        }
        return .recurse(nil)
    }

    private func escapeCaseNames(for classDeclaration: KotlinClassDeclaration) {
        for caseDeclaration in classDeclaration.members.compactMap({ $0 as? KotlinEnumCaseDeclaration }) {
            let fixedName = caseDeclaration.name.fixingKeyword(in: KotlinEnumCaseDeclaration.disallowedCaseNames)
            if caseDeclaration.name != fixedName {
                if caseDeclaration.preEscapedName == nil {
                    caseDeclaration.preEscapedName = caseDeclaration.name
                }
                caseDeclaration.name = fixedName
            }
        }
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
        if let parentClassDeclaration = classDeclaration.parent as? KotlinClassDeclaration {
            factory.modifiers.isStatic = true
            parentClassDeclaration.members.append(factory)
            factory.parent = parentClassDeclaration
        } else if let parentStatement = classDeclaration.parent as? KotlinStatement {
            parentStatement.insert(statements: [factory], after: classDeclaration)
        }
    }

    private func synthesizeCaseIterable(for classDeclaration: KotlinClassDeclaration, in syntaxTree: KotlinSyntaxTree, codebaseInfo: CodebaseInfo.Context) {
        guard codebaseInfo.global.protocolSignatures(forNamed: classDeclaration.signature).contains(where: { $0.isNamed("CaseIterable", moduleName: "Swift", generics: []) }) else {
            return
        }
        let inherit: TypeSignature = .named("CaseIterableCompanion", [classDeclaration.signature])
        if let caseIterableIndex = classDeclaration.companionInherits.firstIndex(where: { $0.signature?.isNamed("CaseIterableCompanion", moduleName: "Swift") == true }) {
            classDeclaration.companionInherits[caseIterableIndex] = .interface(inherit)
        } else {
            classDeclaration.companionInherits.append(.interface(inherit))
        }
        let typeInfos = codebaseInfo.typeInfos(forNamed: classDeclaration.signature)
        guard !typeInfos.contains(where: { $0.members.contains(where: \.isAllCasesVar) }) else {
            return
        }
        syntaxTree.dependencies.insertSkipLibType("Array")

        let allCasesVar = KotlinVariableDeclaration(names: ["allCases"], variableTypes: [.array(classDeclaration.signature)])
        allCasesVar.modifiers.isStatic = true
        allCasesVar.modifiers.isOverride = true
        allCasesVar.modifiers.visibility = .public
        allCasesVar.role = .property
        if classDeclaration.members.contains(where: { ($0 as? KotlinMemberDeclaration)?.isStatic == true }) {
            allCasesVar.extras = .singleNewline
        }
        allCasesVar.declaredType = .array(classDeclaration.signature)
        allCasesVar.isGenerated = true

        let allCasesList = classDeclaration.members
            .compactMap { $0 as? KotlinEnumCaseDeclaration }
            .map { $0.name }
            .joined(separator: ", ")
        let statement = KotlinRawStatement(sourceCode: "return arrayOf(\(allCasesList))")
        allCasesVar.getter = Accessor(body: KotlinCodeBlock(statements: [statement]))
        
        classDeclaration.members.append(allCasesVar)
        allCasesVar.parent = classDeclaration
        allCasesVar.assignParentReferences()
    }
}

extension CodebaseInfoItem {
    fileprivate var isAllCasesVar: Bool {
        return declarationType == .variableDeclaration && name == "allCases" && modifiers.isStatic
    }
}
