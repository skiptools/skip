import Foundation
import PackagePlugin

/// Build plugin to do pre-work like emit warnings about incompatible Swift before transpiling with Skip.
@main struct SkipPrecheckPlugIn: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let tool = try context.tool(named: "skiptool")
        let outputFolder = context.pluginWorkDirectory
        return [.prebuildCommand(displayName: "Skip Precheck", executable: tool.path, arguments: [], outputFilesDirectory: outputFolder)]
    }
}

//#if canImport(XcodeProjectPlugin)
//import XcodeProjectPlugin
//
//extension SkipPrecheckPlugIn: XcodeBuildToolPlugin {
//    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
//    }
//}
//#endif
