// Copyright 2026 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
import Foundation

/// How skip runs the Apple-platform `swift build` / `swift test` invocations it drives itself:
/// the verification build in `skip export`, the project build in `skip checkup`, `skip test`,
/// and the plugin's non-Xcode prebuild.
///
/// Swift 6.4 made `swiftbuild` the default SwiftPM engine, and it turns a warning that the
/// legacy `native` engine merely printed into a hard error: a Skip Fuse package graph embeds
/// shared library products such as SkipLib and SkipUnit into more than one dynamic product
/// ("is linked as a static library by … This will result in duplication of library code").
/// See https://github.com/skiptools/skip/issues/714.
///
/// Two things keep these builds working on every toolchain:
///
/// 1. `SKIP_DYNAMIC_LIBRARIES=1` in the build environment makes those shared products dynamic,
///    so the graph is valid under either engine. This relies on framework releases that honour
///    the variable (skip-lib 1.4.2, skip-unit 1.7.2, skip-foundation 1.4.5, skip-model 1.7.10
///    and later). `SKIP_BRIDGE` must not be used for this: it also switches the skipstone plugin
///    into bridge-generation mode, and the generated JNI sources do not compile for Darwin.
/// 2. `--build-system native` is passed while the toolchain still offers it, so a project whose
///    Package.resolved pins framework versions that predate (1) keeps building as well. Once a
///    toolchain drops `native`, the flag is simply omitted and (1) carries the build alone.
enum HostSwiftBuild {
    /// Environment merged into every skip-driven Apple-platform SwiftPM build.
    static let environment: [String: String] = ["SKIP_DYNAMIC_LIBRARIES": "1"]

    /// `["--build-system", "native"]` when the toolchain behind `swiftCommand` accepts it, else `[]`.
    /// `swiftCommand` is the leading command, e.g. `["swift"]` or `["xcrun", "swift"]`.
    static func buildSystemArguments(swiftCommand: [String] = ["swift"]) async -> [String] {
        await NativeBuildSystemProbe.shared.supportsNative(swiftCommand: swiftCommand) ? ["--build-system", "native"] : []
    }
}

/// Remembers, per `swift` command, whether `swift build --build-system native` is accepted.
actor NativeBuildSystemProbe {
    static let shared = NativeBuildSystemProbe()

    private var cache: [String: Bool] = [:]

    func supportsNative(swiftCommand: [String]) async -> Bool {
        let key = swiftCommand.joined(separator: " ")
        if let cached = cache[key] { return cached }
        let supported = Self.probe(swiftCommand: swiftCommand)
        cache[key] = supported
        return supported
    }

    /// Reads `swift build --help` and checks that `--build-system` is an option and that `native`
    /// is among its values. Passing the flag to a toolchain that lacks either would itself be an
    /// error, so anything short of a positive answer means "do not pass it".
    private static func probe(swiftCommand: [String]) -> Bool {
        guard let launchPath = swiftCommand.first,
              let help = runCapturingOutput(launchPath, Array(swiftCommand.dropFirst()) + ["build", "--help"]),
              let optionRange = help.range(of: "--build-system") else {
            return false
        }
        // the enumerated values follow the option, before the next option's description
        return help[optionRange.upperBound...].prefix(600).contains("native")
    }

    private static func runCapturingOutput(_ launchPath: String, _ arguments: [String]) -> String? {
        let process = Process()
        if launchPath.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
        } else {
            // resolve bare tool names such as "xcrun" through the environment
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [launchPath] + arguments
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
