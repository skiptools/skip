// Copyright 2026 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
import Foundation

/// How skip runs the Apple-platform `swift build` / `swift test` invocations it drives itself:
/// the verification build in `skip export`, the project build in `skip checkup`, `skip test`,
/// and the plugin's non-Xcode prebuild.
///
/// These use the toolchain's default SwiftPM build system, which is `swiftbuild` as of Swift 6.4,
/// matching the Android build. `swiftbuild` turns a warning that the legacy `native` engine merely
/// printed into a hard error: a Skip Fuse package graph embeds shared library products such as
/// SkipLib and SkipUnit into more than one dynamic product ("is linked as a static library by …
/// This will result in duplication of library code"). See https://github.com/skiptools/skip/issues/714.
///
/// `SKIP_DYNAMIC_LIBRARIES=1` in the build environment makes those shared products dynamic, so the
/// graph is valid under either engine. This relies on framework releases that honour the variable
/// (skip-lib 1.4.2, skip-unit 1.7.2, skip-foundation 1.4.5, skip-model 1.7.10 and later).
/// `SKIP_BRIDGE` must not be used for this: it also switches the skipstone plugin into
/// bridge-generation mode, and the generated JNI sources do not compile for Darwin.
enum HostSwiftBuild {
    /// Environment merged into every skip-driven Apple-platform SwiftPM build.
    static let environment: [String: String] = ["SKIP_DYNAMIC_LIBRARIES": "1"]
}
