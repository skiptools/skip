// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "Skip Transpiler",
    defaultLocalization: "en",
    products: [
        .plugin(name: "skip-init", targets: ["Hello Skip"]),

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
                dependencies: ["skiptool"],
                path: "Plugins/SkipInit"),

        .plugin(name: "skip-build",
                capability: .command(
                    intent: .custom(verb: "skip", description: "Run a Skip Gradle build")),
                dependencies: ["skipgradle"],
                path: "Plugins/SkipBuild"),

        .plugin(name: "skip-preflight",
                capability: .buildTool(),
                dependencies: ["skiptool"],
                path: "Plugins/SkipPreflightPlugIn"),

        .plugin(name: "skip-transpiler",
                capability: .buildTool(),
                dependencies: ["skiptool"],
                path: "Plugins/SkipTranspilePlugIn"),

        // skipgradle is the CLI interface from Skip to the Gradle tool for building, testing, and packaging Kotlin
        .executableTarget(name: "skipgradle", dependencies: ["SkipDrive"], path: "Sources/SkipGradle"),
    ]
)

import class Foundation.ProcessInfo
if let localPath = ProcessInfo.processInfo.environment["SKIPLOCAL"] {
    // locally linking SwiftSyntax requires min platform targets
    package.platforms = [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)]
    // build against the local relative packages in the peer folders by running: SKIPLOCAL=.. xed Skip.xcworkspace
    package.dependencies += [.package(path: localPath + "/skiptool")]
    package.targets += [.executableTarget(name: "skiptool", dependencies: [.product(name: "SkipBuild", package: "skiptool")], path: "Sources/SkipTool", sources: ["skiptool.swift"])]
} else {
    // default to using the latest binary skiptool release
    package.targets += [.binaryTarget(name: "skiptool", url: "https://skip.tools/skiptools/skip/releases/download/0.5.19/skiptool.artifactbundle.zip", checksum: "5fbd26317d35c20f57b687c94ae9e3da126a8a01f72b1ddecf7b2f416cb2b9ef")]
}
