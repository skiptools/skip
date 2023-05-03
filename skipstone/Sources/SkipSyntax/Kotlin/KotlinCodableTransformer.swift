/// Synthesize `Encodable` and `Decodable` conformance.
class KotlinCodableTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        syntaxTree.root.visit {
            if let classDeclaration = $0 as? KotlinClassDeclaration {
                if classDeclaration.declarationType == .enumDeclaration && classDeclaration.inherits.contains(.codingKey) {
                    fixupCodingKey(enumDeclaration: classDeclaration)
                } else {
                    synthesizeCodable(for: classDeclaration, source: translator.syntaxTree.source)
                }
            }
            return .recurse(nil)
        }
    }

    private func synthesizeCodable(for classDeclaration: KotlinClassDeclaration, source: Source) {
        // We don't need to worry about extensions because they will have already been merged into the class
        let isEncodable = classDeclaration.inherits.contains(.codable) || classDeclaration.inherits.contains(.encodable)
        let isDecodable = classDeclaration.inherits.contains(.codable) || classDeclaration.inherits.contains(.decodable)
        guard isEncodable || isDecodable else {
            return
        }

        var encodeDeclaration: KotlinFunctionDeclaration? = nil
        if isEncodable {
            encodeDeclaration = classDeclaration.members.first {
                guard let functionDeclaration = $0 as? KotlinFunctionDeclaration else {
                    return false
                }
                return functionDeclaration.name == "encode" && functionDeclaration.parameters.count == 1 && functionDeclaration.parameters[0].externalLabel == "to" && functionDeclaration.parameters[0].declaredType == .named("Encoder", [])
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
                return functionDeclaration.type == .constructorDeclaration && functionDeclaration.parameters.count == 1 && functionDeclaration.parameters[0].externalLabel == "from" && functionDeclaration.parameters[0].declaredType == .named("Decoder", [])
            } as? KotlinFunctionDeclaration
            decodeDeclaration?.modifiers.visibility = .public
        }

        if (isEncodable && encodeDeclaration == nil) || (isDecodable && decodeDeclaration == nil) {
            // The developer may use a bespoke name for their coding keys enum if they implement their own encode/decode,
            // so we only synthesize or look for coding keys after knowing we need to generate a coding function
            let rawValueType = classDeclaration.rawValueType
            let codingKeys = synthesizeCodingKeys(for: classDeclaration, rawValueType: rawValueType, isDecodable: isDecodable)
            let typedCodingKeys = codingKeys.map { $0.map { ($0, propertyType(for: $0, in: classDeclaration, source: source)) } }
            if isEncodable && encodeDeclaration == nil {
                synthesizeEncode(for: classDeclaration, codingKeys: typedCodingKeys, rawValueType: rawValueType, source: source)
            }
            if isDecodable && decodeDeclaration == nil {
                synthesizeDecode(for: classDeclaration, codingKeys: typedCodingKeys, rawValueType: rawValueType, source: source)
            }
        }
        if isDecodable {
            synthesizeDecodableCompanion(for: classDeclaration)
        }
    }

    private func synthesizeCodingKeys(for classDeclaration: KotlinClassDeclaration, rawValueType: TypeSignature, isDecodable: Bool) -> [KotlinEnumCaseDeclaration]? {
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

        // Create cases for all stored variables
        var storedVariableDeclarations: [KotlinVariableDeclaration] = []
        for member in classDeclaration.members {
            guard let variableDeclaration = member as? KotlinVariableDeclaration, !variableDeclaration.isStatic && !variableDeclaration.isGenerated else {
                continue
            }
            guard variableDeclaration.getter == nil else {
                continue
            }
            if isDecodable && variableDeclaration.value != nil {
                // Make let vars writeable so that we can decode them. We decode in a constructor, so this is only needed
                // if the vars have initial values that would otherwise not be re-assignable
                variableDeclaration.isAssignFromWriteable = true
            }
            storedVariableDeclarations.append(variableDeclaration)
        }

        let enumDeclaration = KotlinClassDeclaration(name: "CodingKeys", signature: .named("CodingKeys", []), declarationType: .enumDeclaration)
        enumDeclaration.inherits = [.string, .codingKey]
        enumDeclaration.modifiers.visibility = .private
        enumDeclaration.extras = .singleNewline
        enumDeclaration.isGenerated = true
        let caseDeclarations = storedVariableDeclarations.map {
            KotlinEnumCaseDeclaration(name: $0.propertyName)
        }
        enumDeclaration.members = caseDeclarations
        enumDeclaration.processEnumCaseDeclarations()

        classDeclaration.members.append(enumDeclaration)
        enumDeclaration.parent = classDeclaration
        enumDeclaration.assignParentReferences()
        return caseDeclarations
    }

    private func fixupCodingKey(enumDeclaration: KotlinClassDeclaration) {
        // Coding keys are strings by default
        if enumDeclaration.enumInheritedRawValueType == .none {
            enumDeclaration.inherits.insert(.string, at: 0)
            enumDeclaration.processEnumCaseDeclarations()
        }
    }

    private func synthesizeEncode(for classDeclaration: KotlinClassDeclaration, codingKeys: [(KotlinEnumCaseDeclaration, TypeSignature)]?, rawValueType: TypeSignature, source: Source) {
        let encode = KotlinFunctionDeclaration(name: "encode")
        encode.extras = .singleNewline
        encode.modifiers.visibility = .public
        encode.modifiers.isOverride = true
        encode.isGenerated = true
        encode.parameters = [Parameter<KotlinExpression>(externalLabel: "to", declaredType: .named("Encoder", []))]

        var statements: [KotlinStatement] = []
        if let codingKeys {
            statements.append(KotlinRawStatement(sourceCode: "val container = to.container(keyedBy = CodingKeys::class)"))
            statements += codingKeys.map {
                let encodeFunction = $0.1.isOptional ? "encodeIfPresent" : "encode"
                return KotlinRawStatement(sourceCode: "container.\(encodeFunction)(\($0.0.name), forKey = CodingKeys.\($0.0.name))")
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

    private func synthesizeDecode(for classDeclaration: KotlinClassDeclaration, codingKeys: [(KotlinEnumCaseDeclaration, TypeSignature)]?, rawValueType: TypeSignature, source: Source) {
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
        if let codingKeys {
            if !codingKeys.isEmpty {
                statements.append(KotlinRawStatement(sourceCode: "val container = from.container(keyedBy = CodingKeys::class)"))
            }
            statements += codingKeys.map {
                let type = $0.1
                let decodeFunction = type.isOptional ? "decodeIfPresent" : "decode"
                let decodeType = type.asOptional(false).withGenerics([])
                return KotlinRawStatement(sourceCode: "this.\($0.0.name) = container.\(decodeFunction)(\(decodeType.kotlin)::class, forKey = CodingKeys.\($0.0.name))")
            }
            decode.body = KotlinCodeBlock(statements: statements)

            classDeclaration.members.append(decode)
            decode.parent = classDeclaration
        } else if rawValueType != .none {
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

            (classDeclaration.parent as? KotlinStatement)?.insert(statements: [decode], after: classDeclaration)
        } else {
            classDeclaration.messages.append(.kotlinCodableDecodeRawValueEnumsOnly(classDeclaration, source: source))
            return
        }
        decode.assignParentReferences()
    }

    private func synthesizeDecodableCompanion(for classDeclaration: KotlinClassDeclaration) {
        classDeclaration.companionInherits.append(.named("DecodableCompanion", []))

        let factory = KotlinFunctionDeclaration(name: "init")
        factory.extras = .singleNewline
        factory.modifiers.visibility = .public
        factory.modifiers.isStatic = true
        factory.modifiers.isOverride = true
        factory.isGenerated = true
        factory.parameters = [Parameter<KotlinExpression>(externalLabel: "from", declaredType: .named("Decoder", []))]
        factory.returnType = .any

        let statement = KotlinRawStatement(sourceCode: "return \(classDeclaration.signature.kotlin)(from = from)")
        factory.body = KotlinCodeBlock(statements: [statement])

        classDeclaration.members.append(factory)
        factory.parent = classDeclaration
        factory.assignParentReferences()
    }

    private func propertyType(for codingKey: KotlinEnumCaseDeclaration, in classDeclaration: KotlinClassDeclaration, source: Source) -> TypeSignature {
        guard let variableDeclaration = classDeclaration.members.first(where: { ($0 as? KotlinVariableDeclaration)?.propertyName == codingKey.name }) as? KotlinVariableDeclaration else {
            codingKey.messages.append(.kotlinCodablePropertyForKey(codingKey, source: source))
            return .any
        }
        guard variableDeclaration.propertyType != .none else {
            variableDeclaration.messages.append(.kotlinCodablePropertyType(variableDeclaration, source: source))
            return .any
        }
        return variableDeclaration.propertyType
    }
}
