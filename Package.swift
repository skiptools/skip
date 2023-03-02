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

package.targets += [.binaryTarget(name: "skiptool", url: "https://github.com/skipsource/skip/releases/download/0.0.7/skiptool.artifactbundle.zip", checksum: "1bf7c10b624724b5443387f1601c62c982860d4a33d06d222bfbc78125c78514")]

