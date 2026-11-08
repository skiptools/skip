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
        .plugin(name: "skiptranspile", targets: ["Skip Transpile"]),
        .library(name: "SkipDrive", targets: ["SkipDrive"]),
        .library(name: "SkipTest", targets: ["SkipTest"]),
    ],
    targets: [
        .plugin(name: "skipstone", capability: .buildTool(), dependencies: ["skip"], path: "Plugins/SkipPlugin"),
        .plugin(name: "Create SkipLink", capability: .command(intent: .custom(verb: "SkipLink", description: "Create local links to transpiled output"), permissions: [.writeToPackageDirectory(reason: "This command will create local links to the skipstone output for the specified package(s), enabling access to the transpiled Kotlin")]), dependencies: ["skip"], path: "Plugins/SkipLink"),
        .plugin(name: "Skip Transpile", capability: .command(intent: .custom(verb: "skip-transpile", description: "Transpile the Skip modules without building them"), permissions: [.writeToPackageDirectory(reason: "This command writes the transpiled output to the package's .build/plugins/outputs folder")]), dependencies: ["skip"], path: "Plugins/SkipTranspile"),
        .target(name: "SkipDrive", dependencies: ["skipstone", .target(name: "skip")]),
        .target(name: "SkipTest", dependencies: [.target(name: "SkipDrive", condition: .when(platforms: [.macOS, .macCatalyst, .linux]))]),
        .testTarget(name: "SkipTestTests", dependencies: ["SkipTest"]),
        .testTarget(name: "SkipDriveTests", dependencies: ["SkipDrive"]),
    ]
)

// The `skip` tool is normally a pre-built binary downloaded from this repository's releases.
//
// For local development, the tool is instead built from the `skipstone/` sub-folder of this
// repository, which is a separate SwiftPM package containing the transpiler and the CLI.
// This mode is enabled by setting `SKIPLOCAL` (either to the path of a skipstone checkout, or
// to an empty string to use the bundled `skipstone/` folder), or by launching from a directory
// named "skipstone" (which is how Xcode picks up the local build; see skipstone/README.md).
//
// It can only be used when this package is the root package: a remote dependency cannot declare
// a local path dependency, so this must never be enabled automatically based on the presence of
// the `skipstone/` folder, which is also present in the checkouts of this package's consumers.
let env = Context.environment
if let skipLocal = env["SKIPLOCAL"] ?? (env["PWD"]?.hasSuffix("skipstone") == true ? "" : nil) {
    package.dependencies += [.package(path: skipLocal.isEmpty ? "skipstone" : skipLocal)]
    package.targets += [.executableTarget(name: "skip", dependencies: [.product(name: "SkipBuild", package: "skipstone")])]
} else {
    #if os(macOS)
    package.targets += [.binaryTarget(name: "skip", url: "https://github.com/skiptools/skip/releases/download/1.9.20/skip-macos.zip", checksum: "bd3c6aacb46fecacaea34eac2445489c42e97800099057687a28654230467178")]
    #elseif os(Linux)
    package.targets += [.binaryTarget(name: "skip", url: "https://github.com/skiptools/skip/releases/download/1.9.20/skip-linux.zip", checksum: "b98f5de51818c4802d584c2802f96d45fbf1babc7c1c25f94dc6cb6e7b88f57f")]
    #else
    fatalError("The skip plugin is only supported on macOS and Linux hosts; set SKIPLOCAL to build the skip tool from the skipstone/ sources instead")
    #endif
}

