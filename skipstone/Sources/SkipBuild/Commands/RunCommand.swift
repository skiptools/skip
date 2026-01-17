// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ArgumentParser
import SkipSyntax

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct RunCommand: MessageCommand {
    static var configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the current Skip app project",
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
