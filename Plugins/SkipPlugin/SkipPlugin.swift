// Copyright 2023–2026 Skip
import Foundation
import PackagePlugin

/// Build plugin that unifies the preflight linter and the transpiler in a single plugin.
@main struct SkipPlugin: BuildToolPlugin {
    /// The output folder in which to place Skippy files
    let skippyOutputFolder = ".skippy"

    /// The executable command forked by the plugin; this is the build artifact whose name matches the built `skip` binary
    let skipPluginCommandName = "skip"

    /// The file extension for the metadata about skipcode
    //let skipcodeExtension = ".skipcode.json"

    /// The extension to add to the skippy output; these have the `docc` extension merely because that is the only extension of generated files that is not copied as a resource when a package is built: https://github.com/apple/swift-package-manager/blob/0147f7122a2c66eef55dcf17a0e4812320d5c7e6/Sources/PackageLoading/TargetSourcesBuilder.swift#L665
    let skippyOuptputExtension = ".skippy"

    /// Whether we should run in Skippy or full-transpile mode
    let skippyOnly = ProcessInfo.processInfo.environment["CONFIGURATION"] == "Skippy"

    /// Whether to turn off the Skip plugin manually
    let skipDisabled = (ProcessInfo.processInfo.environment["SKIP_PLUGIN_DISABLED"] ?? "0") != "0"

    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        if skipDisabled {
            Diagnostics.remark("Skip plugin disabled through SKIP_PLUGIN_DISABLED environment variable")
            return []
        }

        if SkipTranspile.skipRootTargetNames.contains(target.name) {
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
        let skip = try context.tool(named: skipPluginCommandName)
        // enable overriding the path to the Skip tool for local development
        let skipToolPath = ProcessInfo.processInfo.environment["SKIP_COMMAND_OVERRIDE"].flatMap({ Path($0) }) ?? skip.path

        let transpile = try SkipTranspile.command(package: context.package, target: target, outputFolder: context.pluginWorkDirectory)
        return [
            .buildCommand(displayName: "Skip \(target.name)", executable: skipToolPath, arguments: transpile.arguments,
                inputFiles: transpile.inputFiles,
                outputFiles: transpile.outputFiles)
        ]
    }
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
