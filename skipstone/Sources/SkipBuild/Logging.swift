// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

#if canImport(OSLog)
import OSLog
typealias Logger = os.Logger
#else
/// Dummy logger when Linux cannot import OSLog
public struct Logger {
    public let subsystem: String
    public let category: String

    public func log(_ message: String) {
        print("[log \(subsystem) \(category)] \(message)")
    }

    public func info(_ message: String) {
        print("[info \(subsystem) \(category)] \(message)")
    }

    public func debug(_ message: String) {
        print("[debug \(subsystem) \(category)] \(message)")
    }

    public func warning(_ message: String) {
        print("[warning \(subsystem) \(category)] \(message)")
    }

    public func error(_ message: String) {
        print("[error \(subsystem) \(category)] \(message)")
    }
}
#endif
