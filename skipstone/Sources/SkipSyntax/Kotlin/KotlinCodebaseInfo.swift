extension CodebaseInfo {
    /// Access Kotlin additions.
    public var kotlin: KotlinCodebaseInfo? {
        get {
            return languageAdditions as? KotlinCodebaseInfo
        }
        set {
            languageAdditions = newValue
        }
    }
}

extension CodebaseInfo.Context {
    /// Return all extensions of a given type.
    func extensions(of type: TypeSignature) -> [(CodebaseInfo.TypeInfo, ExtensionDeclaration)] {
        assert(global.kotlin != nil)
        return typeInfos(forNamed: type).compactMap { typeInfo in
            guard let extensionDeclaration = typeInfo.languageAdditions as? ExtensionDeclaration else {
                return nil
            }
            return (typeInfo, extensionDeclaration)
        }
    }

    /// The signatures of all visible constructors of the given type.
    ///
    /// The type must be concrete - protocol constructors are excluded.
    ///
    /// - Note: The returned parameters are only populated with the external label, declared type, and default value (when available).
    func constructorParameters(of type: TypeSignature) -> [[Parameter<Expression>]] {
        assert(global.kotlin != nil)
        let inits = typeInfos(forNamed: type).flatMap { (typeInfo) -> [CodebaseInfoItem] in
            guard typeInfo.declarationType != .protocolDeclaration else {
                return []
            }
            return typeInfo.visibleMembers(context: self).filter { $0.declarationType == .initDeclaration }
        }
        return inits.compactMap { (initInfo) -> [Parameter<Expression>]? in
            guard let functionInfo = initInfo as? CodebaseInfo.FunctionInfo else {
                return nil
            }
            // Filter out generated default constructor
            let parameters = functionInfo.signature.parameters
            guard parameters.count > 0 || !functionInfo.isGenerated || inits.count > 1 else {
                return nil
            }
            var defaultValues: [Expression?]
            if let additions = functionInfo.languageAdditions as? [Expression?], additions.count == parameters.count {
                defaultValues = additions
            } else {
                defaultValues = Array<Expression?>(repeating: nil, count: parameters.count)
            }
            return parameters.enumerated().map { (index, parameter) in
                Parameter<Expression>(externalLabel: parameter.label, declaredType: parameter.type, isVariadic: parameter.isVariadic, defaultValue: defaultValues[index])
            }
        }
    }

    /// Whether this declaration is implementing a property of the given type, excluding Kotlin extension properties and functions.
    func isImplementingKotlinMember(declaration: VariableDeclaration, inExtension type: TypeSignature, with generics: Generics) -> Bool {
        assert(global.kotlin != nil)
        guard !declaration.names.isEmpty, let name = declaration.names[0] else {
            return false
        }
        let (signature, _) = identifierSignature(of: name, inConstrained: type.constrainedTypeWithGenerics(generics), excludeConstrainedExtensions: true)
        return signature != .none
    }

    /// Whether this declaration is implementing a function of the given type, excluding Kotlin extension properties and functions.
    func isImplementingKotlinMember(declaration: FunctionDeclaration, inExtension type: TypeSignature, with generics: Generics) -> Bool {
        assert(global.kotlin != nil)
        let constrainedSignature = declaration.functionType.constrainedTypeWithGenerics(generics)
        let parameters = constrainedSignature.parameters
        let arguments = parameters.map { LabeledValue(label: $0.label, value: $0.type) }
        let signatures = functionSignature(of: declaration.name, inConstrained: type.constrainedTypeWithGenerics(generics), arguments: arguments, excludeConstrainedExtensions: true)
        return !signatures.isEmpty
    }

    /// Whether this declaration is implementing a protocol property.
    func isImplementingKotlinInterfaceMember(declaration: VariableDeclaration, in type: TypeSignature) -> Bool {
        guard !declaration.names.isEmpty, let name = declaration.names[0] else {
            return false
        }
        return isKotlinInterfaceMember(name: name, parameters: nil, isStatic: declaration.modifiers.isStatic, in: type)
    }

    /// Whether this declaration is implementing a protocol function.
    func isImplementingKotlinInterfaceMember(declaration: FunctionDeclaration, in type: TypeSignature) -> Bool {
        return isKotlinInterfaceMember(name: declaration.name, parameters: declaration.functionType.parameters, isStatic: declaration.modifiers.isStatic, in: type)
    }

