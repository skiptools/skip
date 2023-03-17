import Foundation
import SkipSyntax
import SwiftParser
import SwiftSyntax
import ArgumentParser
import Universal
import TSCBasic
import TSCLibc
import OSLog

/// The current version of the tool
public let skipVersion = "0.1.2"

struct Options {
    var preprocessorSymbols: [String] = []
}


// MARK: Command Executor

public struct SkipCommandExecutor: AsyncParsableCommand {
    public static let experimental = false
    public static var configuration = CommandConfiguration(commandName: "skip",
                                                           abstract: "Skip: Swift Kotlin Interop \(skipVersion)",
                                                           shouldDisplay: !experimental,
                                                           subcommands: [
                                                            VersionCommand.self,
                                                            InfoCommand.self,
                                                            PrecheckAction.self,
                                                            TranspileAction.self,
                                                            GradleAction.self,
                                                            PrintSwiftASTAction.self,
                                                            PrintSkipASTAction.self,
                                                            //DoctorAction.self, // TODO: check installation status, like `brew doctor` and `flutter doctor`
                                                            //InitAction.self, // TODO: initialize module Kotlin source folders and update Package.swift with plug-in and additional Kotlin targets
                                                           ]
    )

    //@OptionGroup public var output: OutputOptions

    /// This is needed to handle execution of the tool from as a sandboxed command plugin
    @Option(name: [.long], help: ArgumentHelp("List of targets to apply", valueName: "target"))
    public var target: Array<String> = []

    public init() {
    }

    /// Run the transpiler on the given arguments.
    public static func run(_ arguments: [String], basePath: AbsolutePath = localFileSystem.currentWorkingDirectory!, out: WritableByteStream? = nil, err: WritableByteStream? = nil) async throws {
        var cmd: ParsableCommand = try parseAsRoot(arguments)
        if var cmd = cmd as? any StreamingCommand {
            if let outputFile = cmd.outputOptions.output {
                let path = try AbsolutePath(validating: outputFile, relativeTo: basePath)
                cmd.outputOptions.streams.out = try LocalFileOutputByteStream(path)
            } else if let out = out {
                cmd.outputOptions.streams.out = out
            }
            if let err = err {
                cmd.outputOptions.streams.err = err
            }
            try await cmd.run()
        } else if var cmd = cmd as? AsyncParsableCommand {
            try await cmd.run()
        } else {
            try cmd.run()
        }
    }
}


struct OutputOptions: ParsableArguments {
    @Option(name: [.customShort("o"), .long], help: ArgumentHelp("Send output to the given file (stdout: -)", valueName: "path"))
    var output: String?

    @Flag(name: [.customShort("E"), .long], help: ArgumentHelp("Emit messages to the output rather than stderr"))
    var messageErrout: Bool = false

    @Flag(name: [.customShort("v"), .long], help: ArgumentHelp("Whether to display verbose messages"))
    var verbose: Bool = false

    @Flag(name: [.customShort("q"), .long], help: ArgumentHelp("Quiet mode: suppress output"))
    var quiet: Bool = false

    @Flag(name: [.customShort("J"), .long], help: ArgumentHelp("Emit output as formatted JSON"))
    var json: Bool = false

    @Flag(name: [.customShort("j"), .long], help: ArgumentHelp("Emit output as compact JSON"))
    var jsonCompact: Bool = false

    @Flag(name: [.customShort("M"), .long], help: ArgumentHelp("Emit messages as plain text rather than JSON"))
    var messagePlain: Bool = false

    @Flag(name: [.customShort("A"), .long], help: ArgumentHelp("Wrap and delimit JSON output as an array"))
    var jsonArray: Bool = false

    /// A transient handler for tool output; this acts as a temporary holder of output streams
    internal var streams: OutputHandler = OutputHandler()

    internal final class OutputHandler : Decodable {
        var out: WritableByteStream = stdoutStream
        var err: WritableByteStream = stderrStream
        var file: LocalFileOutputByteStream? = nil

        func fileStream(for outputPath: String?) -> LocalFileOutputByteStream? {
            guard let outputPath else { return nil }
            if let file = file { return file }
            do {
                let path = try AbsolutePath(validating: outputPath)
                self.file = try LocalFileOutputByteStream(path)
                return self.file
            } catch {
                // should we re-throw? that would make any logging message become throwable
                return nil
            }
        }

        /// The closure that will output a message to standard out
        func write(error: Bool, output: String?, _ message: String, terminator: String = "\n") {
            let stream = (error ? err : fileStream(for: output) ?? out)
            stream.write(message + terminator)
            if !terminator.isEmpty { stream.flush() }
        }

        /// The closure that will handle converting and writing the output type to stream
        fileprivate var yield: (Either<MessageConvertible>.Or<Message>) -> () = { _ in }

        init() {
        }

