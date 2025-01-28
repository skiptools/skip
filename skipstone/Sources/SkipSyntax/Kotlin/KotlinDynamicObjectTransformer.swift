/// Generate dynamic object types.
public final class KotlinDynamicObjectTransformer: KotlinTransformer {
    public static let supportFileName = "AnyDynamicObject_Support.swift"

    private let root: String
    private var generateClassNames: Set<String> = []

    public init(root: String) {
        self.root = root
    }

    public init() {
        self.root = "K"
    }

    public func gather(from syntaxTree: SyntaxTree) {
        guard syntaxTree.bridgeAPI != .none else {
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
        return []
    }

    public func apply(toPackage syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        let classNames = generateClassNames.sorted()
        var generated: Set<String> = []
        var swift: [String] = []
        classNames.forEach { swift += generateDynamicClass(fullName: $0, generated: &generated) }
        guard !swift.isEmpty else {
            return []
        }

        var outputFile = syntaxTree.source.file
        outputFile.name = Self.supportFileName
        let outputNode = SwiftDefinition { output, indentation, _ in
            output.append("import SkipBridge\n\n")
            swift.forEach { output.append($0).append("\n") }
        }
        return [KotlinTransformerOutput(file: outputFile, node: outputNode, type: .bridgeToSwift)]
    }

    private func generateDynamicClass(fullName: String, generated: inout Set<String>) -> [String] {
        let tokens = fullName.split(separator: ".")
        var swift: [String] = []
        for i in 0..<tokens.count {
            let namespace = tokens[0..<i].joined(separator: ".")
            if i > 0 && tokens[i].first?.isUppercase == true {
                generateDynamicClass(name: String(tokens[i]), in: namespace, generated: &generated, swift: &swift)
            } else {
                generateNamespace(String(tokens[i]), in: namespace, generated: &generated, swift: &swift)
            }
        }
        return swift
    }

    private func generateNamespace(_ namespace: String, in parent: String, generated: inout Set<String>, swift: inout [String]) {
        if parent.isEmpty {
            guard generated.insert(namespace).inserted else {
                return
            }
            swift.append("enum \(namespace) {}")
        } else {
            guard generated.insert(parent + "." + namespace).inserted else {
                return
            }
            swift.append("extension \(parent) { enum \(namespace) {} }")
        }
    }

    private func generateDynamicClass(name: String, in namespace: String, generated: inout Set<String>, swift: inout [String]) {
        let className = namespace.dropFirst(root.count + 1) + "." + name
        guard generated.insert(className).inserted else {
            return
        }
        swift.append("extension \(namespace) {")
        swift.append(1, "final class \(name): AnyDynamicObject {")
        swift.append(2, "init(_ arguments: Any?...) throws {")
        swift.append(3, "try super.init(className: \"\(className)\", arguments: arguments)")
        swift.append(2, "}")
        swift.append(2, "required init(for object: JavaObjectPointer) throws {")
        swift.append(3, "try super.init(for: object)")
        swift.append(2, "}")
        swift.append(2, "static let Companion = try! AnyDynamicObject(forStaticsOfClassName: \"\(className)\")")
        swift.append(1, "}")
        swift.append("}")
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
        let (string, _) = memberAccessToString(memberAccess)
        addDynamicClassNames(from: string)
    }

    private func addDynamicClassNames(from string: String) {
        guard string.hasPrefix(root + ".") else {
            return
        }
        // This might be a nested type, in which case we add it and its outer types
        var tokens = string.split(separator: ".")
        while tokens.last?.first?.isUppercase == true {
            generateClassNames.insert(tokens.joined(separator: "."))
            tokens = tokens.dropLast()
        }
    }

    private func memberAccessToString(_ memberAccess: MemberAccess) -> (string: String, append: Bool) {
        guard memberAccess.member != "self" && memberAccess.member != "Type" && memberAccess.member != "Companion" else {
            if let baseAccess = memberAccess.base as? MemberAccess {
                let (string, _) = memberAccessToString(baseAccess)
                return (string, false)
            }
            return ("", false)
        }
        if let identifier = memberAccess.base as? Identifier {
            guard identifier.name == root else {
                return ("", false)
            }
            return (root + "." + memberAccess.member, true)
        } else if let baseAccess = memberAccess.base as? MemberAccess {
            let (string, append) = memberAccessToString(baseAccess)
            if append {
                return (string + "." + memberAccess.member, true)
            } else {
                return (string, false)
            }
        } else {
            return ("", false)
        }
    }
}
