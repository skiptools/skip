// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "skipstone",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
        .macCatalyst(.v16),
    ],
    products: [
        .library(name: "SkipSyntax", targets: ["SkipSyntax"]),
        .library(name: "SkipBuild", targets: ["SkipBuild"]),
        .executable(name: "SkipRunner", targets: ["SkipRunner"]),
        .executable(name: "SkipKey", targets: ["SkipKey"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.0-prerelease-2024-06-12"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-tools-support-core.git", from: "0.6.1"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.4.0"),
        .package(url: "https://github.com/marcprux/universal.git", from: "5.2.2"),
    ],
    targets: [
        // SkipDriveExternal is a link to ../../skip/Sources/SkipDrive
        // it allows skipstone.git to share code with skip.git, which would otherwise cause circular package dependecy errors
        .target(name: "SkipDriveExternal"),

        .target(name: "SkipSyntax", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax"),
        ]),
        .testTarget(name: "SkipSyntaxTests", dependencies: [
            "SkipSyntax",
            "SkipBuild",
            .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
        ]),

        .target(name: "SkipBuild", dependencies: [
            "SkipSyntax",
            .target(name: "SkipDriveExternal", condition: .when(platforms: [.macOS])),
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
            .product(name: "Universal", package: "universal"),
            .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
        ]),
        .testTarget(name: "SkipBuildTests", dependencies: ["SkipBuild"]),

        .executableTarget(name: "SkipRunner", dependencies: ["SkipBuild"]),
        .testTarget(name: "SkipRunnerTests", dependencies: ["SkipBuild"]),

        .executableTarget(name: "SkipKey", dependencies: ["SkipBuild"]),
        .testTarget(name: "SkipKeyTests", dependencies: ["SkipBuild"]),
    ]
)
