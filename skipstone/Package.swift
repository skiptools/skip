// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "SkipSource",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .macCatalyst(.v15),
    ],
    products: [
        .library(name: "SkipSyntax", targets: ["SkipSyntax"]),
        .library(name: "SkipBuild", targets: ["SkipBuild"]),
        .executable(name: "SkipRunner", targets: ["SkipRunner"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-docc-symbolkit.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.2"),
        .package(url: "https://github.com/apple/swift-tools-support-core.git", from: "0.5.1"),
        .package(url: "https://github.com/marcprux/universal.git", from: "5.2.0"),
    ],
    targets: [
        .target(name: "SkipSyntax", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxParser", package: "swift-syntax"),
            .product(name: "SymbolKit", package: "swift-docc-symbolkit"),
        ]),
        .testTarget(name: "SkipSyntaxTests", dependencies: [
            "SkipSyntax",
            "SkipBuild",
        ], resources: [.copy("symbols")]),

        .target(name: "SkipBuild", dependencies: [
            "SkipSyntax",
            .product(name: "SwiftSyntaxParser", package: "swift-syntax"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "TSCBasic", package: "swift-tools-support-core"),
            .product(name: "Universal", package: "universal"),
        ]),
        .testTarget(name: "SkipBuildTests", dependencies: ["SkipBuild"]),

        .executableTarget(name: "SkipRunner", dependencies: ["SkipBuild"]),
        .testTarget(name: "SkipRunnerTests", dependencies: ["SkipRunner"]),
    ]
)
