// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
#if canImport(SkipDriveExternal)
import SkipDriveExternal
#else
typealias ProcessResult = Void
#endif

/// An async stream of standard out + err data resulting from process execution
public typealias AsyncLineOutput = AsyncThrowingStream<(line: String, err: Bool), Swift.Error>

extension ToolOptionsCommand where Self: StreamingCommand {
    /// Executes `adb` with the current default arguments and the additional args and returns an async stream of the lines from the combined standard err and standard out.
    func launchTool(_ toolName: String, in workingDirectory: URL? = nil, arguments: [String], env: [String: String] = [:], includeStdErr: Bool = true, onExit: @escaping (ProcessResult) throws -> () = { _ in }) async throws -> AsyncLineOutput {
        #if DEBUG
        // output the launch message in a format that makes it easy to copy and paste the result into the terminal
        //print("note: skip tool env:", env.keys.sorted().map { $0 + "=\"" + env[$0, default: ""] + "\"" }.joined(separator: " "), (arguments).joined(separator: " "))
        #endif

        #if !canImport(SkipDriveExternal)
        throw ToolLaunchError(errorDescription: "Cannot launch adb without SkipDriveExternal")
        #else
        // transfer process environment along with the additional environment
        var penv = ProcessInfo.processInfo.environmentWithDefaultToolPaths
        for (key, value) in env {
            penv[key] = value
        }

        let cmd = [try toolOptions.toolPath(for: toolName)] + arguments

        if outputOptions.verbose {
            msg(.note, "launching tool: \(env.keys.sorted().map { $0 + "=\"" + env[$0, default: ""] + "\"" }.joined(separator: " ")) \((cmd).joined(separator: " "))")
        }

        return Process.streamLines(command: cmd, environment: penv, workingDirectory: workingDirectory, includeStdErr: includeStdErr, onExit: onExit)
        #endif
    }
}

extension AsyncLineOutput {
    func readLines() async throws -> [AsyncLineOutput.Element] {
        var lines = [AsyncLineOutput.Element]()
        for try await line in self {
            lines.append(line)
        }
        return lines
    }

    /// Reads all the lines of the output and returns a tuple of the standard out and standard error.
    func readOutput() async throws -> (stdout: String, stderr: String) {
        let lines = try await readLines()
        let stdout = lines.filter({ $0.err == false }).map(\.line).joined(separator: "\n")
        let stderr = lines.filter({ $0.err == true }).map(\.line).joined(separator: "\n")
        return (stdout: stdout, stderr: stderr)
    }

    /// Gather all the output from the command and parse it as a single JSON blob into the given format
    func parseJSON<T: Decodable>() async throws -> T {
        let stdout = try await readOutput().stdout
        return try JSONDecoder().decode(T.self, from: stdout.utf8Data)
    }
}
