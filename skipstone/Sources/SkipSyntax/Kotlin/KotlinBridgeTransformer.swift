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
        let isBridgeFile = syntaxTree.isBridgeFile
        syntaxTree.root.visit { node in
            if let typeDeclaration = node as? TypeDeclaration, typeDeclaration.type != .extensionDeclaration {
                let isNativeIfSkipBlock = isBridgeFile && typeDeclaration.isInIfSkipBlock()
                if isBridging(attributes: typeDeclaration.attributes, visibility: typeDeclaration.modifiers.visibility, autoBridge: isNativeIfSkipBlock ? .internal : syntaxTree.autoBridge) {
                    if isBridgeFile && !isNativeIfSkipBlock {
                        typeDeclaration.attributes.attributes.append(.bridgeToKotlin)
                    } else {
                        typeDeclaration.attributes.attributes.append(.bridgeToSwift)
                    }
                }
                return .recurse(nil)
            } else if let typealiasDeclaration = node as? TypealiasDeclaration {
                let isNativeIfSkipBlock = isBridgeFile && typealiasDeclaration.isInIfSkipBlock()
                if isBridging(attributes: typealiasDeclaration.attributes, visibility: typealiasDeclaration.modifiers.visibility, autoBridge: isNativeIfSkipBlock ? .internal : syntaxTree.autoBridge) {
                    if isBridgeFile && !isNativeIfSkipBlock {
                        typealiasDeclaration.attributes.attributes.append(.bridgeToKotlin)
                    } else {
                        typealiasDeclaration.attributes.attributes.append(.bridgeToSwift)
                    }
                }
                return .skip
            } else if node is VariableDeclaration || node is FunctionDeclaration {
                return .skip
            } else {
                return .recurse(nil)
            }
        }
    }

    public func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        var bridgeToKotlinOutputs: [KotlinTransformerOutput] = []
        if syntaxTree.isBridgeFile, let visitor = KotlinBridgeToKotlinVisitor(for: syntaxTree, options: options, translator: translator) {
            bridgeToKotlinOutputs = visitor.visit()
        }
        var bridgeToSwiftOutputs: [KotlinTransformerOutput] = []
        if let visitor = KotlinBridgeToSwiftVisitor(for: syntaxTree, options: options, translator: translator) {
            // Combine any bridging Swift definitions
            for output in visitor.visit() {
                if let index = bridgeToKotlinOutputs.firstIndex(where: { $0.file == output.file }), let swiftDefinition1 = bridgeToKotlinOutputs[index].node as? SwiftDefinition, let swiftDefinition2 = output.node as? SwiftDefinition {
                    bridgeToKotlinOutputs[index].node = swiftDefinition1.combined(with: swiftDefinition2)
                } else {
                    bridgeToSwiftOutputs.append(output)
                }
            }
        }
        return bridgeToKotlinOutputs + bridgeToSwiftOutputs
    }
}
