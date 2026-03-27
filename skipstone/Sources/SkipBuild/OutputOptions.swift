// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ArgumentParser
import Universal
import TSCBasic
import SkipSyntax

/// A command type that contains a `outputOptions: OutputOptions` accessor.
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

    @Option(name: [.long], help: ArgumentHelp("Send log output to the file", valueName: "path"))
    var logFile: String?

    @Flag(name: [.customShort("A"), .long], help: ArgumentHelp("Wrap and delimit JSON output as an array"))
    var jsonArray: Bool = false

    @Flag(name: [.long], inversion: .prefixedNo, help: ArgumentHelp("Show no colors or progress animations"))
    var plain: Bool = ProcessInfo.processInfo.environment["TERM"] == "dumb" || ProcessInfo.processInfo.environment["TERM"] == nil || ProcessInfo.processInfo.environment["CI"] != nil // try to auto-detect when we shouldn't be using ANSI colors

    static var isTerminal: Bool { isatty(fileno(stdout)) != 0 }

    /// Returns the sprite string that should be used to display progress, only if not emitting JSON, plain output, or in verbose mode.
    ///
    /// The chosen string will be picked based on a stable hash of the key, which can be anything (like a header message). In that way, the progress sequence will be random, but will be stable between runs.
    func progressSprites(for key: String) -> String? {
        if emitJSON == true || verbose == true || plain == true {
            return nil
        }

        /// A basic stable hash function
        func simpleHash(_ input: String) -> UInt32 {
            input.unicodeScalars.reduce(0) { hash, char in 31 &* hash &+ char.value }
        }

        let hash = Int(simpleHash(key))
        return Self.progressSprites[hash % Self.progressSprites.count]
    }

    /// Progress animation sprite sequences to entertain patient developers.
    private static let progressSprites = [
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
        Self.checkFirstRun()
    }

    internal final class OutputHandler : Decodable {
        var out: WritableByteStream = stdoutStream
        var err: WritableByteStream = stderrStream
        var outFile: LocalFileOutputByteStream? = nil
        var logFile: LocalFileOutputByteStream? = nil
        private let logFileLock = NSLock()

        private var _currentOutput: (lines: [String], lock: NSLock) = ([], NSLock())

        /// Returns the current output line, optionally also setting it; guarded behind a lock
        @discardableResult func outputBuffer(add line: String? = nil, reset: Bool = false) -> [String] {
            _currentOutput.lock.lock()
            defer { _currentOutput.lock.unlock() }
            if let line = line {
                _currentOutput.lines.append(line)
            }
            defer {
                if reset {
                    // clear the output buffer after we have returned the current lines
                    _currentOutput.lines.removeAll(keepingCapacity: true)
                }
            }
            return _currentOutput.lines
        }

        func fileStream(for outputPath: String?) -> LocalFileOutputByteStream? {
            guard let outputPath else { return nil }
            if let file = outFile { return file }
            do {
                let path = try AbsolutePath(validating: outputPath)
                self.outFile = try LocalFileOutputByteStream(path)
                return self.outFile
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

        /// The closure that will output a message to the log file, if it has been configured for the current operation
        func writeLog(_ message: String, terminator: String = "\n") {
            if let stream = self.logFile {
                logFileLock.withLock {
                    stream.write(message + terminator)
                    if !terminator.isEmpty { stream.flush() }
                }
            }
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
    fileprivate func writeString(_ value: String, error: Bool = false, terminator: String = "\n", flush: Bool = false) {
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
        if jsonArray { writeString("[") }
    }

    /// The output that comes at the end of a sequence of elements; a closing bracket, for JSON arrays
    internal func endCommandOutput() {
        if jsonArray { writeString("]") }
    }

    /// The output that separates elements; a comma, for JSON arrays
    internal func writeOutputSeparator() {
        if jsonArray { writeString(",") }
    }

    /// Whether tool output should be emitted as JSON or not
    var emitJSON: Bool { json || jsonCompact }

    func writeOutput<T: MessageConvertible & Encodable>(_ item: T, error: Bool) throws {
        if emitJSON {
            try streams.writeStream(error: false, output: output, item.toJSON(outputFormatting: [.sortedKeys, .withoutEscapingSlashes, (jsonCompact ? .sortedKeys : .prettyPrinted)], dateEncodingStrategy: .iso8601).utf8String ?? "")
        } else {
            if !item.squelch, let messageString = item.message(term: self.term) {
                streams.writeStream(error: messageErrout == true ? false : error, output: output, messageString)
            }
        }
    }
}

/// The result of a process, with a code, standard out, and standard error
struct ProcessOutput {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    func throwOnFailure() throws {
        if exitCode != 0 {
            throw ProcessFailureError(code: exitCode, errorDescription: scanErrorLine() ?? "Command failed with exit code \(exitCode)")
        }
    }

    /// Scan for common error patterns in the stderr and stdout
    func scanErrorLine() -> String? {
        let lines = (stdout + "\n" + stderr).split(separator: "\n")
        let errors = lines.compactMap { line -> String? in
            let l = line.lowercased()
            if l.hasPrefix("error: ")
                || l.hasPrefix("e: ") // Gradle error message
                || l.contains(": error: ") { // Xcode-formatted error message
                return String(line)
            }
            if l.hasPrefix("adb: ") { // ADB error message
                if line.contains("more than one device/emulator") {
                    return line + " — set ANDROID_SERIAL to specify a target (use `adb devices` to list)"
                }
                return String(line)
            }
            return nil
        }
        if errors.isEmpty {
            return nil // no error found
        }

        return errors.joined(separator: "\n")
    }

    struct ProcessFailureError: LocalizedError {
        let code: Int32
        let errorDescription: String?
    }
}

extension Date {
    /// The number of seconds since the given date
    var timingSecondsSinceNow: String {
        "\(round(-timeIntervalSinceNow * 100.0) / 100.0)s"
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
extension StreamingCommand {

    func resultString(_ result: Result<String, Error>?) -> String {
        guard let result = result else {
            return ""
        }

        do {
            //return try outputOptions.term.green(result.get())
            return try result.get()
        } catch {
            return outputOptions.term.red(error.localizedDescription)
        }
    }

    /// A simple result handler that just reports the amount of time the operation tool
    static func timingResultHandler<T>(message: String, time: Date = .now, permitFailure: Bool) -> (_ result: Result<T, Error>?) -> (result: Result<T, Error>?, message: MessageBlock?) {
        return { result in
            (result, MessageBlock(status: permitFailure ? .pass : result?.messageStatusAny, message + " (\(time.timingSecondsSinceNow))"))
        }
    }

    func findToolPath(for tool: String) throws -> String {
        if let toolCommand = self as? ToolOptionsCommand {
            return try toolCommand.toolOptions.toolPath(for: tool)
        }
        return try URL.findCommandInPath(toolName: tool, withAdditionalPaths: ProcessInfo.isARM ? ["/opt/homebrew/bin"] : ["/usr/local/bin"]).path

    }

    /// Executes a tool with the given arguments and prefix message, waits for the result while showing a progress animation,
    /// and then processes the result and outputs the given message block.
    @discardableResult func run(with messenger: MessageQueue, _ message: String, _ commandArgs: [String], environment: [String: String] = ProcessInfo.processInfo.environmentWithDefaultToolPaths, additionalEnvironment: [String: String] = [:], in workingDirectory: URL? = nil, watch: Bool = true, permitFailure: Bool = false, resultHandler finalResultHandler: MessageResultHandler<ProcessOutput>? = nil) async throws -> Result<ProcessOutput, Error> {

        // default to a result handler that outputs the duration of the operation
        let resultHandler = finalResultHandler ?? Self.timingResultHandler(message: message, permitFailure: permitFailure)

        var cmd = commandArgs.first ?? ""
        // attempt to resolve the tool command if it is not prefixed with a slash
        if !cmd.hasPrefix("/") {
            cmd = try findToolPath(for: cmd)
        }

        let args = [cmd] + commandArgs.dropFirst()

        // write the command output directly to stderr
        self.outputOptions.logMessage("executing command\(workingDirectory == nil ? "" : " in \(workingDirectory!.path)"): \(args.joined(separator: " "))")

        let result: Result<ProcessOutput, Error> = await outputOptions.monitor(with: messenger, message, watch: watch, resultHandler: resultHandler) { outputHandler in
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

            // add all the additional environment settings to the dictionary
            var env = ProcessEnvironmentBlock(environment)
            for (key, value) in additionalEnvironment {
                env[ProcessEnvironmentKey(key)] = value
            }

            // Process has a constructor with a non-optional working dirctory, and another constructor without one, but no constructor that accepts an optional, so we have to create it in one of two separate paths
            let process = workingDirectory != nil
                ? Process(arguments: args, environmentBlock: env, workingDirectory: try workingDirectory!.absolutePath, outputRedirection: .stream(stdout: addBuffer(err: false), stderr: addBuffer(err: true)), loggingHandler: nil)
                : Process(arguments: args, environmentBlock: env, outputRedirection: .stream(stdout: addBuffer(err: false), stderr: addBuffer(err: true)), loggingHandler: nil)


            try process.launch()
            let result = try await process.waitUntilExit()

            let code: Int32
            switch result.exitStatus {
            case .terminated(let c): code = Int32(c)
#if os(Windows)
            case .abnormal(let c): code = Int32(c)
#else
            case .signalled(let c): code = Int32(c)
#endif
            }

            // flush the final output buffers
            addBuffer(err: true)(nil)
            addBuffer(err: false)(nil)

            let output = ProcessOutput(exitCode: permitFailure ? 0 : code, stdout: String(bytes: outBufferComplete, encoding: .utf8) ?? "", stderr: String(bytes: errBufferComplete, encoding: .utf8) ?? "")
            try output.throwOnFailure()
            return output
        }

        if self.failFast {
            // this will cause a failure to surface as an error and halt the process
            _ = try result.get() // .throwOnFailure()
        }

        return result
    }
}

extension OutputOptions {
    /// Logs a message, either to standard error (if verbose is `true`), or to the log stream if it is active
    func logMessage(_ line: String) {
        if verbose {
            // write to standard out when verbose is true
            writeString(line, error: true, flush: true)
        }

        streams.writeLog(line)
    }

    func monitorPrefix(_ progressCharacters: String?, for status: MessageBlock.Status?, startTime: Date) -> String? {
        if let status = status {
            return status.prefix(self.term)
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

    func defaultResultHandler<T>(message: String) -> (_ result: Result<T, Error>?) -> (result: Result<T, Error>?, message: MessageBlock?) {
        return { result in
            guard let result = result else {
                return (result, MessageBlock(status: result?.messageStatusAny, message))
            }

            do {
                let resultString = try result.get()
                return (result, MessageBlock(status: result.messageStatusAny, message + ": " + String(describing: resultString)))
            } catch {
                return (result, MessageBlock(status: result.messageStatusAny, message + ": " + term.red(error.localizedDescription)))
            }
        }
    }

    /// Perform an operation with a given message handler, which will be invoked in the progress cycle with a nil result, and then a final time with the result of the block invocation
    ///
    /// If we are using a rich terminal (and not specifying plain or JSON output), outputs a progress animation while waiting for the given process to complete
    @discardableResult func monitor<T>(with messenger: MessageQueue, _ message: String, watch: Bool = false, resultHandler rhandler: MessageResultHandler<T>? = nil, monitorAction: @escaping (_ outputHandler: @escaping (String) -> ()) async throws -> T) async -> Result<T, Error> {
        _ = self.streams.outputBuffer(reset: true) // reset the output line buffer
        let terminalWidth = TerminalController.terminalWidth()

        let resultHandler = rhandler ?? defaultResultHandler(message: message)

        let startTime = Date.now

        func clearLine() {
            writeString(clearLineString + "\r", terminator: "", flush: false)
        }

        var progressMonitor: Task<(), Error>? = nil
        if let progressSprites = self.progressSprites(for: message) {
            progressMonitor = Task {
                var lastMessage: String? = nil

                /// The default implementation of the message handler cycles through the default progress animation and then outputs the result
                func animatingMessageHandler(_ result: Result<T, Error>?) -> String {
                    let prefix = monitorPrefix(progressSprites, for: result?.messageStatusAny, startTime: startTime)
                    if let result = result {
                        let msg = resultHandler(result)
                        return msg.message.message(term: term) ?? ((prefix ?? "") + message)
                    } else {
                        // the progress index is based on the current time index
                        return (prefix ?? "") + message
                    }
                }

                @discardableResult func printMessage() -> String? {
                    let newMessage = animatingMessageHandler(nil)
                    if newMessage == lastMessage {
                        // the messages are exactly the same, so don't clear the console and print the message again
                        return nil
                    } else {
                        let outputBufferLines = self.streams.outputBuffer()
                        var msg = newMessage
                        if watch == true, let statusLine = outputBufferLines.last, !statusLine.isEmpty {
                            var status = statusLine.trimmingCharacters(in: .whitespacesAndNewlines)
                            let msglen = Term.stripANSIAttributes(from: msg).count // need to remove any ANSI characters in the prefix to match the terminal output width

                            if let width = terminalWidth, width > 0, msglen > width {
                                let swidth = Int(floor(Double(width) - Double(msglen) - 2.0) / 2.0)
                                // command output itself too wide; middle-truncate it
                                msg = String(msg.slice(0, swidth - 1) + "…" + status.slice(msglen - swidth))
                            } else {
                                if let width = terminalWidth, width > 0, (status.count + msglen + 2) > width {
                                    let swidth = Int(floor(Double(width) - Double(msglen) - 2.0) / 2.0)
                                    // middle truncation for highlighted commands
                                    status = String(status.slice(0, swidth - 1) + "…" + status.slice(status.count - swidth))
                                }
                                msg += ": " + term.cyan(status)
                            }
                        }
                        // the last message is the truncated message, so we can erase it
                        writeString(msg, terminator: "", flush: true)
                        lastMessage = msg
                        return msg
                    }
                }

                while !Task.isCancelled {
                    printMessage()
                    defer {
                        // clear the current line, as well as the line ahead
                        // this will happen one last time when we are cancelled with a CancellationError
                        //writeString(String(repeating: "\u{8}", count: printed) + "\u{001B}[2K", terminator: "", flush: false)
                        clearLine()
                    }
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
        }

        let resultTask = Task {
            // Capture the async monitorAction as a Result
            await {
                do {
                    let result = try await monitorAction({ line in
                        logMessage(line)
                        streams.outputBuffer(add: line) // remember the current output line
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
        }

        streams.outputBuffer(reset: true) // clear the current output buffer

        func postMessage(_ message: MessageBlock) async {
            var msg = message
            if progressMonitor != nil {
                // when we are using a terminal progress monitor, we do not post to the messenger but instead write it immediately
                // this is because the message queue is async and might print the result after the next check has started,
                // which can garble the output
                writeString(message.message(term: term) ?? "", flush: true)
                msg.squelch = true
            }
            await messenger.yield(msg)
        }

        // send the final message to the block
        let resultHandled = resultHandler(result)
        if let msgmsg = resultHandled.message { // the result handler specifies a message to issue
            await postMessage(msgmsg)
        } else { // otherwise translate the result
            var messageWithError = message
            if case .failure(let error) = resultHandled.result {
                messageWithError += ": " + error.localizedDescription
            }
            await postMessage(MessageBlock(status: resultHandled.result?.messageStatusAny ?? result.messageStatusAny, messageWithError))
        }

        return result
    }

    static func initialize() {
        checkFirstRun()
    }

    static func checkFirstRun() {
    }
}

/// Code to clear the line on a tty.
private let clearLineString = "\u{001B}[2K"

/// Code to end any currently active wrapping.
private let resetString = "\u{001B}[0m"

/// Code to make string bold.
private let boldString = "\u{001B}[1m"

extension Result where Success == MessageEncodable {
    /// The `MessageBlock.Status` of a `Result` is underlying status, or `.fail` for an error
    var messageStatus: MessageBlock.Status? {
        switch self {
        case .success(let x): return x.status
        case .failure: return .fail
        }
    }
}

extension Result {
    /// Async equivalent of `Result.init(catching:)`
    public init(catchingAsync block: () async throws -> Success) async where Failure == Error {
        do {
            self = .success(try await block())
        } catch {
            self = .failure(error)
        }
    }

    var messageStatusAny: MessageBlock.Status {
        switch self {
        case .success: return .pass
        case .failure: return .fail
        }
    }
}

struct ProcessDidNotLaunchError : LocalizedError {
    var errorDescription: String?
}

extension NSLock {
    internal func withLock<T> (_ body: () throws -> T) rethrows -> T {
        self.lock()
        defer { self.unlock() }
        return try body()
    }
}
