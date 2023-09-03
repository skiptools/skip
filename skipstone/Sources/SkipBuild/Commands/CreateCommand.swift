import Foundation
import ArgumentParser

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct CreateCommand: SkipCommand {
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

    func run() async throws {
        outputOptions.write("Creating project \(projectName) from template \(createOptions.template)")

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

        let downloadURL: URL = try await outputOptions.monitor("Downloading template \(createOptions.template)") {
            let downloadURL = try createOptions.projectTemplateURL
            let (url, response) = try await URLSession.shared.download(from: downloadURL)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200..<300).contains(code) {
                throw CreateError(errorDescription: "Download for template URL \(downloadURL.absoluteString) returned error: \(code)")
            }
            return url
        }

        let projectFolderURL = URL(fileURLWithPath: projectFolder, isDirectory: true)

        try await outputOptions.run("Unpacking template \(createOptions.template) for project \(projectName)", ["unzip", downloadURL.path, "-d", projectFolderURL.path])

        let packageJSONString = try await outputOptions.run("Checking project \(projectName)", [toolOptions.swift, "package", "dump-package", "--package-path", projectFolderURL.path]).out

        let packageJSON = try JSONDecoder().decode(PackageManifest.self, from: Data(packageJSONString.utf8))

        if buildOptions.build == true {
            try await outputOptions.run("Building project \(projectName) for package \(packageJSON.name)", [toolOptions.swift, "build", "-c", createOptions.configuration, "--package-path", projectFolderURL.path])
        }

        if buildOptions.test == true {
            try await outputOptions.run("Testing project \(projectName)", [toolOptions.swift, "test", "-j", "1", "-c", createOptions.configuration, "--package-path", projectFolderURL.path])
        }

        let projectPath = projectFolderURL.path + "/" + "App.xcodeproj"
        if !FileManager.default.isReadableFile(atPath: projectPath) {
            outputOptions.write("Warning: path did not exist at: \(projectPath)", error: true, flush: true)
        }

        if open == true {
            try await outputOptions.run("Launching project \(projectPath)", ["open", projectPath])
        }

        outputOptions.write("Created project: \(projectPath)")
    }

    public struct CreateError : LocalizedError {
        public var errorDescription: String?
    }
}

struct CreateOptions: ParsableArguments {
    /// TODO: dynamic loading of template data
    static let templates = [
        ProjectTemplate(id: "skipapp", url: URL(string: "https://github.com/skiptools/skipapp/releases/latest/download/skip-template-source.zip")!, localizedTitle: [
            "en": "Skip Sample App"
        ], localizedDescription: [
            "en": """
                A Skip sample app for iOS and Android.
                """
        ])
    ]

    @Option(help: ArgumentHelp("Application identifier"))
    var id: String = "net.example.MyApp"

    @Option(name: [.customShort("d"), .long], help: ArgumentHelp("Base folder for project creation", valueName: "directory"))
    var dir: String?

    @Option(name: [.customShort("c"), .long], help: ArgumentHelp("Configuration debug/release", valueName: "c"))
    var configuration: String = "debug"

    @Option(name: [.customShort("t"), .long], help: ArgumentHelp("Template name/ID for new project", valueName: "id"))
    var template: String = templates.first!.id

    var projectTemplateURL: URL {
        get throws {
            guard let sample = Self.templates.first(where: { $0.id == template }) else {
                throw SkipDriveError(errorDescription: "Sample named \(template) could not be found")
            }
            return sample.url
        }
    }
}

