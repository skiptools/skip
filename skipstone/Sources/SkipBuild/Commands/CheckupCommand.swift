// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ArgumentParser
import SkipSyntax
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct CheckupCommand: MessageCommand, ToolOptionsCommand {
    static var configuration = CommandConfiguration(
        commandName: "checkup",
        abstract: "Run tests to ensure Skip is in working order",
        usage: """
# Perform a basic system checkup
skip checkup

# Perform a system checkup for native app support
skip checkup --native
""",
        discussion: """
This command performs a full system checkup to ensure that Skip can create and build a sample project. It runs all the checks performed by skip doctor, and also creates and builds a conventional Skip app project.
""",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(name: [.customShort("c"), .long], help: ArgumentHelp("Configuration debug/release", valueName: "c"))
    var configuration: BuildConfiguration = .debug

    @Flag(help: ArgumentHelp("Check twice that sample build outputs produce identical artifacts", valueName: "verify"))
    var doubleCheck: Bool = false

    @Flag(help: ArgumentHelp("Generate native app when running checkup", valueName: "native"))
    var native: Bool = false

    @Flag(help: ArgumentHelp("Generate native app when running checkup", valueName: "native"))
    var nativeApp: Bool = false

    @Flag(help: ArgumentHelp("Generate native module when running checkup", valueName: "native"))
    var nativeModel: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Fail immediately when an error occurs"))
    var failFast: Bool = true

    @Option(name: [.long], help: ArgumentHelp("Name of checkup project", valueName: "name"))
    var projectName: String = "hello-skip"

    @Option(name: [.long], help: ArgumentHelp("Name of checkup project module", valueName: "module-name"))
    var moduleName: String = "HelloSkip"

    /// The native mode to use for checkup, which can be a combination of native app and native model.
    var nativeMode: NativeMode {
        var mode: NativeMode = []
        if self.nativeApp {
            mode.insert(.nativeApp)
        }
        if self.nativeModel {
            mode.insert(.nativeModel)
        }
        if self.native {
            mode.insert(.nativeModel)
            #if !os(Linux) // Linux does not yet supporting building native apps
            mode.insert(.nativeApp)
            #endif
        }
        return mode
    }

    var moduleMode: ModuleMode {
        if nativeMode.contains(.nativeApp) {
            if nativeMode.contains(.nativeModel) {
                return .nativeBridged
            } else {
                return .native
            }
        } else {
            return .transpiled
        }
    }

    var isNative: Bool {
        !nativeMode.isEmpty
    }

    func performCommand(with out: MessageQueue) async {
        await withLogStream(with: out) {
            try await runCheckup(with: out)
        }
    }

    func runCheckup(with out: MessageQueue) async throws {
        try await runDoctor(checkNative: isNative, with: out)

        @Sendable func buildSampleProject(packageResolvedURL: URL? = nil) async throws -> (projectURL: URL, project: AppProjectLayout, artifacts: [URL: String?]) {
            let primary = packageResolvedURL == nil
            // a random temporary folder for the project
            let tmpdir = NSTemporaryDirectory() + "/" + UUID().uuidString
            try FileManager.default.createDirectory(atPath: tmpdir, withIntermediateDirectories: true)

            //let checkupModules = try [PackageModule(parse: moduleName), PackageModule(parse: "HelloModel"), PackageModule(parse: "HelloCore")]
            var checkupModules = [PackageModule(moduleName: moduleName)]
            // when checking a native package, create a second module that will have the bridge dependency
            if nativeMode.contains(.nativeModel) {
                checkupModules += [PackageModule(moduleName: "HelloModel")]
            }
            let runTests = primary && nativeMode.isEmpty

            let options = ProjectOptionValues(projectName: projectName, swiftPackageVersion: CreateOptions.defaultSwiftPackageVersion, iOSMinVersion: 17.0, chain: true, gitRepo: false, appfair: false, free: true, zero: !isNative, github: true, fastlane: true, testCaseMode: .testing)

            // create a project differently based on the index, but the ultimate binary output should be identical
            return try await initSkipProject(
                options: options,
                modules: checkupModules,
                resourceFolder: "Resources",
                dir: URL(fileURLWithPath: tmpdir, isDirectory: true),
                verify: false,
                configuration: self.configuration,
                build: primary,
                test: runTests,
                returnHashes: doubleCheck,
                messagePrefix: !primary ? "Re-" : "",
                showTree: false,
                app: true,
                appid: "skip.hello.App",
                icon: nil,
                version: "1.0.0",
                nativeMode: nativeMode,
                moduleMode: moduleMode,
                moduleTests: runTests,
                validatePackage: true,
                packageResolved: packageResolvedURL,
                apk: true,
                ipa: true,
                with: out
            )
        }

        // build a sample project (twice when performing a double-check)
        let (p1URL, project, p1) = try await buildSampleProject()
        let packageResolvedURL = p1URL.appendingPathComponent("Package.resolved", isDirectory: false)
        try registerPluginFingerprint(for: packageResolvedURL)
        if doubleCheck {
            // use the Package.resolved from the initial build to ensure that use double-check build uses the same dependency versions as the initial build
            // otherwise if a new version of a Skip library is tagged in between the two builds, the checksums won't match
            let (_, project2, p2) = try await buildSampleProject(packageResolvedURL: packageResolvedURL)

            let (_, _) = (project, project2)
            
            if let ipa1 = p1.filter({ $0.0.pathExtension == "ipa" }).first,
               let ipa2 = p2.filter({ $0.0.pathExtension == "ipa" }).first {
                await out.write(status: ipa1.value == ipa2.value ? .pass : .fail, "Double-check IPA file hashes" + (ipa1.value == ipa2.value ? "" : " (diffoscope \(ipa1.key.path.replacingTmpDir) \(ipa2.key.path.replacingTmpDir))"))
            } else {
                await out.write(status: .fail, "Double-check IPA failed due to missing artifacts")
            }

            if let apk1 = p1.filter({ $0.0.pathExtension == "apk" }).first,
               let apk2 = p2.filter({ $0.0.pathExtension == "apk" }).first {
                await out.write(status: apk1.value == apk2.value ? .pass : .fail, "Double-check APK file hashes" + (apk1.value == apk2.value ? "" : " (diffoscope \(apk1.key.path.replacingTmpDir) \(apk2.key.path.replacingTmpDir))"))
            } else {
                await out.write(status: .fail, "Double-check APK failed due to missing artifacts")
            }
        }

        let latestVersion = await checkSkipUpdates(with: out)
        if let latestVersion = latestVersion, latestVersion != skipVersion {
            await out.yield(MessageBlock(status: .warn, "A new version is Skip (\(latestVersion)) is available to update with: skip upgrade"))
        }
    }
}

extension String {
    /// Replace any instances of the temporary directory with the constant "TMPDIR" for compact ouptut in log messages
    var replacingTmpDir: String {
        replacingOccurrences(of: NSTemporaryDirectory(), with: "${TMPDIR}")
    }
}
