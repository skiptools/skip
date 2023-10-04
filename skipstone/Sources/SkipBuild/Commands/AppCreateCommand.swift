import Foundation
import ArgumentParser
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AppCreateCommand: MessageCommand {
    static var configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new Skip app project from a template",
        shouldDisplay: true)

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

    func performCommand(with out: Messenger) async throws {
        let pname = projectName.split(separator: "/").last?.description ?? projectName

        out.write(status: nil, "Creating project \(pname) from template \(createOptions.template)")

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
        let downloadURL: URL = templateURL.isFileURL ? templateURL : try await outputOptions.monitor(with: out, "Downloading template \(templateURL.absoluteString)", resultHandler: { result in
            (result, nil) // TODO: show positive message
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

        await outputOptions.run(with: out, "Unpacking template \(createOptions.template) (\(ByteCountFormatter().string(fromByteCount: Int64((try? downloadURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)))) for project \(pname)", ["unzip", downloadURL.path, "-d", projectFolderURL.path])

        let packageJSONString = try await outputOptions.run(with: out, "Checking project \(pname)", [toolOptions.swift, "package", "dump-package", "--package-path", projectFolderURL.path]).get().stdout

        let packageJSON = try JSONDecoder().decode(PackageManifest.self, from: Data(packageJSONString.utf8))
        _ = packageJSON
        
        if buildOptions.build == true {
            await outputOptions.run(with: out, "Building \(pname)", [toolOptions.swift, "build", "-c", createOptions.configuration, "--package-path", projectFolderURL.path])
        }

        if buildOptions.test == true {
            await outputOptions.run(with: out, "Testing \(pname)", [toolOptions.swift, "test", "-j", "1", "-c", createOptions.configuration, "--package-path", projectFolderURL.path])
        }

        let projectPath = projectFolderURL.path + "/" + "App.xcodeproj"
        if !FileManager.default.isReadableFile(atPath: projectPath) {
            out.write(status: .warn, "Warning: path did not exist at: \(projectPath)")
        }

        if open == true {
            await outputOptions.run(with: out, "Launching project \(projectPath)", ["open", projectPath])
        }

        out.write(status: .pass, "Created project: \(projectPath)")
    }

    public struct CreateError : LocalizedError {
        public var errorDescription: String?
    }
}