        /// Not really decodable
        convenience init(from decoder: Decoder) throws {
            self.init()
        }
    }

    /// Write the given message to the output streams buffer
    func write(_ value: String) {
        streams.write(error: false, output: output, value)
    }

    /// The output that comes at the beginning of a sequence of elements; an opening bracket, for JSON arrays
    func beginCommandOutput() {
        if jsonArray { write("[") }
    }

    /// The output that comes at the end of a sequence of elements; a closing bracket, for JSON arrays
    func endCommandOutput() {
        if jsonArray { write("]") }
    }

    /// The output that separates elements; a comma, for JSON arrays
    func writeOutputSeparator() {
        if jsonArray { write(",") }
    }

    /// Whether tool output should be emitted as JSON or not
    var emitJSON: Bool { json || jsonCompact }

    func writeOutput<T: MessageConvertible>(_ item: T, error: Bool) throws {
        if emitJSON {
            try streams.write(error: false, output: output, item.toJSON(outputFormatting: [.sortedKeys, .withoutEscapingSlashes, (jsonCompact ? .sortedKeys : .prettyPrinted)], dateEncodingStrategy: .iso8601).utf8String ?? "")
        } else {
            streams.write(error: messageErrout == true ? false : error, output: output, item.description)
        }
    }
}


// MARK: VersionCommand

struct VersionCommand: SingleStreamingCommand {
    static let experimental = false
    struct Output : MessageConvertible {
        var version: String = skipVersion
        #if DEBUG
        let debug: Bool = true
        var description: String { "skip version \(skipVersion) (debug)" }
        #else
        let debug: Bool? = nil
        var description: String { "skip version \(skipVersion)" }
        #endif
    }

    static var configuration = CommandConfiguration(commandName: "version",
                                                           abstract: "Print the Skip version",
                                                           shouldDisplay: !experimental)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    func executeCommand() async throws -> Output {
        return Output()
    }
}

// MARK: InfoCommand

extension FileManager {
    #if os(iOS)
    var homeDirectoryForCurrentUser: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }
    #endif
}

struct InfoCommand: SingleStreamingCommand {
    static let experimental = false
    struct Output : MessageConvertible {
        var version: String = skipVersion
        var hostName = pinfo.hostName
        var arguments = pinfo.arguments
        var operatingSystemVersion = pinfo.operatingSystemVersionString
        var workingDirectory = fm.currentDirectoryPath
        let cwdWritable = fm.isWritableFile(atPath: fm.currentDirectoryPath)
        let cwdReadable = fm.isReadableFile(atPath: fm.currentDirectoryPath)
        let cwdExecutable = fm.isExecutableFile(atPath: fm.currentDirectoryPath)
        var home = fm.homeDirectoryForCurrentUser
        let homeWritable = fm.isWritableFile(atPath: fm.homeDirectoryForCurrentUser.path)
        let homeReadable = fm.isReadableFile(atPath: fm.homeDirectoryForCurrentUser.path)
        let homeExecutable = fm.isExecutableFile(atPath: fm.homeDirectoryForCurrentUser.path)
        let skipLocal = pinfo.environment["SKIPLOCAL"]
        //var environment = pinfo.environment // potentially private information

        private static var fm: FileManager { .default }
        private static var pinfo: ProcessInfo { .processInfo }

        #if DEBUG
        var debug = true
        #else
        var debug = false
        #endif

        var description: String {
            """
            skip: \(version)
            debug: \(debug)
            os: \(operatingSystemVersion)
            cwd: \(workingDirectory) (\(cwdReadable ? "r" : "")\(cwdWritable ? "w" : "")\(cwdExecutable ? "x" : ""))
            home: \(home) (\(homeReadable ? "r" : "")\(homeWritable ? "w" : "")\(homeExecutable ? "x" : ""))
            args: \(arguments)
            SKIPLOCAL: \(skipLocal ?? "no")
            """
            // env: \(environment)
        }
    }

    static var configuration = CommandConfiguration(commandName: "info",
                                                           abstract: "Print system information",
                                                           shouldDisplay: !experimental)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    // alternative way of setting output
    //@OptionGroup var parentOptions: SkipCommandExecutor
    //var output: OutputOptions {
    //    get { parentOptions.output }
    //    set { parentOptions.output = newValue }
    //}

    func executeCommand() async throws -> Output {
        trace("trace message")
        info("info message")
        return Output()
    }
}


// MARK: Command Phases

protocol SkipPhase : AsyncParsableCommand {
    var outputOptions: OutputOptions { get }
}


/// The condition under which the phase should be run
enum PhaseGuard : String, Decodable, CaseIterable {
    case no
    case force
    case onDemand = "on-demand"
}

extension PhaseGuard : ExpressibleByArgument {
}

// MARK: CheckPhase

