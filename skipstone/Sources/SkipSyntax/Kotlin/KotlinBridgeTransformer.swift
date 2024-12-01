import Foundation

/// Available bridge options.
///
/// - Seealso: `JConvertibleOptions` in `SkipBridge`.
public struct KotlinBridgeOptions: OptionSet {
    public static let kotlincompat = KotlinBridgeOptions(rawValue: 1 << 0)

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Create a set from a list of strings, e.g. `["kotlincompat"]`.
    public static func parse(_ strings: [String]) -> KotlinBridgeOptions {
        var options: KotlinBridgeOptions = []
        for string in strings {
            switch string {
            case "kotlincompat":
                options.insert(.kotlincompat)
            default:
                break
            }
        }
        return options
    }
}

/// Generate bridging code and transformations.
public final class KotlinBridgeTransformer: KotlinTransformer {
    private let options: KotlinBridgeOptions

    public init(options: KotlinBridgeOptions) {
        self.options = options
    }

    public init() {
        self.options = []
    }

    public func gather(from syntaxTree: SyntaxTree) {
        // Add attributes marking bridged types so that they're recorded in our codebase info
        syntaxTree.root.visit { node in
            if let typeDeclaration = node as? TypeDeclaration, typeDeclaration.type != .extensionDeclaration {
                if typeDeclaration.modifiers.visibility >= .public, !typeDeclaration.attributes.isNoBridge {
                    if syntaxTree.isBridgeFile {
                        typeDeclaration.attributes.attributes.append(.bridgeToKotlin)
                    } else {
                        typeDeclaration.attributes.attributes.append(.bridgeToSwift)
                    }
                }
                return .recurse(nil)
            } else if node is VariableDeclaration || node is FunctionDeclaration {
                return .skip
            } else {
                return .recurse(nil)
            }
        }
    }

    public func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        if syntaxTree.isBridgeFile {
            guard let visitor = KotlinBridgeToKotlinVisitor(for: syntaxTree, options: options, translator: translator) else {
                return []
            }
            return visitor.visit()
        } else {
            guard let visitor = KotlinBridgeToSwiftVisitor(for: syntaxTree, options: options, translator: translator) else {
                return []
            }
            return visitor.visit()
        }
    }
}
