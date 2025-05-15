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
        discussion: """
This command will check for system configuration and prerequisites. It is a subset of the skip checkup command.
""",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Check for native SDK", valueName: "native"))
    var native: Bool = false

    // we do not fail fast by default for doctor since it is useful to see all the parts that failed
    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Fail immediately when an error occurs"))
    var failFast: Bool = false

    func performCommand(with out: MessageQueue) async {
        await withLogStream(with: out) {
            await out.yield(MessageBlock(status: nil, "Skip Doctor"))

            try await runDoctor(checkNative: self.native, with: out)
            let latestVersion = await checkSkipUpdates(with: out)
            if let latestVersion = latestVersion, latestVersion != skipVersion {
                await out.yield(MessageBlock(status: .warn, "A new version is Skip (\(latestVersion)) is available to update with: skip upgrade"))
            }
        }
    }
}

extension ToolOptionsCommand where Self : StreamingCommand {
    // TODO: check license validity: https://github.com/skiptools/skip/issues/388

    /// Runs the `skip doctor` command and stream the results to the messenger
    func runDoctor(checkNative: Bool, with out: MessageQueue) async throws {
        /// Invokes the given command and attempts to parse the output against the given regular expression pattern to validate that it is a semantic version string
        func checkVersion(title: String, cmd: [String], min: Version? = nil, pattern: String, watch: Bool = false, hint: String? = nil) async throws {

            func parseVersion(_ result: Result<ProcessOutput, Error>?) -> (result: Result<ProcessOutput, Error>?, message: MessageBlock?) {
                guard let res = try? result?.get() else {
                    return (result: result, message: MessageBlock(status: .fail, title + ": error executing \(cmd.first ?? "")\(hint ?? "")"))
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
                    if semver < min {
                        return (result: result, message: MessageBlock(status: .warn, "\(title) \(outputVersion) (< \(min))\(hint ?? "")"))
                    } else {
                        return (result: result, message: MessageBlock(status: .pass, "\(title) \(outputVersion) (\(semver > min ? ">" : "=") \(min))"))
                    }
                } else {
                    return (result: result, message: MessageBlock(status: .pass, "\(title) \(semver)"))
                }
            }

            try await run(with: out, title, cmd, watch: watch, resultHandler: parseVersion)
        }

        /// check for stale Intel Homebrew installations of tools (java, etc.) on ARM (https://github.com/skiptools/skip/issues/97)
        func checkRosetta() async throws {

            let arch = ProcessInfo.isARM ? "ARM" : "Intel"

            func checkResult(_ result: Result<ProcessOutput, Error>?) -> (result: Result<ProcessOutput, Error>?, message: MessageBlock?) {
                guard let res = try? result?.get() else {
                    return (result: result, message: MessageBlock(status: .warn, "Error running sysctl (\(arch))"))
                }
                let stdout = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if stdout != "0" {
                    return (result: result, message: MessageBlock(status: .warn, "macOS architecture: wrong architecture \(stdout), Rosetta must not be enabled for process on (\(arch))"))
                } else {
                    return (result: result, message: MessageBlock(status: .pass, "macOS architecture: \(arch)"))
                }
            }

            try await run(with: out, "macOS architecture", ["sysctl", "-n", "sysctl.proc_translated"], watch: false, resultHandler: checkResult)
        }

        // enable overriding skip command with skip.local
        let skipcmd = ProcessInfo.processInfo.environment["SKIP_COMMAND_OVERRIDE"] ?? "skip"

        //await checkVersion(title: "ECHO2 VERSION", cmd: ["sh", "-c", "echo ONE ; sleep 1; echo TWO ; sleep 1; echo THREE ; sleep 1; echo 3.2.1"], min: Version("1.2.3"), pattern: "([0-9.]+)", watch: true)

        try await checkVersion(title: "Skip version", cmd: [skipcmd, "version"], min: Version(skipVersion), pattern: "Skip version ([0-9.]+)")
        try await checkVersion(title: "macOS version", cmd: ["sw_vers", "--productVersion"], min: Version("13.5.0"), pattern: "([0-9.]+)")
        if ProcessInfo.isARM {
            // only check for Rosetta when we are on an ARM machine
            try await checkRosetta()
        }
        try await checkVersion(title: "Swift version", cmd: ["swift", "-version"], min: Version("5.9.0"), pattern: "Swift version ([0-9.]+)")
        if checkNative {
            try await checkVersion(title: "Swift Android SDK version", cmd: [skipcmd, "android", "toolchain", "version"], min: Version("6.1.0"), pattern: "Swift Package Manager - Swift ([0-9.]+)", hint: " (install with: skip android sdk install)")
        }
        // TODO: add advice to run `xcode-select -s /Applications/Xcode.app/Contents/Developer` to work around https://github.com/skiptools/skip/issues/18
        try await checkVersion(title: "Xcode version", cmd: ["xcodebuild", "-version"], min: Version("15.0.0"), pattern: "Xcode ([0-9.]+)", hint: " (install from: https://developer.apple.com/xcode/)")
        await checkXcodeCommandLineTools(with: out)
        try await checkVersion(title: "Homebrew version", cmd: ["brew", "--version"], min: Version("4.1.0"), pattern: "Homebrew ([0-9.]+)", hint: " (install from: https://brew.sh)")
        try await checkVersion(title: "Gradle version", cmd: ["gradle", "-version"], min: Version("8.6.0"), pattern: "Gradle ([0-9.]+)", hint: " (install with: brew install gradle)")
        try await checkVersion(title: "Java version", cmd: ["java", "-version"], min: Version("21.0.0"), pattern: "version \"([0-9._]+)\"", hint: ProcessInfo.processInfo.environment["JAVA_HOME"] == nil ? nil : " (check JAVA_HOME environment: \(ProcessInfo.processInfo.environment["JAVA_HOME"] ?? "unset"))") // we don't necessarily need java in the path (which it doesn't seem to be by default with Homebrew)
        try await checkVersion(title: "Android Debug Bridge version", cmd: ["adb", "version"], min: Version("1.0.40"), pattern: "version ([0-9.]+)")
        await checkAndroidStudioVersion(with: out)
        await checkSkipLicense(with: out)
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

    func checkSkipLicense(with out: MessageQueue) async {
        // Manually try to parse the Android Studio version; tolerate failures
        await outputOptions.monitor(with: out, "Skip license", resultHandler: { result in
            do {
                guard let (license, trialExpiraton, _, _) = try result?.get() else {
                    return (result, MessageBlock(status: .fail, "Skip license: none found"))
                }

                let exp = license?.expiration ?? trialExpiraton
                let daysLeft = Int(ceil(exp.timeIntervalSince(Date.now) / (24 * 60 * 60)))
                let expires = daysLeft > licenseWarnDays ? "good through" : daysLeft > 0 ? "expires" : "expired"
                let status: MessageBlock.Status = daysLeft < 0 ? .fail : daysLeft < licenseWarnDays ? .warn : .pass
                let fmt = { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) }
                let ltype = license == nil ? "trial" : license?.licenseType?.rawValue ?? "legacy"
                return (result, MessageBlock(status: status, "Skip license: \(ltype) \(expires) \(fmt(exp))"))
            } catch {
                return (result, MessageBlock(status: .fail, "Skip license error: \(error.localizedDescription)"))
            }
        }, monitorAction: { _ in
            try loadSkipLicense()
        })
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
                return (result, MessageBlock(status: .pass, "Android tools SDKs: \(licenseCount)"))
            } else {
                return (result, MessageBlock(status: .warn, "Android SDK licenses need to be accepted with: sdkmanager --licenses"))
            }
        }, monitorAction: { _ in
            try FileManager.default.contentsOfDirectory(atPath: androidHome + "/licenses/")
        })

        #endif
    }

    func androidInfoPlist() throws -> [String: Any]? {
        let appsFolder = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first?.path ?? "/Applications"


        func studioProps(for path: String) throws -> [String: Any]? {
            try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: path)), format: nil) as? [String: Any]
        }

        do {
            return try studioProps(for: "\(appsFolder)/Android Studio.app/Contents/Info.plist")
        } catch let e1 {
            do {
                // Check for /Applications/JetBrains Toolbox/Android Studio.app: https://github.com/skiptools/skip/issues/15
                return try studioProps(for: "\(appsFolder)/JetBrains Toolbox/Android Studio.app/Contents/Info.plist")
            } catch {
                do {
                    // Check for ~/Applications/Android Studio.app: https://github.com/skiptools/skip/issues/107
                    return try studioProps(for: ("~/Applications/Android Studio.app/Contents/Info.plist" as NSString).expandingTildeInPath)
                } catch {
                    throw e1
                }
            }
        }
    }
}
