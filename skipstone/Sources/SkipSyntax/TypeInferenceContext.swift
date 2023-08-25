/// Contextual information used in type inference.
struct TypeInferenceContext {
    private let codebaseInfo: CodebaseInfo.Context?
    private let unavailableAPI: UnavailableAPI?
    private var path: [PathEntry] = []
    private var localIdentifierTypes: [String: TypeSignature] = [:]
    private struct PathEntry {
        var typeSignature: TypeSignature?
        var superSignature: TypeSignature?
        var isStatic = false
    }

    /// Context source.
    let source: Source

    /// Create a top-level context for type inference.
    ///
    /// - Parameters:
    ///   - codebaseInfo: Available codebase information.
    ///   - unavailableAPI: Known unavailable API to use when `codebaseInfo` is not available.
    ///   - source: Source for this context.
    init(codebaseInfo: CodebaseInfo.Context? = nil, unavailableAPI: UnavailableAPI?, source: Source) {
        self.codebaseInfo = codebaseInfo
        self.unavailableAPI = unavailableAPI
        self.source = source
    }

    /// The type we're expecting to return from the current code block.
    private(set) var expectedReturn: TypeSignature = .none

    /// The current generic constraints.
    private(set) var generics = Generics()

    /// Return a context for evaluating members of the given type.
    func pushing(_ typeDeclaration: TypeDeclaration) -> TypeInferenceContext {
        var context = self
        context.path.append(PathEntry(typeSignature: typeDeclaration.signature, superSignature: typeDeclaration.type == .classDeclaration ? typeDeclaration.inherits.first : nil))
        context.generics = context.generics.merge(overrides: typeDeclaration.generics, addNew: true)
        return context
    }

    /// Return a context for evaluating members of the given type.
    func pushing(_ typeInfo: CodebaseInfo.TypeInfo) -> TypeInferenceContext {
        var context = self
        context.path.append(PathEntry(typeSignature: typeInfo.signature, superSignature: typeInfo.declarationType == .classDeclaration ? typeInfo.inherits.first : nil))
        context.generics = context.generics.merge(overrides: typeInfo.generics, addNew: true)
        return context
    }

    /// Return a context for evaluating the code of the given function.
    func pushing(_ functionDeclaration: FunctionDeclaration) -> TypeInferenceContext {
        let parameterDictionary = functionDeclaration.parameters.reduce(into: [String: TypeSignature]()) { result, parameter in
            result[parameter.internalLabel] = parameter.declaredType
        }
        var context = addingIdentifiers(parameterDictionary)
        context.expectedReturn = functionDeclaration.returnType
        if functionDeclaration.modifiers.isStatic, let lastTypePathIndex = context.path.lastIndex(where: { $0.typeSignature != nil }) {
            context.path[lastTypePathIndex].isStatic = true
        }
        context.generics = context.generics.merge(overrides: functionDeclaration.generics, addNew: true)
        return context
    }

    /// Return a context for evaluating the code of the given closure.
    func pushing(_ closure: Closure) -> TypeInferenceContext {
        var parameterDictionary: [String: TypeSignature] = [:]
        // Add captured values to context
        for (captureType, value) in closure.captureList {
            var type = value.value.inferredType
            if captureType == .weak {
                type = type.asOptional(true)
            }
            if let label = value.label {
                parameterDictionary[label] = type
            } else if let identifier = value.value as? Identifier {
                parameterDictionary[identifier.name] = type
            }
        }
        // Add parameters. Use inferred type because we'll already have done our best if the parameter types are not declared
        if !closure.inferredType.parameters.isEmpty {
            let declaredParameters = closure.parameters
            parameterDictionary = closure.inferredType.parameters.enumerated().reduce(into: parameterDictionary) { result, indexedParameter in
                if declaredParameters.count > indexedParameter.0 {
                    result[declaredParameters[indexedParameter.0].internalLabel] = indexedParameter.1.type
                } else {
                    result["$\(indexedParameter.0)"] = indexedParameter.1.type
                }
            }
        }
        var context = addingIdentifiers(parameterDictionary)
        context.expectedReturn = closure.returnType.or(closure.inferredType.returnType)
        return context
    }

