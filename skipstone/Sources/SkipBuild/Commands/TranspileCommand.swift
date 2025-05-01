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

    var dependencyIdPaths: [(targetName: String, packageID: String, packagePath: String)] {
        transpileOptions.dependencies.compactMap({
            let parts = $0.split(separator: ":").map(\.description)
            if parts.count != 3 { return nil }
            return (targetName: parts[0], packageID: parts[1], packagePath: parts[2])
        })
    }

    func performCommand(with out: MessageQueue) async throws {
        #if DEBUG
        let v = skipVersion + "*" // * indicates debug version
        #else
        let v = skipVersion
        #endif

        if Self.enablePreviews == true {
            info("Skip \(v): skipstone plugin not running for ENABLE_PREVIEWS=YES")
            return
        }

        if SkippyCommand.skippyOnly == true {
            info("Skip \(v): skipstone plugin not running for CONFIGURATION=Skippy")
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


        info("Skip \(v): skipstone plugin to: \(transpileOptions.outputFolder ?? "nowhere") at \(dateFormatter.string(from: .now))")
        try await self.transpile(root: baseOutputPath, project: projectFolderPath, module: moduleRootPath, skip: skipFolderPath, output: outputFolderPath, fs: fs, with: out)
    }

    private func transpile(root rootPath: AbsolutePath, project projectFolderPath: AbsolutePath, module moduleRootPath: AbsolutePath, skip skipFolderPath: AbsolutePath, output outputFolderPath: AbsolutePath, fs: FileSystem, with out: MessageQueue) async throws {
        do {
            try await transpileThrows(root: rootPath, project: projectFolderPath, module: moduleRootPath, skip: skipFolderPath, output: outputFolderPath, fs: fs, with: out)
        } catch {
            // ensure that the error is logged in some way before failing
            self.error("Skip \(skipVersion) error: \(error.localizedDescription)")
            throw error
        }
    }

    private func transpileThrows(root rootPath: AbsolutePath, project projectFolderPath: AbsolutePath, module moduleRootPath: AbsolutePath, skip skipFolderPath: AbsolutePath, output outputFolderPath: AbsolutePath, fs: FileSystem, with out: MessageQueue) async throws {
        trace("transpileThrows: rootPath=\(rootPath), projectFolderPath=\(projectFolderPath), moduleRootPath=\(moduleRootPath), skipFolderPath=\(skipFolderPath), outputFolderPath=\(outputFolderPath)")

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
                if staleFileURL.lastPathComponent == "Package.resolved" {
                    // Package.resolved is special, because it is output from the native build and removing it would cause an unnecessary rebuild
                    continue
                }
                msg(.warning, "removing stale output file: \(staleFileURL.lastPathComponent)", sourceFile: try? staleFileURL.absolutePath.sourceFile)

                do {
                    // don't actually trash it, since the output files often have read-only permissions set, and that prevents trash from working
                    try FileManager.default.trash(fileURL: staleFileURL, trash: false)
                } catch {
                    msg(.warning, "error removing stale output file: \(staleFileURL.lastPathComponent): \(error)")
                }
            }
        }

        /// track every output file written using `addOutputFile` to prevent the file from being cleaned up at the end
        @discardableResult func addOutputFile(_ path: AbsolutePath) -> AbsolutePath {
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
            let projectBaseURL = projectFolderPath.asURL
            let allProjectFiles: [URL] = try FileManager.default.enumeratedURLs(of: projectBaseURL)

            let swiftPathExtensions: Set<String> = ["swift"]
            let sourceURLs: [URL] = allProjectFiles.filter({ swiftPathExtensions.contains($0.pathExtension) })

            let projectResourcesURL = projectBaseURL.appendingPathComponent("Resources", isDirectory: true)
            let resourceURLs: [URL] = try FileManager.default.enumeratedURLs(of: projectResourcesURL)

            return (sources: sourceURLs, resources: resourceURLs)
        }

        let (sourceURLs, resourceURLs) = try buildSourceList()

        let moduleBasePath = moduleRootPath.parentDirectory

        // always touch the sourcehash file with the most recent source hashes in order to update the output file time
        /// Create a link from the source to the destination; this is used for resources and custom Kotlin files in order to permit edits to target file and have them reflected in the original source
        func addLink(_ linkSource: AbsolutePath, pointingAt destPath: AbsolutePath, relative: Bool, replace: Bool = true, copyReadOnlyFiles: Bool = true) throws {
            msg(.trace, "linking: \(linkSource) to: \(destPath)")

            if replace && fs.isSymlink(destPath) {
                removePath(destPath) // clear any pre-existing symlink
            }

            if let existingSymlinkDestination = try? FileManager.default.destinationOfSymbolicLink(atPath: linkSource.pathString) {
                if existingSymlinkDestination == destPath.pathString {
                    msg(.trace, "retaining existing link from \(destPath.pathString) to \(existingSymlinkDestination)")
                    addOutputFile(linkSource) // remember that we are using the linkSource file
                    return
                }
            }

            let destInfo = try fs.getFileInfo(destPath)
            let modTime = destInfo.modTime
            let perms = destInfo.posixPermissions

            // 0o200 adds owner write permission (write = 2, owner = 2)
            let writablePermissions = perms | 0o200

            // when the source file is not writable, we copy the file insead of linking it, because otherwise Gradle may fail to overwrite the desination the second time it tries to copy it
            // https://github.com/skiptools/skip/issues/296
            let shouldCopy = copyReadOnlyFiles && !fs.isDirectory(linkSource) && (perms != writablePermissions)

            removePath(linkSource) // remove any existing link in order to re-create it
            if shouldCopy {
                msg(.trace, "copying \(destPath) to \(linkSource)")
                try fs.copy(from: destPath, to: addOutputFile(linkSource))
                //try fs.chmod(.userWritable, path: destPath)
                try FileManager.default.setAttributes([.posixPermissions: writablePermissions], ofItemAtPath: linkSource.pathString)
            } else {
                msg(.trace, "linking \(destPath) to \(linkSource)")
                try fs.createSymbolicLink(addOutputFile(linkSource), pointingAt: destPath, relative: relative)
            }

            // set the output link mod time to match the source link mod time

            // this will try to set the mod time of the *destination* file, which is incorrect (and also not allowed, since the dest is likely outside of our sandboxed write folder list)
            //try FileManager.default.setAttributes([.modificationDate: modTime], ofItemAtPath: linkSource.pathString)

            // using setResourceValue instead does apply it to the link
            // https://stackoverflow.com/questions/10608724/set-modification-date-on-symbolic-link-in-cocoa
            try (linkSource.asURL as NSURL).setResourceValue(modTime, forKey: .contentModificationDateKey)
        }

        // the shared JSON encoder for serializing .skipcode.json codebase and .sourcehash marker contents
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, // needed for deterministic output
            .withoutEscapingSlashes,
            //.prettyPrinted, // compacting JSON significantly reduces the size of the codebase files
        ]

        let sourcehashOutputPath = try AbsolutePath(validating: transpileOptions.sourcehash)
        // We no longer remove the path because the plugin doesn't seem to require it to know to run in dependency order
        //removePath(sourcehashOutputPath) // delete the build completion marker to force its re-creation (removeFileTree doesn't throw when the file doesn't exist)

        // load and merge each of the skip.yml files for the dependent modules
        let (baseSkipConfig, mergedSkipConfig, configMap) = try loadSkipConfig(merge: true)

        let isNativeModule = baseSkipConfig.skip?.mode?.lowercased() == "native"

        // also add any files in the skipFolderFile to the list of sources (including the skip.yml and other metadata files)
        let skipFolderPathContents = try FileManager.default.enumeratedURLs(of: skipFolderPath.asURL)
            .filter({ (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true })

        // validate licenses in all the Skip source files, as well as any custom Kotlin files in the Skip folder
        let sourcehashes = try await createSourceHashes(validateLicense: ["swift", "kt", "java"], isNativeModule: isNativeModule, sourceURLs: sourceURLs + skipFolderPathContents)

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

        let codebaseInfo = try await loadCodebaseInfo() // initialize the codebaseinfo and load DependentModuleName.skipcode.json

        let autoBridge: AutoBridge = primaryModuleName == "SkipSwiftUI" ? .none : baseSkipConfig.skip?.isAutoBridgingEnabled() == true ? .public : .default
        let dynamicRoot = baseSkipConfig.skip?.dynamicroot

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
        //let resourcesOutputFolder = try AbsolutePath(outputFolderPath, validating: "resources") // traditional Java resources folder
        let resourcesOutputFolder = try AbsolutePath(outputFolderPath, validating: "assets") // Android AssetManager folder

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
            removePath(androidTestOutputFolder) // remove any existing link in order to re-create it
            try fs.createSymbolicLink(addOutputFile(androidTestOutputFolder), pointingAt: outputFolderPath, relative: true)
        }

        let packageName = KotlinTranslator.packageName(forModule: primaryModuleName)

        let transformers: [KotlinTransformer] = try createTransformers(for: baseSkipConfig, with: configMap)

        let overridden = try linkSkipFolder(skipFolderPath, to: kotlinOutputFolder, topLevel: true)
        let overriddenKotlinFiles = overridden.map({ $0.basename })

        // the contents of a folder named "buildSrc" are linked at the top level to contain scripts and plugins
        let buildSrcFolder = skipFolderPath.appending(component: buildSrcFolderName)
        if fs.isDirectory(buildSrcFolder) {
            try addLink(moduleBasePath.appending(component: buildSrcFolderName), pointingAt: buildSrcFolder, relative: false)
        }

        // feed the transpiler the files to transpile and any compiled files to potentially bridge
        var transpileFiles: [String] = []
        var swiftFiles: [String] = []
        for sourceFile in sourceURLs.map(\.path).sorted() {
            if isNativeModule {
                swiftFiles.append(sourceFile)
            } else {
                transpileFiles.append(sourceFile)
            }
        }
        let transpiler = Transpiler(packageName: packageName, transpileFiles: transpileFiles.map(Source.FilePath.init(path:)), bridgeFiles: swiftFiles.map(Source.FilePath.init(path:)), autoBridge: autoBridge, isBridgeGatherEnabled: dynamicRoot != nil, codebaseInfo: codebaseInfo, preprocessorSymbols: Set(inputOptions.symbols), transformers: transformers)

        try await transpiler.transpile(handler: handleTranspilation)
        try saveCodebaseInfo() // save out the ModuleName.skipcode.json
        try saveSkipBridgeCode()

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
            var dependentModuleExports: [CodebaseInfo.ModuleExport] = []

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

        func saveSkipBridgeCode() throws {
            // create the generated bridge files when the SKIP_BRIDGE environment is set and the plugin passed the --skip-bridge-output flag to the tool
            if let skipBridgeOutput = transpileOptions.skipBridgeOutput {
                let skipBridgeOutputFolder = try AbsolutePath(validating: skipBridgeOutput)

                let swiftBridgeFileNameTranspilationMap = skipBridgeTranspilations.reduce(into: Dictionary<String, Transpilation>()) { result, transpilation in
                    result[transpilation.output.file.name] = transpilation
                }

                for swiftSourceFile in sourceURLs.filter({ $0.pathExtension == "swift"}) {
                    let swiftFileBase = swiftSourceFile.deletingPathExtension().lastPathComponent
                    let swiftBridgeFileName = swiftFileBase.appending(Source.FilePath.bridgeFileSuffix)
                    let swiftBridgeOutputPath = skipBridgeOutputFolder.appending(components: [swiftBridgeFileName])

                    // FIXME: this doesn't handle the case where there are multiple files with the same name in a project (e.g., Folder1/Utils.swift and Folder2/Utils.swift). We would need to handle un-flattened project hierarchies to get past this
                    let bridgeContents: String
                    if let bridgeTranspilation = swiftBridgeFileNameTranspilationMap[swiftBridgeFileName] {
                        bridgeContents = bridgeTranspilation.output.content
                    } else {
                        bridgeContents = ""
                    }
                    try writeChanges(tag: "skipbridge", to: swiftBridgeOutputPath, contents: bridgeContents.utf8Data, readOnly: true)
                }

                // write support files
                for supportFileName in [KotlinDynamicObjectTransformer.supportFileName, KotlinBundleTransformer.supportFileName, KotlinUserDefaultsTransformer.supportFileName] {
                    let supportContents: String
                    if let supportTranspilation = swiftBridgeFileNameTranspilationMap[supportFileName] {
                        supportContents = supportTranspilation.output.content
                    } else {
                        supportContents = ""
                    }
                    let supportOutputPath = skipBridgeOutputFolder.appending(components: [supportFileName])
                    try writeChanges(tag: "skipbridge", to: supportOutputPath, contents: supportContents.utf8Data, readOnly: true)
                }

                return
            }

            // if the package is to be bridged, then create a src/main/swift folder that links to the source package
            guard isNativeModule || !skipBridgeTranspilations.isEmpty else {
                return
            }

            // Link src/main/swift/ to the absolute Swift project folder
            let swiftLinkFolder = try AbsolutePath(outputFolderPath, validating: "swift")
            try fs.createDirectory(swiftLinkFolder, recursive: true)

            // create Packages/swift-package-name links for all the project's package dependencies so we use the local versions in our swift build rather than downloading the remote dependencies
            // this will sync with Xcode's workspace, which will enable local package development of dependencies to work the same with this derived package as it does in Xcode
            let packagesLinkFolder = try AbsolutePath(swiftLinkFolder, validating: "Packages")
            try fs.createDirectory(packagesLinkFolder, recursive: true)

            // to use the package, we could do the equivalent of `swift package edit --path /path/to/local/package-id package-id,
            // but this would involve writing to the .build/workspace-state.json file with the "edited" property, which is
            // not a stable or well-documented format, and would require a lot of other metadata about the package;
            // so instead we tack on some code to the Package.swift file that we output
            //
            // We pass dependencies is inout to bypass Swift 6+ requiring that it be @MainActor.
            var packageAddendum = """

            /// Convert remote dependencies into their locally-cached versions.
            /// This allows us to re-use dependencies from the parent
            /// Xcode/SwiftPM process without redundently cloning them.
            func useLocalPackage(named packageName: String, id packageID: String, dependencies: inout [Package.Dependency]) {
                func localDependency(name: String?, location: String) -> Package.Dependency? {
                    if name == packageID || location.hasSuffix("/" + packageID) || location.hasSuffix("/" + packageID + ".git") {
                        return Package.Dependency.package(path: "Packages/" + packageID)
                    } else {
                        return nil
                    }
                }
                dependencies = dependencies.map { dep in
                    switch dep.kind {
                    case let .sourceControl(name: name, location: location, requirement: _):
                        return localDependency(name: name, location: location) ?? dep
                    case let .fileSystem(name: name, path: location):
                        return localDependency(name: name, location: location) ?? dep
                    default:
                        return dep
                    }
                }
            }
            
            """

            var createdIds: Set<String> = []

            let moduleLinkPaths = Dictionary(self.linkNamePaths, uniquingKeysWith: { $1 })

            for (targetName, packageName, var packagePath) in self.dependencyIdPaths {
                // the package name in the Package.swift typically the last part of the repository name (e.g., "swift-algorithms" in https://github.com/apple/swift-algorithms.git ), but for other packages it isn't (e.g., "Lottie" for https://github.com/airbnb/lottie-ios.git ); we need to use the repository name
                let packageID = packagePath.split(separator: "/").last?.description ?? packagePath

                if !createdIds.insert(packageID).inserted {
                    // only create the link once, even if specified multiple times
                    continue
                }

                // check whether the linked target is another linked Skip folder, and if so, check whether it has a derived src/main/swift folder (which indicates that it is a bridging package in which case we need the package to reference the *derived* sources rather than the *original* sources)
                if let relativeLinkPath = moduleLinkPaths[targetName] {
                    let linkModuleRoot = moduleRootPath
                        .parentDirectory
                        .appending(try RelativePath(validating: relativeLinkPath))
                    let linkModuleSrcMainSwift = linkModuleRoot.appending(components: "src", "main", "swift")
                    if fs.exists(linkModuleSrcMainSwift) {
                        info("override link path for \(targetName) from \(packagePath) to \(linkModuleSrcMainSwift.pathString)")
                        packagePath = linkModuleSrcMainSwift.pathString
                    }
                }

                let dependencyPackageLink = try AbsolutePath(packagesLinkFolder, validating: packageID)
                let destinationPath = try AbsolutePath(validating: packagePath)
                try addLink(dependencyPackageLink, pointingAt: destinationPath, relative: false)

                packageAddendum += """
                useLocalPackage(named: "\(packageName)", id: "\(packageID)", dependencies: &package.dependencies)
                
                """
            }

            // The source of the link tree needs to be the root project for the module in question, which we don't have access to (it can't be the `rootPath`, since that will be the topmost package that resulted in the transpiler invocation, which may not be the module in question).
            // So we need to guess from the projectFolderPath, which will be something like `/path/to/project-name/Sources/TargetName` by tacking `../..` to the end of the path.
            // WARNING: this is delicate, because there is nothing guaranteeing that the project follows the convention of `Sources/TargetName` for their modules!
            //let mirrorSource = rootPath
            let mirrorSource = projectFolderPath.appending(components: "..", "..")

            //warn("creating absolute merged link tree from: swiftLinkFolder=\(swiftLinkFolder) to mirrorSource=\(mirrorSource) (rootPath=\(rootPath)) with dependencyIdPaths=\(dependencyIdPaths)")
            try createMirroredLinkTree(swiftLinkFolder, pointingAt: mirrorSource, shallow: true, excluding: ["Packages", "Package.resolved", ".build", ".swiftpm", "skip-export", "build"]) { destPath, path in
                trace("createMirroredLinkTree for \(path.pathString)->\(destPath)")

                // manually add the packageAddendum the Package.swift
                if path.basename == "Package.swift" && !self.dependencyIdPaths.isEmpty {
                    let packageContents = try fs.readFileContents(path).withData { $0 + packageAddendum.utf8Data }
                    try writeChanges(tag: "skippackage", to: destPath, contents: packageContents, readOnly: true)
                    return false // override the linking of the file
                } else {
                    return true
                }
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

                var bridgedModules: [String] = []

                func addIncludeModule(_ moduleName: String) {
                    settingsContents += """
                    include(":\(moduleName)")

                    """

                    if configMap[moduleName]?.skip?.mode == "native" {
                        bridgedModules.append(moduleName)
                    }
                }

                // always add the primary module include
                if !sourceModules.contains(primaryModuleName) && !primaryModuleName.hasSuffix("Tests") {
                    addIncludeModule(primaryModuleName)
                }

                for sourceModule in sourceModules {
                    addIncludeModule(sourceModule)
                }

                if !bridgedModules.isEmpty {
                    settingsContents += """

                    gradle.extra["bridgeModules"] = listOf("\(bridgedModules.joined(separator: "\", \""))")

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

            // build up a merged YAML from the base dependencies to the current module
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
            // when we are running with SKIP_BRIDGE, don't link over any files from the skip folder
            // failure to do this will result in (harmless) .kt files being copied over, but since no subsequent transpilation
            // will mark those as expected output file, they will raise warnings: "removing stale output file: …"
            if transpileOptions.skipBridgeOutput != nil {
                return []
            }

            var copiedFiles: Set<AbsolutePath> = []
            for fileName in try fs.getDirectoryContents(path) {
                if fileName.hasPrefix(".") {
                    continue // skip hidden files
                }

                if path.basename == buildSrcFolderName || fileName == buildSrcFolderName {
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

            switch transpilation.outputType {
            case .bridgeToSwift, .bridgeFromSwift:
                skipBridgeTranspilations.append(transpilation)
                return
            case .default:
                break
            }

            // when we are running with SKIP_BRIDGE, we don't need to write out the Kotlin (which has already been generated in the first pass of the plugin)
            if transpileOptions.skipBridgeOutput != nil {
                //warn("suppressing transpiled Kotlin due to transpileOptions.skipBridgeOutput")
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
                    let destinationPath = (isAndroidRes ? resOutputFolder : resourcesBasePath).appending(resourceSourcePath)

                    // only create links for files that exist
                    if fs.isFile(sourcePath) {
                        info("\(destinationPath.relative(to: moduleBasePath).pathString) linking to \(sourcePath.pathString)", sourceFile: sourcePath.sourceFile)
                        try fs.createDirectory(destinationPath.parentDirectory, recursive: true)
                        try addLink(destinationPath, pointingAt: sourcePath, relative: false)
                    }
                }
            }

            func convertStrings(resourceSourceURL: URL, sourcePath: AbsolutePath) throws {
                // process the .xcstrings in the same way that Xcode does: parse the JSON and use the localizations keys to synthesize a LANG.lproj/TABLENAME.strings file
                let xcstrings = try JSONDecoder().decode(LocalizableStringsDictionary.self, from: Data(contentsOf: resourceSourceURL))
                let defaultLanguage = xcstrings.sourceLanguage
                let locales = Set(xcstrings.strings.values.compactMap(\.localizations?.keys).joined())
                for localeId in locales {
                    let lprojFolder = resourcesBasePath.appending(component: localeId + ".lproj")
                    let locBase = sourcePath.basenameWithoutExt

                    var locdict: [String: String] = [:]
                    var plurals: [String: [String : LocalizableStringsDictionary.StringUnit]] = [:]

                    for (key, value) in xcstrings.strings {
                        guard let localized = value.localizations?[localeId] else {
                            continue
                        }
                        if let value = localized.stringUnit?.value {
                            locdict[key] = value
                        }
                        if let pluralDict = localized.variations?.plural {
                            plurals[key] = pluralDict.mapValues(\.stringUnit)
                        }
                    }

                    if !locdict.isEmpty {
                        func escape(_ string: String) throws -> String? {
                            // escape quotes and newlines; we just use a JSON string fragment for this
                            try String(data: JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed, .withoutEscapingSlashes]), encoding: .utf8)
                        }

                        var stringsContent = ""
                        for (key, value) in locdict.sorted(by: { $0.key < $1.key }) {
                            if let keyString = try escape(key), let valueString = try escape(value) {
                                stringsContent += keyString + " = " + valueString + ";\n"
                            }
                        }
                        try fs.createDirectory(lprojFolder, recursive: true)
                        if localeId == defaultLanguage {
                            // when there is a default language, set up a symbolic link so Android localization can know where to fall back in the case of a missing localization key
                            try addLink(resourcesBasePath.appending(component: "base.lproj"), pointingAt: lprojFolder, relative: true)
                        }

                        let localizableStrings = try RelativePath(validating: locBase + ".strings") // e.g., fr.lproj/Localizable.strings
                        let localizableStringsPath = lprojFolder.appending(localizableStrings)
                        info("create \(localizableStrings.pathString) from \(sourcePath.pathString)", sourceFile: localizableStringsPath.sourceFile)
                        try writeChanges(tag: localizableStrings.pathString, to: localizableStringsPath, contents: stringsContent.utf8Data, readOnly: false)
                    }

                    if !plurals.isEmpty {
                        let localizableStringsDict = try RelativePath(validating: locBase + ".stringsdict") // e.g., fr.lproj/Localizable.stringsdict

                        var pluralDictNodes: [Universal.XMLNode] = []
                        for (key, value) in plurals.sorted(by: { $0.key < $1.key }) {
                            pluralDictNodes.append(Universal.XMLNode(elementName: "key", children: [.content(key)]))

                            var pluralsDict = Universal.XMLNode(elementName: "dict")
                            pluralsDict.addPlist(key: "NSStringLocalizedFormatKey", stringValue: "%#@value@")

                            pluralsDict.append(Universal.XMLNode(elementName: "key", children: [.content("value")]))
                            var pluralsSubDict = Universal.XMLNode(elementName: "dict")

                            pluralsSubDict.addPlist(key: "NSStringFormatSpecTypeKey", stringValue: "NSStringPluralRuleType")
                            pluralsSubDict.addPlist(key: "NSStringFormatValueTypeKey", stringValue: "lld")

                            for (pluralType, stringUnit) in value.sorted(by: { $0.key < $1.key }) {
                                // pluralType is zero, one, two, few, many, other
                                if let stringUnitValue = stringUnit.value {
                                    pluralsSubDict.addPlist(key: pluralType, stringValue: stringUnitValue)
                                }
                            }
                            pluralsDict.append(pluralsSubDict)
                            pluralDictNodes.append(pluralsDict)
                        }

                        let pluralDict = Universal.XMLNode(elementName: "dict", children: pluralDictNodes.map({ .element($0) }))

                        let stringsDictPlist = Universal.XMLNode(elementName: "plist", attributes: ["version": "1.0"], children: [.element(pluralDict)])
                        let stringsDictDocument = Universal.XMLNode(elementName: "", children: [.element(stringsDictPlist)])

                        let localizableStringsDictPath = lprojFolder.appending(localizableStringsDict)
                        info("create \(localizableStringsDict.pathString) from \(sourcePath.pathString)", sourceFile: localizableStringsDictPath.sourceFile)
                        try writeChanges(tag: localizableStringsDict.pathString, to: localizableStringsDictPath, contents: stringsDictDocument.xmlString().utf8Data, readOnly: false)
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
                try createMergedRelativeLinkTree(from: linkModulePath, to: relativeLinkPath, shallow: false)
                dependentModules.append(linkModuleName)
            }

            return dependentModules
        }

        /// Attempts to make a link from the `fromPath` to the given relative path.
        /// If `fromPath` already exists and is a directory, attempt to create links for each of the contents of the directory to the updated relative folder
        func createMergedRelativeLinkTree(from fromPath: AbsolutePath, to relative: String, shallow: Bool) throws {
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
                removePath(fromPath) // clear any pre-existing symlink
            }

            // the folder is a directory; recurse into the destination paths in order to link to the local paths
            if !shallow && fs.isDirectory(fromPath) {
                for fsEntry in try fs.getDirectoryContents(destPath) {
                    let fromSubPath = fromPath.appending(try RelativePath(validating: fsEntry))
                    // bump up all the relative links to account for the folder we just recursed into.
                    // e.g.: ../SomeSharedRoot/OtherModule/
                    // becomes: ../../SomeSharedRoot/OtherModule/someFolder/
                    try createMergedRelativeLinkTree(from: fromSubPath, to: "../" + relative + "/" + fsEntry, shallow: shallow)
                }
            } else {
                try addLink(fromPath, pointingAt: destPath, relative: true)
            }
        }

        /// Create a mirror hierarchy of the directory structure at `from` in the folder specified by `to`, and link each individual file in the hierarchy
        func createMirroredLinkTree(_ destPath: AbsolutePath, pointingAt fromPath: AbsolutePath, shallow: Bool, excluding excludePaths: Set<String> = [], contentHandler: ((_ destPath: AbsolutePath, _ fromPath: AbsolutePath) throws -> Bool)? = nil) throws {
            trace("creating absolute merged link tree from: \(fromPath) to: \(destPath)")
            // the folder is a directory; recurse into the destination paths in order to link to the local paths
            if fs.isDirectory(fromPath) {
                // we create output directories and link the contents, rather than just linking the folders themselves, since Gradle wants to be able to write to the output folders
                try fs.createDirectory(destPath, recursive: true)
                for fsEntry in try fs.getDirectoryContents(fromPath) {
                    if fsEntry.hasPrefix(".") || excludePaths.contains(fsEntry) {
                        continue
                    }
                    let rel = try RelativePath(validating: fsEntry)
                    let childDestPath = destPath.appending(rel)
                    let childFromPath = fromPath.appending(rel)
                    if shallow {
                        if try contentHandler?(childDestPath, childFromPath) != false {
                            try addLink(childDestPath, pointingAt: childFromPath, relative: false)
                        }
                    } else {
                        try createMirroredLinkTree(childDestPath, pointingAt: childFromPath, shallow: shallow, contentHandler: contentHandler)
                    }
                }
            } else if fs.isFile(fromPath) {
                // check whether the contentHandler want to override linking the file
                if try contentHandler?(destPath, fromPath) != false {
                    try addLink(destPath, pointingAt: fromPath, relative: false)
                } else {
                    warn("unknown file type encountered when creating links: \(fromPath)")
                }
            }
        }

        @discardableResult
        func removePath(_ path: AbsolutePath) -> Bool {
            do {
                if !fs.exists(path, followSymlink: false) {
                    return false
                }
                try fs.removeFileTree(path)
                return true
            } catch {
                warn("unable to remove entry \(path): \(error)", sourceFile: path.sourceFile)
                return false
            }
        }
    }

    /// Generate transpiler transformers from the given skip config
    func createTransformers(for config: SkipConfig, with moduleMap: [String: SkipConfig]) throws -> [KotlinTransformer] {
        var transformers: [KotlinTransformer] = builtinKotlinTransformers()

        let configOptions = config.skip?.bridgingOptions() ?? []
        let transformerOptions = KotlinBridgeOptions.parse(configOptions)
        transformers.append(KotlinBridgeTransformer(options: transformerOptions))

        if let root = config.skip?.dynamicroot {
            transformers.append(KotlinDynamicObjectTransformer(root: root))
        }

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

    @Option(name: [.long], help: ArgumentHelp("Folder for SkipBridge generated Swift files", valueName: "suffix"))
    var skipBridgeOutput: String? = nil
}


extension Universal.XMLNode {
    mutating func addPlist(key: String, stringValue: String) {
        append(Universal.XMLNode(elementName: "key", children: [.content(key)]))
        append(Universal.XMLNode(elementName: "string", children: [.content(stringValue)]))
    }
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

        /** e.g.:
         ```
         "variations" : {
           "plural" : {
             "one" : {
               "stringUnit" : {
                 "state" : "translated",
                 "value" : "%lld Goose"
               }
             },
             "other" : {
               "stringUnit" : {
                 "state" : "translated",
                 "value" : "%lld Geese"
               }
             }
           }
         }
         ```
         */
        let variations: Variations?

        struct Variations: Decodable {
            let plural: [String: VariationStringUnit]?

            struct VariationStringUnit : Decodable {
                let stringUnit: StringUnit
            }
        }
    }

    struct StringUnit: Decodable {
        let state: String? // e.g., "translated"
        let value: String?
    }
}
