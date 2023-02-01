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
        .plugin(name: "Skippy", targets: ["Skippy"]),
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
        .executableTarget(name: "SkipRunner", dependencies: [
            "Skip",
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxParser", package: "swift-syntax"),
        ]),
        .plugin(name: "Skippy", capability: .buildTool(), dependencies: ["SkipRunner"]),
        .plugin(name: "SkipCommand",
                capability: .command(intent: .custom(verb: "skip", description: "Run Skip transpiler")),
                dependencies: ["SkipRunner"]),
        .testTarget(name: "SkipTests", dependencies: ["Skip"]),
        .testTarget(name: "SkipRunnerTests", dependencies: [], plugins: ["Skippy"]),
    ]
)
