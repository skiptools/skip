import Foundation
import SkipSyntax
import SwiftParser
import SwiftSyntax
import ArgumentParser
import SkipBuild
import Universal
import TSCBasic
import TSCLibc
import OSLog

/// The current versio of the tool
public let skipVersion = "0.0.42"

/// Command-line runner for the transpiler.
@main public struct Runner {
    static func main() async throws {
        await SkipCommandExecutor.main()
    }

    /// Run the transpiler on the given arguments.
    public static func run(_ arguments: [String], out: WritableByteStream? = nil, err: WritableByteStream? = nil) async throws {
        var cmd: ParsableCommand = try SkipCommandExecutor.parseAsRoot(arguments)
        if var cmd = cmd as? any StreamingCommand {
            if let out = out {
                cmd.output.streams.out = out
            }
            if let err = err {
                cmd.output.streams.err = err
            }
            try await cmd.run()
        } else if var cmd = cmd as? AsyncParsableCommand {
            try await cmd.run()
        } else {
            try cmd.run()
        }
    }
}

private protocol Action : AsyncParsableCommand {
    func perform(on sourceFiles: [Source.File], options: Options) async throws
}

struct Options {
    var preprocessorSymbols: [String] = []
    var outputDirectory: String?
}

private struct TranspileAction: Action {
    public static var configuration = CommandConfiguration(commandName: "transpile", abstract: "Transpile Swift to Kotlin")

    @Option(name: [.long, .customShort("S")], help: ArgumentHelp("Preprocessor symbols", valueName: "file"))
    var symbols: [String] = []

    @Option(name: [.long, .customShort("O")], help: ArgumentHelp("Output directory", valueName: "dir"))
    var directory: String? = nil

    @Argument(help: ArgumentHelp("List of files to process"))
    var files: [String]

    var options: Options {
        Options(preprocessorSymbols: symbols, outputDirectory: directory)
    }

    func run() async throws {
        try await perform(on: files.map({ Source.File(path: $0) }), options: options)
    }

    func perform(on sourceFiles: [Source.File], options: Options) async throws {
        var transpiler = Transpiler(sourceFiles: sourceFiles)
        transpiler.preprocessorSymbols = Set(options.preprocessorSymbols)
        try await transpiler.transpile { transpilation in
            for message in transpilation.messages {
                print(message)
            }
            print(transpilation.output.content)
            print()
        }
    }
}

private struct AssembleAction: AsyncParsableCommand {
    public static var configuration = CommandConfiguration(commandName: "assemble", abstract: "Generate Gradle build for project")

    func run() async throws {
        throw ValidationError("Not yet suppoerted")
    }
}

private struct BuildAction: AsyncParsableCommand {
    public static var configuration = CommandConfiguration(commandName: "build", abstract: "Build transpiled Kotlin project")

    func run() async throws {
        throw ValidationError("Not yet suppoerted")
    }
}

private struct TestAction: AsyncParsableCommand {
    public static var configuration = CommandConfiguration(commandName: "test", abstract: "Run transpiled JUnit tests")

    func run() async throws {
        throw ValidationError("Not yet suppoerted")
    }
}

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
//typealias SkippyAction = ForwardingCommand<SkipCheckAction, SkippyCommandName>

struct SkipCheckAction: Action {
    public static var configuration = CommandConfiguration(commandName: "check", abstract: "Preflight Swift transpilation")

    @Option(name: [.long, .customShort("S")], help: ArgumentHelp("Preprocessor symbols", valueName: "file"))
    var symbols: [String] = []

    @Option(name: [.long, .customShort("O")], help: ArgumentHelp("Output directory", valueName: "dir"))
    var directory: String? = nil

    @Argument(help: ArgumentHelp("List of files to process"))
    var files: [String]

    var options: Options {
        Options(preprocessorSymbols: symbols, outputDirectory: directory)
    }

    func run() async throws {
        try await perform(on: files.map({ Source.File(path: $0) }), options: options)
    }

