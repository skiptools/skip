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
        .executable(name: "skip", targets: ["skip"]),
        .plugin(name: "skipstone", targets: ["skipstone"]),
        .library(name: "SkipDrive", targets: ["SkipDrive"]),
        .library(name: "SkipTest", targets: ["SkipTest"]),
    ],
    targets: [
        .plugin(name: "skipstone", capability: .buildTool(), dependencies: ["skip"], path: "Plugins/SkipPlugin"),
        .target(name: "SkipDrive", dependencies: ["skipstone", .target(name: "skip")]),
        .target(name: "SkipTest", dependencies: [.target(name: "SkipDrive", condition: .when(platforms: [.macOS]))]),
        .testTarget(name: "SkipTestTests", dependencies: ["SkipTest"]),
        .testTarget(name: "SkipDriveTests", dependencies: ["SkipDrive"]),
        .binaryTarget(name: "skip", url: "https://source.skip.tools/skip/releases/download/0.6.76/skip.zip", checksum: "404afdde73210a4b2547e3660b1d67f07f8a5abb2ddfb9fc4118c076885584ac")
    ]
)

import Foundation
if ProcessInfo.processInfo.environment["PWD"]?.hasSuffix("skipstone") == true && ProcessInfo.processInfo.environment["NOSKIP"] == nil {
    package.dependencies += [.package(path: "../skipstone")]
    package.targets = package.targets.dropLast() + [.executableTarget(name: "skip", dependencies: [.product(name: "SkipBuild", package: "skipstone")])]
}
