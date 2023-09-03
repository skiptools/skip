// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "skip",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
        .macCatalyst(.v16),
    ],
    products: [
        .plugin(name: "preflight", targets: ["skip-preflight"]),
        .plugin(name: "transpile", targets: ["skip-transpiler"]),
        .library(name: "SkipDrive", targets: ["SkipDrive"]),
    ],
    dependencies: [
    ],
    targets: [
        .plugin(name: "skip-preflight",
                capability: .buildTool(),
                dependencies: ["skipstone"],
                path: "Plugins/SkipPreflightPlugIn"),

        .plugin(name: "skip-transpiler",
                capability: .buildTool(),
                dependencies: ["skipstone"],
                path: "Plugins/SkipTranspilePlugIn"),

        .target(name: "SkipDrive", dependencies: []),

        .testTarget(name: "SkipDriveTests", dependencies: ["SkipDrive"]),

        .binaryTarget(name: "skipstone", url: "https://source.skip.tools/skip/releases/download/0.6.16/skip.zip", checksum: "50bc34c7302a901cd86538d2bc4e36574c3266bced096cd0df7fcdc7628d47ac")
    ]
)

import Foundation
if ProcessInfo.processInfo.environment["PWD"]?.hasSuffix("skipstone") == true {
    package.dependencies += [.package(path: "../skipstone")]
    package.targets = package.targets.dropLast() + [.executableTarget(name: "skipstone", dependencies: [.product(name: "SkipBuild", package: "skipstone")])]
}
