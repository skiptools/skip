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

    /// The skip transpile marker that is always output regardless of whether the transpile was successful or not
    let skipbuildMarker = ".skipbuild"

    /// The process identifier for Xcode, which is used to determine whether plugins go in the "plugins/package-name.output" or "plugins/package-name" folder.
    let xcodeIdentifier = "com.apple.dt.Xcode"

    //let outputSuffix = "_skippy.swift"
    let outputSuffix = ".skippy"

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
        cmds += try await createPreflightBuildCommands(context: context, target: sourceTarget)

        // We only want to run the transpiler when targeting macOS and not iOS, but there doesn't appear to by any way to identify that from this phase of the plugin execution; so the transpiler will check the envrionment (e.g., "SUPPORTED_DEVICE_FAMILIES") and only run conditionally
        cmds += try await createTranspileBuildCommands(context: context, target: sourceTarget)

        return cmds
    }

    func createPreflightBuildCommands(context: PluginContext, target: SourceModuleTarget) async throws -> [Command] {
        let runner = try context.tool(named: skipPluginCommandName).path
        let inputPaths = target.sourceFiles(withSuffix: ".swift").map { $0.path }
        let outputDir = context.pluginWorkDirectory.appending(subpath: skippyOutputFolder)
        return inputPaths.map { Command.buildCommand(displayName: "Skippy \(target.name)", executable: runner, arguments: ["skippy", "--output-suffix", outputSuffix, "-O", outputDir.string, $0.string], inputFiles: [$0], outputFiles: [$0.outputPath(in: outputDir, suffix: outputSuffix)]) }
    }

    func createTranspileBuildCommands(context: PluginContext, target: SourceModuleTarget) async throws -> [Command] {
        //Diagnostics.remark("Skip transpile target: \(target.name)")
        if skipRootTargetNames.contains(target.name) {
            // never transpile the root target names
        }

        let skip = try context.tool(named: skipPluginCommandName)
        let outputFolder = context.pluginWorkDirectory

        // In SPM the per-module outputs has no suffix, but in Xcode it is "module-name.output" below DerivedData/
        // We determine we are in Xcode by checking for environment variables that should only be present for Xcode
        // Note that xcodebuild some has different environment variables, so we need to also check for those.
        let env = ProcessInfo.processInfo.environment
        let xcodeBuildFolder = env["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] ?? env["BUILT_PRODUCTS_DIR"]
        let isXcode = env["__CFBundleIdentifier"] == xcodeIdentifier || xcodeBuildFolder != nil

        // Diagnostics.warning("ENVIRONMENT: \(env)")
        let packageFolderExtension = isXcode ? ".output" : ""

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

        guard let swiftSourceTarget  = peerTarget as? SourceModuleTarget else {
            throw SkipPluginError(errorDescription: "Peer target «\(peerTarget.name)» was not a source module")
        }

        let swiftSourceFiles = swiftSourceTarget.sourceFiles.filter({ $0.type == .source })

        guard !swiftSourceFiles.isEmpty else {
            throw SkipPluginError(errorDescription: "The target «\(peerTarget.name)» does not contain any .swift files for transpilation.")
        }

        let sourceFilePaths = swiftSourceFiles.map(\.path.string)

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

        // the input files consist of all the swift, kotlin, and .yml files in all of the sources
        // having no inputs or outputs in Xcode seems to result in the command running *every* time, but in SPM is appears to have the opposite effect: it never seems to run when there are no inputs or outputs
        //#warning("build sourceFiles from directory rather than from SPM")
        let sourceDir = target.directory
        // TODO: find .swift files in tree
        let _ = sourceDir

        // collect the resources for linking
        var resourceArgs: [String] = []
        for resource in swiftSourceTarget.sourceFiles.filter({ $0.type == .resource }) {
            resourceArgs += ["--resource", resource.path.string]
        }

        // the output files contains the .skipcode.json, and the input files contains all the dependent .skipcode.json files
        let outputURL = URL(fileURLWithPath: outputFolder.string, isDirectory: true)
        //let skipcodeOutputPath = Path(outputURL.appendingPathComponent(peerTarget.name + skipcodeExtension).path)
        let skipbuildMarkerOutputPath = Path(outputURL.appendingPathComponent(peerTarget.name + skipbuildMarker).path)
        //Diagnostics.remark("add skipbuild output for \(target.name): \(skipbuildMarkerOutputPath)", file: skipbuildMarkerOutputPath.string)

        let outputFiles: [Path] = [skipbuildMarkerOutputPath]
        var inputFiles: [Path] = target.sourceFiles.map(\.path) + swiftSourceTarget.sourceFiles.map(\.path)

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
                targetLink = "../../../" + packageID + packageFolderExtension + "/" + target.name + "/" + pluginFolderName + "/" + targetName
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

        for dep in deps {
            guard let depTarget = dep.target as? SourceModuleTarget else {
                // only consider source module targets
                continue
            }

            if skipRootTargetNames.contains(depTarget.name) {
                continue
            }

            if let moduleLinkTarget = try addModuleLinkFlag(depTarget, packageID: dep.package.id) {
                // adds an input file dependency on all the .skipcode.json files output from the dependent targets
                // this should block the invocation of the transpiler plugin for this module
                // until the dependent modules have all been transpiled and their skipcode JSON files emitted
                //let skipcodeInputFile = outputFolder.appending(subpath: moduleLinkTarget + skipcodeExtension)

                // new build system: always output a .skipbuild so the transiler can skip the run for unsupported platforms (i.e., non-macOS) and still be able to use the same input files without the plugin needing to know the target platform (which seems to be a deficiency in the plugin environment)
                let buildMarkerInputFile = outputFolder.appending(subpath: moduleLinkTarget + skipbuildMarker)
                let buildMarkerInputURL = URL(fileURLWithPath: buildMarkerInputFile.string)
                let buildMarkerStandardizedPath = Path(buildMarkerInputURL.standardized.path)
                //Diagnostics.remark("add build marker input to \(depTarget.name): \(buildMarkerStandardizedPath)", file: buildMarkerStandardizedPath.string)
                inputFiles.append(buildMarkerStandardizedPath)
            }
        }

        let outputBase = URL(fileURLWithPath: kotlinModule, isDirectory: true, relativeTo: outputURL)
        let sourceBase = URL(fileURLWithPath: isTest ? "src/test" : "src/main", isDirectory: true, relativeTo: outputBase)

        return [
            .buildCommand(displayName: "Skip \(target.name)", executable: skip.path, arguments: [
                "transpile",
                "--output-folder", sourceBase.path,
                "--module-root", outputBase.path,
                "--skip-folder", skipFolder.string,
                //"--conditional-environment", "SUPPORTED_DEVICE_FAMILIES", // only run if the given environment is unset
                ]
                + resourceArgs
                + buildModuleArgs
                + sourceFilePaths,
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
        return outputDir.appending(subpath: outputFileName)
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
