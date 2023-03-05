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

package.targets += [.binaryTarget(name: "skiptool", url: "https://github.com/skiptools/skip/releases/download/0.0.40/skiptool.artifactbundle.zip", checksum: "5f49333aaacbaa0c25f159c754a1f46a08f745c67cb02ba6a5be37ff7b06e151")]

