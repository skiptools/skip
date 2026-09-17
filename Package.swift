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
    package.targets += [.binaryTarget(name: "skip", url: "https://github.com/skiptools/skip/releases/download/1.9.10/skip-macos.zip", checksum: "e92bb0c9f1f84733e7e9326c7ae26b71603de93eda6029b9e2e9fa27ea305b0a")]
    #elseif os(Linux)
    package.targets += [.binaryTarget(name: "skip", url: "https://github.com/skiptools/skip/releases/download/1.9.10/skip-linux.zip", checksum: "51c94d399865f6024302143aae7d70a367b8713fb7a37770343cc4b77b83924d")]
    #else
    package.dependencies += [.package(url: "https://github.com/skiptools/skipstone.git", exact: "1.9.10")]
    package.targets += [.executableTarget(name: "skip", dependencies: [.product(name: "SkipBuild", package: "skipstone")])]
    #endif
}

