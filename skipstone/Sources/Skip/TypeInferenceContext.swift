/// Contextual information used in type inference.
struct TypeInferenceContext {
    private let symbols: Symbols.Context?
    private var typePath: [TypeDeclaration] = []
    private var functionPath: [FunctionDeclaration] = []
    private var localIdentifierTypes: [String: TypeSignature] = [:]

    /// Create a top-level context for type inference.
    ///
    /// - Parameters:
    ///   - Parameter symbols: Available symbol information.
    ///   - Parameter sourceFile: Source file for this context.
    ///   - Parameter statements: Top-level statements from which to determine imports.
    init(symbols: Symbols? = nil, sourceFile: Source.File?, statements: [Statement]) {
        if let symbols {
            let importedModuleNames: [String] = statements.compactMap { statement in
                guard statement.type == .importDeclaration, let importDeclaration = statement as? ImportDeclaration else {
                    return nil
                }
                return importDeclaration.modulePath.first
            }
            self.symbols = symbols.context(importedModuleNames: importedModuleNames, sourceFile: sourceFile)
        } else {
            self.symbols = nil
        }
    }

    /// The type we're expecting to return from the current code block.
    private(set) var expectedReturn: TypeSignature = .none

    /// Return a context for evaluating members of the given type.
    func pushing(_ typeDeclaration: TypeDeclaration) -> TypeInferenceContext {
        var context = self
        context.typePath.append(typeDeclaration)
        return context
    }

    /// Return a context for evaluating the code of the given function.
    func pushing(_ functionDeclaration: FunctionDeclaration) -> TypeInferenceContext {
        var context = self
        context.functionPath.append(functionDeclaration)
        context.expectedReturn = functionDeclaration.returnType
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

    /// Return the type of the given identifier.
    func identifier(_ name: String) -> TypeSignature {
        // First check local identifiers
        if let identifierType = localIdentifierTypes[name] {
            return identifierType
        }
        // Next check function parameters
        for functionDeclaration in functionPath.reversed() {
            for parameter in functionDeclaration.parameters {
                if parameter.internalLabel == name {
                    return parameter.declaredType
                }
            }
        }
        if name == "self" || name == "super" {
            guard let typeDeclaration = typePath.last else {
                return .none
            }
            return name == "self" ? typeDeclaration.signature : typeDeclaration.inherits.first ?? .none
        }
        guard let symbols else {
            return .none
        }

        for typeDeclaration in typePath.reversed() {
            let symbolType = symbols.identifierSignature(of: name, in: .named(typeDeclaration.qualifiedName, []))
            if symbolType != .none {
                return symbolType
            }
        }
        return symbols.identifierSignature(of: name)
    }

    /// Return the type of the given member.
    func member(_ name: String, in type: TypeSignature) -> TypeSignature {
        guard let symbols else {
            return .none
        }
        return symbols.identifierSignature(of: name, in: type)
    }

    /// Return the signatures of the functions matching the given parameters.
    ///
    /// The match on the parameter types will attempt to allow for unknown types.
    ///
    /// - Parameters:
    ///   - Parameter type: The function's owning type if this is a member function, or nil if not.
    func function(_ name: String, in type: TypeSignature?, parameters: [LabeledValue<TypeSignature>]) -> [TypeSignature] {
        guard let symbols else {
            return []
        }
        if let type {
            return symbols.functionSignature(of: name, in: type, arguments: parameters)
        }

        // Not a known member function. Check functions that can be invoked without a target type
        for typeDeclaration in typePath.reversed() {
            let results = symbols.functionSignature(of: name, in: .named(typeDeclaration.qualifiedName, []), arguments: parameters)
            if !results.isEmpty {
                return results
            }
        }
        return symbols.functionSignature(of: name, arguments: parameters)
    }

    /// Return the signatures of the subscripts matching the given parameters.
    ///
    /// The match on the parameter types will attempt to allow for unknown types.
    ///
    /// - Parameters:
    ///   - Parameter type: The subscript's owning type.
    func `subscript`(in type: TypeSignature, parameters: [LabeledValue<TypeSignature>]) -> [TypeSignature] {
        guard let symbols else {
            return []
        }
        return symbols.subscriptSignature(in: type, arguments: parameters)
    }

    /// For an operation on two types, return the probable result type.
    func operationResult(_ type1: TypeSignature, _ type2: TypeSignature) -> TypeSignature {
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
}
