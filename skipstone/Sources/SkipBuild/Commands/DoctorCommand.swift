import Foundation
import ArgumentParser
import SkipSyntax
import TSCUtility

// MARK: DoctorCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct DoctorCommand: SkipCommand, StreamingCommand {
    typealias Output = MessageBlock

    static var configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Evaluate and diagnose Skip development environment",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    func performCommand(with out: Messenger) async throws {
        out.yield(MessageBlock(status: nil, "Skip Doctor"))

        try await runDoctor(tool: toolOptions, with: out)
        let latestVersion = try await checkSkipUpdates(with: out)
        if let latestVersion = latestVersion, latestVersion != skipVersion {
            out.yield(MessageBlock(status: .warn, "A new version is Skip (\(latestVersion)) is available to update with: skip upgrade"))
        } else {
            out.yield(MessageBlock(status: .pass, "Skip (\(skipVersion)) checks complete"))
        }
    }
}

extension SkipCommand where Self : StreamingCommand {
    /// Runs the `skip doctor` command and stream the results to the messenger
    func runDoctor(tool toolOptions: ToolOptions, with out: Messenger) async throws {

        /// Invokes the given command and attempts to parse the output against the given regular expression pattern to validate that it is a semantic version string
        func checkVersion(title: String, cmd: [String], min: Version? = nil, pattern: String, watch: Bool = false) async {

            func parseVersion(_ result: Result<ProcessOutput, Error>?) -> (result: Result<ProcessOutput, Error>?, message: MessageBlock?) {
                guard let res = try? result?.get() else {
                    return (result: result, message: MessageBlock(status: .fail, title + ": error executing \(cmd.first ?? "")"))
                }

                let output = res.stdout.trimmingCharacters(in: .newlines) + res.stderr.trimmingCharacters(in: .newlines)

                guard let v = try? output.extract(pattern: pattern) else {
                    return (result: result, message: MessageBlock(status: .fail, title + " could not extract version from \(cmd.first ?? "")"))
                }

                // the ToolSupport `Version` constructor only accepts three-part versions,
                // so we need to augment versions like "8.3" and "2022.3" with an extra ".0"
                guard let semver = Version(v) ?? Version(v + ".0") ?? Version(v + ".0.0") else {
                    return (result: result, message: MessageBlock(status: .fail, title + " could not parse version"))
                }

                if let min = min {
                    return (result: result, message: MessageBlock(status: semver < min ? .warn : .pass, "\(title) \(semver) (\(semver < min ? "<" : semver > min ? ">" : "=") \(min))"))
                } else {
                    return (result: result, message: MessageBlock(status: .pass, "\(title) \(semver)"))
                }
            }

            await outputOptions.run(with: out, title, cmd, watch: watch, resultHandler: parseVersion)
        }

        //await checkVersion(title: "ECHO2 VERSION", cmd: ["sh", "-c", "echo ONE ; sleep 1; echo TWO ; sleep 1; echo THREE ; sleep 1; echo 3.2.1"], min: Version("1.2.3"), pattern: "([0-9.]+)", watch: true)

        //await checkVersion(title: "Skip version", cmd: [toolOp, "version"], min: Version("0.6.4"), pattern: "Skip version ([0-9.]+)")
        await checkVersion(title: "macOS version", cmd: ["sw_vers", "--productVersion"], min: Version("13.5.0"), pattern: "([0-9.]+)")
        await checkVersion(title: "Swift version", cmd: [toolOptions.swift , "-version"], min: Version("5.9.0"), pattern: "Swift version ([0-9.]+)")
        await checkVersion(title: "Xcode version", cmd: [toolOptions.xcode, "-version"], min: Version("15.0.0"), pattern: "Xcode ([0-9.]+)")
        await checkVersion(title: "Homebrew version", cmd: ["brew", "--version"], min: Version("4.1.0"), pattern: "Homebrew ([0-9.]+)")
        await checkVersion(title: "Gradle version", cmd: [toolOptions.gradle, "-version"], min: Version("8.3.0"), pattern: "Gradle ([0-9.]+)")
        await checkVersion(title: "Java version", cmd: ["java", "-version"], min: Version("17.0.0"), pattern: "version \"([0-9.]+)\"")
        await checkVersion(title: "Android Debug Bridge version", cmd: [toolOptions.adb, "version"], min: Version("1.0.40"), pattern: "version ([0-9.]+)")
        await checkVersion(title: "Android Studio version", cmd: ["/usr/libexec/PlistBuddy", "-c", "Print CFBundleShortVersionString", "/Applications/Android Studio.app/Contents/Info.plist"], min: Version("2022.3.0"), pattern: "([0-9.]+)")
    }
}
