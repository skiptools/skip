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
        //let overwrite = args.extractFlag(named: "overwrite") > 0
        let sourceTargets = targets
            .compactMap { $0 as? SwiftSourceModuleTarget }
            .filter { !$0.name.hasSuffix("Kt") } // ignore any "Kt" targets
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

        // source target ordering seems to be random
        let allSourceTargets = sourceTargets.sorted { $0.name < $1.name }

        for target in allSourceTargets {
            let targetName = target.name
            let targetDir = target.directory

            func addTargetDependencies() {
                for targetDep in target.dependencies {
                    switch targetDep {
                    case .target(let target):
                        packageAddition += """
                            .target(name: "\(target.name)Kt"),

                        """
                    case .product(let product):
                        packageAddition += """
                            .product(name: "\(product.name)Kt", package: "\(product.id)"),

                        """
                    @unknown default:
                        break
                    }
                }
            }


            if target.kind == .test {
                packageAddition += """
                package.targets += [
                    .testTarget(name: "\(targetName)Kt", dependencies: [

                """
                addTargetDependencies()
                packageAddition += """
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
                        .target(name: "\(targetName)"),

                """
                addTargetDependencies()
                packageAddition += """
                        .product(name: "SkipFoundationKt", package: "skiphub"),
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
                let targetDirKt = targetDir.string + "Kt"
                let targetDirKtSkip = targetDirKt + "/Skip"
                Diagnostics.remark("creating target folder: \(targetDirKtSkip)")
                try FileManager.default.createDirectory(atPath: targetDirKtSkip, withIntermediateDirectories: true)

                let skipConfig = targetDirKtSkip + "/skip.yml"
                if !FileManager.default.fileExists(atPath: skipConfig) {
                    try """
                    # Skip configuration file for \(target.name)

                    """.write(toFile: skipConfig, atomically: true, encoding: .utf8)
                }

                // create a test case stub
                if target.kind == .test {
                    let testClass = target.name + "Kt"
                    let testSource = targetDirKt + "/\(testClass).swift"

                    if !FileManager.default.fileExists(atPath: testSource) {
                        try """
                        import SkipUnit

                        /// This test case will run the transpiled tests for the \(target.name) module using the `JUnitTestCase.testProjectGradle()` harness.
                        class \(testClass): JUnitTestCase {
                        }

                        """.write(toFile: testSource, atomically: true, encoding: .utf8)
                    }
                }

                if target.kind != .test {
                    let moduleClass = target.name + "ModuleKt"
                    let testSource = targetDirKt + "/\(moduleClass).swift"

                    if !FileManager.default.fileExists(atPath: testSource) {
                        try """
                        import SkipFoundation

                        /// A link to the \(moduleClass) module
                        public extension Bundle {
                            static let \(moduleClass) = Bundle.module
                        }
                        """.write(toFile: testSource, atomically: true, encoding: .utf8)
                    }
                }

                // include a sample Kotlin file as an extension point for the user
                if target.kind != .test {
                    let kotlinSource = targetDirKtSkip + "/\(target.name)KotlinSupport.kt"
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

            ```
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


        // In the Skip folder, create links to all the output targets that will contain the transpiled Pradle projects
        // e.g. ~/Library/Developer/Xcode/DerivedData/PACKAGE-ID/SourcePackages/plugins/Hello Skip.output/../skip-template.output
        let ext = context.pluginWorkDirectory.extension ?? "output"
        let packageOutput = context.pluginWorkDirectory.removingLastComponent().appending(subpath: context.package.id + "." + ext)
        for target in sourceTargets {
            let kotlinTargetName = target.name + "Kt"
            try FileManager.default.createSymbolicLink(
                atPath: outputFolder.appending(subpath: kotlinTargetName).string,
                withDestinationPath: packageOutput.appending(subpath: kotlinTargetName).appending(subpath: "skip-transpiler").string)
        }
    }
}
