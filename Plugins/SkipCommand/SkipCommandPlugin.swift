// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Affero General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation
import PackagePlugin

/// Command plugin to invoke skip as a custom command.
///
///     swift package --disable-sandbox --allow-writing-to-package-directory plugin skip [options] <file>+
///
/// - Note: The location of your Command Line Tools must be set in Xcode->Settings->Locations
@main struct SkipCommand: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        try runCommand(tool: context.tool(named: "skiptool"), arguments: arguments)
    }

    fileprivate func runCommand(tool runner: PackagePlugin.PluginContext.Tool, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: runner.path.string)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SkipCommand: XcodeCommandPlugin {
    func performCommand(context: XcodePluginContext, arguments: [String]) throws {
        try runCommand(tool: context.tool(named: "skiptool"), arguments: arguments)
    }
}
#endif
