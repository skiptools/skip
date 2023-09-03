import Foundation
import ArgumentParser
import Universal
import TSCBasic
import SkipSyntax

public struct OutputOptions: ParsableArguments {
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

    @Flag(name: [.customShort("p"), .long], help: ArgumentHelp("Show no ANSI colors or progress animations"))
    var plain: Bool = false

    /// progress animation sequences
    static let progressAimations = [
        "⠙⠸⢰⣠⣄⡆⠇⠋", // clockwise line
        "⠐⢐⢒⣒⣲⣶⣷⣿⡿⡷⡧⠧⠇⠃⠁⠀⡀⡠⡡⡱⣱⣳⣷⣿⢿⢯⢧⠧⠣⠃⠂⠀⠈⠨⠸⠺⡺⡾⡿⣿⡿⡷⡗⡇⡅⡄⠄⠀⡀⡐⣐⣒⣓⣳⣻⣿⣾⣼⡼⡸⡘⡈⠈⠀", // fade
        "⣀⡠⠤⠔⠒⠊⠉⠑⠒⠢⠤⢄", // crawl up and down, tiny
        "⢇⢣⢱⡸⡜⡎", // vertical wobble up
        "⣾⣽⣻⢿⣿⣷⣯⣟⡿⣿", // alternating rain
        "⣀⣠⣤⣦⣶⣾⣿⡿⠿⠻⠛⠋⠉⠙⠛⠟⠿⢿⣿⣷⣶⣴⣤⣄", // crawl up and down, large
        "⣾⣷⣯⣽⣻⣟⡿⢿⣻⣟⣯⣽", // snaking
        "⠙⠚⠖⠦⢤⣠⣄⡤⠴⠲⠓⠋", // crawl up and down, small
        "⠄⡢⢑⠈⠀⢀⣠⣤⡶⠞⠋⠁⠀⠈⠙⠳⣆⡀⠀⠆⡷⣹⢈⠀⠐⠪⢅⡀⠀", // fireworks
        "⡀⣀⣐⣒⣖⣶⣾⣿⢿⠿⠯⠭⠩⠉⠁⠀", // swirl
        "⠁⠈⠐⠠⢀⡀⠄⠂", // clockwise dot
        "⠁⠋⠞⡴⣠⢀⠀⠈⠙⠻⢷⣦⣄⡀⠀⠉⠛⠲⢤⢀⠀", // falling water
        "⣾⣽⣻⢿⡿⣟⣯⣷", // counter-clockwise
        "⣾⣷⣯⣟⡿⢿⣻⣽", // clockwise
        "⣾⣷⣯⣟⡿⢿⣻⣽⣷⣾⣽⣻⢿⡿⣟⣯⣷", // bouncing clockwise and counter-clockwise
        "⡀⣄⣦⢷⠻⠙⠈⠀⠁⠋⠟⡾⣴⣠⢀⠀", // slide up and down
        "⡇⡎⡜⡸⢸⢱⢣⢇", // vertical wobble down
        "⠁⠐⠄⢀⢈⢂⢠⣀⣁⣐⣄⣌⣆⣤⣥⣴⣼⣶⣷⣿⣾⣶⣦⣤⣠⣀⡀⠀⠀", // snowing and melting
    ]

    /// A transient handler for tool output; this acts as a temporary holder of output streams
    internal var streams: OutputHandler = OutputHandler()

    public init() {
        let _ = Self.isFirstRun
    }

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
        var yield: (Either<MessageConvertible>.Or<Message>) -> () = { _ in }

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

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
extension OutputOptions {

    /// The characters for the current progress sequence
    private var progressSeq: [Character] {
        Self.progressAimations.first!.map({ $0 })
    }

    static func initialize() {
        checkFirstRun()
    }

    /// Write the given message to the output streams buffer
    func write(_ value: String, error: Bool = false, terminator: String = "\n", flush: Bool = false) {
        streams.write(error: error, output: output, value, terminator: terminator)
        if flush {
            if error {
                streams.err.flush()
            } else {
                streams.out.flush()
            }
        }
    }

    @discardableResult
    func run(_ message: String, flush: Bool = true, progress: Bool = true, _ args: [String], environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> (out: String, err: String) {
        let (out, err) = try await monitor(message, progress: progress) {
            //try await Process.checkNonZeroExit(arguments: args, environment: environment, loggingHandler: nil)

            let result = try await Process.popen(arguments: args, environment: environment, loggingHandler: nil)
            // Throw if there was a non zero termination.
            guard result.exitStatus == .terminated(code: 0) else {
                throw ProcessResult.Error.nonZeroExit(result)
            }
            let (out, err) = try (result.utf8Output(), result.utf8stderrOutput())
            return (out: out, err: err)
        }

        if flush { // write a final newline (since monitor does not
            write("", flush: true)
        }

        return (out, err)
    }

    static var isTerminal: Bool { isatty(fileno(stdout)) != 0 }

    /// Perform an operation with a given progress animation
    @discardableResult func monitor<T>(_ message: String, progress: Bool = Self.isTerminal, block: () async throws -> T) async throws -> T {
        var progressMonitor: Task<(), Error>? = nil

        @Sendable func clear(_ count: Int) {
            // clear the current line
            write(String(repeating: "\u{8}", count: count), terminator: "", flush: true)
        }

        if progress == false || plain == true {
            write(message)
        } else {
            progressMonitor = Task {
                var lastMessage: String? = nil
                func printMessage(_ char: Character) {
                    if let lastMessage = lastMessage {
                        clear(lastMessage.count)
                    }
                    lastMessage = "[\(char)] \(message)"
                    if let lastMessage = lastMessage {
                        write(lastMessage, terminator: "", flush: true)
                    }
                }

                while true {
                    for char in progressSeq {
                        printMessage(char)
//                        do {
//                            try await Task.sleep(for: .milliseconds(150))
//                        } catch {
//                            break // cancelled
//                        }
                        try Task.checkCancellation()
                        try await Task.sleep(for: .milliseconds(150))
                        try Task.checkCancellation()

                    }
                }
            }
        }

        do {
            let result = try await block()
            progressMonitor?.cancel() // cancel the progress task
            clear(message.count + 4)
            write("[✓] " + message, terminator: "", flush: true)
            return result
        } catch {
            progressMonitor?.cancel() // cancel the progress task
            clear(message.count + 4)
            write("[✗] " + message, flush: true)
            throw error
        }
    }

    static var isFirstRun: Bool = checkFirstRun()

    @discardableResult static func checkFirstRun() -> Bool {
        let cfg = home(".skiptools")

        defer {
            try? FileManager.default.createDirectory(atPath: cfg, withIntermediateDirectories: true)
            let env = cfg + "/skipkey.env"
            if !FileManager.default.fileExists(atPath: env) {
                try? """
                # Obtain a Skip key from https://skip.tools for the SKIPKEY property
                #SKIPKEY:
                """.write(toFile: env, atomically: true, encoding: .utf8)
            }
        }

        return FileManager.default.fileExists(atPath: cfg) == false
    }
}

