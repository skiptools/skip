// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import struct Foundation.URL

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public protocol SkipParsableCommand : AsyncParsableCommand {
    var outputOptions: OutputOptions { get set }

}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension SkipParsableCommand {
    /// Run the transpiler on the given arguments.
    public static func run(_ arguments: [String], out: WritableByteStream? = nil, err: WritableByteStream? = nil) async throws {
        var cmd: ParsableCommand = try parseAsRoot(arguments)
        if var cmd = cmd as? any SkipParsableCommand {
            if let outputFile = cmd.outputOptions.output {
                let path = URL(fileURLWithPath: outputFile)
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

/// The command that is run by "SkipRunner" (aka "skipstone")
public struct SkipDriver: SkipParsableCommand {
    public static var configuration = CommandConfiguration(
        commandName: "skip",
        abstract: "Skip \(skipVersion)",
        shouldDisplay: true,
        subcommands: [
            VersionCommand.self,
        ]
    )

    @OptionGroup(title: "Output Options")
    public var outputOptions: OutputOptions

    public init() {
    }
}

// MARK: VersionCommand

struct VersionCommand: SkipParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Print the Skip version",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    public var outputOptions: OutputOptions

    func run() async throws {
        outputOptions.write("Skip version \(skipVersion)")
    }
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

    /// A transient handler for tool output; this acts as a temporary holder of output streams
    internal var streams: OutputHandler = OutputHandler()

    public init() {
    }

    internal final class OutputHandler : Decodable {
        var out: WritableByteStream = stdoutStream
        var err: WritableByteStream = stderrStream
        var file: LocalFileOutputByteStream? = nil

        func fileStream(for outputPath: String?) -> LocalFileOutputByteStream? {
            guard let outputPath else { return nil }
            if let file = file { return file }
            do {
                let path = URL(fileURLWithPath: outputPath)
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

        init() {
        }

        /// Not really decodable; this is just a transient holder of output streams
        convenience init(from decoder: Decoder) throws {
            self.init()
        }
    }

    /// Write the given message to the output streams buffer
    func write(_ value: String, error: Bool = false) {
        streams.write(error: error, output: output, value)
    }
}

