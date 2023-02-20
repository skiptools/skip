/// Wholistic information about the codebase needed when transpiling Swift to Kotlin.
public class KotlinCodebaseInfo {
    /// The package being generated.
    public let packageName: String?
    private let symbols: Symbols?

    public init(packageName: String? = nil, symbols: Symbols? = nil) {
        self.packageName = packageName
        self.symbols = symbols
    }

    /// Gather codebase-level information from the given syntax tree.
    func gather(from syntaxTree: SyntaxTree) {
        syntaxTree.statements.forEach { gather(from: $0) }
    }

    /// Any issues encountered during information gathering.
    func messages(for sourceFile: Source.File) -> [Message] {
        return []
    }

    fileprivate var typeInfo: [String: [TypeInfo]] = [:]
    fileprivate var extensionInfo: [String: [ExtensionInfo]] = [:]

    private func gather(from statement: Statement) {
        switch statement.type {
        case .classDeclaration:
            addTypeInfo(for: statement as! TypeDeclaration, mayBeMutableValueType: false)
        case .enumDeclaration:
            addTypeInfo(for: statement as! TypeDeclaration, mayBeMutableValueType: false)
        case .protocolDeclaration:
            let typeDeclaration = statement as! TypeDeclaration
            // A protocol may not be mutable value if it extends from AnyObject, may be if it extends from nothing,
            // and we're not sure if it extends from other protocols which may themselves extend from AnyObject. We'll
            // check its symbols later
            let mayBeMutableValueType: Bool? = typeDeclaration.inherits.contains(.anyObject) ? false : typeDeclaration.inherits.isEmpty ? true : nil
            addTypeInfo(for: typeDeclaration, mayBeMutableValueType: mayBeMutableValueType)
        case .structDeclaration:
            let typeDeclaration = statement as! TypeDeclaration
            let mayBeMutableValueType = typeDeclaration.members.contains { member in
                switch member.type {
                case .variableDeclaration:
                    let variableDeclaration = member as! VariableDeclaration
                    return !variableDeclaration.isLet && (variableDeclaration.getter == nil || variableDeclaration.setter != nil)
                case .functionDeclaration:
                    return (member as! FunctionDeclaration).modifiers.isMutating
                default:
                    return false
                }
            }
            addTypeInfo(for: typeDeclaration, mayBeMutableValueType: mayBeMutableValueType)
        case .extensionDeclaration:
            let declaration = statement as! ExtensionDeclaration
            let key = declaration.extends.description
            var infos = extensionInfo[key, default: []]
            infos.append(ExtensionInfo(declaration: declaration, sourceFile: statement.sourceFile))
            extensionInfo[key] = infos
        default:
            break
        }
    }

    private func addTypeInfo(for typeDeclaration: TypeDeclaration, mayBeMutableValueType: Bool?) {
        let info = TypeInfo(declarationType: typeDeclaration.type, mayBeMutableValueType: mayBeMutableValueType, isPrivate: typeDeclaration.modifiers.visibility == .private, sourceFile: typeDeclaration.sourceFile)
        var infos = typeInfo[typeDeclaration.qualifiedName, default: []]
        infos.append(info)
        typeInfo[typeDeclaration.qualifiedName] = infos
    }

    /// Create a context that can access the given imported modules.
    func context(importedModuleNames: [String] = [], sourceFile: Source.File? = nil) -> Context {
        return Context(codebaseInfo: self, symbols: symbols?.context(importedModuleNames: importedModuleNames, sourceFile: sourceFile), sourceFile: sourceFile)
    }

    /// A context for accessing codebase information.
    struct Context {
        private let symbols: Symbols.Context?
        private let codebaseInfo: KotlinCodebaseInfo
        private let sourceFile: Source.File?

        fileprivate init(codebaseInfo: KotlinCodebaseInfo, symbols: Symbols.Context?, sourceFile: Source.File?) {
            self.codebaseInfo = codebaseInfo
            self.symbols = symbols
            self.sourceFile = sourceFile
        }

        /// Return all extensions of a given type.
        func extensions(of declaration: TypeDeclaration) -> [ExtensionDeclaration] {
            return codebaseInfo.extensionInfo[declaration.qualifiedName, default: []].compactMap { info in
                guard declaration.modifiers.visibility != .private || declaration.sourceFile == info.sourceFile else {
                    return nil
                }
                return info.declaration
            }
        }

