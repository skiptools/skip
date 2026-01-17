// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

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


/// Runs the tool with the given arguments, returning the entire output string as well as a function to parse it to `JSON`.
///
/// The command interacts with the `skip` command in the same process, but the command is treated exactly as if it were forked.
/// This enabled functional tool testing without the overhead of forking processes and parsing the output.
public func skipstone(_ args: [String]) async throws -> (out: String, err: String, json: () throws -> JSON) {
    let out = BufferedOutputByteStream()
    let err = BufferedOutputByteStream()
    try await SkipRunnerExecutor.runInProcess(args, out: out, err: err)
    return (out.bytes.description.trimmingCharacters(in: .whitespacesAndNewlines), err.bytes.description.trimmingCharacters(in: .whitespacesAndNewlines), { try JSON.parse(out.bytes.description.utf8Data) })
}

/// The command that is run by "SkipRunner" (aka "skip")
public struct SkipRunnerExecutor: SkipCommandExecutor {
    public static var configuration = CommandConfiguration(
        commandName: "skip",
        abstract: "skip \(skipVersion)",
        //version: skipVersion,
        shouldDisplay: true,
        subcommands: [
            WelcomeCommand.self,
            VersionCommand.self,

            DoctorCommand.self,
            CheckupCommand.self,
            UpgradeCommand.self,
            LicenseCommand.self,

            CreateCommand.self,
            InitCommand.self, // skip init is shorthand for skip lib init
            VerifyCommand.self,
            IconCommand.self,

            // Conditional on SkipDrive being imported
            GradleCommand.self,
            ADBCommand.self,
            AndroidCommand.self,
            ExportCommand.self,
            DevicesCommand.self,
            RunCommand.self,
            TestCommand.self,

            // Hidden commands used by the plugin
            HostIDCommand.self,
            InfoCommand.self,
            SkippyCommand.self,
            TranspileCommand.self,
            SnippetCommand.self,
            PluginCommand.self,
            DumpSwiftCommand.self,
            DumpSkipCommand.self,
        ]
    )

    public init() {
    }
}

/// Encapsulates `--version` flag behavior.
struct VersionOptions: ParsableArguments {
    @Flag(name: .long, help: "Print the version and exit")
    var version: Bool = false

    func validate() throws {
        if version {
            print(VersionCommand.Output().message(term: .plain) ?? "")
            throw ExitCode.success
        }
    }
}

extension SkipCommandExecutor {
    /// Run the given command on the given arguments.
    static func runInProcess(_ arguments: [String], basePath: AbsolutePath = localFileSystem.currentWorkingDirectory!, out: WritableByteStream? = nil, err: WritableByteStream? = nil) async throws {
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


// MARK: Command Phases

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
        input.file.name.hasSuffix(".swift") ? input.file.name.dropLast(".swift".count).description : input.file.name
    }

    /// Returns the expected Kotlin file name for this transpilation
    var kotlinFileName: String {
        outputFileBaseName + ".kt"
    }
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

