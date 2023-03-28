// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation
import PackagePlugin

/// For a given package names "SourceModuleKotlin", take all the `.swift` source files in the peer "SourceModule" package  and transpiles them to Kotlin, as well as outputting a `build.gradle.kts` file.
@main struct SkipTranspilePlugIn: BuildToolPlugin {
    /// The name of the plug-in's output folder is the same as the target name for the transpiler
    let pluginFolderName = "SkipTranspilePlugIn"

    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let skiptool = try context.tool(named: "skiptool")
        let outputFolder = context.pluginWorkDirectory
        //print("createBuildCommands:", context.package.id)
        guard let sourceTarget = target as? SourceModuleTarget else {
            throw TranspilePlugInError("Target «\(target.name)» was not a source module")
        }

        // look for ModuleKotlin/Sources/skip/skip.yml
        let skipFolder = sourceTarget.directory.appending(["skip"])

        // the peer for the current target
        // e.g.: SkipLibKotlin -> SkipLib
        // e.g.: SkipLibTestsKt -> SkipLibTests
        let peerTarget: Target

        let testSuffix = "Tests"
        let kotlinSuffix = "Kt"
        let isTest = target.name.hasSuffix(testSuffix + kotlinSuffix)
        let kotlinModule = String(target.name.dropLast(isTest ? (testSuffix + kotlinSuffix).count : kotlinSuffix.count))
        if isTest {
            if !target.name.hasSuffix(testSuffix + kotlinSuffix) {
                throw TranspilePlugInError("Target «\(target.name)» must have suffix «\(testSuffix + kotlinSuffix)»")
            }

            // convert ModuleKotlinTests -> ModuleTests
            let expectedName = kotlinModule + testSuffix

            // Known issue with SPM in Xcode: we cannot have a depencency from one testTarget to another, or we hit the error:
            // Enable to resolve build file: XCBCore.BuildFile (The workspace has a reference to a missing target with GUID 'PACKAGE-TARGET:SkipLibTests')
            // so we cannot use `target.dependencies.first` to find the target; we just need to scan by name
            guard let dependencyTarget = try context.package.targets(named: [expectedName]).first else {
                throw TranspilePlugInError("Target «\(target.name)» should have a peer test target named «\(expectedName)»")
            }

            peerTarget = dependencyTarget
        } else {
            if !target.name.hasSuffix(kotlinSuffix) {
                throw TranspilePlugInError("Target «\(target.name)» must have suffix «\(kotlinSuffix)»")
            }

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

        func addModuleLinkFlag(_ target: Target, packageID: String?) throws {
            let targetName = target.name
            if !targetName.hasSuffix(kotlinSuffix) {
                //print("peer target had invalid name: \(targetName)")
                return
            }
            let peerTargetName = targetName.dropLast(kotlinSuffix.count).description

            // build up a relative link path to the related module based on the plug-in output directory structure
            buildModuleArgs += ["--module", peerTargetName + ":" + target.directory.string]
            // e.g. ../../SkipFoundationKotlin/SkipTranspilePlugIn/SkipFoundation
            // e.g. ../../../skip-core.output/SkipFoundationKotlin/SkipTranspilePlugIn/SkipFoundation
            // FIXME: the inserted "../" is needed because LocalFileSystem.createSymbolicLink will resolve the relative path against the destinations *parent* for some reason (SPM bug?)
            let targetLink: String
            if let packageID = packageID { // go further up to the external package name
                targetLink = "../../../../" + packageID + ".output/" + target.name + "/" + pluginFolderName + "/" + peerTargetName
            } else {
                targetLink = "../../../" + target.name + "/" + pluginFolderName + "/" + peerTargetName
            }
            buildModuleArgs += ["--link", peerTargetName + ":" + targetLink]
        }

        func addModuleLinkDependency(_ targetDependent: TargetDependency) throws {
            switch targetDependent {
            case .target(let target): // local dependency
                try addModuleLinkFlag(target, packageID: nil)
            case .product(let product): // product, possibly in another package
                for productTarget in product.targets {
                    try addModuleLinkFlag(productTarget, packageID: product
                        .name)
                }
            @unknown default:
                fatalError("unhandled target case")
            }

        }

        // create a lookup table from the (arbitrary but unique) product ID to the owning package
        // this is needed to find the package ID associated with a given product ID
        var productIDPackages: [Product.ID?: Package] = [:]
        for targetPackage in context.package.dependencies {
            for product in targetPackage.package.products {
                productIDPackages[product.id] = targetPackage.package
            }
        }

        for (product, target) in target.recursiveTargetProductDependencies {
            if target.name.hasSuffix(kotlinSuffix) { // only link in if the module is named "*Kotlin"
                // lookup the correct package name that contains this product (whose id will be an arbtrary number like "32")
                //print("TRANSITIVE: product: \(product?.id ?? "NONE") target: \(target.name) targetPackage: \(targetPackage?.package.id ?? "NONE")")
                try addModuleLinkFlag(target, packageID: productIDPackages[product?.id]?.id)
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

private extension Target {
    /// The transitive closure of all the targets on which the reciver depends,
    /// ordered such that every dependency appears before any other target that
    /// depends on it (i.e. in "topological sort order").
    var recursiveTargetProductDependencies: [(Product?, Target)] {
        var visited = Set<Target.ID>()
        func dependencyClosure(for target: Target) -> [(Product?, Target)] {
            guard visited.insert(target.id).inserted else { return [] }
            return target.dependencies.flatMap{ dependencyClosure(for: $0) } + [(nil, target)]
        }
        func dependencyClosure(for dependency: TargetDependency) -> [(Product?, Target)] {
            switch dependency {
            case .target(let target):
                return dependencyClosure(for: target)
            case .product(let product):
                return product.targets.flatMap { dependencyClosure(for: $0) }.map {
                    (product, $0.1) // add in the product
                }
            @unknown default:
                return []
            }
        }
        return self.dependencies.flatMap { dependencyClosure(for: $0) }
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
