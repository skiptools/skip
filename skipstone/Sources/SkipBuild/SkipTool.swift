import Foundation
import SkipSyntax
import SwiftParser
import SwiftSyntax
import ArgumentParser
import TSCBasic
import Universal
import struct Universal.JSON

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
                                                            PreflightAction.self,
                                                            TranspileAction.self,
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
    var preflightOptions: CheckPhaseOptions { get }
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
    func performPreflightActions() async throws -> CheckResult {
        return CheckResult()
    }
}

struct CheckResult {

}

struct PreflightAction: AsyncParsableCommand, CheckPhase {
    static var configuration = CommandConfiguration(commandName: "preflight", abstract: "Perform transpilation preflights")

    @OptionGroup(title: "Check Options")
    var preflightOptions: CheckPhaseOptions

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    func run() async throws {
        try await perform(on: preflightOptions.files.map({ Source.FilePath(path: $0) }), options: preflightOptions)
    }

    func perform(on sourceFiles: [Source.FilePath], options: CheckPhaseOptions) async throws {
        for sourceFile in sourceFiles {
            let source = try Source(file: sourceFile)
            let syntaxTree = SyntaxTree(source: source, preprocessorSymbols: Set(options.symbols), unavailableAPI: KotlinUnavailableAPI())
            let transformers = builtinKotlinTransformers()
            transformers.forEach { $0.gather(from: syntaxTree) }
            transformers.forEach { $0.prepareForUse(codebaseInfo: nil) }
            let translator = KotlinTranslator(syntaxTree: syntaxTree)
            let kotlinTree = translator.translateSyntaxTree()
            transformers.forEach { $0.apply(to: kotlinTree, translator: translator) }

            let messages = kotlinTree.messages + transformers.flatMap { $0.messages(for: sourceFile) }
            messages.forEach { print($0) }

            if let outputDir = options.directory {
                let outputFileURL = outputFileURL(for: sourceFile, in: URL(fileURLWithPath: outputDir))
                try "".write(to: outputFileURL, atomically: false, encoding: .utf8)
            }
        }
    }

    /// Xcode requires that we create an output file in order for incremental build tools to work.
    func outputFileURL(for sourceFile: Source.FilePath, in outputDir: URL) -> URL {
        var outputFileName = sourceFile.name
        if outputFileName.hasSuffix(".swift") {
            outputFileName = String(outputFileName.dropLast(".swift".count))
        }
        outputFileName += "_preflight.swift"
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
    var moduleNames: [String] = [] // --module name:path

    @Option(name: [.customLong("link")], help: ArgumentHelp("ModuleName:LinkPath", valueName: "module"))
    var linkPaths: [String] = [] // --link name:path

    @Option(help: ArgumentHelp("Path to the folder that contains skip.yml and overrides", valueName: "path"))
    var skipFolder: String? = nil // --skip-folder

    @Option(help: ArgumentHelp("Path to the output module root folder", valueName: "path"))
    var moduleRoot: String? = nil // --module-root

    @Option(help: ArgumentHelp("Path to the file that will store the max input file timestamp", valueName: "path"))
    var markerFile: String? = nil // --marker-file

    @Option(name: [.customShort("D", allowingJoined: true)], help: ArgumentHelp("Set preprocessor variable for transpilation", valueName: "value"))
    var preprocessorVariables: [String] = []

    @Option(name: [.long], help: ArgumentHelp("Output directory", valueName: "dir"))
    var outputFolder: String? = nil

    @Option(name: [.long], help: ArgumentHelp("The Gradle wrapper version to generate", valueName: "version"))
    var gradleVersion: String = "8.1.1"
}

struct TranspileResult {

}

extension TranspilePhase {
    func performTranspileActions() async throws -> (check: CheckResult, transpile: TranspileResult) {
        let checkResult = try await performPreflightActions()
        let transpileResult = TranspileResult()
        return (checkResult, transpileResult)
    }
}

struct TranspileAction: TranspilePhase, StreamingCommand {
    static var configuration = CommandConfiguration(commandName: "transpile", abstract: "Transpile Swift to Kotlin")