        /// Whether the given qualified type name is a class, struct, etc *within this module*.
        func declarationType(of qualifiedName: String) -> StatementType? {
            for info in codebaseInfo.typeInfo[qualifiedName, default: []] {
                if !info.isPrivate || info.sourceFile == sourceFile {
                    return info.declarationType
                }
            }
            return nil
        }

        /// The signatures of all constructors of the given type.
        func constructorParameters(of qualifiedName: String) -> [[ConstructorParameter]] {
            //~~~
            return []
        }

        /// Whether a function with the given signature is implementing an inherited protocol function of the given type.
        func isProtocolMember(declaration: FunctionDeclaration, in typeDeclaration: TypeDeclaration) -> Bool {
            // TODO: Needs to check all protocol conformances of the given type, including protocols of protocols, etc
            return false
        }

        /// Whether a property with the given signature is implementing an inherited protocol property of the given type.
        func isProtocolMember(declaration: VariableDeclaration, in typeDeclaration: TypeDeclaration) -> Bool {
            // TODO: Needs to check all protocol conformances of the given type, including protocols of protocols, etc
            return false
        }

        /// Whether the given qualified type name may map to a mutable value type.
        func mayBeMutableValueType(qualifiedName: String) -> Bool {
            for info in codebaseInfo.typeInfo[qualifiedName, default: []] {
                if !info.isPrivate || info.sourceFile == sourceFile, let mayBeMutableValueType = info.mayBeMutableValueType {
                    return mayBeMutableValueType
                }
            }
            return symbols?.isMutableValueType(qualifiedName: qualifiedName) != false
        }
    }

    struct ConstructorParameter {
        let label: String
        let type: TypeSignature
        let isVariadic: Bool
        let defaultValue: KotlinExpression?
    }
}

private struct TypeInfo {
    let declarationType: StatementType
    let mayBeMutableValueType: Bool?
    let isPrivate: Bool
    let sourceFile: Source.File?
}

private struct ExtensionInfo {
    let declaration: ExtensionDeclaration
    let sourceFile: Source.File?
}

// Internal for testing

extension Symbols.Context {
    /// Whether the given name maps to a symbol that is known to be a mutable value type.
    ///
    /// - Returns: true if a symbol exists for a mutable value type, false if only immutable type symbols exist, and nil if no type symbol exists.
    func isMutableValueType(qualifiedName: String) -> Bool? {
        let candidates = lookup(name: qualifiedName)
        var hasType = false
        for candidate in ranked(candidates) {
            guard let kind = candidate.kind else {
                continue
            }
            switch kind {
            case .class:
                hasType = true
            case .enum:
                hasType = true
            case .struct:
                if isMutableStruct(candidate) {
                    return true
                }
                hasType = true
            case .protocol:
                if !isAnyObjectRestrictedProtocol(candidate) {
                    return true
                }
                hasType = true
            default:
                break
            }
        }
        return hasType ? false : nil
    }

    private func isMutableStruct(_ symbol: Symbol) -> Bool {
        for relationship in symbol.relationships {
            guard relationship.kind == .memberOf && relationship.isInverse else {
                continue
            }
            guard let member = lookup(identifier: relationship.targetIdentifier ?? ""), let memberKind = member.kind else {
                // Assume any unknown member might be mutating
                return true
            }
            switch memberKind {
            case .property:
                if member.isVariableReadWrite {
                    return true
                }
            case .method:
                if member.isFunctionMutating {
                    return true
                }
            default:
                break
            }
        }
        return false
    }

    private func isAnyObjectRestrictedProtocol(_ symbol: Symbol) -> Bool {
        if symbol.isInDeclaredInheritanceList(typeName: "AnyObject") {
            return true
        }
        for relationship in symbol.relationships {
            guard relationship.kind == .conformsTo, !relationship.isInverse, let conformsTo = lookup(identifier: relationship.targetIdentifier ?? "") else {
                continue
            }
            if isAnyObjectRestrictedProtocol(conformsTo) {
                return true
            }
        }
        return false
    }
}
