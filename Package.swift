// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "skip",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .macCatalyst(.v15),
    ],
    products: [
        .plugin(name: "skip", targets: ["SkipCommandPlugIn"]),
        .plugin(name: "skippy", targets: ["SkipBuildPlugIn"]),
        .plugin(name: "precheck", targets: ["SkipPrecheckPlugIn"]),
        .plugin(name: "transpile", targets: ["SkipTranspilePlugIn"]),
        .plugin(name: "gradle", targets: ["SkipGradlePlugIn"]),
    ],
    dependencies: [
        //.package(url: "https://github.com/skiptools/skip-lib.git", from: "0.0.0"),
        //.package(url: "https://github.com/skiptools/skip-test.git", from: "0.0.0"),
        //.package(url: "https://github.com/skiptools/cross-foundation.git", from: "0.0.0"),
        //.package(url: "https://github.com/skiptools/cross-ui.git", from: "0.0.0"),
        //.package(url: "https://github.com/skiptools/example-lib.git", from: "0.0.0"),
        //.package(url: "https://github.com/skiptools/example-app.git", from: "0.0.0"),
    ],
    targets: [
//        .target(name: "SkipUnitTestSupport"),
        .plugin(name: "SkipCommandPlugIn",
            capability: .command(
                intent: .custom(verb: "skip", 
                description: "Run Skip transpiler"),
                permissions: [
                    .writeToPackageDirectory(reason: "skip creates source files"),
                    //.allowNetworkConnections(scope: .all(ports: []), reason: "skip needs the network"), // awaiting Swift 5.9
                ]),
            dependencies: ["skiptool"]),
        .plugin(name: "SkipBuildPlugIn", capability: .buildTool(), dependencies: ["skiptool"]),

        .plugin(name: "SkipPrecheckPlugIn", capability: .buildTool(), dependencies: ["skiptool"]),
        .plugin(name: "SkipTranspilePlugIn", capability: .buildTool(), dependencies: ["skiptool"]),
        .plugin(name: "SkipGradlePlugIn", capability: .buildTool(), dependencies: ["skiptool"]),
    ]
)

import class Foundation.ProcessInfo
if let localPath = ProcessInfo.processInfo.environment["SKIPLOCAL"] {
    // build against the local relative packages in the peer folders by running: SKIPLOCAL=.. xed Skip.xcworkspace
    package.dependencies += [.package(path: localPath + "/SkipSource")]
    package.targets += [.executableTarget(name: "skiptool", dependencies: [.product(name: "SkipBuild", package: "SkipSource")], path: "Sources/SkipTool")]
} else {
    // default to using the latest binary skiptool release
    package.targets += [.binaryTarget(name: "skiptool", url: "https://github.com/skiptools/skip/releases/download/0.0.52/skiptool.artifactbundle.zip", checksum: "330d97ef309d920da77b3591e0a8fdbdd7f58f78efaa766521319e48508ecc1e")]
}
