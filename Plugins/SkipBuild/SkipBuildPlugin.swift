// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Affero General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation
import PackagePlugin

/// Command plugin to invoke `skipgradle`.
///
/// Note that this plugin does nothing; it just exists to ensure that skipgradle is built so we can manually execute it with adequate permissions.
/// If ever it becomes possible to execute a post-build plugin, this might be where it takes place.
@main struct SkipBuildPlugIn: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        return []
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SkipBuildPlugIn: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        return []
    }
}
#endif
