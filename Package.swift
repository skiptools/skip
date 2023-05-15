// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "Skip Transpiler",
    defaultLocalization: "en",
    products: [
        .plugin(name: "skip-init", targets: ["Hello Skip"]),
        .plugin(name: "skip-sync", targets: ["Synchronize Packages/Skip"]),
        .plugin(name: "skip", targets: ["Skip Custom Command"]),

        .plugin(name: "preflight", targets: ["skip-preflight"]),
        .plugin(name: "transpile", targets: ["skip-transpiler"]),
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

        .plugin(name: "Synchronize Packages/Skip",
                capability: .command(
                    intent: .custom(verb: "skip-sync",  description: "Synchronize and link the local Skip build output folder(s)"),
                    permissions: [
                        .writeToPackageDirectory(reason: """
                        This command synchronizes and links the build output of the transpiled Gradle project, facilitating the browsing and opening of project files in an external editor.

                        The sync process will create local links under the Packages/Skip/ folder to the DerivedData output of the Skip transpilation process for any Kt library target that is selected.

                        Skip Sync may need to be re-run if the build folder is cleaned or the Xcode DerivedData path changes. You should ensure your project folder is backed up before continuing. By proceeding you agree to abide by the terms and conditions of the Skip license.
                        """)
                    ]),
                dependencies: ["skiptool"],
                path: "Plugins/SkipSync"),

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
                dependencies: ["skiptool"],
                path: "Plugins/SkipTranspilePlugIn"),
    ]
)

import class Foundation.ProcessInfo
if let localPath = ProcessInfo.processInfo.environment["SKIPLOCAL"] {
    // locally linking SwiftSyntax requires min platform targets
    package.platforms = [.iOS(.v15), .macOS(.v12), .tvOS(.v15), .watchOS(.v8), .macCatalyst(.v15)]
    // build against the local relative packages in the peer folders by running: SKIPLOCAL=.. xed Skip.xcworkspace
    package.dependencies += [.package(path: localPath + "/skiptool")]
    package.targets += [.executableTarget(name: "skiptool", dependencies: [.product(name: "SkipBuild", package: "skiptool")], path: "Sources/SkipTool", sources: ["skiptool.swift"])]
} else {
    // default to using the latest binary skiptool release
    package.targets += [.binaryTarget(name: "skiptool", url: "https://github.com/skiptools/skip/releases/download/0.4.33/skiptool.artifactbundle.zip", checksum: "a8dc051222e63d170c55b5f2feabefcafcd0fba4e7e5aa693d9a02d3f33c406e")]
}
