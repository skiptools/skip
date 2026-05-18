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

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Export iOS simulator .app.zip"))
    var iosSim: Bool = false

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

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Generate appindex.json metadata alongside export artifacts"))
    var appindex: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Create a symlink from app Resources to the generated appindex.json"))
    var linkAppindex: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Unpack the exported app project zip into a temp folder and run `gradle assembleDebug` there to confirm the export builds standalone without Skip installed"))
    var validateExport: Bool = false

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

            // Generate and link app index before building so it is included in the app bundle
            if self.appindex {
                let catalog = try await AppIndexGenerator.generateAppIndex(projectURL: projectURL, packageJSON: packageJSON, includeSBOM: true, command: self, out: out)
                try fs.createDirectory(outputFolderAbsolute, recursive: true)
                let appIndexURL = outputFolderAbsolute.asURL.appendingPathComponent(AppIndexGenerator.appIndexFilename)
                let indexURL = try await AppIndexGenerator.writeAppIndex(catalog, to: appIndexURL, linkResource: self.linkAppindex, appModuleName: appModuleName, projectURL: projectURL, out: out)
                createdURLs.append(indexURL)
                await out.write(status: .pass, "Generated \(AppIndexGenerator.appIndexFilename)")
            }

            // Resolve the scheme name once for all iOS builds
            let appSchemeName = (self.ios || self.iosSim) ? try await resolveAppSchemeName(schemeName: self.schemeName, xcodeProjectURL: projectLayout.darwinProjectFolder, out: out) : nil

            if self.ios { // create iOS .ipa
                for variant in variants {
                    let outputFolder = !nested ? outputFolderAbsolute : outputFolderAbsolute.appending(components: [variant.rawValue, "ipa"])
                    try fs.createDirectory(outputFolder, recursive: true)
                    let variantSuffix = /* variant == .release ? "" : */ "-\(variant)"
                    let outputName = "\(appModuleName)\(variantSuffix)"
                    let ipaOutputPath = outputFolder.appending(component: outputName + ".ipa")
                    let xcarchiveOutputPath = outputFolder.appending(component: outputName + ".xcarchive.zip")

                    _ = try await createIPA(configuration: variant, appSchemeName: appSchemeName!, primaryModuleName: appModuleName, cfgSuffix: "-" + variant.rawValue, projectURL: projectURL, out: out, prefix: "", xcodeProjectURL: projectLayout.darwinProjectFolder, ipaURL: ipaOutputPath.asURL, xcarchiveURL: xcarchiveOutputPath.asURL, verifyFile: false, returnHashes: false)

                    createdURLs.append(ipaOutputPath.asURL)
                    createdURLs.append(xcarchiveOutputPath.asURL)
                }
            }

            if self.iosSim { // create iOS simulator .app.zip
                for variant in variants {
                    let outputFolder = !nested ? outputFolderAbsolute : outputFolderAbsolute.appending(components: [variant.rawValue, "simulator"])
                    try fs.createDirectory(outputFolder, recursive: true)

                    let cfg = variant.rawValue.capitalized
                    let variantSuffix = "-Simulator-\(cfg)"
                    let zipName = "\(appModuleName)\(variantSuffix).app.zip"
                    let zipOutputPath = outputFolder.appending(component: zipName)
                    try? fs.removeFileTree(zipOutputPath) // zip will fail if it already exists

                    try await createSimApp(configuration: variant, appSchemeName: appSchemeName!, primaryModuleName: appModuleName, projectURL: projectURL, out: out, xcodeProjectURL: projectLayout.darwinProjectFolder, simAppURL: zipOutputPath.asURL)
                    createdURLs.append(zipOutputPath.asURL)
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

                // For app projects, fold the Android/ scaffold and Skip.env
                // into the exported zip and patch out the skip plugin
                // dependencies so the project can build with plain `gradle`
                // on a host without the Skip CLI installed. See
                // `extendExportWithAndroidScaffold` for the surgery details.
                if isAppProject {
                    let projectURL = URL(fileURLWithPath: self.project)
                    try Self.extendExportWithAndroidScaffold(
                        projectURL: projectURL,
                        exportRoot: projectOutputFolder.asURL,
                        appModuleName: moduleName)
                }
            }

            let projectExportZip = outputFolderAbsolute.appending(components: ["\(moduleName)-project.zip"])

            try await zipFolder(with: out, message: "Archive project source \(projectExportZip.asURL.lastPathComponent)", zipFile: projectExportZip.asURL, folder: projectOutputFolder.asURL)
            createdURLs.append(projectExportZip.asURL)

            // When `--validate-export` is set, unpack the zip into a private
            // temp folder and run `gradle assembleDebug` to prove the export
            // truly stands alone (no Skip CLI, no `skip-build-plugin`
            // dependency). The temp folder is removed on success.
            if isAppProject && self.validateExport {
                try await self.validateExportedProjectZip(
                    zipFile: projectExportZip.asURL,
                    appModuleName: moduleName,
                    env: env,
                    out: out)
            }

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

    /// Copy the project's `Android/` scaffold and `Skip.env` into an already-
    /// populated `exportRoot` (the per-module export folder that holds the
    /// transpiled sources), then add the local infrastructure that lets the
    /// project build standalone without the Skip CLI.
    ///
    /// Approach (does NOT modify `Android/app/build.gradle.kts`):
    ///   * `Android/settings.gradle.kts` is replaced with a copy of the
    ///     transpiled root's `settings.gradle.kts` whose `project(":X").projectDir`
    ///     paths are rewritten to point one directory up (because the Android/
    ///     folder lives next to the transpiled modules in the export). The
    ///     `:app` project is then included so the Android app builds against
    ///     the transpiled libraries as plain Gradle projects.
    ///   * `Android/buildSrc/` is generated with a precompiled-script plugin
    ///     `skip-build-plugin.gradle.kts`. Gradle's `kotlin-dsl` plugin
    ///     registers it as a project plugin with id `skip-build-plugin`, the
    ///     same id requested by `Android/app/build.gradle.kts`. The plugin
    ///     reads `Skip.env` and applies the manifest placeholder /
    ///     applicationId / versionCode / versionName / module dependency
    ///     wiring that the upstream skip-build-plugin does at runtime.
    ///   * `Android/gradle.properties` gets a JVM heap bump appended so the
    ///     Kotlin compile of the transpiled SkipUI module fits in memory.
    ///
    /// Sensitive files (`keystore.jks`, `keystore.properties`), Gradle's local
    /// cache (`build/`, `.gradle/`), and any prior `skip-export/` output are
    /// filtered out of the copy.
    static func extendExportWithAndroidScaffold(projectURL: URL, exportRoot: URL, appModuleName: String) throws {
        let fm = FileManager.default
        let androidSrcURL = projectURL.appendingPathComponent("Android", isDirectory: true)
        let androidDstURL = exportRoot.appendingPathComponent("Android", isDirectory: true)

        // Nothing to do for a non-app or otherwise non-conventional project.
        guard fm.fileExists(atPath: androidSrcURL.path) else { return }

        // Defensive: a previous export run could have left the destination in
        // place. Remove it first so the copy starts clean.
        if fm.fileExists(atPath: androidDstURL.path) {
            try fm.removeItem(at: androidDstURL)
        }
        try fm.copyItem(at: androidSrcURL, to: androidDstURL, traverseLinks: true, excludeNames: standaloneExportAndroidExcludes)

        // Copy Skip.env into the export root so the registered
        // skip-build-plugin precompiled script can read it via
        // `rootDir.parentFile` from inside Android/.
        let skipEnvSrcURL = projectURL.appendingPathComponent("Skip.env")
        if fm.fileExists(atPath: skipEnvSrcURL.path) {
            let skipEnvDstURL = exportRoot.appendingPathComponent("Skip.env")
            if fm.fileExists(atPath: skipEnvDstURL.path) {
                try fm.removeItem(at: skipEnvDstURL)
            }
            try fm.copyItem(at: skipEnvSrcURL, to: skipEnvDstURL)
        }

        // Rewrite Android/settings.gradle.kts to use the transpiled root's
        // settings, with project paths shifted up one directory plus an
        // include() for the app/ subproject. This drops the `skip plugin
        // --prebuild` invocation in the original file, which would require
        // the Skip CLI to be on PATH.
        let transpiledSettingsURL = exportRoot.appendingPathComponent("settings.gradle.kts")
        if fm.fileExists(atPath: transpiledSettingsURL.path) {
            let transpiledSettings = try String(contentsOf: transpiledSettingsURL, encoding: .utf8)
            let standaloneSettings = standaloneAndroidSettings(transpiledSettings: transpiledSettings)
            let androidSettingsURL = androidDstURL.appendingPathComponent("settings.gradle.kts")
            try standaloneSettings.write(to: androidSettingsURL, atomically: false, encoding: .utf8)
        }

        // Drop a buildSrc-based skip-build-plugin into the export so the
        // unchanged `id("skip-build-plugin")` request in Android/app/build.gradle.kts
        // resolves to a precompiled script plugin local to the project.
        try writeStandaloneSkipBuildPluginBuildSrc(androidRoot: androidDstURL)

        // Bump the JVM heap in Android/gradle.properties so subsequent
        // gradle invocations (including --validate-export) have enough
        // memory for the Kotlin compile pass.
        try ensureStandaloneGradleProperties(androidRoot: androidDstURL)
    }

    /// File / directory names excluded when copying the project's Android/
    /// folder into the standalone export. Hidden entries (`.gradle`, `.idea`,
    /// etc.) are already filtered by `copyItem(at:to:traverseLinks:excludeNames:)`.
    static let standaloneExportAndroidExcludes: Set<String> = [
        "build", ".build", ".gradle", "skip-export",
        // Signing material must never leak into a redistributable export.
        "keystore.jks", "keystore.properties",
    ]

    /// Transform the transpiled root's settings.gradle.kts into the form the
    /// standalone Android/ folder needs: shift the `file("X")` project paths
    /// up one directory (since Android/ lives below the transpiled root in
    /// the export) and tack on the `:app` include.
    static func standaloneAndroidSettings(transpiledSettings: String) -> String {
        // Each transpiled module declares
        //   project(":X").projectDir = file("X")
        // which is relative to the settings file. In our standalone layout
        // Android/ is one level below, so adjust to `file("../X")`.
        var content = transpiledSettings.replacingOccurrences(
            of: ".projectDir = file(\"",
            with: ".projectDir = file(\"../")

        if !content.hasSuffix("\n") { content += "\n" }
        content += """

        // ---- Skip standalone export: include the Android :app module ----
        include(":app")
        project(":app").projectDir = file("app")
        """
        return content
    }

    /// Create `Android/buildSrc/` so that Gradle's `kotlin-dsl` plugin
    /// registers a precompiled script plugin named `skip-build-plugin` that
    /// satisfies the `id("skip-build-plugin")` reference in the project's
    /// `Android/app/build.gradle.kts`. The generated plugin reads Skip.env
    /// directly and applies the same applicationId / versionCode /
    /// versionName / manifestPlaceholders / module dependency wiring that
    /// the Skip-CLI-provided skip-build-plugin does at runtime.
    static func writeStandaloneSkipBuildPluginBuildSrc(androidRoot: URL) throws {
        let fm = FileManager.default
        let buildSrcURL = androidRoot.appendingPathComponent("buildSrc", isDirectory: true)

        // If the user already has a buildSrc/ folder, do not overwrite it —
        // their own conventions belong there. The skip-build-plugin id will
        // not resolve in that case, which is a clear signal to the user.
        if fm.fileExists(atPath: buildSrcURL.path) {
            return
        }

        let pluginsDir = buildSrcURL.appendingPathComponent("src/main/kotlin", isDirectory: true)
        try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)

        let buildGradleKts = buildSrcURL.appendingPathComponent("build.gradle.kts")
        try standaloneBuildSrcBuildGradleContent.write(to: buildGradleKts, atomically: false, encoding: .utf8)

        let pluginScript = pluginsDir.appendingPathComponent("skip-build-plugin.gradle.kts")
        try standaloneSkipBuildPluginScriptContent.write(to: pluginScript, atomically: false, encoding: .utf8)
    }

    /// Append a higher JVM heap setting to `Android/gradle.properties` so
    /// downstream `gradle assembleDebug` (including the one driven by
    /// `--validate-export`) has enough memory to compile the transpiled
    /// SkipUI module. Properties parsing uses last-write-wins semantics, so
    /// appending is enough to override any lower `org.gradle.jvmargs` already
    /// set in the file.
    static func ensureStandaloneGradleProperties(androidRoot: URL) throws {
        let fm = FileManager.default
        let gradlePropertiesURL = androidRoot.appendingPathComponent("gradle.properties")
        var existing = ""
        if fm.fileExists(atPath: gradlePropertiesURL.path) {
            existing = (try? String(contentsOf: gradlePropertiesURL, encoding: .utf8)) ?? ""
        }
        if existing.contains("# Skip standalone export") {
            return // already extended on a prior export pass
        }
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let updated = existing + separator + standaloneGradlePropertiesAppendix
        try updated.write(to: gradlePropertiesURL, atomically: false, encoding: .utf8)
    }

    /// `buildSrc/build.gradle.kts` — enables Gradle's Kotlin DSL precompiled
    /// script plugin mechanism. Nothing else is needed; the kotlin-dsl
    /// plugin handles compilation and registration.
    static let standaloneBuildSrcBuildGradleContent: String = """
// Generated by `skip export` to register the local
// `skip-build-plugin` precompiled script plugin.
plugins {
    `kotlin-dsl`
}

repositories {
    mavenCentral()
    google()
    gradlePluginPortal()
}
"""

    /// `buildSrc/src/main/kotlin/skip-build-plugin.gradle.kts` — Gradle's
    /// kotlin-dsl plugin compiles this into a project plugin with id
    /// `skip-build-plugin` (the script name minus the `.gradle.kts` suffix).
    /// This is the same id that `Android/app/build.gradle.kts` requests via
    /// `id("skip-build-plugin")`, so no edits to that file are needed.
    ///
    /// The script avoids depending on AGP types by configuring the
    /// `android {}` extension through `withGroovyBuilder`; the user's
    /// build.gradle.kts lists `alias(libs.plugins.android.application)` ahead
    /// of `id("skip-build-plugin")`, so AGP has already registered its
    /// extension by the time this plugin's body runs.
    static let standaloneSkipBuildPluginScriptContent: String = """
// ----------------------------------------------------------------
// Local stand-in for the `skip-build-plugin` shipped with the Skip CLI.
// Generated by `skip export` so the exported project builds on a host
// without Skip installed; functionally equivalent to SkipBuildPlugin in
// skipstone's PluginCommand.swift, but reads Skip.env directly without
// invoking the Skip toolchain.
//
// The script name registers this as a precompiled script plugin with id
// `skip-build-plugin`, satisfying the `id("skip-build-plugin")` request
// in Android/app/build.gradle.kts.
// ----------------------------------------------------------------
import java.util.Properties
import org.gradle.api.GradleException
import org.gradle.kotlin.dsl.withGroovyBuilder

// Empty marker extension so the user's `skip { }` block compiles. Mirrors
// the SkipBuildExtension type defined by the upstream plugin.
interface SkipBuildExtension
extensions.create("skip", SkipBuildExtension::class.java)

val skipEnv = Properties().apply {
    val skipEnvFile = rootDir.parentFile.resolve("Skip.env")
    require(skipEnvFile.isFile) {
        "Required Skip.env file is missing at ${skipEnvFile}"
    }
    skipEnvFile.reader(Charsets.UTF_8).use(::load)
    // Skip.env uses xcconfig `//` line comments; java.util.Properties
    // parses them as a single empty key, so drop it.
    remove("//")
}

fun lookupSkipEnv(key: String): String =
    skipEnv.getProperty(key)
        ?: System.getProperty("SKIP_${key}")
        ?: throw GradleException(
            "Required key '${key}' is not set in Skip.env or system property SKIP_${key}")

// `android { namespace = group as String }` in the user's build.gradle.kts
// requires `group` to be the Android package name.
project.group = lookupSkipEnv("ANDROID_PACKAGE_NAME")

// AGP's android {} extension is registered before this precompiled plugin
// is applied (the app build.gradle.kts lists com.android.application before
// `id("skip-build-plugin")` in its plugins block), so we can configure it
// immediately using the Groovy builder DSL to avoid a compile-time
// dependency on AGP types in buildSrc.
//
// Note: precompiled script plugins delegate properties through the
// script class, so `withGroovyBuilder` must be called on the project
// explicitly rather than through the implicit receiver.
project.withGroovyBuilder {
    getProperty("android").withGroovyBuilder {
        getProperty("defaultConfig").withGroovyBuilder {
            val applicationId = (skipEnv.getProperty("ANDROID_APPLICATION_ID")
                ?: lookupSkipEnv("PRODUCT_BUNDLE_IDENTIFIER")).replace("-", "_")
            setProperty("applicationId", applicationId)
            setProperty("versionCode", lookupSkipEnv("CURRENT_PROJECT_VERSION").toInt())
            setProperty("versionName", lookupSkipEnv("MARKETING_VERSION"))
            getProperty("manifestPlaceholders").withGroovyBuilder {
                for ((rawKey, rawValue) in skipEnv) {
                    val key = rawKey.toString()
                    if (key.isNotBlank()) {
                        setProperty(key, rawValue.toString())
                    }
                }
            }
        }
    }
}

dependencies {
    // The transpiled app module is included as a sibling project; see
    // `include(":<PRODUCT_NAME>")` in ../settings.gradle.kts.
    add("implementation", project(":${lookupSkipEnv("PRODUCT_NAME")}"))
}
"""

    /// Appended (via last-write-wins property semantics) to `Android/gradle.properties`
    /// so the Kotlin compile in `gradle assembleDebug` has enough heap for the
    /// transpiled SkipUI module on hosts where the upstream 4g default OOMs.
    static let standaloneGradlePropertiesAppendix: String = """

# Skip standalone export: bump JVM heap so the Kotlin compile of the
# transpiled SkipUI module fits. Java `Properties` parsing uses
# last-write-wins, so this overrides any lower `org.gradle.jvmargs` set
# earlier in the file.
org.gradle.jvmargs=-Xmx8g -XX:MaxMetaspaceSize=2g

"""

    /// Unpack the exported project zip into a private temp folder and run
    /// `gradle assembleDebug` there. If the build succeeds and produces an
    /// .apk, the temp folder is removed; on failure the path is reported so
    /// the user can investigate.
    func validateExportedProjectZip(zipFile: URL, appModuleName: String, env: [String: String], out: MessageQueue) async throws {
        let fm = FileManager.default
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("skip-validate-export-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpRoot, withIntermediateDirectories: true)

        await out.write(status: nil, "Validating export by unpacking and assembling at \(tmpRoot.path)")
        do {
            try await run(with: out, "Unzip exported project", ["unzip", "-q", zipFile.path, "-d", tmpRoot.path])
        } catch {
            await out.write(status: .fail, "Could not unzip \(zipFile.path) into \(tmpRoot.path): \(error)")
            throw error
        }

        // The exported zip is rooted at <appModuleName>/, so the standalone
        // Android project sits below it. The build is run with --no-daemon to
        // avoid leaving a stray daemon claiming the temp folder.
        let exportRoot = tmpRoot.appendingPathComponent(appModuleName, isDirectory: true)
        let androidRoot = exportRoot.appendingPathComponent("Android", isDirectory: true)
        guard fm.fileExists(atPath: androidRoot.path) else {
            throw error("Exported zip \(zipFile.lastPathComponent) does not contain the expected Android/ folder at \(androidRoot.path)")
        }

        let gradleArgs = ["gradle", "--project-dir", androidRoot.path, "--console=plain", "--no-daemon", "assembleDebug"]
        do {
            try await run(with: out, "Validate export with `gradle assembleDebug`", gradleArgs, environment: env)
        } catch {
            await out.write(status: .fail, "Standalone build of exported project failed at \(androidRoot.path). The unpacked tree was left in place for debugging.")
            throw error
        }

        // Confirm the apk landed where Android's `assembleDebug` puts it.
        let apkURL = androidRoot.appendingPathComponent("app/build/outputs/apk/debug/app-debug.apk")
        guard fm.fileExists(atPath: apkURL.path) else {
            throw error("Standalone build completed but the expected APK was not produced at \(apkURL.path)")
        }

        await out.write(status: .pass, "Export validated: \(apkURL.lastPathComponent) was produced from the exported zip at \(apkURL.path)")
        try? fm.removeItem(at: tmpRoot)
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
