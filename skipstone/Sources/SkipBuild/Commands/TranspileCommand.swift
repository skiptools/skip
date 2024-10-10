import Foundation
import ArgumentParser
import Universal
import SkipSyntax
import TSCBasic

protocol TranspilePhase: TranspilerInputOptionsCommand {
    var transpileOptions: TranspileCommandOptions { get }
}

/// The file extension for the metadata about skipcode
let skipcodeExtension = ".skipcode.json"

struct TranspileCommand: TranspilePhase, StreamingCommand {
    static var configuration = CommandConfiguration(commandName: "transpile", abstract: "Transpile Swift to Kotlin", shouldDisplay: false)

    /// The `ENABLE_PREVIEW` parameter specifies whether we are building for previews
    static let enablePreviews = ProcessInfo.processInfo.environment["ENABLE_PREVIEWS"] == "YES"

    @OptionGroup(title: "Check Options")
    var inputOptions: TranspilerInputOptions

    @OptionGroup(title: "Transpile Options")
    var transpileOptions: TranspileCommandOptions

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

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

    var dependencyIdPaths: [(id: String, path: String)] {
        transpileOptions.dependencies.map({
            let parts = $0.split(separator: ":")
            return (id: parts.first?.description ?? "", path: parts.last?.description ?? "")
        })
    }