    /// Return a context for evaluating code within a block with the given additional identiifers.
    func pushingBlock(identifiers: [String: TypeSignature]) -> TypeInferenceContext {
        guard !identifiers.isEmpty else {
            return self
        }
        return addingIdentifiers(identifiers)
    }

    /// Return a context expecting the given type to be returned from the current code block.
    func expectingReturn(_ returnType: TypeSignature) -> TypeInferenceContext {
        var context = self
        context.expectedReturn = returnType
        return context
    }

    /// Return a context that includes the given identifier.
    func addingIdentifier(_ name: String, type: TypeSignature) -> TypeInferenceContext {
        var context = self
        context.localIdentifierTypes[name] = type
        return context
    }

    /// Return a context that includes the given identifiers.
    func addingIdentifiers(_ names: [String?], types: [TypeSignature]) -> TypeInferenceContext {
        var context = self
        for nameAndType in zip(names, types) {
            if let name = nameAndType.0 {
                context.localIdentifierTypes[name] = nameAndType.1
            }
        }
        return context
    }

    /// Return a context that includes the given identifiers.
    func addingIdentifiers(_ identifiers: [String: TypeSignature]) -> TypeInferenceContext {
        var context = self
        context.localIdentifierTypes.merge(identifiers) { _, new in new }
        return context
    }

    /// Return a context that includes the given local function.
    func addingLocalFunction(_ function: FunctionDeclaration) -> TypeInferenceContext {
        // Warn for duplicated local functions
        if localIdentifierTypes[function.name] != nil {
            function.messages.append(.localFunctionsUniqueIdentifiers(function, source: source))
        }
        return addingIdentifier(function.name, type: function.functionType)
    }

    /// Return the type of the given identifier.
    func identifier(_ name: String, messagesNode: SyntaxNode?) -> (TypeSignature, APIMatch)? {
        var name = name
        var isBinding = false
        if name.hasPrefix("$") {
            let suffix = String(name.dropFirst())
            // Filter implicit closure arguments: $0, $1, etc
            if Int(suffix) == nil {
                name = suffix
                isBinding = true
            }
        }

        // Check local identifiers and bindings
        if let identifierType = localIdentifierTypes[name] {
            var signature = identifierType.constrainedTypeWithGenerics(generics)
            if isBinding {
                signature = signature.asBinding()
            }
            return (signature, APIMatch(signature: signature))
        }
        if name == "self" || name == "Self" || name == "super" {
            guard let pathEntry = path.last(where: { $0.typeSignature != nil }), let typeSignature = pathEntry.typeSignature else {
                return nil
            }
            if name == "super" {
                var superSignature: TypeSignature? = pathEntry.superSignature
                if superSignature == nil {
                    superSignature = codebaseInfo?.primaryTypeInfo(forNamed: typeSignature)?.inherits.first
                }
                if let superSignature {
                    let constrainedSuperSignature = superSignature.constrainedTypeWithGenerics(generics)
                    return (constrainedSuperSignature, APIMatch(signature: constrainedSuperSignature))
                } else {
                    return nil
                }
            } else {
                let signature = typeSignature.constrainedTypeWithGenerics(generics).asMetaType(name == "Self" || pathEntry.isStatic)
                return (signature, APIMatch(signature: signature))
            }
        }

        for pathEntry in path.reversed() {
            guard let typeSignature = pathEntry.typeSignature else {
                continue
            }
            let signature = typeSignature.asMetaType(pathEntry.isStatic)
            if let codebaseInfo {
                if let match = codebaseInfo.matchIdentifier(name: name, inConstrained: signature.constrainedTypeWithGenerics(generics)) {
                    addUnavailableMessages(to: messagesNode, for: [match.availability])
                    return update((resolveSignature(match: match), match), isBinding: isBinding)
                }
            } else if let match = unavailableAPI?.knownUnavailableMember(name, in: signature) {
                addUnavailableMessages(to: messagesNode, for: [match.availability])
                return update((resolveSignature(match: match), match), isBinding: isBinding)
            }
        }
        let genericType = generics.constrainedType(of: name)
        if genericType != .none {
            return (genericType, APIMatch(signature: genericType))
        }
        if let codebaseInfo {
            if let match = codebaseInfo.matchIdentifier(name: name) {
                addUnavailableMessages(to: messagesNode, for: [match.availability])
                return update((resolveSignature(match: match), match), isBinding: isBinding)
            } else {
                return nil
            }
        } else if let match = unavailableAPI?.knownUnavailableIdentifier(name) {
            addUnavailableMessages(to: messagesNode, for: [match.availability])
            return update((resolveSignature(match: match), match), isBinding: isBinding)
        } else if !isBinding {
            let signature = TypeSignature.for(name: name, genericTypes: [], allowNamed: false).asMetaType(true)
            return signature == .none ? nil : (signature, APIMatch(signature: signature))
        } else {
            return nil
        }
    }

