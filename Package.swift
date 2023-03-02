// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "SkipPlugIn",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SkipCLI", targets: ["SkipCLI"]),
    ],
    targets: [
        .plugin(name: "Skippy", 
            capability: .buildTool(), 
            dependencies: ["SkipRunner"]),
        .plugin(name: "SkipCommand",
            capability: .command(
                intent: .custom(verb: "skip", 
                description: "Run Skip transpiler"),
                permissions: [
                    .writeToPackageDirectory(reason: "skip creates source files"),
                    //.allowNetworkConnections(scope: .all(ports: []), reason: "skip uses gradle to download dependendies from the network"),
                ]),
            dependencies: ["SkipRunner"]),
        .executableTarget(name: "SkipCLI",
            plugins: ["SkipRunner"]),
        .testTarget(name: "SkipCLITests",
            dependencies: ["SkipCLI"]),
    ]
)
// YYY
package.targets += [.binaryTarget(name: "skiptool.artifactbundle", url: "https://github.com/skipsource/skip/releases/download/0.0.3/skiptool.artifactbundle.zip", checksum: "44e4e86db14a5aa204ea829c5ef9c1396c443de2bc2dd9f517a0fe389644218e")]

