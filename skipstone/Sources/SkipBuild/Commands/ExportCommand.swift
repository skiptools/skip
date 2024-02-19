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

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Perform release build", valueName: "release"))
    var release: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Perform debug build", valueName: "debug"))
    var debug: Bool = true

    func performCommand(with out: MessageQueue) async throws {
        let startTime = Date.now
        let variants = [debug ? "debug" : nil, release ? "release" : nil].compactMap({ $0 })
        if variants.isEmpty {
            throw error("must specify at least one of --release or --debug")
        }

        let packageJSON = try await parseSwiftPackage(with: out, at: project)
        let packageName: String = self.package ?? packageJSON.name

        if build == true {
            await run(with: out, "Build project \(packageName)", ["swift", "build", "-v", "--package-path", project])
        } else {
            await run(with: out, "Resolve dependencies", ["swift", "package", "resolve", "-v", "--package-path", project])
        }

        let fs = localFileSystem

        let androidFolder = self.project + "/Android"
        let androidFolderAbsolute = try AbsolutePath(validating: androidFolder, relativeTo: fs.currentWorkingDirectory!)

        // when we are in an app project (identified by the presence of a Android/settings.gradle.kts file), then we will build the apk
        let isAppProject = fs.isFile(androidFolderAbsolute.appending(component: "settings.gradle.kts")) && self.module.isEmpty

        // if modules is not specified, use all the modules for targets listed in the Package.swift that have a plugin set (although we should probably make sure the plugin is skipstone, this is difficult because the dependency graph is sometimes a string array and sometimes a JSON object)
        let moduleNames = !self.module.isEmpty ? self.module : packageJSON.targets.compactMap(\.a).filter({ $0.type == .regular }).filter({ $0.pluginUsages != nil }).map(\.name)

        // when specified, the output folder; otherwise, relative the the specified project folder's .build folder
        let buildFolder = self.project + "/.build"
        let buildFolderAbsolute = try AbsolutePath(validating: buildFolder, relativeTo: fs.currentWorkingDirectory!)

        let outputFolder = self.dir ?? "\(buildFolder)/skip-export"
        let outputFolderAbsolute = try AbsolutePath(validating: outputFolder, relativeTo: fs.currentWorkingDirectory!)

        let env = ProcessInfo.processInfo.environmentWithDefaultToolPaths // environment that includes a default ANDROID_HOME

        let assembleAction = variants == ["debug"] ? "assembleDebug" : variants == ["release"] ? "assembleRelease" : "assemble"

        // as well as the app itself, also output each of the specified modules (or all the modules if they are not specified)
        for moduleName in moduleNames {
            var gradleArgs: [String] = []
            let skipOutputFolder = buildFolderAbsolute.appending(components: ["plugins", "outputs", packageName, moduleName, "skipstone"])

            if !fs.isDirectory(skipOutputFolder) {
                throw error("The transpilation output folder \(skipOutputFolder.pathString) does not exist. Please ensure the project can be transpiled by running swift test")
            }

            gradleArgs += ["--project-dir", skipOutputFolder.pathString]
            gradleArgs += ["--console=plain"]

            await run(with: out, "Assemble frameworks for \(moduleName)", ["gradle", assembleAction] + gradleArgs, environment: env)

            for variant in variants {
                let aarOutputFolder = outputFolderAbsolute.appending(components: [variant, "aar"])
                try fs.createDirectory(aarOutputFolder, recursive: true)

                let depModuleNames = try fs.getDirectoryContents(skipOutputFolder).sorted()
                for depModuleName in depModuleNames {
                    let aarBuildOutputFolder = skipOutputFolder.appending(components: [depModuleName, "build", "outputs", "aar"])
                    if !fs.isDirectory(aarBuildOutputFolder) {
                        // ignore non-module output folders (e.g., "gradle")
                        continue
                    }

                    let aarName = "\(depModuleName)-\(variant).aar"
                    let aarBuildOutputPath = aarBuildOutputFolder.appending(component: aarName)

                    let aarOutputPath = aarOutputFolder.appending(component: aarName)

                    await outputOptions.monitor(with: out, "Export \(aarName)") { _ in
                        try? fs.removeFileTree(aarOutputPath) // copy will fail if it already exists
                        try fs.copy(from: aarBuildOutputPath, to: aarOutputPath)
                        return try aarOutputPath.asURL.fileSizeString
                    }
                }
            }

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

        if isAppProject, let appModuleName = moduleNames.first {
            var gradleArgs: [String] = []
            gradleArgs += ["--project-dir", androidFolderAbsolute.pathString]
            gradleArgs += ["--console=plain"]

            await run(with: out, "Assemble app \(appModuleName)", ["gradle", assembleAction] + gradleArgs, environment: env)

            for variant in variants {
                let appOutputFolder = outputFolderAbsolute.appending(components: [variant, "apk"])
                try fs.createDirectory(appOutputFolder, recursive: true)

                let appBuildOutputFolder = buildFolderAbsolute.appending(components: ["Android", "app", "outputs", "apk", variant])

                // when the user has set up signing in their build.gradle.kts it will not be called "unsigned"
                let apkNames = variant == "release" ? ["app-release.apk", "app-release-unsigned.apk"] : ["app-debug.apk"]
                let apkOutputName = "\(appModuleName)-\(variant).apk"
                let appOutputPath = appOutputFolder.appending(component: apkOutputName)

                await outputOptions.monitor(with: out, "Export \(apkOutputName)") { _ in
                    try? fs.removeFileTree(appOutputPath) // copy will fail if it already exists
                    // try each of the names, to handle signed and unsigned artifacts
                    for apkName in apkNames {
                        try? fs.copy(from: appBuildOutputFolder.appending(component: apkName), to: appOutputPath)
                    }
                    return try appOutputPath.asURL.fileSizeString
                }
            }
        }

        if showTree {
            await showFileTree(in: outputFolderAbsolute, with: out)
        }

        await out.write(status: .pass, "Skip export \(packageName) to \(outputFolder.abbreviatingWithTilde) (\(startTime.timingSecondsSinceNow))")
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