    /// Whether the given name maps to a local identifier or parameter.
    func isLocalOrSelfIdentifier(_ name: String) -> Bool {
        if name == "self" {
            return true
        }
        if localIdentifierTypes.keys.contains(name) {
            return true
        }
        return false
    }

    /// Return the type of the given member.
    ///
    /// The returned signature may be different than the returned `APIMatch.signature` due to optional chaining and type aliasing.
    func member(_ name: String, in type: TypeSignature, messagesNode: SyntaxNode?) -> (TypeSignature, APIMatch)? {
        var type = type
        var name = name
        var isBinding = false
        if case .named("Binding", let generics) = type, generics.count == 1 {
            isBinding = true
            type = generics[0]
        } else if name.hasPrefix("$") {
            isBinding = true
            name = String(name.dropFirst())
        }

        if type.isOptional {
            if let match = member(name, inNonOptional: type.asOptional(false), messagesNode: messagesNode) {
                return update((resolveSignature(match: match).asOptional(true), match), isBinding: isBinding)
            } else {
                return nil
            }
        } else {
            if let match = member(name, inNonOptional: type, messagesNode: messagesNode) {
                return update((resolveSignature(match: match), match), isBinding: isBinding)
            } else {
                return nil
            }
        }
    }

    private func member(_ name: String, inNonOptional type: TypeSignature, messagesNode: SyntaxNode?) -> APIMatch? {
        if case .tuple(let labels, let types) = type {
            if let labelIndex = labels.firstIndex(of: name) {
                return APIMatch(signature: types[labelIndex].constrainedTypeWithGenerics(generics))
            } else if let index = Int(name) {
                return APIMatch(signature: types[index].constrainedTypeWithGenerics(generics))
            }
        }
        if name == "self" || name == "Type" {
            return APIMatch(signature: type.constrainedTypeWithGenerics(generics).asMetaType(true))
        }
        guard let codebaseInfo else {
            return nil
        }
        if let match = codebaseInfo.matchIdentifier(name: name, inConstrained: type.constrainedTypeWithGenerics(generics)) {
            addUnavailableMessages(to: messagesNode, for: [match.availability])
            return match
        } else {
            return nil
        }
    }