protocol CheckPhase : SkipPhase {
    var precheckOptions: CheckPhaseOptions { get }
}

struct CheckPhaseOptions: ParsableArguments {
    @Option(help: ArgumentHelp("Condition for check phase", valueName: "force/no"))
    var check: PhaseGuard = .onDemand

    @Option(name: [.customShort("S")], help: ArgumentHelp("Preprocessor symbols", valueName: "file"))
    var symbols: [String] = []

    @Option(name: [.customShort("O")], help: ArgumentHelp("Output directory", valueName: "dir"))
    var directory: String? = nil

    @Argument(help: ArgumentHelp("List of files to process"))
    var files: [String]
}

extension CheckPhase {
    func performPrecheckActions() async throws -> CheckResult {
        return CheckResult()
    }
}

struct CheckResult {

}

struct PrecheckAction: AsyncParsableCommand, CheckPhase {
    static var configuration = CommandConfiguration(commandName: "precheck", abstract: "Perform transpilation prechecks")

    @OptionGroup(title: "Check Options")
    var precheckOptions: CheckPhaseOptions

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    func run() async throws {
        try await perform(on: precheckOptions.files.map({ Source.File(path: $0) }), options: precheckOptions)
    }

    func perform(on sourceFiles: [Source.File], options: CheckPhaseOptions) async throws {
        for sourceFile in sourceFiles {
            let source = try Source(file: sourceFile)
            let syntaxTree = SyntaxTree(source: source, preprocessorSymbols: Set(options.symbols))
            let translator = KotlinTranslator(syntaxTree: syntaxTree)
            let kotlinTree = translator.translateSyntaxTree()
            kotlinTree.messages.forEach { print($0) }

            if let outputDir = options.directory {
                let outputFileURL = outputFileURL(for: sourceFile, in: URL(fileURLWithPath: outputDir))
                try "".write(to: outputFileURL, atomically: false, encoding: .utf8)
            }
        }
    }

    /// Xcode requires that we create an output file in order for incremental build tools to work.
    ///
    /// - Warning: This is duplicated in SkipCheckBuildPlugin.
    func outputFileURL(for sourceFile: Source.File, in outputDir: URL) -> URL {
        var outputFileName = sourceFile.name
        if outputFileName.hasSuffix(".swift") {
            outputFileName = String(outputFileName.dropLast(".swift".count))
        }
        outputFileName += "_skipcheck.swift"
        return outputDir.appendingPathComponent(outputFileName)
    }
}


// MARK: TranspilePhase

protocol TranspilePhase: CheckPhase {
    var transpileOptions: TranspilePhaseOptions { get }
}

struct TranspilePhaseOptions: ParsableArguments {
    @Option(help: ArgumentHelp("Condition for transpile phase", valueName: "force/no"))
    var transpile: PhaseGuard = .onDemand // --transpile

    @Option(name: [.customLong("module")], help: ArgumentHelp("ModuleName:SourcePath", valueName: "module"))
    var moduleNames: [String] = [] // --module

    @Option(name: [.customLong("link")], help: ArgumentHelp("ModuleName:LinkPath", valueName: "module"))
    var linkPaths: [String] = [] // --link

    @Option(help: ArgumentHelp("Path to the folder containing symbols.json", valueName: "path"))
    var symbolFolder: String? = nil // --symbol-folder

    @Option(help: ArgumentHelp("Path to the folder that contains skip.yml and overrides", valueName: "path"))
    var skipFolder: String? = nil // --skip-folder

    @Option(help: ArgumentHelp("Path to the output module root folder", valueName: "path"))
    var moduleRoot: String? = nil // --module-root

    @Option(name: [.customShort("D", allowingJoined: true)], help: ArgumentHelp("Set preprocessor variable for transpilation", valueName: "value"))
    var preprocessorVariables: [String] = []

    @Option(name: [.long], help: ArgumentHelp("Output directory", valueName: "dir"))
    var outputFolder: String? = nil

}

struct TranspileResult {

}

extension TranspilePhase {
    func performTranspileActions() async throws -> (check: CheckResult, transpile: TranspileResult) {
        let checkResult = try await performPrecheckActions()
        let transpileResult = TranspileResult()
        return (checkResult, transpileResult)
    }
}

struct TranspileAction: TranspilePhase, StreamingCommand {
    static var configuration = CommandConfiguration(commandName: "transpile", abstract: "Transpile Swift to Kotlin")

    @OptionGroup(title: "Check Options")
    var precheckOptions: CheckPhaseOptions

    @OptionGroup(title: "Transpile Options")
    var transpileOptions: TranspilePhaseOptions

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions


    struct Output : MessageConvertible {
        let transpilation: Transpilation

        var description: String {
            "transpilation successful: \(transpilation.messages.count > 0 ? transpilation.messages.count.description : "no") messages" // transpilation.sourceFile.url.lastPathComponent
        }
    }

