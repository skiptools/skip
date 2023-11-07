// Copyright 2023 Skip
import Foundation
import PackagePlugin

/// Build plugin that unifies the preflight linter and the transpiler in a single plugin.
@main struct SkipPlugin: BuildToolPlugin {
    /// The suffix that is requires
    let testSuffix = "Tests"

    /// The root of target dependencies that are don't have any skipcode output
    let skipRootTargetNames: Set<String> = ["SkipDrive", "SkipTest"]

    /// The name of the plug-in's output folder is the same as the target name for the transpiler, which matches the ".plugin(name)" in the Package.swift
    let pluginFolderName = "skipstone"

    /// The output folder in which to place Skippy files
    let skippyOutputFolder = ".skippy"

    /// The executable command forked by the plugin; this is the build artifact whose name matches the built `skip` binary
    let skipPluginCommandName = "skip"

    /// The file extension for the metadata about skipcode
    //let skipcodeExtension = ".skipcode.json"

    /// The skip transpile output containing the input source hashes to check for changes
    let sourcehashExtension = ".sourcehash"

    /// The extension to add to the skippy output; these have the `docc` extension merely because that is the only extension of generated files that is not copied as a resource when a package is built: https://github.com/apple/swift-package-manager/blob/0147f7122a2c66eef55dcf17a0e4812320d5c7e6/Sources/PackageLoading/TargetSourcesBuilder.swift#L665
    let skippyOuptputExtension = ".skippy"

    /// Whether we should run in Skippy or full-transpile mode
    let skippyOnly = ProcessInfo.processInfo.environment["CONFIGURATION"] == "Skippy"

    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        if skipRootTargetNames.contains(target.name) {
            Diagnostics.remark("Skip eliding target name \(target.name)")
            return []
        }
        guard let sourceTarget = target as? SourceModuleTarget else {
            Diagnostics.remark("Skip skipping non-source target name \(target.name)")
            return []
        }

        var cmds: [Command] = []
        if skippyOnly {
            cmds += try await createPreflightBuildCommands(context: context, target: sourceTarget)
        } else {
            // We only want to run the transpiler when targeting macOS and not iOS, but there doesn't appear to by any way to identify that from this phase of the plugin execution; so the transpiler will check the environment (e.g., "SUPPORTED_DEVICE_FAMILIES") and only run conditionally
            cmds += try await createTranspileBuildCommands(context: context, target: sourceTarget)
        }

