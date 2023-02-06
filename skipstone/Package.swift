// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Skip",
    platforms: [
        .macOS(.v12),
        .iOS(.v16),
    ],
    products: [
        .library(name: "Skip", targets: ["Skip"]),
        .library(name: "SkipPack", targets: ["SkipPack"]),
        .library(name: "SkipTest", targets: ["SkipTest"]),
        .plugin(name: "Skippy", targets: ["Skippy"]),
        .library(name: "SkipFoundation", targets: ["SkipFoundation"]),
        .library(name: "SkipUI", targets: ["SkipUI"]),
        .library(name: "SkipDemoLib", targets: ["SkipDemoLib"]),
        .library(name: "SkipDemoApp", targets: ["SkipDemoApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-docc-symbolkit.git", branch: "main"),
    ],
    targets: [
        .target(name: "Skip", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxParser", package: "swift-syntax"),
            .product(name: "SymbolKit", package: "swift-docc-symbolkit"),
        ]),
        .target(name: "SkipPack", dependencies: ["Skip"]),
        .target(name: "SkipTest", dependencies: ["SkipPack"]),
        .target(name: "SkipFoundation", dependencies: []),
        .target(name: "SkipUI", dependencies: ["SkipFoundation"]),
        .target(name: "SkipDemoLib", dependencies: ["SkipFoundation"]),
        .target(name: "SkipDemoApp", dependencies: ["SkipDemoLib", "SkipUI"]),
        .executableTarget(name: "SkipRunner", dependencies: ["SkipPack"]),
        .plugin(name: "Skippy", capability: .buildTool(), dependencies: ["SkipRunner"]),
        .plugin(name: "SkipCommand",
                capability: .command(intent: .custom(verb: "skip", description: "Run Skip transpiler")),
                dependencies: ["SkipRunner"]),
        .testTarget(name: "SkipTests", dependencies: ["Skip"]),
        .testTarget(name: "SkipRunnerTests", dependencies: [], plugins: ["Skippy"]),
        .testTarget(name: "SkipPackTests", dependencies: ["SkipPack"]),
        .testTarget(name: "SkipTestTests", dependencies: ["SkipTest"]),
        .testTarget(name: "SkipFoundationTests", dependencies: ["SkipFoundation", "SkipTest"]),
        .testTarget(name: "SkipUITests", dependencies: ["SkipUI", "SkipTest"]),
        .testTarget(name: "SkipDemoAppTests", dependencies: ["SkipDemoApp", "SkipTest"]),
        .testTarget(name: "SkipDemoLibTests", dependencies: ["SkipDemoLib", "SkipTest"]),
    ]
)
