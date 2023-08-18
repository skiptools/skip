// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation
import Darwin

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
public protocol SkipParsableCommand : AsyncParsableCommand {
    var outputOptions: OutputOptions { get set }

}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
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
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
public struct SkipDriver: SkipParsableCommand {
    public static var configuration = CommandConfiguration(
        commandName: "skip",
        abstract: "Skip \(skipVersion)",
        shouldDisplay: true,
        subcommands: [
            VersionCommand.self,
            CreateCommand.self,
            //DoctorCommand.self,
            //RunCommand.self,
            //TestCommand.self,
            //AssembleCommand.self,
            //UploadCommand.self,
        ]
    )

    @OptionGroup(title: "Output Options")
    public var outputOptions: OutputOptions

    public init() {
    }
}

// MARK: VersionCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
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

// MARK: CreateCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct CreateCommand: SkipParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new Skip project from a template",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Create Options")
    var createOptions: CreateOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Run the project build"))
    var build: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Run the project tests"))
    var test: Bool = false

    @Argument(help: ArgumentHelp("Project folder name"))
    var projectName: String

    func run() async throws {
        outputOptions.write("Creating project \(projectName) from template \(createOptions.template)")

        let outputFolder = createOptions.dir ?? "."
        var isDir: Foundation.ObjCBool = false
        if !FileManager.default.fileExists(atPath: outputFolder, isDirectory: &isDir) {
            throw AppLaunchError(errorDescription: "Specified output folder does not exist: \(outputFolder)")
        }
        if isDir.boolValue == false {
            throw AppLaunchError(errorDescription: "Specified output folder is not a directory: \(outputFolder)")
        }

        let projectFolder = outputFolder + "/" + projectName
        if FileManager.default.fileExists(atPath: projectFolder) {
            throw AppLaunchError(errorDescription: "Specified project path already exists: \(projectFolder)")
        }

        let downloadURL: URL = try await outputOptions.monitor("Downloading template \(createOptions.template)") {
            let downloadURL = try createOptions.projectTemplateURL
            let (url, response) = try await URLSession.shared.download(from: downloadURL)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200..<300).contains(code) {
                throw AppLaunchError(errorDescription: "Download for template URL \(downloadURL.absoluteString) returned error: \(code)")
            }
            return url
        }

        let projectFolderURL = URL(fileURLWithPath: projectFolder, isDirectory: true)

        try await outputOptions.run("Unpacking template \(createOptions.template) for project \(projectName)", ["unzip", downloadURL.path, "-d", projectFolderURL.path])

        let packageJSONString = try await outputOptions.run("Checking project \(projectName)", [toolOptions.swift, "package", "dump-package", "--package-path", projectFolderURL.path])

        let packageJSON = try JSONDecoder().decode(SwiftPackage.self, from: Data(packageJSONString.utf8))

        if build == true {
            try await outputOptions.run("Building project \(projectName) for package \(packageJSON.name)", [toolOptions.swift, "build", "-c", createOptions.configuration, "--package-path", projectFolderURL.path])
        }

        if test == true {
            try await outputOptions.run("Testing project \(projectName)", [toolOptions.swift, "test", "-c", createOptions.configuration, "--package-path", projectFolderURL.path])
        }

        outputOptions.write("Created project \(projectName) from template \(createOptions.template) in \(projectFolder)")
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

struct CreateOptions: ParsableArguments {
    /// TODO: dynamic loading of template data
    static let templates = [
        ProjectTemplate(id: "skipapp", url: URL(string: "https://github.com/skiptools/skipapp/releases/latest/download/App-Source.zip")!, localizedTitle: [
            "en": "Skip Sample App"
        ], localizedDescription: [
            "en": """
                A Skip sample app for iOS and Android.
                """
        ])
    ]

    @Option(help: ArgumentHelp("Application identifier"))
    var id: String = "net.example.MyApp"

    @Option(name: [.customShort("d"), .long], help: ArgumentHelp("Base folder for project creation", valueName: "directory"))
    var dir: String?

    @Option(name: [.customShort("c"), .long], help: ArgumentHelp("Configuration debug/release", valueName: "c"))
    var configuration: String = "debug"

    @Option(name: [.customShort("t"), .long], help: ArgumentHelp("Template name/ID for new project", valueName: "id"))
    var template: String = templates.first!.id

    var projectTemplateURL: URL {
        get throws {
            guard let sample = Self.templates.first(where: { $0.id == template }) else {
                throw SkipDriveError(errorDescription: "Sample named \(template) could not be found")
            }
            return sample.url
        }
    }

}

struct ProjectTemplate : Codable {
    let id: String
    let url: URL
    let localizedTitle: [String: String]
    let localizedDescription: [String: String]
}

/// An incomplete representation of package JSON, to be filled in as needed for the purposes of the tool
struct SwiftPackage : Decodable {
    let name: String
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
public struct OutputOptions: ParsableArguments {
    @Option(name: [.customShort("o"), .long], help: ArgumentHelp("Send output to the given file (stdout: -)", valueName: "path"))
    var output: String?

    @Flag(name: [.customShort("v"), .long], help: ArgumentHelp("Whether to display verbose messages"))
    var verbose: Bool = false

    @Flag(name: [.customShort("q"), .long], help: ArgumentHelp("Quiet mode: suppress output"))
    var quiet: Bool = false

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

    /// The characters for the current progress sequence
    private var progressSeq: [Character] {
        Self.progressAimations.first!.map({ $0 })
    }

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
    func run(_ message: String, progress: Bool = true, _ args: [String], environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> String {
        try await monitor(message, progress: progress) {
            try await Process.checkNonZeroExit(arguments: args, environment: environment, loggingHandler: nil)
        }
    }

    static var isTerminal: Bool { isatty(fileno(stdout)) != 0 }

    /// Perform an operation with a given progress animation
    @discardableResult func monitor<T>(_ message: String, progress: Bool = Self.isTerminal, block: () async throws -> T) async throws -> T {
        var progressMonitor: Task<(), Error>? = nil

        @Sendable func clear(_ count: Int) {
            // clear the current line
            write(String(repeating: "\u{8}", count: count), terminator: "", flush: true)
        }

        if !progress {
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
            write("[✓] " + message, flush: true)
            return result
        } catch {
            progressMonitor?.cancel() // cancel the progress task
            clear(message.count + 4)
            write("[✗] " + message, flush: true)
            throw error
        }
    }

}

public struct SkipDriveError : LocalizedError {
    public var errorDescription: String?
}
