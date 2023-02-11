/// Contextual information used in type inference.
struct TypeInferenceContext {
    private let symbolInfo: SymbolInfo?
    private let sourceFile: Source.File?
    private var typePath: [TypeDeclaration] = []
    private var functionPath: [FunctionDeclaration] = []
    private var localIdentifierTypes: [String: TypeSignature] = [:]
    private let importedModuleNames: Set<String>

    /// Create a top-level context for type inference.
    ///
    /// - Parameters:
    ///   - Parameter symbolInfo: Available symbol information.
    ///   - Parameter sourceFile: Source file for this context.
    ///   - Parameter statements: Top-level statements from which to determine imports.
    init(symbolInfo: SymbolInfo? = nil, sourceFile: Source.File?, statements: [Statement]) {
        self.symbolInfo = symbolInfo
        self.sourceFile = sourceFile
        self.importedModuleNames = Set(statements.compactMap { statement in
            guard statement.type == .importDeclaration, let importDeclaration = statement as? ImportDeclaration else {
                return nil
            }
            return importDeclaration.modulePath.first
        })
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
    func identifier(_ name: String) -> (TypeSignature, Message?) {
        // First check local identifiers
        if let identifierType = localIdentifierTypes[name] {
            return (identifierType, nil)
        }
        // Next check function parameters
        for functionDeclaration in functionPath.reversed() {
            for parameter in functionDeclaration.parameters {
                if parameter.internalName == name {
                    return (parameter.declaredType, nil)
                }
            }
        }
        if let symbolInfo {
        //~~~    return symbolInfo.typeSignature(identifier: name, typePath: typePath, sourceFile: sourceFile)
        }
        return (.none, nil)
    }

    func member(_ name: String, of type: TypeSignature?) -> TypeSignature {
        return .none
    }

    func function(_ name: String, of type: TypeSignature?, parameters: [LabeledValue<TypeSignature>]) -> (TypeSignature, Message?) {
        return (.none, nil)
    }

    func `subscript`(of type: TypeSignature?, parameters: [LabeledValue<TypeSignature>]) -> (TypeSignature, Message?) {
        return (.none, nil)
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