    /// Whether the given member is declared by a protocol of the given type.
    func isKotlinInterfaceMember(name: String, parameters: [TypeSignature.Parameter]?, isStatic: Bool, in owningType: TypeSignature) -> Bool {
        assert(global.kotlin != nil)
        let protocolSignatures = global.protocolSignatures(forNamed: owningType)
        for protocolSignature in protocolSignatures {
            // Exclude protocols that do not translate into Kotlin interfaces
            guard protocolSignature != .customStringConvertible && protocolSignature != .equatable && protocolSignature != .hashable else {
                continue
            }
            for protocolInfo in typeInfos(forNamed: protocolSignature) {
                if let parameters {
                    if protocolInfo.functions.contains(where: { $0.name == name && $0.signature.parameters.map(\.label) == parameters.map(\.label) }) {
                        return true
                    }
                } else if protocolInfo.variables.contains(where: { $0.name == name }) {
                    return true
                }
            }
        }
        return false
    }

    /// Whether the given type may be a mutable struct.
    func mayBeMutableStruct(type: TypeSignature) -> Bool {
        assert(global.kotlin != nil)
        let typeInfos = typeInfos(forNamed: type)
        if let structInfo = typeInfos.first(where: { $0.declarationType == .structDeclaration }) {
            return structInfo.variables.contains(where: { !$0.isReadOnly }) || structInfo.functions.contains(where: { $0.isMutating })
        } else if typeInfos.contains(where: { $0.declarationType == .protocolDeclaration }) {
            // If this is a protocol that is constrained to class impls, then it isn't a mutable struct. Otherwise it could be
            return !global.protocolSignatures(forNamed: type).contains(.anyObject)
        } else if typeInfos.isEmpty {
            // Assume an unknown type could be a mutable struct
            let type = type.asOptional(false)
            if case .named = type {
                // Cross platform typealiases should not be treated as mutable structs
                return crossPlatformTypealias(forUnknownNamed: type) == nil
            } else if type == .any {
                return true
            } else {
                return false
            }
        } else {
            return false
        }
    }

    /// Whether the given type conforms to `Error` through its protocols, **not** through inheritance.
    func conformsToError(type: TypeSignature) -> Bool {
        assert(global.kotlin != nil)
        return global.protocolSignatures(forNamed: type).contains(.named("Error", []))
    }

    /// Whether the given enum type has cases with associated values.
    func isSealedClassesEnum(type: TypeSignature) -> Bool {
        assert(global.kotlin != nil)
        guard let enumInfo = typeInfos(forNamed: type).first(where: { $0.declarationType == .enumDeclaration }) else {
            return false
        }
        if enumInfo.cases.contains(where: { if case .function = $0.signature { return true } else { return false } }) {
            return true
        }
        return conformsToError(type: type)
    }

    /// Whether the given name corresponds to a function in the given type.
    func isFunctionName(_ name: String, in owningType: TypeSignature?) -> Bool {
        assert(global.kotlin != nil)
        let owningType = owningType?.asOptional(false)
        if owningType != nil && name == "init" {
            return true
        }
        let items = ranked(global.lookup(name: name))
        return items.contains { $0.declarationType == .functionDeclaration && $0.declaringType?.name == owningType?.name }
    }

    private func hasMember(_ owningType: TypeSignature, name: String, type: TypeSignature?, isStatic: Bool) -> Bool {
        for typeInfo in typeInfos(forNamed: owningType) {
            if typeInfo.visibleMembers(context: self).contains(where: { $0.name == name && $0.isStatic == isStatic && (type == nil || $0.signature == type) }) {
                return true
            }
        }
        return false
    }
}

/// Wholistic information about the codebase needed when transpiling Swift to Kotlin.
public class KotlinCodebaseInfo: CodebaseInfoLanguageAdditions, CodebaseInfoLanguageAdditionsGatherDelegate {
    /// The package being generated.
    public let packageName: String?

    init(packageName: String? = nil) {
        self.packageName = packageName
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typeInfo: CodebaseInfo.TypeInfo, from statement: ExtensionDeclaration) {
        // Keep the extension statement around so we can move it to the extended declarations
        typeInfo.languageAdditions = statement
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather functionInfo: inout CodebaseInfo.FunctionInfo, from statement: FunctionDeclaration) {
        // Track init parameter default values so that we can transfer them to subclass constructors we generate
        if functionInfo.declarationType == .initDeclaration {
            functionInfo.languageAdditions = statement.parameters.map(\.defaultValue)
        }
    }
}
