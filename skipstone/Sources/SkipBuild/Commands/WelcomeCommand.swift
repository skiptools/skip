// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ArgumentParser
import SkipSyntax

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct WelcomeCommand: SkipCommand, SingleStreamingCommand {
    typealias Output = WelcomeInfo?

    static var configuration = CommandConfiguration(
        commandName: "welcome",
        abstract: "Show the skip welcome message",
        shouldDisplay: false)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @Flag(help: ArgumentHelp("Show message only on first run"))
    var firstRun: Bool = false

    /// The return value for Welcome is just a string message
    struct WelcomeInfo : StringMessageEncodable {

        func message(term: Term) -> String? {
            /// Colorize ASCI art banner by in fixed-width columns
            func col(_ value: String) -> String {
                term.cyan(value.slice(0, 9))
                + term.green(value.slice(9, 18))
                + term.yellow(value.slice(18, 22))
                + term.red(value.slice(22))
            }

            return """

             \(col(" ▄▄▄▄▄▄▄  ▄▄▄  ▄▄▄ ▄▄  ▄▄▄▄▄▄▄ "))
             \(col("█       ██   █ █ ██  ██       █"))
             \(col("█  ▄▄▄▄▄██   █▄█ ██  ██    ▄  █"))
             \(col("█ █▄▄▄▄▄██      ▄██  ██   █▄█ █"))
             \(col("█▄▄▄▄▄  ██     █▄██  ██    ▄▄▄█"))
             \(col(" ▄▄▄▄▄█ ██    ▄  ██  ██   █    "))
             \(col("█▄▄▄▄▄▄▄██▄▄▄█ █▄██▄▄██▄▄▄█    "))

            Welcome to Skip \(skipVersion)!

            Run "skip checkup" to perform a full system evaluation.
            Run "skip create" to start a new project.

            Visit https://skip.tools for documentation, samples, and FAQs.

            Happy Skipping!
            """
        }
    }

    func executeCommand() async throws -> WelcomeInfo? {
        if !firstRun || OutputOptions.isFirstRun == true {
            return WelcomeInfo()
        } else {
            return nil
        }
    }
}
