// Copyright 2024–2025 Skip
import Foundation
import PackagePlugin

/// Command plugin that create a local link to the transpiled output
@main struct SkipPlugin: CommandPlugin {
    func performCommand(context: PackagePlugin.PluginContext, arguments: [String]) async throws {
        let packageID = context.package.id

        let packageFolder = URL(fileURLWithPath: context.package.directory.string)
        let skipLinkFolder = packageFolder.appendingPathComponent("SkipLink")

        // When ran from Xcode, the plugin command is invoked with `--target` arguments,
        // specifying the targets selected in the plugin dialog.
        var argumentExtractor = ArgumentExtractor(arguments)
        let inputTargets = argumentExtractor.extractOption(named: "target")

        let skipLinkOutut = URL(fileURLWithPath: context.pluginWorkDirectory.string)
        for targetName in inputTargets {
            let skipstoneTargetOutput = skipLinkOutut
                .deletingLastPathComponent()
                .appendingPathComponent(packageID + ".output")
                .appendingPathComponent(targetName)
                .appendingPathComponent("skipstone")
                .resolvingSymlinksInPath()

            if (try? skipstoneTargetOutput.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
                Diagnostics.warning("skipstone output folder did not exist: \(skipstoneTargetOutput.path)")
            } else {
                // create the link from the local folder to the derived data output, replacing any existing link
                try FileManager.default.createDirectory(at: skipLinkFolder, withIntermediateDirectories: true)
                let targetLinkFolder = skipLinkFolder.appendingPathComponent(targetName)
                Diagnostics.remark("creating link from \(skipstoneTargetOutput.path) to \(targetLinkFolder.path)")

                // clear any pre-existing links
                if (try? targetLinkFolder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    try FileManager.default.removeItem(at: targetLinkFolder)
                }
                try FileManager.default.createSymbolicLink(at: targetLinkFolder, withDestinationURL: skipstoneTargetOutput)
            }
        }
    }
}

