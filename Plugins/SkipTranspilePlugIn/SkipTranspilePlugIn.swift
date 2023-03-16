// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation
import PackagePlugin

/// Build plugin to do pre-work like emit warnings about incompatible Swift before transpiling with Skip.
@main struct SkipTranspilePlugIn: BuildToolPlugin {
    let pluginFolderName = "SkipTranspilePlugIn"

    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let skiptool = try context.tool(named: "skiptool")
        let outputFolder = context.pluginWorkDirectory
        // let pkg = context.package

        guard let sourceTarget = target as? SourceModuleTarget else {
            throw TranspilePlugInError("Target «\(target.name)» was not a source module")
        }

        // look for ModuleKotlin/Sources/skip/skip.yml
        let skipFolder = sourceTarget.directory.appending(["skip"])

        // the peer for the current target
        // e.g.: CrossSQLKotlin -> CrossSQL
        // e.g.: CrossSQLKotlinTests -> CrossSQLTests
        let peerTarget: Target

        let testSuffix = "Tests"
        let kotlinSuffix = "Kotlin"
        let isTest = target.name.hasSuffix(testSuffix)
        let kotlinModule: String // the Kotlin module, which will be the same for both TargetName and TargetNameTests
        if isTest {
            if !target.name.hasSuffix(kotlinSuffix + testSuffix) {
                throw TranspilePlugInError("Target «\(target.name)» must have suffix «\(kotlinSuffix + testSuffix)»")
            }

            // convert ModuleKotlinTests -> ModuleTests
            kotlinModule = String(target.name.dropLast(kotlinSuffix.count + testSuffix.count))
            let expectedName = kotlinModule + testSuffix

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

            kotlinModule = String(target.name.dropLast(kotlinSuffix.count))
            let expectedName = kotlinModule

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
            peerTarget.name + ":" + peerTarget.directory.string,
        ]

        func addModuleLinkFlag(_ target: Target) {
            let targetName = target.name
            if !targetName.hasSuffix(kotlinSuffix) {
                //print("peer target had invalid name: \(targetName)")
                return
            }
            let peerTargetName = targetName.dropLast(kotlinSuffix.count).description

            // build up a relative link path to the related module based on the plug-in output directory structure
            buildModuleArgs += ["--module", peerTargetName + ":" + target.directory.string]
            // e.g. ../../CrossFoundationKotlin/SkipTranspilePlugIn/CrossFoundation
            // FIXME: the inserted "../" is needed because LocalFileSystem.createSymbolicLink will resolve the relative path against the destinations *parent* for some reason (SPM bug?)
            let targetLink = "../../../" + target.name + "/" + pluginFolderName + "/" + peerTargetName
            buildModuleArgs += ["--link", peerTargetName + ":" + targetLink]
        }

        func addModuleLinkDependency(_ targetDependent: TargetDependency) {
            switch targetDependent {
            case .target(let target):
                addModuleLinkFlag(target)
            case .product(let product):
                for productTarget in product.targets {
                    addModuleLinkFlag(productTarget)
                }
            @unknown default:
                fatalError("unhandled target case")
            }

        }

        for target in target.recursiveTargetDependencies {
            if target.name.hasSuffix(kotlinSuffix) { // only link in if the module is named "*Kotlin"
                addModuleLinkFlag(target)
            }
        }

        let outputURL = URL(fileURLWithPath: outputFolder.string, isDirectory: true)
        let outputBase = URL(fileURLWithPath: kotlinModule, isDirectory: true, relativeTo: outputURL)

        let sourceOutputPath = URL(fileURLWithPath: isTest ? "src/test/kotlin" : "src/main/kotlin", isDirectory: true, relativeTo: outputBase)

        // note that commands are executed in reverse order
        return [
            .buildCommand(displayName: "Skip Transpile \(target.name)", executable: skiptool.path, arguments: [
                "transpile",
                "--output-folder", sourceOutputPath.path,
                "--module-root", outputBase.path,
                "--skip-folder", skipFolder.string,
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
