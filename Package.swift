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
        .plugin(name: "skip", targets: ["skip"]),
        .library(name: "SkipDrive", targets: ["SkipDrive"]),
    ],
    dependencies: [
    ],
    targets: [
        .plugin(name: "skip",
                capability: .buildTool(),
                dependencies: ["SkipTool"],
                path: "Plugins/SkipPlugin"),

        .target(name: "SkipDrive", dependencies: []),

        .testTarget(name: "SkipDriveTests", dependencies: ["SkipDrive"]),

        .binaryTarget(name: "SkipTool", url: "https://source.skip.tools/skip/releases/download/0.6.30/skip.zip", checksum: "0f7cc8156d5f8c932e611e38d3c0f711ea2c0c4f5531172f8810dbf0fbdc4abe")
    ]
)

import Foundation
if ProcessInfo.processInfo.environment["PWD"]?.hasSuffix("skipstone") == true {
    package.dependencies += [.package(path: "../skipstone")]
    package.targets = package.targets.dropLast() + [.executableTarget(name: "SkipTool", dependencies: [.product(name: "SkipBuild", package: "skipstone")])]
}