    static func byteCount(for size: Int) -> String {
        ByteCountFormatter.string(fromByteCount: .init(size), countStyle: .file)
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
        let sourceFiles = try precheckOptions.files.map(AbsolutePath.init(validating:))
        info("performing transpilation to: \(transpileOptions.outputFolder ?? "nowhere") for: \(sourceFiles.map(\.pathString))")
        info("linkPaths: \(transpileOptions.linkPaths)")
        info("moduleNames: \(transpileOptions.moduleNames)")
        info("skipFolder: \(transpileOptions.skipFolder ?? "none")")
        try await self.transpile(fs: localFileSystem, sourceFiles: Set(sourceFiles), with: continuation)
    }

    private func transpile(fs: FileSystem, sourceFiles: Set<AbsolutePath>, with continuation: AsyncThrowingStream<OutputMessage, Error>.Continuation) async throws {
        // the path that will contain the `skip.yml`
        guard let skipFolder = transpileOptions.skipFolder else {
            throw ValidationError("Must specify --skip-folder")
        }

        let skipFolderPath = try AbsolutePath(validating: skipFolder, relativeTo: fs.currentWorkingDirectory ?? fs.tempDirectory)
        if !fs.isDirectory(skipFolderPath) {
            throw ValidationError("Folder specified by --skip-folder did not exist: \(skipFolderPath)")
        }

        guard let outputFolder = transpileOptions.outputFolder else {
            throw ValidationError("Must specify --output-folder")
        }

        let outputFolderPath = try AbsolutePath(validating: outputFolder, relativeTo: fs.currentWorkingDirectory ?? fs.tempDirectory)
        if !fs.isDirectory(outputFolderPath) {
            // e.g.: ~Library/Developer/Xcode/DerivedData/PACKAGE-ID/SourcePackages/plugins/skip-core.output/SkipFoundationKotlinTests/SkipTranspilePlugIn/SkipFoundation/src/test/kotlin
            //throw ValidationError("Folder specified by --output-folder did not exist: \(outputFolder)")
            try fs.createDirectory(outputFolderPath, recursive: true)
        }

        guard let moduleRoot = transpileOptions.moduleRoot else {
            throw ValidationError("Must specify --module-root")
        }
        let moduleRootPath = try AbsolutePath(validating: moduleRoot)
        if !fs.isDirectory(moduleRootPath) {
            throw ValidationError("Module root path did not exist at: \(moduleRootPath.pathString)")
        }

        let allModuleNames = moduleNamePaths.map(\.module)

        guard let (primaryModuleName, primaryModulePath) = moduleNamePaths.first else {
            throw ValidationError("Must specify at least one --module")
        }

        let packageName = KotlinTranslator.packageName(forModule: primaryModuleName)

        let skipConfig: YAML = try loadSkipConfig() // TODO: use the config for generating the build.gradle.kts
        #if os(macOS) || os(Linux)
        let symbols: Symbols? = try await loadSymbols()
        #else
        let symbols: Symbols? = nil
        #endif
        let overridden = try copyKotlinOverrides()
        let overriddenSwiftFileNames = overridden.map({ $0.basenameWithoutExt + ".swift" })

        // skip over any source file whose name would match a copied Kotlin file
        let sources = sourceFiles.map(\.sourceFile).filter { sourceFile in
            if overriddenSwiftFileNames.contains(sourceFile.name) {
                info("skipping transpilation of overridden file \(sourceFile.path)", sourceFile: sourceFile)
                return false
            } else {
                return true
            }
        }
        let transpiler = Transpiler(sourceFiles: sources, packageName: packageName, symbols: symbols, preprocessorSymbols: Set(precheckOptions.symbols))
        try await transpiler.transpile(handler: handleTranspilation)
        let sourceModules = try linkDependentModuleSources()
        try generateGradle(for: sourceModules, with: skipConfig)

        return // everything following is a stage of the transpilation process


        func generateGradle(for sourceModules: [String], with skipConfig: YAML) throws {
            try generateSettingsGradle()
            try generatePerModuleGradle()

            func generateSettingsGradle() throws {
                let settingsPath = moduleRootPath.parentDirectory.appending(component: "settings.gradle.kts")

                //let gradle = GradleProject()
                //let settingsContents = gradle.generate()

                var settingsContents = """
                rootProject.name = "\(primaryModuleName)"


                """
                for sourceModule in sourceModules {
                    settingsContents += """
                    include("\(sourceModule)")

                    """
                }

                info("saving \(settingsPath)", sourceFile: settingsPath.sourceFile)
                try fs.writeChanges(path: settingsPath, makeWritable: true, makeReadOnly: true, bytes: ByteString(encodingAsUTF8: settingsContents))
            }

            func generatePerModuleGradle(exportAPI: Bool = true) throws {
                let buildGradle = moduleRootPath.appending(components: ["build.gradle.kts"])

                var buildContents = """
                plugins {
                    kotlin("jvm") version "1.8.10"
                }

                repositories {
                    mavenCentral()
                }

                dependencies {
                    api("org.jetbrains.kotlin:kotlin-test-junit5")
                    implementation("org.junit.jupiter:junit-jupiter-engine:5.9.1")

                    testImplementation("org.jetbrains.kotlin:kotlin-test-junit5")
                    testImplementation("org.junit.jupiter:junit-jupiter-engine:5.9.1")
                
                    //api("org.apache.commons:commons-math3:3.6.1")
                    //implementation("com.google.guava:guava:31.1-jre")

                """


                for sourceModule in sourceModules {
                    // don't add a dependency to ourselves
                    if primaryModuleName == sourceModule || primaryModuleName == sourceModule + "Tests" {
                        continue
                    }

                    // - api: “dependencies appearing in the api configurations will be transitively exposed to consumers of the library, and as such will appear on the compile classpath of consumers. Dependencies found in the implementation configuration will, on the other hand, not be exposed to consumers, and therefore not leak into the consumers' compile classpath.”
                    let dependencyType = exportAPI ? "api" : "implementation"
                    buildContents += """
                        \(dependencyType)(project(":\(sourceModule)"))

                    """
                }

                buildContents += """

                }

                tasks.named<Test>("test") {
                    useJUnitPlatform()
                }

                """

                info("saving \(buildGradle)", sourceFile: buildGradle.sourceFile)
                try fs.writeChanges(path: buildGradle, makeWritable: true, makeReadOnly: true, bytes: ByteString(encodingAsUTF8: buildContents))
            }
        }

        func loadSkipConfig() throws -> YAML {
            let skipConfigPath = skipFolderPath.appending(component: "skip.yml")
            do {
                let skipConfig = try fs.readFileContents(skipConfigPath).withData(YAML.parse(_:))
                try info("starting transpilation with config \(skipConfigPath): \(skipConfig.prettyJSON)")
                return skipConfig
            } catch {
                throw ValidationError("The skip.yml file in the --skip-folder path \(skipConfigPath) could not be loaded: \(error)")
            }
        }

        func kotlinOutputPath(for baseSourceFileName: String) -> AbsolutePath {
            let packagePath = RelativePath((packageName as NSString).replacingOccurrences(of: ".", with: "/"))
            let outputFolderPackagePath = outputFolderPath.appending(packagePath)
            let kotlinFilePath = RelativePath(baseSourceFileName)
            let outputFilePath = outputFolderPackagePath.appending(kotlinFilePath)
            return outputFilePath
        }

        /// Copies over the overridden .kt files from `ModuleNameKotlin/skip/*.kt` into the destination folder
        ///
        /// Any Kotlin files that are overridden will not be transpiled.
        func copyKotlinOverrides() throws -> Set<AbsolutePath> {
            var copiedFiles: Set<AbsolutePath> = []
            for file in try fs.getDirectoryContents(skipFolderPath) {
                if file.hasSuffix(".kt") {
                    let sourcePath = AbsolutePath(skipFolderPath, file)
                    info("copying overridden source: \(file)", sourceFile: sourcePath.sourceFile)
                    let outputFilePath = kotlinOutputPath(for: file)
                    try fs.writeChanges(path: outputFilePath, checkSize: true, bytes: fs.readFileContents(sourcePath))
                    copiedFiles.insert(outputFilePath)
                }
            }
            return copiedFiles
        }

        #if os(macOS) || os(Linux)
        func loadSymbols() async throws -> Symbols {
            let symbolFolder = transpileOptions.symbolFolder.flatMap(URL.init(fileURLWithPath:))
            //let symbolFolderPath = try transpileOptions.symbolFolder.flatMap(AbsolutePath.init(validating:))

            let symbolStart = Date.now.timeIntervalSinceReferenceDate
            let symbolsGraph = try await SkipSystem.extractSymbolGraph(moduleFolder: symbolFolder, moduleNames: allModuleNames, from: URL.moduleBuildFolder())
            let symbolEnd = Date.now.timeIntervalSinceReferenceDate
            info("extract symbols: \(symbolsGraph.unifiedGraphs.keys.sorted()) (\(Int64((symbolEnd - symbolStart) * 1000)) ms)")

            let loadSymbols = Symbols(moduleName: primaryModuleName, graphs: symbolsGraph.unifiedGraphs)
            return loadSymbols
        }
        #endif

        func handleTranspilation(transpilation: Transpilation) throws {
            for message in transpilation.messages {
                continuation.yield(.init(message))
            }
            trace(transpilation.output.content)

            let sourcePath = try AbsolutePath(validating: transpilation.sourceFile.path)
            let sourceSize = try fs.getFileInfo(sourcePath).size

            info("transpiling \(sourcePath.basename) (\(Self.byteCount(for: .init(sourceSize))))", sourceFile: transpilation.sourceFile)

            let outputFile = try saveTranspilation()

            info("transpiled \(transpilation.sourceFile.name) (\(Self.byteCount(for: .init(sourceSize)))) to \(outputFile.basename) (\(Self.byteCount(for: transpilation.output.content.utf8.count))) (\(Int64(transpilation.duration * 1000)) ms)", sourceFile: Source.File(path: outputFile))

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


            func saveTranspilation() throws -> AbsolutePath {
                // the build plug-in's output folder base will be something like ~/Library/Developer/Xcode/DerivedData/Mod-ID/SourcePackages/plugins/module-name.output/ModuleNameKotlin/SkipTranspilePlugIn/ModuleName/src/test/kotlin
                trace("path: \(outputFolderPath)")
                let kotlinName = transpilation.kotlinFileName
                let outputFilePath = kotlinOutputPath(for: kotlinName)

                let kotlinBytes = ByteString(encodingAsUTF8: transpilation.output.content)
                let fileWritten = try fs.writeChanges(path: outputFilePath, checkSize: true, makeWritable: true, makeReadOnly: true, bytes: kotlinBytes)

                info("wrote to: \(outputFilePath)\(fileWritten ? " (unchanged)" : "")", sourceFile: outputFilePath.sourceFile)
                return outputFilePath
            }

        }


        // NOTE: when linking between modules, note that SPM and Xcode use different output paths:
        // Xcode: ~/Library/Developer/Xcode/DerivedData/PROJECT-ID/SourcePackages/plugins/skip-core.output/SkipFoundationKotlinTests/SkipTranspilePlugIn/SkipFoundation
        // SPM: .build/plugins/outputs/skip-core/
        func linkDependentModuleSources() throws -> [String] {
            var dependentModules: [String] = []
            // transpilation was successful; now set up links to the other output packages (located in different plug-in folders)
            let moduleBasePath = moduleRootPath.parentDirectory

            /// Attempts to make a link from the `fromPath` to the given relative path.
            /// If `fromPath` already exists and is a directory, attempt to create links for each of the contents of the directory to the updated relative folder
            func createMergedLinkTree(from fromPath: AbsolutePath, to relative: String) throws {
                let destPath = try AbsolutePath(validating: relative, relativeTo: fromPath)
                if !fs.isDirectory(destPath) {
                    // skip over anything that is not a destination folder
                    return
                }
                info("creating merged link tree from: \(fromPath) to: \(relative)")
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
                        let toRelativePath = "../" + relative + "/" + fsEntry
                        try createMergedLinkTree(from: fromSubPath, to: toRelativePath)
                    }
                } else {
                    try fs.createSymbolicLink(fromPath, pointingAt: destPath, relative: true)
                }
            }

