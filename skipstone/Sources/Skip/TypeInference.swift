indirect enum InferredType: Hashable {
    case array(InferredType)
    case boolean
    case double
    case function([InferredType], InferredType)
    case int
    case string
    case void
    case none

    var element: InferredType {
        return .none
    }

    var parameters: [InferredType] {
        return []
    }

    var returnType: InferredType {
        return .none
    }
}

/// Contextual information used in type inference.
struct TypeInferenceContext {
    var expectedReturn: InferredType = .none

    func pushing(_ typeDeclaration: TypeDeclaration) -> TypeInferenceContext {
        return self
    }

    func pushing(_ functionDeclaration: FunctionDeclaration) -> TypeInferenceContext {
        return self
    }

    func expectingReturn(_ returnType: InferredType) -> TypeInferenceContext {
        var context = self
        context.expectedReturn = returnType
        return context
    }

    func addingIdentifier(_ name: String, type: InferredType) -> TypeInferenceContext {
        return self
    }

    func identifier(_ name: String) -> InferredType? {
        return nil
    }

    func member(_ name: String, of type: InferredType?) -> InferredType? {
        return nil
    }

    func function(_ name: String, of type: InferredType?, parameters: [LabeledValue<InferredType>]) -> InferredType? {
        return nil
    }

    func commonType(_ type1: InferredType, _ type2: InferredType) -> InferredType {
        return .none
    }
}

extension TypeSignature {
    var inferredType: InferredType {
        return .none
    }
}

