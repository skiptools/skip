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
    /// Return all extensions of a given type that can move into its definition.
    func moveableExtensions(of type: TypeSignature, in syntaxTree: SyntaxTree) -> [(CodebaseInfo.TypeInfo, ExtensionDeclaration, [[String]])] {
        assert(global.kotlin != nil)
        // Sort to always output added extensions in a stable order
        return typeInfos(forNamed: type)
            .compactMap { typeInfo in
                guard let extensionAdditions = typeInfo.languageAdditions as? ExtensionAdditions else {
                    return nil
                }
                guard let extensionDeclaration = extensionAdditions.moveableExtensionDeclaration(codebaseInfo: self, in: syntaxTree) else {
                    return nil
                }
                return (typeInfo, extensionDeclaration, extensionAdditions.importedModulePaths)
            }
            .sorted { ($0.0.sourceFile?.path ?? "") < ($1.0.sourceFile?.path ?? "") }
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

    /// Whether this constrained declaration is implementing an existing property of the given type, excluding Kotlin extension properties and functions.
    func isImplementingKotlinMember(declaration: VariableDeclaration, inExtension type: TypeSignature, withConstrainingGenerics generics: Generics) -> Bool {
        assert(global.kotlin != nil)
        guard !declaration.names.isEmpty, let name = declaration.names[0] else {
            return false
        }
        return matchIdentifier(name: name, inConstrained: type.constrainedTypeWithGenerics(generics), excludeConstrainedExtensions: true) != nil
    }

    /// Whether this constrained declaration is implementing a function of the given type, excluding Kotlin extension properties and functions.
    func isImplementingKotlinMember(declaration: FunctionDeclaration, inExtension type: TypeSignature, withConstrainingGenerics generics: Generics) -> Bool {
        assert(global.kotlin != nil)
        let constrainedSignature = declaration.functionType.constrainedTypeWithGenerics(generics)
        let parameters = constrainedSignature.parameters
        let arguments = parameters.map { LabeledValue(label: $0.label, value: $0.type) }
        let matches = matchFunction(name: declaration.name, inConstrained: type.constrainedTypeWithGenerics(generics), arguments: arguments, excludeConstrainedExtensions: true)
        return !matches.isEmpty
    }

    /// Whether this declaration is implementing a protocol property.
    func isImplementingKotlinInterfaceMember(declaration: Statement, in type: TypeSignature) -> Bool {
        if let variableDeclaration = declaration as? VariableDeclaration {
            guard !variableDeclaration.names.isEmpty, let name = variableDeclaration.names[0] else {
                return false
            }
            return isKotlinInterfaceMember(name: name, parameters: nil, isStatic: variableDeclaration.modifiers.isStatic, in: type)
        } else if let functionDeclaration = declaration as? FunctionDeclaration {
            return isKotlinInterfaceMember(name: functionDeclaration.name, parameters: functionDeclaration.functionType.parameters, isStatic: functionDeclaration.modifiers.isStatic, in: type)
        } else if let subscriptDeclaration = declaration as? SubscriptDeclaration {
            return isKotlinInterfaceMember(name: "subscript", parameters: subscriptDeclaration.getterType.parameters, isStatic: subscriptDeclaration.modifiers.isStatic, in: type)
        } else {
            return false
        }
    }

    /// Whether the given member is declared by a protocol of the given type.
    func isKotlinInterfaceMember(name: String, parameters: [TypeSignature.Parameter]?, isStatic: Bool, in owningType: TypeSignature) -> Bool {
        assert(global.kotlin != nil)
        let protocolSignatures = global.protocolSignatures(forNamed: owningType)
        let parameterLabels = parameters?.map(\.label) ?? []
        let parameterTypes = parameters?.map(\.type) ?? []
        for protocolSignature in protocolSignatures {
            // Exclude protocols that do not translate into Kotlin interfaces
            guard !protocolSignature.isCustomStringConvertible && !protocolSignature.isEquatable && !protocolSignature.isHashable else {
                continue
            }
            for protocolInfo in typeInfos(forNamed: protocolSignature) {
                if parameters != nil {
                    if name == "subscript" {
                        if protocolInfo.subscripts.contains(where: { $0.signature.parameters.map(\.label) == parameterLabels && isCompatibleParameterTypes(candidates: parameterTypes, in: owningType, targets: $0.signature.parameters.map(\.type), in: protocolInfo.signature) }) {
                            return true
                        }
                    } else {
                        if protocolInfo.functions.contains(where: { $0.name == name && $0.signature.parameters.map(\.label) == parameterLabels && isCompatibleParameterTypes(candidates: parameterTypes, in: owningType, targets: $0.signature.parameters.map(\.type), in: protocolInfo.signature) }) {
                            return true
                        }
                    }
                } else if protocolInfo.variables.contains(where: { $0.name == name }) {
                    return true
                }
            }
        }
        return false
    }

    private func isCompatibleParameterTypes(candidates: [TypeSignature], in candidateType: TypeSignature, targets: [TypeSignature], in targetType: TypeSignature) -> Bool {
        // If there are generics involved, it is difficult to calculate final types, so we bail
        guard candidateType.generics.isEmpty && targetType.generics.isEmpty else {
            return true
        }
        return candidates == targets
    }

    /// Whether the given type may be a mutable struct.
    func mayBeMutableStruct(type: TypeSignature) -> Bool {
        assert(global.kotlin != nil)
        let typeInfos = typeInfos(forNamed: type)
        if let structInfo = typeInfos.first(where: { $0.declarationType == .structDeclaration }) {
            guard !structInfo.attributes.kotlinHasDirective(.nocopy) else {
                return false
            }
            return structInfo.variables.contains(where: { $0.apiFlags?.contains(.writeable) == true && !$0.attributes.isNonMutating }) || structInfo.functions.contains(where: \.isMutating)
        } else if typeInfos.contains(where: { $0.declarationType == .protocolDeclaration && !$0.attributes.kotlinHasDirective(.nocopy) }) {
            // If this is a protocol that is constrained to class impls, then it isn't a mutable struct. Otherwise it could be
            return !global.protocolSignatures(forNamed: type).contains(.anyObject)
        } else if typeInfos.isEmpty {
            // Assume an unknown type could be a mutable struct
            switch type.asTypealiased(nil).withoutOptionality() {
            case .named, .member, .module:
                // Cross platform typealiases should not be treated as mutable structs
                return crossPlatformTypealias(forUnknownNamed: type) == nil
            case .any:
                return true
            default:
                return false
            }
        } else {
            return false
        }
    }

    /// Whether the given type conforms to `Error` through its protocols, **not** through inheritance.
    func conformsToError(type: TypeSignature) -> Bool {
        assert(global.kotlin != nil)
        return global.protocolSignatures(forNamed: type).contains { $0.isNamed("Error", moduleName: "Swift", generics: []) }
    }

    /// Whether the given enum type has cases with associated values.
    func isSealedClassesEnum(type: TypeSignature) -> Bool {
        assert(global.kotlin != nil)
        guard let enumInfo = typeInfos(forNamed: type).first(where: { $0.declarationType == .enumDeclaration }) else {
            return false
        }
        if enumInfo.cases.contains(where: { $0.signature.isFunction }) {
            return true
        }
        return conformsToError(type: type)
    }

    /// Whether the given name corresponds to a function in the given type.
    func isFunctionName(_ name: String, in owningType: TypeSignature?) -> Bool {
        assert(global.kotlin != nil)
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

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typeInfo: CodebaseInfo.TypeInfo, from statement: ExtensionDeclaration, syntaxTree: SyntaxTree) {
        // Keep the extension statement around so we can move it to the extended declarations
        typeInfo.languageAdditions = ExtensionAdditions(extensionDeclaration: statement, syntaxTree: syntaxTree)
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather functionInfo: inout CodebaseInfo.FunctionInfo, from statement: FunctionDeclaration, syntaxTree: SyntaxTree) {
        // Track init parameter default values so that we can transfer them to subclass constructors we generate
        if functionInfo.declarationType == .initDeclaration {
            functionInfo.languageAdditions = statement.parameters.map(\.defaultValue)
        }
    }
}