            // for each of the specified link/path pairs, create symbol links, either to the base folders, or the the sub-folders that share a common root
            // this is the logic that allows us to merge two modules (like MyMod and MyModTests) into a single Kotlin module with the idiomatic src/main/kotlin/ and src/test/kotlin/ pair of folders
            for (linkModuleName, relativeLinkPath) in linkNamePaths {
                let linkModulePath = moduleBasePath.appending(RelativePath(linkModuleName))
                info("relativeLinkPath: \(relativeLinkPath) moduleBasePath: \(moduleBasePath) linkModuleName: \(linkModuleName) -> linkModulePath: \(linkModulePath)")
                try createMergedLinkTree(from: linkModulePath, to: relativeLinkPath)
                dependentModules.append(linkModuleName)
            }

            return dependentModules
        }
    }
}


extension Source.File {
    /// Initialize this file reference with an `AbsolutePath`
    init(path absolutePath: AbsolutePath) {
        self.init(path: absolutePath.pathString)
    }
}

extension Transpilation {
    /// The base name for the transpilation's input source file
    var outputFileBaseName: String {
        sourceFile.name.hasSuffix(".swift") ? sourceFile.name.dropLast(".swift".count).description : sourceFile.name
    }

    /// Returns the expected Kotlin file name for this transpilation
    var kotlinFileName: String {
        outputFileBaseName + ".kt"
    }
}

