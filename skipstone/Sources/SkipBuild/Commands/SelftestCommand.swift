import Foundation
import Darwin
import ArgumentParser
import SkipSyntax

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct SelftestCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "selftest",
        abstract: "Run tests to ensure Skip is in working order",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    func run() async throws {
        try await runDoctor()

        func selftest() throws -> [String] {
            let tmpdir = NSTemporaryDirectory() + "/" + UUID().uuidString
            try FileManager.default.createDirectory(atPath: tmpdir, withIntermediateDirectories: true)
            return ["skip", "init", "--build", "--test", "-d", tmpdir, "lib-name", "ModuleName"]
        }

        // if we have not initiailized Gradle before (indicated by the absence of a ~/.gradle/caches/ folder), indicate that the first run will take a while
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: home(".gradle/caches"), isDirectory: &isDir) == false || isDir.boolValue == false {
            try await outputOptions.run("Pre-Caching Gradle Dependencies (~1G)", selftest())
        }

        let _ = try await outputOptions.run("Running Skip Self-Test", selftest())

        //outputOptions.write(output.out)
        //outputOptions.write(output.err)
        outputOptions.write("Skip \(skipVersion) self-test passed!")

    }
}

