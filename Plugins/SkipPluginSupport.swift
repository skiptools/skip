// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Affero General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation
import PackagePlugin

enum SkipBuildCommand : Equatable {
    /// Initialize a Skip peer target for the selected Swift target(s)
    case `init`
    /// Synchronize the gradle build output links in Packages/Skip
    case sync
}

/// The options to use when running the plugin command.
struct SkipCommandOptions : OptionSet {
    let rawValue: Int

    public static let `default`: Self = [project, scaffold, preflight, transpile, targets, inplace, link, skiplocal]

    /// Generate the project output structure
    public static let project = Self(rawValue: 1 << 0)

    /// Create the scaffold of folders and files for Kt targets.
    public static let scaffold = Self(rawValue: 1 << 1)

    /// Adds the preflight plugin to each selected target
    public static let preflight = Self(rawValue: 1 << 2)

    /// Adds the transpile plugin to each of the created targets
    public static let transpile = Self(rawValue: 1 << 3)

    /// Add the Kt targets to the Package.swift
    public static let targets = Self(rawValue: 1 << 4)

    /// Add the Package.swift modification directly to the file rather than the README.md
    public static let inplace = Self(rawValue: 1 << 5)

    /// Link the Gradle outputs intpo the Packages/Skip folder
    public static let link = Self(rawValue: 1 << 6)

    /// Add skiplocal directives to the Package.skip
    public static let skiplocal = Self(rawValue: 1 << 7)
}


/// An extension that is shared between multiple plugin targets.
///
/// This file is included in the plugin source folders as a symbolic links.
/// This works around the limitation that SPM plugins cannot depend on a shared library target,
/// and thus is the only way to share code between plugins.
extension CommandPlugin {