    func perform(on sourceFiles: [Source.File], options: Options) async throws {
        for sourceFile in sourceFiles {
            let source = try Source(file: sourceFile)
            let syntaxTree = SyntaxTree(source: source, preprocessorSymbols: Set(options.preprocessorSymbols))
            let translator = KotlinTranslator(syntaxTree: syntaxTree)
            let kotlinTree = translator.translateSyntaxTree()
            kotlinTree.messages.forEach { print($0) }

            if let outputDir = options.outputDirectory {
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

private struct PrintSwiftASTAction: Action {
    public static var configuration = CommandConfiguration(commandName: "ast-swift", abstract: "Print the Swift AST")

    @Option(name: [.long, .customShort("S")], help: ArgumentHelp("Preprocessor symbols", valueName: "file"))
    var symbols: [String] = []

    @Option(name: [.long, .customShort("O")], help: ArgumentHelp("Output directory", valueName: "dir"))
    var directory: String? = nil

    @Argument(help: ArgumentHelp("List of files to process"))
    var files: [String]

    var options: Options {
        Options(preprocessorSymbols: symbols, outputDirectory: directory)
    }

    func run() async throws {
        try await perform(on: files.map({ Source.File(path: $0) }), options: options)
    }

    func perform(on sourceFiles: [Source.File], options: Options) async throws {
        for sourceFile in sourceFiles {
            let syntax = try Parser.parse(source: Source(file: sourceFile).content)
            print(syntax.root.prettyPrintTree)
        }
    }
}

private struct PrintSkipASTAction: Action {
    public static var configuration = CommandConfiguration(commandName: "ast-skip", abstract: "Print the Skip AST")

    @Option(name: [.long, .customShort("S")], help: ArgumentHelp("Preprocessor symbols", valueName: "file"))
    var symbols: [String] = []

    @Option(name: [.long, .customShort("O")], help: ArgumentHelp("Output directory", valueName: "dir"))
    var directory: String? = nil

    @Argument(help: ArgumentHelp("List of files to process"))
    var files: [String]

    var options: Options {
        Options(preprocessorSymbols: symbols, outputDirectory: directory)
    }

    func run() async throws {
        try await perform(on: files.map({ Source.File(path: $0) }), options: options)
    }

    func perform(on sourceFiles: [Source.File], options: Options) async throws {
        for sourceFile in sourceFiles {
            let source = try Source(file: sourceFile)
            let syntaxTree = SyntaxTree(source: source, preprocessorSymbols: Set(options.preprocessorSymbols))
            print(syntaxTree.prettyPrintTree)
        }
    }
}

public struct SkipCommandExecutor : AsyncParsableCommand {
    public static let experimental = false
    public static var configuration = CommandConfiguration(commandName: "skip",
                                                           abstract: "Swift Kotlin Interop",
                                                           shouldDisplay: !experimental,
                                                           subcommands: [
                                                            VersionCommand.self,
                                                            //SkippyAction.self,
                                                            SkipCheckAction.self,
                                                            TranspileAction.self,
                                                            AssembleAction.self,
                                                            BuildAction.self,
                                                            TestAction.self,
                                                            PrintSwiftASTAction.self,
                                                            PrintSkipASTAction.self,
                                                           ]
    )

    //@OptionGroup public var output: OutputOptions

    /// This is needed to handle execution of the tool from as a sandboxed command plugin
    @Option(name: [.long], help: ArgumentHelp("List of targets to apply", valueName: "target"))
    public var target: Array<String> = []

    public init() {
    }
}

public struct VersionCommand: SingleStreamingCommand {
    public static let experimental = false
    public struct Output : MessageConvertible {
        public var version: String = skipVersion
        public var description: String { "skip version \(skipVersion)" }
    }

    public static var configuration = CommandConfiguration(commandName: "version",
                                                           abstract: "Print the Skip version",
                                                           shouldDisplay: !experimental)

    @OptionGroup public var output: OutputOptions
    // alternative way of setting output
    //@OptionGroup public var parentOptions: SkipCommandExecutor
    //public var output: OutputOptions {
    //    get { parentOptions.output }
    //    set { parentOptions.output = newValue }
    //}

    public init() {
    }

    public func executeCommand() -> Output {
        return Output()
    }
}

extension MessageConvertible {
    //public var attributedString: String { description }
}

extension Never : MessageConvertible {
    public var description: String { "never" }
}

extension ToolOutput : MessageConvertible {
    public var description: String {
        if let kind = kind {
            return kind.name + ": " + message.description
        } else {
            return message.description
        }
    }
}

/// A command that contains options for how messages will be conveyed to the user
public protocol StreamingCommand : AsyncParsableCommand {
    /// The structured output of this tool
    associatedtype Output : MessageConvertible

    var output: OutputOptions { get set }

    func performCommand(with continuation: AsyncThrowingStream<Output, Error>.Continuation) async throws
}

extension StreamingCommand {
    public mutating func run() async throws {
        output.beginCommandOutput()
        var elements = self.startCommand().makeAsyncIterator()
        if let first = try await elements.next() {
            try output.writeOutput(first)
            while let element = try await elements.next() {
                output.writeOutputSeparator()
                try output.writeOutput(element)
            }
        }
        output.endCommandOutput()
    }
}


extension StreamingCommand {
    public mutating func startCommand() -> AsyncThrowingStream<Output, Error> {
        AsyncThrowingStream { (continuation: AsyncThrowingStream.Continuation) in
            self.output.streams.yield = { continuation.yield($0 as! Output) }
            // defer { self.output.streams.yield = { _ in } } // clears output
            doCommand(continuation: continuation)
        }
    }

    private func doCommand(continuation: AsyncThrowingStream<Output, Error>.Continuation) {
        Task {
            defer {
                self.output.streams.flush()
            }
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
            msg(.warn, "the \(Self.configuration.commandName ?? "") command is experimental and may change in minor releases")
        }
    }
}

protocol SingleStreamingCommand : StreamingCommand {
    func executeCommand() async throws -> Output
}

extension SingleStreamingCommand {
    public func performCommand(with continuation: AsyncThrowingStream<Output, Error>.Continuation) async throws {
        yield(try await executeCommand())
    }
}


/// A type that can be output in a sequence of messages
public protocol MessageConvertible : Encodable & CustomStringConvertible {
    /// The attributed output string, used for ANSI terminals
    // var attributedString: String { get }
}

extension StreamingCommand {
    /// Sends the output to the hander
    func yield(_ output: Output) {
        self.output.streams.yield(output)
    }

    /// Output the given message to standard error
    func msg(_ kind: MessageKind? = nil, _ message: @autoclosure () -> String) {
        if output.quiet == true {
            return
        }
        if kind == .trace && output.verbose != true {
            return // skip debug output unless we are running verbose
        }

        self.output.streams.writeMessage(ToolOutput(kind: kind, message: message()))
    }
}

/// The type of message output
public enum MessageKind: String, Encodable, Hashable {
    case trace, info, warn, error

    public var name: String {
        switch self {
        case .trace: return "TRACE"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        }
    }
}

public struct ToolOutput : Encodable {
    public let kind: MessageKind?
    public let message: String
}

extension ToolOutput {
    var color: TerminalController.Color {
        switch self.kind {
        case .trace: return .gray
        case .info: return .cyan
        case .warn: return .yellow
        case .error: return .red
        case .none: return .noColor
        }
    }
}

public typealias BufferedOutputByteStream = TSCBasic.BufferedOutputByteStream

public struct OutputOptions: ParsableArguments {
    @Option(name: [.long, .customShort("o")], help: ArgumentHelp("Send output to the given file", valueName: "path"))
    public var output: String?

    @Flag(name: [.long, .customShort("v")], help: ArgumentHelp("Whether to display verbose messages"))
    public var verbose: Bool = false

    @Flag(name: [.long, .customShort("q")], help: ArgumentHelp("Quiet mode: suppress output"))
    public var quiet: Bool = false

    @Flag(name: [.long, .customShort("J")], help: ArgumentHelp("Emit output as formatted JSON"))
    public var json: Bool = false

    @Flag(name: [.long, .customShort("j")], help: ArgumentHelp("Emit output as compact JSON"))
    public var jsonCompact: Bool = false

    @Flag(name: [.long, .customShort("M")], help: ArgumentHelp("Include messages in JSON output"))
    public var jsonMessages: Bool = false

    @Flag(name: [.long, .customShort("A")], help: ArgumentHelp("Wrap and delimit JSON output as an array"))
    public var jsonArray: Bool = false

    /// A transient handler for tool output; this acts as a temporary holder of output streams
    internal var streams: OutputHandler = OutputHandler()

    internal final class OutputHandler : Decodable {
        var out: WritableByteStream = stdoutStream
        var err: WritableByteStream = stderrStream

        func flush() {
            out.flush()
            err.flush()
        }

        /// The closure that will output a message
        func writeOut(_ output: String, newline: Bool = true) {
            //print(output, to: &out) // crashes compiler
            out.write(output + (newline ? "\n" : ""))
            if newline {
                out.flush()
            }
        }

        /// The closure that will output a message
        func writeMessage(_ output: ToolOutput, newline: Bool = true) {
            err.write(output.description  + (newline ? "\n" : ""))
            if newline {
                err.flush()
            }
        }

        /// The closure that will handle writing the output type to either the stream
        var yield: (MessageConvertible) -> () = { _ in }

        init() {
        }

        /// Not really decodable
        convenience init(from decoder: Decoder) throws {
            self.init()
        }
    }

    public init() {
    }

    /// Write the given message to the output streams buffer
    public func write(_ value: String) {
        streams.writeOut(value)
    }

    /// The output that comes at the beginning of a sequence of elements; an opening bracket, for JSON arrays
    public func beginCommandOutput() {
        if jsonArray { write("[") }
    }

    /// The output that comes at the end of a sequence of elements; a closing bracket, for JSON arrays
    public func endCommandOutput() {
        if jsonArray { write("]") }
    }

    /// The output that separates elements; a comma, for JSON arrays
    public func writeOutputSeparator() {
        if jsonArray { write(",") }
    }

    func writeOutput<T: MessageConvertible>(_ item: T) throws {
        if json || jsonCompact {
            try write(item.toJSON(outputFormatting: [.sortedKeys, .withoutEscapingSlashes, (jsonCompact ? .sortedKeys : .prettyPrinted)], dateEncodingStrategy: .iso8601).utf8String ?? "")
        } else {
            write(item.description)
        }
    }
}

