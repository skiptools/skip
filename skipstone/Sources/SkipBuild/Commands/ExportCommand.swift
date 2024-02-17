import Foundation
import ArgumentParser
import SkipSyntax
import TSCBasic
#if canImport(SkipDriveExternal)
import SkipDriveExternal

extension ExportCommand : GradleHarness { }
fileprivate let exportCommandEnabled = true
#else
fileprivate let exportCommandEnabled = false
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct ExportCommand: MessageCommand, ToolOptionsCommand {
    static var configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export the Gradle project and built artifacts",
        shouldDisplay: exportCommandEnabled)

    @Option(name: [.customShort("d"), .long], help: ArgumentHelp("Export output folder", valueName: "directory"))
    var dir: String?

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(help: ArgumentHelp("App package name", valueName: "package-name"))
    var package: String?

    @Option(help: ArgumentHelp("Modules to export", valueName: "ModuleName"))
    var module: [String] = []

    @Option(help: ArgumentHelp("Project folder", valueName: "dir"))
    var project: String = "."

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Build the Swift project before exporting"))
    var build: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Display a file system tree summary", valueName: "show"))
    var showTree: Bool = false

    func performCommand(with out: MessageQueue) async throws {
        let startTime = Date.now

        let packageJSON = try await parseSwiftPackage(with: out, at: project)
        let packageName: String = self.package ?? packageJSON.name

        if build == true {
            await run(with: out, "Build project \(packageName)", ["swift", "build", "-v", "--package-path", project])
        } else {
            await run(with: out, "Resolve dependencies", ["swift", "package", "resolve", "-v", "--package-path", project])
        }

        //let packageResolvedJSON = try JSONDecoder().decode(PackageResolved.self, from: Data(contentsOf: URL(fileURLWithPath: project + "/Package.resolved")))


        // if modules not specified, use all the modules for targets listed in the Package.swift that have a plugin set (although we should probably make sure the plugin is skipstone, this is difficult because it a JSON like a dependency)
        let moduleNames = !self.module.isEmpty ? self.module : packageJSON.products.map(\.name)

        // alternatively, we could export for all the targets that have a pluginUsage, but some targets won't have a top-level settings.gradle.kts file (like C targets like LibCDemo), so we would need to identify these cases and build against the sub-folder
        //let moduleNames = !self.module.isEmpty ? self.module : packageJSON.targets.compactMap(\.a).filter({ $0.type == .regular }).filter({ $0.pluginUsages != nil }).map(\.name)


        let fs = localFileSystem
        // when specified, the output folder; otherwise, relative the the specified project folder's .build folder
        let buildFolder = self.project + "/.build"
        let buildFolderAbsolute = try AbsolutePath(validating: buildFolder, relativeTo: fs.currentWorkingDirectory!)

        let outputFolder = self.dir ?? "\(buildFolder)/skip-export"
        let outputFolderAbsolute = try AbsolutePath(validating: outputFolder, relativeTo: fs.currentWorkingDirectory!)

        for moduleName in moduleNames {
            var gradleArgs: [String] = []
            let skipOutputFolder = buildFolderAbsolute.appending(components: ["plugins", "outputs", packageName, moduleName, "skipstone"])

            let moduleOutputFolder = outputFolderAbsolute.appending(components: ["artifacts", moduleName])

            if !fs.isDirectory(skipOutputFolder) {
                throw error("The transpilation output folder \(skipOutputFolder.pathString) does not exist. Please ensure the project can be transpiled by running: swift test")
            }
            gradleArgs += ["--project-dir", skipOutputFolder.pathString]
            gradleArgs += ["--console=plain"]
            gradleArgs += ["-Dmaven.repo.local=" + moduleOutputFolder.pathString]
            //gradleArgs += ["-PbuildDir=" + buildFolderAbsolute.appending(component: "skip-export").pathString]

            let env = ProcessInfo.processInfo.environmentWithDefaultToolPaths // environment that includes a default ANDROID_HOME
            await run(with: out, "Assemble archive for \(moduleName)", ["gradle", "publishToMavenLocal"] + gradleArgs, environment: env)

            await outputOptions.monitor(with: out, "Export project for \(moduleName)", resultHandler: { result in
                (result, MessageBlock(status: result?.messageStatusAny, "Export project for \(moduleName)"))
            }) { log in
                let projectOutputFolder = outputFolderAbsolute.appending(components: ["project", moduleName])
                if fs.exists(projectOutputFolder) || fs.isDirectory(projectOutputFolder) {
                    try fs.removeFileTree(projectOutputFolder)
                }
                try fs.createDirectory(projectOutputFolder.parentDirectory, recursive: true)

                try FileManager.default.copyItem(at: skipOutputFolder.asURL, to: projectOutputFolder.asURL, traverseLinks: true, excludeNames: ["build"])
            }
        }

        if showTree {
            await showFileTree(in: outputFolderAbsolute, with: out)
        }

        await out.write(status: .pass, "Skip export \(packageName) to \((outputFolder as NSString).abbreviatingWithTildeInPath) (\(startTime.timingSecondsSinceNow))")
    }
}

extension FileManager {
    func copyItem(at srcURL: URL, to dstURL: URL, traverseLinks: Bool, excludeNames: Set<String>) throws {
        if !traverseLinks {
            // fall back to default copy implementation, which doesn't follow symlinks
            try copyItem(at: srcURL, to: dstURL)
        } else {
            if try srcURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                let resolved = srcURL.resolvingSymlinksInPath()
                if resolved != srcURL {
                    try copyItem(at: resolved, to: dstURL, traverseLinks: traverseLinks, excludeNames: excludeNames)
                }
            } else if try srcURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                let contents = try contentsOfDirectory(at: srcURL, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])
                for subURL in contents {
                    let pathName = subURL.lastPathComponent
                    if excludeNames.contains(pathName) || pathName.hasPrefix(".") {
                        // skip over excluded names and hidden files
                        continue
                    }
                    try createDirectory(at: dstURL, withIntermediateDirectories: true, attributes: nil)
                    let dstFolderURL = dstURL.appendingPathComponent(pathName)
                    try copyItem(at: subURL, to: dstFolderURL, traverseLinks: traverseLinks, excludeNames: excludeNames)
                }
            } else {
                // copy the file directly
                return try copyItem(at: srcURL, to: dstURL)
            }
        }
    }
}