    @OptionGroup(title: "Check Options")
    var preflightOptions: CheckPhaseOptions

    @OptionGroup(title: "Transpile Options")
    var transpileOptions: TranspilePhaseOptions

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "License Options")
    var licenseOptions: LicenseOptions

    /// The lock file to prevent concurrent builds from reading from an output folder before it has been completed
    private static var skipLockFile = RelativePath(".skiplock")

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
        let sourceFiles = try preflightOptions.files.map(AbsolutePath.init(validating:))
        #if DEBUG
        let v = skipVersion + "*" // * indicated debug version
        #else
        let v = skipVersion
        #endif
        info("Skip \(v): performing transpilation to: \(transpileOptions.outputFolder ?? "nowhere") for: \(sourceFiles.map(\.basename))")
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

        let skipFolderPathContents = try fs.getDirectoryContents(skipFolderPath)
            .map { AbsolutePath(skipFolderPath, $0) }

        guard let outputFolder = transpileOptions.outputFolder else {
            throw error("Must specify --output-folder")
        }

        let outputFolderPath = try AbsolutePath(validating: outputFolder, relativeTo: baseOutputPath)
        if !fs.isDirectory(outputFolderPath) {
            // e.g.: ~Library/Developer/Xcode/DerivedData/PACKAGE-ID/SourcePackages/plugins/skiphub.output/SkipFoundationKotlinTests/skip-transpiler/SkipFoundation/src/test/kotlin
            //throw error("Folder specified by --output-folder did not exist: \(outputFolder)")
            try fs.createDirectory(outputFolderPath, recursive: true)
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

        let skiplock = moduleRootPath.appending(Self.skipLockFile)
        info("Using lock file: \(skiplock)")

        // if the lock file already exists, that means another process is currently building (or that the transpiler crashed last time, in which case the lock needs to be manually deleted)
        let pid = ProcessInfo.processInfo.processIdentifier
        if let lockFileContents = try? fs.readFileContents(skiplock),
           let lockFileProcess = pid_t(lockFileContents.description) {
            if (try? ProcessInfo.getRunningProcessIDs().contains(lockFileProcess)) == true {
                throw error("Lock file exists for running process \(lockFileProcess) at \(skiplock)", sourceFile: skiplock.sourceFile)
            } else {
                info("Removing stale pid \(lockFileProcess) lock file: \(skiplock)", sourceFile: skiplock.sourceFile)
                try? fs.removeFileTree(skiplock)
            }
        }

        // touch the lock file and then delete it when we are done
        try fs.writeFileContents(skiplock, bytes: ByteString(stringLiteral: pid.description), atomically: true)
        // clean up the lock file; note this won't happen when Xcode kills the transpiler due to use user halting a build
        defer { try? fs.removeFileTree(skiplock) }

        // track the most recent input change, and touch a file with the modified date to signify the most recent input source date that triggered a build; we first seed it with the most recent input source file, and the we also check out inputs (such as skip.yml) for changes
        var mostRecentInputSourceLoad: Date = try sourceFiles.map({ try fs.getFileInfo($0).modTime }).max() ?? .distantPast

        let packageName = KotlinTranslator.packageName(forModule: primaryModuleName)
        let overridden = try copyKotlinOverrides()
        let overriddenKotlinFiles = overridden.map({ $0.basename })
        // skip over any source file whose name would match a copied Kotlin file
        let sources = sourceFiles.map(\.sourceFile)

        // load and merge each of the skip.yml files for the dependent modules
        let (baseSkipConfig, mergedSkipConfig, configMap) = try loadSkipConfig(merge: true)
        let transformers: [KotlinTransformer] = try createTransformers(for: baseSkipConfig, with: configMap)

        var dependentCodebaseInfos: [CodebaseInfo] = []

        let moduleBasePath = moduleRootPath.parentDirectory

        let codebaseInfo = try await loadCodebaseInfo() // initialize the codebaseinfo and load DependentModuleName.skipcode.json

        var sourceURLs = sourceFiles.map(\.asURL)

        // also check any Kotlin files in the skipFolderFile
        for kotlinFile in skipFolderPathContents {
            if kotlinFile.extension == "kt" {
                sourceURLs += [kotlinFile.asURL]
            }
        }

        try await validateLicense(sourceURLs: sourceURLs)

        let transpiler = Transpiler(packageName: packageName, sourceFiles: sources, codebaseInfo: codebaseInfo, preprocessorSymbols: Set(preflightOptions.symbols), transformers: transformers)
        try await transpiler.transpile(handler: handleTranspilation)
        try saveCodebaseInfo() // save out the ModuleName.skipcode.json

        let sourceModules = try linkDependentModuleSources()
        try generateGradle(for: sourceModules, with: mergedSkipConfig)
        try saveSkipBuildSourceTimeMarker()


        return // everything following is a stage of the transpilation process

        /// Load the given source file, tracking its last modified date for the timestamp on the `.skipbuild` marker file
        func inputSource(_ path: AbsolutePath) throws -> ByteString {
            mostRecentInputSourceLoad = max(mostRecentInputSourceLoad, try fs.getFileInfo(path).modTime)
            return try fs.readFileContents(path)
        }

        func saveSkipBuildSourceTimeMarker() throws {
            guard let markerFile = transpileOptions.markerFile else {
                return
            }

            let skipBuildMarkerFile = try AbsolutePath(validating: markerFile, relativeTo: moduleBasePath)

            // touch the output file
            FileManager.default.createFile(atPath: skipBuildMarkerFile.pathString, contents: Data(), attributes: [.creationDate: mostRecentInputSourceLoad as NSDate, .modificationDate: mostRecentInputSourceLoad as NSDate])

            info("\(skipBuildMarkerFile.basename) marker file date: \(mostRecentInputSourceLoad)")
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

                let lockFile = linkModuleRoot.appending(Self.skipLockFile)

                for backoff in 1... {
                    // read the process id integer from the .skiplock file
                    guard let lockFileContents = try? fs.readFileContents(lockFile),
                          let pid = UInt32(lockFileContents.description) else {
                        break
                    }

                    if backoff >= 20 {
                        // give up after around 20 seconds
                        throw error("Stale pid \(pid) lock file detected: \(lockFile)")
                    } else {
                        info("Waiting on pid \(pid) lock file: \(lockFile)")
                        // backoff for N milliseconds
                        try await Task.sleep(nanoseconds: .init(backoff) * 100_000_000)
                    }
                }
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
                    info("\(dependencyCodebaseInfo.basename) codebase (\(Self.byteCount(for: .init(cbdata.count)))) loaded (\(Int64((codebaseLoadEnd - codebaseLoadStart) * 1000)) ms) for \(linkModuleName)", sourceFile: dependencyCodebaseInfo.sourceFile)
                } catch let e {
                    error("error loading codebase for linkModuleName: \(linkModuleName) from: \(dependencyCodebaseInfo.pathString) error: \(e.localizedDescription)", sourceFile: dependencyCodebaseInfo.sourceFile)
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
            info("\(outputFilePath.basename) (\(Self.byteCount(for: .init(codebaseBytes.count)))) codebase \(!codebaseWritten ? "unchanged" : "saved")", sourceFile: outputFilePath.sourceFile)
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
                info("\(buildGradle.basename) (\(Self.byteCount(for: .init(contents.count)))) \(!changed ? "unchanged" : "saved")", sourceFile: buildGradle.sourceFile)
            }

            func generateSettingsGradle() throws {
                let settingsPath = moduleRootPath.parentDirectory.appending(component: "settings.gradle.kts")
                var settingsContents = (skipConfig.settings ?? .init()).generate(context: .init(dsl: .kotlin))

                settingsContents += """

                rootProject.name = "\(primaryModuleName)"

                """

                for sourceModule in sourceModules {
                    settingsContents += """
                    include(":\(sourceModule)")

                    """
                }

                let changed = try fs.writeChanges(path: settingsPath, makeReadOnly: true, bytes: ByteString(encodingAsUTF8: settingsContents))
                info("\(settingsPath.basename) (\(Self.byteCount(for: .init(settingsContents.count)))) \(!changed ? "unchanged" : "written")", sourceFile: settingsPath.sourceFile)
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
                info("\(gradleWrapperPath.basename) (\(Self.byteCount(for: .init(gradeWrapperContents.count)))) \(!changed ? "unchanged" : "written")", sourceFile: gradleWrapperPath.sourceFile)
            }

            func generateGradleProperties() throws {
                let gradlePropertiesPath = moduleRootPath.parentDirectory.appending(component: "gradle.properties")
                let gradePropertiesContents = """
                org.gradle.jvmargs=-Xmx2048m
                android.useAndroidX=true
                android.enableJetifier=true
                kotlin.code.style=official
                """

                let changed = try fs.writeChanges(path: gradlePropertiesPath, makeReadOnly: true, bytes: ByteString(encodingAsUTF8: gradePropertiesContents))
                info("\(gradlePropertiesPath.basename) (\(Self.byteCount(for: .init(gradePropertiesContents.count)))) \(!changed ? "unchanged" : "written")", sourceFile: gradlePropertiesPath.sourceFile)
            }
        }

