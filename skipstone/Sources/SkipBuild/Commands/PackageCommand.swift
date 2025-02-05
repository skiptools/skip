import Foundation
import ArgumentParser
import TSCBasic
import SkipSyntax

/// Common functions for managing Skip Packages common protocol for `AppCommand` and `LibCommand`.
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
protocol PackageCommand : SkipCommand, ToolOptionsCommand, OutputOptionsCommand {

}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AppCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "app",
        abstract: "Commands to manage application projects",
        shouldDisplay: false,
        subcommands: [
            AppCreateCommand.self
        ])
}


@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct LibCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "lib",
        abstract: "Commands to manage library projects",
        shouldDisplay: false,
        subcommands: [
            LibInitCommand.self
        ])
}

protocol CreateOptionsCommand : ParsableArguments {
    /// This command's create options
    var createOptions: CreateOptions { get }
}

struct CreateOptions : ParsableArguments {
    @Option(help: ArgumentHelp("Application identifier"))
    var id: String = "net.example.MyApp"

    @Option(name: [.customShort("d"), .long], help: ArgumentHelp("Base folder for project creation", valueName: "directory"))
    var dir: String?

    @Option(name: [.customShort("c"), .long], help: ArgumentHelp("Configuration debug/release", valueName: "c"))
    var configuration: BuildConfiguration = .debug

    @Option(name: [.long], help: ArgumentHelp("Template name/ID for new project", valueName: "id"))
    var template: String = "skipapp"

    @Option(name: [.long], help: ArgumentHelp("The host name for the template repository", valueName: "host"))
    var templateHost: String = "https://github.com"

    @Option(name: [.long], help: ArgumentHelp("A path to the template zip file to use", valueName: "zip"))
    var templateFile: String?

//    @Option(help: ArgumentHelp("The package dependencies for this module"))
//    var dependency: [String] = ["skip", "skip-foundation"]

    @Option(help: ArgumentHelp("Resource folder name"))
    var resourcePath: String = "Resources"

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Create library dependencies between modules", valueName: "show"))
    var chain: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Add SKIP_ZERO environment check to Package.swift", valueName: "zero"))
    var zero: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Create a local git repository for the app", valueName: "create"))
    var gitRepo: Bool = false

    @Flag(help: ArgumentHelp("Create package with free software license", valueName: "free"))
    var free: Bool = false

    @Flag(help: ArgumentHelp("Create a standard app fair project"))
    var appfair: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Display a file system tree summary of the new files", valueName: "show"))
    var showTree: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Whether to create a native model layer", valueName: "native"))
    var native: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Whether to create test modules", valueName: "tests"))
    var moduleTests: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Whether to create fastlane metadata", valueName: "enable"))
    var fastlane: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Whether to create github metadata", valueName: "enable"))
    var github: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Validate generated Package.swift files", valueName: "validate"))
    var validatePackage: Bool = true

    var projectTemplateURL: URL {
        get throws {
            let url: URL?
            let templateParts = template.split(separator: "/")

            // construct, e.g.:
            // https://github.com/skiptools/skipapp/releases/latest/download/skip-template-source.zip
            if let templateFile = templateFile {
                let fileURL = URL(fileURLWithPath: templateFile)
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    throw SkipDriveError(errorDescription: "template-file could not be found at: \(templateFile)")
                }
                return fileURL
            } else if templateParts.isEmpty {
                throw SkipDriveError(errorDescription: "Sample named “\(template)” must be a repository name")
            } else if templateParts.count == 1, let repo = templateParts.last {
                url = URL(string: templateHost + "/skiptools/\(repo)")
            } else if templateParts.count == 2, let org = templateParts.first, let repo = templateParts.last {
                url = URL(string: templateHost + "/\(org)/\(repo)")
            } else {
                // if it is not "repo" or "org/repo", then assume it is a full URL to the actual template zip
                url = URL(string: template)
                if let url = url {
                    return url // return the actual URL to the template zip
                }
            }

            guard let url = url else {
                throw SkipDriveError(errorDescription: "Sample named \(template) could not be found")
            }

            let templateURL = url.appending(path: "releases/latest/download/skip-template-source.zip")
            return templateURL
        }
    }
}

extension OutputOptionsCommand {
    /// Output an ASCII tree representation of the file system as a result of the command
    func showFileTree(in dir: AbsolutePath, folderName: String = ".", with out: MessageQueue) async {
        do {
            let tree = try localFileSystem.treeASCIIRepresentation(at: dir, folderName: folderName, hideHiddenFiles: true)
            await out.write(status: nil, tree)
        } catch {
            await out.yield(MessageBlock(error: error))
        }
    }
}
