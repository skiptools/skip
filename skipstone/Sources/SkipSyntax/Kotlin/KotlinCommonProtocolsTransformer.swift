/// Perform synthesis and fixups related to `Equatable`, `Hashable`, `Comparable`, etc implementations.
///
///   1. Synthesize `equals` and `hashCode` members in cases where the Swift compiler synthesizes `Equatable` and `Hashable`.
///   2. Remove references to `CustomStringConvertible`, `Equatable`, `Hashable` in inherits lists and generic constraints, because they are just aliases for `Any` in Kotlin.
///   3. Change references to `Comparable` in inherits lists and generic constraints to Kotlin's `Comparable<T>`.
final class KotlinCommonProtocolsTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        guard let codebaseInfo = translator.codebaseInfo else {
            return
        }
        syntaxTree.root.visit { visit($0, codebaseInfo: codebaseInfo, source: translator.syntaxTree.source) }
    }

    private func visit(_ node: KotlinSyntaxNode, codebaseInfo: CodebaseInfo.Context, source: Source) -> VisitResult<KotlinSyntaxNode> {
        if let classDeclaration = node as? KotlinClassDeclaration {
            synthesizeToString(for: classDeclaration, codebaseInfo: codebaseInfo)
            synthesizeConformances(for: classDeclaration, codebaseInfo: codebaseInfo, source: source)
            classDeclaration.inherits = fixupInherits(classDeclaration.inherits, for: classDeclaration.signature)
            classDeclaration.generics = fixupGenerics(classDeclaration.generics)
        } else if let interfaceDeclaration = node as? KotlinInterfaceDeclaration {
            interfaceDeclaration.inherits = fixupInherits(interfaceDeclaration.inherits, for: interfaceDeclaration.signature)
            interfaceDeclaration.generics = fixupGenerics(interfaceDeclaration.generics)
        } else if let functionDeclaration = node as? KotlinFunctionDeclaration {
            functionDeclaration.generics = fixupGenerics(functionDeclaration.generics)
            if let convertedGenerics = functionDeclaration.convertedGenerics {
                functionDeclaration.convertedGenerics = fixupGenerics(convertedGenerics)
            }
        } else if let enumCaseDeclaration = node as? KotlinEnumCaseDeclaration {
            enumCaseDeclaration.generics = fixupGenerics(enumCaseDeclaration.generics)
            enumCaseDeclaration.enumGenerics = fixupGenerics(enumCaseDeclaration.enumGenerics)
        }
        if let memberDeclaration = node as? KotlinMemberDeclaration, let extends = memberDeclaration.extends {
            memberDeclaration.extends = (extends.0, fixupGenerics(extends.1))
        }
        return .recurse(nil)
    }

    private func fixupInherits(_ inherits: [TypeSignature], for type: TypeSignature) -> [TypeSignature] {
        return inherits.compactMap {
            // Filter types that are aliased to Kotlin Any
            guard !$0.isCustomStringConvertible && !$0.isEquatable && !$0.isHashable else {
                return nil
            }
            // Map Comparable to Kotlin's Comparable<T>
            if $0.isComparable {
                return .kotlinComparable(for: type)
            } else {
                return $0
            }
        }
    }

    private func fixupGenerics(_ generics: Generics) -> Generics {
        guard !generics.isEmpty else {
            return generics
        }
        let entries = generics.entries.map {
            guard !$0.inherits.isEmpty else {
                return $0
            }
            var generic = $0
            generic.inherits = fixupInherits(generic.inherits, for: .named(generic.name, []))
            return generic
        }
        return Generics(entries: entries)
    }

    private func synthesizeToString(for classDeclaration: KotlinClassDeclaration, codebaseInfo: CodebaseInfo.Context) {
        guard classDeclaration.members.contains(where: { member in
            guard let variableDeclaration = member as? KotlinVariableDeclaration else {
                return false
            }
            return !variableDeclaration.isStatic && variableDeclaration.propertyName == "description" && variableDeclaration.propertyType == .string
        }) else {
            return
        }
        guard codebaseInfo.global.protocolSignatures(forNamed: classDeclaration.signature).contains(where: { $0.isCustomStringConvertible }) else {
            return
        }

        let toStringFunction = toStringFunction()
        toStringFunction.extras = .singleNewline
        classDeclaration.members.append(toStringFunction)
        toStringFunction.parent = classDeclaration
        toStringFunction.assignParentReferences()
    }

    private func synthesizeConformances(for classDeclaration: KotlinClassDeclaration, codebaseInfo: CodebaseInfo.Context, source: Source) {
        // Kotlin enums have built-in non-overridable ordering, so we have to convert regular enums to use sealed
        // classes if they want custom ordering
        let isEnum = classDeclaration.declarationType == .enumDeclaration
        let isEnumWithLessThan = isEnum && codebaseInfo.typeInfos(forNamed: classDeclaration.signature).contains(where: { $0.members.contains { $0.isLessThanFunction } })
        if isEnumWithLessThan && !classDeclaration.isSealedClassesEnum {
            classDeclaration.isSealedClassesEnum = true
        }

        // Nothing to do for classes - which never get automatic conformance - or for non-sealed-classes enums -
        // which have builtin conformances already
        guard classDeclaration.declarationType == .structDeclaration || classDeclaration.isSealedClassesEnum else {
            return
        }

        let protocols = codebaseInfo.global.protocolSignatures(forNamed: classDeclaration.signature)
        let isEnumWithoutAssociatedValues = isEnum && !classDeclaration.members.contains { ($0 as? KotlinEnumCaseDeclaration)?.associatedValues.isEmpty == false }
        if isEnumWithoutAssociatedValues || protocols.contains(where: \.isHashable) {
            ensureHasEquals(for: classDeclaration, codebaseInfo: codebaseInfo)
            ensureHasHash(for: classDeclaration, codebaseInfo: codebaseInfo)
        } else if isEnumWithoutAssociatedValues || protocols.contains(where: \.isEquatable) {
            ensureHasEquals(for: classDeclaration, codebaseInfo: codebaseInfo)
        }

        if isEnum && !isEnumWithLessThan && protocols.contains(where: \.isComparable) {
            classDeclaration.messages.append(.kotlinEnumSealedClassComparableConformance(classDeclaration, source: source))
        }
    }

    private func ensureHasEquals(for classDeclaration: KotlinClassDeclaration, codebaseInfo: CodebaseInfo.Context) {
        let typeInfos = codebaseInfo.typeInfos(forNamed: classDeclaration.signature)
        guard !typeInfos.contains(where: { $0.members.contains(where: \.isEqualsFunction) }) else {
            return
        }
        if classDeclaration.declarationType == .structDeclaration {
            let equalsFunction = equalsFunction(for: classDeclaration.signature.name, generics: classDeclaration.generics, properties: storedPropertyNames(of: classDeclaration))
            if !classDeclaration.members.isEmpty {
                equalsFunction.extras = .singleNewline
            }
            classDeclaration.members.append(equalsFunction)
            equalsFunction.parent = classDeclaration
            equalsFunction.assignParentReferences()
        } else if classDeclaration.isSealedClassesEnum {
            for enumCase in classDeclaration.members.compactMap({ $0 as? KotlinEnumCaseDeclaration }) {
                guard classDeclaration.alwaysCreateNewSealedClassInstances || !enumCase.associatedValues.isEmpty else {
                    continue
                }
                let equalsFunction = equalsFunction(for: KotlinEnumCaseDeclaration.sealedClassName(for: enumCase.name), generics: enumCase.generics, properties: (0..<enumCase.associatedValues.count).map { "associated\($0)" })
                enumCase.members.append(equalsFunction)
                equalsFunction.parent = enumCase
                equalsFunction.assignParentReferences()
            }
        }
    }

    private func ensureHasHash(for classDeclaration: KotlinClassDeclaration, codebaseInfo: CodebaseInfo.Context) {
        let typeInfos = codebaseInfo.typeInfos(forNamed: classDeclaration.signature)
        guard !typeInfos.contains(where: { $0.members.contains(where: \.isHashFunction) }) else {
            return
        }
        if classDeclaration.declarationType == .structDeclaration {
            let hashCodeFunction = hashCodeFunction(for: classDeclaration.signature.name, properties: storedPropertyNames(of: classDeclaration))
            if !classDeclaration.members.isEmpty {
                hashCodeFunction.extras = .singleNewline
            }
            classDeclaration.members.append(hashCodeFunction)
            hashCodeFunction.parent = classDeclaration
            hashCodeFunction.assignParentReferences()
        } else if classDeclaration.isSealedClassesEnum {
            for enumCase in classDeclaration.members.compactMap({ $0 as? KotlinEnumCaseDeclaration }) {
                guard classDeclaration.alwaysCreateNewSealedClassInstances || !enumCase.associatedValues.isEmpty else {
                    continue
                }
                let hashCodeFunction = hashCodeFunction(for: KotlinEnumCaseDeclaration.sealedClassName(for: enumCase.name), properties: (0..<enumCase.associatedValues.count).map { "associated\($0)" })
                enumCase.members.append(hashCodeFunction)
                hashCodeFunction.parent = enumCase
                hashCodeFunction.assignParentReferences()
            }
        }
    }

    private func toStringFunction() -> KotlinFunctionDeclaration {
        let toStringFunction = KotlinFunctionDeclaration(name: "toString")
        toStringFunction.returnType = .string
        toStringFunction.modifiers.visibility = .public
        toStringFunction.modifiers.isOverride = true
        toStringFunction.isGenerated = true

        let statements: [KotlinStatement] = [KotlinRawStatement(sourceCode: "return description")]
        toStringFunction.body = KotlinCodeBlock(statements: statements)
        return toStringFunction
    }

    private func hashCodeFunction(for className: String, properties: [String]) -> KotlinFunctionDeclaration {
        let hashCodeFunction = KotlinFunctionDeclaration(name: "hashCode")
        hashCodeFunction.returnType = .int
        hashCodeFunction.modifiers.visibility = .public
        hashCodeFunction.modifiers.isOverride = true
        hashCodeFunction.isGenerated = true

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
        equalsFunction.parameters = [.init(externalLabel: "other", declaredType: .any.asOptional(true))]
        equalsFunction.returnType = .bool
        equalsFunction.modifiers.visibility = .public
        equalsFunction.modifiers.isOverride = true
        equalsFunction.isGenerated = true

        var typeName = className
        if !generics.entries.isEmpty {
            typeName += "<\((0..<generics.entries.count).map { _ in "*" }.joined(separator: ", "))>"
        }
        let statements: [KotlinStatement]
        if properties.isEmpty {
            statements = [KotlinRawStatement(sourceCode: "return other is \(typeName)")]
        } else {
            let conditions = properties.map { "\($0) == other.\($0)" }.joined(separator: " && ")
            statements = [
                KotlinRawStatement(sourceCode: "if (other !is \(typeName)) return false"),
                KotlinRawStatement(sourceCode: "return \(conditions)")
            ]
        }
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

extension KotlinCommonProtocolsTransformer: KotlinTypeSignatureOutputTransformer {
    static func outputSignature(for signature: TypeSignature) -> TypeSignature {
        if signature.isNamed("Comparable", moduleName: "Swift", generics: []) {
            return signature.withGenerics([.named("*", [])])
        } else {
            return signature
        }
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
        return parameters.count == 1 && parameters[0].label == "into" && parameters[0].type.isNamed("Hasher", moduleName: "Swift", generics: [])
    }

    var isLessThanFunction: Bool {
        return declarationType == .functionDeclaration && name == "<" && modifiers.isStatic && signature.parameters.count == 2
    }
}
