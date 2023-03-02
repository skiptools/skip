import Foundation
import PackagePlugin

/// Command plugin to invoke our transpilation runner.
///
///     swift package plugin skip [options] <file>+
///
/// - Note: The location of your Command Line Tools must be set in Xcode->Settings->Locations
@main struct SkipCommand: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let runner = try context.tool(named: "SkipRunner")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: runner.path.string)
        process.arguments = arguments
        print("### FORKING:", process)
        try process.run()
        process.waitUntilExit()
    }
}
