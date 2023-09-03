import Foundation
import Darwin
import ArgumentParser
import SkipSyntax

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct HostIDCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "hostid",
        abstract: "Display the current host ID",
        shouldDisplay: false)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    func run() async throws {
        guard let hostid = ProcessInfo.processInfo.hostIdentifier else {
            throw HostIDError(errorDescription: "Could not access Host ID")
        }
        outputOptions.write(hostid)
    }

    public struct HostIDError : LocalizedError {
        public var errorDescription: String?
    }
}
