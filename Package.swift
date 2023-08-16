// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "skip",
    defaultLocalization: "en",
    products: [
        .executable(name: "skip", targets: ["skip"]),

        .plugin(name: "skip-init", targets: ["Hello Skip"]),

        .plugin(name: "skipstone", targets: ["skip-command"]),
        .plugin(name: "preflight", targets: ["skip-preflight"]),
        .plugin(name: "transpile", targets: ["skip-transpiler"]),
        .plugin(name: "skipbuild", targets: ["skip-build"]),

        .library(name: "SkipDrive", targets: ["SkipDrive"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(name: "SkipDrive", dependencies: []),

        .plugin(name: "Hello Skip",
                capability: .command(
                    intent: .custom(verb: "skip-init", description: "Show an introduction to Skip and how it can be added to this project."),
                    permissions: [
                        .writeToPackageDirectory(reason: """
                        Skip: Swift Kotlin Interop (Technology Preview)”

                        This operation will setup the necessary files and folders to transpile your Swift SPM package into a Kotlin Gradle project. It is meant to be run on individual library targets for which a Skip peer Kt module is desited. The command will do the following:

                        1. A “Skip” folder will be created at the root of your package with a skip.yml configuration file and links to the eventual build output of your project.

                        2. The Package.swift file will be modified to add a “TargetNameKt” peer target for each pure-Swift library target, which will use the Skip transpile plugin to generate the Kotlin for its Swift counterpart.

                        3. Test cases that inherit «XCTest» will be transpiled to «JUnit» tests, and the Kotlin test cases can be run from the generated Gradle build files once it is manually installed with the homebrew command: `brew install gradle`

                        4. A “Skip/README.md” file will be created with the results of this command. Please continue reading this file for further instructions once this command completes.

                        You should ensure your project folder is backed up before continuing. By proceeding you agree to abide by the terms and conditions of the Skip license.

                        “Happy Skipping!
                        """)
                    ]),
                dependencies: ["skipstone"],
                path: "Plugins/SkipInit"),

        .plugin(name: "skip-command",
                capability: .command(
                    intent: .custom(verb: "skip",  description: "Run Skip by specifying arguments manually"),
                    permissions: [
                        .writeToPackageDirectory(reason: "Skip needs to create and update the Skip folder in the project."),
                    ]),
                dependencies: ["skipstone"],
                path: "Plugins/SkipCommand"),

        .plugin(name: "skip-build",
                capability: .buildTool(),
                dependencies: ["skipgradle"],
                path: "Plugins/SkipBuild"),

        .plugin(name: "skip-preflight",
                capability: .buildTool(),
                dependencies: ["skipstone"],
                path: "Plugins/SkipPreflightPlugIn"),

        .plugin(name: "skip-transpiler",
                capability: .buildTool(),
                dependencies: ["skipstone"],
                path: "Plugins/SkipTranspilePlugIn"),

        .executableTarget(name: "skip", dependencies: ["SkipDrive"]),

        // skipgradle is the CLI interface from Skip to the Gradle tool for building, testing, and packaging Kotlin
        .executableTarget(name: "skipgradle", dependencies: ["SkipDrive"], path: "Sources/SkipGradle"),
    ]
)

import class Foundation.ProcessInfo
if let localPath = ProcessInfo.processInfo.environment["SKIPLOCAL"] {
    // locally linking SwiftSyntax requires min platform targets
    package.platforms = [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)]
    // build against the local relative packages in the peer folders by running: SKIPLOCAL=.. xed Skip.xcworkspace
    package.dependencies += [.package(path: localPath + "/skipstone")]
    package.targets += [.executableTarget(name: "skipstone", dependencies: [.product(name: "SkipBuild", package: "skipstone")])]
} else {
    // default to using the latest binary skipstone release
    package.targets += [.binaryTarget(name: "skipstone", url: "https://skip.tools/skiptools/skip/releases/download/0.5.46/skipstone.plugin.zip", checksum: "b77f074118a2703b760a07709124c5a17456d7517a2db2496f2088108043ff98")]
}
