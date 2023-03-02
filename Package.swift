// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "SkipPlugIn",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SkipCLI", targets: ["SkipCLI"]),
    ],
    targets: [
        .plugin(name: "SkipBuildPlugIn",
            capability: .buildTool(), 
            dependencies: ["SkipCLI"]),
        .plugin(name: "SkipCommandPlugIn",
            capability: .command(
                intent: .custom(verb: "skip", 
                description: "Run Skip transpiler"),
                permissions: [
                    .writeToPackageDirectory(reason: "skip creates source files"),
                    //.allowNetworkConnections(scope: .all(ports: []), reason: "skip uses gradle to download dependendies from the network"), // awaiting Swift 5.9
                ]),
            dependencies: ["SkipCLI"]),
        .executableTarget(name: "SkipCLI", plugins: ["skiptool"]),
        .testTarget(name: "SkipCLITests", dependencies: ["SkipCLI"]),
    ]
)

package.targets += [.binaryTarget(name: "skiptool", url: "https://github.com/skipsource/skip/releases/download/0.0.15/skiptool.artifactbundle.zip", checksum: "29dd2676ac20f381230acf024fa77fb0c8c6df24dc07c9754bd66fa1f054c156")]

