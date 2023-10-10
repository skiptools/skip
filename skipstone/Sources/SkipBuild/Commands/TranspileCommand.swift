import Foundation
import ArgumentParser
import Universal
import SkipSyntax
import TSCBasic

protocol TranspilePhase: TranspilerInputOptionsCommand {
    var transpileOptions: TranspilePhaseOptions { get }
}

/// The file extension for the metadata about skipcode
let skipcodeExtension = ".skipcode.json"

/// The output folder in which to place Skippy files
let skipOutputFolder = ".skip"

/// The skip transpile marker that is always output regardless of whether the transpile was successful or not
/// `.docc` extension is needed to prevent file from being included in the build output folder
let skipbuildMarkerExtension = ".skipbuild.docc"

struct TranspileCommand: TranspilePhase, LicenseValidator, StreamingCommand {
    static var configuration = CommandConfiguration(commandName: "transpile", abstract: "Transpile Swift to Kotlin", shouldDisplay: false)

    @OptionGroup(title: "Check Options")
    var inputOptions: TranspilerInputOptions

    @OptionGroup(title: "Transpile Options")
    var transpileOptions: TranspilePhaseOptions

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "License Options")
    var licenseOptions: LicenseOptions

    @Option(help: ArgumentHelp("Only run if the given environment is unset", valueName: "envkey"))
    var envDisable: [String] = []

    @Option(help: ArgumentHelp("Run when the given environment is set", valueName: "envkey"))
    var envEnable: [String] = []

    struct Output : MessageEncodable {
        let transpilation: Transpilation

        func message(term: Term) -> String? {
            // successful transpile outputs no message so as to not clutter xcode logs
            return nil
        }
    }

    var moduleNamePaths: [(module: String, path: String)] {
        transpileOptions.moduleNames.map({
            let parts = $0.split(separator: ":")
            return (module: parts.first?.description ?? "", path: parts.last?.description ?? "")
        })
    }

    var linkNamePaths: [(module: String, link: String)] {
        transpileOptions.linkPaths.map({
            let parts = $0.split(separator: ":")
            return (module: parts.first?.description ?? "", link: parts.last?.description ?? "")
        })
    }

    func performCommand(with out: MessageQueue) async throws {
        #if DEBUG
        let v = skipVersion + "*" // * indicates debug version
        #else
        let v = skipVersion
        #endif

        if ProcessInfo.processInfo.environment["CONFIGURATION"] == "Skippy" {
            info("Skip \(v): transpile plugin not running for CONFIGURATION=Skippy")
            return
        }

        // show the local time in the transpile output; this helps identify from the Xcode Navigator when an old log file is being replayed for a plugin re-execution
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"

        guard let moduleRoot = transpileOptions.moduleRoot else {
            throw error("Must specify --module-root")
        }
        let moduleRootPath = try AbsolutePath(validating: moduleRoot)

        guard let skipFolder = transpileOptions.skipFolder else {
            throw error("Must specify --skip-folder")
        }

        let fs = localFileSystem
        let baseOutputPath = try fs.currentWorkingDirectory ?? fs.tempDirectory

        // the --skip-folder flag
        let skipFolderPath = try AbsolutePath(validating: skipFolder, relativeTo: baseOutputPath)

        // the --project flag
        let projectFolderPath = try AbsolutePath(validating: transpileOptions.projectFolder, relativeTo: baseOutputPath)

        guard let outputFolder = transpileOptions.outputFolder else {
            throw error("Must specify --output-folder")
        }
        let outputFolderPath = try AbsolutePath(validating: outputFolder, relativeTo: baseOutputPath)


        info("Skip \(v): transpile plugin to: \(transpileOptions.outputFolder ?? "nowhere") at \(dateFormatter.string(from: .now))")
        try await self.transpile(root: baseOutputPath, project: projectFolderPath, module: moduleRootPath, skip: skipFolderPath, output: outputFolderPath, fs: fs, with: out)
    }

    private func transpile(root rootPath: AbsolutePath, project projectFolderPath: AbsolutePath, module moduleRootPath: AbsolutePath, skip skipFolderPath: AbsolutePath, output outputFolderPath: AbsolutePath, fs: FileSystem, with out: MessageQueue) async throws {
        // the path that will contain the `skip.yml`

        if !fs.isDirectory(skipFolderPath) {
            throw error("In order to transpile the module, a Skip/ folder must exist and contain a skip.yml file at: \(skipFolderPath)")
        }

        // when renaming SomeClassA.swift to SomeClassB.swift, the stale SomeClassA.kt file from previous runs will be left behind, and will then cause a "Redeclaration:" error from the Kotlin compiler if they declare the same types
        // so keep a snapshot of the output folder files that existed at the start of the transpile operation, so we can then clean up any output files that are no longer being produced
        let outputFilesSnapshot: [URL] = try FileManager.default.enumeratedURLs(of: outputFolderPath.asURL)
        //msg(.warning, "transpiling to \(outputFolderPath.pathString) with existing files: \(outputFilesSnapshot.map(\.lastPathComponent).sorted().joined(separator: ", "))")

        var outputFiles: [AbsolutePath] = []

        func cleanupStaleOutputFiles() {
            let staleFiles = Set(outputFilesSnapshot.map(\.path))
                .subtracting(outputFiles.map(\.pathString))
            for staleFile in staleFiles.sorted() {
                let staleFileURL = URL(fileURLWithPath: staleFile, isDirectory: false)
                msg(.warning, "removing stale output files: \(staleFileURL.lastPathComponent)")

                do {
                    // don't actually trash it, since the output files often have read-only permissions set, and that prevents trash from working
                    try FileManager.default.trash(fileURL: staleFileURL, trash: false)
                } catch {
                    msg(.warning, "error removing stale output files: \(staleFileURL.lastPathComponent): \(error)")
                }
            }
        }

        /// track every output file written using `addOutputFile` to prevent the file from being cleaned up at the end
        func addOutputFile(_ path: AbsolutePath) -> AbsolutePath {
            outputFiles.append(path)
            return path
        }

        var inputFiles: [AbsolutePath] = []
        // add the given file to the list of input files for consideration of mod time
        func addInputFile(_ path: AbsolutePath) -> AbsolutePath {
            inputFiles.append(path)
            return path
        }

        /// Load the given source file, tracking its last modified date for the timestamp on the `.skipbuild` marker file
        func inputSource(_ path: AbsolutePath) throws -> ByteString {
            _ = addInputFile(path)
            return try fs.readFileContents(path)
        }


        if !fs.isDirectory(moduleRootPath) {
            try fs.createDirectory(moduleRootPath, recursive: true)
        }

        if !fs.isDirectory(moduleRootPath) {
            throw error("Module root path did not exist at: \(moduleRootPath.pathString)")
        }

        guard let (primaryModuleName, primaryModulePath) = moduleNamePaths.first else {
            throw error("Must specify at least one --module")
        }

        let _ = primaryModulePath

        func buildSourceList() throws -> (sources: [URL], resources: [URL]) {
            let allProjectFiles: [URL] = try FileManager.default.enumeratedURLs(of: projectFolderPath.asURL)

            let swiftPathExtensions: Set<String> = ["swift"]
            let resourcePathExclusions: Set<String> = swiftPathExtensions.union(["kt"]) // resource files are anything that isn't a swift file or a kotlin file

            let sourceURLs: [URL] = allProjectFiles.filter({ swiftPathExtensions.contains($0.pathExtension) })
            let resourceURLs: [URL] = allProjectFiles.filter({ !$0.lastPathComponent.hasPrefix(".") && !resourcePathExclusions.contains($0.pathExtension) })

            return (sources: sourceURLs, resources: resourceURLs)
        }

        let (sourceURLs, resourceURLs) = try buildSourceList()

        let moduleBasePath = moduleRootPath.parentDirectory

        // always touch the build completion marker with the most recent file mod time
        /// Create a link from the source to the destination; this is used for resources and custom Kotlin files in order to permit edits to target file and have them reflected in the original source
        func addLink(at linkSource: AbsolutePath, pointingAt destPath: AbsolutePath, relative: Bool) throws {
            let modTime = try? fs.getFileInfo(destPath).modTime
            try? fs.removeFileTree(linkSource) // remove any existing link in order to re-create it
            try fs.createSymbolicLink(addOutputFile(linkSource), pointingAt: destPath, relative: relative)
            // set the output link mod time to match the source link mod time
            if let modTime = modTime {
                // this will try to set the mod time of the *destination* file, which is incorrect (and also not allowed, since the dest is likely outside of our sandboxed write folder list)
                //try FileManager.default.setAttributes([.modificationDate: modTime], ofItemAtPath: linkSource.pathString)

                // using setResourceValue instead does apply it to the link
                // https://stackoverflow.com/questions/10608724/set-modification-date-on-symbolic-link-in-cocoa
                try (linkSource.asURL as NSURL).setResourceValue(modTime, forKey: .contentModificationDateKey)
            }
        }


        // the shared JSON encoder for serializing .skipcode.json codebase and .skipbuild marker contents
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, // needed for deterministic output
            .withoutEscapingSlashes,
            //.prettyPrinted, // compacting JSON significantly reduces the size of the codebase files
        ]

        let skipBuildOutputPath = moduleBasePath.appending(component: skipOutputFolder)
        try? fs.createDirectory(skipBuildOutputPath, recursive: true) // ensure the .skip output folder exists

        let buildCompletionMarkerPath = skipBuildOutputPath.appending(component: "." + primaryModuleName + skipbuildMarkerExtension)
        try? fs.removeFileTree(buildCompletionMarkerPath) // delete the build completion marker to force its re-creation

        // touch the build marker with the most recent file time from the complete build list
        // if we were to touch it afresh every time, the plugin would be re-executed every time
        defer {
            do {
                // get the modification times for all the files we have written and which were used as inputs
                let fileDates = try (outputFiles + inputFiles).map({ try fs.getFileInfo($0).modTime })
                // touch the build marker with the max file time of all the inputs and outputs
                try touchBuildCompletionMarker(at: fileDates.max() ?? Date.now)
            } catch {
                msg(.warning, "could not create build completion marker: \(error)")
            }
        }

        let env = ProcessInfo.processInfo.environment

        // at this point, check for the conditional environment and halt transpilation on unsupported (i.e., non-macOS) platforms; this will still output the .skipbuild file, because the plugin needs to have it created for evey plugin invocation (since we don't know in SkipPlugin.swift what the target platform is).
        let explicitlyEnabled = envEnable.contains(where: { env[$0] != nil })
        let explicitlyDisabled = envDisable.contains(where: { env[$0] != nil })

        if explicitlyEnabled == false && explicitlyDisabled == true {
            info("Skip transpiler explicitly disabled for environment key: \(envDisable)")
            return
        }

        // the standard base name for Gradle Kotlin source files
        let kotlinOutputFolder = try AbsolutePath(outputFolderPath, validating: "kotlin")

        // the standard base name for resources, which will be linked from a path like: src/main/resources/package/name/resname.ext
        let resourcesOutputFolder = try AbsolutePath(outputFolderPath, validating: "resources")

        if !fs.isDirectory(kotlinOutputFolder) {
            // e.g.: ~Library/Developer/Xcode/DerivedData/PACKAGE-ID/SourcePackages/plugins/skiphub.output/SkipFoundationKotlinTests/skipstone/SkipFoundation/src/test/kotlin
            //throw error("Folder specified by --output-folder did not exist: \(outputFolder)")
            try fs.createDirectory(kotlinOutputFolder, recursive: true)
        }

        let packageName = KotlinTranslator.packageName(forModule: primaryModuleName)

        // load and merge each of the skip.yml files for the dependent modules
        let (baseSkipConfig, mergedSkipConfig, configMap) = try loadSkipConfig(merge: true)
        let transformers: [KotlinTransformer] = try createTransformers(for: baseSkipConfig, with: configMap)

        var dependentCodebaseInfos: [CodebaseInfo] = []

        let codebaseInfo = try await loadCodebaseInfo() // initialize the codebaseinfo and load DependentModuleName.skipcode.json

        let overridden = try linkSkipFolder(skipFolderPath, to: kotlinOutputFolder, topLevel: true)
        let overriddenKotlinFiles = overridden.map({ $0.basename })

        // also add any Kotlin files in the skipFolderFile to the list of sources
        let skipFolderPathContents = try fs.getDirectoryContents(skipFolderPath)
            .map { try AbsolutePath(skipFolderPath, validating: $0) }

        // validate licenses in all the Skip source files, as well as any custom Kotlin files in the Skip folder
        try await validateLicense(sourceURLs: sourceURLs + skipFolderPathContents.map(\.asURL).filter({ $0.pathExtension == "kt" }))

        let transpiler = Transpiler(packageName: packageName, sourceFiles: sourceURLs.map(\.path).sorted().map(Source.FilePath.init(path:)), codebaseInfo: codebaseInfo, preprocessorSymbols: Set(inputOptions.symbols), transformers: transformers)

        try await transpiler.transpile(handler: handleTranspilation)
        try saveCodebaseInfo() // save out the ModuleName.skipcode.json

        let sourceModules = try linkDependentModuleSources()
        try linkResources()
        try generateGradle(for: sourceModules, with: mergedSkipConfig)

        // finally, remove any "stale" files from the output folder that probably indicate a deleted or renamed file once all the known outputs have been written
        cleanupStaleOutputFiles()
        return // done

        // MARK: Transpilation helper functions

        /// The relative path for cached codebase info JSON
        func codebaseInfoPath(forModule moduleName: String) throws -> RelativePath {
            try RelativePath(validating: moduleName + skipcodeExtension)
        }

        func loadCodebaseInfo() async throws -> CodebaseInfo {
            let decoder = JSONDecoder()

            // go through the '--link modulename:../../some/path' arguments and try to load the modulename.skipcode.json symbols from the previous module's transpilation output
            for (linkModuleName, relativeLinkPath) in linkNamePaths {
                let linkModuleRoot = moduleRootPath
                    .parentDirectory
                    .appending(try RelativePath(validating: relativeLinkPath))


                let dependencyCodebaseInfo = linkModuleRoot
                    .parentDirectory
                    .appending(try codebaseInfoPath(forModule: linkModuleName))

                do {
                    let codebaseLoadStart = Date().timeIntervalSinceReferenceDate
                    trace("dependencyCodebaseInfo \(dependencyCodebaseInfo): exists \(fs.exists(dependencyCodebaseInfo))")
                    let cbdata = try inputSource(dependencyCodebaseInfo).withData { Data($0) }
                    let cbinfo = try decoder.decode(CodebaseInfo.self, from: cbdata)
                    dependentCodebaseInfos.append(cbinfo)
                    let codebaseLoadEnd = Date().timeIntervalSinceReferenceDate
                    info("\(dependencyCodebaseInfo.basename) codebase (\(cbdata.count.byteCount)) loaded (\(Int64((codebaseLoadEnd - codebaseLoadStart) * 1000)) ms) for \(linkModuleName)", sourceFile: dependencyCodebaseInfo.sourceFile)
                } catch let e {
                    throw error("Skip: error loading codebase for \(linkModuleName): \(e.localizedDescription)", sourceFile: dependencyCodebaseInfo.sourceFile)
                }
            }

            let codebaseInfo = CodebaseInfo(moduleName: primaryModuleName)
            codebaseInfo.dependentModules = dependentCodebaseInfos
            return codebaseInfo
        }

        func writeChanges(tag: String, to outputFilePath: AbsolutePath, contents: any DataProtocol, readOnly: Bool) throws {
            let changed = try fs.writeChanges(path: addOutputFile(outputFilePath), makeReadOnly: readOnly, bytes: ByteString(contents))
            info("\(outputFilePath.relative(to: moduleBasePath).pathString) (\(contents.count.byteCount)) \(tag) \(!changed ? "unchanged" : "written")", sourceFile: outputFilePath.sourceFile)
        }

        func touchBuildCompletionMarker(at dateOfLastFileChange: Date) throws {
            if !fs.isDirectory(buildCompletionMarkerPath.parentDirectory) {
                try fs.createDirectory(buildCompletionMarkerPath.parentDirectory, recursive: true)
            }

            struct SkipMarkerContents : Encodable {
                /// The version of Skip that generates this marker file
                let skipstone: String = skipVersion

                /// The ordered input paths for source files, in order to identify when input file lists have changed even if none of the contents have
                let sourceFiles: [String]?
            }

            let marker = SkipMarkerContents(sourceFiles: sourceURLs.map(\.path))
            try writeChanges(tag: "marker", to: buildCompletionMarkerPath, contents: try encoder.encode(marker), readOnly: false)
        }

        func saveCodebaseInfo() throws {
            let outputFilePath = try moduleBasePath.appending(codebaseInfoPath(forModule: primaryModuleName))
            try writeChanges(tag: "codebase", to: outputFilePath, contents: encoder.encode(codebaseInfo), readOnly: true)
        }

        func generateGradle(for sourceModules: [String], with skipConfig: SkipConfig) throws {
            if let gradleVersion = transpileOptions.gradleVersion as String? {
                try generateGradleWrapperProperties(version: gradleVersion)
            }
            try generateProguardFile()
            try generatePerModuleGradle()
            try generateGradleProperties()
            try generateSettingsGradle()

            func generatePerModuleGradle() throws {
                let buildContents = (skipConfig.build ?? .init()).generate(context: .init(dsl: .kotlin))
                // we output as a joined string because there is a weird stdout bug with the tool or plugin executor somewhere that causes multi-line strings to be output in the wrong order
                trace("created gradle: \(buildContents.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }).joined(separator: "; "))")

                let buildGradle = moduleRootPath.appending(components: ["build.gradle.kts"])
                let contents = """
                // build.gradle.kts generated by Skip for \(primaryModuleName)

                """ + buildContents

                try writeChanges(tag: "gradle project", to: buildGradle, contents: contents.utf8Data, readOnly: true)
            }

            func generateSettingsGradle() throws {
                let settingsPath = moduleRootPath.parentDirectory.appending(component: "settings.gradle.kts")
                var settingsContents = (skipConfig.settings ?? .init()).generate(context: .init(dsl: .kotlin))

                settingsContents += """

                rootProject.name = "\(packageName)"

                """

                // always add the primary module include
                if !sourceModules.contains(primaryModuleName) && !primaryModuleName.hasSuffix("Tests") {
                    settingsContents += """
                    include(":\(primaryModuleName)")

                    """
                }

                for sourceModule in sourceModules {
                    settingsContents += """
                    include(":\(sourceModule)")

                    """
                }

                try writeChanges(tag: "gradle settings", to: settingsPath, contents: settingsContents.utf8Data, readOnly: true)
            }

            /// Create the proguard-rules.pro file, which configures the optimization settings for release buils
            func generateProguardFile() throws {
                try writeChanges(tag: "proguard", to: moduleRootPath.appending(component: "proguard-rules.pro"), contents: """
                    -keep class skip.** { *; }
                    """.utf8Data, readOnly: true)
            }


            /// Create the gradle-wrapper.properties file, which will dictate which version of Gradle that Android Studio should use to build the project.
            func generateGradleWrapperProperties(version: String) throws {
                let gradleWrapperFolder = moduleRootPath.parentDirectory.appending(components: "gradle", "wrapper")
                try fs.createDirectory(gradleWrapperFolder, recursive: true)
                let gradleWrapperPath = gradleWrapperFolder.appending(component: "gradle-wrapper.properties")
                let gradeWrapperContents = """
                distributionUrl=https\\://services.gradle.org/distributions/gradle-\(version)-all.zip
                """

                try writeChanges(tag: "gradle wrapper", to: gradleWrapperPath, contents: gradeWrapperContents.utf8Data, readOnly: true)
            }

            func generateGradleProperties() throws {
                // TODO: assemble these from skip.yml settings
                let gradlePropertiesPath = moduleRootPath.parentDirectory.appending(component: "gradle.properties")
                let gradePropertiesContents = """
                org.gradle.jvmargs=-Xmx2048m
                android.useAndroidX=true
                kotlin.code.style=official
                android.suppressUnsupportedCompileSdk=34
                """

                try writeChanges(tag: "gradle config", to: gradlePropertiesPath, contents: gradePropertiesContents.utf8Data, readOnly: true)
            }
        }

        func loadSkipYAML(path: AbsolutePath, forExport: Bool) throws -> SkipConfig {
            do {
                var yaml = try inputSource(path).withData(YAML.parse(_:))
                if yaml.object == nil { // an empty file will appear as nil, so just convert to an empty dictionary
                    yaml = .object([:])
                }

                // go through all the top-level "export: false" blocks and remove them when the config is being imported elsewhere
                if forExport {
                    func filterExport(from yaml: YAML) -> YAML? {
                        guard var obj = yaml.object else {
                            if let array = yaml.array {
                                return .array(array.compactMap(filterExport(from:)))
                            } else {
                                return yaml
                            }
                        }
                        for (key, value) in obj {
                            if key == "export" {
                                if value.boolean == false {
                                    // skip over the whole dict
                                    return nil
                                }
                            } else {
                                obj[key] = filterExport(from: value)
                            }
                        }
                        return .object(obj)
                    }

                    yaml = filterExport(from: yaml) ?? yaml
                }
                return try yaml.json().decode()
            } catch let e {
                throw error("The skip.yml file at \(path) could not be loaded: \(e)", sourceFile: path.sourceFile)
            }
        }

        /// Loads the `skip.yml` config, optionally merged with the `skip.yml` of all the module dependencies
        func loadSkipConfig(merge: Bool = true, configFileName: String = "skip.yml") throws -> (base: SkipConfig, merged: SkipConfig, configMap: [String: SkipConfig]) {
            let configStart = Date().timeIntervalSinceReferenceDate
            let skipConfigPath = skipFolderPath.appending(component: configFileName)
            let currentModuleConfig = try loadSkipYAML(path: skipConfigPath, forExport: false)

            var configMap: [String: SkipConfig] = [:]
            configMap[primaryModuleName] = currentModuleConfig

            let currentModuleJSON = try currentModuleConfig.json()
            info("loading skip.yml from \(skipConfigPath)", sourceFile: skipConfigPath.sourceFile)

            if !merge {
                return (currentModuleConfig, currentModuleConfig, configMap) // just the unmerged base YAML
            }

            // build up a merged YAML from the base dependenices to the current module
            var aggregateJSON: Universal.JSON = [:]

            func isTestModule(_ moduleName: String) -> Bool {
                primaryModuleName != moduleName && primaryModuleName != moduleName + "Tests"
            }

            for (moduleName, modulePath) in moduleNamePaths {
                trace("moduleName: \(moduleName) modulePath: \(modulePath) primaryModuleName: \(primaryModuleName)")
                if moduleName == primaryModuleName {
                    // don't merge the primary module name with itself
                    continue
                }

                let moduleSkipBasePath = try AbsolutePath(validating: modulePath, relativeTo: moduleRootPath.parentDirectory)
                    .appending(components: ["Skip"])

                let moduleSkipConfigPath = moduleSkipBasePath.appending(component: configFileName)

                if fs.isFile(moduleSkipConfigPath) {
                    let skipConfigLoadStart = Date().timeIntervalSinceReferenceDate
                    let isTestPeer = primaryModuleName == moduleName + "Tests" // test peers have the same module name
                    trace("primaryModuleName: \(primaryModuleName) moduleName: \(moduleName) isTestPeer=\(isTestPeer)") // SkipLibTests moduleName: SkipLib
                    let isForExport = !isTestPeer
                    let moduleConfig = try loadSkipYAML(path: moduleSkipConfigPath, forExport: isForExport)
                    configMap[moduleName] = moduleConfig // remember the raw config for use in configuring transpiler plug-ins
                    let skipConfigLoadEnd = Date().timeIntervalSinceReferenceDate
                    info("\(moduleName) skip.yml config loaded (\(Int64((skipConfigLoadEnd - skipConfigLoadStart) * 1000)) ms)", sourceFile: moduleSkipConfigPath.sourceFile)
                    aggregateJSON = try aggregateJSON.merged(with: moduleConfig.json())
                }
            }

            aggregateJSON = try aggregateJSON.merged(with: currentModuleJSON)

            // finally, merge with a manually constructed SkipConfig that contains references to the modules this module depends on
            do {
                var moduleDependencyBlocks: [GradleBlock.BlockOrCommand] = []

                for (moduleName, _) in moduleNamePaths {
                    // manually exclude our own module and tests names
                    if isTestModule(moduleName) {
                        if moduleName == "SkipUnit" {
                            moduleDependencyBlocks += [
                                .init("testImplementation(project(\":\(moduleName)\"))"),
                                .init("androidTestImplementation(project(\":\(moduleName)\"))")
                            ]
                        } else {
                            moduleDependencyBlocks += [
                                .init("api(project(\":\(moduleName)\"))"),
                            ]
                        }
                    }
                }

                var localConfig = GradleBlock(contents: [.init(GradleBlock(block: "dependencies", contents: moduleDependencyBlocks))])

                // finally check for the existance of PrimaryModuleName.xcconfig, and if it exists, imports its settings into the manifestPlaceholders dictionary in the `android { defaultConfig { } }` block
                let configModuleName = primaryModuleName.hasSuffix("Tests") ? String(primaryModuleName.dropLast("Tests".count)) : primaryModuleName
                let moduleXCConfig = rootPath.appending(component: configModuleName + ".xcconfig")
                if fs.isFile(moduleXCConfig) {
                    var manifestConfigLines: [String] = []

                    let moduleXCConfigContents = try String(contentsOf: moduleXCConfig.asURL, encoding: .utf8)
                    for (key, value) in parseXCConfig(contents: moduleXCConfigContents) {
                        manifestConfigLines += ["""
                        manifestPlaceholders["\(key)"] = System.getenv("\(key)") ?: "\(value)"
                        """]
                    }


                    // now do some manual configuration of the android properties
                    manifestConfigLines += ["""
                    applicationId = manifestPlaceholders["PRODUCT_BUNDLE_IDENTIFIER"] as String
                    """]

                    manifestConfigLines += ["""
                    versionCode = (manifestPlaceholders["CURRENT_PROJECT_VERSION"] as String).toInt()
                    """]

                    manifestConfigLines += ["""
                    versionName = manifestPlaceholders["MARKETING_VERSION"] as String
                    """]

                    localConfig.contents?.append(.init(GradleBlock(block: "android", contents: [
                        .init(GradleBlock(block: "defaultConfig", contents: manifestConfigLines.map({ .a($0) })))
                    ])))
                }

                aggregateJSON = try aggregateJSON.merged(with: JSON.object(["build": localConfig.json()]))
            }

            var aggregateSkipConfig: SkipConfig = try aggregateJSON.decode()
            // clear exports and perform final item removal
            aggregateSkipConfig.build?.removeContent(withExports: true)
            aggregateSkipConfig.settings?.removeContent(withExports: true)

            let configEnd = Date().timeIntervalSinceReferenceDate
            info("skip.yml aggregate created (\(Int64((configEnd - configStart) * 1000)) ms) for modules: \(moduleNamePaths.map(\.module))")
            return (currentModuleConfig, aggregateSkipConfig, configMap)
        }

        func kotlinOutputPath(for baseSourceFileName: String, in basePath: AbsolutePath? = nil) throws -> AbsolutePath? {
            if baseSourceFileName == "skip.yml" {
                // skip metadata files are excluded from copy
                return nil
            }

            // the "AndroidManifest.xml" file is special: it needs to go in the root src/main/ folder
            let isManifest = baseSourceFileName == "AndroidManifest.xml"
            // if an empty basePath, treat as a source file and place in package-derived folders
            return try (basePath ?? kotlinOutputFolder
                .appending(components: isManifest ? [".."] : packageName.split(separator: ".").map(\.description)))
                .appending(RelativePath(validating: baseSourceFileName))
        }

        /// Copies over the overridden .kt files from `ModuleNameKotlin/Skip/*.kt` into the destination folder,
        /// and makes links to any subdirectories, which enables the handling of `src/main/AndroidManifest.xml`
        /// and other custom resources.
        ///
        /// Any Kotlin files that are overridden will not be transpiled.
        func linkSkipFolder(_ path: AbsolutePath, to outputFilePath: AbsolutePath, topLevel: Bool) throws -> Set<AbsolutePath> {
            var copiedFiles: Set<AbsolutePath> = []
            for fileName in try fs.getDirectoryContents(path) {
                if fileName.hasPrefix(".") {
                    continue // skip hidden files
                }
                let sourcePath = try AbsolutePath(path, validating: fileName)
                let outputPath = try AbsolutePath(outputFilePath, validating: fileName)

                if fs.isDirectory(sourcePath) {
                    // make recursive folders for sub-linked resources
                    let subPaths = try linkSkipFolder(sourcePath, to: outputPath, topLevel: false)
                    copiedFiles.formUnion(subPaths)
                } else {
                    if let outputFilePath = try kotlinOutputPath(for: sourcePath.basename, in: topLevel ? nil : outputFilePath) {
                        copiedFiles.insert(outputFilePath)
                        try fs.createDirectory(outputFilePath.parentDirectory, recursive: true) // ensure parent exists
                        // we make links instead of copying so the file can be edited from the gradle project structure without needing to be manually synchronized
                        try addLink(at: outputFilePath, pointingAt: sourcePath, relative: false)
                        info("\(outputFilePath.relative(to: moduleBasePath).pathString) override linked from project source \(sourcePath.pathString)", sourceFile: sourcePath.sourceFile)
                    }
                }
            }
            return copiedFiles
        }

        func handleTranspilation(transpilation: Transpilation) async throws {
            for message in transpilation.messages {
                await out.yield(message)
            }

            trace(transpilation.output.content)

            let sourcePath = try AbsolutePath(validating: transpilation.sourceFile.path)
            let sourceSize = transpilation.isSourceFileSynthetic ? 0 : try fs.getFileInfo(sourcePath).size

            let (outputFile, changed, overridden) = try saveTranspilation()

            // 2 separate log messages, one linking to the source swift and the second linking to the kotlin
            // this makes the log rather noisy, and isn't very useful
            //if !transpilation.isSourceFileSynthetic {
            //    info("\(sourcePath.basename) (\(byteCount(for: .init(sourceSize)))) transpiling to \(outputFile.basename)", sourceFile: transpilation.sourceFile)
            //}

            info("\(outputFile.relative(to: moduleBasePath).pathString) (\(transpilation.output.content.lengthOfBytes(using: .utf8).byteCount)) transpilation \(overridden ? "overridden" : !changed ? "unchanged" : "saved") from \(sourcePath.basename) (\(sourceSize.byteCount)) in \(Int64(transpilation.duration * 1000)) ms", sourceFile: overridden ? transpilation.sourceFile : outputFile.sourceFile)

            for message in transpilation.messages {
                //writeMessage(message)
                if message.kind == .error {
                    // throw the first error we see
                    await out.finish(throwing: message)
                    return
                }
            }

            let output = Output(transpilation: transpilation)
            await out.yield(output)

            func saveTranspilation() throws -> (output: AbsolutePath, changed: Bool, overridden: Bool) {
                // the build plug-in's output folder base will be something like ~/Library/Developer/Xcode/DerivedData/Mod-ID/SourcePackages/plugins/module-name.output/ModuleNameKotlin/skipstone/ModuleName/src/test/kotlin
                trace("path: \(kotlinOutputFolder)")

                let kotlinName = transpilation.kotlinFileName
                guard let outputFilePath = try kotlinOutputPath(for: kotlinName) else {
                    throw error("No output path for \(kotlinName)")
                }

                if overriddenKotlinFiles.contains(kotlinName) {
                    return (output: outputFilePath, changed: false, overridden: true)
                }

                let kotlinBytes = ByteString(encodingAsUTF8: transpilation.output.content)
                let fileWritten = try fs.writeChanges(path: addOutputFile(outputFilePath), checkSize: true, makeReadOnly: true, bytes: kotlinBytes)

                trace("wrote to: \(outputFilePath)\(!fileWritten ? " (unchanged)" : "")", sourceFile: outputFilePath.sourceFile)

                // also save the output line mapping file: SomeFile.kt -> .SomeFile.sourcemap
                let sourceMappingPath = outputFilePath.parentDirectory.appending(component: "." + outputFilePath.basenameWithoutExt + ".sourcemap")
                let encoder = JSONEncoder()
                encoder.outputFormatting = [
                    .sortedKeys, // needed for deterministic output
                    .withoutEscapingSlashes,
                    //.prettyPrinted,
                ]
                let sourceMapData = try encoder.encode(transpilation.outputMap)
                try fs.writeChanges(path: addOutputFile(sourceMappingPath), makeReadOnly: true, bytes: ByteString(sourceMapData))

                return (output: outputFilePath, changed: fileWritten, overridden: false)
            }
        }

        /// Links each of the resource files passed to the transpiler to the underlying source files.
        /// - Returns: the list of root resource folder(s) that contain the link(s) for the resources
        func linkResources() throws {
            let destinationBasePath = resourcesOutputFolder
                .appending(components: packageName.split(separator: ".").map(\.description))
                .appending(component: "Resources")

            var resourcesIndex: [String] = []

            for resourceFile in resourceURLs.map(\.path).sorted() {
                guard let resourceSourceURL = moduleNamePaths.compactMap({ (_, folder) in
                    resourceFile.hasPrefix(folder) ? URL(fileURLWithPath: resourceFile.dropFirst(folder.count).trimmingCharacters(in: CharacterSet(charactersIn: "/")).description, relativeTo: URL(fileURLWithPath: folder, isDirectory: true)) : nil }).first else {
                    msg(.warning, "no module root parent for \(resourceFile)")
                    continue
                }

                let sourcePath = try AbsolutePath(validating: resourceSourceURL.path)

                // all resources get put into a single "Resources/" folder in the jar, so drop the first item and replace it with "Resources/"
                let components = try RelativePath(validating: resourceSourceURL.relativePath).components.dropFirst(1)
                let resPath = components.joined(separator: "/")
                let resourceSourcePath = try RelativePath(validating: resPath)
                resourcesIndex.append(resPath)

                let destinationPath = destinationBasePath.appending(resourceSourcePath)

                // only create links for files that exist
                if fs.isFile(sourcePath) {
                    info("\(destinationPath.relative(to: moduleBasePath).pathString) linking to \(sourcePath.pathString)", sourceFile: sourcePath.sourceFile)
                    try fs.createDirectory(destinationPath.parentDirectory, recursive: true)
                    if fs.isSymlink(destinationPath) {
                        try fs.removeFileTree(destinationPath) // clear any pre-existing symlink
                    }
                    try addLink(at: destinationPath, pointingAt: sourcePath, relative: false)
                }
            }

            let indexPath = destinationBasePath.appending(component: "resources.lst")

            if !resourcesIndex.isEmpty {
                // write out the resources index file that acts as the directory for Java/Android resources
                try fs.writeChanges(path: addOutputFile(indexPath), bytes: ByteString(encodingAsUTF8: resourcesIndex.sorted().joined(separator: "\n")))
                info("indexed \(resourcesIndex.count) resources at \(indexPath.pathString)", sourceFile: indexPath.sourceFile)
            } else {
                // remove the resources file if it should be empty
                try? fs.removeFileTree(indexPath)
            }
        }

        // NOTE: when linking between modules, SPM and Xcode will use different output paths:
        // Xcode: ~/Library/Developer/Xcode/DerivedData/PROJECT-ID/SourcePackages/plugins/skiphub.output/SkipFoundationKotlinTests/skipstone/SkipFoundation
        // SPM: .build/plugins/outputs/skiphub/
        func linkDependentModuleSources() throws -> [String] {
            var dependentModules: [String] = []
            // transpilation was successful; now set up links to the other output packages (located in different plug-in folders)
            let moduleBasePath = moduleRootPath.parentDirectory

            /// Attempts to make a link from the `fromPath` to the given relative path.
            /// If `fromPath` already exists and is a directory, attempt to create links for each of the contents of the directory to the updated relative folder
            func createMergedLinkTree(from fromPath: AbsolutePath, to relative: String) throws {
                let destPath = try AbsolutePath(validating: relative, relativeTo: fromPath.parentDirectory)
                if !fs.isDirectory(destPath) {
                    // skip over anything that is not a destination folder
                    // if it doesn't exist at all, then it is an error
                    if !fs.exists(destPath) {
                        warn("Expected destination path did not exist: \(destPath)")
                    }
                    return
                }
                trace("creating merged link tree from: \(fromPath) to: \(relative)")
                if fs.isSymlink(fromPath) {
                    try fs.removeFileTree(fromPath) // clear any pre-existing symlink
                }

                // the folder is a directory; recurse into the destination paths in order to link to the local paths
                if fs.isDirectory(fromPath) {
                    for fsEntry in try fs.getDirectoryContents(destPath) {
                        let fromSubPath = fromPath.appending(try RelativePath(validating: fsEntry))
                        // bump up all the relative links to account for the folder we just recursed into.
                        // e.g.: ../SomeSharedRoot/OtherModule/
                        // becomes: ../../SomeSharedRoot/OtherModule/someFolder/
                        try createMergedLinkTree(from: fromSubPath, to: "../" + relative + "/" + fsEntry)
                    }
                } else {
                    try addLink(at: fromPath, pointingAt: destPath, relative: true)
                }
            }

            // for each of the specified link/path pairs, create symbol links, either to the base folders, or the the sub-folders that share a common root
            // this is the logic that allows us to merge two modules (like MyMod and MyModTests) into a single Kotlin module with the idiomatic src/main/kotlin/ and src/test/kotlin/ pair of folders
            for (linkModuleName, relativeLinkPath) in linkNamePaths {
                let linkModulePath = try moduleBasePath.appending(RelativePath(validating: linkModuleName))
                trace("relativeLinkPath: \(relativeLinkPath) moduleBasePath: \(moduleBasePath) linkModuleName: \(linkModuleName) -> linkModulePath: \(linkModulePath)")
                try createMergedLinkTree(from: linkModulePath, to: relativeLinkPath)
                dependentModules.append(linkModuleName)
            }

            return dependentModules
        }
    }

    /// Generate transpiler transformers from the given skip config
    func createTransformers(for config: SkipConfig, with moduleMap: [String: SkipConfig]) throws -> [KotlinTransformer] {
        let transformers: [KotlinTransformer] = builtinKotlinTransformers()

        //if let packageName = config.skip?.package {
            // TODO: throw error("implement package/module map plugin")
        //}

        return transformers
    }

}

