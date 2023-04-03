// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation
import PackagePlugin

enum SkipBuildCommand {
    case helloSkip
    case synchronizeGradle
    case runGradleTests
}

/// The options to use when running the plugin command.
struct SkipCommandOptions : OptionSet {
    let rawValue: Int

    public static let `default`: Self = [scaffold, preflight, transpile, targets]

    /// Create the scaffold of folders and files for Kt targets.
    public static let scaffold = Self(rawValue: 1 << 0)

    /// Adds the preflight plugin to each selected target
    public static let preflight = Self(rawValue: 1 << 1)

    /// Adds the transpile plugin to each of the created targets
    public static let transpile = Self(rawValue: 1 << 2)

    /// Add the Kt targets to the Package.swift
    public static let targets = Self(rawValue: 1 << 3)

//    /// Add the Package.swift modification directly to the file rather than the README.md
//    public static let inplace = Self(rawValue: 1 << 4)
}


/// An extension that is shared between multiple plugin targets.
///
/// This file is included in the plugin source folders as a symbolic links.
/// This works around the limitation that SPM plugins cannot depend on a shared library target,
/// and thus is the only way to share code between plugins.
extension CommandPlugin {

    func performBuildCommand(_ options: SkipCommandOptions, context: PluginContext, arguments: [String]) throws {
        Diagnostics.remark("performing build command with options: \(options)")

        var args = ArgumentExtractor(arguments)
        let targetArgs = args.extractOption(named: "target")
        let targets = try context.package.targets(named: targetArgs)
        let sourceTargets = targets.compactMap { $0 as? SwiftSourceModuleTarget }
        let overwrite = args.extractFlag(named: "overwrite") > 0
        let _ = overwrite
        let targetNames = sourceTargets.map(\.moduleName)

        Diagnostics.remark("targets: \(targetNames)")
        Diagnostics.remark("package.displayName: \(context.package.displayName)")
        Diagnostics.remark("package.id: \(context.package.id)")
        Diagnostics.remark("package.origin: \(context.package.origin)")
        Diagnostics.remark("target ids: \(sourceTargets.map(\.id))")
        Diagnostics.remark("target ids: \(sourceTargets.map(\.recursiveTargetDependencies))")
        Diagnostics.remark("package.directory: \(context.package.directory)")
        Diagnostics.remark("pluginWorkDirectory: \(context.pluginWorkDirectory)") // 

        var contents = """
        ███████╗██╗  ██╗██╗██████╗
        ██╔════╝██║ ██╔╝██║██╔══██╗
        ███████╗█████╔╝ ██║██████╔╝
        ╚════██║██╔═██╗ ██║██╔═══╝
        ███████║██║  ██╗██║██║
        ╚══════╝╚═╝  ╚═╝╚═╝╚═╝

        Welcome to Skip!

        The Skip build plugin will transform your Swift package
        targets and tests into Kotlin and generate Gradle build
        files for each of the targets.

        To add support for Skip to your project, each target `TargetName`
        that is to be transpiled must have a corresponding `TargetNameKt`
        target, which is associated with a source folder that contains a
        skip/skip.yml configuration file.


        """

        var packageAddition = ""
        var scaffoldCommands = ""

        for target in sourceTargets {
            let targetName = target.name
            let targetDir = target.directory

            if targetName.hasSuffix("Kt") {
                Diagnostics.remark("ignoring Kt target \(target.name)")
                continue
            }

            if target.kind == .test {
                packageAddition += """
                package.targets += [
                    .testTarget(name: "\(targetName)TestsKt", dependencies: [
                        "\(targetName)Kt",
                        .product(name: "SkipUnit", package: "skiphub"),
                        .product(name: "SkipUnitKt", package: "skiphub"),
                    ],
                                resources: [.copy("Skip")],
                                plugins: [.plugin(name: "transpile", package: "skip")])
                ]


                """
            } else {

                packageAddition += """

                package.products += [
                    .library(name: "\(targetName)Kt", targets: ["\(targetName)Kt"])
                ]

                package.targets += [
                    .target(name: "\(targetName)Kt", dependencies: [
                        "\(targetName)",
                        .product(name: "SkipFoundationKt", package: "skiphub"),

                """

                if options.contains(.scaffold) {
                    // create the folder and skip config file
                }

                for targetDep in target.dependencies {
                    switch targetDep {
                    case .target(let target):
                        contents += """
                        .target(name: "\(target.name)Kt"),

                        """
                    case .product(let product):
                        contents += """
                        .product(name: "\(product.name)Kt", package: "\(product.id)"),

                        """
                    @unknown default:
                        break
                    }
                }

                packageAddition += """
                    ],
                            resources: [.copy("Skip")],
                            plugins: [.plugin(name: "transpile", package: "skip")])
                ]


                """

            }


            // add advice on how to create the targets manually
            let dirname = target.directory.removingLastComponent().lastComponent + "/" + target.directory.lastComponent
            scaffoldCommands += """
            mkdir -p \(dirname)Kt/skip/ && touch \(dirname)Kt/skip/skip.yml

            """

            if options.contains(.scaffold) {
                // create the directory and test case stub
                let targetDirKt = targetDir.string + "Kt/Skip"
                Diagnostics.remark("creating target folder: \(targetDirKt)")
                try FileManager.default.createDirectory(atPath: targetDirKt, withIntermediateDirectories: true)

                let skipConfig = targetDirKt + "/skip.yml"
                if !FileManager.default.fileExists(atPath: skipConfig) {
                    try """
                    # Skip configuration file for \(target.name)

                    """.write(toFile: skipConfig, atomically: true, encoding: .utf8)
                }

                // include a sample Kotlin file as an extension point for the user
                if target.kind != .test {
                    let kotlinSource = targetDirKt + "/\(target.name).kt"
                    if !FileManager.default.fileExists(atPath: kotlinSource) {
                        try """
                        // Kotlin included in this file will be included in the transpiled package for \(target.name)
                        // This can be used to provide support shims for Android equivalent files

                        """.write(toFile: kotlinSource, atomically: true, encoding: .utf8)
                    }
                }
            }

        }

        // if we do not create the scaffold directly, insert advice on how to create it manually
        do { // if !options.contains(.scaffold) {
            contents += """

            The new targets can be added by appending the following block to
            the bottom of the project's `Package.swift` file:

            ```
            // MARK: Skip Kotlin Peer Targets

            \(packageAddition)

            """


            contents += """

            The files needed for these targets may need ti be created by running
            the following shell commands from the project root folder:

            ```
            \(scaffoldCommands)
            ```

            """
        }


        let outputFolder = context.package.directory.appending(subpath: "Skip")
        try FileManager.default.createDirectory(atPath: outputFolder.string, withIntermediateDirectories: true)

        let outputPath = outputFolder.appending(subpath: "README.md")
        Diagnostics.remark("saving to \(outputPath.string)")
        try contents.write(toFile: outputPath.string, atomically: true, encoding: .utf8)
    }
}
