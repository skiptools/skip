import Foundation
import ArgumentParser
import Universal
import SkipSyntax
import TSCBasic

protocol TranspilePhase: CheckPhase {
    var transpileOptions: TranspilePhaseOptions { get }
}

struct TranspileCommand: TranspilePhase, StreamingCommand {
    static var configuration = CommandConfiguration(commandName: "transpile", abstract: "Transpile Swift to Kotlin", shouldDisplay: false)

    @OptionGroup(title: "Check Options")
    var checkOptions: CheckPhaseOptions

    @OptionGroup(title: "Transpile Options")
    var transpileOptions: TranspilePhaseOptions

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "License Options")
    var licenseOptions: LicenseOptions

    struct Output : MessageConvertible {
        let transpilation: Transpilation

        var description: String {
            "transpilation successful: \(transpilation.messages.count > 0 ? transpilation.messages.count.description : "no") messages" // transpilation.sourceFile.url.lastPathComponent
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

    func performCommand(with continuation: AsyncThrowingStream<OutputMessage, Error>.Continuation) async throws {
        let sourceFiles = try checkOptions.files.map(AbsolutePath.init(validating:))
        #if DEBUG
        let v = skipVersion + "*" // * indicates debug version
        #else
        let v = skipVersion
        #endif
        info("Skip \(v): transpiling to: \(transpileOptions.outputFolder ?? "nowhere") for: \(sourceFiles.map(\.basename))")
        try await self.transpile(fs: localFileSystem, sourceFiles: Set(sourceFiles), with: continuation)
    }

    private func transpile(fs: FileSystem, sourceFiles: Set<AbsolutePath>, with continuation: AsyncThrowingStream<OutputMessage, Error>.Continuation) async throws {
        // the path that will contain the `skip.yml`
        guard let skipFolder = transpileOptions.skipFolder else {
            throw error("Must specify --skip-folder")
        }

        let baseOutputPath = try fs.currentWorkingDirectory ?? fs.tempDirectory

        let skipFolderPath = try AbsolutePath(validating: skipFolder, relativeTo: baseOutputPath)
        if !fs.isDirectory(skipFolderPath) {
            throw error("Folder specified by --skip-folder did not exist: \(skipFolderPath)")
        }

        guard let outputFolder = transpileOptions.outputFolder else {
            throw error("Must specify --output-folder")
        }

        let kotlinOutputFolder = try AbsolutePath(AbsolutePath(validating: outputFolder, relativeTo: baseOutputPath), "kotlin")
        // the standard base name for resources, which will be linked from a path like: src/main/resources/package/name/resname.ext
        let resourcesOutputFolder = try AbsolutePath(AbsolutePath(validating: outputFolder, relativeTo: baseOutputPath), "resources")

        if !fs.isDirectory(kotlinOutputFolder) {
            // e.g.: ~Library/Developer/Xcode/DerivedData/PACKAGE-ID/SourcePackages/plugins/skiphub.output/SkipFoundationKotlinTests/skip-transpiler/SkipFoundation/src/test/kotlin
            //throw error("Folder specified by --output-folder did not exist: \(outputFolder)")
            try fs.createDirectory(kotlinOutputFolder, recursive: true)
        }

        guard let moduleRoot = transpileOptions.moduleRoot else {
            throw error("Must specify --module-root")
        }
        let moduleRootPath = try AbsolutePath(validating: moduleRoot)
        if !fs.isDirectory(moduleRootPath) {
            throw error("Module root path did not exist at: \(moduleRootPath.pathString)")
        }

        guard let (primaryModuleName, primaryModulePath) = moduleNamePaths.first else {
            throw error("Must specify at least one --module")
        }

        let _ = primaryModulePath

        let packageName = KotlinTranslator.packageName(forModule: primaryModuleName)
        // skip over any source file whose name would match a copied Kotlin file
        let sources = sourceFiles.map(\.sourceFile)

        // load and merge each of the skip.yml files for the dependent modules
        let (baseSkipConfig, mergedSkipConfig, configMap) = try loadSkipConfig(merge: true)
        let transformers: [KotlinTransformer] = try createTransformers(for: baseSkipConfig, with: configMap)

        var dependentCodebaseInfos: [CodebaseInfo] = []

        let moduleBasePath = moduleRootPath.parentDirectory

        let codebaseInfo = try await loadCodebaseInfo() // initialize the codebaseinfo and load DependentModuleName.skipcode.json

        var sourceURLs = sourceFiles.map(\.asURL)

        let overridden = try linkSkipFolder(skipFolderPath, to: kotlinOutputFolder, topLevel: true)
        let overriddenKotlinFiles = overridden.map({ $0.basename })

        // also check any Kotlin files in the skipFolderFile
        let skipFolderPathContents = try fs.getDirectoryContents(skipFolderPath)
            .map { AbsolutePath(skipFolderPath, $0) }

        for kotlinFile in skipFolderPathContents {
            if kotlinFile.extension == "kt" {
                sourceURLs += [kotlinFile.asURL]
            }
        }

        try await validateLicense(sourceURLs: sourceURLs)

        let transpiler = Transpiler(packageName: packageName, sourceFiles: sources, codebaseInfo: codebaseInfo, preprocessorSymbols: Set(checkOptions.symbols), transformers: transformers)
        try await transpiler.transpile(handler: handleTranspilation)
        try saveCodebaseInfo() // save out the ModuleName.skipcode.json

        let sourceModules = try linkDependentModuleSources()
        try linkResources()
        try generateGradle(for: sourceModules, with: mergedSkipConfig)

        return // everything following is a stage of the transpilation process

        /// Load the given source file, tracking its last modified date for the timestamp on the `.skipbuild` marker file
        func inputSource(_ path: AbsolutePath) throws -> ByteString {
            try fs.readFileContents(path)
        }

        /// The relative path for cached codebase info JSON
        func codebaseInfoPath(forModule moduleName: String) -> RelativePath {
            RelativePath(moduleName + ".skipcode.json")
        }

        func loadCodebaseInfo() async throws -> CodebaseInfo {
            let decoder = JSONDecoder()

            // go through the '--link modulename:../../some/path' arguments and try to load the modulename.skipcode.json symbols from the previous module's transpilation output
            for (linkModuleName, relativeLinkPath) in linkNamePaths {
                let linkModuleRoot = moduleRootPath
                    .parentDirectory
                    .appending(RelativePath(relativeLinkPath))


                let dependencyCodebaseInfo = linkModuleRoot
                    .parentDirectory
                    .appending(codebaseInfoPath(forModule: linkModuleName))

                do {
                    let codebaseLoadStart = Date().timeIntervalSinceReferenceDate
                    let cbdata = try inputSource(dependencyCodebaseInfo).withData { Data($0) }
                    trace("dependencyCodebaseInfo \(dependencyCodebaseInfo): exists \(fs.exists(dependencyCodebaseInfo)) data: \(cbdata.count)")
                    let cbinfo = try decoder.decode(CodebaseInfo.self, from: cbdata)
                    dependentCodebaseInfos.append(cbinfo)
                    let codebaseLoadEnd = Date().timeIntervalSinceReferenceDate
                    info("\(dependencyCodebaseInfo.basename) codebase (\(byteCount(for: .init(cbdata.count)))) loaded (\(Int64((codebaseLoadEnd - codebaseLoadStart) * 1000)) ms) for \(linkModuleName)", sourceFile: dependencyCodebaseInfo.sourceFile)
                } catch let e {
                    throw error("Skip: error loading codebase for \(linkModuleName): \(e.localizedDescription)", sourceFile: dependencyCodebaseInfo.sourceFile)
                }
            }

            let codebaseInfo = CodebaseInfo(moduleName: primaryModuleName)
            codebaseInfo.dependentModules = dependentCodebaseInfos
            return codebaseInfo
        }

        func saveCodebaseInfo() throws {
            let outputFilePath = moduleBasePath.appending(codebaseInfoPath(forModule: primaryModuleName))

            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .sortedKeys, // needed for deterministic output
                .withoutEscapingSlashes,
                //.prettyPrinted,
            ]
            let codebaseBytes = ByteString(Array(try encoder.encode(codebaseInfo)))

            let codebaseWritten = try fs.writeChanges(path: outputFilePath, checkSize: true, makeReadOnly: true, bytes: codebaseBytes)
            info("\(outputFilePath.basename) (\(byteCount(for: .init(codebaseBytes.count)))) codebase \(!codebaseWritten ? "unchanged" : "saved")", sourceFile: outputFilePath.sourceFile)
        }

        func generateGradle(for sourceModules: [String], with skipConfig: SkipConfig) throws {
            try generateSettingsGradle()
            try generatePerModuleGradle()
            try generateGradleProperties()
            if let gradleVersion = transpileOptions.gradleVersion as String? {
                try generateGradleWrapperProperties(version: gradleVersion)
            }

            func generatePerModuleGradle() throws {
                let buildContents = (skipConfig.build ?? .init()).generate(context: .init(dsl: .kotlin))
                // we output as a joined string because there is a weird stdout bug with the tool or plugin executor somewhere that causes multi-line strings to be output in the wrong order
                trace("created gradle: \(buildContents.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }).joined(separator: "; "))")

                let buildGradle = moduleRootPath.appending(components: ["build.gradle.kts"])
                let contents = """
                // build.gradle.kts generated by Skip for \(primaryModuleName)

                """ + buildContents

                let changed = try fs.writeChanges(path: buildGradle, makeReadOnly: true, bytes: ByteString(encodingAsUTF8: contents))
                info("\(buildGradle.basename) (\(byteCount(for: .init(contents.count)))) \(!changed ? "unchanged" : "saved")", sourceFile: buildGradle.sourceFile)
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

                let changed = try fs.writeChanges(path: settingsPath, makeReadOnly: true, bytes: ByteString(encodingAsUTF8: settingsContents))
                info("\(settingsPath.basename) (\(byteCount(for: .init(settingsContents.count)))) \(!changed ? "unchanged" : "written")", sourceFile: settingsPath.sourceFile)
            }

            /// Create the gradle-wrapper.properties file, which will dictate which version of Gradle that Android Studio should use to build the project.
            func generateGradleWrapperProperties(version: String) throws {
                let gradleWrapperFolder = moduleRootPath.parentDirectory.appending(components: "gradle", "wrapper")
                try fs.createDirectory(gradleWrapperFolder, recursive: true)
                let gradleWrapperPath = gradleWrapperFolder.appending(component: "gradle-wrapper.properties")
                let gradeWrapperContents = """
                distributionUrl=https\\://services.gradle.org/distributions/gradle-\(version)-all.zip
                """

                let changed = try fs.writeChanges(path: gradleWrapperPath, makeReadOnly: true, bytes: ByteString(encodingAsUTF8: gradeWrapperContents))
                info("\(gradleWrapperPath.basename) (\(byteCount(for: .init(gradeWrapperContents.count)))) \(!changed ? "unchanged" : "written")", sourceFile: gradleWrapperPath.sourceFile)
            }

            func generateGradleProperties() throws {
                // TODO: assemble these from skip.yml settings
                let gradlePropertiesPath = moduleRootPath.parentDirectory.appending(component: "gradle.properties")
                let gradePropertiesContents = """
                org.gradle.jvmargs=-Xmx2048m
                android.useAndroidX=true
                kotlin.code.style=official
                """

                let changed = try fs.writeChanges(path: gradlePropertiesPath, makeReadOnly: true, bytes: ByteString(encodingAsUTF8: gradePropertiesContents))
                info("\(gradlePropertiesPath.basename) (\(byteCount(for: .init(gradePropertiesContents.count)))) \(!changed ? "unchanged" : "written")", sourceFile: gradlePropertiesPath.sourceFile)
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
            try trace("loading skip.yml from \(skipConfigPath): \(currentModuleJSON.prettyJSON)", sourceFile: skipConfigPath.sourceFile)

            if !merge {
                return (currentModuleConfig, currentModuleConfig, configMap) // just the unmerged base YAML
            }

            // build up a merged YAML from the base dependenices to the current module
            var aggregateJSON: Universal.JSON = [:]

            func isTestModule(_ moduleName: String) -> Bool {
                primaryModuleName != moduleName && primaryModuleName != moduleName + "Tests"
            }

            for (moduleName, modulePath) in moduleNamePaths {
                info("moduleName: \(moduleName) modulePath: \(modulePath)")
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
                var contents: [GradleBlock.BlockOrCommand] = []

                for (moduleName, _) in moduleNamePaths {
                    // manually exclude our own module and tests names
                    if isTestModule(moduleName) {
                        if moduleName == "SkipUnit" {
                            contents += [
                                .init("testImplementation(project(\":\(moduleName)\"))"),
                                .init("androidTestImplementation(project(\":\(moduleName)\"))")
                            ]
                        } else {
                            contents += [
                                .init("implementation(project(\":\(moduleName)\"))"),
                            ]
                        }
                    }
                }

                let localConfig = GradleBlock(contents: [.init(GradleBlock(block: "dependencies", contents: contents))])
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

        func kotlinOutputPath(for baseSourceFileName: String, in basePath: AbsolutePath? = nil) -> AbsolutePath? {
            if baseSourceFileName == "skip.yml" {
                // skip metadata files are excluded from copy
                return nil
            }

            // the "AndroidManifest.xml" file is special: it needs to go in the root src/main/ folder
            let isManifest = baseSourceFileName == "AndroidManifest.xml"
            // if an empty basePath, treat as a source file and place in package-derived folders
            return (basePath ?? kotlinOutputFolder
                .appending(components: isManifest ? [".."] : packageName.split(separator: ".").map(\.description)))
                .appending(RelativePath(baseSourceFileName))
        }

        /// Copies over the overridden .kt files from `ModuleNameKotlin/Skip/*.kt` into the destination folder,
        /// and makes links to any subdirectories, which enables the handling of `src/main/AndroidManifest.xml`
        /// and other custom resources.
        ///
        /// Any Kotlin files that are overridden will not be transpiled.
        func linkSkipFolder(_ path: AbsolutePath, to outputFilePath: AbsolutePath, topLevel: Bool, makeLinks: Bool = true) throws -> Set<AbsolutePath> {
            var copiedFiles: Set<AbsolutePath> = []
            for fileName in try fs.getDirectoryContents(path) {
                if fileName.hasPrefix(".") {
                    continue // skip hidden files
                }
                let sourcePath = AbsolutePath(path, fileName)
                let outputPath = AbsolutePath(outputFilePath, fileName)

                if fs.isDirectory(sourcePath) {
                    // make recursive folders for sub-linked resources
                    let subPaths = try linkSkipFolder(sourcePath, to: outputPath, topLevel: false, makeLinks: makeLinks)
                    copiedFiles.formUnion(subPaths)
                } else {
                    if let outputFilePath = kotlinOutputPath(for: sourcePath.basename, in: topLevel ? nil : outputFilePath) {
                        copiedFiles.insert(outputFilePath)
                        if makeLinks {
                            // we make links instead of copying so the file can be edited from the gradle project structure without needing to be manually synchronized
                            try? fs.removeFileTree(outputFilePath)
                            try fs.createDirectory(outputFilePath.parentDirectory, recursive: true) // ensure parent exists
                            try fs.createSymbolicLink(outputFilePath, pointingAt: sourcePath, relative: false)
                            trace("linked overridden source: \(sourcePath.pathString) to: \(outputFilePath.pathString)", sourceFile: sourcePath.sourceFile)
                            info("\(outputFilePath.basename) override linked from project", sourceFile: sourcePath.sourceFile)
                        } else {
                            try fs.writeChanges(path: outputFilePath, checkSize: true, bytes: inputSource(sourcePath))
                            trace("copied overridden source: \(sourcePath.pathString) to: \(outputFilePath.pathString)", sourceFile: sourcePath.sourceFile)
                            info("\(outputFilePath.basename) copied from project", sourceFile: sourcePath.sourceFile)
                        }
                    }
                }
            }
            return copiedFiles
        }

        func handleTranspilation(transpilation: Transpilation) throws {
            for message in transpilation.messages {
                continuation.yield(.init(message))
            }

            trace(transpilation.output.content)

            let sourcePath = try AbsolutePath(validating: transpilation.sourceFile.path)
            let sourceSize = transpilation.isSourceFileSynthetic ? 0 : try fs.getFileInfo(sourcePath).size

            let (outputFile, changed, overridden) = try saveTranspilation()

            // 2 separate log messages, one linking to the source swift and the second linking to the kotlin
            if !transpilation.isSourceFileSynthetic {
                info("\(sourcePath.basename) (\(byteCount(for: .init(sourceSize)))) transpiling to \(outputFile.basename)", sourceFile: transpilation.sourceFile)
            }

            info("\(outputFile.basename) (\(byteCount(for: transpilation.output.content.lengthOfBytes(using: .utf8)))) transpilation \(overridden ? "overridden" : !changed ? "unchanged" : "saved") from \(sourcePath.basename) (\(byteCount(for: .init(sourceSize)))) in \(Int64(transpilation.duration * 1000)) ms", sourceFile: overridden ? transpilation.sourceFile : outputFile.sourceFile)

            for message in transpilation.messages {
                //writeMessage(message)
                if message.kind == .error {
                    // throw the first error we see
                    continuation.finish(throwing: message)
                    return
                }
            }

            let output = Output(transpilation: transpilation)
            continuation.yield(.init(output))

            func saveTranspilation() throws -> (output: AbsolutePath, changed: Bool, overridden: Bool) {
                // the build plug-in's output folder base will be something like ~/Library/Developer/Xcode/DerivedData/Mod-ID/SourcePackages/plugins/module-name.output/ModuleNameKotlin/skip-transpiler/ModuleName/src/test/kotlin
                trace("path: \(kotlinOutputFolder)")

                let kotlinName = transpilation.kotlinFileName
                guard let outputFilePath = kotlinOutputPath(for: kotlinName) else {
                    throw error("No output path for \(kotlinName)")
                }

                if overriddenKotlinFiles.contains(kotlinName) {
                    return (output: outputFilePath, changed: false, overridden: true)
                }

                let kotlinBytes = ByteString(encodingAsUTF8: transpilation.output.content)
                let fileWritten = try fs.writeChanges(path: outputFilePath, checkSize: true, makeReadOnly: true, bytes: kotlinBytes)

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
                try fs.writeChanges(path: sourceMappingPath, makeReadOnly: true, bytes: ByteString(sourceMapData))

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

            for resourceFile in self.transpileOptions.resources {
                guard let resourceSourceURL = moduleNamePaths.compactMap({ (_, folder) in
                    resourceFile.hasPrefix(folder) ? URL(fileURLWithPath: resourceFile.dropFirst(folder.count).trimmingCharacters(in: CharacterSet(charactersIn: "/")).description, relativeTo: URL(fileURLWithPath: folder, isDirectory: true)) : nil }).first else {
                    msg(.warning, "no module root parent for \(resourceFile)")
                    continue
                }

                let sourcePath = try AbsolutePath(validating: resourceSourceURL.path)

                // all resources get put into a single "Resources/" folder in the jar, so drop the first item and replace it with "Resources/"
                let components = RelativePath(resourceSourceURL.relativePath).components.dropFirst(1)
                let resPath = components.joined(separator: "/")
                let resourceSourcePath = RelativePath(resPath)
                resourcesIndex.append(resPath)

                let destinationPath = destinationBasePath.appending(resourceSourcePath)

                // only create links for files that exist
                if fs.isFile(sourcePath) {
                    info("linking resource \(destinationPath.pathString) to \(sourcePath.sourceFile)", sourceFile: sourcePath.sourceFile)
                    try fs.createDirectory(destinationPath.parentDirectory, recursive: true)
                    if fs.isSymlink(destinationPath) {
                        try fs.removeFileTree(destinationPath) // clear any pre-existing symlink
                    }
                    try fs.createSymbolicLink(destinationPath, pointingAt: sourcePath, relative: false)
                }
            }

            let indexPath = destinationBasePath.appending(component: "resources.lst")

            if !resourcesIndex.isEmpty {
                // write out the resources index file that acts as the directory for Java/Android resources
                try fs.writeChanges(path: indexPath, bytes: ByteString(encodingAsUTF8: resourcesIndex.sorted().joined(separator: "\n")))
                info("indexed \(resourcesIndex.count) resources at \(indexPath.pathString)", sourceFile: indexPath.sourceFile)
            } else {
                // remove the resources file if it should be empty
                try? fs.removeFileTree(indexPath)
            }
        }

        // NOTE: when linking between modules, SPM and Xcode will use different output paths:
        // Xcode: ~/Library/Developer/Xcode/DerivedData/PROJECT-ID/SourcePackages/plugins/skiphub.output/SkipFoundationKotlinTests/skip-transpiler/SkipFoundation
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
                        let fromSubPath = fromPath.appending(RelativePath(fsEntry))
                        // bump up all the relative links to account for the folder we just recursed into.
                        // e.g.: ../SomeSharedRoot/OtherModule/
                        // becomes: ../../SomeSharedRoot/OtherModule/someFolder/
                        try createMergedLinkTree(from: fromSubPath, to: "../" + relative + "/" + fsEntry)
                    }
                } else {
                    try fs.createSymbolicLink(fromPath, pointingAt: destPath, relative: true)
                }
            }

            // for each of the specified link/path pairs, create symbol links, either to the base folders, or the the sub-folders that share a common root
            // this is the logic that allows us to merge two modules (like MyMod and MyModTests) into a single Kotlin module with the idiomatic src/main/kotlin/ and src/test/kotlin/ pair of folders
            for (linkModuleName, relativeLinkPath) in linkNamePaths {
                let linkModulePath = moduleBasePath.appending(RelativePath(linkModuleName))
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
    @Option(help: ArgumentHelp("Condition for transpile phase", valueName: "force/no"))
    var transpile: PhaseGuard = .onDemand // --transpile

    @Option(name: [.customLong("module")], help: ArgumentHelp("ModuleName:SourcePath", valueName: "module"))
    var moduleNames: [String] = [] // --module name:path

    @Option(name: [.customLong("resource")], help: ArgumentHelp("Resource path to link", valueName: "file"))
    var resources: [String] = [] // --resource Source/App/Resources/fr.lproj/Localizable.strings

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
    var gradleVersion: String = "8.1.1" // note: this should not be higher than the pre-installed version on the active CI runner image: https://github.com/actions/runner-images/tree/main/images/macos
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
