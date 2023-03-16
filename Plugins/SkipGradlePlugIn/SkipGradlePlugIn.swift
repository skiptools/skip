// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation
import PackagePlugin

/// Build plugin to do pre-work like emit warnings about incompatible Swift before transpiling with Skip.
@main struct SkipGradlePlugIn: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let tool = try context.tool(named: "skiptool")
        let outputFolder = context.pluginWorkDirectory
        return [.prebuildCommand(displayName: "Skip Gradle", executable: tool.path, arguments: [], outputFilesDirectory: outputFolder)]
    }
}

//#if canImport(XcodeProjectPlugin)
//import XcodeProjectPlugin
//
//extension SkipGradlePlugIn: XcodeBuildToolPlugin {
//    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
//    }
//}
//#endif
