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
    let pluginFolderName = "skip-transpiler"

    /// The file extension for the metadata about skipcode
    let skipcodeExtension = ".skipcode.json"

    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let skip = try context.tool(named: "skip")
        let outputFolder = context.pluginWorkDirectory

        // In SPM the per-module outputs has no suffix, but in Xcode it is "ModuleName.output" below DerivedData/
        // We determine we are in Xcode by checking for environment variables that should only be present for Xcode
        // Note that xcodebuild some has different environment variables, so we need to also check for those.
        let env = ProcessInfo.processInfo.environment
        let xcodeBuildFolder = env["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] ?? env["BUILT_PRODUCTS_DIR"]
        let isXcode = env["__CFBundleIdentifier"] == "com.apple.dt.Xcode" || xcodeBuildFolder != nil

        // Diagnostics.warning("ENVIRONMENT: \(env)")
        let packageFolderExtension = isXcode ? ".output" : ""

        //print("createBuildCommands:", context.package.id)
        guard let sourceTarget = target as? SourceModuleTarget else {
            throw TranspilePlugInError("Target «\(target.name)» was not a source module")
        }

        // look for ModuleKotlin/Sources/Skip/skip.yml
        let skipFolder = sourceTarget.directory.appending(["Skip"])

        // the peer for the current target
        // e.g.: SkipLibKotlin -> SkipLib
        // e.g.: SkipLibKtTests -> SkipLibTests
        let peerTarget: Target

        let kotlinSuffix = "Kt"
        let testSuffix = "Tests"
        //let kotlinTestSuffix = testSuffix + kotlinSuffix // ModuleNameTestsKt
        let kotlinTestSuffix = kotlinSuffix + testSuffix // ModuleNameKtTests
        let isTest = target.name.hasSuffix(kotlinTestSuffix)
        let kotlinModule = String(target.name.dropLast(isTest ? kotlinTestSuffix.count : kotlinSuffix.count))
        if isTest {
            if !target.name.hasSuffix(kotlinTestSuffix) {
                throw TranspilePlugInError("Target «\(target.name)» must have suffix «\(kotlinTestSuffix)»")
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

            guard let dependencyTarget = try context.package.targets(named: [expectedName]).first else {
                throw TranspilePlugInError("Target «\(target.name)» should have a peer test target named «\(expectedName)»")
            }

            peerTarget = dependencyTarget
        }

        guard let swiftSourceTarget  = peerTarget as? SourceModuleTarget else {
            throw TranspilePlugInError("Peer target «\(peerTarget.name)» was not a source module")
        }

        let swiftSourceFiles = swiftSourceTarget.sourceFiles.filter({ $0.type == .source })

        guard !swiftSourceFiles.isEmpty else {
            throw TranspilePlugInError("The target «\(peerTarget.name)» does not contain any .swift files for transpilation.")
        }

        let sourceFilePaths = swiftSourceFiles.map(\.path.string)

        var buildModuleArgs: [String] = [
            "--module",
            peerTarget.name + ":" + peerTarget.directory.string,
        ]

        @discardableResult func addModuleLinkFlag(_ target: Target, packageID: String?) throws -> String? {
            let targetName = target.name
            if !targetName.hasSuffix(kotlinSuffix) {
                //print("peer target had invalid name: \(targetName)")
                return nil
            }
            let peerTargetName = targetName.dropLast(kotlinSuffix.count).description

            // build up a relative link path to the related module based on the plug-in output directory structure
            buildModuleArgs += ["--module", peerTargetName + ":" + target.directory.string]
            // e.g. ../../../skiphub.output/SkipFoundationKotlin/skip-transpiler/SkipFoundation
            // e.g. ../../SkipFoundationKotlin/skip-transpiler/SkipFoundation
            let targetLink: String
            if let packageID = packageID { // go further up to the external package name
                targetLink = "../../../" + packageID + packageFolderExtension + "/" + target.name + "/" + pluginFolderName + "/" + peerTargetName
            } else {
                targetLink = "../../" + target.name + "/" + pluginFolderName + "/" + peerTargetName
            }
            buildModuleArgs += ["--link", peerTargetName + ":" + targetLink]
            return targetLink
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


        // the input files consist of all the swift, kotlin, and .yml files in all of the sources
        // having no inputs or outputs in Xcode seems to result in the command running *every* time, but in SPM is appears to have the opposite effect: it never seems to run when there are no inputs or outputs
        //#warning("build sourceFiles from directory rather than from SPM")
        let sourceDir = sourceTarget.directory
        // TODO: find .swift files in tree
        let _ = sourceDir

        // collect the resources for linking
        var resourceArgs: [String] = []
        for resource in swiftSourceTarget.sourceFiles.filter({ $0.type == .resource }) {
            resourceArgs += ["--resource", resource.path.string]
        }

        // the output files contains the .skipcode.json, and the input files contains all the dependent .skipcode.json files
        let outputURL = URL(fileURLWithPath: outputFolder.string, isDirectory: true)
        let skipcodeOutputPath = Path(outputURL.appendingPathComponent(peerTarget.name + skipcodeExtension).path)
        Diagnostics.remark("add skipcode output for \(target.name): \(skipcodeOutputPath)", file: skipcodeOutputPath.string)

        let outputFiles: [Path] = [skipcodeOutputPath]
        var inputFiles: [Path] = sourceTarget.sourceFiles.map(\.path) + swiftSourceTarget.sourceFiles.map(\.path)

        for (product, depTarget) in target.recursiveTargetProductDependencies {
            if depTarget.name.hasSuffix(kotlinSuffix) { // only link in if the module is named "*Kotlin"
                // lookup the correct package name that contains this product (whose id will be an arbtrary number like "32")
                if let moduleLinkTarget = try addModuleLinkFlag(depTarget, packageID: productIDPackages[product?.id]?.id) {
                    // adds an input file dependency on all the .skipcode.json files output from the dependent targets
                    // this should block the invocation of the transpiler plugin for this module
                    // until the dependent modules have all been transpiled and their skipcode JSON files emitted
                    let skipcodeInputFile = outputFolder.appending(subpath: moduleLinkTarget + skipcodeExtension)
                    let skipcodeURL = URL(fileURLWithPath: skipcodeInputFile.string)
                    let skipcodeStandardizedPath = Path(skipcodeURL.standardized.path)
                    Diagnostics.remark("add skipcode input to \(depTarget.name): \(skipcodeStandardizedPath)", file: skipcodeStandardizedPath.string)
                    inputFiles.append(skipcodeStandardizedPath)
                }
            }
        }

        let outputBase = URL(fileURLWithPath: kotlinModule, isDirectory: true, relativeTo: outputURL)
        let sourceBase = URL(fileURLWithPath: isTest ? "src/test" : "src/main", isDirectory: true, relativeTo: outputBase)

        return [
            .buildCommand(displayName: "Skip Transpile \(target.name)", executable: skip.path, arguments: [
                "transpile",
                "--output-folder", sourceBase.path,
                "--module-root", outputBase.path,
                "--skip-folder", skipFolder.string,
                ]
                + resourceArgs
                + buildModuleArgs
                + sourceFilePaths, 
                inputFiles: inputFiles, 
                outputFiles: outputFiles)
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

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SkipTranspilePlugIn: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        Diagnostics.error("SkipTranspilePlugIn does not support Xcode projects, only SPM")
        return []
    }
}
#endif
