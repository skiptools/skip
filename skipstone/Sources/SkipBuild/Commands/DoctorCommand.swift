import Foundation
import ArgumentParser
import SkipSyntax
import TSCUtility

// MARK: DoctorCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct DoctorCommand: SkipCommand, StreamingCommand, ToolOptionsCommand {
    typealias Output = MessageBlock

    static var configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Evaluate and diagnose Skip development environment",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    func performCommand(with out: MessageQueue) async {
        await out.yield(MessageBlock(status: nil, "Skip Doctor"))

        await runDoctor(with: out)
        let latestVersion = await checkSkipUpdates(with: out)
        if let latestVersion = latestVersion, latestVersion != skipVersion {
            await out.yield(MessageBlock(status: .warn, "A new version is Skip (\(latestVersion)) is available to update with: skip upgrade"))
        }
        await reportMessageQueue(with: out, title: "Skip (\(skipVersion)) checks complete")
    }
}

extension ToolOptionsCommand {
    /// Runs the `skip doctor` command and stream the results to the messenger
    func runDoctor(with out: MessageQueue) async {

        /// Invokes the given command and attempts to parse the output against the given regular expression pattern to validate that it is a semantic version string
        func checkVersion(title: String, cmd: [String], min: Version? = nil, pattern: String, watch: Bool = false) async {

            func parseVersion(_ result: Result<ProcessOutput, Error>?) -> (result: Result<ProcessOutput, Error>?, message: MessageBlock?) {
                guard let res = try? result?.get() else {
                    return (result: result, message: MessageBlock(status: .fail, title + ": error executing \(cmd.first ?? "")"))
                }

                let output = res.stdout.trimmingCharacters(in: .newlines) + res.stderr.trimmingCharacters(in: .newlines)

                guard let outputVersion = try? output.extract(pattern: pattern) else {
                    return (result: result, message: MessageBlock(status: .fail, title + " could not extract version from \(cmd.first ?? "")"))
                }

                var versionString = outputVersion.replacing("_", with: ".") // fix up, e.g., Java 1.8.0_32
                while versionString.split(separator: ".").count < 3 {
                    // handle too few numbers, like: gradle 8.4
                    versionString += ".0"
                }
                while versionString.split(separator: ".").count > 3 {
                    // handle too many numbers, like: openjdk version "17.0.8.1" 2023-08-24
                    versionString = versionString.split(separator: ".").dropLast().joined(separator: ".")
                }

                // the ToolSupport `Version` constructor only accepts three-part versions,
                // so we need to augment versions like "8.3" and "2022.3" with an extra ".0"
                guard let semver = Version(versionString) else {
                    return (result: result, message: MessageBlock(status: .fail, title + " could not parse version: \(versionString)"))
                }

                if let min = min {
                    return (result: result, message: MessageBlock(status: semver < min ? .warn : .pass, "\(title) \(outputVersion) (\(semver < min ? "<" : semver > min ? ">" : "=") \(min))"))
                } else {
                    return (result: result, message: MessageBlock(status: .pass, "\(title) \(semver)"))
                }
            }

            await run(with: out, title, cmd, watch: watch, resultHandler: parseVersion)
        }

        //await checkVersion(title: "ECHO2 VERSION", cmd: ["sh", "-c", "echo ONE ; sleep 1; echo TWO ; sleep 1; echo THREE ; sleep 1; echo 3.2.1"], min: Version("1.2.3"), pattern: "([0-9.]+)", watch: true)

        await checkVersion(title: "Skip version", cmd: ["skip", "version"], min: Version(skipVersion), pattern: "Skip version ([0-9.]+)")
        await checkVersion(title: "macOS version", cmd: ["sw_vers", "--productVersion"], min: Version("13.5.0"), pattern: "([0-9.]+)")
        await checkVersion(title: "Swift version", cmd: ["swift", "-version"], min: Version("5.9.0"), pattern: "Swift version ([0-9.]+)")
        // TODO: add advice to run `xcode-select -s /Applications/Xcode.app/Contents/Developer` to work around https://github.com/skiptools/skip/issues/18
        await checkVersion(title: "Xcode version", cmd: ["xcodebuild", "-version"], min: Version("15.0.0"), pattern: "Xcode ([0-9.]+)")
        await checkXcodeCommandLineTools(with: out)
        await checkVersion(title: "Homebrew version", cmd: ["brew", "--version"], min: Version("4.1.0"), pattern: "Homebrew ([0-9.]+)")
        await checkVersion(title: "Gradle version", cmd: ["gradle", "-version"], min: Version("8.3.0"), pattern: "Gradle ([0-9.]+)")
        await checkVersion(title: "Java version", cmd: ["java", "-version"], min: Version("17.0.0"), pattern: "version \"([0-9._]+)\"") // we don't necessarily need java in the path (which it doesn't seem to be by default with Homebrew)
        await checkVersion(title: "Android Debug Bridge version", cmd: ["adb", "version"], min: Version("1.0.40"), pattern: "version ([0-9.]+)")
        await checkAndroidStudioVersion(with: out)

        // TODO: check for stale Intel Homebrew installations of tools (java, etc.) on ARM
    }

