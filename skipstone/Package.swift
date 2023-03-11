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
        .library(name: "SkipUnit", targets: ["SkipUnit"]),

        .plugin(name: "SkipCheck", targets: ["SkipCheck"]),

        .library(name: "ExampleSkipPrecheck", targets: ["ExampleSkipPrecheck"]),

        .library(name: "SkipLib", targets: ["SkipLib"]),
        .library(name: "SkipLibKotlin", targets: ["SkipLib"]),

        .library(name: "CrossFoundation", targets: ["CrossFoundation"]),
        .library(name: "CrossFoundationKotlin", targets: ["CrossFoundationKotlin"]),

        .library(name: "CrossUI", targets: ["CrossUI"]),
        .library(name: "CrossUIKotlin", targets: ["CrossUIKotlin"]),

        .library(name: "ExampleLib", targets: ["ExampleLib"]),
        .library(name: "ExampleLibKotlin", targets: ["ExampleLibKotlin"]),

        .library(name: "ExampleApp", targets: ["ExampleApp"]),
        .library(name: "ExampleAppKotlin", targets: ["ExampleAppKotlin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-docc-symbolkit.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.2"),
        .package(url: "https://github.com/apple/swift-tools-support-core.git", from: "0.5.1"),
        .package(url: "https://github.com/marcprux/universal.git", from: "5.1.1"),
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
            .product(name: "SwiftSyntaxParser", package: "swift-syntax"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "TSCBasic", package: "swift-tools-support-core"),
            .product(name: "Universal", package: "universal"),
        ]),
        .testTarget(name: "SkipBuildTests", dependencies: ["SkipBuild"]),

        .executableTarget(name: "SkipRunner", dependencies: ["SkipBuild"]),
        .testTarget(name: "SkipRunnerTests", dependencies: ["SkipRunner"]),

        .plugin(name: "SkipCheck",
                capability: .buildTool(),
                dependencies: ["SkipRunner"]),
        .plugin(name: "SkipCommand",
                capability: .command(intent: .custom(verb: "skip", description: "Run Skip transpiler"),
                    permissions: [
                        .writeToPackageDirectory(reason: "This command creates kotlin source files")
                    ]),
                dependencies: ["SkipRunner"]),


        .target(name: "ExampleSkipPrecheck", plugins: ["SkipCheck"]),

        .target(name: "SkipUnit", dependencies: ["SkipBuild"]),
        .testTarget(name: "SkipUnitTests", dependencies: ["SkipUnit"]),


        .target(name: "SkipLib"),
        .testTarget(name: "SkipLibTests", dependencies: ["SkipLib", "SkipBuild"]),

        .target(name: "SkipLibKotlin", dependencies: ["SkipLib"], resources: [.copy("skip")]),
        .testTarget(name: "SkipLibKotlinTests", dependencies: ["SkipLibKotlin", "SkipUnit"]),


        .target(name: "CrossFoundation", dependencies: ["SkipLib"], resources: [.process("Resources")]),
        .testTarget(name: "CrossFoundationTests", dependencies: ["CrossFoundation"], resources: [.process("Resources")]),

        .target(name: "CrossFoundationKotlin", dependencies: ["CrossFoundation", "SkipLibKotlin"], resources: [.copy("skip")]),
        .testTarget(name: "CrossFoundationKotlinTests", dependencies: ["CrossFoundationKotlin", "SkipUnit"]),


        .target(name: "CrossUI", dependencies: ["CrossFoundation"], resources: [.process("Resources")]),
        .testTarget(name: "CrossUITests", dependencies: ["CrossUI"], resources: [.process("Resources")]),

        .target(name: "CrossUIKotlin", dependencies: ["CrossUI", "CrossFoundationKotlin"], resources: [.copy("skip")]),
        .testTarget(name: "CrossUIKotlinTests", dependencies: ["CrossUIKotlin", "SkipUnit"]),


        .target(name: "ExampleLib", dependencies: ["CrossFoundation"], resources: [.process("Resources")]),
        .testTarget(name: "ExampleLibTests", dependencies: ["ExampleLib"], resources: [.process("Resources")]),

        .target(name: "ExampleLibKotlin", dependencies: ["ExampleLib", "CrossFoundationKotlin"], resources: [.copy("skip")]),
        .testTarget(name: "ExampleLibKotlinTests", dependencies: ["ExampleLibKotlin", "SkipUnit"]),


        .target(name: "ExampleApp", dependencies: ["ExampleLib", "CrossUI"], resources: [.process("Resources")]),
//        .target(name: "ExampleApp", dependencies: [
//            .product(name: "ExampleLib", package: "example-lib"),
//            .product(name: "CrossUI", package: "cross-ui")
//        ], resources: [.process("Resources")]),
        .testTarget(name: "ExampleAppTests", dependencies: ["ExampleApp"], resources: [.process("Resources")]),

        .target(name: "ExampleAppKotlin", dependencies: ["ExampleApp"], resources: [.copy("skip")]),
        .testTarget(name: "ExampleAppKotlinTests", dependencies: ["ExampleAppKotlin", "SkipUnit"]),
    ]
)
