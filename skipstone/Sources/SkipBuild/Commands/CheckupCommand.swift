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

    func performCommand(with out: Messenger) async throws {
        try await runDoctor(tool: toolOptions, with: out)

        let tmpdir = NSTemporaryDirectory() + "/" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: tmpdir, withIntermediateDirectories: true)
//        func checkup() throws -> [String] {
//            return [toolOptions.skip, "init", "--build", "--plain", "--test", "-d", tmpdir, "lib-name", "ModuleName"]
//        }
//
//        // if we have not initiailized Gradle before (indicated by the absence of a ~/.gradle/caches/ folder), indicate that the first run will take a while
//        var isDir: ObjCBool = false
//        if FileManager.default.fileExists(atPath: home(".gradle/caches"), isDirectory: &isDir) == false || isDir.boolValue == false {
//            try await outputOptions.run(with: out, "Pre-Caching Gradle Dependencies (~1G)", checkup())
//        }

        try await performLibInitCommand(projectName: "lib-name", moduleNames: ["ModuleNameA", "ModuleNameB"], dir: tmpdir, configuration: "debug", build: true, test: true, with: out)

        out.write(status: .pass, "Skip \(skipVersion) self-test passed!")
    }
}

