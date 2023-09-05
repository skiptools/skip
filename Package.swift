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
        .plugin(name: "skipstone", targets: ["skipstone"]),
        .library(name: "SkipDrive", targets: ["SkipDrive"]),
    ],
    dependencies: [
    ],
    targets: [
        .plugin(name: "skipstone",
                capability: .buildTool(),
                dependencies: ["skip"],
                path: "Plugins/SkipPlugin"),

        .target(name: "SkipDrive", dependencies: []),

        .testTarget(name: "SkipDriveTests", dependencies: ["SkipDrive"]),

        .binaryTarget(name: "skip", url: "https://source.skip.tools/skip/releases/download/0.6.35/skip.zip", checksum: "5f0c98f6621da2a1e16debe75c8a34fb93f79426525a1ba6e81a951ba93b87fd")
    ]
)

import Foundation
if ProcessInfo.processInfo.environment["PWD"]?.hasSuffix("skipstone") == true {
    package.dependencies += [.package(path: "../skipstone")]
    package.targets = package.targets.dropLast() + [.executableTarget(name: "skip", dependencies: [.product(name: "SkipBuild", package: "skipstone")])]
}