    func performCommand(with out: MessageQueue) async throws {
        #if DEBUG
        let v = skipVersion + "*" // * indicates debug version
        #else
        let v = skipVersion
        #endif

        if Self.enablePreviews == true {
            info("Skip \(v): transpile plugin not running for ENABLE_PREVIEWS=YES")
            return
        }

        if SkippyCommand.skippyOnly == true {
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
        do {
            try await transpileThrows(root: rootPath, project: projectFolderPath, module: moduleRootPath, skip: skipFolderPath, output: outputFolderPath, fs: fs, with: out)
        } catch {
            // ensure that the error is logged in some way before failing
            self.error("An error occurred while performing transpilation: \(error.localizedDescription)")
            throw error
        }
    }

    private func transpileThrows(root rootPath: AbsolutePath, project projectFolderPath: AbsolutePath, module moduleRootPath: AbsolutePath, skip skipFolderPath: AbsolutePath, output outputFolderPath: AbsolutePath, fs: FileSystem, with out: MessageQueue) async throws {
        // the path that will contain the `skip.yml`

        // the module will be treated differently if it is an app versus a library (it will use the "com.android.application" plugin instead of "com.android.library")
        let AndroidManifestName = "AndroidManifest.xml"

        // folders that can contain gradle plugins and scripts
        let buildSrcFolderName = "buildSrc"

        let cmakeLists = projectFolderPath.appending(component: "CMakeLists.txt")
        let isCMakeProject = fs.exists(cmakeLists)
        if !isCMakeProject && !fs.isDirectory(skipFolderPath) {
            throw error("In order to transpile the module, a Skip/ folder must exist and contain a skip.yml file at: \(skipFolderPath)")
        }

        // when renaming SomeClassA.swift to SomeClassB.swift, the stale SomeClassA.kt file from previous runs will be left behind, and will then cause a "Redeclaration:" error from the Kotlin compiler if they declare the same types
        // so keep a snapshot of the output folder files that existed at the start of the transpile operation, so we can then clean up any output files that are no longer being produced
        let outputFilesSnapshot: [URL] = try FileManager.default.enumeratedURLs(of: outputFolderPath.asURL)
        //msg(.warning, "transpiling to \(outputFolderPath.pathString) with existing files: \(outputFilesSnapshot.map(\.lastPathComponent).sorted().joined(separator: ", "))")

        var outputFiles: [AbsolutePath] = []

        var skipBridgeTranspilations: [Transpilation] = []

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

        /// Load the given source file, tracking its last modified date for the timestamp on the `.sourcehash` marker file
        func inputSource(_ path: AbsolutePath) throws -> ByteString {
            try fs.readFileContents(addInputFile(path))
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

        func isTestModule(_ moduleName: String) -> Bool {
            primaryModuleName != moduleName && primaryModuleName != moduleName + "Tests"
        }

        // check for the existence of PrimaryModuleName.xcconfig, and if it exists, this is an app module
        let configModuleName = primaryModuleName.hasSuffix("Tests") ? String(primaryModuleName.dropLast("Tests".count)) : primaryModuleName
        let moduleXCConfig = rootPath.appending(component: configModuleName + ".xcconfig")
        let isAppModule = fs.isFile(moduleXCConfig)

        let _ = primaryModulePath

        func buildSourceList() throws -> (sources: [URL], resources: [URL]) {
            let allProjectFiles: [URL] = try FileManager.default.enumeratedURLs(of: projectFolderPath.asURL)

            let swiftPathExtensions: Set<String> = ["swift"]
            let resourcePathExclusions: Set<String> = swiftPathExtensions.union(["kt", "java"]) // resource files are anything that isn't a swift file or a kotlin file

            let sourceURLs: [URL] = allProjectFiles.filter({ swiftPathExtensions.contains($0.pathExtension) })
            // also exclude files starting with dot and `skip.yml`
            let resourceURLs: [URL] = allProjectFiles.filter({ !$0.lastPathComponent.hasPrefix(".") && !resourcePathExclusions.contains($0.pathExtension) && $0.lastPathComponent != "skip.yml" })

            return (sources: sourceURLs, resources: resourceURLs)
        }

        let (sourceURLs, resourceURLs) = try buildSourceList()

        let moduleBasePath = moduleRootPath.parentDirectory

        // always touch the sourcehash file with the most recent source hashes in order to update the output file time
        /// Create a link from the source to the destination; this is used for resources and custom Kotlin files in order to permit edits to target file and have them reflected in the original source
        func addLink(_ linkSource: AbsolutePath, pointingAt destPath: AbsolutePath, relative: Bool, replace: Bool = true) throws {
            msg(.trace, "linking: \(linkSource) to: \(destPath)")

            if replace && fs.isSymlink(destPath) {
                try fs.removeFileTree(destPath) // clear any pre-existing symlink
            }

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


        // the shared JSON encoder for serializing .skipcode.json codebase and .sourcehash marker contents
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, // needed for deterministic output
            .withoutEscapingSlashes,
            //.prettyPrinted, // compacting JSON significantly reduces the size of the codebase files
        ]

        let sourcehashOutputPath = try AbsolutePath(validating: transpileOptions.sourcehash)
        try fs.removeFileTree(sourcehashOutputPath) // delete the build completion marker to force its re-creation (removeFileTree doesn't throw when the file doesn't exist)

        // also add any files in the skipFolderFile to the list of sources (including the skip.yml and other metadata files)
        let skipFolderPathContents = try FileManager.default.enumeratedURLs(of: skipFolderPath.asURL)
            .filter({ (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true })

        // validate licenses in all the Skip source files, as well as any custom Kotlin files in the Skip folder
        let sourcehashes = try await createSourceHashes(validateLicense: ["swift", "kt", "java"], sourceURLs: sourceURLs + skipFolderPathContents)
        // touch the build marker with the most recent file time from the complete build list
        // if we were to touch it afresh every time, the plugin would be re-executed every time
        defer {
            // finally, remove any "stale" files from the output folder that probably indicate a deleted or renamed file once all the known outputs have been written
            cleanupStaleOutputFiles()

            do {
                // touch the source hash file with a new timestamp to signal to the plugin host that our output file has been written
                try saveSourcehashFile()
            } catch {
                msg(.warning, "could not create build completion marker: \(error)")
            }
        }

        let buildGradle = moduleRootPath.appending(component: "build.gradle.kts")

        var dependentModuleExports: [CodebaseInfo.ModuleExport] = []
        let codebaseInfo = try await loadCodebaseInfo() // initialize the codebaseinfo and load DependentModuleName.skipcode.json

        // load and merge each of the skip.yml files for the dependent modules
        let (baseSkipConfig, mergedSkipConfig, configMap) = try loadSkipConfig(merge: true)

        let isNativeSwiftProject = baseSkipConfig.skip?.mode?.lowercased() == "swift"
        let swiftSourceFolder = skipFolderPath.parentDirectory.appending(component: "Swift")
        let kotlinSourceFolder = skipFolderPath.parentDirectory.appending(component: "Kotlin")

        // projects with a CMakeLists.txt file are built as a native Android library
        // these are only used for purely native code libraries, and so we short-circuit the build generation
        if isCMakeProject {
            // Link ext/ to the relative cmake target
            let extLink = moduleRootPath.appending(component: "ext")
            try addLink(extLink, pointingAt: projectFolderPath, relative: false)
        }

        // the standard base name for Gradle Kotlin and Java source files
        let kotlinOutputFolder = try AbsolutePath(outputFolderPath, validating: "kotlin")
        let javaOutputFolder = try AbsolutePath(outputFolderPath, validating: "java")

        // the standard base name for resources, which will be linked from a path like: src/main/resources/package/name/resname.ext
        let resourcesOutputFolder = try AbsolutePath(outputFolderPath, validating: "resources")

        // Android-specific resources like res/values/strings.xml
        let resOutputFolder = try AbsolutePath(outputFolderPath, validating: "res")

        if !fs.isDirectory(kotlinOutputFolder) {
            // e.g.: ~Library/Developer/Xcode/DerivedData/PACKAGE-ID/SourcePackages/plugins/skiphub.output/SkipFoundationKotlinTests/skipstone/SkipFoundation/src/test/kotlin
            //throw error("Folder specified by --output-folder did not exist: \(outputFolder)")
            try fs.createDirectory(kotlinOutputFolder, recursive: true)
        }

        // now make a link from src/androidTest/kotlin to src/test/kotlin so the same tests will run against an Android emulator/device with the ANDROID_SERIAL environment
        if primaryModuleName.hasSuffix("Tests") {
            let androidTestOutputFolder = try AbsolutePath(outputFolderPath, validating: "../androidTest")
            try? fs.removeFileTree(androidTestOutputFolder) // remove any existing link in order to re-create it
            try fs.createSymbolicLink(addOutputFile(androidTestOutputFolder), pointingAt: outputFolderPath, relative: true)
        }

        //let isAppProject = skipFolderPathContents.contains(where: { $0.lastPathComponent == AndroidManifestName })

        let packageName = KotlinTranslator.packageName(forModule: primaryModuleName)

        let transformers: [KotlinTransformer] = try createTransformers(for: baseSkipConfig, with: configMap)

        let overridden = try linkSkipFolder(skipFolderPath, to: kotlinOutputFolder, topLevel: true)
        let overriddenKotlinFiles = overridden.map({ $0.basename })

        // the contents of a folder named "buildSrc" are linked at the top level to contain scripts and plugins
        let buildSrcFolder = skipFolderPath.appending(component: buildSrcFolderName)
        if fs.isDirectory(buildSrcFolder) {
            // we link (recursively) the individual files in a mirror of the directory hierarchy
            try createMirroredLinkTree(from: buildSrcFolder, to: moduleBasePath.appending(component: buildSrcFolderName))
        }

        // feed the transpiler the files to transpile and any compiled files to potentially bridge.
        // we default the file mode based on skip.yml's mode, and anything in 'Swift/' is compiled
        // and anything in 'Kotlin/' is transpiled
        let kotlinSourcePrefix = kotlinSourceFolder.pathString + "/"
        let swiftSourcePrefix = swiftSourceFolder.pathString + "/"
        var transpileFiles: [String] = []
        var swiftFiles: [String] = []
        for sourceFile in sourceURLs.map(\.path).sorted() {
            if isNativeSwiftProject {
                if sourceFile.hasPrefix(kotlinSourcePrefix) {
                    transpileFiles.append(sourceFile)
                } else {
                    swiftFiles.append(sourceFile)
                }
            } else {
                if sourceFile.hasPrefix(swiftSourcePrefix) {
                    swiftFiles.append(sourceFile)
                } else {
                    transpileFiles.append(sourceFile)
                }
            }
        }
        let transpiler = Transpiler(packageName: packageName, transpileFiles: transpileFiles.map(Source.FilePath.init(path:)), bridgeFiles: swiftFiles.map(Source.FilePath.init(path:)), codebaseInfo: codebaseInfo, preprocessorSymbols: Set(inputOptions.symbols), transformers: transformers)

        try await transpiler.transpile(handler: handleTranspilation)
        try saveCodebaseInfo() // save out the ModuleName.skipcode.json
        if isNativeSwiftProject || fs.exists(swiftSourceFolder) {
            try saveSkipBridgeCode(swiftSourceFolder: swiftSourceFolder)
        }

        let sourceModules = try linkDependentModuleSources()
        try linkResources()

        try generateGradle(for: sourceModules, with: mergedSkipConfig, isApp: isAppModule)

        return // done

        // MARK: Transpilation helper functions

        /// The relative path for cached codebase info JSON
        func moduleExportPath(forModule moduleName: String) throws -> RelativePath {
            try RelativePath(validating: moduleName + skipcodeExtension)
        }

        func loadCodebaseInfo() async throws -> CodebaseInfo {
            let decoder = JSONDecoder()

            // go through the '--link modulename:../../some/path' arguments and try to load the modulename.skipcode.json symbols from the previous module's transpilation output
            for (linkModuleName, relativeLinkPath) in linkNamePaths {
                let linkModuleRoot = moduleRootPath
                    .parentDirectory
                    .appending(try RelativePath(validating: relativeLinkPath))


                let dependencyModuleExport = linkModuleRoot
                    .parentDirectory
                    .appending(try moduleExportPath(forModule: linkModuleName))

                do {
                    let exportLoadStart = Date().timeIntervalSinceReferenceDate
                    trace("dependencyModuleExport \(dependencyModuleExport): exists \(fs.exists(dependencyModuleExport))")
                    let exportData = try inputSource(dependencyModuleExport).withData { Data($0) }
                    let export = try decoder.decode(CodebaseInfo.ModuleExport.self, from: exportData)
                    dependentModuleExports.append(export)
                    let exportLoadEnd = Date().timeIntervalSinceReferenceDate
                    info("\(dependencyModuleExport.basename) codebase (\(exportData.count.byteCount)) loaded (\(Int64((exportLoadEnd - exportLoadStart) * 1000)) ms) for \(linkModuleName)", sourceFile: dependencyModuleExport.sourceFile)
                } catch let e {
                    throw error("Skip: error loading codebase for \(linkModuleName): \(e.localizedDescription)", sourceFile: dependencyModuleExport.sourceFile)
                }
            }

            let codebaseInfo = CodebaseInfo(moduleName: primaryModuleName)
            codebaseInfo.dependentModules = dependentModuleExports
            return codebaseInfo
        }

        func writeChanges(tag: String, to outputFilePath: AbsolutePath, contents: any DataProtocol, readOnly: Bool) throws {
            let changed = try fs.writeChanges(path: addOutputFile(outputFilePath), makeReadOnly: readOnly, bytes: ByteString(contents))
            info("\(outputFilePath.relative(to: moduleBasePath).pathString) (\(contents.count.byteCount)) \(tag) \(!changed ? "unchanged" : "written")", sourceFile: outputFilePath.sourceFile)
        }

        func saveSourcehashFile() throws {
            if !fs.isDirectory(moduleBasePath) {
                try fs.createDirectory(moduleBasePath, recursive: true)
            }

            struct SourcehashContents : Encodable {
                /// The version of Skip that generates this marker file
                let skipstone: String = skipVersion

                /// The relative input paths and hashes for source files, in order to identify when input contents or file lists have changed
                let sourcehashes: [String: String]
            }

            // create relative source paths so we do not encode full paths in the output
            let sourcePathHashes: [(String, String)] = sourcehashes.compactMap { url, sourcehash in
                let absolutePath = url.path
                if !absolutePath.hasPrefix(projectFolderPath.pathString) {
                    return .none
                }

                let relativePath = absolutePath.dropFirst(projectFolderPath.pathString.count).trimmingPrefix(while: { $0 == "/" })
                return (relativePath.description, sourcehash)
            }

            let sourcehash = SourcehashContents(sourcehashes: Dictionary(sourcePathHashes, uniquingKeysWith: { $1 }))
            try writeChanges(tag: "sourcehash", to: sourcehashOutputPath, contents: try encoder.encode(sourcehash), readOnly: false)
        }

        func saveCodebaseInfo() throws {
            let outputFilePath = try moduleBasePath.appending(moduleExportPath(forModule: primaryModuleName))
            let moduleExport = CodebaseInfo.ModuleExport(of: codebaseInfo)
            try writeChanges(tag: "codebase", to: outputFilePath, contents: encoder.encode(moduleExport), readOnly: true)
        }

        func saveSkipBridgeCode(swiftSourceFolder: AbsolutePath) throws {
            // Link src/main/swift/ to the relative Swift project folder
            let swiftLinkFolder = try AbsolutePath(outputFolderPath, validating: "swift")
            try fs.createDirectory(swiftLinkFolder.parentDirectory, recursive: true)

            try createMirroredLinkTree(from: rootPath, to: swiftLinkFolder) { path in
                info("createMirroredLinkTree for \(path.pathString)")
                if let matchingBridge = skipBridgeTranspilations.first(where: { t in
                    info("skipBridgeTranspilations: \(t.outputFileBaseName) vs. \(path.sourceFile.path)")
                    return t.output.file.bridgelessOutputFile == path.sourceFile
                }) {
                    let basename = try AbsolutePath(validating: matchingBridge.output.file.path).basename
                    let isBridgeToSwift = matchingBridge.outputType == .bridgeToSwift
                    info("bridge \(isBridgeToSwift ? "replace" : "add") content with \(matchingBridge.output.file.path) (kotlin: \(matchingBridge.kotlinFileName)) to \(basename)")
                    return (tag: "skipbridge", basename: isBridgeToSwift ? nil : basename, content: matchingBridge.output.content.utf8Data)
                }
                return nil
            }

            // create Packages/swift-package-name links for all the project's package dependencies so we use the local versions in our swift build rather than downloading the remote dependencies
            // this will sync with Xcode's workspace, which will enable local package development of dependencies to work the same with this derived package as it does in Xcode
            let packagesLinkFolder = try AbsolutePath(swiftLinkFolder, validating: "Packages")
            try fs.createDirectory(packagesLinkFolder, recursive: false)
            for (id, path) in self.dependencyIdPaths {
                info("creating dependency link: \(id)->\(path)")
                let dependencyPackageLink = try AbsolutePath(packagesLinkFolder, validating: id)
                let destinationPath = try AbsolutePath(validating: path)
                try addLink(dependencyPackageLink, pointingAt: destinationPath, relative: false)
            }
        }

        func generateGradle(for sourceModules: [String], with skipConfig: SkipConfig, isApp: Bool) throws {
            try generateGradleWrapperProperties()
            try generateProguardFile(packageName)
            try generatePerModuleGradle()
            try generateGradleProperties()
            try generateSettingsGradle()

            func generatePerModuleGradle() throws {
                let buildContents = (skipConfig.build ?? .init()).generate(context: .init(dsl: .kotlin))

                // we output as a joined string because there is a weird stdout bug with the tool or plugin executor somewhere that causes multi-line strings to be output in the wrong order
                trace("created gradle: \(buildContents.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }).joined(separator: "; "))")

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
            func generateProguardFile(_ packageName: String) throws {
                try writeChanges(tag: "proguard", to: moduleRootPath.appending(component: "proguard-rules.pro"), contents: FrameworkProjectLayout.defaultProguardContents(packageName).utf8Data, readOnly: true)
            }


            /// Create the gradle-wrapper.properties file, which will dictate which version of Gradle that Android Studio should use to build the project.
            func generateGradleWrapperProperties() throws {
                let gradleWrapperFolder = moduleRootPath.parentDirectory.appending(components: "gradle", "wrapper")
                try fs.createDirectory(gradleWrapperFolder, recursive: true)
                let gradleWrapperPath = gradleWrapperFolder.appending(component: "gradle-wrapper.properties")
                let gradeWrapperContents = FrameworkProjectLayout.defaultGradleWrapperProperties()
                try writeChanges(tag: "gradle wrapper", to: gradleWrapperPath, contents: gradeWrapperContents.utf8Data, readOnly: true)
            }

            func generateGradleProperties() throws {
                // TODO: assemble these from skip.yml settings
                let gradlePropertiesPath = moduleRootPath.parentDirectory.appending(component: "gradle.properties")
                let gradePropertiesContents = FrameworkProjectLayout.defaultGradleProperties()
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

                // for app modules, import its settings into the manifestPlaceholders dictionary in the `android { defaultConfig { } }` block
                if isAppModule {
                    var manifestConfigLines: [String] = []

                    let moduleXCConfigContents = try String(contentsOf: moduleXCConfig.asURL, encoding: .utf8)
                    for (key, value) in parseXCConfig(contents: moduleXCConfigContents) {
                        manifestConfigLines += ["""
                        manifestPlaceholders["\(key)"] = System.getenv("\(key)") ?: "\(value)"
                        """]
                    }


                    // now do some manual configuration of the android properties
                    manifestConfigLines += ["""
                    applicationId = manifestPlaceholders["PRODUCT_BUNDLE_IDENTIFIER"]?.toString().replace("-", "_")
                    """]

                    manifestConfigLines += ["""
                    versionCode = (manifestPlaceholders["CURRENT_PROJECT_VERSION"]?.toString())?.toInt()
                    """]

                    manifestConfigLines += ["""
                    versionName = manifestPlaceholders["MARKETING_VERSION"]?.toString()
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

        func sourceFileOutputPath(for baseSourceFileName: String, in basePath: AbsolutePath? = nil) throws -> AbsolutePath? {
            if baseSourceFileName == "skip.yml" {
                // skip metadata files are excluded from copy
                return nil
            }

            // Kotlin (.kt) files go to src/main/kotlin/package/name/File.kt, and Java (.java) files go to src/main/java/package/name/File.kt
            let rawSourceDestination = baseSourceFileName.hasSuffix(".kt") ? kotlinOutputFolder : javaOutputFolder

            // the "AndroidManifest.xml" file is special: it needs to go in the root src/main/ folder
            let isManifest = baseSourceFileName == AndroidManifestName
            // if an empty basePath, treat as a source file and place in package-derived folders
            return try (basePath ?? rawSourceDestination
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

                if path.basename == buildSrcFolderName {
                    continue // don't copy buildSrc into resources
                }

                let sourcePath = try AbsolutePath(path, validating: fileName)
                let outputPath = try AbsolutePath(outputFilePath, validating: fileName)

                if fs.isDirectory(sourcePath) {
                    // make recursive folders for sub-linked resources
                    let subPaths = try linkSkipFolder(sourcePath, to: outputPath, topLevel: false)
                    copiedFiles.formUnion(subPaths)
                } else {
                    if let outputFilePath = try sourceFileOutputPath(for: sourcePath.basename, in: topLevel ? nil : outputFilePath) {
                        copiedFiles.insert(outputFilePath)
                        try fs.createDirectory(outputFilePath.parentDirectory, recursive: true) // ensure parent exists
                        // we make links instead of copying so the file can be edited from the gradle project structure without needing to be manually synchronized
                        try addLink(outputFilePath, pointingAt: sourcePath, relative: false)
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

            guard !transpilation.output.file.isBridgeOutputFile else {
                skipBridgeTranspilations.append(transpilation)
                info("bridge transpilation: \(transpilation.output.file.path) source: \(transpilation.output.content.count.byteCount)")
                return
            }

            let sourcePath = try AbsolutePath(validating: transpilation.input.file.path)

            let (outputFile, changed, overridden) = try saveTranspilation()

            // 2 separate log messages, one linking to the source swift and the second linking to the kotlin
            // this makes the log rather noisy, and isn't very useful
            //if !transpilation.isSourceFileSynthetic {
            //    info("\(sourcePath.basename) (\(byteCount(for: .init(sourceSize)))) transpiling to \(outputFile.basename)", sourceFile: transpilation.sourceFile)
            //}

            info("\(outputFile.relative(to: moduleBasePath).pathString) (\(transpilation.output.content.lengthOfBytes(using: .utf8).byteCount)) transpilation \(overridden ? "overridden" : !changed ? "unchanged" : "saved") from \(sourcePath.basename) (\(transpilation.input.content.lengthOfBytes(using: .utf8).byteCount)) in \(Int64(transpilation.duration * 1000)) ms", sourceFile: overridden ? transpilation.input.file : outputFile.sourceFile)

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
                guard let outputFilePath = try sourceFileOutputPath(for: kotlinName) else {
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
            let resourcesBasePath = resourcesOutputFolder
                .appending(components: packageName.split(separator: ".").map(\.description))
                .appending(component: "Resources")

            var resourcesIndex: [RelativePath] = []

            for resourceFile in resourceURLs.map(\.path).sorted() {
                guard let resourceSourceURL = moduleNamePaths.compactMap({ (_, folder) in
                    resourceFile.hasPrefix(folder) ? URL(fileURLWithPath: resourceFile.dropFirst(folder.count).trimmingCharacters(in: CharacterSet(charactersIn: "/")).description, relativeTo: URL(fileURLWithPath: folder, isDirectory: true)) : nil }).first else {
                    // skip over resources that are not contained within the Resources/ folder (such as files in the Skip/ folder, which contain metadata that should not be copied)
                    msg(.trace, "no module root parent for \(resourceFile)")
                    continue
                }

                let sourcePath = try AbsolutePath(validating: resourceSourceURL.path)


                let resourceComponents = try RelativePath(validating: resourceSourceURL.relativePath).components
                // all resources get put into a single "Resources/" folder in the jar, so drop the first item and replace it with "Resources/"
                let components = resourceComponents.dropFirst(1)
                let resourceSourcePath = try RelativePath(validating: components.joined(separator: "/"))

                if sourcePath.parentDirectory.basename == buildSrcFolderName {
                    trace("skipping resource linking for buildSrc/")
                } else if isCMakeProject {
                    trace("skipping resource linking for CMake project")
                } else if sourcePath.extension == "xcstrings" {
                    try convertStrings(resourceSourceURL: resourceSourceURL, sourcePath: sourcePath)
                //} else if sourcePath.extension == "xcassets" {
                    // TODO: convert various assets into Android res/ folder
                } else { // non-processed resources are just linked directly from the package
                    // the Android "res" folder is special: it is intended to store Android-specific resources like values/strings.xml, and will be linked into the archive's res/ folder
                    let isAndroidRes = resourceComponents.first == "res"
                    if !isAndroidRes {
                        resourcesIndex.append(resourceSourcePath)
                    }
                    let destinationPath = (isAndroidRes ? resOutputFolder : resourcesBasePath).appending(resourceSourcePath)

                    // only create links for files that exist
                    if fs.isFile(sourcePath) {
                        info("\(destinationPath.relative(to: moduleBasePath).pathString) linking to \(sourcePath.pathString)", sourceFile: sourcePath.sourceFile)
                        try fs.createDirectory(destinationPath.parentDirectory, recursive: true)
                        try addLink(destinationPath, pointingAt: sourcePath, relative: false)
                    }
                }
            }

            let indexPath = resourcesBasePath.appending(component: "resources.lst")

            if !resourcesIndex.isEmpty {
                // write out the resources index file that acts as the directory for Java/Android resources
                try fs.writeChanges(path: addOutputFile(indexPath), bytes: ByteString(encodingAsUTF8: resourcesIndex.map(\.pathString).sorted().joined(separator: "\n")))
                info("indexed \(resourcesIndex.count) resources at \(indexPath.pathString)", sourceFile: indexPath.sourceFile)
            } else {
                // remove the resources file if it should be empty
                try? fs.removeFileTree(indexPath)
            }

            func convertStrings(resourceSourceURL: URL, sourcePath: AbsolutePath) throws {
                // process the .xcstrings in the same way that Xcode does: parse the JSON and use the localizations keys to synthesize a LANG.lproj/TABLENAME.strings file
                let xcstrings = try JSONDecoder().decode(LocalizableStringsDictionary.self, from: Data(contentsOf: resourceSourceURL))
                let locales = Set(xcstrings.strings.values.compactMap(\.localizations?.keys).joined())
                for localeId in locales {
                    var locdict: [String: String] = [:]
                    for key in xcstrings.strings.keys.sorted() {
                        if let value = xcstrings.strings[key]?.localizations?[localeId]?.stringUnit?.value {
                            locdict[key] = value
                        }
                    }

                    if !locdict.isEmpty {
                        let lproj = try RelativePath(validating: localeId + ".lproj" + "/" + sourcePath.basenameWithoutExt + ".strings") // e.g., fr.lproj/Localizable.strings
                        let destinationPath = resourcesBasePath.appending(lproj)

                        func escape(_ string: String) throws -> String? {
                            // escape quotes and newlines; we just use a JSON string fragment for this
                            try String(data: JSONSerialization.data(withJSONObject: string, options: .fragmentsAllowed), encoding: .utf8)
                        }

                        var stringsContent = ""
                        for (key, value) in locdict.sorted(by: { $0.key < $1.key }) {
                            if let keyString = try escape(key), let valueString = try escape(value) {
                                stringsContent += keyString + " = " + valueString + ";\n"
                            }
                        }
                        try fs.createDirectory(destinationPath.parentDirectory, recursive: true)
                        info("create \(lproj.pathString) from \(sourcePath.pathString)", sourceFile: destinationPath.sourceFile)
                        try writeChanges(tag: lproj.pathString, to: destinationPath, contents: stringsContent.utf8Data, readOnly: false)
                        resourcesIndex.append(lproj)
                    }
                }
            }


        }

        // NOTE: when linking between modules, SPM and Xcode will use different output paths:
        // Xcode: ~/Library/Developer/Xcode/DerivedData/PROJECT-ID/SourcePackages/plugins/skiphub.output/SkipFoundationKotlinTests/skipstone/SkipFoundation
        // SPM: .build/plugins/outputs/skiphub/
        func linkDependentModuleSources() throws -> [String] {
            var dependentModules: [String] = []
            // transpilation was successful; now set up links to the other output packages (located in different plug-in folders)
            let moduleBasePath = moduleRootPath.parentDirectory


            // for each of the specified link/path pairs, create symbol links, either to the base folders, or the the sub-folders that share a common root
            // this is the logic that allows us to merge two modules (like MyMod and MyModTests) into a single Kotlin module with the idiomatic src/main/kotlin/ and src/test/kotlin/ pair of folders
            for (linkModuleName, relativeLinkPath) in linkNamePaths {
                let linkModulePath = try moduleBasePath.appending(RelativePath(validating: linkModuleName))
                trace("relativeLinkPath: \(relativeLinkPath) moduleBasePath: \(moduleBasePath) linkModuleName: \(linkModuleName) -> linkModulePath: \(linkModulePath)")
                try createMergedRelativeLinkTree(from: linkModulePath, to: relativeLinkPath)
                dependentModules.append(linkModuleName)
            }

            return dependentModules
        }

        /// Attempts to make a link from the `fromPath` to the given relative path.
        /// If `fromPath` already exists and is a directory, attempt to create links for each of the contents of the directory to the updated relative folder
        func createMergedRelativeLinkTree(from fromPath: AbsolutePath, to relative: String) throws {
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
                    try createMergedRelativeLinkTree(from: fromSubPath, to: "../" + relative + "/" + fsEntry)
                }
            } else {
                try addLink(fromPath, pointingAt: destPath, relative: true)
            }
        }


        /// Create a mirror hierarchy of the directory structure at `from` in the folder specified by `to`, and link each individual file in the hierarchy
        func createMirroredLinkTree(from fromPath: AbsolutePath, to destPath: AbsolutePath, contentHandler: ((AbsolutePath) throws -> (tag: String, basename: String?, content: Data)?)? = nil) throws {
            trace("creating absolute merged link tree from: \(fromPath) to: \(destPath)")
            // the folder is a directory; recurse into the destination paths in order to link to the local paths
            if fs.isDirectory(fromPath) {
                // we create output directories and link the contents, rather than just linking the folders themselves, since Gradle wants to be able to write to the output folders
                try fs.createDirectory(destPath, recursive: true)
                for fsEntry in try fs.getDirectoryContents(fromPath) {
                    if fsEntry.hasPrefix(".") {
                        continue
                    }
                    let rel = try RelativePath(validating: fsEntry)
                    let destDir = destPath.appending(rel)
                    try createMirroredLinkTree(from: fromPath.appending(rel), to: destDir, contentHandler: contentHandler)
                }
            } else if fs.isFile(fromPath) {
                // check whether the contentHandler wants to write out additional data, either as a separate sidecar or overriding the link
                if let (tag, basename, content) = try contentHandler?(fromPath) {
                    if let basename = basename {
                        // link the file as expected, but then add the contents to the basename as a sidecar for the file
                        try addLink(destPath, pointingAt: fromPath, relative: false)
                        let destPathPeer = try destPath.parentDirectory.appending(RelativePath(validating: basename))
                        info("writing bridge sidecare contents (\(content.count.byteCount)) to \(destPathPeer)")
                        try writeChanges(tag: tag, to: destPathPeer, contents: content, readOnly: true)
                    } else {
                        // with no basename specified, we override the link with the contents from the handler
                        info("override bridge link tag \(tag) content (\(content.count.byteCount)) for: \(fromPath)")
                        try writeChanges(tag: tag, to: destPath, contents: content, readOnly: true)
                    }
                } else {
                    try addLink(destPath, pointingAt: fromPath, relative: false)
                }
            } else {
                warn("unknown file type encountered when creating links: \(fromPath)")
            }
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

struct TranspileCommandOptions: ParsableArguments {
    @Option(name: [.customLong("project"), .long], help: ArgumentHelp("The project folder to transpile", valueName: "folder"))
    var projectFolder: String // --project

    @Option(name: [.long], help: ArgumentHelp("The path to the source hash file to output", valueName: "path"))
    var sourcehash: String // --sourcehash

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

    @Option(name: [.customLong("dependency")], help: ArgumentHelp("id:path", valueName: "dependency"))
    var dependencies: [String] = [] // --dependency id:path
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

        if let fileURLs = self.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let fileURL as URL in fileURLs {
                let attrs = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if attrs.isRegularFile == true || attrs.isSymbolicLink == true {
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

        let components = line.split(separator: "=", maxSplits: 2)
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


/// The contents of a `Localizable.xcstrings` file, which is used for maually generating `Localizable.strings` files.
struct LocalizableStringsDictionary : Decodable {
    let version: String
    let sourceLanguage: String
    let strings: [String: StringsEntry]

    struct StringsEntry : Decodable {
        let extractionState: String? // e.g., "stale"
        let comment: String?
        let localizations: [String: TranslationSet]?
    }

    struct TranslationSet : Decodable {
        let stringUnit: StringUnit?
    }

    struct StringUnit: Decodable {
        let state: String? // e.g., "translated"
        let value: String?
    }
}
