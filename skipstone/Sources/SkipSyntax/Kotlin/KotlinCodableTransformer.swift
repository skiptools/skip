/// Synthesize `Encodable` and `Decodable` conformance.
final class KotlinCodableTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        syntaxTree.root.visit {
            if let classDeclaration = $0 as? KotlinClassDeclaration {
                if classDeclaration.declarationType == .enumDeclaration && classDeclaration.inherits.contains(where: \.isCodingKey) {
                    fixupCodingKey(enumDeclaration: classDeclaration, translator: translator)
                } else {
                    synthesizeCodable(for: classDeclaration, translator: translator)
                }
            } else if let functionCall = $0 as? KotlinFunctionCall {
                fixupDecode(functionCall: functionCall)
            }
            return .recurse(nil)
        }
    }

    private func synthesizeCodable(for classDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) {
        // We don't need to worry about extensions because they will have already been merged into the class
        let inherits: [TypeSignature]
        if let codebaseInfo = translator.codebaseInfo {
            inherits = codebaseInfo.global.protocolSignatures(forNamed: classDeclaration.signature)
        } else {
            inherits = classDeclaration.inherits
        }
        let isEncodable = inherits.contains(where: \.isCodable) || inherits.contains(where: \.isEncodable)
        let isDecodable = inherits.contains(where: \.isCodable) || inherits.contains(where: \.isDecodable)
        guard isEncodable || isDecodable else {
            return
        }

        var encodeDeclaration: KotlinFunctionDeclaration? = nil
        if isEncodable {
            encodeDeclaration = classDeclaration.members.first {
                guard let functionDeclaration = $0 as? KotlinFunctionDeclaration else {
                    return false
                }
                return functionDeclaration.name == "encode" && functionDeclaration.parameters.count == 1 && functionDeclaration.parameters[0].externalLabel == "to" && functionDeclaration.parameters[0].declaredType.isNamed("Encoder", moduleName: "Swift", generics: [])
            } as? KotlinFunctionDeclaration
            encodeDeclaration?.modifiers.visibility = .public
            encodeDeclaration?.modifiers.isOverride = true
        }
        var decodeDeclaration: KotlinFunctionDeclaration? = nil
        if isDecodable {
            decodeDeclaration = classDeclaration.members.first {
                guard let functionDeclaration = $0 as? KotlinFunctionDeclaration else {
                    return false
                }
                return functionDeclaration.isDecodableConstructor
            } as? KotlinFunctionDeclaration
            decodeDeclaration?.modifiers.visibility = .public
        }

        if (isEncodable && encodeDeclaration == nil) || (isDecodable && decodeDeclaration == nil) {
            let storedVariableDeclarations = storedVariableDeclarations(of: classDeclaration)
            // The developer may use a bespoke name for their coding keys enum if they implement their own encode/decode,
            // so we only synthesize or look for coding keys after knowing we need to generate a coding function
            let rawValueType = classDeclaration.rawValueType
            let codingKeys = synthesizeCodingKeys(for: classDeclaration, with: storedVariableDeclarations, rawValueType: rawValueType, isDecodable: isDecodable, translator: translator)
            let matchedCodingKeys = matchCodingKeys(codingKeys, to: storedVariableDeclarations, source: translator.syntaxTree.source)
            let matchedCodingKeysByName = matchedCodingKeys?.reduce(into: [String: (KotlinEnumCaseDeclaration, KotlinVariableDeclaration)]()) { result, entry in
                result[entry.1.propertyName] = entry
            }

            if isEncodable && encodeDeclaration == nil {
                synthesizeEncode(for: classDeclaration, codingKeys: matchedCodingKeys, rawValueType: rawValueType, source: translator.syntaxTree.source)
            }
            if isDecodable && decodeDeclaration == nil {
                synthesizeDecode(for: classDeclaration, storedVariableDeclarations: storedVariableDeclarations, codingKeysByName: matchedCodingKeysByName, rawValueType: rawValueType, source: translator.syntaxTree.source)
            }
        }
        if isDecodable {
            synthesizeDecodableCompanion(for: classDeclaration)
        }
    }

    private func synthesizeCodingKeys(for classDeclaration: KotlinClassDeclaration, with storedVariableDeclarations: [KotlinVariableDeclaration], rawValueType: TypeSignature, isDecodable: Bool, translator: KotlinTranslator) -> [KotlinEnumCaseDeclaration]? {
        // Does the user have a custom enum?
        if let existingKeys = classDeclaration.members.first(where: {
            guard let memberClassDeclaration = $0 as? KotlinClassDeclaration else {
                return false
            }
            return memberClassDeclaration.declarationType == .enumDeclaration && memberClassDeclaration.name == "CodingKeys"
        }) as? KotlinClassDeclaration {
            return existingKeys.members.compactMap { $0 as? KotlinEnumCaseDeclaration }
        }
        guard rawValueType == .none && classDeclaration.declarationType != .enumDeclaration else {
            return nil
        }

        let enumDeclaration = KotlinClassDeclaration(name: "CodingKeys", signature: .named("CodingKeys", []), declarationType: .enumDeclaration)
        enumDeclaration.inherits = [.string, .named("CodingKey", [])]
        enumDeclaration.modifiers.visibility = .private
        enumDeclaration.extras = .singleNewline
        enumDeclaration.isGenerated = true
        let caseDeclarations = storedVariableDeclarations.map {
            let caseDeclaration = KotlinEnumCaseDeclaration(name: $0.propertyName)
            if let preEscapedPropertyName = $0.preEscapedPropertyName {
                caseDeclaration.preEscapedName = preEscapedPropertyName
                caseDeclaration.rawValue = KotlinStringLiteral(literal: preEscapedPropertyName)
            }
            return caseDeclaration
        }
        enumDeclaration.members = caseDeclarations
        enumDeclaration.processEnumMemberDeclarations(translator: translator)

        classDeclaration.members.append(enumDeclaration)
        enumDeclaration.parent = classDeclaration
        enumDeclaration.assignParentReferences()
        return caseDeclarations
    }

    private func matchCodingKeys(_ codingKeys: [KotlinEnumCaseDeclaration]?, to storedVariableDeclarations: [KotlinVariableDeclaration], source: Source) -> [(KotlinEnumCaseDeclaration, KotlinVariableDeclaration)]? {
        guard let codingKeys else {
            return nil
        }
        let mappedVariableDeclarations = storedVariableDeclarations.reduce(into: [String: KotlinVariableDeclaration]()) { result, variableDeclaration in
            result[variableDeclaration.propertyName] = variableDeclaration
        }
        var matchedCodingKeys: [(KotlinEnumCaseDeclaration, KotlinVariableDeclaration)] = []
        for codingKey in codingKeys {
            if let variableDeclaration = mappedVariableDeclarations[codingKey.forPropertyName] {
                if variableDeclaration.propertyType == .none {
                    variableDeclaration.messages.append(.kotlinCodablePropertyType(variableDeclaration, source: source))
                }
                matchedCodingKeys.append((codingKey, variableDeclaration))
            } else {
                codingKey.messages.append(.kotlinCodablePropertyForKey(codingKey, source: source))
            }
        }
        return matchedCodingKeys
    }

    private func fixupCodingKey(enumDeclaration: KotlinClassDeclaration, translator: KotlinTranslator) {
        // Coding keys are strings by default
        if enumDeclaration.enumInheritedRawValueType == .none {
            enumDeclaration.inherits.insert(.string, at: 0)
            enumDeclaration.processEnumMemberDeclarations(translator: translator)
        }
    }

    private func synthesizeEncode(for classDeclaration: KotlinClassDeclaration, codingKeys: [(KotlinEnumCaseDeclaration, KotlinVariableDeclaration)]?, rawValueType: TypeSignature, source: Source) {
        let encode = KotlinFunctionDeclaration(name: "encode")
        encode.extras = .singleNewline
        encode.modifiers.visibility = .public
        encode.modifiers.isOverride = true
        encode.isGenerated = true
        encode.parameters = [Parameter<KotlinExpression>(externalLabel: "to", declaredType: .named("Encoder", []))]

        var statements: [KotlinStatement] = []
        if let codingKeys {
            statements.append(KotlinRawStatement(sourceCode: "val container = to.container(keyedBy = CodingKeys::class)"))
            statements += codingKeys.map { entry in
                // We're run before the enum transformer, so our case names aren't fixed yet
                let caseName = entry.0.name.fixingKeyword(in: KotlinEnumCaseDeclaration.disallowedCaseNames)
                let encodeFunction = entry.1.propertyType.isOptional ? "encodeIfPresent" : "encode"
                return KotlinRawStatement(sourceCode: "container.\(encodeFunction)(\(entry.1.propertyName), forKey = CodingKeys.\(caseName))")
            }
        } else if rawValueType != .none {
            statements.append(KotlinRawStatement(sourceCode: "val container = to.singleValueContainer()"))
            statements.append(KotlinRawStatement(sourceCode: "container.encode(rawValue)"))
        } else {
            classDeclaration.messages.append(.kotlinCodableEncodeRawValueEnumsOnly(classDeclaration, source: source))
            return
        }
        encode.body = KotlinCodeBlock(statements: statements)

        classDeclaration.members.append(encode)
        encode.parent = classDeclaration
        encode.assignParentReferences()
    }

    private func synthesizeDecode(for classDeclaration: KotlinClassDeclaration, storedVariableDeclarations: [KotlinVariableDeclaration], codingKeysByName: [String: (KotlinEnumCaseDeclaration, KotlinVariableDeclaration)]?, rawValueType: TypeSignature, source: Source) {
        let decode: KotlinFunctionDeclaration
        if classDeclaration.declarationType == .enumDeclaration {
            decode = KotlinFunctionDeclaration(name: classDeclaration.name)
            decode.returnType = classDeclaration.signature
            decode.modifiers.visibility = classDeclaration.modifiers.visibility
        } else {
            decode = KotlinFunctionDeclaration(name: "constructor")
            decode.modifiers.visibility = .public
        }
        decode.extras = .singleNewline
        decode.isGenerated = true
        decode.parameters = [Parameter<KotlinExpression>(externalLabel: "from", declaredType: .named("Decoder", []))]

        var statements: [KotlinStatement] = []
        if let codingKeysByName { // Must be a non-RawRepresentable, non-enum type
            if !codingKeysByName.isEmpty {
                statements.append(KotlinRawStatement(sourceCode: "val container = from.container(keyedBy = CodingKeys::class)"))
            }
            for variableDeclaration in storedVariableDeclarations {
                if let entry = codingKeysByName[variableDeclaration.propertyName] {
                    if !variableDeclaration.isLet || (variableDeclaration.constructionValue == nil && variableDeclaration.value == nil) {
                        statements.append(synthesizeDecodeStatement(for: entry.0, with: entry.1))
                    }
                } else if !variableDeclaration.isLet, let constructionValue = variableDeclaration.constructionValue {
                    // Make sure that any uncoded variables are also initialized. 'let' vars will already be initialized by the
                    // constructor transformer
                    let access = KotlinMemberAccess(base: KotlinIdentifier(name: "self"), member: variableDeclaration.propertyName)
                    let assignment = KotlinBinaryOperator(op: .with(symbol: "="), lhs: access, rhs: constructionValue)
                    statements.append(KotlinExpressionStatement(expression: assignment))
                }
            }
            decode.body = KotlinCodeBlock(statements: statements)

            classDeclaration.members.append(decode)
            decode.parent = classDeclaration
        } else if rawValueType != .none { // RawRepresentable type
            statements.append(KotlinRawStatement(sourceCode: "val container = from.singleValueContainer()"))
            statements.append(KotlinRawStatement(sourceCode: "val rawValue = container.decode(\(rawValueType.kotlin)::class)"))
            // Raw value constructor may or may not be optional - check for explicit optional constructor or generated enum constructor
            let (constructor, _) = classDeclaration.rawValueMembers
            let isOptionalConstructor = constructor?.isOptionalInit == true || (constructor == nil && classDeclaration.declarationType == .enumDeclaration)
            if isOptionalConstructor {
                statements.append(KotlinRawStatement(sourceCode: "return \(classDeclaration.name)(rawValue = rawValue) ?: throw ErrorException(cause = NullPointerException())"))
            } else {
                statements.append(KotlinRawStatement(sourceCode: "return \(classDeclaration.name)(rawValue = rawValue)"))
            }
            decode.body = KotlinCodeBlock(statements: statements)

            if let parentClassDeclaration = classDeclaration.parent as? KotlinClassDeclaration {
                decode.modifiers.isStatic = true
                decode.modifiers.isFinal = true
                parentClassDeclaration.members.append(decode)
                decode.parent = parentClassDeclaration
            } else if let parentStatement = classDeclaration.parent as? KotlinStatement {
                parentStatement.insert(statements: [decode], after: classDeclaration)
            }
        } else {
            classDeclaration.messages.append(.kotlinCodableDecodeRawValueEnumsOnly(classDeclaration, source: source))
            return
        }
        decode.assignParentReferences()
    }

    private func synthesizeDecodeStatement(for codingKey: KotlinEnumCaseDeclaration, with variableDeclaration: KotlinVariableDeclaration) -> KotlinStatement {
        // We're run before the enum transformer, so our case names aren't fixed yet
        let caseName = codingKey.name.fixingKeyword(in: KotlinEnumCaseDeclaration.disallowedCaseNames)
        let type = variableDeclaration.propertyType.or(.any)
        let decodeFunction = type.isOptional ? "decodeIfPresent" : "decode"
        let decodeType = type.asOptional(false)
        let typeArguments: String
        switch decodeType {
        case .array(let elementType):
            if let elementType {
                if case .array(let nestedElementType) = elementType, let nestedElementType {
                    typeArguments = "Array::class, elementType = Array::class, nestedElementType = \(nestedElementType.withGenerics([]).kotlin)::class"
                } else {
                    typeArguments = "Array::class, elementType = \(elementType.withGenerics([]).kotlin)::class"
                }
            } else {
                typeArguments = "Array::class"
            }
        case .dictionary(let keyType, let valueType):
            if let keyType, let valueType {
                if case .array(let nestedElementType) = valueType, let nestedElementType {
                    typeArguments = "Dictionary::class, keyType = \(keyType.withGenerics([]).kotlin)::class, valueType = Array::class, nestedElementType = \(nestedElementType.withGenerics([]).kotlin)::class"
                } else {
                    typeArguments = "Dictionary::class, keyType = \(keyType.withGenerics([]).kotlin)::class, valueType = \(valueType.withGenerics([]).kotlin)::class"
                }
            } else {
                typeArguments = "Dictionary::class"
            }
        case .set(let elementType):
            if let elementType {
                typeArguments = "Set::class, elementType = \(elementType.withGenerics([]).kotlin)::class"
            } else {
                typeArguments = "Set::class"
            }
        default:
            typeArguments = "\(decodeType.withGenerics([]).kotlin)::class"
        }
        return KotlinRawStatement(sourceCode: "this.\(variableDeclaration.propertyName) = container.\(decodeFunction)(\(typeArguments), forKey = CodingKeys.\(caseName))")
    }

    private func synthesizeDecodableCompanion(for classDeclaration: KotlinClassDeclaration) {
        classDeclaration.companionInherits.append(.interface(.named("DecodableCompanion", [classDeclaration.signature])))

        let factory = KotlinFunctionDeclaration(name: "init")
        factory.modifiers.isStatic = true
        if classDeclaration.members.contains(where: { ($0 as? KotlinMemberDeclaration)?.isStatic == true }) {
            factory.extras = .singleNewline
        }
        factory.modifiers.visibility = .public
        factory.modifiers.isOverride = true
        factory.isGenerated = true
        factory.returnType = classDeclaration.signature
        factory.parameters = [Parameter<KotlinExpression>(externalLabel: "from", declaredType: .named("Decoder", []))]

        let statement = KotlinRawStatement(sourceCode: "return \(classDeclaration.signature.kotlin)(from = from)")
        factory.body = KotlinCodeBlock(statements: [statement])

        classDeclaration.members.append(factory)
        factory.parent = classDeclaration
        factory.assignParentReferences()
    }

    private func storedVariableDeclarations(of classDeclaration: KotlinClassDeclaration) -> [KotlinVariableDeclaration] {
        return classDeclaration.members
            .compactMap { $0 as? KotlinVariableDeclaration }
            .filter { !$0.isStatic && !$0.isGenerated && $0.getter == nil }
    }

    private func fixupDecode(functionCall: KotlinFunctionCall) {
        guard let function = functionCall.function as? KotlinMemberAccess, function.member == "decode" || function.member == "decodeIfPresent" else {
            return
        }
        // .decode(_, from:) for e.g. JSONDecoder or .decode(_, forKey:) for KeyedDecodingContainer
        guard functionCall.arguments.first?.label == nil, functionCall.arguments.count == 1 || (functionCall.arguments.count == 2 && (functionCall.arguments[1].label == "from" || functionCall.arguments[1].label == "forKey")) else {
            return
        }
        // Type.self
        guard let typeMember = functionCall.arguments[0].value as? KotlinMemberAccess, typeMember.member == "self", let type = typeMember.base else {
            return
        }
        // For array and dictionary decoding, call the appropriate decode overload to pass in the generic types
        var genericArguments: [LabeledValue<KotlinExpression>] = []
        if (type as? KotlinIdentifier)?.name == "Array" || type is KotlinArrayLiteral, let generics = typeMember.classReferenceGenerics, generics.count == 1 {
            if generics[0].name == "Array", let nestedElementType = generics[0].generics?.first {
                genericArguments = [arrayArgument(label: "elementType"), elementArgument(label: "nestedElementType", type: nestedElementType)]
            } else {
                genericArguments = [elementArgument(label: "elementType", type: generics[0])]
            }
        } else if (type as? KotlinIdentifier)?.name == "Dictionary" || type is KotlinDictionaryLiteral, let generics = typeMember.classReferenceGenerics, generics.count == 2 {
            let keyArgument = elementArgument(label: "keyType", type: generics[0])
            if generics[1].name == "Array", let nestedElementType = generics[1].generics?.first {
                genericArguments = [keyArgument, arrayArgument(label: "valueType"), elementArgument(label: "nestedElementType", type: nestedElementType)]
            } else {
                genericArguments = [keyArgument, elementArgument(label: "valueType", type: generics[1])]
            }
        }
        if !genericArguments.isEmpty {
            functionCall.arguments.insert(contentsOf: genericArguments, at: 1)
        }
    }

    private func arrayArgument(label: String) -> LabeledValue<KotlinExpression> {
        return LabeledValue(label: label, value: KotlinRawExpression(sourceCode: "Array::class"))
    }

    private func elementArgument(label: String, type: KotlinIdentifier) -> LabeledValue<KotlinExpression> {
        let signature = TypeSignature.for(name: type.name, genericTypes: [])
        return elementArgument(label: label, type: signature)
    }

    private func elementArgument(label: String, type: TypeSignature) -> LabeledValue<KotlinExpression> {
        return LabeledValue(label: label, value: KotlinRawExpression(sourceCode: "\(type.kotlin)::class"))
    }
}

extension KotlinEnumCaseDeclaration {
    private static let disallowedCaseNameCodingKeySuffix = "codingkey"

    fileprivate var forPropertyName: String {
        // Retain this for backwards compatibility: we used to encourage users to add this suffix
        guard name.count > Self.disallowedCaseNameCodingKeySuffix.count && name.hasSuffix(Self.disallowedCaseNameCodingKeySuffix) else {
            return name
        }
        return String(name.dropLast(Self.disallowedCaseNameCodingKeySuffix.count))
    }
}

extension TypeSignature {
    fileprivate var isCodingKey: Bool {
        return isNamed("CodingKey", moduleName: "Swift", generics: [])
    }

    fileprivate var isCodable: Bool {
        return isNamed("Codable", moduleName: "Swift", generics: [])
    }

    fileprivate var isDecodable: Bool {
        return isNamed("Decodable", moduleName: "Swift", generics: [])
    }

    fileprivate var isEncodable: Bool {
        return isNamed("Encodable", moduleName: "Swift", generics: [])
    }
}