    func subqueue(_ title: String) -> MessageQueue {
        // TODO: create a child message queue that will be used for nesting output messages or hiding them in terse mode
        return self
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

extension StreamingCommand {

    /// Returns the plugin build output folder with the given module and package names, taking into account changes in the SwiftPM output folder structure between different Swift versions.
    func buildPluginOutputFolder(forModule moduleName: String, inBuildFolder buildFolderAbsolute: AbsolutePath) throws -> AbsolutePath {
        // the plugin outputs are placed in a folder name that matches the root name of the package, irrespective of the actual package name in the Package.swift file
        let rootFolderName = buildFolderAbsolute.parentDirectory.basename.lowercased()

        var buildOutputFolder = buildFolderAbsolute.appending(components: ["plugins", "outputs", rootFolderName, moduleName])
        // accomodate the change in plugin output folders for Swift 6/Xcode 16:
        // Swift 5: .build/plugins/outputs/skipapp-hello/HelloSkip/skipstone
        // Swift 6: .build/plugins/outputs/skipapp-hello/HelloSkip/destination/skipstone
        if (try? buildOutputFolder.appending(component: "destination").asURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            buildOutputFolder = buildOutputFolder.appending(component: "destination")
        }

        buildOutputFolder = buildOutputFolder.appending(component: "skipstone")
        if (try? buildOutputFolder.asURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
            throw error("The expected build output folder \(buildOutputFolder.pathString) did not exist")
        }
        return buildOutputFolder
    }

    /// Perform the given operation, logging to a temporary file and displaying the results of the command once it has completed.
    /// - Parameters:
    ///   - out: the message queue for outputting messages and statuses
    ///   - operation: the operation to execute
    func withLogStream(title: String? = nil, with out: MessageQueue, operation: () async throws -> ()) async {
        let cmdname = Self.configuration.commandName ?? "cmd"
        let title = title ?? "Skip \(skipVersion) \(cmdname)"
        let startTime = Date.now

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        let dateString = dateFormatter.string(from: startTime)

        let logPath = outputOptions.logFile ?? "/tmp/skip-\(cmdname)-\(dateString).txt"

        outputOptions.streams.logFile = try? .init(AbsolutePath(validating: logPath))
        defer {
            outputOptions.streams.logFile = nil
        }

        do {
            try await operation()
        } catch {
            await out.yield(MessageBlock(status: .fail, error.localizedDescription))
        }
        let messages = await out.elements

        if messages.isEmpty {
            await out.yield(MessageBlock(status: .fail, "No command output"))
        } else {
            //let total = messages.count
            let warnings = messages.filter({ $0.messageStatus == .warn }).count
            let errors = messages.filter({ $0.messageStatus == .fail }).count

            var msg = title
            if warnings > 0 || errors > 0 {
                if errors > 0 {
                    msg += " failed with \(errors) error\(errors == 1 ? "" : "s")"
                }
                if warnings > 0 {
                    msg += " \(errors > 0 ? "and" : "with") \(warnings) warning\(warnings == 1 ? "" : "s")"
                }
                if errors > 0 || warnings > 0 {
                    msg += "\nSee \(outputOptions.term.yellow("https://skip.tools/docs/faq")) and \(outputOptions.term.yellow("https://community.skip.tools")) for help"
                    msg += "\nSee output log for error details: \(logPath)"
                }
            } else {
                msg += " succeeded in \(startTime.timingSecondsSinceNow)"
            }

            await out.yield(MessageBlock(status: errors > 0 ? .fail : warnings > 0 ? .warn : .pass, msg))
        }
    }
}

/// A command that contains options for how messages will be conveyed to the user
protocol StreamingCommand: AsyncParsableCommand {
    /// The structured output of this tool
    var outputOptions: OutputOptions { get set }

    associatedtype Output : MessageEncodable

    /// Perform the command, which will write messages to the output queue
    func performCommand(with out: MessageQueue) async throws


    /// Whether this command should immediately fail on error or not
    var failFast: Bool { get }
}

extension StreamingCommand {
    // By default, all tools will fail fast
    var failFast: Bool {
        true
    }

    func writeOutput(message: MessageEncodable) throws {
        try outputOptions.writeOutput(message, error: message is Message ? true : false)
    }

    mutating func run() async throws {

        var messages: [any MessageEncodable] = []
        outputOptions.beginCommandOutput()

        let stream = AsyncThrowingStream { continuation in
            let out = MessageQueue(retain: true, continuation: continuation)
            self.outputOptions.streams.yield = { messageConvertibleOrMessage in
                switch messageConvertibleOrMessage {
                case .a(let messageConvertible): continuation.yield(messageConvertible)
                case .b(let message): continuation.yield(message)
                }
            }
            doCommand(with: out)
        }

        var elements = stream.makeAsyncIterator()
        if let message = try await elements.next() {
            try writeOutput(message: message) // the initial element
            while let element = try await elements.next() {
                outputOptions.writeOutputSeparator()
                try writeOutput(message: element) // subsequent elements after the first separator (e.g., a JSON comma)
                messages.append(element)
            }
        }
        outputOptions.endCommandOutput()

        let messageTypes = Dictionary(grouping: messages, by: \.status)

        // in the end, throw an error if there are any failures; otherwise pass
        // TODO: a --warnings-as-errors flag could be useful for running in strict mode
        if let failCount = messageTypes[.fail]?.count, failCount > 0 {
            // this is useful for unit test failures, but is too verbose for command-line failures
            //throw StreamCommandError(errorDescription: "\(failCount) \(failCount == 1 ? "error" : "errors"): \(messages.compactMap({ $0.message(term: .plain) }))", messages: messages)
            throw StreamCommandError(errorDescription: "\(failCount) \(failCount == 1 ? "error" : "errors")", messages: messages)
        }
    }
}

struct StreamCommandError : LocalizedError {
    var errorDescription: String?
    var messages: [any MessageEncodable]

    var description: String {
        errorDescription ?? ""
    }
}

extension StreamingCommand {

    fileprivate func doCommand(with out: MessageQueue) {
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
protocol MessageCommand : SkipCommand, StreamingCommand, OutputOptionsCommand where Output == MessageBlock {
}

protocol SingleStreamingCommand : StreamingCommand {
    func executeCommand() async throws -> Output
}

extension SingleStreamingCommand {
    func performCommand(with out: MessageQueue) async throws {
        yield(output: try await executeCommand())
    }
}

/// A "message" that can be output in various ways.
///
/// The default `message(term:)` must minimally be implemented for terminal messages.
public protocol MessageConvertible {
    /// Returns the message for the output with optional ANSI coloring
    func message(term: Term) -> String?

    var status: MessageBlock.Status? { get }
    var squelch: Bool { get }
}

extension MessageConvertible {
    public var squelch: Bool { false }
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

    /// Whether to silence this message from being printed to the terminal
    public var squelch: Bool = false

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
    /// The root path for Homebrew on this macOS
    public static let homebrewRoot: String = {
        if let envroot = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"] {
            return envroot
        }

        // “The script installs Homebrew to its default, supported, best prefix (/opt/homebrew for Apple Silicon, /usr/local for macOS Intel and /home/linuxbrew/.linuxbrew for Linux)” — https://docs.brew.sh/Installation
        #if os(macOS) || os(macCatalyst)
        return ProcessInfo.isARM ? "/opt/homebrew" : "/usr/local"
        #else
        // Linux
        return "/home/linuxbrew/.linuxbrew"
        #endif
    }()

    /// The default `JAVA_HOME`
    public static let defaultJavaHome: String = homebrewRoot + "/opt/java"

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

    /// The current process environment along with the default paths to various tools set
    public var environmentWithDefaultToolPaths: [String: String] {
        var env = self.environment
        let ANDROID_HOME = "ANDROID_HOME"
        if (env[ANDROID_HOME] ?? "").isEmpty {
            #if os(macOS)
            env[ANDROID_HOME] = ("~/Library/Android/sdk" as NSString).expandingTildeInPath
            #elseif os(Windows)
            env[ANDROID_HOME] = ("~/AppData/Local/Android/Sdk" as NSString).expandingTildeInPath
            #elseif os(Linux)
            env[ANDROID_HOME] = ("~/Android/Sdk" as NSString).expandingTildeInPath
            #endif
        }

        return env
    }

        /// The unique host identifier as returned from `IOPlatformExpertDevice` on Darwin and the contents of "/etc/machine-id" on Linux
    public var hostIdentifier: String? {
        #if canImport(IOKit)
        let matchingDict = IOServiceMatching("IOPlatformExpertDevice")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matchingDict)
        defer { IOObjectRelease(service) }
        guard service != .zero else { return nil }
        return (IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, .zero).takeRetainedValue() as? String)
        #elseif os(Linux)
        return ((try? String(contentsOfFile: "/etc/machine-id")) ?? (try? String(contentsOfFile: "/var/lib/dbus/machine-id")))?.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// A new string that replaces the current home directory portion of the current path with a tilde (~) character.
    ///
    /// On non-macOS systems, returns the string itself
    var abbreviatingWithTilde: String {
        #if os(macOS)
        // crashes the compiler on Linux
        (self as NSString).abbreviatingWithTildeInPath as String
        #else
        self
        #endif
    }
}


protocol ProjectCommand {
    var project: String { get }
}

extension ProjectCommand {
    var projectFolderURL: URL { URL(fileURLWithPath: project, isDirectory: true) }

}

/// A `ToolOptionsCommand` holds options that can be used to control the paths of commonly-used tools
protocol ToolOptionsCommand: OutputOptionsCommand {
    /// This command's tool options
    var toolOptions: ToolOptions { get set }
}

extension ToolOptionsCommand {
    var homeDir: URL {
        FileManager.default.homeDirectoryForCurrentUser // or URL.homeDirectory, but unavailable on Linux
    }

    var swiftPMConfigFolder: URL {
        #if os(macOS)
        homeDir.appendingPathComponent("Library/org.swift.swiftpm", isDirectory: true)
        #else
        // there are a couple of "standard" locations for the swift package manager configuration
        let cfg1 = homeDir.appendingPathComponent(".config/swiftpm", isDirectory: true)
        let cfg2 = homeDir.appendingPathComponent(".swiftpm/org.swift.swiftpm", isDirectory: true)
        let cfg3 = homeDir.appendingPathComponent(".swiftpm", isDirectory: true)
        return [cfg1, cfg2, cfg3].first(where: { FileManager.default.fileExists(atPath: $0.path) }) ?? cfg1
        #endif
    }
}

extension ToolOptionsCommand where Self : StreamingCommand {

    /// Extract the skip plugin fingerprint from the `Package.resolved` and add it to the trusted plugins in `~/Library/org.swift.swiftpm/security/plugins.json`
    func registerPluginFingerprint(for packageResolvedURL: URL) throws {
        // load the latest skip hash from `Package.resolved` and update it in the `security/plugins.json` file
        guard let packageResolved = try? JSONDecoder().decode(PackageResolved.self, from: Data(contentsOf: packageResolvedURL)) else {
            return // tolerate parse failures, since Package.resolved is not an especially stable format
        }

        guard let skipPin = packageResolved.pins.first(where: { $0.identity == "skip" && $0.kind == "remoteSourceControl" }) else {
            return
        }

        //let resolvedSkipVersion = skipPin.state.version
        let resolvedSkipFingerprint = skipPin.state.revision

        let pluginsFile = swiftPMConfigFolder.appendingPathComponent("security/plugins.json", isDirectory: false)
        var pluginsContent = try JSONDecoder().decode([PluginSecurity].self, from: (try? Data(contentsOf: pluginsFile)) ?? "[]".utf8Data)
        let originalPluginsContent = pluginsContent
        func isSkipPlugin(_ fingerprint: PluginSecurity) -> Bool {
            fingerprint.packageIdentity == "skip" && fingerprint.targetName == "skipstone"
        }
        var skipPlugin = pluginsContent.first(where: isSkipPlugin) ?? PluginSecurity(fingerprint: "", packageIdentity: "skip", targetName: "skipstone")
        if skipPlugin.fingerprint == resolvedSkipFingerprint {
            return // no change in latest plugin fingerprint
        }
        skipPlugin.fingerprint = resolvedSkipFingerprint

        pluginsContent = pluginsContent.filter { !isSkipPlugin($0) } + [skipPlugin]

        pluginsContent.sort { $0.packageIdentity < $1.packageIdentity }

        // if there were no changes, do not write out any changes
        if Set(pluginsContent) == Set(originalPluginsContent) { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let pluginsContentData = try encoder.encode(pluginsContent)
        try pluginsContentData.write(to: try pluginsFile.createParentDirectory())
    }

    /// Run swift package dump-package and return the parsed JSON results
    func parseSwiftPackage(with out: MessageQueue, at projectPath: String, swift swiftCommand: String = "swift") async throws -> PackageManifest {
        try await decodeCommand(with: out, title: "Check Swift Package", cmd: [swiftCommand, "package", "dump-package", "--package-path", projectPath]).get()
    }

    /// Invokes the given command that launches an executable and is expected to output JSON, which we parse into the specified data structure
    func decodeCommand<T: Decodable>(with out: MessageQueue, title: String, cmd: [String]) async throws -> Result<T, Error> {

        func decodeResult(_ result: Result<ProcessOutput, Error>) -> Result<T, Error> {
            do {
                let res = try result.get()
                let decoder = JSONDecoder()
                let decoded = try decoder.decode(T.self, from: res.stdout.utf8Data)
                return .success(decoded) // (result: .success(decoded), message: nil)
            } catch {
                return .failure(error) // (result: .failure(error), message: MessageBlock(status: .fail, title + ": error executing \(cmd.joined(separator: " ")): \(error)"))
            }
        }

        let output = try await run(with: out, title, cmd)
        return decodeResult(output)
    }
}

extension ToolOptionsCommand {
    /// Perform a monitor check on the given URL
    @discardableResult func check<T, U>(_ item: T, with out: MessageQueue, title: String, handle: @escaping (T) throws -> U) async -> Result<U, Error> {
        await outputOptions.monitor(with: out, title, resultHandler: { result in
            return (nil, nil) as (result: Result<U, any Error>?, message: MessageBlock?)
        }) { line in
            try handle(item)
        }
    }


    /// Perform a monitor check on the given URL
    @discardableResult func checkFile(_ url: URL, with out: MessageQueue, title: String? = nil, handle: @escaping (_ title: String, _ url: URL) throws -> CheckStatus) async -> Bool {
        let title = title ?? "Check \(url.relativeString)"
        let result = await outputOptions.monitor(with: out, title, resultHandler: { result in
            do {
                if let resultURL = try result?.get() {
                    let handleResult = try handle(title, resultURL)
                    return (result, MessageBlock(status: handleResult.status, handleResult.message ?? title))
                } else {
                    return (result, nil)
                }
            } catch {
                return (Result.failure(error), nil)
            }
        }) { loggingHandler in
            return url
        }
        return (try? result.get()) != nil
    }
}

struct CheckStatus {
    var status: MessageBlock.Status
    var message: String? = nil
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
            case "emulator": return self.emulator ?? ProcessInfo.processInfo.environment["SKIP_EMULATOR_PATH"] ?? self.emulatorBinary
            case "java": return ProcessInfo.processInfo.environment["JAVA_HOME"]?.appending("/bin/java") ?? ProcessInfo.defaultJavaHome.appending("/bin/java")
            default: return nil
            }
        }
        if let toolPath = customTool() {
            return toolPath
        }
        return try URL.findCommandInPath(toolName: tool, withAdditionalPaths: ProcessInfo.isARM ? ["/opt/homebrew/bin"] : ["/usr/local/bin"]).path
    }

