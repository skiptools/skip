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
        await performVerifyCommand(project: project, with: out)
    }
}

struct NoResultOutputError : LocalizedError {
    var errorDescription: String?
}

extension ToolOptionsCommand {

    /// Invokes the given command that launches an executable and is expected to output JSON, which we parse into the specified data structure
    func decodeCommand<T: Decodable>(with out: MessageQueue, title: String, cmd: [String]) async -> Result<T, Error> {

        func decodeResult(_ result: Result<ProcessOutput, Error>) -> Result<T, Error> {
            do {
                let res = try result.get()
                let decoder = JSONDecoder()
                let decoded = try decoder.decode(T.self, from: res.stdout.utf8Data)
                return .success(decoded) // (result: .success(decoded), message: nil)
            } catch {
                return .failure(error) // (result: .failure(error), message: MessageBlock(status: .fail, title + ": error executing \(cmd.joined(separator: " ")): \(error)"))
            }
        }

        let output = await run(with: out, title, cmd)
        return decodeResult(output)
    }

    func parseSwiftPackage(with out: MessageQueue, at projectPath: String) async throws -> PackageManifest {
        try await decodeCommand(with: out, title: "Check Swift Package", cmd: ["swift", "package", "dump-package", "--package-path", projectPath]).get()
    }

    func performVerifyCommand(project projectPath: String, with out: MessageQueue) async {

        //await checkVersion(title: "Skip version", cmd: ["skip", "version"], min: Version(skipVersion), pattern: "Skip version ([0-9.]+)")

        #if os(macOS)
        //await checkVersion(title: "macOS version", cmd: ["XXXX", "--productVersion"], min: Version("13.5.0"), pattern: "([0-9.]+)")

        // Run swift package dump-package
        if let packageJSON: PackageManifest = try? await parseSwiftPackage(with: out, at: projectPath) {
            let _ = packageJSON.name
        }

        // -list for a pure SPM will look like: {"workspace":{"name":"skip-script","schemes":["skip-script"]}}
        // -list with a project will look like: {"project":{"configurations":["Debug","Release","Skippy"],"name":"DataBake","schemes":["DataBake","DataBakeApp","DataBakeModel"],"targets":["DataBakeApp"]}}
        // with a workspace will give the error: xcodebuild: error: The directory /opt/src/github/skiptools/skipstone contains 3 workspaces. Specify the workspace to use with the -workspace option
        //let _ = try await run(with: out, "Check schemes", ["xcodebuild", "-list", "-json", project]).get().stdout

        //let _ = try await run(with: out, "Check xcconfig", ["xcodebuild", "-showBuildSettings", "-json", project]).get().stdout

        // Check xcode project config: xcodebuild -describeAllArchivableProducts -json
        //let _ = try await run(with: out, "Check Xcode Project", ["xcodebuild", "-describeAllArchivableProducts", "-json", project]).get().stdout

        #endif

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
