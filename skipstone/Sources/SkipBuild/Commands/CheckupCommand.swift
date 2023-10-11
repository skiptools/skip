import Foundation
import ArgumentParser
import SkipSyntax

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct CheckupCommand: MessageCommand, ToolOptionsCommand  {
    static var configuration = CommandConfiguration(
        commandName: "checkup",
        abstract: "Run tests to ensure Skip is in working order",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(name: [.customShort("c"), .long], help: ArgumentHelp("Configuration debug/release", valueName: "c"))
    var configuration: String = "release"

    @Flag(help: ArgumentHelp("Check twice that sample build outputs produce identical artifacts", valueName: "verify"))
    var doubleCheck: Bool = false

    func performCommand(with out: MessageQueue) async throws {
        try await runDoctor(with: out)

        let tmpdir = NSTemporaryDirectory() + "/" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: tmpdir, withIntermediateDirectories: true)

        _ = try await buildSkipProject(projectName: "hello-skip", modules: [PackageModule(parse: "HelloSkip"), PackageModule(parse: "HelloModel")], resourceFolder: "Resources", dir: tmpdir, configuration: self.configuration, build: true, test: true, doubleCheck: doubleCheck, tree: false, chain: true, free: true, zero: true, appid: "skip.hello.App", version: "1.0.0", apk: true, ipa: true, with: out)

        await out.write(status: .pass, "Skip \(skipVersion) self-test passed!")
    }
}

