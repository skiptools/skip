/// Generate code to support `Bundle` and `Bundle.module` if it is needed within the module.
public final class KotlinBundleTransformer: KotlinTransformer {
    public static let supportFileName = "Bundle_Support.swift"

    private var needsModuleBundle = false
    public static var testSkipAndroidBridge = false // For testing

    public init() {
    }

    public func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        guard !needsModuleBundle else {
            return []
        }
        // No need to add Bundle.module if not a full build
        guard translator.codebaseInfo != nil else {
            return []
        }
        let foundationModules: Set<String> = [
            "Foundation", "SkipFoundation", "SwiftUI", "SkipUI", "SkipFuseUI"
        ]
        guard syntaxTree.root.statements.compactMap({ $0 as? KotlinImportDeclaration }).contains(where: { foundationModules.contains($0.modulePath.first ?? "") }) else {
            return []
        }

        syntaxTree.root.visit(ifSkipBlockContent: syntaxTree.isBridgeFile) { node in
            if !needsModuleBundle, let memberAccess = node as? KotlinMemberAccess, memberAccess.member == "module" {
                needsModuleBundle = memberAccess.isBaseType(named: "Bundle", moduleName: "Foundation")
            }
            return .recurse(nil)
        }
        return []
    }

    public func apply(toPackage syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        // Generate Bundle support for any module using SkipAndroidBridge
        let needsAndroidBridge = Self.testSkipAndroidBridge || translator.codebaseInfo?.global.needsAndroidBridge == true
        guard needsModuleBundle || needsAndroidBridge else {
            return []
        }

        var declarations = ["""
        internal val skip.foundation.Bundle.Companion.module: skip.foundation.Bundle
            get() = _moduleBundle
        private val _moduleBundle: skip.foundation.Bundle by lazy {
            skip.foundation.Bundle(_ModuleBundleLocator::class)
        }
        internal class _ModuleBundleLocator {}
        """]
        if needsAndroidBridge {
            // Native modules need access to our module bundle via reflection
            let className = moduleBundleAccessorClassName(moduleName: translator.codebaseInfo?.global.moduleName ?? "")
            declarations += ["""
            class \(className) {
                val moduleBundle = _moduleBundle
            }
            """]
        }
        let statements = declarations.map { KotlinRawStatement(sourceCode: $0) }
        statements[0].extras = .singleNewline
        syntaxTree.root.insert(statements: statements, after: syntaxTree.root.statements.last)
        return needsAndroidBridge ? [bundleSupportOutput(forPackage: syntaxTree, translator: translator)] : []
    }

    private func moduleBundleAccessorClassName(moduleName: String) -> String {
        return "_ModuleBundleAccessor_\(moduleName)"
    }

    private func bundleSupportOutput(forPackage syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> KotlinTransformerOutput {
        var outputFile = syntaxTree.source.file
        outputFile.name = Self.supportFileName

        // Strategy:
        // - SkipAndroidBridge.AndroidBundle handles bridging to our Kotlin Bundle implementation
        // - AndroidBundle is also JConvertible so we can pass it to any Compose UI code
        // - We generate our own AndroidBundle subclass that knows the current module name and how to access the
        //   Kotlin module bundle, so that we can detect the Swift compiler's attempt to find the module bundle path
        //   (which normally causes a fatal exception because it is designed for Linux rather than Android)
        // - We typealias Bundle to our subclass so that both user code and the Swift compiler's generated code use it
        let moduleName = translator.codebaseInfo?.global.moduleName ?? ""
        let packageName = KotlinTranslator.packageName(forModule: moduleName)
        let className = moduleBundleAccessorClassName(moduleName: moduleName)
        let outputNode = SwiftDefinition { output, indentation, _ in
            // The blank line after the SkipBridge import is expected by our bridge testing
            output.append("""
            import SkipBridge

            import Foundation
            import SkipAndroidBridge
            
            typealias Bundle = AndroidModuleBundle
            class AndroidModuleBundle : AndroidBundle, @unchecked Sendable {
                required init(_ bundle: SkipAndroidBridge.BundleAccess) {
                    super.init(bundle)
                }
            
                init?(path: String) {
                    super.init(path: path, moduleName: "\(moduleName)") {
                        try! AnyDynamicObject(className: "\(packageName).\(className)").moduleBundle!
                    }
                }

                override init?(url: URL) {
                    super.init(url: url)
                }
            }
            
            let NSLocalizedString = AndroidLocalizedString()
            """)
        }
        return KotlinTransformerOutput(file: outputFile, node: outputNode, type: .bridgeToSwift)
    }
}
