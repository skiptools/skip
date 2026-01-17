// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ArgumentParser
import SkipSyntax
import TSCBasic

struct InfoCommand: SingleStreamingCommand {
    struct Output : MessageEncodable {
        var version: String = skipVersion
        var hostName = pinfo.hostName
        var arguments = pinfo.arguments
        var operatingSystemVersion = pinfo.operatingSystemVersionString
        var workingDirectory = fm.currentDirectoryPath
        let cwdWritable = fm.isWritableFile(atPath: fm.currentDirectoryPath)
        let cwdReadable = fm.isReadableFile(atPath: fm.currentDirectoryPath)
        let cwdExecutable = fm.isExecutableFile(atPath: fm.currentDirectoryPath)
        var home = fm.homeDirectoryForCurrentUser
        let homeWritable = fm.isWritableFile(atPath: fm.homeDirectoryForCurrentUser.path)
        let homeReadable = fm.isReadableFile(atPath: fm.homeDirectoryForCurrentUser.path)
        let homeExecutable = fm.isExecutableFile(atPath: fm.homeDirectoryForCurrentUser.path)
        let skipLocal = pinfo.environment["SKIPLOCAL"]
        //var environment = pinfo.environment // potentially private information

        private static var fm: FileManager { .default }
        private static var pinfo: ProcessInfo { .processInfo }

        #if DEBUG
        var debug = true
        #else
        var debug = false
        #endif

        func message(term: Term) -> String? {
            """
            \(term.green("skip")): \(version)
            debug: \(debug)
            os: \(operatingSystemVersion)
            cwd: \(workingDirectory) (\(cwdReadable ? "r" : "")\(cwdWritable ? "w" : "")\(cwdExecutable ? "x" : ""))
            home: \(home) (\(homeReadable ? "r" : "")\(homeWritable ? "w" : "")\(homeExecutable ? "x" : ""))
            args: \(arguments)
            SKIPLOCAL: \(skipLocal ?? "no")
            """
            // env: \(environment)
        }
    }

    static var configuration = CommandConfiguration(commandName: "info",
                                                           abstract: "Print system information",
                                                           shouldDisplay: false)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    // alternative way of setting output
    //@OptionGroup var parentOptions: SkipCommandExecutor
    //var output: OutputOptions {
    //    get { parentOptions.output }
    //    set { parentOptions.output = newValue }
    //}

    func executeCommand() async throws -> Output {
        trace("trace message")
        info("info message")
        return Output()
    }
}

