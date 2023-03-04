// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "skip",
    products: [
        .plugin(name: "skip", targets: ["SkipCommandPlugIn"]),
        .plugin(name: "skippy", targets: ["SkipBuildPlugIn"]),
        .library(name: "SkipUnitTestSupport", targets: ["SkipUnitTestSupport"]),
        //.library(name: "SkipKit", targets: ["SkipKit"]),
    ],
    dependencies: [
        //.package(url: "https://github.com/skiptools/cross-foundation.git", from: "0.0.0"),
        //.package(url: "https://github.com/skiptools/cross-ui.git", from: "0.0.0"),
        //.package(url: "https://github.com/skiptools/cross-test.git", from: "0.0.0"),
    ],
    targets: [
        .target(name: "SkipUnitTestSupport"),
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
        //.target(name: "SkipKit", dependencies: [
        //    .product(name: "CrossFoundation", package: "cross-foundation"),
        //    .product(name: "CrossUI", package: "cross-ui"),
        //    .product(name: "CrossTest", package: "cross-test"),
        //]),
    ]
)

package.targets += [.binaryTarget(name: "skiptool", url: "https://github.com/skiptools/skip/releases/download/0.0.39/skiptool.artifactbundle.zip", checksum: "872f6505c76ccdb320968e8a4a9a4626a5b9ee86ca561dd436a2cc88a4f51a05")]

