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

package.targets += [.binaryTarget(name: "SkipRunner", url: "https://github.com/skipsource/skip/releases/download/main-1677773888/skiptool.artifactbundle.zip", checksum: "7e524e0322247fecd26dd8d6ea80d158f1f740234effeda61f8fca95a317e721")]

