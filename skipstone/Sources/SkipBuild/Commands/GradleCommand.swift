import Foundation
import ArgumentParser
import SkipSyntax
#if canImport(SkipDriveExternal)
import SkipDriveExternal

extension GradleCommand : GradleHarness { }
//fileprivate let gradleCommandEnabled = true
fileprivate let gradleCommandEnabled = false // advanced command, so do not display
#else
fileprivate let gradleCommandEnabled = false
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct GradleCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "gradle",
        abstract: "Launch the gradle build tool",
        shouldDisplay: gradleCommandEnabled)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @Option(help: ArgumentHelp("App package name", valueName: "package-name"))
    var package: String

    @Option(help: ArgumentHelp("App module name", valueName: "ModuleName"))
    var module: String

    @Argument(help: ArgumentHelp("The arguments to pass to the gradle command"))
    var gradleArguments: [String]

    func run() async throws {
        #if !canImport(SkipDriveExternal)
        throw SkipDriveError(errorDescription: "SkipDrive not linked")
        #else
        try await self.gradleExec(appName: module, packageName: package, arguments: gradleArguments)
        #endif
    }
}

