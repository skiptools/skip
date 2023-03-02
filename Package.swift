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

package.targets += [.binaryTarget(name: "skiptool", url: "https://github.com/skipsource/skip/releases/download/0.0.31/skiptool.artifactbundle.zip", checksum: "464a62c853c9e8237a16aa478babc495ab579503e204029270969a05aaa6dd53")]

