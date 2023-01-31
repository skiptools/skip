import Foundation
import PackagePlugin

/// Build plugin to do pre-work like emit warnings about incompatible Swift before transpiling with Skip.
@main struct SkippyTool: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceModuleTarget = target as? SourceModuleTarget else {
            return []
        }
        let runner = try context.tool(named: "SkipRunner").path
        let inputPaths = sourceModuleTarget.sourceFiles(withSuffix: "swift").map { $0.path }
        let outputDir = context.pluginWorkDirectory
        return inputPaths.map { Command.buildCommand(displayName: "skippy", executable: runner, arguments: ["-skippy", "-O\(outputDir.string)", $0.string], inputFiles: [$0], outputFiles: [$0.skipPath(in: outputDir)]) }
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
        return inputPaths.map { Command.buildCommand(displayName: "skippy", executable: runner, arguments: ["-skippy", "-O\(outputDir.string)", $0.string], inputFiles: [$0], outputFiles: [$0.skipPath(in: outputDir)]) }
    }
}
#endif

extension Path {
    func skipPath(in outputDir: Path) -> Path {
        let lastComponent = self.lastComponent
        var extensionLength = 0
        if let ext = self.extension {
            extensionLength = ext.count + 1
        }
        return outputDir.appending(subpath: lastComponent.dropLast(extensionLength) + ".skip")
    }
}
