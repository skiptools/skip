// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ArgumentParser
import SkipSyntax
#if canImport(SkipDriveExternal)
import SkipDriveExternal
fileprivate let adbCommandEnabled = false // advanced command, so do not display
//fileprivate let adbCommandEnabled = true
#else
fileprivate let adbCommandEnabled = false
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct ADBCommand: MessageCommand, ToolOptionsCommand {
    static var configuration = CommandConfiguration(
        commandName: "adb",
        abstract: "Launch the adb build tool",
        shouldDisplay: adbCommandEnabled)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Argument(parsing: .allUnrecognized, help: ArgumentHelp("The arguments to pass to the adb command"))
    var arguments: [String]

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Fail immediately when an error occurs"))
    var failFast: Bool = true

    func performCommand(with out: MessageQueue) async throws {
        // ADB itself doesn't ever exit with a non-zero exit code (https://issuetracker.google.com/issues/36908392?pli=1)
        // So we need to parse the output for known error patterns and translate them into Xcode-aware messages
        #if !canImport(SkipDriveExternal)
        throw SkipDriveError(errorDescription: "SkipDrive not linked")
        #else
        var exitCode: ProcessResult.ExitStatus? = nil
        let output = try await self.launchTool("adb", arguments: arguments) {
            exitCode = $0.exitStatus
        }

        for try await line in output {
            await out.write(status: nil, "ADB> \(line)")
            if let formattedError = scanADBOutput(line: line.line) { // check for errors and report them to the IDE
                await out.write(status: nil, formattedError)
            }
        }

        guard let exitCode = exitCode, case .terminated(0) = exitCode else {
            throw ADBLaunchError(errorDescription: "ADB run error: \(String(describing: exitCode))")
        }

        #endif
    }


    /// Check for common ADB error patterns and report them back to Xcode.
    /// - Parameter line: the ADB output line to scan
    func scanADBOutput(line: String) -> String? {
        func err(_ msg: String) -> String {
            // Xcode will report "error:" strings as an error; insert a file prefix to add a link
            return "error: skip adb error: \(msg) (troubleshoot at https://skip.tools/docs)"
        }

        switch line {
        case "adb: more than one device/emulator":
            return err("The Android Debug Bridge found more than one running Android emulator or connected device. Check device list with adb devices.")
        case "adb: no devices/emulators found":
            return err("No Android emulators or devices were found. Launch Android Studio.app and open the Virtual Device Manager to create an emulator to continue.")
        case _ where line.hasPrefix("Exception occurred while executing"): // command-specifiec error output
            return err(line)
        case _ where line.hasPrefix("Error:"): // general ADB error output
            return err(line)
        default:
            return nil
        }
    }

}

public struct ADBLaunchError : LocalizedError {
    public var errorDescription: String?
}