struct TranspilePhaseOptions: ParsableArguments {
    @Option(name: [.customLong("project"), .long], help: ArgumentHelp("The project folder to transpile", valueName: "folder"))
    var projectFolder: String // --project

    @Option(help: ArgumentHelp("Condition for transpile phase", valueName: "force/no"))
    var transpile: PhaseGuard = .onDemand // --transpile

    @Option(name: [.customLong("module")], help: ArgumentHelp("ModuleName:SourcePath", valueName: "module"))
    var moduleNames: [String] = [] // --module name:path

    @Option(name: [.customLong("link")], help: ArgumentHelp("ModuleName:LinkPath", valueName: "module"))
    var linkPaths: [String] = [] // --link name:path

    @Option(help: ArgumentHelp("Path to the folder that contains skip.yml and overrides", valueName: "path"))
    var skipFolder: String? = nil // --skip-folder

    @Option(help: ArgumentHelp("Path to the output module root folder", valueName: "path"))
    var moduleRoot: String? = nil // --module-root

    @Option(name: [.customShort("D", allowingJoined: true)], help: ArgumentHelp("Set preprocessor variable for transpilation", valueName: "value"))
    var preprocessorVariables: [String] = []

    @Option(name: [.long], help: ArgumentHelp("Output directory", valueName: "dir"))
    var outputFolder: String? = nil