    func checkXcodeCommandLineTools(with out: MessageQueue) async {
        #if os(macOS)
        await outputOptions.monitor(with: out, "Android Studio licenses", resultHandler: { result in
            let paths: [String]? = try? result?.get()
            let sdkCount = paths?.count ?? 0
            if sdkCount > 0 {
                return (result, MessageBlock(status: .pass, "Xcode tools SDKs: \(sdkCount)"))
            } else {
                return (result, MessageBlock(status: .warn, "Xcode tools must be installed with: xcode-select --install"))
            }
        }, monitorAction: { _ in
            try FileManager.default.contentsOfDirectory(atPath: "/Library/Developer/CommandLineTools/SDKs/")
        })

        #endif
    }

    func checkAndroidStudioVersion(with out: MessageQueue) async {
        #if os(macOS) // on macOS, check for Android Studio
        //await checkVersion(title: "Android Studio version", cmd: ["/usr/libexec/PlistBuddy", "-c", "Print CFBundleShortVersionString", "/Applications/Android Studio.app/Contents/Info.plist"], min: Version("2022.3.0"), pattern: "([0-9.]+)")

        // Manually try to parse the Android Studio version; tolerate failures
        await outputOptions.monitor(with: out, "Android Studio version", resultHandler: { result in
            let studioVersion = try? result?.get()
            return (result, MessageBlock(status: studioVersion == nil ? .warn : .pass, studioVersion != nil 
                                         ? "Android Studio version: \(studioVersion!)"
                                         : "Android Studio not found: brew install android-studio"))
        }, monitorAction: { _ in
            try androidInfoPlist()?["CFBundleShortVersionString"] as? String
        })

        let androidHome = ProcessInfo.processInfo.environmentWithDefaultToolPaths["ANDROID_HOME"] ?? NSTemporaryDirectory()

        // Check for SDK licenses in ~/Library/Android/sdk/licenses/ and advise to run ~/Library/Android/sdk/tools/bin/sdkmanager --licenses when not found
        await outputOptions.monitor(with: out, "Android Studio licenses", resultHandler: { result in
            let licensePaths: [String]? = try? result?.get()
            let licenseCount = licensePaths?.count ?? 0
            if licenseCount > 0 {
                return (result, MessageBlock(status: .pass, "Android SDK licenses: \(licenseCount)"))
            } else {
                return (result, MessageBlock(status: .warn, "Android SDK licenses need to be accepted with: \((androidHome as NSString).abbreviatingWithTildeInPath)/tools/bin/sdkmanager --licenses"))
            }
        }, monitorAction: { _ in
            try FileManager.default.contentsOfDirectory(atPath: androidHome + "/licenses/")
        })

        #endif
    }

    func androidInfoPlist() throws -> [String: Any]? {
        let appsFolder = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.path ?? "/Applications"

        do {
            return try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: "\(appsFolder)/Android Studio.app/Contents/Info.plist")), format: nil) as? [String: Any]
        } catch let e1 {
            do {
                // Check for /Applications/JetBrains Toolbox/Android Studio.app as well: https://github.com/skiptools/skip/issues/15
                return try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: "\(appsFolder)/JetBrains Toolbox/Android Studio.app/Contents/Info.plist")), format: nil) as? [String: Any]
            } catch {
                throw e1
            }
        }
    }
}
