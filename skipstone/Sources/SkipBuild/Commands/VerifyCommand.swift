import Foundation
import ArgumentParser
//import TSCUtility

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct VerifyCommand: SkipCommand, StreamingCommand, ProjectCommand, ToolOptionsCommand {

    static var configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Verify Skip project",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(help: ArgumentHelp("Project folder", valueName: "dir"))
    var project: String = "."

    func performCommand(with out: MessageQueue) async {
        do {
            try await performVerifyCommand(project: project, with: out)
        } catch {
            await out.yield(MessageBlock(status: .fail, error.localizedDescription))
        }
        await reportMessageQueue(with: out, title: "Verify skip project (\(skipVersion)) checks complete")
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

    /// Run swift package dump-package and return the parsed JSON results
    func parseSwiftPackage(with out: MessageQueue, at projectPath: String) async throws -> PackageManifest {
        try await decodeCommand(with: out, title: "Check Swift Package", cmd: ["swift", "package", "dump-package", "--package-path", projectPath]).get()
    }

    func performVerifyCommand(project projectPath: String, with out: MessageQueue) async throws {
        let projectFolderURL = URL(fileURLWithPath: projectPath, isDirectory: true)

        let packageJSON = try await parseSwiftPackage(with: out, at: projectPath)
        let packageName = packageJSON.name
        guard var moduleName = packageJSON.products.first?.name else {
            throw AppVerifyError(errorDescription: "No products declared in package \(packageName) at \(projectPath)")
        }
        if moduleName.hasSuffix("App") {
            moduleName = moduleName.dropLast(3).description
        }

        let androidDir = projectFolderURL.appendingPathComponent("Android", isDirectory: true)
        let darwinDir = projectFolderURL.appendingPathComponent("Darwin", isDirectory: true)
        let isAppProject = androidDir.fileExists(isDirectory: true) && darwinDir.fileExists(isDirectory: true)

        if isAppProject {
            let project = try AppProjectLayout(moduleName: moduleName, root: projectFolderURL)
            let _ = project
        } else {
            let project = try FrameworkProjectLayout(root: projectFolderURL)
            let _ = project
        }

        #if os(macOS)

        // -list for a pure SPM will look like: {"workspace":{"name":"skip-script","schemes":["skip-script"]}}
        // -list with a project will look like: {"project":{"configurations":["Debug","Release","Skippy"],"name":"DataBake","schemes":["DataBake","DataBakeApp","DataBakeModel"],"targets":["DataBakeApp"]}}
        // with a workspace will give the error: xcodebuild: error: The directory /opt/src/github/skiptools/skipstone contains 3 workspaces. Specify the workspace to use with the -workspace option
        //let _ = try await run(with: out, "Check schemes", ["xcodebuild", "-list", "-json", project]).get().stdout

        //let _ = try await run(with: out, "Check xcconfig", ["xcodebuild", "-showBuildSettings", "-json", project]).get().stdout

        // Check xcode project config: xcodebuild -describeAllArchivableProducts -json
        //let _ = try await run(with: out, "Check Xcode Project", ["xcodebuild", "-describeAllArchivableProducts", "-json", project]).get().stdout
        #endif
    }
}
