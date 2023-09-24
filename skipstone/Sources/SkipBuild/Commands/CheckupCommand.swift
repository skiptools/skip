import Foundation
import ArgumentParser
import SkipSyntax

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct CheckupCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "checkup",
        abstract: "Run tests to ensure Skip is in working order",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    func run() async throws {
        try await runDoctor()

        func checkup() throws -> [String] {
            let tmpdir = NSTemporaryDirectory() + "/" + UUID().uuidString
            try FileManager.default.createDirectory(atPath: tmpdir, withIntermediateDirectories: true)
            return [toolOptions.skip, "init", "--build", "--test", "-d", tmpdir, "lib-name", "ModuleName"]
        }

        // if we have not initiailized Gradle before (indicated by the absence of a ~/.gradle/caches/ folder), indicate that the first run will take a while
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: home(".gradle/caches"), isDirectory: &isDir) == false || isDir.boolValue == false {
            try await outputOptions.run("Pre-Caching Gradle Dependencies (~1G)", checkup())
        }

        let _ = try await outputOptions.run("Running Skip Checkup", checkup())

        //outputOptions.write(output.out)
        //outputOptions.write(output.err)
        outputOptions.write("Skip \(skipVersion) self-test passed!")

    }
}