        func loadSkipConfig(path: AbsolutePath) throws -> SkipConfig {
            do {
                var yaml = try inputSource(path).withData(YAML.parse(_:))
                if yaml.object == nil { // an empty file will appear as nil, so just convert to an empty dictionary
                    yaml = .object([:])
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
            let currentModuleConfig = try loadSkipConfig(path: skipConfigPath)

            var configMap: [String: SkipConfig] = [:]
            configMap[primaryModuleName] = currentModuleConfig

            let currentModuleJSON = try currentModuleConfig.json()
            try trace("loading skip.yml from \(skipConfigPath): \(currentModuleJSON.prettyJSON)", sourceFile: skipConfigPath.sourceFile)

            if !merge {
                return (currentModuleConfig, currentModuleConfig, configMap) // just the unmerged base YAML
            }

            // build up a merged YAML from the base dependenices to the current module
            var aggregateJSON: Universal.JSON = [:]

            for (moduleName, modulePath) in moduleNamePaths {
                trace("moduleName: \(moduleName) modulePath: \(modulePath)")
                let moduleSkipBasePath = try AbsolutePath(validating: modulePath, relativeTo: moduleRootPath.parentDirectory)
                    .appending(components: ["Skip"])

                let moduleSkipConfigPath = moduleSkipBasePath.appending(component: configFileName)

                if fs.isFile(moduleSkipConfigPath) {
                    let skipConfigLoadStart = Date().timeIntervalSinceReferenceDate
                    let moduleConfig = try loadSkipConfig(path: moduleSkipConfigPath)
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
                    if primaryModuleName != moduleName
                        && primaryModuleName != moduleName + "Tests" {
                        if moduleName == "SkipUnit" {
                            contents += [.init("testImplementation(project(\":\(moduleName)\"))")]
                        } else {
                            contents += [.init("implementation(project(\":\(moduleName)\"))")]
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

        func kotlinOutputPath(for baseSourceFileName: String) -> AbsolutePath {
            outputFolderPath
                .appending(components: packageName.split(separator: ".").map(\.description)) // split package into directories
                .appending(RelativePath(baseSourceFileName))
        }


        /// Copies over the overridden .kt files from `ModuleNameKotlin/skip/*.kt` into the destination folder
        ///
        /// Any Kotlin files that are overridden will not be transpiled.
        func copyKotlinOverrides(makeLinks: Bool = true) throws -> Set<AbsolutePath> {
            var copiedFiles: Set<AbsolutePath> = []
            for sourcePath in skipFolderPathContents {
                let outputFilePath = kotlinOutputPath(for: sourcePath.basename)
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
                copiedFiles.insert(outputFilePath)
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
                info("\(sourcePath.basename) (\(Self.byteCount(for: .init(sourceSize)))) transpiling to \(outputFile.basename)", sourceFile: transpilation.sourceFile)
            }

            info("\(outputFile.basename) (\(Self.byteCount(for: transpilation.output.content.lengthOfBytes(using: .utf8)))) transpilation \(overridden ? "overridden" : !changed ? "unchanged" : "saved") from \(sourcePath.basename) (\(Self.byteCount(for: .init(sourceSize)))) in \(Int64(transpilation.duration * 1000)) ms", sourceFile: overridden ? transpilation.sourceFile : outputFile.sourceFile)

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
                trace("path: \(outputFolderPath)")

                let kotlinName = transpilation.kotlinFileName
                let outputFilePath = kotlinOutputPath(for: kotlinName)

                if overriddenKotlinFiles.contains(kotlinName) {
                    return (output: outputFilePath, changed: false, overridden: true)
                }

                let kotlinBytes = ByteString(encodingAsUTF8: transpilation.output.content)
                let fileWritten = try fs.writeChanges(path: outputFilePath, checkSize: true, makeReadOnly: true, bytes: kotlinBytes)

                trace("wrote to: \(outputFilePath)\(!fileWritten ? " (unchanged)" : "")", sourceFile: outputFilePath.sourceFile)

                // also save the output line mapping file: SomeFile.kt -> SomeFile.sourcemap
                let sourceMappingPath = outputFilePath.deletingPathExtension().appendingPathExtension("sourcemap")
                let sourceMapData = try JSONEncoder().encode(transpilation.outputMap)
                try fs.writeChanges(path: sourceMappingPath, makeReadOnly: true, bytes: ByteString(sourceMapData))

                return (output: outputFilePath, changed: fileWritten, overridden: false)
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

    /// Validate the license key if it is present in the tool or environment; otherwise scan the sources above the given codebase threshold size for approved headers
    func validateLicense(sourceURLs: [URL], against now: Date = Date.now) async throws {
        // the total size of all input source files, below which we will not enforce either license key or valid header comments
        // this is meant to be large enough to accomodate simple demos and experiments without requiring any license
        let codebaseThresholdSize: Int = 10 * 1024

        // the list of header match expressions that we permit for codebases above the given threshold
        let validLicenseHeaders = [
            try! NSRegularExpression(pattern: ".*GNU.*General Public License.*"),
        ]

        /// Loads the `.skip.yml` at the root of the project and checks for a "skip-license" key
        func parseLicenseConfig() throws -> String? {
            try YAML.parse(Data(contentsOf: URL(fileURLWithPath: ".skip.yml")))["skip-license"]?.string
        }

        let licenseString = licenseOptions.skipLicense ?? ProcessInfo.processInfo.environment["SKIP_LICENSE"] ?? (try? parseLicenseConfig())

        do {
            let license = try licenseString.flatMap { try LicenseKey(licenseString: $0) }

            if let license = license {
                let exp = DateFormatter.localizedString(from: license.expiration, dateStyle: .short, timeStyle: .none)
                let daysLeft = Int(ceil(license.expiration.timeIntervalSince(now) / (12 * 60 * 60)))

                // allow padding the license expiration for up to 14 days
                if daysLeft + min(licenseOptions.skipGracePeriod ?? 0, 14) < 0 {
                    error("Skip license expired on \(exp)")
                } else if daysLeft < 10 { // warn when the license is about to expire
                    warn("Skip license will expire in \(daysLeft) day\(daysLeft == 1 ? "" : "s") on \(exp)")
                } else {
                    info("Skip license valid through \(exp)")
                }
            } else {
                let scanSourceStart = Date().timeIntervalSinceReferenceDate
                let (codebaseSize, validated) = try await SourceValidator.scanSources(from: sourceURLs, codebaseThreshold: codebaseThresholdSize, headerExpressions: validLicenseHeaders)
                let scanSourceEnd = Date().timeIntervalSinceReferenceDate
                info("Codebase (\(Self.byteCount(for: .init(codebaseSize)))) \(validated ? " scanned for non-commercial license headers" : " scanned") in (\(Int64((scanSourceEnd - scanSourceStart) * 1000)) ms)")
            }
        } catch let e as LicenseError {
            // issue an error with the offending file
            error(e.localizedDescription, sourceFile: e.sourceFile)
            throw e
        }
    }

}

extension Source.FilePath {
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

struct LicenseOptions: ParsableArguments {
    @Option(help: ArgumentHelp("The license key for transpiling non-free sources", valueName: "SKIP_LICENSE"))
    var skipLicense: String? = nil // --skip-license SKP657AB7680CA6789F76ABB65975678CDCA34PKS

    /// A license flag that lets someone with an expired license add a few more days in order to confinue developing while the license is being renewed.
    @Option(help: ArgumentHelp("Grace period", valueName: "days"))
    var skipGracePeriod: Int? = nil // --skip-grace-period 7
}

extension AbsolutePath {
    /// Converts this FileSystem `AbsolutePath` into a `Source.FilePath` that the transpiler can use.
    var sourceFile: Source.FilePath {
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
            if isSymlink(path) {
                // if the file already exists but it is a link, delete it so we can overwrite it
                try? removeFileTree(path)
            }
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
        try await perform(on: files.map({ Source.FilePath(path: $0) }), options: opts)
    }

    func perform(on sourceFiles: [Source.FilePath], options: CheckPhaseOptions) async throws {
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
        try await perform(on: files.map({ Source.FilePath(path: $0) }), options: opts)
    }

    func perform(on sourceFiles: [Source.FilePath], options: CheckPhaseOptions) async throws {
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
//typealias SkippyAction = ForwardingCommand<PreflightAction, SkippyCommandName>


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

    func trace(_ message: @autoclosure () throws -> String, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) rethrows {
        try msg(.trace, message(), sourceFile: sourceFile, sourceRange: sourceRange)
    }

    func info(_ message: @autoclosure () throws -> String, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) rethrows {
        try msg(.note, message(), sourceFile: sourceFile, sourceRange: sourceRange)
    }

    func warn(_ message: @autoclosure () throws -> String, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) rethrows {
        try msg(.warning, message(), sourceFile: sourceFile, sourceRange: sourceRange)
    }

    @discardableResult func error(_ message: @autoclosure () throws -> String, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) rethrows -> ValidationError {
        try msg(.error, message(), sourceFile: sourceFile, sourceRange: sourceRange)
        return ValidationError(try message())
    }

    /// Output the given message to standard error
    func msg(_ kind: Message.Kind = .note, _ message: @autoclosure () throws -> String, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) rethrows {
        if outputOptions.quiet == true {
            return
        }
        if kind == .trace && outputOptions.verbose != true {
            return // skip debug output unless we are running verbose
        }
        writeMessage(Message(kind: kind, message: "" + (try message()), sourceFile: sourceFile, sourceRange: sourceRange))
    }


    /// Output the given message to standard error with no type prefix
    ///
    /// This function is redundant, but works around some compiled issue with disambiguating the default initial arg with the nameless autoclosure final arg.
    func msg(_ message: @autoclosure () throws -> String, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) rethrows {
        try self.msg(.note, try message(), sourceFile: sourceFile, sourceRange: sourceRange)
    }
}

// MARK: Helpers

typealias BufferedOutputByteStream = TSCBasic.BufferedOutputByteStream

private extension AbsolutePath {
    func deletingPathExtension() -> AbsolutePath {
        parentDirectory.appending(component: basenameWithoutExt)
    }

    func appendingPathExtension(_ ext: String) -> AbsolutePath {
        parentDirectory.appending(component: basenameWithoutExt + "." + ext)
    }
}

extension ProcessInfo {
    /// Get the list of all running process IDs, which we check against the contents of a `.skiplock` file
    static func getRunningProcessIDs() throws -> [Int32] {
        #if !canImport(Darwin)
        struct ProcessListUnsupportedPlatformError : Error { }
        throw ProcessListUnsupportedPlatformError()
        #else
        // return NSWorkspace.shared.runningApplications.map { $0.processIdentifier }
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        sysctl(&mib, 4, nil, &size, nil, 0)
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: Int(size) / MemoryLayout<kinfo_proc>.size)
        let count = sysctl(&mib, 4, &buffer, &size, nil, 0)
        guard count >= 0 else {
            return []
        }
        return buffer.map { $0.kp_proc.p_pid }
        #endif
    }
}
