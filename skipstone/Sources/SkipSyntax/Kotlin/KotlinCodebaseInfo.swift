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
    func moveableExtensions(of type: TypeSignature, in syntaxTree: SyntaxTree) -> [(ExtensionDeclaration, [TypeSignature], [[String]])] {
        assert(global.kotlin != nil)
        var additions = typeInfos(forNamed: type)
            .compactMap { (typeInfo: CodebaseInfo.TypeInfo) -> (ExtensionAdditions, [TypeSignature])? in
                guard let additions = typeInfo.languageAdditions as? ExtensionAdditions else {
                    return nil
                }
                return (additions, typeInfo.inherits)
            }
        additions += (global.kotlin?.selfTypeExtensionAdditions[type.name] ?? []).map { ($0, []) }
        // Sort to always output added extensions in a stable order
        return additions.compactMap { (addition: (ExtensionAdditions, [TypeSignature])) -> (ExtensionDeclaration, [TypeSignature], [[String]])? in
            guard let declaration = addition.0.moveableExtensionDeclaration(codebaseInfo: self, in: syntaxTree) else {
                    return nil
                }
            return (declaration, addition.1, addition.0.importedModulePaths)
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
            return visibleMembers(of: typeInfo).filter { $0.declarationType == .initDeclaration }
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
        let arguments = parameters.map { LabeledValue(label: $0.label, value: ArgumentValue(type: $0.type)) }
        let matches = matchFunction(name: declaration.name, inConstrained: type.constrainedTypeWithGenerics(generics), arguments: arguments, excludeConstrainedExtensions: true)
        return !matches.isEmpty
    }

    /// Whether this declaration is implementing a protocol property, excluding constrained properties.
    func isImplementingKotlinInterfaceMember(declaration: Statement, in type: TypeSignature) -> Bool {
        if let variableDeclaration = declaration as? VariableDeclaration {
            guard !variableDeclaration.names.isEmpty, let name = variableDeclaration.names[0] else {
                return false
            }
            return isKotlinUnconstrainedInterfaceMember(name: name, parameters: nil, isStatic: variableDeclaration.modifiers.isStatic, in: type, includeDeclaringType: false)
        } else if let functionDeclaration = declaration as? FunctionDeclaration {
            return isKotlinUnconstrainedInterfaceMember(name: functionDeclaration.name, parameters: functionDeclaration.functionType.parameters, isStatic: functionDeclaration.modifiers.isStatic, in: type, includeDeclaringType: false)
        } else if let subscriptDeclaration = declaration as? SubscriptDeclaration {
            return isKotlinUnconstrainedInterfaceMember(name: "subscript", parameters: subscriptDeclaration.getterType.parameters, isStatic: subscriptDeclaration.modifiers.isStatic, in: type, includeDeclaringType: false)
        } else {
            return false
        }
    }

    /// Whether the given member is declared by a protocol of the given type.
    func isKotlinUnconstrainedInterfaceMember(name: String, parameters: [TypeSignature.Parameter]?, isStatic: Bool, in owningType: TypeSignature, includeDeclaringType: Bool = true) -> Bool {
        assert(global.kotlin != nil)
        let protocolSignatures = global.protocolSignatures(forNamed: owningType)
        let parameterLabels = parameters?.map(\.label) ?? []
        let parameterTypes = parameters?.map(\.type) ?? []
        for protocolSignature in protocolSignatures {
            // Exclude protocols that do not translate into Kotlin interfaces
            guard (includeDeclaringType || protocolSignature.name != owningType.name), !protocolSignature.isCustomStringConvertible && !protocolSignature.isEquatable && !protocolSignature.isHashable else {
                continue
            }
            for protocolInfo in typeInfos(forNamed: protocolSignature) {
                // You can't override a constrained protocol because its members are implemented as extension functions
                if protocolInfo.declarationType == .extensionDeclaration && protocolInfo.generics.entries.contains(where: { !$0.inherits.isEmpty || $0.whereEqual != nil }) {
                    continue
                }
                if parameters != nil {
                    if name == "subscript" {
                        if protocolInfo.subscripts.contains(where: { $0.isStatic == isStatic && $0.signature.parameters.map(\.label) == parameterLabels && isCompatibleParameterTypes(candidates: parameterTypes, in: owningType, targets: $0.signature.parameters.map(\.type), in: protocolInfo.signature) }) {
                            return true
                        }
                    } else {
                        if protocolInfo.functions.contains(where: { $0.isStatic == isStatic && $0.name == name && $0.signature.parameters.map(\.label) == parameterLabels && isCompatibleParameterTypes(candidates: parameterTypes, in: owningType, targets: $0.signature.parameters.map(\.type), in: protocolInfo.signature) }) {
                            return true
                        }
                    }
                } else if protocolInfo.variables.contains(where: { $0.isStatic == isStatic && $0.name == name }) {
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
        let typeInfos = typeInfos(forNamed: type)
        guard let enumInfo = typeInfos.first(where: { $0.declarationType == .enumDeclaration }) else {
            return false
        }
        if enumInfo.cases.contains(where: { $0.signature.isFunction }) {
            return true
        }
        // Kotlin enums have built-in non-overridable ordering, so we have to convert regular enums to use sealed
        // classes if they want custom ordering
        if typeInfos.contains(where: { $0.members.contains { $0.isLessThanFunction } }) {
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

    /// The companion object type of the given type.
    func companionType(of type: TypeSignature) -> KotlinCompanionType {
        let typeInfos = typeInfos(forNamed: type)
        if let classInfo = typeInfos.first(where: { $0.declarationType == .classDeclaration }) {
            // Classes that need companion objects:
            // - Is public/open (so that static extensions from other modules work)
            // - Has static members
            // - Extends a type with a companion class or companion interface
            // Classes that need companion classes:
            // - Is non-final and has a companion object and is public/open or has subclasses
            let isPublicOrOpen = classInfo.modifiers.visibility == .public || classInfo.modifiers.visibility == .open
            let hasCompanion = isPublicOrOpen || hasStaticMembers(typeInfos: typeInfos) || hasCompanionInherits(classInfo.inherits)
            guard hasCompanion else {
                return .none
            }
            guard !classInfo.modifiers.isFinal && (isPublicOrOpen || global.kotlin?.subclassedTypeNames.contains(classInfo.signature.name) == true) else {
                return .object
            }
            return .class(.member(type.withGenerics([]), .named("CompanionClass", [])))
        } else if let interfaceInfo = typeInfos.first(where: { $0.declarationType == .protocolDeclaration }) {
            // Protocols that need companion interfaces:
            // - Has static members
            // - Has initializer members
            // - Extends a protocol with a companion interface
            guard hasStaticMembers(typeInfos: typeInfos, includeInits: true) || hasCompanionInherits(interfaceInfo.inherits) else {
                return .none
            }
            return .interface(.named(type.name + "Companion", type.generics))
        } else if let typeInfo = typeInfos.first(where: { $0.declarationType == .actorDeclaration || $0.declarationType == .enumDeclaration || $0.declarationType == .structDeclaration }) {
            let hasCompanion = typeInfo.modifiers.visibility == .public || typeInfo.modifiers.visibility == .open || hasStaticMembers(typeInfos: typeInfos) || hasCompanionInherits(typeInfo.inherits)
            return hasCompanion ? .object : .none
        } else {
            // Unknown: default to object
            return .object
        }
    }

    /// Return the function signatures of all init methods in inherited protocols of the given type.
    func companionInits(of type: TypeSignature, for sourceDerived: SourceDerived, source: Source) -> ([TypeSignature], [Message]) {
        let protocolSignatures = global.protocolSignatures(forNamed: type)
        var messages: [Message] = []
        let initSignatures = protocolSignatures.flatMap { (protocolSignature: TypeSignature) -> [TypeSignature] in
            guard let primaryTypeInfo = primaryTypeInfo(forNamed: protocolSignature) else {
                return []
            }
            let initSignatures = primaryTypeInfo.members.compactMap {
                return $0.declarationType == .initDeclaration ? $0.signature : nil
            }
            let generics = protocolSignature.generics
            guard !initSignatures.isEmpty && !generics.isEmpty else {
                return initSignatures
            }
            // If the protocol has any generics, we have to find the implementation of each init to get the actual types used
            let nones = generics.map { _ in TypeSignature.none }
            return initSignatures.compactMap {
                let match = matchFunction(name: "init", inConstrained: type, arguments: $0.parameters.map {
                    LabeledValue(label: $0.label, value: ArgumentValue(type: $0.type.mappingTypes(from: generics, to: nones)))
                }).first?.signature
                if match == nil {
                    messages.append(.kotlinConstructorMatchProtocolInit(sourceDerived, protocolSignature: protocolSignature, source: source))
                } else if type.generics.contains(where: { match?.referencesType($0) == true }) {
                    messages.append(.kotlinConstructorStaticInitGenerics(sourceDerived, protocolSignature: protocolSignature, source: source))
                }
                return match
            }
        }
        return (Self.dedupe(initSignatures), messages)
    }

    // WARNING: Technically we should be excluding static members of protocols that have a `Self == Type` constraint,
    // because those members are added directly to the target type. The declaring protocol may not need a companion
    // protocol. But then we wouldn't count those members on the protocol extension AND we wouldn't find them in the
    // typeInfos of the extended type, which could result in us generating the wrong companion type.
    private func hasStaticMembers(typeInfos: [CodebaseInfo.TypeInfo], includeInits: Bool = false) -> Bool {
        return typeInfos.contains { typeInfo in
            typeInfo.members.contains { member in
                (includeInits && member.declarationType == .initDeclaration)
                || (member.isStatic && (member.declarationType == .variableDeclaration || (member.declarationType == .functionDeclaration && member.name != "==" && member.name != "<")))
            }
        }
    }

    private func hasCompanionInherits(_ inherits: [TypeSignature]) -> Bool {
        for inherit in inherits {
            switch companionType(of: inherit) {
            case .class, .interface:
                return true
            case .object, .none:
                break
            }
        }
        return false
    }
}

/// Wholistic information about the codebase needed when transpiling Swift to Kotlin.
public final class KotlinCodebaseInfo: CodebaseInfoLanguageAdditions, CodebaseInfoLanguageAdditionsGatherDelegate {
    /// The package being generated.
    public let packageName: String?

    // Warning: for performance, this set may contain interface names as well as the intended class names
    fileprivate var subclassedTypeNames: Set<String> = []
    fileprivate var selfTypeExtensionAdditions: [String: [ExtensionAdditions]] = [:]

    init(packageName: String? = nil) {
        self.packageName = packageName
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typeInfo: CodebaseInfo.TypeInfo, from statement: TypeDeclaration, syntaxTree: SyntaxTree) {
        if typeInfo.declarationType == .classDeclaration, let firstInherits = typeInfo.inherits.first {
            subclassedTypeNames.insert(firstInherits.name)
        }
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather typeInfo: CodebaseInfo.TypeInfo, from statement: ExtensionDeclaration, syntaxTree: SyntaxTree) {
        // Keep the extension statement around so we can move it to the extended declarations
        let extensionAdditions = ExtensionAdditions(extensionDeclaration: statement, syntaxTree: syntaxTree)
        if let selfType = typeInfo.generics.selfType {
            let typeName = selfType.name
            var additions = selfTypeExtensionAdditions[typeName] ?? []
            additions.append(extensionAdditions)
            selfTypeExtensionAdditions[typeName] = additions
        } else {
            typeInfo.languageAdditions = extensionAdditions
        }
    }

    func codebaseInfo(_ codebaseInfo: CodebaseInfo, didGather functionInfo: inout CodebaseInfo.FunctionInfo, from statement: FunctionDeclaration, syntaxTree: SyntaxTree) {
        // Track init parameter default values so that we can transfer them to subclass constructors we generate
        if functionInfo.declarationType == .initDeclaration {
            functionInfo.languageAdditions = statement.parameters.map(\.defaultValue)
        }
    }
}

extension CodebaseInfoItem {
    var isEqualsFunction: Bool {
        return declarationType == .functionDeclaration && name == "==" && modifiers.isStatic && signature.parameters.count == 2
    }

    var isHashFunction: Bool {
        guard declarationType == .functionDeclaration && name == "hash" && !modifiers.isStatic else {
            return false
        }
        let parameters = signature.parameters
        return parameters.count == 1 && parameters[0].label == "into" && parameters[0].type.isNamed("Hasher", moduleName: "Swift", generics: [])
    }

    var isLessThanFunction: Bool {
        return declarationType == .functionDeclaration && name == "<" && modifiers.isStatic && signature.parameters.count == 2
    }
}

private final class ExtensionAdditions {
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
        if statements.containsDeclaration(of: extensionDeclaration.generics.selfType ?? extensionDeclaration.extends), let index = statements.firstIndex(where: { $0 === extensionDeclaration }) {
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
