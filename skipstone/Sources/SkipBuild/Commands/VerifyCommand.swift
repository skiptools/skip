// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ArgumentParser
import Universal
//import TSCUtility

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct VerifyCommand: SkipCommand, StreamingCommand, ProjectCommand, ToolOptionsCommand {
    typealias Output = MessageBlock

    static var configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Verify Skip project",
        usage: """
        # Verify the current project
        skip verify

        # Verify a project at a specific path
        skip verify --project path/to/project
        """,
        discussion: """
        Validates the structure and configuration of a Skip project, checking \
        Package.swift layout, skip.yml files, and module dependencies.
        """,
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(help: ArgumentHelp("Project folder", valueName: "dir"))
    var project: String = "."

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Validate free project"))
    var free: Bool? = nil

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Validate fastlane config"))
    var fastlane: Bool? = nil

    // we do not fail fast by default for verify since it is useful to see all the parts that failed
    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Fail immediately when an error occurs"))
    var failFast: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Attempt to automatically fix issues"))
    var fix: Bool = false

    func performCommand(with out: MessageQueue) async {
        await withLogStream(with: out) {
            try await performVerifyCommand(project: project, autofix: fix, free: free, fastlane: fastlane, with: out)
        }
    }
}


struct NoResultOutputError : LocalizedError {
    var errorDescription: String?
}

extension ToolOptionsCommand where Self : StreamingCommand {

