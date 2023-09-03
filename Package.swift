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
        .plugin(name: "skippy", targets: ["skip-preflight"]),
        .plugin(name: "transpile", targets: ["skip-transpiler"]),
        .library(name: "SkipDrive", targets: ["SkipDrive"]),
    ],
    dependencies: [
    ],
    targets: [
        .plugin(name: "skip-preflight",
                capability: .buildTool(),
                dependencies: ["skip"],
                path: "Plugins/SkipPreflightPlugIn"),

        .plugin(name: "skip-transpiler",
                capability: .buildTool(),
                dependencies: ["skip"],
                path: "Plugins/SkipTranspilePlugIn"),

        .target(name: "SkipDrive", dependencies: []),

        .testTarget(name: "SkipDriveTests", dependencies: ["SkipDrive"]),

        .binaryTarget(name: "skip", url: "https://source.skip.tools/skip/releases/download/0.6.26/skip.zip", checksum: "2e92b6c566c82f366db38d0ec8547ed58f03559efab88bd5abdd63943253386e")
    ]
)

import Foundation
if ProcessInfo.processInfo.environment["PWD"]?.hasSuffix("skipstone") == true {
    package.dependencies += [.package(path: "../skipstone")]
    package.targets = package.targets.dropLast() + [.executableTarget(name: "skip", dependencies: [.product(name: "SkipBuild", package: "skipstone")])]
}
