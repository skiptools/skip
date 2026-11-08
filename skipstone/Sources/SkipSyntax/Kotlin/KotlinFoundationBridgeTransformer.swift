/// Generate code to support various `Foundation` types bridging to Android.
public final class KotlinFoundationBridgeTransformer: KotlinTransformer {
    public static let supportFileName = "FoundationBridge_Support.swift"

    public init() {
    }

    public func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        return []
    }

    public func apply(toPackage syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        // Generate support for any native module using SkipAndroidBridge
        let needsAndroidBridge = translator.codebaseInfo?.global.needsAndroidBridge == true
        guard needsAndroidBridge else {
            return []
        }

        var outputFile = syntaxTree.source.file
        outputFile.name = Self.supportFileName
        let outputNode = SwiftDefinition { output, indentation, _ in
            // The blank line after the SkipBridge import is expected by our bridge testing
            output.append("""
            import SkipBridge

            import Foundation
            import SkipAndroidBridge
            
            typealias UserDefaults = AndroidUserDefaults
            typealias LocalizedStringResource = AndroidLocalizedStringResource
            """)
        }
        return [KotlinTransformerOutput(file: outputFile, node: outputNode, type: .bridgeToSwift)]
    }
}
