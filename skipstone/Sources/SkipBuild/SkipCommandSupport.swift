import Foundation
#if canImport(SkipDriveExternal)
import SkipDriveExternal
#endif

typealias AsyncLineOutput = AsyncCompactMapSequence<AsyncThrowingStream<Data, Error>, String>

extension ToolOptionsCommand {
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
        return Process.streamLines(command: [try toolOptions.toolPath(for: toolName)] + arguments, environment: penv, workingDirectory: workingDirectory, includeStdErr: includeStdErr, onExit: onExit)
        #endif
    }
}

extension AsyncLineOutput {
    /// Gather all the output from the command and parse it as a single JSON blob into the given format
    func parseJSON<T: Decodable>() async throws -> T {
        var lines = [String]()
        for try await line in self {
            lines.append(line)
        }
        return try JSONDecoder().decode(T.self, from: lines.joined(separator: "\n").utf8Data)
    }
}
