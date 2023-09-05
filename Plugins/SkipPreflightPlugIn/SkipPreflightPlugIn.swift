// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation
import PackagePlugin

let preflightOutputSuffix = "_skippy"

/// Build plugin to do pre-work like emit warnings about incompatible Swift before transpiling with Skip.
@main struct SkipPreflightPlugIn: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceModuleTarget = target as? SourceModuleTarget else {
            return []
        }
        let runner = try context.tool(named: "SkipTool").path
        let inputPaths = sourceModuleTarget.sourceFiles(withSuffix: ".swift").map { $0.path }
        let outputDir = context.pluginWorkDirectory
        return inputPaths.map { Command.buildCommand(displayName: "Skippy \(target.name)", executable: runner, arguments: ["skippy", "-O", outputDir.string, "--", preflightOutputSuffix, $0.string], inputFiles: [$0], outputFiles: [$0.outputPath(in: outputDir)]) }
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SkipPreflightPlugIn: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let runner = try context.tool(named: "SkipTool").path
        let inputPaths = target.inputFiles
            .filter { $0.type == .source && $0.path.extension == "swift" }
            .map { $0.path }
        let outputDir = context.pluginWorkDirectory
        return inputPaths.map { Command.buildCommand(displayName: "Skip Preflight \(target.displayName)", executable: runner, arguments: ["skippy", "-O", "\(outputDir.string)", $0.string], inputFiles: [$0], outputFiles: [$0.outputPath(in: outputDir)]) }
    }
}
#endif

extension Path {
    /// Xcode requires that we create an output file in order for incremental build tools to work.
    ///
    /// - Warning: This is duplicated in SkippyCommand.
    func outputPath(in outputDir: Path) -> Path {
        var outputFileName = self.lastComponent
        if outputFileName.hasSuffix(".swift") {
            outputFileName = String(lastComponent.dropLast(".swift".count))
        }
        outputFileName += preflightOutputSuffix + ".swift"
        return outputDir.appending(subpath: outputFileName)
    }
}