    func performBuildCommand(_ command: SkipBuildCommand, _ options: SkipCommandOptions? = nil, context: PluginContext, arguments: [String]) throws {
        let options = options ?? (command == .`init` ? .default : command == .sync ? .link : [])
        Diagnostics.remark("performing build command with options: \(options)")

        var args = ArgumentExtractor(arguments)
        let targetArgs = args.extractOption(named: "target")
        var targets = try context.package.targets(named: targetArgs)

        // when no targets are specified (e.g., when running the CLI `swift package plugin skip-init`), enable all the targets
        if targets.isEmpty {
            targets = context.package.targets
        }

        //let overwrite = args.extractFlag(named: "overwrite") > 0
        let allTargets = targets
            .compactMap { $0 as? SwiftSourceModuleTarget }

        let sourceTargets = allTargets
            .filter { !$0.name.hasSuffix("Kt") && !$0.name.hasSuffix("KtTests") } // ignore any "Kt" targets

        // the marker comment that will be used to delimit the Skip-edited section of the Package.swift
        let packageAdditionMarker = "// MARK: Skip Kotlin Peer Targets"
        var packageAddition = packageAdditionMarker + "\n\n"

        packageAddition += """

        // add the Skip transpiler preflight checks to each of the existing Swift targets
        for target in package.targets {
            target.plugins = (target.plugins ?? []) + [.plugin(name: "preflight", package: "skip")]
        }

        """

        if options.contains(.project) {
            var skipREADME = """
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


            """

            var scaffoldCommands = ""

            // source target ordering seems to be random
            let allSourceTargets = sourceTargets.sorted { $0.name < $1.name }

            for target in allSourceTargets {
                let targetName = target.name

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
                        .testTarget(name: "\(targetName.dropLast("Tests".count))KtTests", dependencies: [

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
                    let targetNameKt = target.kind == .test ? (target.name.dropLast("Tests".count) + "KtTests") : (target.name + "Kt")
                    let targetDirKt = target.directory.removingLastComponent().appending(subpath: targetNameKt)

                    let targetDirKtSkip = targetDirKt.appending(subpath: "Skip")

                    Diagnostics.remark("creating target folder: \(targetDirKtSkip)")
                    try FileManager.default.createDirectory(atPath: targetDirKtSkip.string, withIntermediateDirectories: true)

                    let skipConfig = targetDirKtSkip.appending(subpath: "/skip.yml")
                    if !FileManager.default.fileExists(atPath: skipConfig.string) {
                        try """
                        # Skip configuration file for \(target.name)

                        """.write(toFile: skipConfig.string, atomically: true, encoding: .utf8)
                    }

                    // create a test case stub
                    if target.kind == .test {
                        let testClass = targetNameKt // class name is same as target name
                        let testSource = targetDirKt.appending(subpath: testClass + ".swift")

                        if !FileManager.default.fileExists(atPath: testSource.string) {
                            try """
                            // This is free software: you can redistribute and/or modify it
                            // under the terms of the GNU Lesser General Public License 3.0
                            // as published by the Free Software Foundation https://fsf.org
                            import SkipUnit

                            // This is the entry point for the Gradle test case runner,
                            // which takes Skip's transpiled XCTest -> JUnit tests and
                            // runs them by forking the `gradle` command.

                            // Test results are parsed and mapped back to their equivalent
                            // Swift source code locations and highlighted in the Xcode
                            // Issue Navigator.

                            #if os(Android) || os(macOS) || os(Linux) || targetEnvironment(macCatalyst)

                            /// Do not modify. This is a bridge to the Gradle test case runner.
                            /// New tests should be added to the `\(target.name)` module.
                            final class \(testClass): XCTestCase, XCGradleHarness {
                                /// This test case will run the transpiled tests defined in the Swift peer module.
                                public func testSkipModule() async throws {
                                    try await gradle(actions: ["test"])
                                }
                            }

                            #endif
                            """.write(toFile: testSource.string, atomically: true, encoding: .utf8)
                        }
                    }

                    if target.kind != .test {
                        let moduleClass = target.name + "ModuleKt"
                        let testSource = targetDirKt.appending(subpath: moduleClass + ".swift")

                        if !FileManager.default.fileExists(atPath: testSource.string) {
                            try """
                            // This is free software: you can redistribute and/or modify it
                            // under the terms of the GNU Lesser General Public License 3.0
                            // as published by the Free Software Foundation https://fsf.org
                            import Foundation

                            /// A link to the \(moduleClass) module, which can be used for loading resources.
                            public extension Bundle {
                                static let \(moduleClass) = Bundle.module
                            }
                            """.write(toFile: testSource.string, atomically: true, encoding: .utf8)
                        }
                    }

                    // include a sample Kotlin file as an extension point for the user
                    if target.kind != .test {
                        let kotlinSource = targetDirKtSkip.appending(subpath: target.name + "KtSupport.kt")
                        let packageName = packageName(forModule: targetName)
                        if !FileManager.default.fileExists(atPath: kotlinSource.string) {
                            try """
                            // This is free software: you can redistribute and/or modify it
                            // under the terms of the GNU Lesser General Public License 3.0
                            // as published by the Free Software Foundation https://fsf.org

                            // Any Kotlin included in this file will be included in the transpiled package for \(targetName)
                            // This can be used to provide support for Kotlin-specific functionality.
                            package \(packageName)

                            """.write(toFile: kotlinSource.string, atomically: true, encoding: .utf8)
                        }
                    }
                }

            }

            if options.contains(.skiplocal) {
                packageAddition += """

                // MARK: Internal Skip Development Support

                import class Foundation.ProcessInfo
                // For Skip library development in peer directories, run: SKIPLOCAL=.. xed Package.swift
                if let localPath = ProcessInfo.processInfo.environment["SKIPLOCAL"] {
                    package.platforms = package.platforms ?? [.iOS(.v15), .macOS(.v12), .tvOS(.v15), .watchOS(.v8), .macCatalyst(.v15)]
                    package.dependencies[package.dependencies.count - 2] = .package(path: localPath + "/skip")
                    package.dependencies[package.dependencies.count - 1] = .package(path: localPath + "/skiphub")
                }
                """
            }

            // if we do not create the scaffold directly, insert advice on how to create it manually
            do { // if !options.contains(.scaffold) {
                skipREADME += """

                The new targets can be added by appending the following block to
                the bottom of the project's `Package.swift` file:

                ```
                \(packageAdditionMarker)

                \(packageAddition)

                ```
                """


                skipREADME += """

                The files needed for these targets may need to be created by running
                the following shell commands from the project root folder:

                ```
                \(scaffoldCommands)
                ```

                """
            }

            //let outputPath = outputFolder.appending(subpath: "README.md")
            //Diagnostics.remark("saving to \(outputPath.string)")
            //try skipREADME.write(toFile: outputPath.string, atomically: true, encoding: .utf8)
        }

        let packageDir = context.package.directory
        let packageFile = packageDir.appending(subpath: "Package.swift")
        if options.contains(.inplace) && !packageAddition.isEmpty {
            var encoding: String.Encoding = .utf8
            var packageContents = try String(contentsOfFile: packageFile.string, usedEncoding: &encoding)
            // trim off anything after the skip marker
            packageContents = packageContents.components(separatedBy: packageAdditionMarker).first?.description ?? packageContents

            packageContents += packageAddition
            try packageContents.write(toFile: packageFile.string, atomically: true, encoding: encoding)
            Diagnostics.remark("Updated Package.swift with frameworks")
        }

        /// Returns all the subpaths of the given path
        func subpaths(of path: Path) throws -> [Path] {
            try FileManager.default.contentsOfDirectory(atPath: path.string).map {
                path.appending(subpath: $0)
            }
        }

        if options.contains(.link) {
            let packagesFolder = packageDir.appending(subpath: "Packages")
            let outputFolder = packagesFolder.appending(subpath: "Skip")

            try FileManager.default.createDirectory(atPath: outputFolder.string, withIntermediateDirectories: true)

            func isDirectory(_ path: Path) -> Bool {
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: path.string, isDirectory: &isDirectory)
                return isDirectory.boolValue
            }
            /// Delete all the symbolic links in a given folder
            func clearLinks(in folder: Path) throws {
                // clear out any the links in the Packages/Skip folder for re-creation
                for subpath in try subpaths(of: folder) {
                    if (try? FileManager.default.destinationOfSymbolicLink(atPath: subpath.string)) != nil {
                        Diagnostics.remark("Clearing link \(subpath.string)")
                        try FileManager.default.removeItem(atPath: subpath.string)
                    }
                }
            }

            // clear links in all the output folders, then clear any empty folders that remain
            try clearLinks(in: outputFolder)
            for subpath in try subpaths(of: outputFolder).filter(isDirectory) {
                try clearLinks(in: subpath)
                if try subpaths(of: subpath).isEmpty {
                    try FileManager.default.removeItem(atPath: subpath.string)
                }
            }

            // In the Skip folder, create links to all the output targets that will contain the transpiled Gradle projects
            // e.g. ~/Library/Developer/Xcode/DerivedData/PACKAGE-ID/SourcePackages/plugins/Hello Skip.output/../skip-template.output
            let ext = context.pluginWorkDirectory.extension ?? "output"
            let packageOutput = context.pluginWorkDirectory
                .removingLastComponent()
                .removingLastComponent()
                .appending(subpath: context.package.id + "." + ext)

            var readme = """
            The Packages/Skip folder contains links to the transpilation
            output for each of the following Skip packages defined in
            \((packageFile.string as NSString).abbreviatingWithTildeInPath):


            """

            let settingsPath = "settings.gradle.kts"
            var packageCount = 0

            for target in allTargets {
                var targetName = target.name
                let isTestTarget = targetName.hasSuffix("Tests")
                if isTestTarget {
                    targetName.removeLast("Tests".count)
                }
                if targetName.hasSuffix("Kt") { // handle Kt targets by merging them into the base
                    targetName.removeLast("Kt".count)
                }
                let kotlinTargetName = targetName + "Kt" + (isTestTarget ? "Tests" : "")

                let destPath = packageOutput.appending(subpath: kotlinTargetName).appending(subpath: "skip-transpiler")
                let linkBasePath = outputFolder.appending(subpath: kotlinTargetName)

                if !isDirectory(destPath) {
                    Diagnostics.remark("Not creating link from \(linkBasePath) to \(destPath) (missing destination)")
                    continue
                }
                Diagnostics.remark("Creating link from \(linkBasePath) to \(destPath)")

                readme += """
                \(linkBasePath.stem): \((destPath.string as NSString).abbreviatingWithTildeInPath)
                
                """

                try FileManager.default.createDirectory(atPath: linkBasePath.string, withIntermediateDirectories: true)

                // we link to only two files in the destination: the folder for the project's source, and the settings.gradle.kts file for external editing

                try? FileManager.default.removeItem(atPath: linkBasePath.appending(subpath: settingsPath).string) // clear dest in case it exists
                try FileManager.default.createSymbolicLink(atPath: linkBasePath.appending(subpath: settingsPath).string, withDestinationPath: destPath.appending(subpath: settingsPath).string)

                try? FileManager.default.removeItem(atPath: linkBasePath.appending(subpath: targetName).string) // clear dest in case it exists
                try FileManager.default.createSymbolicLink(atPath: linkBasePath.appending(subpath: targetName).string, withDestinationPath: destPath.appending(subpath: targetName).string)

                packageCount += 1

                // raises: "internalError(\"unimplemented\")"
                // let buildResult = try packageManager.build(.target(targetName), parameters: PackageManager.BuildParameters(configuration: PackageManager.BuildConfiguration.debug, logging: PackageManager.BuildLogVerbosity.verbose))

            }

            readme.append("""

            
            Each of these folders contains links to the transient build result,
            as well as the \(settingsPath) file, for which the File command
            Open in External Editor can be used to launch an IDE or supporting editor
            to build, test, debug, and run the project.

            Note that this Packages/Skip folder should be excluded from source control management.
            It appears in the .gitignore file that is generated from swift package init,
            and so it is likely to be excluded by default.

            These links may need to be re-created using the
            Synchronize Packages/Skip command when the Xcode DerivedData is
            cleaned, the project name changes, or the project is relocated to another
            source folder.
            """)

            try readme.write(toFile: packagesFolder.appending(subpath: "README").string, atomically: true, encoding: .utf8)

            if packageCount == 0 {
                // not an error, because this can happen as a side-effect of the Hello Skip command
                Diagnostics.warning("No links were created. Ensure that the modules have each been alreaduy built.")
            }
        }
    }
}

private func packageName(forModule moduleName: String, trimTests: Bool = true) -> String {
    var lastLower = false
    var packageName = ""
    for c in moduleName {
        let lower = c.lowercased()
        if lower == String(c) {
            lastLower = true
        } else {
            if lastLower == true {
                packageName += "."
            }
            lastLower = false
        }
        packageName += lower
    }

    // the "Tests" module suffix is special: in Swift XXX and XXXTest are different modules (with a @testable import to allow the tests to access internal symbols), but in Kotlin, test cases need to be in the same package in order to be able to access the symbols
    if trimTests && packageName.hasSuffix(".tests") {
        packageName = String(packageName.dropLast(".tests".count))
    }
    if trimTests && packageName.hasSuffix("tests") {
        packageName = String(packageName.dropLast("tests".count))
    }
    return packageName
}
