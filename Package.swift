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

package.targets += [.binaryTarget(name: "skiptool", url: "https://github.com/skipsource/skip/releases/download/0.0.28/skiptool.artifactbundle.zip", checksum: "cf0ae6aaf7e217117e4d28bc3ed0774da752b4b13b287de54f60e5bc4d800482")]

