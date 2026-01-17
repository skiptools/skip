// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

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
        usage: """
# export just the debug version of the archives
skip export --debug

# export just the "ModuleName" module
skip export --module ModuleName
""",
        discussion: """
Build and export the Skip modules defined in the Package.swift, with libraries exported as .aar files and the app exported as an .apk and .adb file suitable for distribution.
""",
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

    @Option(help: ArgumentHelp("Output summary path", valueName: "file"))
    var summaryFile: String? = nil

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Build the Swift project before exporting"))
    var build: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Display a file system tree summary", valueName: "show"))
    var showTree: Bool = false

    @Flag(help: ArgumentHelp("Perform release build", valueName: "release"))
    var release: Bool = false

    @Flag(help: ArgumentHelp("Perform debug build", valueName: "debug"))
    var debug: Bool = false

    // TODO: immediately fail when any of the steps fail
    //@Flag(inversion: .prefixedNo, help: ArgumentHelp("Stop the process on the first error"))
    //var failFast: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Export project sources", valueName: "source"))
    var exportProject: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Export iOS .ipa"))
    var ios: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Export Android .apk"))
    var android: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Output folders to variant sub-folders", valueName: "nest"))
    var nested: Bool = false

    @Option(help: ArgumentHelp("SDK path for export build", valueName: "sdk dir"))
    var sdkPath: String? = nil

    @Option(help: ArgumentHelp("Project scheme name to export", valueName: "scheme"))
    var schemeName: String? = nil

    @Option(help: ArgumentHelp("Destination architectures for native libraries", valueName: "arch"))
    var arch: [AndroidArchArgument] = []

    func performCommand(with out: MessageQueue) async {
        await withLogStream(with: out) {
            try await runExport(with: out)
        }
    }

    func runExport(with out: MessageQueue) async throws {
        let startTime = Date.now
        var createdURLs: [URL] = []
        let releaseDebugUnspecified = debug == false && release == false
        let variants: [BuildConfiguration] = [((debug == true) || releaseDebugUnspecified) ? .debug : nil, ((release == true) || releaseDebugUnspecified) ? .release : nil].compactMap({ $0 })
        if variants.isEmpty {
            throw error("must specify at least one of --release or --debug")
        }

        let packageJSON = try await parseSwiftPackage(with: out, at: project)
        let packageName: String = self.package ?? packageJSON.name

        if build == true {

            // This builds for macOS
            // await run(with: out, "Build project \(packageName)", ["swift", "build", "-v", "--package-path", project, "-Xswiftc", "-target", "-Xswiftc", "arm64-apple-ios"])

            // to build for iOS, we need to do something like this:
            //swift build  --package-path . -Xswiftc -sdk -Xswiftc `xcrun --sdk iphonesimulator --show-sdk-path` -Xswiftc -target -Xswiftc arm64-apple-ios`xcrun --sdk iphonesimulator --show-sdk-version`-simulator

            func fetchSDKPath() async throws -> String? {
                // the "--sdk-path" argument
                if let sdkPath = self.sdkPath {
                    return sdkPath
                }

                return try await run(with: out, "Getting SDK Path", "xcrun --sdk iphoneos --show-sdk-path".split(separator: " ").map(\.description), watch: false).get().stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let sdk = try? await fetchSDKPath(), sdk != "legacy" {
                try await run(with: out, "Build project \(packageName)", ["xcrun", "swift", "build", "-v", "--package-path", project, "--triple", "arm64-apple-ios", "--sdk", sdk])
            } else {
                // fallback to plain "swift build" for legacy build, which has the down-side that it will build against macOS (and thereby fail when there are iOS-only API calls): "Basics/Triple+Basics.swift:149: Fatal error: Cannot create dynamic libraries for os "ios".", also @availability annotations are required for everything
                // however, it permits us to build and export against macOS-13/Xcode 15.2 (which is the OS version needed for GitHub CI to be able to run tests against the Android Emulator using the reactivecircus/android-emulator-runner action),
                try await run(with: out, "Build project \(packageName)", ["swift", "build", "-v", "--package-path", project])
            }
        } else {
            try await run(with: out, "Resolve dependencies", ["swift", "package", "resolve", "-v", "--package-path", project])
        }

        let fs = localFileSystem

        let androidFolder = self.project + "/Android"
        let androidFolderAbsolute = try AbsolutePath(validating: androidFolder, relativeTo: fs.currentWorkingDirectory!)

        // when we are in an app project (identified by the presence of a Android/settings.gradle.kts file), then we will build the apk
        let isAppProject = fs.isFile(androidFolderAbsolute.appending(component: "settings.gradle.kts")) && self.module.isEmpty

        // if modules is not specified, use all the modules for targets listed in the Package.swift that have a plugin set (although we should probably make sure the plugin is skipstone, this is difficult because the dependency graph is sometimes a string array and sometimes a JSON object)
        let moduleNames = !self.module.isEmpty ? self.module : packageJSON.targets.compactMap(\.a).filter({ $0.type == "regular" }).filter({ $0.pluginUsages != nil }).map(\.name)

        // when specified, the output folder; otherwise, relative the the specified project folder's .build folder
        let buildFolder = self.project + "/.build"
        let buildFolderAbsolute = try AbsolutePath(validating: buildFolder, relativeTo: fs.currentWorkingDirectory!)

        let outputFolder = self.dir ?? "\(buildFolder)/skip-export"
        let outputFolderAbsolute = try AbsolutePath(validating: outputFolder, relativeTo: fs.currentWorkingDirectory!)

        var env = ProcessInfo.processInfo.environmentWithDefaultToolPaths // environment that includes a default ANDROID_HOME

        if !arch.isEmpty {
            // take the arch flag(s) and set them in the `SKIP_EXPORT_ARCHS` environment, which will be processed by the AndroidCommand when it sees the SkipBridge `--arch automatic` setting
            env[AndroidArchArgument.exportArchsEnvironment] = arch.map(\.rawValue).joined(separator: ",")
        }

        let assembleAction = variants == [.debug] ? "assembleDebug" : variants == [.release] ? "assembleRelease" : "assemble"
        let bundleAction = variants == [.debug] ? "bundleDebug" : variants == [.release] ? "bundleRelease" : "bundle"


        if isAppProject, let appModuleName = moduleNames.first {
            let projectURL = URL(fileURLWithPath: self.project)

            func validateLayoutURL(url: URL, isDirectory: Bool) throws {
                // we do not perform validaton of the project files
                return
            }

            let projectLayout = try AppProjectLayout(moduleName: appModuleName, root: projectURL, check: validateLayoutURL)

            if self.ios { // create iOS .ipa
                for variant in variants {
                    let outputFolder = !nested ? outputFolderAbsolute : outputFolderAbsolute.appending(components: [variant.rawValue, "ipa"])
                    try fs.createDirectory(outputFolder, recursive: true)
                    let variantSuffix = /* variant == .release ? "" : */ "-\(variant)"
                    let outputName = "\(appModuleName)\(variantSuffix)"
                    let ipaOutputPath = outputFolder.appending(component: outputName + ".ipa")
                    let xcarchiveOutputPath = outputFolder.appending(component: outputName + ".xcarchive.zip")

                    _ = try await createIPA(configuration: variant, schemeName: self.schemeName, primaryModuleName: appModuleName, cfgSuffix: "-" + variant.rawValue, projectURL: projectURL, out: out, prefix: "", xcodeProjectURL: projectLayout.darwinProjectFolder, ipaURL: ipaOutputPath.asURL, xcarchiveURL: xcarchiveOutputPath.asURL, verifyFile: false, returnHashes: false)

                    createdURLs.append(ipaOutputPath.asURL)
                    createdURLs.append(xcarchiveOutputPath.asURL)
                }
            }

            if self.android {
                var gradleArgs: [String] = []
                gradleArgs += ["--project-dir", androidFolderAbsolute.pathString]
                gradleArgs += ["--console=plain"]

                try await run(with: out, "Assemble Android app \(appModuleName)", ["gradle", assembleAction] + gradleArgs, environment: env)
                try await exportAndroidArtifact(type: "apk")

                try await run(with: out, "Bundle Android app \(appModuleName)", ["gradle", bundleAction] + gradleArgs, environment: env)
                try await exportAndroidArtifact(type: "bundle")

                func exportAndroidArtifact(type: String) async throws {
                    for variant in variants {
                        let outputFolder = !nested ? outputFolderAbsolute : outputFolderAbsolute.appending(components: [variant.rawValue, type])
                        try fs.createDirectory(outputFolder, recursive: true)

                        let ext = type == "bundle" ? "aab" : type
                        // when the user has set up signing in their build.gradle.kts it will not be called "unsigned"
                        let names = variant == .release ? ["app-release.\(ext)", "app-release-unsigned.\(ext)"] : ["app-debug.\(ext)"]

                        let variantSuffix = /* variant == .release ? "" : */ "-\(variant)"
                        let outputName = "\(appModuleName)\(variantSuffix).\(ext)"
                        let outputPath = outputFolder.appending(component: outputName)

                        let buildOutputFolder = buildFolderAbsolute.appending(components: ["Android", "app", "outputs", type, variant.rawValue])
                        await outputOptions.monitor(with: out, "Export \(outputName)") { _ in
                            try? fs.removeFileTree(outputPath) // copy will fail if it already exists
                            // try each of the names, to handle signed and unsigned artifacts
                            for name in names {
                                try? fs.copy(from: buildOutputFolder.appending(component: name), to: outputPath)
                            }
                            createdURLs.append(outputPath.asURL)
                            return try outputPath.asURL.fileSizeString
                        }
                    }
                }
            }
        } else { // not an app project; export the individual modules instead
            for moduleName in moduleNames {
                var gradleArgs: [String] = []
                let skipOutputFolder = try buildPluginOutputFolder(forModule: moduleName, inBuildFolder: buildFolderAbsolute)

                if !fs.isDirectory(skipOutputFolder) {
                    throw error("The transpilation output folder \(skipOutputFolder.pathString) does not exist. Please ensure the project can be transpiled by running swift test")
                }

                gradleArgs += ["--project-dir", skipOutputFolder.pathString]
                gradleArgs += ["--console=plain"]

                try await run(with: out, "Assemble frameworks for \(moduleName)", ["gradle", assembleAction] + gradleArgs, environment: env)

                for variant in variants {
                    let aarOutputFolder = !nested ? outputFolderAbsolute : outputFolderAbsolute.appending(components: [variant.rawValue, "aar"])
                    try fs.createDirectory(aarOutputFolder, recursive: true)

                    let depModuleNames = try fs.getDirectoryContents(skipOutputFolder).sorted()
                    for depModuleName in depModuleNames {
                        let aarBuildOutputFolder = skipOutputFolder.appending(components: [depModuleName, "build", "outputs", "aar"])
                        if !fs.isDirectory(aarBuildOutputFolder) {
                            // ignore non-module output folders (e.g., "gradle")
                            continue
                        }

                        let variantSuffix = /* variant == .release ? "" : */ "-\(variant)"
                        let aarName = "\(depModuleName)\(variantSuffix).aar"
                        let aarBuildOutputPath = aarBuildOutputFolder.appending(component: aarName)

                        let aarOutputPath = aarOutputFolder.appending(component: aarName)

                        await outputOptions.monitor(with: out, "Export \(aarName)") { _ in
                            try? fs.removeFileTree(aarOutputPath) // copy will fail if it already exists
                            try fs.copy(from: aarBuildOutputPath, to: aarOutputPath)
                            createdURLs.append(aarOutputPath.asURL)
                            return try aarOutputPath.asURL.fileSizeString
                        }
                    }
                }
            }
        }

        if exportProject, let moduleName = moduleNames.first {
            let skipOutputFolder = try buildPluginOutputFolder(forModule: moduleName, inBuildFolder: buildFolderAbsolute)

            let projectOutputBaseFolder = outputFolderAbsolute.appending(components: ["project"])
            let projectOutputFolder = projectOutputBaseFolder.appending(components: [moduleName])

            await outputOptions.monitor(with: out, "Export project \(moduleName)", resultHandler: { result in
                return (result, MessageBlock(status: result?.messageStatusAny, "Export project for \(moduleName)"))
            }) { log in
                if fs.exists(projectOutputFolder) || fs.isDirectory(projectOutputFolder) {
                    try fs.removeFileTree(projectOutputFolder)
                }
                try fs.createDirectory(projectOutputFolder.parentDirectory, recursive: true)

                try FileManager.default.copyItem(at: skipOutputFolder.asURL, to: projectOutputFolder.asURL, traverseLinks: true, excludeNames: ["build", ".build", "skip-export"])
            }

            let projectExportZip = outputFolderAbsolute.appending(components: ["\(moduleName)-project.zip"])

            try await zipFolder(with: out, message: "Archive project source \(projectExportZip.asURL.lastPathComponent)", zipFile: projectExportZip.asURL, folder: projectOutputFolder.asURL)
            createdURLs.append(projectExportZip.asURL)

            try fs.removeFileTree(projectOutputBaseFolder) // only export the zip file; remove the sources
        }

        let outputFolderTitle = outputFolder.abbreviatingWithTilde

        await out.write(status: .pass, "Skip export \(packageName) to \(outputFolderTitle) (\(startTime.timingSecondsSinceNow))")

        // output the summary file to the given path (e.g., $GITHUB_STEP_SUMMARY or "-" for stdout)
        if let summaryFile = summaryFile {
            var summary = """
            Artifact | Size
            --- | ---

            """

            // show the output of each of the generated files in a table
            for createdURL in createdURLs.sorted(by: {
                $0.lastPathComponent < $1.lastPathComponent
            }) {
                summary += try createdURL.lastPathComponent + " | " + createdURL.fileSizeString + "\n"
            }

            if summaryFile == "-" {
                print(summary)
            } else {
                try summary.write(toFile: summaryFile, atomically: false, encoding: .utf8)
            }
        }

        if showTree {
            await showFileTree(in: outputFolderAbsolute, folderName: outputFolderTitle, with: out)
        }
        
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
