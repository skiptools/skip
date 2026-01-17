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
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
        .package(url: "https://github.com/swiftlang/swift-tools-support-core.git", from: "0.7.3"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.1"),
        .package(url: "https://github.com/marcprux/universal.git", from: "5.2.2"),
        .package(url: "https://github.com/marcprux/ELFKit.git", from: "0.2.1"),
    ],
    targets: [
        // SkipDriveExternal is a link to ../../skip/Sources/SkipDrive
        // it allows skipstone.git to share code with skip.git, which would otherwise cause
        // circular package dependecy errors when building the plugin locally
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
            .target(name: "SkipDriveExternal", condition: .when(platforms: [.macOS, .linux])),
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
            .product(name: "Universal", package: "universal"),
            .product(name: "ELFKit", package: "ELFKit"),
        ]),
        .testTarget(name: "SkipBuildTests", dependencies: ["SkipBuild"]),
        .executableTarget(name: "SkipRunner", dependencies: ["SkipBuild"]),
        .testTarget(name: "SkipRunnerTests", dependencies: ["SkipBuild"]),
    ]
)

let SKIP_LICENSE_CHECK = (Context.environment["SKIP_LICENSE_CHECK"] ?? "1") == "1"

if SKIP_LICENSE_CHECK {
    let skipBuild = package.targets.first(where: { $0.name == "SkipBuild"})!
    package.dependencies += [.package(url: "https://github.com/apple/swift-crypto.git", from: "3.15.1")]
    skipBuild.dependencies += [.product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))]
    package.targets.forEach({ target in
        target.swiftSettings = (target.swiftSettings ?? []) + [.define("SKIP_LICENSE_CHECK")]
    })
}
