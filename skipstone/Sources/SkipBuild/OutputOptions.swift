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

        private var _currentOutput: (line: String?, lock: NSLock) = (nil, NSLock())

        /// Returns the current output line, optionally also setting it; guarded behind a lock
        @discardableResult func currentOutputLine(set line: String? = nil, reset: Bool = false) -> String? {
            _currentOutput.lock.lock()
            defer { _currentOutput.lock.unlock() }
            if reset || line != nil { _currentOutput.line = line }
            return _currentOutput.line
        }


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
        func writeStream(error: Bool, output: String?, _ message: String, terminator: String = "\n") {
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

    public func stripANSIAttributes(from text: String) -> String {
        guard !text.isEmpty else { return text }

        // ANSI attribute is always started with ESC and ended by `m`
        var txt = text.split(separator: Term.Color.esc)
        for (i, sub) in txt.enumerated() {
            if let end = sub.firstIndex(of: "m") {
                txt[i] = sub[sub.index(after: end)...]
            }
        }
        return txt.joined()
    }

    /// Write the given message to the output streams buffer
    private func writeOutput(_ value: String, error: Bool = false, terminator: String = "\n", flush: Bool = false) {
        streams.writeStream(error: error, output: output, value, terminator: terminator)
        if flush {
            if error {
                streams.err.flush()
            } else {
                streams.out.flush()
            }
        }
    }

    /// The output that comes at the beginning of a sequence of elements; an opening bracket, for JSON arrays
    internal func beginCommandOutput() {
        if jsonArray { writeOutput("[") }
    }

    /// The output that comes at the end of a sequence of elements; a closing bracket, for JSON arrays
    internal func endCommandOutput() {
        if jsonArray { writeOutput("]") }
    }

    /// The output that separates elements; a comma, for JSON arrays
    internal func writeOutputSeparator() {
        if jsonArray { writeOutput(",") }
    }

    /// Whether tool output should be emitted as JSON or not
    var emitJSON: Bool { json || jsonCompact }

    func writeOutput<T: MessageConvertible & Encodable>(_ item: T, error: Bool) throws {
        if emitJSON {
            try streams.writeStream(error: false, output: output, item.toJSON(outputFormatting: [.sortedKeys, .withoutEscapingSlashes, (jsonCompact ? .sortedKeys : .prettyPrinted)], dateEncodingStrategy: .iso8601).utf8String ?? "")
        } else {
            if let messageString = item.message(term: self.term) {
                streams.writeStream(error: messageErrout == true ? false : error, output: output, messageString)
            }
        }
    }
}

/// The result of a process, with a code, standard out, and standard error
typealias ProcessOutput = (exitCode: Int, stdout: String, stderr: String)

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
extension OutputOptions {

    static func initialize() {
        checkFirstRun()
    }
    
    /// Executes a process with the given arguments and prefix message, waits for the result while showing a progress animation,
    /// and then processes the result and outputs the given message block.
    @discardableResult func run(with messenger: Messenger, _ message: String, _ args: [String], environment: [String: String] = ProcessInfo.processInfo.environment, watch: Bool = true, resultHandler: @escaping MessageResultHandler<ProcessOutput> = { ($0, nil) }) async -> Result<ProcessOutput, Error> {
        await monitor(with: messenger, message, watch: watch, resultHandler: resultHandler) { outputHandler in
            //let result = try await Process.popen(arguments: args, environment: environment, loggingHandler: outputHandler)
            var outBufferComplete: [UInt8] = []
            var outBuffer: [UInt8] = []
            var errBufferComplete: [UInt8] = []
            var errBuffer: [UInt8] = []
            let newline = UnicodeScalar("\n")

            // both stdout and stderr go the an output buffer; when there are any newlines available in the buffer, flush it
            func addBuffer(err: Bool) -> (_ bytes: [UInt8]?) -> () {
                return { bytes in
                    if err {
                        errBufferComplete += bytes ?? []
                    } else {
                        outBufferComplete += bytes ?? []
                    }
                    var buffer = err ? errBuffer : outBuffer
                    defer {
                        // set the correct buffer
                        if err {
                            errBuffer = buffer
                        } else {
                            outBuffer = buffer
                        }
                    }
                    buffer.append(contentsOf: bytes ?? [])
                    // output each string ending in a newline
                    while let nlindex = bytes == nil ? buffer.endIndex : buffer.firstIndex(where: { UnicodeScalar($0) == newline }) {
                        let lstr = buffer.prefix(nlindex)
                        buffer.removeFirst(nlindex + (bytes == nil ? 0 : 1))
                        if !lstr.isEmpty,
                           let str = String(bytes: lstr, encoding: .utf8) {
                            outputHandler(str)
                        }
                        if bytes == nil {
                            break // just a flush
                        }
                    }
                }
            }

            let process = Process(arguments: args, environment: environment, outputRedirection: .stream(stdout: addBuffer(err: false), stderr: addBuffer(err: true)), loggingHandler: nil)
            try process.launch()
            let result = try await process.waitUntilExit()
            // flush the final output buffers
            addBuffer(err: true)(nil)
            addBuffer(err: false)(nil)

            let code: Int
            switch result.exitStatus {
            case .terminated(let c): code = Int(c)
            #if os(Windows)
            case .abnormal(let c): code = Int(c)
            #else
            case .signalled(let c): code = Int(c)
            #endif
            }
            //let (out, err) = try (result.utf8Output(), result.utf8stderrOutput())
            //return (exitCode: code, stdout: out, stderr: err)
            return (exitCode: code, stdout: String(bytes: outBufferComplete, encoding: .utf8) ?? "", stderr: String(bytes: errBufferComplete, encoding: .utf8) ?? "")
        }
    }

