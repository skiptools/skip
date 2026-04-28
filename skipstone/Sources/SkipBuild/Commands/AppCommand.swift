// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ArgumentParser
import TSCBasic
import SkipSyntax

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AppCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "app",
        abstract: "Build, run, and manage Skip apps",
        discussion: """
        Commands for working with conventional Skip app projects that contain a \
        Project.xcworkspace alongside Darwin and Android folders.
        """,
        shouldDisplay: true,
        subcommands: [
            AppLaunchCommand.self,
        ])
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AppLaunchCommand: MessageCommand, ToolOptionsCommand {
    static var configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Build and launch the Skip app on iOS simulator and/or Android emulator",
        usage: """
        # Build and launch on both iOS simulator and Android emulator (default)
        skip app launch

        # Build and launch a release build
        skip app launch --configuration release

        # Build and launch only the iOS app on the booted simulator
        skip app launch --ios

        # Build and launch only the Android app via the Skip plugin
        skip app launch --android
        """,
        discussion: """
        Builds the Skip app via xcodebuild and installs and launches it on the booted iOS \
        simulator. The PRODUCT_NAME and PRODUCT_BUNDLE_IDENTIFIER are read from the Skip.env \
        configuration file. By default both the iOS and Android targets are built and launched. \
        Use --ios to skip the Android build (the Skip plugin is disabled), or --android to skip \
        the iOS install/launch steps.
        """,
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(name: [.customShort("c"), .long], help: ArgumentHelp("Build configuration (debug or release)", valueName: "config"))
    var configuration: BuildConfiguration = .debug

    @Flag(help: ArgumentHelp("Build and launch only the iOS app (skip the Android build)"))
    var ios: Bool = false

    @Flag(help: ArgumentHelp("Build and launch only the Android app (skip iOS install/launch)"))
    var android: Bool = false

    @Option(help: ArgumentHelp("Project folder", valueName: "dir"))
    var project: String = "."

    func validate() throws {
        if ios && android {
            throw ValidationError("--ios and --android are mutually exclusive")
        }
    }

    func performCommand(with out: MessageQueue) async throws {
        await withLogStream(title: "Launch Skip app", with: out) {
            try await runAppLaunch(with: out)
        }
    }

    private func runAppLaunch(with out: MessageQueue) async throws {
        let projectURL = URL(fileURLWithPath: project, isDirectory: true)
        let workspaceURL = projectURL.appendingPathComponent("Project.xcworkspace", isDirectory: true)
        let skipEnvURL = projectURL.appendingPathComponent("Skip.env", isDirectory: false)

        guard FileManager.default.fileExists(atPath: workspaceURL.path) else {
            throw error("Not a conventional Skip app project: missing Project.xcworkspace at \(workspaceURL.path)")
        }
        guard FileManager.default.fileExists(atPath: skipEnvURL.path) else {
            throw error("Not a conventional Skip app project: missing Skip.env at \(skipEnvURL.path)")
        }

        let envContents = try String(contentsOf: skipEnvURL, encoding: .utf8)
        let envValues = parseXCConfig(contents: envContents)
        guard let productName = envValues.first(where: { $0.key == "PRODUCT_NAME" })?.value else {
            throw error("PRODUCT_NAME not found in \(skipEnvURL.path)")
        }
        guard let bundleIdentifier = envValues.first(where: { $0.key == "PRODUCT_BUNDLE_IDENTIFIER" })?.value else {
            throw error("PRODUCT_BUNDLE_IDENTIFIER not found in \(skipEnvURL.path)")
        }

        let darwinFolder = projectURL.appendingPathComponent("Darwin", isDirectory: true)
        let xcodeProjectURL = darwinFolder.appendingPathComponent("\(productName).xcodeproj", isDirectory: true)
        let appSchemeName = try await resolveAppSchemeName(schemeName: nil, xcodeProjectURL: xcodeProjectURL, out: out)

        let derivedDataPath = projectURL.appendingPathComponent("\(darwinBuildFolder)/DerivedData", isDirectory: true).path

        var buildEnv: [String: String] = [:]
        if ios {
            // iOS-only: disable the Skip Android build/launch entirely
            buildEnv["SKIP_PLUGIN_DISABLED"] = ""
            buildEnv["SKIP_ACTION"] = "none"
        }

        try await run(with: out, "Build \(appSchemeName)", [
            "xcodebuild",
            "-workspace", workspaceURL.path,
            "-scheme", appSchemeName,
            "-sdk", "iphonesimulator",
            "-configuration", configuration.rawValue.capitalized,
            "-skipPackagePluginValidation",
            "-skipMacroValidation",
            "-derivedDataPath", derivedDataPath,
        ], additionalEnvironment: buildEnv)

        // When building Android-only, the iOS build above still produced a Darwin app, but we
        // skip installing and launching it on the simulator.
        if android {
            return
        }

        let appPath = derivedDataPath + "/Build/Products/\(configuration.rawValue.capitalized)-iphonesimulator/\(productName).app"

        try await run(with: out, "Install \(productName).app", [
            "xcrun", "simctl", "install", "booted", appPath,
        ])

        try await run(with: out, "Launch \(productName)", [
            "xcrun", "simctl", "launch", "booted", bundleIdentifier,
        ])
    }
}
