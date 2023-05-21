/// Contextual information used in type inference.
struct TypeInferenceContext {
    private let codebaseInfo: CodebaseInfo.Context?
    private let unavailableAPI: UnavailableAPI?
    private var path: [PathEntry] = []
    private var localIdentifierTypes: [String: TypeSignature] = [:]
    private struct PathEntry {
        var typeDeclaration: TypeDeclaration? = nil
        var isStatic = false
        var identifiers: [String: TypeSignature] = [:]
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
        context.path.append(PathEntry(typeDeclaration: typeDeclaration))
        context.generics = context.generics.merge(overrides: typeDeclaration.generics, addNew: true)
        return context
    }

    /// Return a context for evaluating the code of the given function.
    func pushing(_ functionDeclaration: FunctionDeclaration) -> TypeInferenceContext {
        var context = self
        let parameterDictionary = functionDeclaration.parameters.reduce(into: [String: TypeSignature]()) { result, parameter in
            result[parameter.internalLabel] = parameter.declaredType
        }
        context.expectedReturn = functionDeclaration.returnType
        if functionDeclaration.modifiers.isStatic, let lastTypePathIndex = context.path.lastIndex(where: { $0.typeDeclaration != nil }) {
            context.path[lastTypePathIndex].isStatic = true
        }
        context.path.append(PathEntry(identifiers: parameterDictionary))
        context.generics = context.generics.merge(overrides: functionDeclaration.generics, addNew: true)
        return context
    }

    /// Return a context for evaluating the code of the given closure.
    func pushing(_ closure: Closure) -> TypeInferenceContext {
        var context = self
        var parameterDictionary: [String: TypeSignature] = [:]
        // Use the inferred type because we'll already have done our best if the parameter types are not declared
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
        context.path.append(PathEntry(identifiers: parameterDictionary))
        context.expectedReturn = closure.returnType.or(closure.inferredType.returnType)
        return context
    }

