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

        .plugin(name: "skip-init", targets: ["Hello Skip"]),

        .plugin(name: "skipcommand", targets: ["skip-command"]),
        .plugin(name: "preflight", targets: ["skip-preflight"]),
        .plugin(name: "transpile", targets: ["skip-transpiler"]),
        .plugin(name: "skipbuild", targets: ["skip-build"]),

        .library(name: "SkipDrive", targets: ["SkipDrive"]),
    ],
    dependencies: [
    ],
    targets: [
        .plugin(name: "Hello Skip",
                capability: .command(
                    intent: .custom(verb: "skip-init", description: "Show an introduction to Skip and how it can be added to this project."),
                    permissions: [
                        .writeToPackageDirectory(reason: "Skip needs to create and update the Skip folder in the project.")
                    ]),
                dependencies: ["skipstone"],
                path: "Plugins/SkipInit"),

        .plugin(name: "skip-command",
                capability: .command(
                    intent: .custom(verb: "skip",  description: "Run Skip by specifying arguments manually"),
                    permissions: [
                        .writeToPackageDirectory(reason: "Skip needs to create and update the Skip folder in the project."),
                    ]),
                dependencies: ["skip"],
                path: "Plugins/SkipCommand"),

        .plugin(name: "skip-build",
                capability: .buildTool(),
                dependencies: ["skipgradle"],
                path: "Plugins/SkipBuild"),

        .plugin(name: "skip-preflight",
                capability: .buildTool(),
                dependencies: ["skipstone"],
                path: "Plugins/SkipPreflightPlugIn"),

        .plugin(name: "skip-transpiler",
                capability: .buildTool(),
                dependencies: ["skipstone"],
                path: "Plugins/SkipTranspilePlugIn"),


        .target(name: "SkipDrive", dependencies: []),

        .executableTarget(name: "skip", dependencies: ["SkipDrive"]),
        .executableTarget(name: "skipgradle", dependencies: ["SkipDrive"], path: "Sources/SkipGradle"),

        .testTarget(name: "SkipDriveTests", dependencies: ["skip"]),

        .binaryTarget(name: "skipstone", url: "https://source.skip.tools/skip/releases/download/0.5.89/skipstone.plugin.zip", checksum: "9bf6e1649ce60082a9b01bb5a251ac808c7e1411e10331bf7ea23b81500ec87d")
    ]
)

import Foundation
if ProcessInfo.processInfo.environment["PWD"]?.hasSuffix("skipstone") == true {
    package.dependencies += [.package(path: "../skipstone")]
    package.targets = package.targets.dropLast() + [.executableTarget(name: "skipstone", dependencies: [.product(name: "SkipBuild", package: "skipstone")])]
}
