// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "SkipPlugIn",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SkipCLI", targets: ["SkipCLI"]),
    ],
    targets: [
        .plugin(name: "Skippy2", 
            capability: .buildTool(), 
            dependencies: ["skiptool"]),
        .plugin(name: "SkipCommand2",
            capability: .command(
                intent: .custom(verb: "skip", 
                description: "Run Skip transpiler"),
                permissions: [
                    .writeToPackageDirectory(reason: "skip creates source files"),
                    //.allowNetworkConnections(scope: .all(ports: []), reason: "skip uses gradle to download dependendies from the network"), // awaiting Swift 5.9
                ]),
            dependencies: ["skiptool"]),
        .executableTarget(name: "SkipCLI",
            plugins: ["skiptool"]),
        .testTarget(name: "SkipCLITests",
            dependencies: ["SkipCLI"]),
    ]
)

package.targets += [.binaryTarget(name: "skiptool", url: "https://github.com/skipsource/skip/releases/download/0.0.6/skiptool.artifactbundle.zip", checksum: "c982b89e177165a35cba433c42d891c86c23590d12027093108e40a3fabbfff3")]