        return cmds
    }

    func createPreflightBuildCommands(context: PluginContext, target: SourceModuleTarget) async throws -> [Command] {
        let runner = try context.tool(named: skipPluginCommandName).path
        let inputPaths = target.sourceFiles(withSuffix: ".swift").map { $0.path }
        let outputDir = context.pluginWorkDirectory.appending(subpath: skippyOutputFolder)
        return inputPaths.map { Command.buildCommand(displayName: "Skippy \(target.name): \($0.lastComponent)", executable: runner, arguments: ["skippy", "--output-suffix", skippyOuptputExtension, "-O", outputDir.string, $0.string], inputFiles: [$0], outputFiles: [$0.outputPath(in: outputDir, suffix: skippyOuptputExtension)]) }
    }

    func createTranspileBuildCommands(context: PluginContext, target: SourceModuleTarget) async throws -> [Command] {
        //Diagnostics.remark("Skip transpile target: \(target.name)")

        // we need to know the names of peer target folders in order to set up dependency links, so we need to determine the output folder structure

        // output named vary dependeding on whether we are running from Xcode/xcodebuild and SPM:
        // xcode: DERIVED/SourcePackages/plugins/skip-unit.output/SkipUnit/skipstone/SkipUnit.skipcode.json
        // SPM:     PROJECT_HOME/.build/plugins/outputs/skip-unit/SkipUnit/skipstone/SkipUnit.skipcode.json
        //Diagnostics.warning("OUTPUT: \(context.pluginWorkDirectory)")
        let outputExt = context.pluginWorkDirectory.removingLastComponent().removingLastComponent().extension
        let pkgext = outputExt.flatMap({ "." + $0 }) ?? ""

        let skip = try context.tool(named: skipPluginCommandName)
        let outputFolder = context.pluginWorkDirectory

        // look for ModuleKotlin/Sources/Skip/skip.yml
        let skipFolder = target.directory.appending(["Skip"])

        // the peer for the current target
        // e.g.: SkipLibKotlin -> SkipLib
        // e.g.: SkipLibKtTests -> SkipLibTests
        let peerTarget: Target

        let isTest = target.name.hasSuffix(testSuffix)
        let kotlinModule = String(target.name.dropLast(isTest ? testSuffix.count : 0))
        if isTest {
            if !target.name.hasSuffix(testSuffix) {
                throw SkipPluginError(errorDescription: "Target «\(target.name)» must have suffix «\(testSuffix)»")
            }

            // convert ModuleKotlinTests -> ModuleTests
            let expectedName = kotlinModule + testSuffix

            // Known issue with SPM in Xcode: we cannot have a depencency from one testTarget to another, or we hit the error:
            // Enable to resolve build file: XCBCore.BuildFile (The workspace has a reference to a missing target with GUID 'PACKAGE-TARGET:SkipLibTests')
            // so we cannot use `target.dependencies.first` to find the target; we just need to scan by name
            guard let dependencyTarget = try context.package.targets(named: [expectedName]).first else {
                throw SkipPluginError(errorDescription: "Target «\(target.name)» should have a peer test target named «\(expectedName)»")
            }

            peerTarget = dependencyTarget
        } else {
            let expectedName = kotlinModule

            guard let dependencyTarget = try context.package.targets(named: [expectedName]).first else {
                throw SkipPluginError(errorDescription: "Target «\(target.name)» should have a peer test target named «\(expectedName)»")
            }

            peerTarget = dependencyTarget
        }

        guard let swiftSourceTarget = peerTarget as? SourceModuleTarget else {
            throw SkipPluginError(errorDescription: "Peer target «\(peerTarget.name)» was not a source module")
        }

        func recursivePackageDependencies(for package: Package) -> [PackageDependency] {
            package.dependencies + package.dependencies.flatMap({ recursivePackageDependencies(for: $0.package) })
        }

        // create a lookup table from the (arbitrary but unique) product ID to the owning package
        // this is needed to find the package ID associated with a given product ID
        var productIDPackages: [Product.ID?: Package] = [:]
        for targetPackage in recursivePackageDependencies(for: context.package) {
            for product in targetPackage.package.products {
                productIDPackages[product.id] = targetPackage.package
            }
        }

        // the output files contains the .skipcode.json, and the input files contains all the dependent .skipcode.json files
        let outputURL = URL(fileURLWithPath: outputFolder.string, isDirectory: true)
        let sourceHashDot = "."
        let sourcehashOutputPath = Path(outputURL.appendingPathComponent(sourceHashDot + peerTarget.name + sourcehashExtension, isDirectory: false).path)
        Diagnostics.remark("add sourcehash output for \(target.name): \(sourcehashOutputPath)", file: sourcehashOutputPath.string)

        struct Dep : Identifiable {
            let package: Package
            let target: Target

            var id: String { target.id }
        }

        var buildModuleArgs: [String] = [
            "--module",
            peerTarget.name + ":" + peerTarget.directory.string,
        ]

        @discardableResult func addModuleLinkFlag(_ target: SourceModuleTarget, packageID: String?) throws -> String? {
            let targetName = target.name
            // build up a relative link path to the related module based on the plug-in output directory structure
            buildModuleArgs += ["--module", targetName + ":" + target.directory.string]
            // e.g. ../../../skiphub.output/SkipFoundationKotlin/skip/SkipFoundation
            // e.g. ../../SkipFoundationKotlin/skip/SkipFoundation
            let targetLink: String
            if let packageID = packageID { // go further up to the external package name
                targetLink = "../../../" + packageID + pkgext + "/" + target.name + "/" + pluginFolderName + "/" + targetName
            } else {
                targetLink = "../../" + target.name + "/" + pluginFolderName + "/" + targetName
            }
            buildModuleArgs += ["--link", targetName + ":" + targetLink]
            return targetLink
        }

        func dependencies(for targetDependencies: [TargetDependency], in package: Package) -> [Dep] {
            return targetDependencies.flatMap { dep in
                switch dep {
                case .product(let product):
                    guard let productPackage = productIDPackages[product.id] else {
                        fatalError("could not find product package for \(product.id)")
                    }

                    return product.targets.flatMap { target in
                        // stop at any external targets
                        if skipRootTargetNames.contains(target.name) {
                            return [] as [Dep]
                        }
                        return [Dep(package: productPackage, target: target)] + dependencies(for: target.dependencies, in: productPackage)
                    }
                case .target(let target):
                    if skipRootTargetNames.contains(target.name) {
                        return [] as [Dep]
                    }
                    return [Dep(package: package, target: target)] + dependencies(for: target.dependencies, in: package)
                @unknown default:
                    fatalError("unhanded target casecheckDependencies(target")
                }
            }
        }

        var deps = dependencies(for: target.dependencies, in: context.package)
        deps = makeUniqueById(deps)

        let outputFiles: [Path] = [sourcehashOutputPath]
        // input files consist of the source files, as well as all the dependent module output source hash directory files, which will be modified whenever a transpiled module changes
        // note that using the directory as the input will cause the transpile to re-run for any sub-folder change, although this behavior is not explicitly documented
        var inputFiles: [Path] = [target.directory] + target.sourceFiles.map(\.path)

        for dep in deps {
            guard let depTarget = dep.target as? SourceModuleTarget else {
                // only consider source module targets
                continue
            }

            if skipRootTargetNames.contains(depTarget.name) {
                continue
            }

            // ignore non-Skip-enabled dependency modules, based on the existance of the SRC/MODULE/Skip/skip.yml file
            if !FileManager.default.isReadableFile(atPath: depTarget.directory.appending("Skip", "skip.yml").string) {
                continue
            }

            if let moduleLinkTarget = try addModuleLinkFlag(depTarget, packageID: dep.package.id) {
                // adds an input file dependency on all the .skipcode.json files output from the dependent targets
                // this should block the invocation of the transpiler plugin for this module
                // until the dependent modules have all been transpiled and their skipcode JSON files emitted

                var sourceHashFile = URL(fileURLWithPath: outputFolder.string, isDirectory: true).appendingPathComponent(moduleLinkTarget + sourcehashExtension, isDirectory: false)
                // turn the module name into a sourcehash file name
                // need to standardize the path to remove ../../ elements form the symlinks, otherwise the input and output paths don't match and Xcode will re-build everything each time
                sourceHashFile = sourceHashFile.standardized
                    .deletingLastPathComponent()
                    .appendingPathComponent(sourceHashDot + sourceHashFile.lastPathComponent, isDirectory: false)

                // output a .sourcehash file contains all the input files, so the transpile will be re-run when any of the input sources have changed
                let sourceHashFilePath = Path(sourceHashFile.path)
                inputFiles.append(sourceHashFilePath)
                //Diagnostics.remark("add sourcehash input for \(depTarget.name): \(sourceHashFilePath.string)", file: sourceHashFilePath.string)
            }
        }

        // due to FB12969712 https://github.com/apple/swift-package-manager/issues/6816 , we cannot trust the list of input files sent to the plugin because Xcode caches them onces and doesn't change them when the package source file list changes (unless first manually running: File -> Packages -> Reset Package Caches)
        // so instead we just pass the targets folder to the skip tool, and rely on it the tool to walk the file system and determine which files have changed or been renamed
        //let inputSources = target.sourceFiles // source file list will be built by walking the --project flag instead

        let outputBase = URL(fileURLWithPath: kotlinModule, isDirectory: true, relativeTo: outputURL)
        let sourceBase = URL(fileURLWithPath: isTest ? "src/test" : "src/main", isDirectory: true, relativeTo: outputBase)

        return [
            .buildCommand(displayName: "Skip \(target.name)", executable: skip.path, arguments: [
                "transpile",
                "--project", swiftSourceTarget.directory.string,
                "--skip-folder", skipFolder.string,
                "--sourcehash", sourcehashOutputPath.string,
                "--output-folder", sourceBase.path,
                "--module-root", outputBase.path,
                ]
                + buildModuleArgs,
                inputFiles: inputFiles,
                outputFiles: outputFiles)
        ]
    }
}

struct SkipPluginError : LocalizedError {
    let errorDescription: String?
}

extension Path {
    /// Xcode requires that we create an output file in order for incremental build tools to work.
    ///
    /// - Warning: This is duplicated in SkippyCommand.
    func outputPath(in outputDir: Path, suffix: String) -> Path {
        var outputFileName = self.lastComponent
        if outputFileName.hasSuffix(".swift") {
            outputFileName = String(lastComponent.dropLast(".swift".count))
        }
        outputFileName += suffix
        return outputDir.appending(subpath: "." + outputFileName)
    }
}

func makeUniqueById<T: Identifiable>(_ items: [T]) -> [T] {
    var uniqueItems = Set<T.ID>()
    var result = [T]()
    for item in items {
        if uniqueItems.insert(item.id).inserted {
            result.append(item)
        }
    }
    return result
}
