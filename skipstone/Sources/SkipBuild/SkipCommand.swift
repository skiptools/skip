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

protocol SkipPhase : AsyncParsableCommand {
    var outputOptions: OutputOptions { get }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
protocol SkipCommand : SkipPhase {
    var outputOptions: OutputOptions { get set }
}

extension SkipCommand {
    /// Initialize a Skip command to run with the given fixed streams.
    func setup(out: WritableByteStream? = nil, err: WritableByteStream? = nil) throws -> Self {
        if let outputFile = outputOptions.output {
            let path = URL(fileURLWithPath: outputFile)
            outputOptions.streams.out = try LocalFileOutputByteStream(AbsolutePath(validating: path.path))
        } else if let out = out {
            outputOptions.streams.out = out
        }
        if let err = err {
            outputOptions.streams.err = err
        }
        return self
    }
}

// MARK: Command Executor

public protocol SkipCommandExecutor : AsyncParsableCommand {

}

/// The command that is run by "SkipRunner" (aka "skip")
public struct SkipRunnerExecutor: SkipCommandExecutor {
    public static var configuration = CommandConfiguration(
        commandName: "skip",
        abstract: "skip \(skipVersion)",
        shouldDisplay: true,
        subcommands: [
            WelcomeCommand.self,
            VersionCommand.self,

            DoctorCommand.self,
            SelftestCommand.self,
            UpgradeCommand.self,

            CreateCommand.self,
            InitCommand.self,

            // Conditional on SkipDrive being imported
            GradleCommand.self,
            TestCommand.self,

            // Hidden commands used by the plugin
            HostIDCommand.self,
            InfoCommand.self,
            SkippyCommand.self,
            TranspileCommand.self,
            SnippetCommand.self,
            DumpSwiftCommand.self,
            DumpSkipCommand.self,
        ]
    )

    //@OptionGroup public var output: OutputOptions

    /// This is needed to handle execution of the tool from as a sandboxed command plugin; hide from display for normal CLI usage
    @Option(name: [.long], help: ArgumentHelp("List of targets to apply", valueName: "target", visibility: .private))
    public var target: Array<String> = []

    public init() {
    }
}


/// The command that is run by "SkipKey", which can be used to create and verify Skip license keys
public struct SkipKeyExecutor: SkipCommandExecutor {
    public static var configuration = CommandConfiguration(commandName: "skipkey",
                                                           abstract: "Skip Key Tool \(skipVersion)",
                                                           subcommands: [
                                                            InfoCommand.self,
                                                            CreateCommand.self,
                                                           ])

    public init() {
    }

    struct KeyOutput : MessageConvertible {
        var id: String
        var expiration: Date
        var key: String

        var description: String {
            """
            id: \(id)
            expiration: \(ISO8601DateFormatter.string(from: expiration, timeZone: TimeZone(secondsFromGMT: 0)!))
            key: \(key)
            """
        }
    }


    struct InfoCommand: SingleStreamingCommand {
        static var configuration = CommandConfiguration(commandName: "info", abstract: "Show key info")

        @Option(name: [.customShort("k"), .long], help: ArgumentHelp("The key to open", valueName: "key"))
        var key: String

        @OptionGroup(title: "Output Options")
        var outputOptions: OutputOptions

        typealias Output = KeyOutput

        func executeCommand() async throws -> Output {
            //info("create key")
            let licenseKey = try LicenseKey(licenseString: self.key)
            return KeyOutput(id: licenseKey.id, expiration: licenseKey.expiration, key: key)
        }
    }

    struct CreateCommand: SingleStreamingCommand {
        static var configuration = CommandConfiguration(commandName: "create", abstract: "Create a new key")

        @Option(name: [.customShort("i"), .long], help: ArgumentHelp("The identifier for the key", valueName: "id"))
        var id: String

        @Option(name: [.customShort("e"), .long], help: ArgumentHelp("The ISO-8601 key expiration date", valueName: "date"))
        var expiration: String

        @Option(name: [.customShort("h"), .long], help: ArgumentHelp("The hostid for the key", valueName: "hostid"))
        var hostid: String?

        @Option(name: [.long], help: ArgumentHelp("A hex-encoded 12-byte initialization vector", valueName: "nonce"))
        var nonce: String?

        @OptionGroup(title: "Output Options")
        var outputOptions: OutputOptions

        typealias Output = KeyOutput

        func executeCommand() async throws -> Output {
            guard let exp = ISO8601DateFormatter().date(from: expiration) else {
                throw LicenseError.licenseExpirationDateInvalid
            }
            let key = LicenseKey(id: id, expiration: exp, hostid: hostid)
            let iv = nonce.flatMap(Data.init(hexString:))
            if nonce != nil && iv?.count != 12 {
                throw LicenseError.invalidNonceFormat
            }
            let keyString = try key.licenseKeyString(iv: iv)
            return KeyOutput(id: id, expiration: exp, key: keyString)
        }
    }
}


extension SkipCommandExecutor {
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
                                                           abstract: "Print the skip version",
                                                           shouldDisplay: !experimental)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    func executeCommand() async throws -> Output {
        return Output()
    }
}


