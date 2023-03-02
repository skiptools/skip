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

package.targets += [.binaryTarget(name: "skiptool", url: "https://github.com/skipsource/skip/releases/download/0.0.12/skiptool.artifactbundle.zip", checksum: "6ec020957f78fa801d0ef4eb87d3fe0ed7d02e92b947267ac2778e58a9630538")]

