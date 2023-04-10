/// Synthesize `equals` and `hashCode` members in cases where the Swift compiler synthesizes `Equatable` and `Hashable`.
class KotlinEqualsHashCodeTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        guard let codebaseInfo = translator.codebaseInfo else {
            return
        }
        syntaxTree.root.visit { visit($0, codebaseInfo: codebaseInfo) }
    }

    private func visit(_ node: KotlinSyntaxNode, codebaseInfo: CodebaseInfo.Context) -> VisitResult<KotlinSyntaxNode> {
        if let classDeclaration = node as? KotlinClassDeclaration {
            if classDeclaration.declarationType == .structDeclaration || classDeclaration.isSealedClassesEnum {
                let protocols = codebaseInfo.global.protocolSignatures(forNamed: classDeclaration.signature)
                if protocols.contains(.named("Hashable", [])) {
                    ensureHasEquals(for: classDeclaration, codebaseInfo: codebaseInfo)
                    ensureHasHash(for: classDeclaration, codebaseInfo: codebaseInfo)
                } else if protocols.contains(.named("Equatable", [])) {
                    ensureHasEquals(for: classDeclaration, codebaseInfo: codebaseInfo)
                }
            }
        }
        // Recurse to find nested declarations
        return .recurse(nil)
    }

    private func ensureHasEquals(for classDeclaration: KotlinClassDeclaration, codebaseInfo: CodebaseInfo.Context) {
        let typeInfos = codebaseInfo.typeInfos(forNamed: classDeclaration.signature)
        guard !typeInfos.contains(where: { $0.members.contains { $0.isEqualsFunction } }) else {
            return
        }
        if classDeclaration.declarationType == .structDeclaration {
            let equalsFunction = equalsFunction(for: classDeclaration.signature.name, generics: classDeclaration.generics, properties: storedPropertyNames(of: classDeclaration))
            classDeclaration.members.append(equalsFunction)
            equalsFunction.parent = classDeclaration
            equalsFunction.assignParentReferences()
        } else if classDeclaration.isSealedClassesEnum {
            for enumCase in classDeclaration.members.compactMap({ $0 as? KotlinEnumCaseDeclaration }) {
                let equalsFunction = equalsFunction(for: KotlinEnumCaseDeclaration.sealedClassName(for: enumCase.name), generics: enumCase.generics, properties: (0..<enumCase.associatedValues.count).map { "associated\($0)" })
                enumCase.members.append(equalsFunction)
                equalsFunction.parent = enumCase
                equalsFunction.assignParentReferences()
            }
        }
    }

    private func ensureHasHash(for classDeclaration: KotlinClassDeclaration, codebaseInfo: CodebaseInfo.Context) {
        let typeInfos = codebaseInfo.typeInfos(forNamed: classDeclaration.signature)
        guard !typeInfos.contains(where: { $0.members.contains { $0.isHashFunction } }) else {
            return
        }
        if classDeclaration.declarationType == .structDeclaration {
            let hashCodeFunction = hashCodeFunction(for: classDeclaration.signature.name, properties: storedPropertyNames(of: classDeclaration))
            classDeclaration.members.append(hashCodeFunction)
            hashCodeFunction.parent = classDeclaration
            hashCodeFunction.assignParentReferences()
        } else if classDeclaration.isSealedClassesEnum {
            for enumCase in classDeclaration.members.compactMap({ $0 as? KotlinEnumCaseDeclaration }) {
                let hashCodeFunction = hashCodeFunction(for: KotlinEnumCaseDeclaration.sealedClassName(for: enumCase.name), properties: (0..<enumCase.associatedValues.count).map { "associated\($0)" })
                enumCase.members.append(hashCodeFunction)
                hashCodeFunction.parent = enumCase
                hashCodeFunction.assignParentReferences()
            }
        }
    }

    private func hashCodeFunction(for className: String, properties: [String]) -> KotlinFunctionDeclaration {
        let hashCodeFunction = KotlinFunctionDeclaration(name: "hashCode")
        hashCodeFunction.returnType = .int
        hashCodeFunction.modifiers.visibility = .public
        hashCodeFunction.modifiers.isOverride = true
        hashCodeFunction.extras = .singleNewline

        var statements: [KotlinStatement] = []
        if properties.isEmpty {
            statements.append(KotlinRawStatement(sourceCode: "return \"\(className)\".hashCode()"))
        } else {
            statements.append(KotlinRawStatement(sourceCode: "var result = 1"))
            statements += properties.map { KotlinRawStatement(sourceCode: "result = Hasher.combine(result, \($0))") }
            statements.append(KotlinRawStatement(sourceCode: "return result"))
        }
        hashCodeFunction.body = KotlinCodeBlock(statements: statements)
        return hashCodeFunction
    }

    private func equalsFunction(for className: String, generics: Generics, properties: [String]) -> KotlinFunctionDeclaration {
        let equalsFunction = KotlinFunctionDeclaration(name: "equals")
        equalsFunction.parameters = [.init(externalLabel: "other", declaredType: .optional(.any))]
        equalsFunction.returnType = .bool
        equalsFunction.modifiers.visibility = .public
        equalsFunction.modifiers.isOverride = true
        equalsFunction.extras = .singleNewline

        var typeName = className
        if !generics.entries.isEmpty {
            typeName += "<\((0..<generics.entries.count).map { _ in "*" }.joined(separator: ", "))>"
        }
        let conditions: String
        if properties.isEmpty {
            conditions = "true"
        } else {
            conditions = properties.map { "\($0) == other.\($0)" }.joined(separator: " && ")
        }
        let statements: [KotlinStatement] = [
            KotlinRawStatement(sourceCode: "if (other !is \(typeName)) return false"),
            KotlinRawStatement(sourceCode: "return \(conditions)")
        ]
        equalsFunction.body = KotlinCodeBlock(statements: statements)
        return equalsFunction
    }

    private func storedPropertyNames(of classDeclaration: KotlinClassDeclaration) -> [String] {
        return classDeclaration.members
            .compactMap { $0 as? KotlinVariableDeclaration }
            .filter { !$0.isStatic && !$0.isGenerated && $0.getter == nil }
            .map { $0.names[0] ?? "" }
    }
}

private extension CodebaseInfoItem {
    var isEqualsFunction: Bool {
        return declarationType == .functionDeclaration && name == "==" && modifiers.isStatic && signature.parameters.count == 2
    }

    var isHashFunction: Bool {
        guard declarationType == .functionDeclaration && name == "hash" && !modifiers.isStatic else {
            return false
        }
        let parameters = signature.parameters
        return parameters.count == 1 && parameters[0].label == "into" && parameters[0].type == .named("Hasher", [])
    }
}
