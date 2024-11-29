/// Generate dynamic object types.
public final class KotlinDynamicObjectTransformer: KotlinTransformer {
    private let root: String
    private var generateClassNames: Set<String> = []

    public init(root: String) {
        self.root = root
    }

    public init() {
        self.root = "K"
    }

    public func gather(from syntaxTree: SyntaxTree) {
        guard syntaxTree.isBridgeFile else {
            return
        }
        syntaxTree.root.visit { node in
            if let memberAccess = node as? MemberAccess {
                addDynamicClassNames(from: memberAccess)
            } else if let typealiasDeclaration = node as? TypealiasDeclaration {
                addDynamicClassNames(from: typealiasDeclaration.aliasedType)
            } else if let typeLiteral = node as? TypeLiteral {
                addDynamicClassNames(from: typeLiteral.literal)
            }
            return .recurse(nil)
        }
    }

    public func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        let classNames = generateClassNames.sorted()
        var namespaces: Set<String> = []
        
        return []
    }

    private func addDynamicClassNames(from signature: TypeSignature) {
        signature.visit { type in
            if type.isNamedType {
                addDynamicClassNames(from: type.name)
                return .skip
            } else {
                return .recurse(nil)
            }
        }
    }

    private func addDynamicClassNames(from memberAccess: MemberAccess) {
        guard !(memberAccess.parent is MemberAccess) else {
            return
        }
        var string: String = ""
        if memberAccessToString(memberAccess, string: &string) {
            addDynamicClassNames(from: string)
        }
    }

    private func addDynamicClassNames(from string: String) {
        guard string.hasPrefix(root + ".") else {
            return
        }
        // This might be a nested type, in which case we added it and its outer types
        var tokens = string.dropFirst(root.count + 1).split(separator: ".")
        while tokens.last?.first?.isUppercase == true {
            generateClassNames.insert(tokens.joined(separator: "."))
            tokens = tokens.dropLast()
        }
    }

    private func memberAccessToString(_ memberAccess: MemberAccess, string: inout String) -> Bool {
        guard memberAccess.member != "self" && memberAccess.member != "Type" && memberAccess.member != "Companion" else {
            if let baseAccess = memberAccess.base as? MemberAccess {
                return memberAccessToString(baseAccess, string: &string)
            } else {
                return false
            }
        }
        if let identifier = memberAccess.base as? Identifier {
            if identifier.name != root {
                return false
            }
            string = identifier.name + "." + memberAccess.member
            return true
        } else if let baseAccess = memberAccess.base as? MemberAccess {
            if memberAccessToString(baseAccess, string: &string) {
                string = string + "." + memberAccess.member
                return true
            } else {
                return false
            }
        } else {
            return false
        }
    }
}
