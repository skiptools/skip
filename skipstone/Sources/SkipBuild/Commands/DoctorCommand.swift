import Foundation
import ArgumentParser
import SkipSyntax
import TSCUtility

// MARK: DoctorCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct DoctorCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Evaluate and diagnose Skip development environment",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    func run() async throws {
        outputOptions.write("Skip Doctor")
        try await runDoctor()
        let latestVersion = try await checkSkipUpdates()
        if let latestVersion = latestVersion, latestVersion != skipVersion {
            outputOptions.write("A new version is Skip (\(latestVersion)) is available to update with: skip update")
        } else {
            outputOptions.write("Skip (\(skipVersion)) checks complete")
        }
    }
}

extension SkipCommand {
    /// Runs the `skip doctor` command.
    func runDoctor() async throws {
        func run(_ title: String, _ args: [String]) async throws -> String {
            let (out, err) = try await outputOptions.run(title, flush: false, args)
            return out.trimmingCharacters(in: .newlines) + err.trimmingCharacters(in: .newlines)
        }

        func checkVersion(title: String, cmd: [String], min: Version? = nil, pattern: String) async {
            do {
                let output = try await run(title, cmd)
                if let v = try output.extract(pattern: pattern) {
                    // the ToolSupport `Version` constructor only accepts three-part versions,
                    // so we need to augment versions like "8.3" and "2022.3" with an extra ".0"
                    guard let semver = Version(v) ?? Version(v + ".0") ?? Version(v + ".0.0") else {
                        outputOptions.write(": PARSE ERROR")
                        return
                    }
                    if let min = min, semver < min {
                        outputOptions.write(": \(semver) (NEEDS \(min))")
                    } else {
                        outputOptions.write(": \(semver)")
                    }
                } else {
                    outputOptions.write(": ERROR")
                }
            } catch {
                outputOptions.write(": ERROR: \(error)")
            }
        }

        await checkVersion(title: "Skip version", cmd: ["skip", "version"], min: Version("0.6.4"), pattern: "Skip version ([0-9.]+)")
        await checkVersion(title: "macOS version", cmd: ["sw_vers", "--productVersion"], min: Version("13.5.0"), pattern: "([0-9.]+)")
        await checkVersion(title: "Swift version", cmd: ["swift", "-version"], min: Version("5.9.0"), pattern: "Swift version ([0-9.]+)")
        await checkVersion(title: "Xcode version", cmd: ["xcodebuild", "-version"], min: Version("15.0.0"), pattern: "Xcode ([0-9.]+)")
        await checkVersion(title: "Gradle version", cmd: ["gradle", "-version"], min: Version("8.3.0"), pattern: "Gradle ([0-9.]+)")
        await checkVersion(title: "Java version", cmd: ["java", "-version"], min: Version("17.0.0"), pattern: "version \"([0-9.]+)\"")
        await checkVersion(title: "Homebrew version", cmd: ["brew", "--version"], min: Version("4.1.5"), pattern: "Homebrew ([0-9.]+)")
        await checkVersion(title: "Android Studio version", cmd: ["/usr/libexec/PlistBuddy", "-c", "Print CFBundleShortVersionString", "/Applications/Android Studio.app/Contents/Info.plist"], min: Version("2022.3.0"), pattern: "([0-9.]+)")
    }
}
