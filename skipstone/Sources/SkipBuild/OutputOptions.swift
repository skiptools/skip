import Foundation
import ArgumentParser
import Universal
import TSCBasic
import SkipSyntax

public protocol OutputOptionsCommand : ParsableArguments {
    /// This command's output options
    var outputOptions: OutputOptions { get }
}

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
    
    @Flag(name: [.customShort("M"), .long], help: ArgumentHelp("Show console messages as plain text rather than JSON"))
    var messagePlain: Bool = false

    @Flag(name: [.customShort("A"), .long], help: ArgumentHelp("Wrap and delimit JSON output as an array"))
    var jsonArray: Bool = false

    @Flag(name: [.long], inversion: .prefixedNo, help: ArgumentHelp("Show no colors or progress animations"))
    var plain: Bool = ProcessInfo.processInfo.environment["TERM"] == "dumb" || ProcessInfo.processInfo.environment["TERM"] == nil || ProcessInfo.processInfo.environment["CI"] != nil // try to auto-detect when we shouldn't be using ANSI colors

    static var isTerminal: Bool { isatty(fileno(stdout)) != 0 }

    /// progress animation sequences
    static let progressAimations = [
        "⡀⣄⣦⢷⠻⠙⠈⠀⠁⠋⠟⡾⣴⣠⢀⠀", // slide up and down
        "⠙⠚⠖⠦⢤⣠⣄⡤⠴⠲⠓⠋", // crawl up and down, small
        "⠁⠋⠞⡴⣠⢀⠀⠈⠙⠻⢷⣦⣄⡀⠀⠉⠛⠲⢤⢀⠀", // falling water
        "⣀⣠⣤⣦⣶⣾⣿⡿⠿⠻⠛⠋⠉⠙⠛⠟⠿⢿⣿⣷⣶⣴⣤⣄", // crawl up and down, large
        "⠙⠸⢰⣠⣄⡆⠇⠋", // clockwise line
        "⠐⢐⢒⣒⣲⣶⣷⣿⡿⡷⡧⠧⠇⠃⠁⠀⡀⡠⡡⡱⣱⣳⣷⣿⢿⢯⢧⠧⠣⠃⠂⠀⠈⠨⠸⠺⡺⡾⡿⣿⡿⡷⡗⡇⡅⡄⠄⠀⡀⡐⣐⣒⣓⣳⣻⣿⣾⣼⡼⡸⡘⡈⠈⠀", // fade
        "⣀⡠⠤⠔⠒⠊⠉⠑⠒⠢⠤⢄", // crawl up and down, tiny
        "⢇⢣⢱⡸⡜⡎", // vertical wobble up
        "⣾⣽⣻⢿⣿⣷⣯⣟⡿⣿", // alternating rain
        "⣾⣷⣯⣽⣻⣟⡿⢿⣻⣟⣯⣽", // snaking
        "⡀⣀⣐⣒⣖⣶⣾⣿⢿⠿⠯⠭⠩⠉⠁⠀", // swirl
        "⠁⠈⠐⠠⢀⡀⠄⠂", // clockwise dot
        "⣾⣽⣻⢿⡿⣟⣯⣷", // counter-clockwise
        "⣾⣷⣯⣟⡿⢿⣻⣽", // clockwise
        "⣾⣷⣯⣟⡿⢿⣻⣽⣷⣾⣽⣻⢿⡿⣟⣯⣷", // bouncing clockwise and counter-clockwise
        "⡇⡎⡜⡸⢸⢱⢣⢇", // vertical wobble down
        "⠁⠐⠄⢀⢈⢂⢠⣀⣁⣐⣄⣌⣆⣤⣥⣴⣼⣶⣷⣿⣾⣶⣦⣤⣠⣀⡀⠀⠀", // snowing and melting
    ]

    /// A transient handler for tool output; this acts as a temporary holder of output streams
    internal var streams: OutputHandler = OutputHandler()

    /// The terminal implementation to use for colorization of console output
    var term: Term {
        plain ? Term.plain : Term.ansi
    }

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
        var yield: (Either<MessageConvertible & Encodable>.Or<Message>) -> () = { _ in }

        init() {
        }

        /// Not really decodable
        convenience init(from decoder: Decoder) throws {
            self.init()
        }
    }

    /// Write the given message to the output streams buffer
    internal func write(_ value: String) {
        streams.write(error: false, output: output, value)
    }

    /// The output that comes at the beginning of a sequence of elements; an opening bracket, for JSON arrays
    internal func beginCommandOutput() {
        if jsonArray { write("[") }
    }

    /// The output that comes at the end of a sequence of elements; a closing bracket, for JSON arrays
    internal func endCommandOutput() {
        if jsonArray { write("]") }
    }

    /// The output that separates elements; a comma, for JSON arrays
    internal func writeOutputSeparator() {
        if jsonArray { write(",") }
    }

    /// Whether tool output should be emitted as JSON or not
    var emitJSON: Bool { json || jsonCompact }

    func writeOutput<T: MessageConvertible & Encodable>(_ item: T, error: Bool) throws {
        if emitJSON {
            try streams.write(error: false, output: output, item.toJSON(outputFormatting: [.sortedKeys, .withoutEscapingSlashes, (jsonCompact ? .sortedKeys : .prettyPrinted)], dateEncodingStrategy: .iso8601).utf8String ?? "")
        } else {
            if let messageString = item.message(term: self.term) {
                streams.write(error: messageErrout == true ? false : error, output: output, messageString)
            }
        }
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
extension OutputOptions {

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
    func run(_ message: String, flush: Bool = true, _ args: [String], environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> (out: String, err: String) {
        try await monitor(message) {
            let result = try await Process.popen(arguments: args, environment: environment, loggingHandler: nil)
            // Throw if there was a non zero termination.
            guard result.exitStatus == .terminated(code: 0) else {
                throw ProcessResult.Error.nonZeroExit(result)
            }
            let (out, err) = try (result.utf8Output(), result.utf8stderrOutput())
            return (out: out, err: err)
        }
    }

    func monitorPrefix<T>(_ progressCharacters: String?, for result: Result<T, Error>?, startTime: Date) -> String {
        switch result {
        case .success: 
            return "[" + term.green("✓") + "]"
        case .failure:
            return "[" + term.red("✗") + "]"
        case .none:
            let pseq = progressCharacters ?? "…" // fall back to a single ellipsis if no progress sequence is specified
            // use an ease-out animation to start the progress spinner quick and then slow it down as time progresses
            let t = Date.now.timeIntervalSince(startTime)
            
            let mag = 100_000
            let factor = 1.0 / 1.5 // sqrt timing factor; 1.5 is a good slowdown rate
            let cidx = (Int(pow(t * 100.0, factor)) * mag) % (pseq.count * mag) / mag
            let pchar = pseq[pseq.index(pseq.startIndex, offsetBy: cidx)]
            return "[" + term.yellow(String(pchar)) + "]"
        }
    }

    /// Perform an operation with a given message handler, which will be invoked in the progress cycle with a nil result, and then a final time with the result of the block invocation
    ///
    /// If we are using a rich terminal (and no specifying plain or JSON output), when output a progress animation while waiting for the given process to complete
    @discardableResult func monitor<T>(_ message: String, block: @escaping () async throws -> T, messageHandler handler: ((Result<T, Error>?) -> String)? = nil) async throws -> T {
        let startTime = Date.now
        let progress = (self.emitJSON == false && self.messagePlain == false && self.plain == false) ? Self.progressAimations.first : nil
        let progressMonitor: Task<(), Error>?
        if progress == nil {
            progressMonitor = nil
        } else {
            progressMonitor = Task {
                var lastMessage: String? = nil
                /// The default implementation of the message handler cycles through the default progress animation and then outputs the result
                let messageHandler = handler ?? { result in
                    // the progress index is based on the current time index
                    monitorPrefix(progress, for: result, startTime: startTime) + " " + message
                }

                func printMessage() -> Int {
                    let newMessage = messageHandler(nil)
                    if newMessage == lastMessage {
                        // the messages are exactly the same, so don't clear the console and print the message again
                        return 0
                    } else {
                        lastMessage = newMessage
                        write(newMessage, terminator: "", flush: true)
                        return newMessage.count
                    }
                }

                while true {
                    let printed = printMessage()
                    defer {
                        // clear the current line; we explicitly do not flush so the cursor doesn't jump around
                        write(String(repeating: "\u{8}", count: printed), terminator: "", flush: false)
                    }
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
        }

        let resultTask = Task {
            // Capture the async block as a Result
            await {
                defer {
                    // after the task completes, stop the progress monitor
                    progressMonitor?.cancel()
                }
                do {
                    return .success(try await block())
                } catch {
                    return .failure(error)
                }
            }() as Result<T, Error>
        }

        let result = await resultTask.value

        // wait for the progress monitor to clear the final line, which it will do when it sees that the result is complete
        _ = try? await progressMonitor?.value

        // now output the final result message
        //write(messageHandler(result), terminator: "", flush: true)
        return try result.get()
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

struct ProcessDidNotLaunchError : LocalizedError {
    var errorDescription: String?
}