    /// Return the signatures of the functions matching the given arguments.
    ///
    /// The match on the argument types will attempt to allow for unknown types. The returned signatures may be different than the returned `APIMatch.signatures` due to optional chaining.
    ///
    /// - Parameters:
    ///   - name: The function name, or `nil` if none, as in constructor calls.
    ///   - type: The function's owning type if this is a member function, or nil if not.
    func function(_ name: String?, in type: TypeSignature?, arguments: [LabeledValue<Expression>], expectedReturn: TypeSignature, messagesNode: SyntaxNode?) -> (TypeSignature, APIMatch)? {
        let argumentTypes = arguments.map { LabeledValue(label: $0.label, value: $0.value.inferredType) }
        let matches = function(name, in: type, arguments: argumentTypes, messagesNode: messagesNode)
        if matches.count > 1 {
            if let match = findUnqualifiedArgumentMatch(in: matches, arguments: arguments) {
                return match
            }
            if let messagesNode {
                messagesNode.messages.append(.ambiguousFunctionCall(messagesNode, source: source))
            }
        }
        return matches.first { $0.0.returnType == expectedReturn } ?? matches.first
    }

    // Exposed for testing
    func function(_ name: String?, in type: TypeSignature?, arguments: [LabeledValue<TypeSignature>], messagesNode: SyntaxNode?) -> [(TypeSignature, APIMatch)] {
        if let type, type.isOptional {
            return function(name, inNonOptional: type.asOptional(false), arguments: arguments, messagesNode: messagesNode).map { match in
                let signature = resolveSignature(match: match)
                return (.function(signature.parameters, signature.returnType.asOptional(true), signature.apiFlags, signature.additionalAttributes), match)
            }
        } else {
            return function(name, inNonOptional: type, arguments: arguments, messagesNode: messagesNode).map { (resolveSignature(match: $0), $0) }
        }
    }

    private func function(_ name: String?, inNonOptional type: TypeSignature?, arguments: [LabeledValue<TypeSignature>], messagesNode: SyntaxNode?) -> [APIMatch] {
        let constrainedArguments = arguments.map { LabeledValue(label: $0.label, value: $0.value.constrainedTypeWithGenerics(generics)) }
        if let type {
            if let codebaseInfo {
                let matches = codebaseInfo.matchFunction(name: name, inConstrained: type.constrainedTypeWithGenerics(generics), arguments: constrainedArguments)
                addUnavailableMessages(to: messagesNode, for: matches.map(\.availability))
                return matches
            } else if let match = unavailableAPI?.knownUnavailableFunction(name ?? "init", in: type, arguments: arguments) {
                addUnavailableMessages(to: messagesNode, for: [match.availability])
                return [match]
            } else {
                return []
            }
        }
        guard let name else {
            return []
        }

        // Not a known member function. Check functions that can be invoked without a target type
        if let localFunction = localIdentifierTypes[name], case .function = localFunction {
            if let codebaseInfo {
                if let callSignature = codebaseInfo.callableSignature(of: localFunction, generics: generics, arguments: constrainedArguments) {
                    return [APIMatch(signature: callSignature, apiFlags: localFunction.apiFlags, declarationType: .functionDeclaration)]
                }
            } else {
                return []
            }
        }
        for pathEntry in path.reversed() {
            guard let typeSignature = pathEntry.typeSignature else {
                continue
            }
            let signature = typeSignature.asMetaType(pathEntry.isStatic)
            if let codebaseInfo {
                let matches = codebaseInfo.matchFunction(name: name, inConstrained: signature.constrainedTypeWithGenerics(generics), arguments: constrainedArguments)
                if !matches.isEmpty {
                    addUnavailableMessages(to: messagesNode, for: matches.map(\.availability))
                    return matches
                }
            } else if let match = unavailableAPI?.knownUnavailableFunction(name, in: signature, arguments: arguments) {
                addUnavailableMessages(to: messagesNode, for: [match.availability])
                return [match]
            }
        }
        if let codebaseInfo {
            let matches = codebaseInfo.matchFunction(name: name, arguments: constrainedArguments)
            addUnavailableMessages(to: messagesNode, for: matches.map(\.availability))
            return matches
        } else if let match = unavailableAPI?.knownUnavailableFunction(name, in: nil, arguments: arguments) {
            addUnavailableMessages(to: messagesNode, for: [match.availability])
            return [match]
        } else {
            return []
        }
    }