extension AbsolutePath {
    /// Converts this FileSystem `AbsolutePath` into a `Source.File` that the transpiler can use.
    var sourceFile: Source.File {
        Source.FilePath(path: pathString)
    }
}

extension FileSystem {

    /// A version of `FileSystem.writeIfChanged` that allows control over permissions and size check optimizations.
    @discardableResult func writeChanges(path: AbsolutePath, checkSize: Bool = true, makeWritable: Bool = true, makeReadOnly: Bool = false, bytes: ByteString) throws -> Bool {
        if !isFile(path) {
            return try save()
        }

        // make sure we can overwrite the file (usually clearing the read-only bit we set after writing the file)
        if makeWritable && !isWritable(path) {
            try chmod(.userWritable, path: path)
        }

        let info = try getFileInfo(path)
        let size = info.size
        if size != bytes.count {
            // different size; they must be different
            return try save()
        }

        // compare for changes
        let changed = try bytes.withData { data1 in
            try readFileContents(path).withData { data2 in
                data1 != data2
            }
        }

        if changed {
            return try save()
        } else {
            return false // file was unchanged
        }

        func save() throws -> Bool {
            try createDirectory(path.parentDirectory, recursive: true)
            try writeFileContents(path, bytes: bytes)
            if makeReadOnly == true {
                // remove write access
                try chmod(.userUnWritable, path: path)
            }
            return true
        }

    }
}
// MARK: GradlePhase

