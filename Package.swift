// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "skip",
    defaultLocalization: "en",
    products: [
        .plugin(name: "hello-skip", targets: ["Hello Skip"]),
        .plugin(name: "run-kotlin-tests", targets: ["Run Kotlin Tests"]),
        .plugin(name: "synchronize-gradle", targets: ["Synchronize Gradle Project"]),

        .plugin(name: "preflight", targets: ["skip-preflight"]),
        .plugin(name: "transpile", targets: ["skip-transpiler"]),

        .library(name: "SkipDriver", targets: ["SkipDriver"])
    ],
    dependencies: [
    ],
    targets: [
        .plugin(name: "Hello Skip",
                capability: .command(
                    intent: .custom(verb: "skip-welcome",  description: "Show an introduction to Skip and how it can be added to this project."),
                    permissions: [
                        .writeToPackageDirectory(reason: """
                        Skip: Swift Kotlin Interop”

                        This plugin will setup the necessary files and folders to transpile your Swift SPM package into a Kotlin Gradle project.

                        • A “Skip” folder will be created at the root of your package with links to the generated Kotlin sources.

                        • A “TargetNameKt” peer target will be created for each library target in the package, which will use the Skip plugin to transpile the Swift code into Kotlin.

                        • Test cases that inherit `XCTest` will be transpiled to JUnit tests, and the Kotlin test cases can be run from the generated Gradle build files once it is manually installed with the command: `brew install gradle`

                        • All Swift dependencies, either local or external, must each have their own Kt peer targets configured. Only Swift source targets are supported: no C, C++, Objective-C or binary targets will be transpiled.

                        • A “Skip/README.md” file will be created with the results of this command. Please continue reading this file for further instructions once it has been generated.

                        “Happy Skipping!
                        """)
                    ]),
                dependencies: ["skiptool"],
                path: "Plugins/HelloSkip"),

        .plugin(name: "Run Kotlin Tests",
                capability: .command(
                    intent: .custom(verb: "skip-test",  description: "Add Kotlin Targets to the current Package.swift"),
                    permissions: [
                        .writeToPackageDirectory(reason: "Skip needs to create and update the Skip folder in the project."),
                    ]),
                dependencies: ["skiptool"],
                path: "Plugins/RunGradleTests"),

        .plugin(name: "Skip Custom Command",
                capability: .command(
                    intent: .custom(verb: "skip",  description: "Run a custom Skip command by specifying arguments manually"),
                    permissions: [
                        .writeToPackageDirectory(reason: "Skip needs to create and update the Skip folder in the project."),
                    ]),
                dependencies: ["skiptool"],
                path: "Plugins/SkipCommand"),

        .plugin(name: "Synchronize Gradle Project",
                capability: .command(
                    intent: .custom(verb: "skip-sync",  description: "Create local links to the transpiled gradle project(s)"),
                    permissions: [
                        .writeToPackageDirectory(reason: "Skip needs to create and update the Skip folder in the project."),
                    ]),
                dependencies: ["skiptool"],
                path: "Plugins/SynchronizeGradle"),

        .plugin(name: "skip-preflight",
                capability: .buildTool(),
                dependencies: ["skiptool"],
                path: "Plugins/SkipPreflightPlugIn"),

        .plugin(name: "skip-transpiler",
                capability: .buildTool(),
                // dependencies: ["SkipDriver"], // plugin 'skip-transpiler' cannot depend on 'SkipDriver' of type 'library'; this dependency is unsupported
                dependencies: ["skiptool"],
                path: "Plugins/SkipTranspilePlugIn"),

        .target(name: "SkipDriver", dependencies: ["skiptool"]),
        .testTarget(name: "SkipDriverTests", dependencies: ["SkipDriver"]),
    ]
)

import class Foundation.ProcessInfo
if let localPath = ProcessInfo.processInfo.environment["SKIPLOCAL"] {
    // locally linking SwiftSyntax requires min platform targets
    package.platforms = [.iOS(.v15), .macOS(.v12), .tvOS(.v15), .watchOS(.v8), .macCatalyst(.v15)]
    // build against the local relative packages in the peer folders by running: SKIPLOCAL=.. xed Skip.xcworkspace
    package.dependencies += [.package(path: localPath + "/SkipSource")]
    package.targets += [.executableTarget(name: "skiptool", dependencies: [.product(name: "SkipBuild", package: "SkipSource")], path: "Sources/SkipTool", sources: ["skiptool.swift"])]
} else {
    // default to using the latest binary skiptool release
    package.targets += [.binaryTarget(name: "skiptool", url: "https://github.com/skiptools/skip/releases/download/0.3.4/skiptool.artifactbundle.zip", checksum: "5710271332a052278fae36d1e5d57db9772af472a12bdd730121b7c1f8ebe1d2")]
}