    /// Return the signatures of the subscripts matching the given parameters.
    ///
    /// The match on the parameter types will attempt to allow for unknown types. The returned signatures may be different than the returned `APIMatch.signatures` due to optional chaining.
    ///
    /// - Parameters:
    ///   - type: The subscript's owning type.
    func `subscript`(in type: TypeSignature, arguments: [LabeledValue<Expression>], expectedReturn: TypeSignature, messagesNode: SyntaxNode?) -> (TypeSignature, APIMatch)? {
        let argumentTypes = arguments.map { LabeledValue(label: $0.label, value: $0.value.inferredType) }
        let matches = self.subscript(in: type, arguments: argumentTypes, messagesNode: messagesNode)
        if matches.count > 1 {
            if let match = findUnqualifiedArgumentMatch(in: matches, arguments: arguments) {
                return match
            }
            if let messagesNode {
                messagesNode.messages.append(.ambiguousFunctionCall(messagesNode, source: source))
            }
        }
        return matches.first { $0.0.returnType == expectedReturn } ?? matches.first
    }

    // Exposed for testing
    func `subscript`(in type: TypeSignature, arguments: [LabeledValue<TypeSignature>], messagesNode: SyntaxNode?) -> [(TypeSignature, APIMatch)] {
        if type.isOptional {
            return self.subscript(inNonOptional: type.asOptional(false), arguments: arguments, messagesNode: messagesNode).map { match in
                let signature = resolveSignature(match: match)
                return (.function(signature.parameters, signature.returnType.asOptional(true), signature.apiFlags, signature.additionalAttributes), match)
            }
        } else {
            return self.subscript(inNonOptional: type, arguments: arguments, messagesNode: messagesNode).map { (resolveSignature(match: $0), $0) }
        }
    }

    private func `subscript`(inNonOptional type: TypeSignature, arguments: [LabeledValue<TypeSignature>], messagesNode: SyntaxNode?) -> [APIMatch] {
        if let codebaseInfo {
            let constrainedArguments = arguments.map { LabeledValue(label: $0.label, value: $0.value.constrainedTypeWithGenerics(generics)) }
            let matches = codebaseInfo.matchSubscript(inConstrained: type.constrainedTypeWithGenerics(generics), arguments: constrainedArguments)
            addUnavailableMessages(to: messagesNode, for: matches.map(\.availability))
            return matches
        } else if let match = unavailableAPI?.knownUnavailableFunction("subscript", in: type, arguments: arguments) {
            addUnavailableMessages(to: messagesNode, for: [match.availability])
            return [match]
        } else {
            return []
        }
    }

    /// Determine the element type of the given type, correctly handling custom sequences.
    func elementType(of type: TypeSignature) -> TypeSignature {
        let builtinType = type.elementType
        guard builtinType == .none else {
            return builtinType
        }
        guard let makeIteratorMatch = function("makeIterator", in: type, arguments: [], messagesNode: nil).first ?? function("makeAsyncIterator", in: type, arguments: [], messagesNode: nil).first else {
            return .none
        }
        guard let nextMatch = function("next", in: makeIteratorMatch.0.returnType, arguments: [], messagesNode: nil).first else {
            return .none
        }
        return nextMatch.0.returnType.asOptional(false)
    }

