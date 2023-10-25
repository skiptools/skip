import Foundation
import ArgumentParser
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AppCreateCommand: MessageCommand, ToolOptionsCommand {
    static var configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new Skip app project from a template",
        shouldDisplay: false)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Create Options")
    var createOptions: CreateOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @OptionGroup(title: "Build Options")
    var buildOptions: BuildOptions

    @Argument(help: ArgumentHelp("Project folder name"))
    var projectName: String

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Open the new project in Xcode"))
    var open: Bool = false

    func performCommand(with out: MessageQueue) async throws {
        let pname = projectName.split(separator: "/").last?.description ?? projectName

        await out.write(status: nil, "Create project \(pname) from template \(createOptions.template)")

        let outputFolder = createOptions.dir ?? "."
        var isDir: Foundation.ObjCBool = false
        if !FileManager.default.fileExists(atPath: outputFolder, isDirectory: &isDir) {
            throw CreateError(errorDescription: "Specified output folder does not exist: \(outputFolder)")
        }
        if isDir.boolValue == false {
            throw CreateError(errorDescription: "Specified output folder is not a directory: \(outputFolder)")
        }

        let projectFolder = outputFolder + "/" + projectName
        if FileManager.default.fileExists(atPath: projectFolder) {
            throw CreateError(errorDescription: "Specified project path already exists: \(projectFolder)")
        }

        let templateURL = try createOptions.projectTemplateURL
        let tmsg = "template \(templateURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent)"
        let downloadURL: URL = templateURL.isFileURL ? templateURL : try await outputOptions.monitor(with: out, "Downloading \(tmsg)", resultHandler: { result in
            let fileSize = try? result?.get().resourceValues(forKeys: [.fileSizeKey]).fileSize
            return (result, MessageBlock(status: result?.messageStatusAny, "Downloaded \(tmsg) \(ByteCountFormatter.string(fromByteCount: Int64(fileSize ?? 0), countStyle: .file))"))
        }) { loggingHandler in
            let (url, response) = try await URLSession.shared.download(from: templateURL)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200..<300).contains(code) {
                throw CreateError(errorDescription: "Download for template URL \(templateURL.absoluteString) returned error: \(code)")
            }
            return url
        }.get()

        let projectFolderURL = URL(fileURLWithPath: projectFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolderURL, withIntermediateDirectories: true)

        await run(with: out, "Unpacking template \(createOptions.template) (\(ByteCountFormatter().string(fromByteCount: Int64((try? downloadURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)))) for project \(pname)", ["unzip", downloadURL.path, "-d", projectFolderURL.path])

        let packageJSONString = try await run(with: out, "Checking project \(pname)", ["swift", "package", "dump-package", "--package-path", projectFolderURL.path]).get().stdout

        let packageJSON = try JSONDecoder().decode(PackageManifest.self, from: Data(packageJSONString.utf8))
        let appName = packageJSON.products.first?.name ?? "App"

        await run(with: out, "Resolving \(pname)/\(appName)", ["swift", "package", "resolve", "--verbose", "--package-path", projectFolderURL.path])

        if buildOptions.build == true {
            await run(with: out, "Building \(pname)/\(appName)", ["swift", "build", "--verbose", "-c", createOptions.configuration, "--package-path", projectFolderURL.path])
        }

        if buildOptions.test == true {
            await run(with: out, "Test \(pname)/\(appName)", ["swift", "test", "-j", "1", "--verbose", "-c", createOptions.configuration, "--package-path", projectFolderURL.path])
        }

        // TODO: make code project match project name
        let projectPath = projectFolderURL.path + "/" + appName + ".xcodeproj"
        if !FileManager.default.isReadableFile(atPath: projectPath) {
            await out.write(status: .warn, "Warning: path did not exist at: \(projectPath)")
        }

        if open == true {
            await run(with: out, "Launching project \(projectPath)", ["open", projectPath])
        }

        await out.write(status: .pass, "Created project: \(projectPath)")
    }

    public struct CreateError : LocalizedError {
        public var errorDescription: String?
    }
}