protocol GradlePhase: TranspilePhase {
    var gradleOptions: GradlePhaseOptions { get }
}

struct GradlePhaseOptions: ParsableArguments {
//    @Option(help: ArgumentHelp("Condition for gradle phase", valueName: "force/no"))
//    var gradle: PhaseGuard = .onDemand

    @Option(help: ArgumentHelp("Path to Android Studio.app", valueName: "folder"))
    var studioHome: String? = nil

}

struct GradleResult {

}

extension GradlePhase {
    func performGradleActions() async throws -> (check: CheckResult, transpile: TranspileResult, gradle: GradleResult) {
        let transpileResult = try await performTranspileActions()
        let gradleResult = GradleResult()
        return (check: transpileResult.check, transpile: transpileResult.transpile, gradle: gradleResult)
    }
}


struct GradleAction: GradlePhase {
    static var configuration = CommandConfiguration(commandName: "gradle", abstract: "Gradle build system interface")

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Precheck Options")
    var precheckOptions: CheckPhaseOptions

    @OptionGroup(title: "Transpile Options")
    var transpileOptions: TranspilePhaseOptions

    @OptionGroup(title: "Gradle Options")
    var gradleOptions: GradlePhaseOptions

    func run() async throws {
        throw ValidationError("Not yet supported")
    }
}


// MARK: AST Actions


struct PrintSwiftASTAction: AsyncParsableCommand {
    static var configuration = CommandConfiguration(commandName: "ast-swift", abstract: "Print the Swift AST")

    @Option(name: [.customShort("S")], help: ArgumentHelp("Preprocessor symbols", valueName: "file"))
    var symbols: [String] = []

    @Option(name: [.customShort("O")], help: ArgumentHelp("Output directory", valueName: "dir"))
    var directory: String? = nil

    @Argument(help: ArgumentHelp("List of files to process"))
    var files: [String]

    func run() async throws {
        var opts = CheckPhaseOptions()
        opts.directory = directory
        opts.symbols = symbols
        try await perform(on: files.map({ Source.File(path: $0) }), options: opts)
    }

    func perform(on sourceFiles: [Source.File], options: CheckPhaseOptions) async throws {
        for sourceFile in sourceFiles {
            let syntax = try Parser.parse(source: Source(file: sourceFile).content)
            print(syntax.root.prettyPrintTree)
        }
    }
}

struct PrintSkipASTAction: AsyncParsableCommand {
    static var configuration = CommandConfiguration(commandName: "ast-skip", abstract: "Print the Skip AST")

    @Option(name: [.customShort("S")], help: ArgumentHelp("Preprocessor symbols", valueName: "file"))
    var symbols: [String] = []

    @Argument(help: ArgumentHelp("List of files to process"))
    var files: [String]

    func run() async throws {
        var opts = CheckPhaseOptions()
        opts.symbols = symbols
        try await perform(on: files.map({ Source.File(path: $0) }), options: opts)
    }

    func perform(on sourceFiles: [Source.File], options: CheckPhaseOptions) async throws {
        for sourceFile in sourceFiles {
            let source = try Source(file: sourceFile)
            let syntaxTree = SyntaxTree(source: source, preprocessorSymbols: Set(options.symbols))
            print(syntaxTree.prettyPrintTree)
        }
    }
}


// MARK: Utilities


/// A command that forwards itself to another command. Used for aliasing commands.
struct ForwardingCommand<Base: ParsableCommand, Name: RawRepresentable & CaseIterable>: ParsableCommand where Name.RawValue : StringProtocol {
    static var configuration: CommandConfiguration {
        var cfg = Base.configuration
        cfg.commandName = Name.allCases.first?.rawValue.description
        cfg.shouldDisplay = false
        return cfg
    }

    @OptionGroup
    var command: Base

    mutating func run() throws {
        try command.run()
    }
}

//enum SkippyCommandName : String, CaseIterable { case skippy }
//typealias SkippyAction = ForwardingCommand<PrecheckAction, SkippyCommandName>


