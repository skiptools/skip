import Foundation
import PackagePlugin

/// Build plugin to do pre-work like emit warnings about incompatible Swift before transpiling with Skip.
@main struct SkipTranspilePlugIn: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let skiptool = try context.tool(named: "skiptool")
        let outputFolder = context.pluginWorkDirectory
        // let pkg = context.package

        // the peer for the current target
        // e.g.: CrossSQLKotlin -> CrossSQL
        // e.g.: CrossSQLKotlinTests -> CrossSQLTests
        let peerTarget: Target

        let testSuffix = "Tests"
        let kotlinSuffix = "Kotlin"
        let isTest = target.name.hasSuffix(testSuffix)

        if isTest {
            if !target.name.hasSuffix(kotlinSuffix + testSuffix) {
                throw TranspilePlugInError("Target «\(target.name)» must have suffix «\(kotlinSuffix + testSuffix)»")
            }

            // convert ModuleKotlinTests -> ModuleTests
            let expectedName = String(target.name.dropLast(kotlinSuffix.count + testSuffix.count)) + testSuffix

            // Known issue with SPM in Xcode: we cannot have a depencency from one testTarget to another, or we hit the error:
            // Enable to resolve build file: XCBCore.BuildFile (The workspace has a reference to a missing target with GUID 'PACKAGE-TARGET:CrossSQLTests')
            // so we cannot use `target.dependencies.first` to find the target; we just need to scan by name
            guard let dependencyTarget = try context.package.targets(named: [expectedName]).first else {
                throw TranspilePlugInError("Target «\(target.name)» should have a peer test target named «\(expectedName)»")
            }

            peerTarget = dependencyTarget
        } else {
            if !target.name.hasSuffix(kotlinSuffix) {
                throw TranspilePlugInError("Target «\(target.name)» must have suffix «\(kotlinSuffix)»")
            }

            let expectedName = String(target.name.dropLast(kotlinSuffix.count))

            guard let primaryDependency = target.dependencies.first,
                case .target(let dependencyTarget) = primaryDependency else {
                throw TranspilePlugInError("Target «\(target.name)» should have initial dependency on «\(expectedName)»")
            }

            peerTarget = dependencyTarget
            if peerTarget.name != expectedName {
                throw TranspilePlugInError("Target «\(target.name)» should have initial dependency on «\(expectedName)»")
            }
        }

        guard let swiftSourceTarget  = peerTarget as? SourceModuleTarget else {
            throw TranspilePlugInError("Peer target «\(peerTarget.name)» was not a source module")
        }

        let swiftSourceFiles = swiftSourceTarget.sourceFiles(withSuffix: ".swift").map({ $0 })

        guard !swiftSourceFiles.isEmpty else {
            throw TranspilePlugInError("The target «\(peerTarget.name)» does not contain any .swift files for transpilation.")
        }

        let sourceFilePaths = swiftSourceFiles.map(\.path.string)

        var buildModuleArgs: [String] = [
            "--module",
            peerTarget.name,
        ]
        for targetDependent in peerTarget.dependencies {
            switch targetDependent {
            case .target(let target):
                buildModuleArgs += [
                    "--module",
                    target.name,
                ]
            case .product(let product):
                for productTarget in product.targets {
                    buildModuleArgs += [
                        "--module",
                        productTarget.name,
                    ]
                }
            @unknown default:
                fatalError("unhandled target case")
            }
        }

        // note that commands are executed in reverse order
        return [
            .buildCommand(displayName: "Skip Transpile \(target.name)", executable: skiptool.path, arguments: [
                "transpile",
                "--output-folder", outputFolder.string,
                //"-v",
                ]
                + buildModuleArgs
                + sourceFilePaths),
            .buildCommand(displayName: "Skip Info", executable: skiptool.path, arguments: [
                "info",
                "-v",
                "-E",
            ]),
        ]
    }
}

struct TranspilePlugInError : LocalizedError {
    let msg: String

    init(_ msg: String) {
        self.msg = msg
    }

    var errorDescription: String? {
        msg
    }
}

//#if canImport(XcodeProjectPlugin)
//import XcodeProjectPlugin
//
//extension SkipTranspilePlugIn: XcodeBuildToolPlugin {
//    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
//    }
//}
//#endif
