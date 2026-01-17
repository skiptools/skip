// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ArgumentParser
import SkipSyntax
#if canImport(SkipDriveExternal)
import SkipDriveExternal

extension GradleCommand : GradleHarness { }
//fileprivate let gradleCommandEnabled = true
fileprivate let gradleCommandEnabled = false // advanced command, so do not display
#else
fileprivate let gradleCommandEnabled = false
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct GradleCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "gradle",
        abstract: "Launch the gradle build tool",
        shouldDisplay: gradleCommandEnabled)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(help: ArgumentHelp("App package name", valueName: "package-name"))
    var package: String?

    @Option(help: ArgumentHelp("App module name", valueName: "ModuleName"))
    var module: String?

    @Option(help: ArgumentHelp("Project folder", valueName: "dir"))
    var project: String = "."

    @Argument(parsing: .allUnrecognized, help: ArgumentHelp("The arguments to pass to the gradle command"))
    var gradleArguments: [String]

    func run() async throws {
        // when the environment "SKIP_ACTION" is set to "none", completely ignore the gradle launch command; this is to provide backwards compatibility for pre-existing projects that do not have updated Xcode target's Build Phases "Run script" actions.
        // https://github.com/skiptools/skip/issues/408
        // TODO: should we just handle all the short-circuit environment variables here, like SKIP_ZERO, ENABLE_PREVIEWS, and ACTION="insall"?
        if ProcessInfo.processInfo.environment["SKIP_ACTION"] == "none" {
            print("note: skipping skip due to SKIP_ACTION none")
            return
        }
        do {
            #if !canImport(SkipDriveExternal)
            throw SkipDriveError(errorDescription: "SkipDrive not linked")
            #else
            try await self.gradleExec(in: projectRoot(forModule: module, packageName: package, projectFolder: project), moduleName: module, packageName: package, arguments: gradleArguments)
            #endif
        } catch {
            // output error message
            print("\(error.localizedDescription)")
            throw error
        }
    }
}

