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
        .library(name: "SkipLib", targets: ["SkipLib"]),
        .plugin(name: "SkipCheck", targets: ["SkipCheck"]),

        .library(name: "CrossFoundation", targets: ["CrossFoundation"]),
        .library(name: "CrossUI", targets: ["CrossUI"]),

        .library(name: "SampleLib", targets: ["SampleLib"]),
        .library(name: "SampleApp", targets: ["SampleApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-docc-symbolkit.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-tools-support-core.git", from: "0.5.0"),
        .package(url: "https://github.com/marcprux/universal.git", from: "5.0.0"),
    ],
    targets: [
        .target(name: "SkipSyntax", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxParser", package: "swift-syntax"),
            .product(name: "SymbolKit", package: "swift-docc-symbolkit"),
        ]),
        .testTarget(name: "SkipSyntaxTests", dependencies: ["SkipSyntax", "SkipLib", "SkipBuild"]),

        .target(name: "SkipBuild", dependencies: [
            "SkipSyntax",
            .product(name: "Universal", package: "universal"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "TSCBasic", package: "swift-tools-support-core"),
        ]),
        .testTarget(name: "SkipBuildTests", dependencies: ["SkipBuild"]),

        .executableTarget(name: "SkipRunner", dependencies: ["SkipBuild"]),
        .testTarget(name: "SkipRunnerTests", dependencies: ["SkipRunner"], plugins: ["SkipCheck"]),

        .plugin(name: "SkipCheck",
                capability: .buildTool(),
                dependencies: ["SkipRunner"]),
        .plugin(name: "SkipCommand",
                capability: .command(intent: .custom(verb: "skip", description: "Run Skip transpiler"),
                    permissions: [
                        .writeToPackageDirectory(reason: "This command creates kotlin source files")
                    ]),
                dependencies: ["SkipRunner"]),


        .target(name: "SkipUnit", dependencies: ["SkipBuild"]),
        .testTarget(name: "SkipUnitTests", dependencies: ["SkipUnit"]),


        .target(name: "SkipLib"),
        .target(name: "SkipLibKotlin", dependencies: ["SkipLib"], resources: [.copy("skip.yml")]),
        .testTarget(name: "SkipLibTests", dependencies: ["SkipLib", "SkipBuild"]),
        .testTarget(name: "SkipLibKotlinTests", dependencies: ["SkipLibKotlin", "SkipUnit"]),

        .target(name: "CrossFoundation", dependencies: ["SkipLib"], resources: [.process("Resources")]),
        .target(name: "CrossFoundationKotlin", dependencies: ["CrossFoundation"], resources: [.copy("skip.yml")]),
        .testTarget(name: "CrossFoundationTests", dependencies: ["CrossFoundation"], resources: [.process("Resources")]),
        .testTarget(name: "CrossFoundationKotlinTests", dependencies: ["CrossFoundationKotlin", "SkipUnit"]),

        .target(name: "CrossUI", dependencies: ["CrossFoundation"], resources: [.process("Resources")]),
        .target(name: "CrossUIKotlin", dependencies: ["CrossUI"], resources: [.copy("skip.yml")]),
        .testTarget(name: "CrossUITests", dependencies: ["CrossUI"], resources: [.process("Resources")]),
        .testTarget(name: "CrossUIKotlinTests", dependencies: ["CrossUIKotlin", "SkipUnit"]),

        .target(name: "SampleLib", dependencies: ["CrossFoundation"], resources: [.process("Resources")]),
        .target(name: "SampleLibKotlin", dependencies: ["SampleLib"], resources: [.copy("skip.yml")]),
        .testTarget(name: "SampleLibTests", dependencies: ["SampleLib"], resources: [.process("Resources")]),
        .testTarget(name: "SampleLibKotlinTests", dependencies: ["SampleLibKotlin", "SkipUnit"]),

        .target(name: "SampleApp", dependencies: ["SampleLib", "CrossUI"], resources: [.process("Resources")]),
        .target(name: "SampleAppKotlin", dependencies: ["SampleApp"], resources: [.copy("skip.yml")]),
        .testTarget(name: "SampleAppTests", dependencies: ["SampleApp"], resources: [.process("Resources")]),
        .testTarget(name: "SampleAppKotlinTests", dependencies: ["SampleAppKotlin", "SkipUnit"]),

    ]
)
