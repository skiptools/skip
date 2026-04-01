// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ArgumentParser
import TSCBasic
import SkipSyntax

extension TestCaseMode : ExpressibleByArgument { }

/// Common functions for managing Skip Packages common protocol for `AppCommand` and `LibCommand`.
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
protocol PackageCommand : SkipCommand, ToolOptionsCommand, OutputOptionsCommand {
}

protocol CreateOptionsCommand : ParsableArguments {
    /// This command's create options
    var createOptions: CreateOptions { get }
}

enum ProjectMode : String, EnumerableFlag {
    case nativeApp
    case transpiledApp
    case nativeModel
    case transpiledModel
}

struct NativeMode : OptionSet {
    static let nativeModel = NativeMode(rawValue: 1 << 0)
    static let nativeApp = NativeMode(rawValue: 1 << 1)

    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }
}


struct ProjectOptions : ParsableArguments {
    /// This is not part of `CreateOptions` since it is non-optional, and the `CreateCommand` must accept no arguments
    @Flag
    var projectMode: [ProjectMode]
}

struct CreateOptions : ParsableArguments {
    @Option(name: [.customShort("d"), .long], help: ArgumentHelp("Base folder for project creation", valueName: "directory"))
    var dir: String?

//    @Option(name: [.customShort("c"), .long], help: ArgumentHelp("Configuration debug/release", valueName: "c"))
//    var configuration: BuildConfiguration = .debug

    // Template options: Hidden because they are not yet supported

    @Option(name: [.long], help: ArgumentHelp("Template name/ID for new project", valueName: "id", visibility: .hidden))
    var template: String = "skipapp"

    @Option(name: [.long], help: ArgumentHelp("The host name for the template repository", valueName: "host", visibility: .hidden))
    var templateHost: String = "https://github.com"

    @Option(name: [.long], help: ArgumentHelp("A path to the template zip file to use", valueName: "zip", visibility: .hidden))
    var templateFile: String?

    @Option(help: ArgumentHelp("Resource folder name"))
    var resourcePath: String = "Resources"

    @Option(help: ArgumentHelp("Swift version for project"))
    var swiftPackageVersion: String = defaultSwiftPackageVersion

    /// The defaut Package.swift version to create when initializing a project
    static let defaultSwiftPackageVersion = "6.1"

    @Option(help: ArgumentHelp("Minimum iOS version to target"))
    var iosMinVersion: Double = 17.0

    @Option(help: ArgumentHelp("Minimum macOS version to target"))
    var macosMinVersion: Double?

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Create library dependencies between modules", valueName: "show"))
    var chain: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Add SKIP_ZERO environment check to Package.swift", valueName: "zero"))
    var zero: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Create a local git repository for the app", valueName: "create"))
    var gitRepo: Bool = false

    @Flag(help: ArgumentHelp("Create package with free software license", valueName: "free"))
    var free: Bool = false

    @Flag(help: ArgumentHelp("Create a standard app fair project", visibility: .hidden))
    var appfair: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Display a file system tree summary of the new files", valueName: "show"))
    var showTree: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Whether native model should use kotlincompat", valueName: "kotlincompat"))
    var kotlincompat: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Whether transpiled model should be bridged", valueName: "bridged"))
    var bridged: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Whether to create test modules", valueName: "tests"))
    var moduleTests: Bool? = nil

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Whether to create fastlane metadata", valueName: "enable"))
    var fastlane: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Whether to create github metadata", valueName: "enable"))
    var github: Bool = false

    @Option(help: ArgumentHelp("Test case style: testing or xctest", valueName: "mode"))
    var testCaseMode: TestCaseMode = .testing

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

    func projectOptionValues(projectName: String) -> ProjectOptionValues {
        ProjectOptionValues(projectName: projectName, swiftPackageVersion: self.swiftPackageVersion, iOSMinVersion: self.iosMinVersion, macOSMinVersion: self.macosMinVersion, chain: self.chain, gitRepo: self.gitRepo, appfair: self.appfair, free: self.free || self.appfair, zero: self.zero, github: self.github, fastlane: self.fastlane, testCaseMode: self.testCaseMode)
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