    /// Returns the path to the emulator binary
    var emulatorBinary: String {
        // on Linux for Homebrew: /home/linuxbrew/.linuxbrew/share/android-commandlinetools/emulator/emulator
        // on macOS for Homebrew: /opt/homebrew/share/android-commandlinetools/emulator/emulator
        // on macOS: ~/Library/Android/sdk/emulator/emulator
        var emulatorBinary = ProcessInfo.homebrewRoot + "/share/android-commandlinetools/emulator/emulator"
        // check whether it exists, and if not, fallback to ~/Library/Android/sdk/emulator/emulator or path
        if !FileManager.default.isExecutableFile(atPath: emulatorBinary) {
            // TODO: search around for, e.g., Android Studio's version
            emulatorBinary = "emulator" // fallback to checking PATH
        }
        return emulatorBinary
    }

}

public struct ToolLaunchError : LocalizedError {
    public var errorDescription: String?
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

    func lastPathComponents(_ count: Int) -> String {
        var components: [String] = []
        var url = self
        for _ in 0..<count {
            components.append(url.lastPathComponent)
            url = url.deletingLastPathComponent()
        }
        return components.reversed().joined(separator: "/")
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

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Verify the project output"))
    var verify: Bool = false
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
    public var targets: [Either<Target>.Or<String>]
    public var platforms: [SupportedPlatform]
    public var cModuleName: String?
    public var cLanguageStandard: String?
    public var cxxLanguageStandard: String?

    public struct Target: Hashable, Decodable {
        public var packageAccess: Bool?
        public var `type`: String
        public var name: String
        public var path: String?
        public var excludedPaths: [String]?
        //public var resources: [String]? // dict
        public var settings: [JSON]?
        public var cModuleName: String?
        // public var providers: [] // apt, brew, etc.

        /*
         "pluginUsages" : [
                 {
                   "plugin" : [
                     "skipstone",
                     "skip"
                   ]
                 }
               ]
         */
        public var pluginUsages: [JSON]?

        /*
         "dependencies" : [
                 {
                   "byName" : [
                     "LibCLibrary",
                     null
                   ]
                 },
                 {
                   "product" : [
                     "SkipFoundation",
                     "skip-foundation",
                     null,
                     null
                   ]
                 },
                 {
                   "product" : [
                     "SkipFFI",
                     "skip-ffi",
                     null,
                     null
                   ]
                 }
               ]
         */
        public var dependencies: [JSON]?
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


/// An incomplete representation of Package.resolved JSON.
public struct PackageResolved : Hashable, Decodable {
    public var version: Int
    public var originHash: String?
    public var pins: [Pin]

    /**
     A package pin. E.g.:

     ```
     {
           "identity" : "skip",
           "kind" : "remoteSourceControl",
           "location" : "https://source.skip.tools/skip.git",
           "state" : {
             "revision" : "18aba366924bf622d047b97f3249560e1471cc25",
             "version" : "1.5.21"
           }
         }
     }
     ```
     */
    public struct Pin : Hashable, Decodable {
        public var identity: String
        public var kind: String
        public var location: String
        public var state: State

        public struct State: Hashable, Decodable {
            public var revision: String
            public var version: String
        }
    }
}

/**
 The `~/Library/org.swift.swiftpm/security/plugins.json` file with hashes for trusted plugins, e.g.:

 ```
 [
   {
     "fingerprint" : "18aba366924bf622d047b97f3249560e1471cc25",
     "packageIdentity" : "skip",
     "targetName" : "skipstone"
   },
   {
     "fingerprint" : "755c0ec69bd667aa4e8ba50c8b710585d302879e",
     "packageIdentity" : "swift-openapi-generator",
     "targetName" : "OpenAPIGenerator"
   }
 ]
 ```
 */
public struct PluginSecurity : Hashable, Codable {
    public var fingerprint: String
    public var packageIdentity: String
    public var targetName: String
}


/// The output from `xcodebuild -showBuildSettings -json -project Project.xcodeproj -scheme SchemeName`
public struct ProjectBuildSettings : Decodable {
    public let target: String
    public let action: String
    public let buildSettings: [String: String]
}


/**
 The output from `xcodebuild -list -json -project Project.xcodeproj`

 ```
 {
   "project" : {
     "configurations" : [
       "Debug",
       "Release"
     ],
     "name" : "HelloSkip",
     "schemes" : [
       "HelloSkip",
       "HelloSkip App"
     ],
     "targets" : [
       "HelloSkip App"
     ]
   }
 }
 ```
 */
struct XcodeProjectSchemes : Decodable {
    var project: XcodeProject

    struct XcodeProject : Decodable {
        var configurations: [String]?
        var name: String?
        var schemes: [String]?
        var targets: [String]?
    }
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
    public func treeASCIIRepresentation(at path: AbsolutePath, folderName: String = ".", hideHiddenFiles: Bool = true) throws -> String {
        var writer: String = ""
        print(folderName, to: &writer)
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
