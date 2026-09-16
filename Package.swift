// swift-tools-version: 5.10
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
        .plugin(name: "skiplink", targets: ["Create SkipLink"]),
        .library(name: "SkipDrive", targets: ["SkipDrive"]),
        .library(name: "SkipTest", targets: ["SkipTest"]),
    ],
    targets: [
        .plugin(name: "skipstone", capability: .buildTool(), dependencies: ["skip"], path: "Plugins/SkipPlugin"),
        .plugin(name: "Create SkipLink", capability: .command(intent: .custom(verb: "SkipLink", description: "Create local links to transpiled output"), permissions: [.writeToPackageDirectory(reason: "This command will create local links to the skipstone output for the specified package(s), enabling access to the transpiled Kotlin")]), dependencies: ["skip"], path: "Plugins/SkipLink"),
        .target(name: "SkipDrive", dependencies: ["skipstone", .target(name: "skip")]),
        .target(name: "SkipTest", dependencies: [.target(name: "SkipDrive", condition: .when(platforms: [.macOS, .macCatalyst, .linux]))]),
        .testTarget(name: "SkipTestTests", dependencies: ["SkipTest"]),
        .testTarget(name: "SkipDriveTests", dependencies: ["SkipDrive"]),
    ]
)

let env = Context.environment
if (env["SKIPLOCAL"] != nil || env["PWD"]?.hasSuffix("skipstone") == true) {
    package.dependencies += [.package(path: env["SKIPLOCAL"] ?? "../skipstone")]
    package.targets += [.executableTarget(name: "skip", dependencies: [.product(name: "SkipBuild", package: "skipstone")])]
} else {
    #if os(macOS)
    package.targets += [.binaryTarget(name: "skip", url: "https://github.com/skiptools/skip/releases/download/1.9.9/skip-macos.zip", checksum: "fbb0c374cb20a1a92d995f93220e305c58c55ce32bbb723968e8fffaf4b8ba75")]
    #elseif os(Linux)
    package.targets += [.binaryTarget(name: "skip", url: "https://github.com/skiptools/skip/releases/download/1.9.9/skip-linux.zip", checksum: "ec620a1cd1db6a6ba3910dc067b032b1cfa569f5b8a541895060a68e908d38fd")]
    #else
    package.dependencies += [.package(url: "https://github.com/skiptools/skipstone.git", exact: "1.9.9")]
    package.targets += [.executableTarget(name: "skip", dependencies: [.product(name: "SkipBuild", package: "skipstone")])]
    #endif
}

