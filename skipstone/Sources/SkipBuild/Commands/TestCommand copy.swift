import Foundation
import ArgumentParser

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct VerifyCommand: SkipCommand, StreamingCommand {

    static var configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Verify the Skip project",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @Option(help: ArgumentHelp("Project folder", valueName: "dir"))
    var project: String = "."


    func performCommand(with out: MessageQueue) async throws {
    }
}
