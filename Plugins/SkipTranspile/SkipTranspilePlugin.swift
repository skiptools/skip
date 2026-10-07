// Copyright 2023–2026 Skip
import Foundation
import PackagePlugin

/// Command plugin that runs the skipstone transpiler over the given targets and their Skip dependencies without compiling any Swift.
///
/// It writes to the same `.build/plugins/outputs` folders that the `skipstone` build plugin uses, so that `skip export` can assemble the Gradle project from them without a host `swift build`.
///
/// `swift package --disable-sandbox --allow-writing-to-package-directory skip-transpile [--target Name …] [--outputs PROJECT/.build/plugins/outputs]`
@main struct SkipTranspilePlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var argumentExtractor = ArgumentExtractor(arguments)
        let targetNames = argumentExtractor.extractOption(named: "target")
        let outputs = argumentExtractor.extractOption(named: "outputs").last.map({ Path($0) }) ?? context.package.directory.appending(".build", "plugins", "outputs")
        // enable overriding the path to the Skip tool for local development
        let skipToolPath = try ProcessInfo.processInfo.environment["SKIP_COMMAND_OVERRIDE"].flatMap({ Path($0) }) ?? context.tool(named: "skip").path

        // the package that owns each target, which determines its transpile arguments and output folder
        var owners: [Target.ID: Package] = [:]
        var visitedPackageIDs: Set<Package.ID> = []
        func addOwners(_ package: Package) {
            guard visitedPackageIDs.insert(package.id).inserted else { return }
            for target in package.targets {
                owners[target.id] = package
            }
            package.dependencies.forEach({ addOwners($0.package) })
        }
        addOwners(context.package)

        // the same test the build plugin uses to decide which dependencies to link: a Skip/skip.yml in the target folder
        func isSkipModule(_ target: Target) -> Bool {
            guard let target = target as? SourceModuleTarget, !SkipTranspile.skipRootTargetNames.contains(target.name) else { return false }
            return FileManager.default.fileExists(atPath: target.directory.appending("Skip", "skip.yml").string)
        }

        let roots = targetNames.isEmpty
            ? context.package.targets.filter({ isSkipModule($0) && ($0 as? SourceModuleTarget)?.kind != .test })
            : try context.package.targets(named: targetNames)

        // every module to transpile, dependencies before their dependents (recursiveTargetDependencies is topologically sorted)
        var modules: [SourceModuleTarget] = []
        var seenTargetIDs: Set<Target.ID> = []
        for target in roots.flatMap({ $0.recursiveTargetDependencies.filter(isSkipModule) + [$0] }) where seenTargetIDs.insert(target.id).inserted {
            if let module = target as? SourceModuleTarget {
                modules.append(module)
            }
        }

        // a module reads the .skipcode.json of the Skip modules it depends on, so transpile in waves: each wave after all of its dependencies
        // every module is re-transpiled on each run (about 3.5 s of 6 s for a 16-module project on an M-series Mac); skipping modules whose sources and dependencies are unchanged would save that
        var waveIndex: [Target.ID: Int] = [:]
        for module in modules {
            waveIndex[module.id] = (module.recursiveTargetDependencies.compactMap({ waveIndex[$0.id] }).max() ?? -1) + 1
        }
        let waves = Dictionary(grouping: modules, by: { waveIndex[$0.id]! }).sorted(by: { $0.key < $1.key }).map(\.value)

        for wave in waves {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for module in wave {
                    guard let package = owners[module.id] else {
                        throw SkipPluginError(errorDescription: "Could not find the package for target «\(module.name)»")
                    }
                    // the build plugin's work directory for the target under SwiftPM 6: PROJECT_HOME/.build/plugins/outputs/skip-unit/SkipUnit/destination/skipstone
                    let outputFolder = outputs.appending(package.id, module.name, "destination", SkipTranspile.pluginFolderName)
                    try FileManager.default.createDirectory(atPath: outputFolder.string, withIntermediateDirectories: true)
                    let transpile = try SkipTranspile.command(package: package, target: module, outputFolder: outputFolder)
                    group.addTask { try await run(skipToolPath, transpile.arguments, module: module.name) }
                }
                try await group.waitForAll()
            }
        }
    }

    func run(_ tool: Path, _ arguments: [String], module: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool.string)
        process.arguments = arguments
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SkipPluginError(errorDescription: "Skip \(module) failed with exit code \(process.terminationStatus)"))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
