// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "skip",
    products: [
        .plugin(name: "skip", targets: ["SkipCommandPlugIn"]),
    ],
    targets: [
        .plugin(name: "SkipBuildPlugIn",
            capability: .buildTool(), 
            dependencies: ["skiptool"]),
        .plugin(name: "SkipCommandPlugIn",
            capability: .command(
                intent: .custom(verb: "skip", 
                description: "Run Skip transpiler"),
                permissions: [
                    .writeToPackageDirectory(reason: "skip creates source files"),
                    //.allowNetworkConnections(scope: .all(ports: []), reason: "skip uses gradle to download dependendies from the network"), // awaiting Swift 5.9
                ]),
            dependencies: ["skiptool"]),
//        .executableTarget(name: "SkipCLI", plugins: ["skiptool"]),
//        .testTarget(name: "SkipCLITests", dependencies: ["SkipCLI"]),
    ]
)

package.targets += [.binaryTarget(name: "skiptool", url: "https://github.com/skipsource/skip/releases/download/0.0.30/skiptool.artifactbundle.zip", checksum: "e2af696d833d548939b1388798de9526a84d7648c88e27a5ef60f684ee9d5cfc")]

