import Foundation
import ArgumentParser
import SkipSyntax
#if canImport(SkipDriveExternal)
import SkipDriveExternal
fileprivate let adbCommandEnabled = false // advanced command, so do not display
//fileprivate let adbCommandEnabled = true
#else
fileprivate let adbCommandEnabled = false
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct ADBCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "adb",
        abstract: "Launch the adb build tool",
        shouldDisplay: adbCommandEnabled)

    static let adbRegex = try! NSRegularExpression(pattern: #"^error: (.*)"#)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @Argument(help: ArgumentHelp("The arguments to pass to the adb command"))
    var arguments: [String]

    func run() async throws {
        // ADB itself doesn't ever exit with a non-zero exit code (https://issuetracker.google.com/issues/36908392?pli=1)
        // So we need to parse the output for known error patterns and translate them into Xcode-aware messages
        #if !canImport(SkipDriveExternal)
        throw SkipDriveError(errorDescription: "SkipDrive not linked")
        #else
        var exitCode: ProcessResult.ExitStatus? = nil
        let output = try await self.adb(args: arguments) {
            exitCode = $0.exitStatus
        }

        for try await line in output {
            print("ADB>", line)
            // scanADBOutput(line: line) // check for errors and report them to the IDE
        }

        guard let exitCode = exitCode, case .terminated(0) = exitCode else {
            throw ADBLaunchError(errorDescription: "ADB run error: \(String(describing: exitCode))")
        }

        #endif
    }

    #if canImport(SkipDriveExternal)
    /// Executes `adb` with the current default arguments and the additional args and returns an async stream of the lines from the combined standard err and standard out.
    private func adb(in workingDirectory: URL? = nil, args: [String], env: [String: String] = [:], onExit: @escaping (ProcessResult) throws -> () = { _ in }) async throws -> SkipDriveExternal.Process.AsyncLineOutput {
        #if DEBUG
        // output the launch message in a format that makes it easy to copy and paste the result into the terminal
        print("adb:", env.keys.sorted().map { $0 + "=\"" + env[$0, default: ""] + "\"" }.joined(separator: " "), (args).joined(separator: " "))
        #endif

        // transfer process environment along with the additional environment
        var penv = ProcessInfo.processInfo.environment
        for (key, value) in env {
            penv[key] = value
        }
        return Process.streamLines(command: args, environment: penv, workingDirectory: workingDirectory, onExit: onExit)
    }
    #endif

}

public struct ADBLaunchError : LocalizedError {
    public var errorDescription: String?
}