extension FileManager {
#if os(iOS)
    var homeDirectoryForCurrentUser: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }
#endif
}

// MARK: Command Phases

extension SkipPhase {
    /// The total size of all input source files, below which we will not enforce either license key or valid header comments
    /// this is meant to be large enough to accomodate simple demos and experiments without requiring any license
    static var codebaseThresholdSize: Int? { nil }
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
    var checkOptions: CheckPhaseOptions { get }
    var licenseOptions: LicenseOptions { get }
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
    func performSkippyCommands() async throws -> CheckResult {
        return CheckResult()
    }
}

extension CheckPhase where Self : StreamingCommand {

    /// Validate the license key if it is present in the tool or environment; otherwise scan the sources for approved license headers
    func validateLicense(sourceURLs: [URL], against now: Date = Date.now) async throws {

        /// Loads the `skipkey.env` file in ~/.skiptools/ for a license key
        func parseLicenseConfig() throws -> (Date, String?) {
            let (folder, installDate) = try skiptoolsFolder()
            let skipkeyFile = URL(fileURLWithPath: "skipkey.env", isDirectory: false, relativeTo: folder)
            if FileManager.default.fileExists(atPath: skipkeyFile.path) {
                let yaml = try YAML.parse(Data(contentsOf: skipkeyFile))
                if let license = yaml["SKIPKEY"]?.string, !license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (installDate, license)
                }
            }

            return (installDate, nil)
        }

        do {
            var (installDate, licenseString) = try parseLicenseConfig()
            let trialExpiration = installDate.addingTimeInterval(60 * 60 * 24 * 15) // 15-day implicit trial

            licenseString = licenseString ?? licenseOptions.skipKey ?? ProcessInfo.processInfo.environment["SKIPKEY"]

            let license = try licenseString.flatMap { try LicenseKey(licenseString: $0) }

            if let license = license {
                let exp = DateFormatter.localizedString(from: license.expiration, dateStyle: .short, timeStyle: .none)
                let daysLeft = Int(ceil(license.expiration.timeIntervalSince(now) / (12 * 60 * 60)))

                // if the license key has a hostid encoded into it, then validate it against the current machine
                if let hostid = license.hostid, hostid != ProcessInfo.processInfo.hostIdentifier {
                    throw error("Skip license key validation failed – manage your skipkeys at https://skip.tools")
                }

                // allow padding the license expiration for up to 14 days
                if daysLeft + min(licenseOptions.skipGracePeriod ?? 0, 14) < 0 {
                    throw error("Skip license key expired on \(exp) – get a new skipkey from https://skip.tools")
                } else if daysLeft <= 10 { // warn when the license is about to expire
                    warn("Skip license key will expire in \(daysLeft) day\(daysLeft == 1 ? "" : "s") on \(exp) – get a new skipkey from https://skip.tools")
                } else {
                    info("Skip license key valid through \(exp)")
                }
            } else if now < trialExpiration {
                let exp = DateFormatter.localizedString(from: trialExpiration, dateStyle: .short, timeStyle: .none)
                let daysLeft = Int(ceil(trialExpiration.timeIntervalSince(now) / (12 * 60 * 60)))
                if daysLeft <= 10 {
                    warn("Skip trial will expire in \(daysLeft) day\(daysLeft == 1 ? "" : "s") on \(exp) – get a skipkey from https://skip.tools")
                }
            } else { // no license key – scan sources for valid open-source license headers
                let scanSourceStart = Date().timeIntervalSinceReferenceDate
                let validated = try SourceValidator.scanSources(from: sourceURLs, codebaseThreshold: Self.codebaseThresholdSize)
                let scanSourceEnd = Date().timeIntervalSinceReferenceDate
                info("Codebase \(validated ? " scanned" : " scanned") (\(Int64((scanSourceEnd - scanSourceStart) * 1000)) ms)")
            }
        } catch let e as LicenseError {
            // issue an error with the offending file
            error(e.localizedDescription, sourceFile: e.sourceFile)
            throw e
        }
    }
}

struct CheckResult {

}

// MARK: SnippetPhase

protocol SnippetPhase: SkipPhase {
    var snippetOptions: SnippetPhaseOptions { get }
}

struct SnippetPhaseOptions: ParsableArguments {
    @Option(help: ArgumentHelp("Condition for snippet phase", valueName: "force/no"))
    var snippet: PhaseGuard = .onDemand // --snippet
}