// MARK: Streaming command support


extension MessageConvertible {
    //var attributedString: String { description }
}

extension Never: MessageConvertible {
    public var description: String { "never" }
}

extension Message: MessageConvertible {
}

/// A command that contains options for how messages will be conveyed to the user
protocol StreamingCommand: AsyncParsableCommand {
    /// The structured output of this tool
    associatedtype Output : MessageConvertible
    typealias OutputMessage = Either<Output>.Or<Message>

    var outputOptions: OutputOptions { get set }

    func performCommand(with continuation: AsyncThrowingStream<OutputMessage, Error>.Continuation) async throws
}

extension StreamingCommand {
    func writeOutput(message: OutputMessage) throws {
        switch message {
        case .a(let a): try outputOptions.writeOutput(a as Output, error: false)
        case .b(let b): try outputOptions.writeOutput(b as Message, error: true)
        }
    }

    mutating func run() async throws {
        outputOptions.beginCommandOutput()
        var elements = self.startCommand().makeAsyncIterator()
        if let first = try await elements.next() {
            try writeOutput(message: first)
            while let element = try await elements.next() {
                outputOptions.writeOutputSeparator()
                try writeOutput(message: element)
            }
        }
        outputOptions.endCommandOutput()
    }
}

extension StreamingCommand {

    mutating func startCommand() -> AsyncThrowingStream<OutputMessage, Error> {
        AsyncThrowingStream { (continuation: AsyncThrowingStream.Continuation) in
            self.outputOptions.streams.yield = {
                switch $0 {
                case .a(let a): continuation.yield(.init(a as! Output))
                case .b(let b): continuation.yield(.init(b))
                }

            }
            // defer { self.output.streams.yield = { _ in } } // clears output
            doCommand(continuation: continuation)
        }
    }

    func doCommand(continuation: AsyncThrowingStream<OutputMessage, Error>.Continuation) {
        Task {
            do {
                try await performCommand(with: continuation)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

extension StreamingCommand {
    func warnExperimental(_ experimental: Bool) {
        if experimental {
            msg(.warning, "the \(Self.configuration.commandName ?? "") command is experimental and may change in minor releases")
        }
    }
}

protocol SingleStreamingCommand : StreamingCommand {
    func executeCommand() async throws -> Output
}

extension SingleStreamingCommand {
    func performCommand(with continuation: AsyncThrowingStream<OutputMessage, Error>.Continuation) async throws {
        yield(output: try await executeCommand())
    }
}


/// A type that can be output in a sequence of messages
protocol MessageConvertible: Encodable & CustomStringConvertible {
    /// The attributed output string, used for ANSI terminals
    // var attributedString: String { get }
}

extension StreamingCommand {
    /// Sends the output to the hander
    func yield(output: Output) {
        outputOptions.streams.yield(Either.Or.a(output))
    }

    func yield(message: Message) {
        outputOptions.streams.yield(Either.Or.b(message))
    }

    /// The closure that will output a message
    fileprivate func writeMessage(_ message: Message, output: String? = nil, terminator: String = "\n") {
        if !outputOptions.emitJSON || outputOptions.messagePlain {
            let message = message.description
            outputOptions.streams.write(error: !outputOptions.messageErrout, output: output, message, terminator: terminator)
        } else {
            yield(message: message)
        }
    }

    func trace(_ message: @autoclosure () throws -> String) rethrows {
        try msg(.trace, message())
    }

    func info(_ message: @autoclosure () throws -> String, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) rethrows {
        try msg(.note, message(), sourceFile: sourceFile, sourceRange: sourceRange)
    }

    func warn(_ message: @autoclosure () throws -> String, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) rethrows {
        try msg(.warning, message(), sourceFile: sourceFile, sourceRange: sourceRange)
    }

    func error(_ message: @autoclosure () throws -> String, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) rethrows {
        try msg(.error, message(), sourceFile: sourceFile, sourceRange: sourceRange)
    }

    /// Output the given message to standard error
    func msg(_ kind: Message.Kind = .note, _ message: @autoclosure () throws -> String, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) rethrows {
        if outputOptions.quiet == true {
            return
        }
        if kind == .trace && outputOptions.verbose != true {
            return // skip debug output unless we are running verbose
        }

        writeMessage(Message(kind: kind, message: try message(), sourceFile: sourceFile, sourceRange: sourceRange))
    }


    /// Output the given message to standard error with no type prefix
    ///
    /// This function is redundant, but works around some compiled issue with disambiguating the default initial arg with the nameless autoclosure final arg.
    func msg(_ message: @autoclosure () throws -> String, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) rethrows {
        try self.msg(.note, try message(), sourceFile: sourceFile, sourceRange: sourceRange)
    }
}

typealias BufferedOutputByteStream = TSCBasic.BufferedOutputByteStream