private class ExtensionAdditions {
    let extensionDeclaration: ExtensionDeclaration?
    let importedModulePaths: [[String]]
    let source: Source?
    var hasInferredTypes = false
    let statementIndex: Int?

    init(extensionDeclaration: ExtensionDeclaration, syntaxTree: SyntaxTree) {
        // If we're in the same file as the extended declaration, we'll be able to find this extension in the
        // syntax tree given on lookup, so just record the statement index. Otherwise we have to save the entire
        // extension declaration
        let statements = syntaxTree.root.statements
        if statements.containsDeclaration(of: extensionDeclaration.extends), let index = statements.firstIndex(where: { $0 === extensionDeclaration }) {
            self.statementIndex = index
            self.extensionDeclaration = nil
            self.importedModulePaths = []
            self.source = nil
        } else {
            self.extensionDeclaration = extensionDeclaration
            self.importedModulePaths = statements.importedModulePaths
            self.source = syntaxTree.source
            self.statementIndex = nil
        }
    }

    func moveableExtensionDeclaration(codebaseInfo: CodebaseInfo.Context, in syntaxTree: SyntaxTree) -> ExtensionDeclaration? {
        // Recover the extension declaration
        if let statementIndex {
            guard statementIndex < syntaxTree.root.statements.count, let extensionDeclaration = syntaxTree.root.statements[statementIndex] as? ExtensionDeclaration else {
                assert(false)
                return nil
            }
            return extensionDeclaration.canMoveIntoExtendedType ? extensionDeclaration : nil
        } else if let extensionDeclaration, let source {
            guard extensionDeclaration.canMoveIntoExtendedType && extensionDeclaration.visibilityAllowsMoveIntoExtendedType else {
                return nil
            }
            if !hasInferredTypes {
                let context = codebaseInfo.global.context(importedModuleNames: importedModulePaths.compactMap(\.moduleName), sourceFile: source.file)
                let typeResolutionContext = TypeResolutionContext(codebaseInfo: context)
                extensionDeclaration.resolveSubtreeAttributes(in: syntaxTree, context: typeResolutionContext)
                let typeInferenceContext = TypeInferenceContext(codebaseInfo: context, unavailableAPI: nil, source: syntaxTree.source)
                let _ = extensionDeclaration.inferTypes(context: typeInferenceContext, expecting: .none)
                hasInferredTypes = true
            }
            return extensionDeclaration
        } else {
            return nil
        }
    }
}
