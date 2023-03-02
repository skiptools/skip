import Foundation
import PackagePlugin

/// Build plugin to do pre-work like emit warnings about incompatible Swift before transpiling with Skip.
@main struct SkippyTool: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceModuleTarget = target as? SourceModuleTarget else {
            return []
        }
        let runner = try context.tool(named: "SkipRunner").path
        let inputPaths = sourceModuleTarget.sourceFiles(withSuffix: ".swift").map { $0.path }
        let outputDir = context.pluginWorkDirectory
        return inputPaths.map { Command.buildCommand(displayName: "skippy", executable: runner, arguments: ["-skippy", "-O\(outputDir.string)", $0.string], inputFiles: [$0], outputFiles: [$0.outputPath(in: outputDir)]) }
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SkippyTool: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let runner = try context.tool(named: "SkipRunner").path
        let inputPaths = target.inputFiles
            .filter { $0.type == .source && $0.path.extension == "swift" }
            .map { $0.path }
        let outputDir = context.pluginWorkDirectory
        return inputPaths.map { Command.buildCommand(displayName: "skippy", executable: runner, arguments: ["-skippy", "-O\(outputDir.string)", $0.string], inputFiles: [$0], outputFiles: [$0.outputPath(in: outputDir)]) }
    }
}
#endif

extension Path {
    /// Xcode requires that we create an output file in order for incremental build tools to work.
    ///
    /// - Warning: This is duplicated in Runner.
    func outputPath(in outputDir: Path) -> Path {
        var outputFileName = self.lastComponent
        if outputFileName.hasSuffix(".swift") {
            outputFileName = String(lastComponent.dropLast(".swift".count))
        }
        outputFileName += "_skippy.swift"
        return outputDir.appending(subpath: outputFileName)
    }
}
