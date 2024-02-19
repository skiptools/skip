import Foundation
import ArgumentParser
//import TSCUtility

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct VerifyCommand: SkipCommand, StreamingCommand, ProjectCommand, ToolOptionsCommand {
    typealias Output = MessageBlock

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
