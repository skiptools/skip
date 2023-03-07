// swift-tools-version: 5.7
import PackageDescription
import class Foundation.ProcessInfo

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
//        .library(name: "SkipUnitTestSupport", targets: ["SkipUnitTestSupport"]),

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


if !0.isZero { // let _ = ProcessInfo.processInfo.environment["SKIP_USE_LOCAL_DEPS"] {
    // build agains the local relative package ../SkipSource
    package.dependencies += [.package(path: "../SkipSource")]
    package.targets += [.executableTarget(name: "skiptool", dependencies: [.product(name: "SkipBuild", package: "SkipSource")])]
} else {
    // use the binary dependency
    package.targets += [.binaryTarget(name: "skiptool", url: "https://github.com/skiptools/skip/releases/download/0.0.49/skiptool.artifactbundle.zip", checksum: "a160a9edc3b533c6303f5f574e3f57c4d4a29bf883a3161f2aa7a5e5a14b3151")]
}