    func performVerifyCommand(project projectPath: String, autofix: Bool, free: Bool? = nil, fastlane: Bool? = nil, with out: MessageQueue) async throws {
        let projectFolderURL = URL(fileURLWithPath: projectPath, isDirectory: true)

        func checkFolder(_ dir: URL, _ message: String? = nil) async -> Bool {
            await checkFile(dir, with: out, title: message ?? "Check folder: \(dir.lastPathComponents(2))") { title, url in
                return CheckStatus(status: url.isDirectoryFile == true ? .pass : .fail, message: message ?? "Check folder: \(dir.lastPathComponents(2))")
            }
        }

        /// Returns either the value of the flag, or, if nil, whether any of the specified files exist at the given paths.
        ///
        /// This is used to provide a default value for otherwise unspecified values.
        func flagOrFiles(_ flag: Bool?, _ fileURLs: URL...) -> Bool {
            if let flag = flag {
                return flag
            }

            // return true if any of the file URLs exist
            return fileURLs.first { $0.isReadableFile == true } != nil
        }

        @discardableResult func checkFileContents(_ file: URL, message: String? = nil, length: Range<Int>? = nil, trailingContents: Array<String> = [], isURL: Bool = false) async -> Bool {
            await checkFile(file, with: out, title: message) { title, url in
                if url.isRegularFile != true {
                    return CheckStatus(status: .fail, message: "Missing file: \(file.relativePath)")
                }

                func trim(_ string: String) -> String {
                    string.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                let contents = try String(contentsOf: url, encoding: .utf8)
                if !trailingContents.isEmpty,
                   !trailingContents.contains(where: {
                       trim(contents).hasSuffix(trim($0)) || trim(contents).hasPrefix(trim($0))
                   }) {
                    return CheckStatus(status: .fail, message: "Contents did not match expected contents: \(file.relativePath)")
                }

                if let length, contents.count < length.lowerBound {
                    return CheckStatus(status: .fail, message: "Contents too short (\(contents.count) < \(length.lowerBound)): \(file.relativePath)")
                }

                if let length, contents.count > length.upperBound {
                    return CheckStatus(status: .fail, message: "Contents too long (\(contents.count) < \(length.upperBound)): \(file.relativePath)")
                }

                if isURL == true && (contents.hasPrefix("https://") == false || URL(string: contents.trimmingCharacters(in: .newlines)) == nil) {
                    return CheckStatus(status: .fail, message: "Contents not a valid URL: \(file.relativePath)")
                }

                return CheckStatus(status: .pass, message: message ?? "Verify file: \(file.relativePath)")
            }
        }

        let packageJSON = try await parseSwiftPackage(with: out, at: projectPath)
        let packageName = packageJSON.name
        guard var moduleName = packageJSON.products.first?.name else {
            throw AppVerifyError(errorDescription: "No products declared in package \(packageName) at \(projectPath)")
        }
        if moduleName.hasSuffix("App") {
            moduleName = moduleName.dropLast(3).description
        }

        //let project = try FrameworkProjectLayout(root: projectFolderURL)
        //let sourcesDir = URL(fileURLWithPath: "Sources", isDirectory: true, relativeTo: projectFolderURL)

        let licenseGPL = URL(fileURLWithPath: "LICENSE.GPL", isDirectory: false, relativeTo: projectFolderURL)
        let licenseLGPL = URL(fileURLWithPath: "LICENSE.LGPL", isDirectory: false, relativeTo: projectFolderURL)
        let licenseTXT = URL(fileURLWithPath: "LICENSE.txt", isDirectory: false, relativeTo: projectFolderURL)
        if flagOrFiles(free, licenseGPL, licenseLGPL) {
            // either GPL or LGPL license file must exist for it to pass the free test
            if licenseLGPL.isReadableFile == true {
                await checkFileContents(licenseLGPL, message: "Verify free software license", trailingContents: [SourceLicense.lgpl3.licenseContents])
            } else if licenseGPL.isReadableFile == true {
                await checkFileContents(licenseGPL, message: "Verify free software license", trailingContents: [SourceLicense.gpl2.licenseContents, SourceLicense.gpl3.licenseContents])
            } else if licenseTXT.isReadableFile == true {
                await checkFileContents(licenseTXT, message: "Verify free software license", trailingContents: [SourceLicense.mpl2.licenseContents, SourceLicense.gpl2.licenseContents, SourceLicense.gpl3.licenseContents, SourceLicense.lgpl3.licenseContents, SourceLicense.osl.licenseContents, SourceLicense.eupl.licenseContents])
            }
        }

        let androidDir = URL(fileURLWithPath: "Android", isDirectory: true, relativeTo: projectFolderURL)
        let darwinDir = URL(fileURLWithPath: "Darwin", isDirectory: true, relativeTo: projectFolderURL)
        let isAppProject = androidDir.fileExists(isDirectory: true) && darwinDir.fileExists(isDirectory: true)

        if isAppProject {
            func validateLayoutURL(url: URL, isDirectory: Bool) throws {
                if isDirectory {
                    return // don't bother checking directories (like Resources, which might be empty)
                }

                if FileManager.default.fileExists(atPath: url.path) {
                    return
                }

                // Source code file names have changed between releases, and are permitted to be renamed by the user
                if url.path.hasSuffix(".swift") || url.path.hasSuffix(".kt") {
                    return
                }

                // Resources can be added or removed
                if url.path.hasSuffix(".json") {
                    return
                }

                throw MissingProjectFileError(errorDescription: "Expected path at \(url.path) does not exist")
            }

            let project = try AppProjectLayout(moduleName: moduleName, root: projectFolderURL, check: validateLayoutURL)

            await checkFile(project.skipEnv, with: out) { title, url in
                //let plist = try PLIST.parse(Data(contentsOf: url))
                return CheckStatus(status: .pass)
            }

            await checkFile(project.androidGradleSettings, with: out) { title, url in
                let expectedContents = AppProjectLayout.createSettingsGradle()
                let actualContents = try String(contentsOf: url)
                if expectedContents.trimmingCharacters(in: .whitespacesAndNewlines) != actualContents.trimmingCharacters(in: .whitespacesAndNewlines) {
                    if autofix {
                        try expectedContents.write(to: url, atomically: false, encoding: .utf8)
                        return CheckStatus(status: .warn, message: "\(title): updated contents")
                    } else {
                        return CheckStatus(status: .warn, message: "\(title): out of date: run skip verify --fix")
                    }
                } else {
                    return CheckStatus(status: .pass)
                }
            }

            await checkFile(project.androidManifest, with: out) { title, url in
                let node = try XMLNode.parse(data: Data(contentsOf: url), options: [.processNamespaces], entityResolver: nil)
                guard let manifest = node.elementChildren.first else {
                    return CheckStatus(status: .fail, message: "Verify AndroidManifest.xml: root node is not <manifest>: \(node.elementName)")
                }
                if manifest.elementName != "manifest" {
                    return CheckStatus(status: .fail, message: "Verify AndroidManifest.xml: root node is not <manifest>: \(manifest.elementName)")
                }
                guard let application = manifest.elementChildren.first(where: { $0.elementName == "application" }) else {
                    return CheckStatus(status: .fail, message: "Verify AndroidManifest.xml: <application> node not found")
                }
                // TODO: add more checks for application and uses-permission…
                let _ = application

                return CheckStatus(status: .pass)
            }

            if flagOrFiles(fastlane, project.darwinFastlaneFolder, project.androidFastlaneFolder) {
                if await checkFolder(project.darwinFastlaneFolder) {
                    let metadataDir = project.darwinFastlaneMetadataFolder
                    for locale in ["en-US"] {
                        let enUSDir = metadataDir.appendingPathComponent(locale, isDirectory: true)
                        await checkFileContents(enUSDir.appendingPathComponent("title.txt"), length: 1..<30)
                        await checkFileContents(enUSDir.appendingPathComponent("subtitle.txt"), length: 1..<30)
                        await checkFileContents(enUSDir.appendingPathComponent("description.txt"), length: 1..<4000)
                        await checkFileContents(enUSDir.appendingPathComponent("keywords.txt"), length: 1..<255)
                        await checkFileContents(enUSDir.appendingPathComponent("release_notes.txt"), length: 1..<4000)
                        await checkFileContents(enUSDir.appendingPathComponent("version_whats_new.txt"), length: 1..<4000)
                        await checkFileContents(enUSDir.appendingPathComponent("software_url.txt"), length: 1..<255, isURL: true)
                        await checkFileContents(enUSDir.appendingPathComponent("privacy_url.txt"), length: 1..<255, isURL: true)
                        await checkFileContents(enUSDir.appendingPathComponent("support_url.txt"), length: 1..<255, isURL: true)

                        // TODO: replicate Fastlane's deliver checks like:
                        /*
                         [14:03:21]: ✅  Passed: No negative  sentiment
                         [14:03:21]: ✅  Passed: No placeholder text
                         [14:03:21]: ✅  Passed: No mentioning  competitors
                         [14:03:21]: ✅  Passed: No future functionality promises
                         [14:03:21]: ✅  Passed: No words indicating test content
                         [14:03:21]: ✅  Passed: No curse words
                         [14:03:21]: ✅  Passed: No words indicating your IAP is free
                         [14:03:21]: ✅  Passed: Incorrect, or missing copyright date
                         [14:03:21]: ✅  Passed: No broken urls

                         */
                    }
                }

                if await checkFolder(project.androidFastlaneFolder) {
                    let metadataDir = project.androidFastlaneMetadataFolder
                    for locale in ["en-US"] {
                        let enUSDir = metadataDir.appendingPathComponent(locale, isDirectory: true)
                        await checkFileContents(enUSDir.appendingPathComponent("title.txt"), length: 1..<30)
                        await checkFileContents(enUSDir.appendingPathComponent("short_description.txt"), length: 1..<100)
                        await checkFileContents(enUSDir.appendingPathComponent("full_description.txt"), length: 30..<4000)
                    }
                }
            }
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
