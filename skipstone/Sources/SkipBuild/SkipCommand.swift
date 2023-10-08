import Foundation
import SkipSyntax
import SwiftParser
import SwiftSyntax
import ArgumentParser
import TSCBasic
import Universal
import struct Universal.JSON

/// The version of Skip, via `SkipSyntax`
public let skipVersion = SkipSyntax.skipVersion // we don't want to have to import SkipSyntax just to get the version, so re-export it

struct Options {
    var preprocessorSymbols: [String] = []
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
protocol SkipCommand : AsyncParsableCommand, OutputOptionsCommand {
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


/// Runs the tool with the given arguments, returning the entire output string as well as a function to parse it to `JSON`
public func skipstone(_ args: [String]) async throws -> (out: String, err: String, json: () throws -> JSON) {
    let out = BufferedOutputByteStream()
    let err = BufferedOutputByteStream()
    try await SkipRunnerExecutor.run(args, out: out, err: err)
    return (out.bytes.description.trimmingCharacters(in: .whitespacesAndNewlines), err.bytes.description.trimmingCharacters(in: .whitespacesAndNewlines), { try JSON.parse(out.bytes.description.utf8Data) })
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
            CheckupCommand.self,
            UpgradeCommand.self,

            AppCommand.self,
            LibCommand.self,
            AppCreateCommand.self, // skip create is shorthand for skip app create
            LibInitCommand.self, // skip init is shorthand for skip lib init

            // Conditional on SkipDrive being imported
            GradleCommand.self,
            ADBCommand.self,
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

    struct KeyOutput : MessageEncodable {
        var id: String
        var expiration: Date
        var key: String

        func message(term: Term) -> String? {
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
    /// Run the given command on the given arguments.
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
    struct Output : MessageEncodable {
        var version: String = skipVersion
        #if DEBUG
        let debug: Bool = true
        func message(term: Term) -> String? {
            "Skip version \(skipVersion) (debug)"
        }
        #else
        let debug: Bool? = nil
        func message(term: Term) -> String? {
            "Skip version \(skipVersion)"
        }
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

    /// Sets the modification time of all the files and folders under the given directory (inclusive) to the epoch, which defaults to January 1970.
    func zeroFileTimes(under directory: URL, epoch: Date = Date(timeIntervalSince1970: 0.0)) throws {
        if let pathEnumerator = self.enumerator(at: directory, includingPropertiesForKeys: nil, options: []) {
            for path in pathEnumerator {
                if let url = path as? URL {
                    try self.setAttributes([FileAttributeKey.modificationDate: epoch], ofItemAtPath: url.path)
                }
            }
        }

        // the parent directory itself is not included in the enumerator
        try self.setAttributes([FileAttributeKey.modificationDate: epoch], ofItemAtPath: directory.path)
    }
}

// MARK: Command Phases

extension SkipCommand {
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

// MARK: TranspilerInputOptionsCommand

protocol TranspilerInputOptionsCommand : SkipCommand {
    var inputOptions: TranspilerInputOptions { get }
}

extension TranspilerInputOptionsCommand {
    func performSkippyCommands() async throws -> CheckResult {
        return CheckResult()
    }
}

struct TranspilerInputOptions: ParsableArguments {
    @Option(help: ArgumentHelp("Condition for check phase", valueName: "force/no"))
    var check: PhaseGuard = .onDemand

    @Option(name: [.customShort("S")], help: ArgumentHelp("Preprocessor symbols", valueName: "file"))
    var symbols: [String] = []

    @Option(name: [.customShort("O")], help: ArgumentHelp("Output directory", valueName: "dir"))
    var directory: String? = nil

    // TODO: @available(*, deprecated, message: "unused since we no longer trust input file lists from plugin")
    @Argument(help: ArgumentHelp("List of files to process"))
    var files: [String] = []
}

struct CheckResult {

}

// MARK: SnippetOptions

protocol SnippetOptionsCommand: SkipCommand {
    var snippetOptions: SnippetOptions { get }
}

struct SnippetOptions: ParsableArguments {
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

protocol LicenseOptionsCommand : ParsableArguments {
    /// This command's output options
    var licenseOptions: LicenseOptions { get }
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


extension Message: MessageConvertible {
    /// A transpiler mesage converts warnings and errors to warn/fail
    public var status: MessageBlock.Status? {
        switch kind {
        case .trace:
            return .none
        case .note:
            return .none
        case .warning:
            return .warn
        case .error:
            return .fail
        }

    }

    public func message(term: Term) -> String? {
        // TODO: use terminal colors to highlight transpile errors in console environments
        self.formattedMessage
    }
}

/// A stream of output messages that can be issued by a command; they can be encodables for JSON output or message handles for rich terminal output
public typealias MessageStream = AsyncThrowingStream<MessageEncodable, Error>

/// A message handler for the results of commands. The messenger remembers the output of previous commands, and can also forward messages to various formatters, such as JSON or colored console output.
actor MessageQueue {
    let retain: Bool
    let continuation: MessageStream.Continuation
    var elements: [Result<MessageStream.Element, Error>] = []

    init(retain: Bool, continuation: MessageStream.Continuation) {
        self.retain = retain
        self.continuation = continuation
    }

    @discardableResult public func yield(_ value: MessageStream.Element) -> AsyncThrowingStream<MessageStream.Element, Error>.Continuation.YieldResult {
        if retain {
            elements.append(.success(value))
        }
        return continuation.yield(value)
    }

    public func yield(with result: Result<MessageEncodable, Error>) {
        if retain {
            elements.append(result)
        }
        continuation.yield(with: result)
    }

    public func finish(throwing error: Error? = nil) async {
        continuation.finish(throwing: error)
    }

    /// Writes the given message to the continuation
    public func write(status: MessageBlock.Status?, _ message: String) {
        self.yield(MessageBlock(status: status, message))
    }
}

/// A command that contains options for how messages will be conveyed to the user
protocol StreamingCommand: AsyncParsableCommand {
    /// The structured output of this tool
    var outputOptions: OutputOptions { get set }

    //associatedtype Output : MessageConvertible
    //typealias OutputMessage = Either<Output>.Or<Message>

    func performCommand(with out: MessageQueue) async throws
}

extension StreamingCommand {
    func writeOutput(message: MessageEncodable) throws {
        try outputOptions.writeOutput(message, error: message is Message ? true : false)
    }

    mutating func run() async throws {
        var totalErrors: [any MessageEncodable] = []
        outputOptions.beginCommandOutput()
        var elements = self.startCommand().makeAsyncIterator()
        if let message = try await elements.next() {
            try writeOutput(message: message) // the initial element
            while let element = try await elements.next() {
                outputOptions.writeOutputSeparator()
                try writeOutput(message: element) // subsequent elements after the first separator
                if element.status == .fail {
                    totalErrors.append(element)
                }
            }
        }
        outputOptions.endCommandOutput()

        if totalErrors.count > 0 {
            throw StreamCommandError(errorDescription: "\(totalErrors.count) \(totalErrors.count == 1 ? "error" : "errors")")
        }
    }
}

struct StreamCommandError : LocalizedError {
    var errorDescription: String?

    var description: String {
        errorDescription ?? ""
    }
}

extension StreamingCommand {

    mutating func startCommand() -> MessageStream {
        AsyncThrowingStream { continuation in
            self.outputOptions.streams.yield = {
                switch $0 {
                case .a(let a): continuation.yield(a)
                case .b(let b): continuation.yield(b)
                }

            }
            // defer { self.output.streams.yield = { _ in } } // clears output
            let messenger = MessageQueue(retain: true, continuation: continuation)
            doCommand(with: messenger)
            //doCommand(with: continuation)
        }
    }

    func doCommand(with out: MessageQueue) {
        Task.detached {
            do {
                try await performCommand(with: out)
                await out.finish()
            } catch {
                await out.finish(throwing: error)
            }
        }
    }
}

extension StreamingCommand {
    func warnExperimental(_ experimental: Bool) {
        if experimental {
            self.msg(.warning, "the \(Self.configuration.commandName ?? "") command is experimental and may change in minor releases")
        }
    }
}

/// A simple command that issues messages
protocol MessageCommand : SkipCommand, StreamingCommand, OutputOptionsCommand {
    typealias Output = MessageBlock
    // func performCommand(with out: Messenger) async throws
}

protocol SingleStreamingCommand : StreamingCommand {
    associatedtype Output : MessageEncodable
    func executeCommand() async throws -> Output
}

extension SingleStreamingCommand {
    func performCommand(with out: MessageQueue) async throws {
        yield(output: try await executeCommand())
    }
}

/// Terminal output information, such as how to output messages in various ANSI colors.
public struct Term {
    public static let plain = Term(colors: false)
    public static let ansi = Term(colors: true)

    /// Whether to use color or plain output
    public let colors: Bool

    func color(_ string: any StringProtocol, code: Color) -> String {
        if colors == false {
            return string.description // return the plain string
        } else {
            return code.rawValue + string + Color.reset.rawValue
        }
    }

    /// Returns the string with and ANSI `black` code when colors are enabled, or the raw string when they are disabled
    public func black(_ string: any StringProtocol) -> String { color(string, code: .black) }
    /// Returns the string with and ANSI `red` code when colors are enabled, or the raw string when they are disabled
    public func red(_ string: any StringProtocol) -> String { color(string, code: .red) }
    /// Returns the string with and ANSI `green` code when colors are enabled, or the raw string when they are disabled
    public func green(_ string: any StringProtocol) -> String { color(string, code: .green) }
    /// Returns the string with and ANSI `yellow` code when colors are enabled, or the raw string when they are disabled
    public func yellow(_ string: any StringProtocol) -> String { color(string, code: .yellow) }
    /// Returns the string with and ANSI `blue` code when colors are enabled, or the raw string when they are disabled
    public func blue(_ string: any StringProtocol) -> String { color(string, code: .blue) }
    /// Returns the string with and ANSI `magenta` code when colors are enabled, or the raw string when they are disabled
    public func magenta(_ string: any StringProtocol) -> String { color(string, code: .magenta) }
    /// Returns the string with and ANSI `cyan` code when colors are enabled, or the raw string when they are disabled
    public func cyan(_ string: any StringProtocol) -> String { color(string, code: .cyan) }
    /// Returns the string with and ANSI `gray` code when colors are enabled, or the raw string when they are disabled
    public func gray(_ string: any StringProtocol) -> String { color(string, code: .gray) }
    /// Returns the string with and ANSI `white` code when colors are enabled, or the raw string when they are disabled
    public func white(_ string: any StringProtocol) -> String { color(string, code: .white) }

    // ANSI escape sequences for text colors
    enum Color : String, CaseIterable {
        static let esc = "\u{001B}"

        case reset = "\u{001B}[0m"
        case black = "\u{001B}[30m"
        case red = "\u{001B}[31m"
        case green = "\u{001B}[32m"
        case yellow = "\u{001B}[33m"
        case blue = "\u{001B}[34m"
        case magenta = "\u{001B}[35m"
        case cyan = "\u{001B}[36m"
        case white = "\u{001B}[37m"
        case gray = "\u{001B}[30;1m"
    }
}

/// A "message" that can be output in various ways.
///
/// The default `message(term:)` must minimally be implemented for terminal messages.
public protocol MessageConvertible {
    /// Returns the message for the output with optional ANSI coloring
    func message(term: Term) -> String?

    var status: MessageBlock.Status? { get }
}

/// Any message that can be output either as a terminal message or a JSON encoded string
public typealias MessageEncodable = MessageConvertible & Encodable

/// A callback that converts a result into a `MessageBlock` and returns it along with the result
typealias MessageResultHandler<T> = (Result<T, Error>?) -> (result: Result<T, Error>?, message: MessageBlock?)

/// A message that is encoded by its string value
public protocol StringMessageEncodable : MessageConvertible, Encodable {
}

extension MessageConvertible {
    //var attributedString: String { description }

    /// The default status is nil
    public var status: MessageBlock.Status? { nil }
}

extension Never: MessageConvertible {
    public func message(term: Term) -> String? {
        nil
    }
}

extension StringMessageEncodable {
    /// Message convertable blocks default to encoding the string output
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let plainString = self.message(term: .plain) {
            try container.encode(plainString)
        } else {
            try container.encodeNil()
        }
    }

}

extension Optional : MessageConvertible where Wrapped : MessageConvertible {
    public var status: MessageBlock.Status? {
        flatMap(\.status)
    }

    /// An option return value will just return nil for an empty wrapped value
    public func message(term: Term) -> String? {
        flatMap({ $0.message(term: term) })
    }
}

/// A message that can optionally be highlighted with colors for rich terminal output, or a `nil` Terminal for omitting a status prefix from the message
public struct MessageBlock : StringMessageEncodable {
    public enum Status : String, Encodable {
        case pass, warn, fail, skip

        /// The character prefix to output before the command result
        func prefix(_ term: Term?) -> String? {
            guard let term = term else {
                return nil
            }
            switch self {
            case .pass:
                return "[" + term.green("✓") + "] "
            case .fail:
                return "[" + term.red("✗") + "] "
            case .warn:
                return "[" + term.yellow("!") + "] "
            case .skip:
                return "[" + term.magenta("-") + "] "
            }
        }
    }

    public let status: Status?
    let _message: (_ term: Term?) -> String?

    public init(status: Status?, _ message: String) {
        self.status = status
        self._message = { term in
            (status?.prefix(term) ?? "") + message
        }
    }

    /// Create a message from the given error with the expected prefix
    public init(error: Error, prefix: String = "") {
        self.init(status: .fail, prefix + error.localizedDescription)
    }

    public init(_ message: @escaping (_ term: Term?) -> String?) {
        self.status = nil
        self._message = message
    }

    public func message(term: Term) -> String? {
        self._message(term)
    }

    public enum CodingKeys : CodingKey {
        case status, msg
    }

    /// Messages are encoded like `{ "status": "fail", "msg": "operation failed" }`
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(_message(nil), forKey: .msg)
    }
}


extension StreamingCommand {
    /// Sends the output message the the handler, which will handle formatting it for various outputs like a terminal or JSON
    func yield(output: MessageEncodable) {
        outputOptions.streams.yield(.init(output))
    }

    func yield(message: Message) {
        outputOptions.streams.yield(Either.Or.b(message))
    }

    /// The closure that will output a message
    fileprivate func writeMessage(_ message: Message, output: String? = nil, terminator: String = "\n") {
        if !outputOptions.emitJSON || outputOptions.messagePlain {
            if let messageString = message.message(term: .plain) {
                outputOptions.streams.writeStream(error: !outputOptions.messageErrout, output: output, messageString, terminator: terminator)
            }
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
    /// True when the current architecture is ARM
    public static let isARM = {
        #if os(macOS)
        var size: size_t = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let platform = String(cString: machine)
        return platform.lowercased().contains("arm")

        #elseif os(Linux)
        if let cpuInfo = try? String(contentsOfFile: "/proc/cpuinfo") {
            return cpuInfo.lowercased().contains("arm")
        }
        return false

        #else
        return false
        #endif
    }()

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
    /// Extracts a regular expression created from the given string
    func extract(pattern: String) throws -> String? {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: self.utf16.count)
        if let match = regex.firstMatch(in: self, options: [], range: range), match.numberOfRanges >= 2 {
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

/// A `ToolOptionsCommand` holds options that can be used to control the paths of commonly-used tools
protocol ToolOptionsCommand : OutputOptionsCommand {
    /// This command's tool options
    var toolOptions: ToolOptions { get }
}

struct ToolOptions: ParsableArguments {
    @Option(help: ArgumentHelp("Xcode command path", valueName: "path"))
    var xcodebuild: String? = nil

    @Option(help: ArgumentHelp("Swift command path", valueName: "path"))
    var swift: String? = nil

    @Option(help: ArgumentHelp("Gradle command path", valueName: "path"))
    var gradle: String? = nil

    @Option(help: ArgumentHelp("ADB command path", valueName: "path"))
    var adb: String? = nil

    @Option(help: ArgumentHelp("Android emulator path", valueName: "path"))
    var emulator: String? = nil

    @Option(help: ArgumentHelp("Path to the Android SDK (ANDROID_HOME)", valueName: "path"))
    var androidHome: String? = nil

    private static var homebrewRoot: String {
        ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"]
            ?? (ProcessInfo.isARM ? "/opt/homebrew" : "/usr/local")
    }

    /// Returns the path for the given tool, or throws an error if no executable tool was found.
    ///
    /// Note that some tools can be overridden by name
    func toolPath(for tool: String) throws -> String {
        func customTool() -> String? {
            switch tool {
            case "swift": return self.swift ?? ProcessInfo.processInfo.environment["SKIP_SWIFT_PATH"]
            case "xcodebuild": return self.xcodebuild ?? ProcessInfo.processInfo.environment["SKIP_XCODEBUILD_PATH"]
            case "gradle": return self.gradle ?? ProcessInfo.processInfo.environment["SKIP_GRADLE_PATH"]
            case "adb": return self.adb ?? ProcessInfo.processInfo.environment["SKIP_ADB_PATH"]
            case "emulator": return self.emulator ?? ProcessInfo.processInfo.environment["SKIP_EMULATOR_PATH"]
            default: return nil
            }
        }
        if let toolPath = customTool() {
            return toolPath
        }
        return try URL.findCommandInPath(toolName: tool, withAdditionalPaths: ProcessInfo.isARM ? ["/opt/homebrew/bin"] : ["/usr/local/bin"]).path
    }
}

extension URL {
    /// Locates the given tool in the user's path
    public static func findCommandInPath(toolName: String, withAdditionalPaths extraPATH: [String]) throws -> URL {
        let env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? ""
        let pathParts = path.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
        for pathPart in pathParts + extraPATH {
            let dir = URL(fileURLWithPath: pathPart, isDirectory: true)
            let exePath = URL(fileURLWithPath: toolName, relativeTo: dir)
            if FileManager.default.isExecutableFile(atPath: exePath.path) {
                return exePath
            }
        }

        struct ToolNotFoundError : LocalizedError {
            var errorDescription: String?
        }
        throw ToolNotFoundError(errorDescription: "An executable tool named '\(toolName)' could not be found in the PATH, nor was it specified as part of the command-line flags.")
    }

}

protocol BuildOptionsCommand : ParsableArguments {
    /// This command's output options
    var buildOptions: BuildOptions { get }
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


extension FileSystem {
    /// Helper method to recurse the tree and perform the given block on each file.
    ///
    /// Note: `Task.isCancelled` is not checked; the controlling block should check for task cancellation.
    public func recurse(path: AbsolutePath, block: (AbsolutePath) async throws -> ()) async throws {
        let contents = try getDirectoryContents(path)

        for entry in contents {
            let entryPath = path.appending(component: entry)
            try await block(entryPath)
            if isDirectory(entryPath) {
                try await recurse(path: entryPath, block: block)
            }
        }
    }

    /// Output the filesystem tree of the given path.
    public func treeASCIIRepresentation(at path: AbsolutePath, hideHiddenFiles: Bool = true) throws -> String {
        var writer: String = ""
        print(".", to: &writer)
        try treeASCIIRepresent(fs: self, path: path, hideHiddenFiles: hideHiddenFiles, to: &writer)
        return writer
    }

    /// Helper method to recurse and print the tree.
    private func treeASCIIRepresent<T: TextOutputStream>(fs: FileSystem, path: AbsolutePath, hideHiddenFiles: Bool, prefix: String = "", to writer: inout T) throws {
        let contents = try fs.getDirectoryContents(path)
        let entries = contents
            .filter {
                !hideHiddenFiles || ($0.hasPrefix(".") == false)
            }
            //.sorted(using: .localizedStandard) // Darwin only
            .sorted()

        for (idx, entry) in entries.enumerated() {
            let isLast = idx == entries.count - 1
            let line = prefix + (isLast ? "└─ " : "├─ ") + entry
            print(line, to: &writer)

            let entryPath = path.appending(component: entry)
            if fs.isDirectory(entryPath) {
                let childPrefix = prefix + (isLast ?  "   " : "│  ")
                try treeASCIIRepresent(fs: fs, path: entryPath, hideHiddenFiles: hideHiddenFiles, prefix: String(childPrefix), to: &writer)
            }
        }
    }

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

extension Collection {
    /// Returns the substring of the given string
    func slice(_ i1: Int, _ i2: Int? = nil) -> SubSequence {
        self[index(startIndex, offsetBy: i1)..<((i2 == nil ? nil : index(startIndex, offsetBy: i2!, limitedBy: endIndex)) ?? endIndex)]
    }
}