struct SnippetResult {
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
    @Option(help: ArgumentHelp("The license key for transpiling non-free sources", valueName: "SKIPKEY"))
    var skipKey: String? = nil // --skip-key SKP657AB7680CA6789F76ABB65975678CDCA34PKS

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

func byteCount(for size: Int) -> String {
    ByteCountFormatter.string(fromByteCount: .init(size), countStyle: .file)
}


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
public protocol StreamingCommand: AsyncParsableCommand {
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

public protocol SingleStreamingCommand : StreamingCommand {
    func executeCommand() async throws -> Output
}

extension SingleStreamingCommand {
    public func performCommand(with continuation: AsyncThrowingStream<OutputMessage, Error>.Continuation) async throws {
        yield(output: try await executeCommand())
    }
}


/// A type that can be output in a sequence of messages
public protocol MessageConvertible: Encodable & CustomStringConvertible {
    /// The attributed output string, used for ANSI terminals
    // var attributedString: String { get }
}

public extension StreamingCommand {
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
        /// The unique host identifier as returned from `IOPlatformExpertDevice` on Darwin and the contents of "/etc/machine-id" on Linux
    public var hostIdentifier: String? {
        #if canImport(IOKit)
        let matchingDict = IOServiceMatching("IOPlatformExpertDevice")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matchingDict)
        defer { IOObjectRelease(service) }
        guard service != .zero else { return nil }
        return (IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, .zero).takeRetainedValue() as? String)
        #elseif os(Linux)
        return (try? String(contentsOfFile: "/etc/machine-id")) ?? (try? String(contentsOfFile: "/var/lib/dbus/machine-id"))
        #elseif os(Windows)
        // TODO: Windows registry key `MachineGuid`
        return nil
        #else
        return nil // unsupported platform
        #endif
    }

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


/// The path to a file/folder in a user's home directory
internal func home(_ file: String) -> String {
    NSHomeDirectory() + "/" + file
}


extension String {
    func extract(pattern: String) throws -> String? {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: self.utf16.count)
        if let match = regex.firstMatch(in: self, options: [], range: range) {
            let matchRange = match.range(at: 1)
            if let range = Range(matchRange, in: self) {
                return String(self[range])
            }
        }
        return nil
    }

    /// Pads the given string to the specified length
    func pad(_ length: Int, paddingCharacter: Character = " ") -> String {
        if self.count == length {
            return self
        } else if self.count < length {
            return self + String(repeating: paddingCharacter, count: length - self.count)
        } else {
            return String(self[..<self.index(self.startIndex, offsetBy: length)])
        }
    }
}

struct ToolOptions: ParsableArguments {
    @Option(help: ArgumentHelp("Xcode command path", valueName: "path"))
    var xcode: String = "/usr/bin/xcodebuild"

    @Option(help: ArgumentHelp("Swift command path", valueName: "path"))
    var swift: String = "/usr/bin/swift"

    // TODO: check processor for intel vs. arm for homebrew location rather than querying file system
    @Option(help: ArgumentHelp("Gradle command path", valueName: "path"))
    var gradle: String = FileManager.default.fileExists(atPath: "/usr/local/bin/gradle") ? "/usr/local/bin/gradle" : "/opt/homebrew/bin/gradle"

    @Option(help: ArgumentHelp("Path to the Android SDK (ANDROID_HOME)", valueName: "path"))
    var androidHome: String?
}

struct BuildOptions: ParsableArguments {
    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Run the project build"))
    var build: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Run the project tests"))
    var test: Bool = false
}

struct ProjectTemplate : Codable {
    let id: String
    let url: URL
    let localizedTitle: [String: String]
    let localizedDescription: [String: String]
}

/// An incomplete representation of package JSON, to be filled in as needed for the purposes of the tool
/// The output from `swift package dump-package`.
public struct PackageManifest : Hashable, Decodable {
    public var name: String
    //public var toolsVersion: String // can be string or dict
    public var products: [Product]
    public var dependencies: [Dependency]
    //public var targets: [Either<Target>.Or<String>]
    public var platforms: [SupportedPlatform]
    public var cModuleName: String?
    public var cLanguageStandard: String?
    public var cxxLanguageStandard: String?

    public struct Target: Hashable, Decodable {
        public enum TargetType: String, Hashable, Decodable {
            case regular
            case test
            case system
        }

        public var `type`: TargetType
        public var name: String
        public var path: String?
        public var excludedPaths: [String]?
        //public var dependencies: [String]? // dict
        //public var resources: [String]? // dict
        public var settings: [String]?
        public var cModuleName: String?
        // public var providers: [] // apt, brew, etc.
    }


    public struct Product : Hashable, Decodable {
        //public var `type`: ProductType // can be string or dict
        public var name: String
        public var targets: [String]

        public enum ProductType: String, Hashable, Decodable, CaseIterable {
            case library
            case executable
        }
    }

    public struct Dependency : Hashable, Decodable {
        public var name: String?
        public var url: String?
        //public var requirement: Requirement // revision/range/branch/exact
    }

    public struct SupportedPlatform : Hashable, Decodable {
        var platformName: String
        var version: String
    }
}


/// The output from `xcodebuild -showBuildSettings -json -project Project.xcodeproj -scheme SchemeName`
public struct ProjectBuildSettings : Decodable {
    public let target: String
    public let action: String
    public let buildSettings: [String: String]
}



public struct SkipDriveError : LocalizedError {
    public var errorDescription: String?
}

