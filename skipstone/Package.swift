// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "SkipSource",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
    ],
    products: [
        .library(name: "SkipSyntax", targets: ["SkipSyntax"]),
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
        .package(url: "https://github.com/apple/swift-syntax.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-docc-symbolkit.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "SkipSyntax", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxParser", package: "swift-syntax"),
            .product(name: "SymbolKit", package: "swift-docc-symbolkit"),
        ]),
        .testTarget(name: "SkipSyntaxTests", dependencies: ["SkipSyntax", "SkipKotlin", "SkipBuild"]),

        .target(name: "SkipBuild", dependencies: ["SkipSyntax"]),
        .testTarget(name: "SkipBuildTests", dependencies: ["SkipBuild"]),

        .target(name: "SkipUnit", dependencies: ["SkipBuild"]),
        .testTarget(name: "SkipUnitTests", dependencies: ["SkipUnit"]),

        .target(name: "SkipKotlin", dependencies: []),
        .testTarget(name: "SkipKotlinTests", dependencies: ["SkipKotlin", "SkipBuild"]),
        .testTarget(name: "SkipKotlinKip", dependencies: ["SkipKotlin", "SkipUnit"]),

        .target(name: "SkipFoundation", dependencies: ["SkipKotlin"], resources: [.process("Resources")]),
        .testTarget(name: "SkipFoundationTests", dependencies: ["SkipFoundation"], resources: [.process("Resources")]),
        .testTarget(name: "SkipFoundationKip", dependencies: ["SkipFoundation", "SkipUnit"]),

        .target(name: "SkipUI", dependencies: ["SkipFoundation"], resources: [.process("Resources")]),
        .testTarget(name: "SkipUITests", dependencies: ["SkipUI"], resources: [.process("Resources")]),
        .testTarget(name: "SkipUIKip", dependencies: ["SkipUI", "SkipUnit"]),

        .target(name: "SkipDemoLib", dependencies: ["SkipFoundation"], resources: [.process("Resources")]),
        .testTarget(name: "SkipDemoLibTests", dependencies: ["SkipDemoLib"], resources: [.process("Resources")]),
        .testTarget(name: "SkipDemoLibKip", dependencies: ["SkipDemoLib", "SkipUnit"]),

        .target(name: "SkipDemoApp", dependencies: ["SkipDemoLib", "SkipUI"], resources: [.process("Resources")]),
        .testTarget(name: "SkipDemoAppTests", dependencies: ["SkipDemoApp"], resources: [.process("Resources")]),
        .testTarget(name: "SkipDemoAppKip", dependencies: ["SkipDemoApp", "SkipUnit"]),

        .executableTarget(name: "SkipRunner", dependencies: ["SkipBuild", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .testTarget(name: "SkipRunnerTests", dependencies: [], plugins: ["Skippy"]),

        .plugin(name: "Skippy",
                capability: .buildTool(),
                dependencies: ["SkipRunner"]),
        .plugin(name: "SkipCommand",
                capability: .command(intent: .custom(verb: "skip", description: "Run Skip transpiler"),
                    permissions: [
                        .writeToPackageDirectory(reason: "This command creates kotlin source files")
                    ]),
                dependencies: ["SkipRunner"]),
    ]
)
