// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "skip",
    products: [
        .plugin(name: "skip", targets: ["SkipCommandPlugIn"]),
        .plugin(name: "skippy", targets: ["SkipBuildPlugIn"]),
    ],
    targets: [
        .plugin(name: "SkipCommandPlugIn",
            capability: .command(
                intent: .custom(verb: "skip", 
                description: "Run Skip transpiler"),
                permissions: [
                    .writeToPackageDirectory(reason: "skip creates source files"),
                    //.allowNetworkConnections(scope: .all(ports: []), reason: "skip needs the network"), // awaiting Swift 5.9
                ]),
            dependencies: ["skiptool"]),
        .plugin(name: "SkipBuildPlugIn",
            capability: .buildTool(),
            dependencies: ["skiptool"]),
    ]
)

package.targets += [.binaryTarget(name: "skiptool", url: "https://github.com/skipsource/skip/releases/download/0.0.36/skiptool.artifactbundle.zip", checksum: "0aaddb26d53d328ece87c218fbc2bed61e68f1ba44c6e635912331f6cc83ff16")]

