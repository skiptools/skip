// swift-tools-version: 5.7
import PackageDescription
import class Foundation.ProcessInfo

let package = Package(
    name: "skip",
    products: [
        .plugin(name: "skip", targets: ["SkipCommandPlugIn"]),
        .plugin(name: "skippy", targets: ["SkipBuildPlugIn"]),
        .library(name: "SkipUnitTestSupport", targets: ["SkipUnitTestSupport"]),
        //.library(name: "SkipKit", targets: ["SkipKit"]),

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
        .plugin(name: "SkipBuildPlugIn", capability: .buildTool(), dependencies: ["skiptool"]),

        .plugin(name: "SkipPrecheckPlugIn", capability: .buildTool(), dependencies: ["skiptool"]),
        .plugin(name: "SkipTranspilePlugIn", capability: .buildTool(), dependencies: ["skiptool"]),
        .plugin(name: "SkipGradlePlugIn", capability: .buildTool(), dependencies: ["skiptool"]),
    ]
)


if let _ = ProcessInfo.processInfo.environment["SKIP_USE_LOCAL_DEPS"] {
    // build agains the local relative package ../SkipSource
    package.dependencies += [.package(path: "../SkipSource")]
    package.targets += [.binaryTarget(name: "skiptool", url: "https://github.com/skiptools/skip/releases/download/0.0.45/skiptool.artifactbundle.zip", checksum: "571b63d95fdf8b5c498f6ea54190395d5b0b9efd25b0aef17a8d53b64a6cae84")]
} else {
    // use the binary dependency
    package.targets += [.binaryTarget(name: "skiptool", url: "https://github.com/skiptools/skip/releases/download/0.0.45/skiptool.artifactbundle.zip", checksum: "571b63d95fdf8b5c498f6ea54190395d5b0b9efd25b0aef17a8d53b64a6cae84")]
}
