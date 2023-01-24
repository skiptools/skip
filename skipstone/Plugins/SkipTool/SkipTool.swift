import Foundation
import PackagePlugin

/// Built plugin to invoke our `Skip` tool with source files.
@main struct SkipTool: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let runner = try context.tool(named: "SkipRunner").path
        let inputFiles = inputFiles(in: target.directory)
        return [
            .buildCommand(displayName: "Skip", executable: runner, arguments: inputFiles, outputFiles: [])
        ]
    }

    private func inputFiles(in directory: Path) -> [String] {
        let directoryURL = URL(fileURLWithPath: directory.string, isDirectory: true)
        guard let directoryEnumerator = FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var inputFiles: [String] = []
        for case let fileURL as URL in directoryEnumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]), resourceValues.isDirectory != true else {
                continue
            }
            inputFiles.append(fileURL.path)
        }
        return inputFiles
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SkipTool: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let runner = try context.tool(named: "SkipRunner").path
        let arguments = target.inputFiles
            .filter { $0.type == .source }
            .map { $0.path.string }
        return [
            .buildCommand(displayName: "Skip", executable: runner, arguments: arguments, outputFiles: [])
        ]
    }
}
#endif
