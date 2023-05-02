/// Handle `RawRepresentable` implementation.
class KotlinRawRepresentableTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        syntaxTree.root.visit {
            // We don't need to worry about extensions because they will have already been merged into the class
            if let classDeclaration = $0 as? KotlinClassDeclaration {
                handleRawValue(for: classDeclaration)
            }
            return .recurse(nil)
        }
    }

    private func handleRawValue(for classDeclaration: KotlinClassDeclaration) {
        let (constructor, property) = classDeclaration.rawValueMembers
        let rawValueType: TypeSignature
        if let constructor {
            rawValueType = constructor.parameters[0].declaredType
        } else if let property {
            rawValueType = property.propertyType
        } else {
            rawValueType = classDeclaration.enumInheritedRawValueType
        }
        if constructor == nil && classDeclaration.enumInheritedRawValueType != .none {
            addEnumRawValueFactory(to: classDeclaration)
        }

        if rawValueType != .none {
            let inherit: TypeSignature = .named("RawRepresentable", [rawValueType])
            if let rawRepresentableIndex = classDeclaration.inherits.firstIndex(where: { $0.isRawRepresentable }) {
                classDeclaration.inherits[rawRepresentableIndex] = inherit
            } else if classDeclaration.enumInheritedRawValueType != .none {
                classDeclaration.inherits.append(inherit)
            }
        }
    }

    private func addEnumRawValueFactory(to classDeclaration: KotlinClassDeclaration) {
        let factory = KotlinFunctionDeclaration(name: classDeclaration.name)
        factory.modifiers = classDeclaration.modifiers
        factory.generics = classDeclaration.generics
        factory.extras = .singleNewline
        factory.isGenerated = true
        factory.returnType = classDeclaration.signature.asOptional(true)
        factory.parameters = [Parameter<KotlinExpression>(externalLabel: "rawValue", declaredType: classDeclaration.enumInheritedRawValueType)]

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
}