    /// Return a context for evaluating code within a block with the given additional identiifers.
    func pushingBlock(identifiers: [String: TypeSignature]) -> TypeInferenceContext {
        guard !identifiers.isEmpty else {
            return self
        }
        var context = self
        context.path.append(PathEntry(identifiers: identifiers))
        return context
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
    func identifier(_ name: String, messagesNode: SyntaxNode?) -> TypeSignature {
        // First check local identifiers
        if let identifierType = localIdentifierTypes[name] {
            return identifierType.constrainedTypeWithGenerics(generics)
        }
        // Next check function / closure / block bindings
        for pathEntry in path.reversed() {
            if let identifierType = pathEntry.identifiers[name] {
                return identifierType.constrainedTypeWithGenerics(generics)
            }
        }
        if name == "self" || name == "Self" || name == "super" {
            guard let pathEntry = path.last(where: { $0.typeDeclaration != nil }), let typeDeclaration = pathEntry.typeDeclaration else {
                return .none
            }
            if name == "super" {
                return typeDeclaration.inherits.first?.constrainedTypeWithGenerics(generics) ?? .none
            } else if name == "Self" || pathEntry.isStatic {
                return typeDeclaration.signature.constrainedTypeWithGenerics(generics).asMetaType(true)
            } else {
                return typeDeclaration.signature.constrainedTypeWithGenerics(generics)
            }
        }

        for pathEntry in path.reversed() {
            guard let typeDeclaration = pathEntry.typeDeclaration else {
                continue
            }
            let signature = typeDeclaration.signature.asMetaType(pathEntry.isStatic)
            if let codebaseInfo {
                if let match = codebaseInfo.matchIdentifier(name: name, inConstrained: signature.constrainedTypeWithGenerics(generics)) {
                    addMessages(to: messagesNode, for: [match.availability])
                    return match.signature
                }
            } else if let match = unavailableAPI?.knownUnavailableMember(name, in: signature) {
                addMessages(to: messagesNode, for: [match.availability])
                return match.signature
            }
        }
        if let codebaseInfo {
            if let match = codebaseInfo.matchIdentifier(name: name) {
                addMessages(to: messagesNode, for: [match.availability])
                return match.signature
            } else {
                return .none
            }
        } else if let match = unavailableAPI?.knownUnavailableIdentifier(name) {
            addMessages(to: messagesNode, for: [match.availability])
            return match.signature
        } else {
            return TypeSignature.for(name: name, genericTypes: [], allowNamed: false).asMetaType(true)
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
        for pathEntry in path.reversed() {
            if pathEntry.identifiers.keys.contains(name) {
                return true
            }
        }
        return false
    }

    /// Return the type of the given member.
    func member(_ name: String, in type: TypeSignature, messagesNode: SyntaxNode?) -> TypeSignature {
        if type.isOptional {
            let result = member(name, inNonOptional: type.asOptional(false), messagesNode: messagesNode)
            return result.asOptional(true)
        } else {
            return member(name, inNonOptional: type, messagesNode: messagesNode)
        }
    }

    private func member(_ name: String, inNonOptional type: TypeSignature, messagesNode: SyntaxNode?) -> TypeSignature {
        if case .tuple(let labels, let types) = type {
            if let labelIndex = labels.firstIndex(of: name) {
                return types[labelIndex].constrainedTypeWithGenerics(generics)
            } else if let index = Int(name) {
                return types[index].constrainedTypeWithGenerics(generics)
            }
        }
        if name == "self" || name == "Type" {
            return type.constrainedTypeWithGenerics(generics).asMetaType(true)
        }
        guard let codebaseInfo else {
            return .none
        }
        if let match = codebaseInfo.matchIdentifier(name: name, inConstrained: type.constrainedTypeWithGenerics(generics)) {
            addMessages(to: messagesNode, for: [match.availability])
            return match.signature
        } else {
            return .none
        }
    }

    /// Return the signatures of the functions matching the given parameters, and whether each is an init call.
    ///
    /// The match on the parameter types will attempt to allow for unknown types.
    ///
    /// - Parameters:
    ///   - type: The function's owning type if this is a member function, or nil if not.
    func function(_ name: String, in type: TypeSignature?, parameters: [LabeledValue<TypeSignature>], messagesNode: SyntaxNode?) -> [(TypeSignature, StatementType?)] {
        if let type, type.isOptional {
            return function(name, inNonOptional: type.asOptional(false), parameters: parameters, messagesNode: messagesNode).map {
                (.function($0.0.parameters, $0.0.returnType.asOptional(true)), $0.1)
            }
        } else {
            return function(name, inNonOptional: type, parameters: parameters, messagesNode: messagesNode)
        }
    }

    private func function(_ name: String, inNonOptional type: TypeSignature?, parameters: [LabeledValue<TypeSignature>], messagesNode: SyntaxNode?) -> [(TypeSignature, StatementType?)] {
        let constrainedArguments = parameters.map { LabeledValue(label: $0.label, value: $0.value.constrainedTypeWithGenerics(generics)) }
        if let type {
            if let codebaseInfo {
                let matches = codebaseInfo.matchFunction(name: name, inConstrained: type.constrainedTypeWithGenerics(generics), arguments: constrainedArguments)
                addMessages(to: messagesNode, for: matches.map(\.availability))
                return matches.map { ($0.signature, $0.declarationType) }
            } else if let match = unavailableAPI?.knownUnavailableFunction(name, in: type, parameters: parameters) {
                addMessages(to: messagesNode, for: [match.availability])
                return [(match.signature, match.declarationType)]
            } else {
                return []
            }
        }

        // Not a known member function. Check functions that can be invoked without a target type
        if let localFunction = localIdentifierTypes[name], case .function = localFunction {
            if let codebaseInfo {
                if let callSignature = codebaseInfo.callableSignature(of: localFunction, generics: generics, arguments: constrainedArguments) {
                    return [(callSignature, .functionDeclaration)]
                }
            } else {
                return []
            }
        }
        for pathEntry in path.reversed() {
            guard let typeDeclaration = pathEntry.typeDeclaration else {
                continue
            }
            let signature = typeDeclaration.signature.asMetaType(pathEntry.isStatic)
            if let codebaseInfo {
                let matches = codebaseInfo.matchFunction(name: name, inConstrained: signature.constrainedTypeWithGenerics(generics), arguments: constrainedArguments)
                if !matches.isEmpty {
                    addMessages(to: messagesNode, for: matches.map(\.availability))
                    return matches.map { ($0.signature, $0.declarationType) }
                }
            } else if let match = unavailableAPI?.knownUnavailableFunction(name, in: signature, parameters: parameters) {
                addMessages(to: messagesNode, for: [match.availability])
                return [(match.signature, match.declarationType)]
            }
        }
        if let codebaseInfo {
            let matches = codebaseInfo.matchFunction(name: name, arguments: constrainedArguments)
            addMessages(to: messagesNode, for: matches.map(\.availability))
            return matches.map { ($0.signature, $0.declarationType) }
        } else if let match = unavailableAPI?.knownUnavailableFunction(name, in: nil, parameters: parameters) {
            addMessages(to: messagesNode, for: [match.availability])
            return [(match.signature, match.declarationType)]
        } else {
            return []
        }
    }

    /// Return the signatures of the subscripts matching the given parameters.
    ///
    /// The match on the parameter types will attempt to allow for unknown types.
    ///
    /// - Parameters:
    ///   - type: The subscript's owning type.
    func `subscript`(in type: TypeSignature, parameters: [LabeledValue<TypeSignature>], messagesNode: SyntaxNode?) -> [TypeSignature] {
        if case .optional = type {
            return self.subscript(inNonOptional: type.asOptional(false), parameters: parameters, messagesNode: messagesNode).map {
                .function($0.parameters, $0.returnType.asOptional(true))
            }
        } else {
            return self.subscript(inNonOptional: type, parameters: parameters, messagesNode: messagesNode)
        }
    }

    private func `subscript`(inNonOptional type: TypeSignature, parameters: [LabeledValue<TypeSignature>], messagesNode: SyntaxNode?) -> [TypeSignature] {
        if let codebaseInfo {
            let constrainedArguments = parameters.map { LabeledValue(label: $0.label, value: $0.value.constrainedTypeWithGenerics(generics)) }
            let matches = codebaseInfo.matchSubscript(inConstrained: type.constrainedTypeWithGenerics(generics), arguments: constrainedArguments)
            addMessages(to: messagesNode, for: matches.map(\.availability))
            return matches.map(\.signature)
        } else if let match = unavailableAPI?.knownUnavailableFunction("subscript", in: type, parameters: parameters) {
            addMessages(to: messagesNode, for: [match.availability])
            return [match.signature]
        } else {
            return []
        }
    }

    /// For an operation on two types, return the probable result type.
    func operationResult(_ type1: TypeSignature, _ type2: TypeSignature) -> TypeSignature {
        let type1 = type1.constrainedTypeWithGenerics(generics)
        let type2 = type2.constrainedTypeWithGenerics(generics)
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
        case .unwrappedOptional(let baseType1):
            if case .unwrappedOptional(let baseType2) = type2 {
                return operationResult(baseType1, baseType2)
            }
            return operationResult(baseType1, type2)
        default:
            return type1
        }
    }

    private func addMessages(to messagesNode: SyntaxNode?, for availability: [Availability]) {
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
        if availability.count > 1 {
            messagesNode.messages.append(.ambiguousFunctionCall(messagesNode, source: source))
        }
    }
}
