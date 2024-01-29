import Foundation
import ArgumentParser
import SkipSyntax

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AssembleCommand: MessageCommand {
    static var configuration = CommandConfiguration(
        commandName: "assemble",
        abstract: "Build and assemble Skip app or framework",
        shouldDisplay: false) // TODO

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    func performCommand(with out: MessageQueue) async throws {
        guard let hostid = ProcessInfo.processInfo.hostIdentifier else {
            throw HostIDError(errorDescription: "Could not access Host ID")
        }
        await out.write(status: nil, hostid)
    }

    public struct HostIDError : LocalizedError {
        public var errorDescription: String?
    }
}
