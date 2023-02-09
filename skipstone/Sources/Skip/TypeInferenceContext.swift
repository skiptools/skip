/// Contextual information used in type inference.
struct TypeInferenceContext {
    var expectedReturn: TypeSignature = .none

    func pushing(_ typeDeclaration: TypeDeclaration) -> TypeInferenceContext {
        return self
    }

    func pushing(_ functionDeclaration: FunctionDeclaration) -> TypeInferenceContext {
        return self
    }

    func expectingReturn(_ returnType: TypeSignature) -> TypeInferenceContext {
        var context = self
        context.expectedReturn = returnType
        return context
    }

    func addingIdentifier(_ name: String, type: TypeSignature) -> TypeInferenceContext {
        return self
    }

    func identifier(_ name: String) -> TypeSignature? {
        return nil
    }

    func member(_ name: String, of type: TypeSignature?) -> TypeSignature? {
        return nil
    }

    func function(_ name: String, of type: TypeSignature?, parameters: [LabeledValue<TypeSignature>]) -> TypeSignature? {
        return nil
    }

    func commonType(_ type1: TypeSignature, _ type2: TypeSignature) -> TypeSignature {
        return .none
    }
}