    /// For an operation on two types, return the probable result type.
    func operationResult(_ type1: TypeSignature, _ type2: TypeSignature) -> TypeSignature {
        let type1 = type1.constrainedTypeWithGenerics(generics).asTypealiased(nil).withoutOptionality().withModuleName(nil)
        let type2 = type2.constrainedTypeWithGenerics(generics).asTypealiased(nil).withoutOptionality().withModuleName(nil)
        if type1 == type2 {
            return type1
        }
        if type1 == .none {
            return type2
        }
        if type2 == .none {
            return type1
        }

        switch type1 {
        case .array(let elementType1):
            if case .array(let elementType2) = type2 {
                return .array(operationResult(elementType1, elementType2))
            }
            if case .set(let elementType2) = type2 {
                return .set(operationResult(elementType1, elementType2))
            }
            return type1
        case .character:
            return type2.isStringy ? .string : type1
        case .dictionary(let keyType1, let valueType1):
            if case .dictionary(let keyType2, let valueType2) = type2 {
                return .dictionary(operationResult(keyType1, keyType2), operationResult(valueType1, valueType2))
            }
            return type1
        case .double:
            return type2.isNumeric ? .double : type1
        case .float:
            return type2 == .double ? .double : type1
        case .int:
            return type2.isFloatingPoint ? type2 : type1
        case .int8:
            return type2.isFloatingPoint ? type2 : type1
        case .int16:
            return type2.isFloatingPoint ? type2 : type1
        case .int32:
            return type2.isFloatingPoint ? type2 : type1
        case .int64:
            return type2.isFloatingPoint ? type2 : type1
        case .set(let elementType1):
            if case .array(let elementType2) = type2 {
                return .array(operationResult(elementType1, elementType2))
            }
            if case .set(let elementType2) = type2 {
                return .set(operationResult(elementType1, elementType2))
            }
            return type1
        case .string:
            return type2.isStringy ? .string : type1
        case .uint:
            return type2.isFloatingPoint ? type2 : type1
        case .uint8:
            return type2.isFloatingPoint ? type2 : type1
        case .uint16:
            return type2.isFloatingPoint ? type2 : type1
        case .uint32:
            return type2.isFloatingPoint ? type2 : type1
        case .uint64:
            return type2.isFloatingPoint ? type2 : type1
        default:
            return type1
        }
    }

    private func findUnqualifiedArgumentMatch(in matches: [(TypeSignature, APIMatch)], arguments: [LabeledValue<Expression>]) -> (TypeSignature, APIMatch)? {
        // Look for arguments that are unqualified member accesses and see if we can match them to members
        for i in 0..<arguments.count {
            guard arguments[i].value.inferredType == .none, let memberAccess = arguments[i].value as? MemberAccess, memberAccess.base == nil else {
                continue
            }
            for match in matches {
                let parameters = match.0.parameters
                if parameters.count > i && parameters[i].type != .none && member(memberAccess.member, in: parameters[i].type.asMetaType(true), messagesNode: nil) != nil {
                    return match
                }
            }
        }
        return nil
    }

    private func resolveSignature(match: APIMatch) -> TypeSignature {
        return codebaseInfo?.resolveTypealias(for: match.signature) ?? match.signature
    }

    private func update(_ match: (TypeSignature, APIMatch), isBinding: Bool) -> (TypeSignature, APIMatch) {
        guard isBinding else {
            return match
        }
        var bindingAPIMatch = match.1
        bindingAPIMatch.signature = bindingAPIMatch.signature.asBinding()
        return (match.0.asBinding(), bindingAPIMatch)
    }

    private func addUnavailableMessages(to messagesNode: SyntaxNode?, for availability: [Availability]) {
        guard let messagesNode, !availability.isEmpty else {
            return
        }
        if availability.allSatisfy({ if case .unavailable = $0 { return true } else { return false } }) {
            if case .unavailable(let message) = availability[0] {
                if codebaseInfo != nil {
                    messagesNode.messages.append(.availabilityUnavailable(message: message, sourceDerived: messagesNode, source: source))
                } else {
                    messagesNode.messages.append(.availabilityMaybeUnavailable(message: message, sourceDerived: messagesNode, source: source))
                }
            }
        } else if availability.allSatisfy({ if case .deprecated = $0 { return true } else { return false } }) {
            if case .deprecated(let message) = availability[0] {
                messagesNode.messages.append(.availabilityDeprecated(message: message, sourceDerived: messagesNode, source: source))
            }
        }
    }
}