    @Option(name: [.long], help: ArgumentHelp("The Gradle wrapper version to generate", valueName: "version"))
    var gradleVersion: String = "8.3" // note: this should not be higher than the pre-installed version on the active CI runner image: https://github.com/actions/runner-images/tree/main/images/macos
}

struct TranspileResult {

}

extension TranspilePhase {
    func performTranspileActions() async throws -> (check: CheckResult, transpile: TranspileResult) {
        let checkResult = try await performSkippyCommands()
        let transpileResult = TranspileResult()
        return (checkResult, transpileResult)
    }
}

extension URL {
    /// The path from this URL, validatating that it is an absolute path
    var absolutePath: AbsolutePath {
        get throws {
            try AbsolutePath(validating: path)
        }
    }
}

extension FileManager {
    /// Remove the given file URL, attempting to trash it when on macOS, otherwise just deleting it
    public func trash(fileURL: URL, trash: Bool) throws {
        if trash {
            #if os(macOS)
            do {
                // make sure it is writeable, since trashItem will fail if it is not
                try localFileSystem.chmod(.userWritable, path: fileURL.absolutePath)

                // trash it on macOS so the user can recover it from the trash
                try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
            } catch {
                // tolerate failures and fall back to removing the item
            }
            #endif
        }

        // trash not supported or requested
        try FileManager.default.removeItem(at: fileURL)
    }

    /// Returns the deep contents of a given directory URL.
    public func enumeratedURLs(of folderURL: URL) throws -> [URL] {
        var childFileURLs: [URL] = []

        if let fileURLs = self.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let fileURL as URL in fileURLs {
                if try fileURL.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile == true {
                    childFileURLs.append(fileURL)
                }
            }
        }

        return childFileURLs
    }
}

/// Parse the simple .xcconfig file format
func parseXCConfig(contents: String) -> [(key: String, value: String)] {
    var keyValues: [(key: String, value: String)] = []
    let lines = contents.components(separatedBy: .newlines)
    for line in lines {
        if line.hasPrefix("#") || line.hasPrefix("//") || line.isEmpty {
            continue
        }

        let components = line.components(separatedBy: "=")
        // note that we do not currently handle conditional lines like "PRODUCT_BUNDLE_IDENTIFIER[config=Debug][sdk=iphoneos*] = myorg.app.App-Name"
        if components.count == 2 {
            let key = components[0].trimmingCharacters(in: .whitespaces)
            let value = components[1].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty && !value.isEmpty {
                keyValues.append((key, value))
            }
        }
    }
    return keyValues
}
