import Foundation
import SkipSyntax
import SwiftParser
import SwiftSyntax
import ArgumentParser
import SkipBuild
import Universal
import TSCBasic
import OSLog

/// The current versio of the tool
public let skipVersion = "0.0.40"

/// Command-line runner for the transpiler.
@main public struct Runner {
    static func main() async throws {
        try await mainNEW()
    }

    static func mainNEW() async throws {
        await SkipCommandExecutor.main()
    }

    static func mainOLD() async throws {
        let arguments = CommandLine.arguments
        if !arguments.isEmpty {
            try await run(Array(arguments.dropFirst())) // Drop executable argument
        }
    }

    /// Run the transpiler on the given arguments.
    public static func run(_ arguments: [String], out: WritableByteStream? = nil, err: WritableByteStream? = nil) async throws {
        var cmd = try SkipCommandExecutor.parseAsRoot(arguments) as! AsyncParsableCommand
        if var cmd = cmd as? any StreamingCommand {
            // set up error and output streams
            if let out = out {
                cmd.output.streams.out = out
            }
            if let err = err {
                cmd.output.streams.err = err
            }
            try await cmd.run()
        } else {
            try await cmd.run()
        }
    }

    public static func runOLD(_ arguments: [String]) async throws {
        let (action, options, files) = try processArguments(arguments)
        try await action.perform(on: files, options: options)
    }

    private static func processArguments(_ arguments: [String]) throws -> (Action, Options, [Source.File]) {
        var files: [Source.File] = []
        var action: Action?
        var options = Options()
        for argument in arguments {
            if argument == "-skippy" {
                action = SkippyAction()
            } else if argument == "-version" {
                action = PrintVersionAction()
            } else if argument == "-swiftAST" {
                action = PrintSwiftASTAction()
            } else if argument == "-skipAST" {
                action = PrintSkipASTAction()
            } else if argument.hasPrefix("-D") && argument.count > 2 {
                options.preprocessorSymbols.append(String(argument.dropFirst(2)))
            } else if argument.hasPrefix("-O") && argument.count > 2 {
                options.outputDirectory = String(argument.dropFirst(2))
            } else if argument.hasPrefix("-") {
                throw RunnerError(message: "Unrecognized option: \(argument)")
            } else {
                let source = Source.File(path: argument)
                if source.isSwift {
                    files.append(source)
                }
            }
        }

        if action == nil && files.isEmpty {
            print("skip \(skipVersion): no input files")
        }

        return (action ?? TranspileAction(), options, files)
    }
}

private protocol Action : AsyncParsableCommand {
    func perform(on sourceFiles: [Source.File], options: Options) async throws
}

private struct Options {
    var preprocessorSymbols: [String] = []
    var outputDirectory: String?
}

private struct TranspileAction: Action {
    public static var configuration = CommandConfiguration(commandName: "transpile", abstract: "transpile the sources")

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

private struct SkippyAction: Action {
    public static var configuration = CommandConfiguration(commandName: "skippy", abstract: "run the skippy processor")

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
    /// - Warning: This is duplicated in SkippyTool.
    func outputFileURL(for sourceFile: Source.File, in outputDir: URL) -> URL {
        var outputFileName = sourceFile.name
        if outputFileName.hasSuffix(".swift") {
            outputFileName = String(outputFileName.dropLast(".swift".count))
        }
        outputFileName += "_skippy.swift"
        return outputDir.appendingPathComponent(outputFileName)
    }
}

private struct PrintSwiftASTAction: Action {
    public static var configuration = CommandConfiguration(commandName: "ast-swift", abstract: "print the swift AST")

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
    public static var configuration = CommandConfiguration(commandName: "ast-skip", abstract: "print the skip AST")

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

private struct PrintVersionAction: Action {
    func perform(on sourceFiles: [Source.File], options: Options) async throws {
        print("skip version \(skipVersion)")
    }
}


public struct SkipCommandExecutor : AsyncParsableCommand {
    public static let experimental = false
    public static var configuration = CommandConfiguration(commandName: "skip",
                                                           abstract: "the skip tool",
                                                           shouldDisplay: !experimental,
                                                           subcommands: [
                                                            VersionCommand.self,
                                                            SkippyAction.self,
                                                            TranspileAction.self,
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
                                                           abstract: "Show the skip version",
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
        Output()
    }
}

extension Never : MessageConvertible {
    public var description: String {
        "never"
    }
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
        //msg(.info, "skip version \(skipVersion)")
        yield(try await executeCommand())
    }
}


/// A type that can be output in a sequence of messages
public protocol MessageConvertible : Encodable & CustomStringConvertible {

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

        self.output.streams.msg(ToolOutput(kind: kind, message: message()))
    }
}

public extension StreamingCommand {
    mutating func run() async throws {
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
        var out: WritableByteStream = TSCBasic.stdoutStream
        var err: WritableByteStream = TSCBasic.stderrStream

        func flush() {
            out.flush()
            err.flush()
        }

        /// The closure that will output a message
        func msg(_ output: ToolOutput) {
            err.write(output.message)
        }

        /// The closure that will handle writing the output type to either the stream
        var yield: (Encodable & CustomStringConvertible) -> () = { _ in }

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
        streams.out.write(value)
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

    func writeOutput<T: Encodable & CustomStringConvertible>(_ item: T) throws {
        if json || jsonCompact {
            try write(item.toJSON(outputFormatting: [.sortedKeys, .withoutEscapingSlashes, (jsonCompact ? .sortedKeys : .prettyPrinted)], dateEncodingStrategy: .iso8601).utf8String ?? "")
        } else {
            write(item.description)
        }
    }
}

