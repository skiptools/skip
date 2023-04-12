// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "skip",
    defaultLocalization: "en",
    products: [
        .plugin(name: "skip-init", targets: ["Hello Skip"]),
        .plugin(name: "skip", targets: ["Skip Custom Command"]),

        .plugin(name: "preflight", targets: ["skip-preflight"]),
        .plugin(name: "transpile", targets: ["skip-transpiler"]),

        .library(name: "SkipDriver", targets: ["SkipDriver"])
    ],
    dependencies: [
    ],
    targets: [
        .plugin(name: "Hello Skip",
                capability: .command(
                    intent: .custom(verb: "skip-init",  description: "Show an introduction to Skip and how it can be added to this project."),
                    permissions: [
                        .writeToPackageDirectory(reason: """
                        Skip: Swift Kotlin Interop (Technology Preview)”

                        This operation will setup the necessary files and folders to transpile your Swift SPM package into a Kotlin Gradle project.

                        1. A “Skip” folder will be created at the root of your package with a skip.yml configuration file and links to the eventual build output of your project.

                        2. The Package.swift file will be modified to add a “TargetNameKt” peer target for each pure-Swift library target, which will use the Skip transpile plugin to generate the Kotlin for its Swift counterpart.

                        3. Test cases that inherit «XCTest» will be transpiled to «JUnit» tests, and the Kotlin test cases can be run from the generated Gradle build files once it is manually installed with the homebrew command: `brew install gradle`

                        4. A “Skip/README.md” file will be created with the results of this command. Please continue reading this file for further instructions once this command completes.

                        You should ensure your project folder is backed up before continuing. By proceeding you agree to abide by the terms and conditions of the Skip license.

                        “Happy Skipping!
                        """)
                    ]),
                dependencies: ["skiptool"],
                path: "Plugins/SkipInit"),

        .plugin(name: "Skip Custom Command",
                capability: .command(
                    intent: .custom(verb: "skip",  description: "Run a custom Skip command by specifying arguments manually"),
                    permissions: [
                        .writeToPackageDirectory(reason: "Skip needs to create and update the Skip folder in the project."),
                    ]),
                dependencies: ["skiptool"],
                path: "Plugins/SkipCommand"),

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
    package.targets += [.binaryTarget(name: "skiptool", url: "https://github.com/skiptools/skip/releases/download/0.3.29/skiptool.artifactbundle.zip", checksum: "b94a2963f34927ce92d79750133e48f2dd975bde6bf68c20d6886c951d278e0f")]
}
