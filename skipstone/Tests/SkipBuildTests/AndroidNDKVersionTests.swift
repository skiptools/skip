// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import SkipBuild

/// The Swift Android SDK's sysroot is linked against the NDK it was built with, so the NDK
/// that gets installed has to match the Swift version: 6.4 moved to NDK 30.
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
final class AndroidNDKVersionTests: XCTestCase {
    func testSwiftVersionIsAtLeast64() throws {
        // releases
        XCTAssertFalse(AndroidSDKInstallCommand.swiftVersionIsAtLeast64("6.3"))
        XCTAssertFalse(AndroidSDKInstallCommand.swiftVersionIsAtLeast64("6.3.3"))
        XCTAssertFalse(AndroidSDKInstallCommand.swiftVersionIsAtLeast64("5.10.1"))
        XCTAssertTrue(AndroidSDKInstallCommand.swiftVersionIsAtLeast64("6.4"))
        XCTAssertTrue(AndroidSDKInstallCommand.swiftVersionIsAtLeast64("6.4.0"))
        XCTAssertTrue(AndroidSDKInstallCommand.swiftVersionIsAtLeast64("6.10.0"))
        XCTAssertTrue(AndroidSDKInstallCommand.swiftVersionIsAtLeast64("7.0"))

        // nightlies
        XCTAssertFalse(AndroidSDKInstallCommand.swiftVersionIsAtLeast64("nightly-6.3"))
        XCTAssertTrue(AndroidSDKInstallCommand.swiftVersionIsAtLeast64("nightly-6.4"))
        XCTAssertTrue(AndroidSDKInstallCommand.swiftVersionIsAtLeast64("nightly-main"))

        // snapshots, both branch-specific and main
        XCTAssertFalse(AndroidSDKInstallCommand.swiftVersionIsAtLeast64("swift-6.3-DEVELOPMENT-SNAPSHOT-2025-12-18-a"))
        XCTAssertTrue(AndroidSDKInstallCommand.swiftVersionIsAtLeast64("swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-09-04-a"))
        XCTAssertTrue(AndroidSDKInstallCommand.swiftVersionIsAtLeast64("swift-DEVELOPMENT-SNAPSHOT-2025-12-19-a"))
    }

    func testDefaultNDKVersionForSwiftVersion() throws {
        XCTAssertEqual("r27d", AndroidSDKInstallCommand.defaultAndroidNDKVersion(forSwiftVersion: "6.3.3"))
        XCTAssertEqual("r30", AndroidSDKInstallCommand.defaultAndroidNDKVersion(forSwiftVersion: "6.4.0"))
        XCTAssertEqual("r30", AndroidSDKInstallCommand.defaultAndroidNDKVersion(forSwiftVersion: "nightly-main"))
    }

    /// An explicit `--ndk-version` must win over the version-derived default.
    func testExplicitNDKVersionOverridesDefault() throws {
        XCTAssertNil(try AndroidSDKInstallCommand.parse([]).ndkVersion)
        XCTAssertEqual("r28c", try AndroidSDKInstallCommand.parse(["--ndk-version", "r28c"]).ndkVersion)
    }
}
