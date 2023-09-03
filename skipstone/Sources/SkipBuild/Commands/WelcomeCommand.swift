import Foundation
import ArgumentParser
import SkipSyntax

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct WelcomeCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "welcome",
        abstract: "Show the skip welcome message",
        shouldDisplay: false)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @Flag(help: ArgumentHelp("Show message only on first run"))
    var firstRun: Bool = false

    func run() async throws {
        if !firstRun || OutputOptions.isFirstRun == true {
            outputOptions.write("""

              ▄▄▄▄▄▄▄ ▄▄▄   ▄ ▄▄▄ ▄▄▄▄▄▄▄
             █       █   █ █ █   █       █
             █  ▄▄▄▄▄█   █▄█ █   █    ▄  █
             █ █▄▄▄▄▄█      ▄█   █   █▄█ █
             █▄▄▄▄▄  █     █▄█   █    ▄▄▄█
              ▄▄▄▄▄█ █    ▄  █   █   █
             █▄▄▄▄▄▄▄█▄▄▄█ █▄█▄▄▄█▄▄▄█

            Welcome to Skip \(skipVersion)!

            Run "skip doctor" to check system requirements.
            Run "skip selftest" to perform a full system evaluation.
            Run "skip create --open AppName" to create a new Skip Xcode project.

            Visit https://skip.tools for documentation, samples, and FAQs.

            Happy Skipping!
            """)
        }
    }
}
