// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Skip",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "Skip", targets: ["Skip"]),
        .library(name: "SkipBuild", targets: ["SkipBuild"]),
        .library(name: "SkipUnit", targets: ["SkipUnit"]),
        .library(name: "SkipKotlin", targets: ["SkipKotlin"]),
        .library(name: "SkipFoundation", targets: ["SkipFoundation"]),
        .library(name: "SkipUI", targets: ["SkipUI"]),
        .library(name: "SkipDemoLib", targets: ["SkipDemoLib"]),
        .library(name: "SkipDemoApp", targets: ["SkipDemoApp"]),
        .plugin(name: "Skippy", targets: ["Skippy"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", revision: "swift-DEVELOPMENT-SNAPSHOT-2023-01-19-a"),
        .package(url: "https://github.com/apple/swift-docc-symbolkit.git", branch: "main"),
    ],
    targets: [
        .target(name: "Skip", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxParser", package: "swift-syntax"),
            .product(name: "SymbolKit", package: "swift-docc-symbolkit"),
        ]),
        .target(name: "SkipBuild", dependencies: ["Skip"]),
        .target(name: "SkipUnit", dependencies: ["SkipBuild"]),
        .target(name: "SkipKotlin", dependencies: []),
        .target(name: "SkipFoundation", dependencies: []),
        .target(name: "SkipUI", dependencies: ["SkipFoundation"]),
        .target(name: "SkipDemoLib", dependencies: ["SkipFoundation"]),
        .target(name: "SkipDemoApp", dependencies: ["SkipDemoLib", "SkipUI"]),

        .testTarget(name: "SkipTests", dependencies: ["Skip", "SkipBuild"]),
        .testTarget(name: "SkipRunnerTests", dependencies: [], plugins: ["Skippy"]),
        .testTarget(name: "SkipBuildTests", dependencies: ["SkipBuild"]),
        .testTarget(name: "SkipUnitTests", dependencies: ["SkipUnit"]),
        .testTarget(name: "SkipKotlinTests", dependencies: ["SkipKotlin", "SkipUnit"]),
        .testTarget(name: "SkipFoundationTests", dependencies: ["SkipFoundation", "SkipUnit"], resources: [.process("Resources")]),
        .testTarget(name: "SkipUITests", dependencies: ["SkipUI", "SkipUnit"]),
        .testTarget(name: "SkipDemoAppTests", dependencies: ["SkipDemoApp", "SkipUnit"]),
        .testTarget(name: "SkipDemoLibTests", dependencies: ["SkipDemoLib", "SkipUnit"]),

        .executableTarget(name: "SkipRunner", dependencies: ["SkipBuild"]),
        .plugin(name: "Skippy", capability: .buildTool(), dependencies: ["SkipRunner"]),
        .plugin(name: "SkipCommand",
                capability: .command(intent: .custom(verb: "skip", description: "Run Skip transpiler")),
                dependencies: ["SkipRunner"]),
    ]
)
