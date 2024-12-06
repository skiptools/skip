import Foundation
import ArgumentParser
import SkipSyntax

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct CheckupCommand: MessageCommand, ToolOptionsCommand {
    static var configuration = CommandConfiguration(
        commandName: "checkup",
        abstract: "Run tests to ensure Skip is in working order",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(name: [.customShort("c"), .long], help: ArgumentHelp("Configuration debug/release", valueName: "c"))
    var configuration: BuildConfiguration = .release

    @Flag(help: ArgumentHelp("Check twice that sample build outputs produce identical artifacts", valueName: "verify"))
    var doubleCheck: Bool = false

    @Flag(help: ArgumentHelp("Generate native module when running checkup", valueName: "native"))
    var native: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Fail immediately when an error occurs"))
    var failFast: Bool = true

    func performCommand(with out: MessageQueue) async {
        await withLogStream(with: out) {
            try await runCheckup(with: out)
        }
    }

    func runCheckup(with out: MessageQueue) async throws {
        try await runDoctor(with: out)

        @Sendable func buildSampleProject(packageResolvedURL: URL? = nil) async throws -> (projectURL: URL, project: AppProjectLayout, artifacts: [URL: String?]) {
            let primary = packageResolvedURL == nil
            // a random temporary folder for the project
            let tmpdir = NSTemporaryDirectory() + "/" + UUID().uuidString
            try FileManager.default.createDirectory(atPath: tmpdir, withIntermediateDirectories: true)

            //let checkupModules = try [PackageModule(parse: "HelloSkip"), PackageModule(parse: "HelloModel"), PackageModule(parse: "HelloCore")]
            var checkupModules = [PackageModule(moduleName: "HelloSkip")]
            // when checking a native package, create a second module that will have the bridge dependency
            if native == true {
                checkupModules += [PackageModule(moduleName: "HelloModel")]
            }
            // create a project differently based on the index, but the ultimate binary output should be identical
            return try await initSkipProject(projectName: "hello-skip", modules: checkupModules, resourceFolder: "Resources", dir: URL(fileURLWithPath: tmpdir, isDirectory: true), verify: true, configuration: self.configuration, build: primary, test: primary, returnHashes: doubleCheck, messagePrefix: !primary ? "Re-" : "", showTree: false, chain: true, gitRepo: false, free: true, zero: !native, appid: "skip.hello.App", iconColor: nil, version: "1.0.0", native: native, moduleTests: primary, fastlane: true, validatePackage: true, packageResolved: packageResolvedURL, apk: true, ipa: true, with: out)
        }

        // build a sample project (twice when performing a double-check)
        let (p1URL, project, p1) = try await buildSampleProject()
        if doubleCheck {
            // use the Package.resolved from the initial build to ensure that use double-check build uses the same dependency versions as the initial build
            // otherwise if a new version of a Skip library is tagged in between the two builds, the checksums won't match
            let packageResolvedURL = p1URL.appendingPathComponent("Package.resolved", isDirectory: false)
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
