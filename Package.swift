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
package.targets += [.binaryTarget(name: "skiptool.artifactbundle", url: "https://github.com/skipsource/skip/releases/download/0.0.2/skiptool.artifactbundle.zip", checksum: "438d9371735e723994b0a1ca45b53bd4a2508db1aacd176eabb2037642376fa8")]

