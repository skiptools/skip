class CodebaseInfo: Codable {

    struct TypeInfo: CodebaseInfoItem, Codable {
        let declarationType: StatementType
        let module: String
        let sourceFile: Source.FilePath
        let modifiers: Modifiers

        let name: String
        let signature: TypeSignature
        let generics: Generics
        let inherits: TypeSignature

        var types: [TypeInfo]
        var typealiases: [TypealiasInfo]
        var cases: [EnumCaseInfo]
        var properties: [VariableInfo]
        var functions: [FunctionInfo]
    }

    struct VariableInfo: CodebaseInfoItem, Codable {
        let declarationType: StatementType
        let module: String
        let sourceFile: Source.FilePath
        let modifiers: Modifiers

        let name: String
        let type: TypeSignature
        let generics: Generics
        let isReadOnly: Bool
    }

    struct FunctionInfo: CodebaseInfoItem, Codable {
        let declarationType: StatementType
        let module: String
        let sourceFile: Source.FilePath
        let modifiers: Modifiers

        let name: String
        let type: TypeSignature
        let generics: Generics
        let isMutating: Bool
    }

    struct TypealiasInfo: CodebaseInfoItem, Codable {
        let declarationType: StatementType
        let module: String
        let sourceFile: Source.FilePath
        let modifiers: Modifiers

        let name: String
        let generics: Generics
        let aliasedType: TypeSignature
    }

    struct EnumCaseInfo: CodebaseInfoItem, Codable {
        let declarationType: StatementType
        let module: String
        let sourceFile: Source.FilePath
        let modifiers: Modifiers

        let name: String
        let associatedValues: [TypeSignature.Parameter]
    }
}

protocol CodebaseInfoItem {
    var declarationType: StatementType { get }
    var module: String { get }
    var sourceFile: Source.FilePath { get }
    var modifiers: Modifiers { get }
}