    func monitorPrefix(_ progressCharacters: String?, for status: MessageBlock.Status?, startTime: Date) -> String? {
        if let status = status {
            return status.prefix(term)
        }
        let pseq = progressCharacters ?? "…" // fall back to a single ellipsis if no progress sequence is specified
        // use an ease-out animation to start the progress spinner quick and then slow it down as time progresses
        let t = Date.now.timeIntervalSince(startTime)

        let mag = 100_000
        let factor = 1.0 / 1.5 // sqrt timing factor; 1.5 is a good slowdown rate
        let cidx = (Int(pow(t * 100.0, factor)) * mag) % (pseq.count * mag) / mag
        let pchar = pseq[pseq.index(pseq.startIndex, offsetBy: cidx)]
        return "[" + term.cyan(String(pchar)) + "] "
    }

    /// Perform an operation with a given message handler, which will be invoked in the progress cycle with a nil result, and then a final time with the result of the block invocation
    ///
    /// If we are using a rich terminal (and not specifying plain or JSON output), outputs a progress animation while waiting for the given process to complete
    @discardableResult func monitor<T>(with messenger: Messenger, _ message: String, watch: Bool = false, resultHandler: MessageResultHandler<T>?, block monitorAction: @escaping (_ outputHandler: @escaping (String) -> ()) async throws -> T) async -> Result<T, Error> {
        self.streams.currentOutputLine(reset: true) // reset the output line buffer

        let terminalWidth = TerminalController.terminalWidth()

        let startTime = Date.now
        let progress = (self.emitJSON == false && self.messagePlain == false && self.plain == false) ? Self.progressAimations.first : nil

        /// The default implementation of the message handler cycles through the default progress animation and then outputs the result
        let messageHandler: ((Result<T, Error>?) -> String) = { result in
            let prefix = monitorPrefix(progress, for: result?.messageStatus, startTime: startTime)
            if let result = result, let msg = resultHandler?(result) {
                return msg.message.message(term: term) ?? ((prefix ?? "") + message)
            } else {
                // the progress index is based on the current time index
                return (prefix ?? "") + message
            }
        }

        let progressMonitor: Task<(), Error>?
        if progress == nil {
            progressMonitor = nil
        } else {
            progressMonitor = Task {
                var lastMessage: String? = nil
                func printMessage() -> String? {
                    let newMessage = messageHandler(nil)
                    if newMessage == lastMessage {
                        // the messages are exactly the same, so don't clear the console and print the message again
                        return nil
                    } else {
                        var msg = newMessage
                        if watch == true, let statusLine = self.streams.currentOutputLine(), !statusLine.isEmpty {
                            var status = statusLine.trimmingCharacters(in: .whitespacesAndNewlines)
                            let msglen = stripANSIAttributes(from: msg).count // need to remove any ANSI characters in the prefix to match the terminal output width

                            if let width = terminalWidth, width > 0, (status.count + msglen + 2) > width {
                                let swidth = Int(floor(Double(width) - Double(msglen) - 2.0) / 2.0)
                                // middle truncation for highlighted commands
                                status = String(status.slice(0, swidth - 1) + "…" + status.slice(status.count - swidth))
                            }

                            msg += ": " + term.cyan(status)
                        }
                        // the last message is the truncated message, so we can erase it
                        writeOutput(msg, terminator: "", flush: true)
                        lastMessage = msg
                        return msg
                    }
                }

                while true {
                    let printed = printMessage()?.count ?? 0
                    defer {
                        // clear the current line; we explicitly do not flush so the cursor doesn't jump around
                        writeOutput(String(repeating: "\u{8}", count: printed), terminator: "", flush: false)

                        // also clear the line ahead
                        writeOutput("\u{001B}[2K", terminator: "", flush: false)
                    }
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
        }

        let resultTask = Task.detached {
            // Capture the async monitorAction as a Result
            await {
                do {
                    let result = try await monitorAction({ line in
                        streams.currentOutputLine(set: line) // remember the current output line
                    })

                    return .success(result)
                } catch {
                    return .failure(error)
                }
            }() as Result<T, Error>
        }

        let result = await resultTask.value

        if let progressMonitor = progressMonitor {

            // wait for the progress monitor to clear the final line, which it will do once cancelled
            progressMonitor.cancel()
            _ = try? await progressMonitor.value // wait for compltion
            // send the final message to the output stream
            writeOutput(messageHandler(result), terminator: "\n", flush: true) // output the final result message
        } else {
            // send the final message to the block
            if let msg = resultHandler?(result) {
                messenger.yield(msg.message)
                //messenger.yield(MessageBlock(status: .pass, message))
            }
        }

        return result
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

extension Result {
    var messageStatus: MessageBlock.Status {
        switch self {
        case .success: return .pass
        case .failure: return .fail
        }
    }
}

struct ProcessDidNotLaunchError : LocalizedError {
    var errorDescription: String?
}
