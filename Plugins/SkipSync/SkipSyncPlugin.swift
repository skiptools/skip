// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Affero General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation
import PackagePlugin

@main struct SkipSyncPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        try performBuildCommand(.sync, context: context, arguments: arguments)
    }
}

//#if canImport(XcodeProjectPlugin)
//import XcodeProjectPlugin
//
//extension SkipSyncPlugin: XcodeCommandPlugin {
//    /// 👇 This entry point is called when operating on an Xcode project.
//    func performCommand(context: XcodePluginContext, arguments: [String]) throws {
//        //try performBuildCommand(.sync, context: context, arguments: arguments)
//    }
//}
//#endif
