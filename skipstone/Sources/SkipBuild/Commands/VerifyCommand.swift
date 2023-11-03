import Foundation
import ArgumentParser
import TSCUtility

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct VerifyCommand: SkipCommand, StreamingCommand, ToolOptionsCommand {

    static var configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Verify the Skip project",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(help: ArgumentHelp("Project folder", valueName: "dir"))
    var project: String = "."


    func performCommand(with out: MessageQueue) async throws {
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

            
            await run(with: out, title, cmd, watch: watch, resultHandler: parseVersion)
        }

        //await checkVersion(title: "ECHO2 VERSION", cmd: ["sh", "-c", "echo ONE ; sleep 1; echo TWO ; sleep 1; echo THREE ; sleep 1; echo 3.2.1"], min: Version("1.2.3"), pattern: "([0-9.]+)", watch: true)

        await checkVersion(title: "Skip version", cmd: ["skip", "version"], min: Version(skipVersion), pattern: "Skip version ([0-9.]+)")

        //await checkVersion(title: "macOS version", cmd: ["XXXX", "--productVersion"], min: Version("13.5.0"), pattern: "([0-9.]+)")

        // TODO:
        // Run swift package dump-package
        let packageJSONString = try await run(with: out, "Check Swift Package", ["swift", "package", "dump-package", "--package-path", project]).get().stdout
        let _ = try JSONDecoder().decode(PackageManifest.self, from: Data(packageJSONString.utf8))

        // -list for a pure SPM will look like: {"workspace":{"name":"skip-script","schemes":["skip-script"]}}
        // -list with a project will look like: {"project":{"configurations":["Debug","Release","Skippy"],"name":"DataBake","schemes":["DataBake","DataBakeApp","DataBakeModel"],"targets":["DataBakeApp"]}}
        // with a workspace will give the error: xcodebuild: error: The directory /opt/src/github/skiptools/skipstone contains 3 workspaces. Specify the workspace to use with the -workspace option
        //let _ = try await run(with: out, "Check schemes", ["xcodebuild", "-list", "-json", project]).get().stdout

        //let _ = try await run(with: out, "Check xcconfig", ["xcodebuild", "-showBuildSettings", "-json", project]).get().stdout

        // Check xcode project config: xcodebuild -describeAllArchivableProducts -json
        //let _ = try await run(with: out, "Check Xcode Project", ["xcodebuild", "-describeAllArchivableProducts", "-json", project]).get().stdout


        let messages = await out.elements

        if messages.isEmpty {
            await out.yield(MessageBlock(status: .fail, "Verify command performed no checks"))
        } else {
            //let total = messages.count
            let warnings = messages.filter({ $0.messageStatus == .warn }).count
            let errors = messages.filter({ $0.messageStatus == .fail }).count

            var msg = "Verify skip project (\(skipVersion)) checks complete"
            if warnings > 0 || errors > 0 {
                if errors > 0 {
                    msg += " with \(errors) error\(warnings == 1 ? "" : "s")"
                }
                if warnings > 0 {
                    msg += " \(errors > 0 ? "and" : "with") \(warnings) warning\(warnings == 1 ? "" : "s")"
                }
            }

            await out.yield(MessageBlock(status: errors > 0 ? .fail : warnings > 0 ? .warn : .pass, msg))
        }
    }
}
