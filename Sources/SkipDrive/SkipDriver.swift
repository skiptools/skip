// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation
import Darwin

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
public protocol SkipCommand : AsyncParsableCommand {
    var outputOptions: OutputOptions { get set }

}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
extension AsyncParsableCommand {
    /// Run the transpiler on the given arguments.
    public static func run(_ arguments: [String], out: WritableByteStream? = nil, err: WritableByteStream? = nil) async throws {
        var cmd: ParsableCommand = try parseAsRoot(arguments)
        if let cmd = cmd as? any SkipCommand {
            var skipCommand = try cmd.setup(out: out, err: err)
            try await skipCommand.run()
        } else if var cmd = cmd as? AsyncParsableCommand {
            try await cmd.run()
        } else {
            try cmd.run()
        }
    }
}

/// The command that is run by "SkipRunner" (aka "skipstone")
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
public struct SkipDriver: AsyncParsableCommand {
    public static var configuration = CommandConfiguration(
        commandName: "skip",
        abstract: "Skip \(skipVersion)",
        shouldDisplay: true,
        subcommands: [
            VersionCommand.self,
            DoctorCommand.self,
            SelftestCommand.self,

            CreateCommand.self,
            InitCommand.self,

            UpgradeCommand.self,
            GradleCommand.self,

            TestCommand.self,

            WelcomeCommand.self,
            HostIDCommand.self,

            //CheckCommand.self,
            //RunCommand.self,
            //AssembleCommand.self,
            //UploadCommand.self,
        ]
    )

    public init() {
    }
}

extension SkipCommand {
    func setup(out: WritableByteStream? = nil, err: WritableByteStream? = nil) throws -> Self {
        if let outputFile = outputOptions.output {
            let path = URL(fileURLWithPath: outputFile)
            outputOptions.streams.out = try LocalFileOutputByteStream(path)
        } else if let out = out {
            outputOptions.streams.out = out
        }
        if let err = err {
            outputOptions.streams.err = err
        }

        // setup local skip config folder if it doesn't exist
        try? FileManager.default.createDirectory(atPath: home(".skiptools"), withIntermediateDirectories: true)

        return self
    }
}

/// The path to a file/folder in a user's home directory
private func home(_ file: String) -> String {
    ("~/\(file)" as NSString).expandingTildeInPath
}

// MARK: VersionCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct VersionCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Print the Skip version",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    public var outputOptions: OutputOptions

    func run() async throws {
        outputOptions.write("Skip version \(skipVersion)")
    }
}

// MARK: UpgradeCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct UpgradeCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "upgrade",
        abstract: "Upgrade to the latest Skip version using Homebrew",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    func run() async throws {
        if try await checkSkipUpdates() == skipVersion {
            outputOptions.write("Skip \(skipVersion) is up to date.")
            return
        }

        try await outputOptions.run("Updating Homebew", ["brew", "update"])
        let upgradeOutput = try await outputOptions.run("Updating Skip", ["brew", "upgrade", "skip"])
        outputOptions.write(upgradeOutput.out)
        outputOptions.write(upgradeOutput.err)
    }
}

// MARK: WelcomeCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct WelcomeCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "welcome",
        abstract: "Show the skip welcome message",
        shouldDisplay: false)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    func run() async throws {
        outputOptions.write("""

         ▄▄▄▄▄▄▄ ▄▄▄   ▄ ▄▄▄ ▄▄▄▄▄▄▄
        █       █   █ █ █   █       █
        █  ▄▄▄▄▄█   █▄█ █   █    ▄  █
        █ █▄▄▄▄▄█      ▄█   █   █▄█ █
        █▄▄▄▄▄  █     █▄█   █    ▄▄▄█
         ▄▄▄▄▄█ █    ▄  █   █   █
        █▄▄▄▄▄▄▄█▄▄▄█ █▄█▄▄▄█▄▄▄█

        Welcome to Skip \(skipVersion)!

        Run "skip doctor" to check system requirements.
        Run "skip selftest" to perform a full system evaluation.

        Visit https://skip.tools for documentation, samples, and FAQs.

        Happy Skipping!
        """)
    }
}

// MARK: SelftestCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct SelftestCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "selftest",
        abstract: "Run a test to ensure Skip is in working order",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    func run() async throws {
        try await runDoctor()

        func selftest() throws -> [String] {
            let tmpdir = NSTemporaryDirectory() + "/" + UUID().uuidString
            try FileManager.default.createDirectory(atPath: tmpdir, withIntermediateDirectories: true)
            return ["skip", "init", "--build", "--test", "-d", tmpdir, "lib-name", "ModuleName"]
        }

        // if we have never run with Gradle before (indicated by the absence of a ~/.gradle folder), then indicate that the first run may take a long time
        if !FileManager.default.fileExists(atPath: home(".gradle")) {
            try await outputOptions.run("Pre-Caching Gradle Dependencies (~1G)", selftest())
        }
        let _ = try await outputOptions.run("Running Skip Self-Test", selftest())
        //outputOptions.write(output.out)
        //outputOptions.write(output.err)
        outputOptions.write("Skip \(skipVersion) self-test passed!")

    }
}


// MARK: HostIDCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct HostIDCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "hostid",
        abstract: "Display the current host ID",
        shouldDisplay: false)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    func run() async throws {
        guard let hostid = ProcessInfo.processInfo.hostIdentifier else {
            throw AppLaunchError(errorDescription: "Could not access Host ID")
        }
        outputOptions.write(hostid)
    }
}

// MARK: DoctorCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct DoctorCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Evaluate and diagnose Skip development environmental",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    func run() async throws {
        outputOptions.write("Skip Doctor")
        try await runDoctor()
        let latestVersion = try await checkSkipUpdates()
        if let latestVersion = latestVersion, latestVersion != skipVersion {
            outputOptions.write("A new version is Skip (\(latestVersion)) is available to update with: skip update")
        } else {
            outputOptions.write("Skip (\(skipVersion)) checks complete")
        }
    }
}

extension SkipCommand {
    /// Runs the `skip doctor` command.
    func runDoctor() async throws {
        func run(_ title: String, _ args: [String]) async throws -> String {
            let (out, err) = try await outputOptions.run(title, flush: false, args)
            return out.trimmingCharacters(in: .newlines) + err.trimmingCharacters(in: .newlines)
        }

        func checkVersion(title: String, cmd: [String], min: Version? = nil, pattern: String) async {
            do {
                let output = try await run(title, cmd)
                if let v = try output.extract(pattern: pattern) {
                    // the ToolSupport `Version` constructor only accepts three-part versions,
                    // so we need to augment versions like "8.3" and "2022.3" with an extra ".0"
                    guard let semver = Version(v) ?? Version(v + ".0") ?? Version(v + ".0.0") else {
                        outputOptions.write(": PARSE ERROR")
                        return
                    }
                    if let min = min, semver < min {
                        outputOptions.write(": \(semver) (NEEDS \(min))")
                    } else {
                        outputOptions.write(": \(semver)")
                    }
                } else {
                    outputOptions.write(": ERROR")
                }
            } catch {
                outputOptions.write(": ERROR: \(error)")
            }
        }

        await checkVersion(title: "Skip version", cmd: ["skip", "version"], min: Version("0.6.4"), pattern: "Skip version ([0-9.]+)")
        await checkVersion(title: "macOS version", cmd: ["sw_vers", "--productVersion"], min: Version("13.5.1"), pattern: "([0-9.]+)")
        await checkVersion(title: "Swift version", cmd: ["swift", "-version"], min: Version("5.9.0"), pattern: "Swift version ([0-9.]+)")
        await checkVersion(title: "Xcode version", cmd: ["xcodebuild", "-version"], min: Version("15.0.0"), pattern: "Xcode ([0-9.]+)")
        await checkVersion(title: "Gradle version", cmd: ["gradle", "-version"], min: Version("8.3.0"), pattern: "Gradle ([0-9.]+)")
        await checkVersion(title: "Java version", cmd: ["java", "-version"], min: Version("17.0.0"), pattern: "version \"([0-9.]+)\"")
        await checkVersion(title: "Homebrew version", cmd: ["brew", "--version"], min: Version("4.1.7"), pattern: "Homebrew ([0-9.]+)")
        await checkVersion(title: "Android Studio version", cmd: ["/usr/libexec/PlistBuddy", "-c", "Print CFBundleShortVersionString", "/Applications/Android Studio.app/Contents/Info.plist"], min: Version("2022.3.0"), pattern: "([0-9.]+)")
    }
}

extension SkipCommand {
    /// Checks the https://source.skip.tools/skip/releases.atom page and returns the semantic version contained in the title of the first entry (i.e., the latest release of Skip)
    func checkSkipUpdates() async throws -> String? {
        let latestVersion: String? = try await outputOptions.monitor("Check Skip Updates") {
            try await fetchLatestRelease(from: URL(string: "https://source.skip.tools/skip/releases.atom")!)
        }
        outputOptions.write(": " + ((try? latestVersion?.extract(pattern: "([0-9.]+)")) ?? "unknown"))
        return latestVersion
    }

    /// Grabs an Atom XML feed of releases and returns the first title.
    private func fetchLatestRelease(from atomURL: URL) async throws -> String? {
        let (data, response) = try await URLSession.shared.data(from: atomURL)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(code) {
            throw AppLaunchError(errorDescription: "Update check from \(atomURL.absoluteString) returned error: \(code)")
        }

        // parse the Atom XML and get the latest version, which is the title of the first entry
        let document = try XMLDocument(data: data)
        return document.rootElement()?.elements(forName: "entry").first?.elements(forName: "title").first?.stringValue
    }
}

extension String {
    func extract(pattern: String) throws -> String? {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: self.utf16.count)
        if let match = regex.firstMatch(in: self, options: [], range: range) {
            let matchRange = match.range(at: 1)
            if let range = Range(matchRange, in: self) {
                return String(self[range])
            }
        }
        return nil
    }
}

// MARK: CreateCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct CreateCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new Skip app project from a template",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Create Options")
    var createOptions: CreateOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @OptionGroup(title: "Build Options")
    var buildOptions: BuildOptions

    @Argument(help: ArgumentHelp("Project folder name"))
    var projectName: String

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Open the new project in Xcode"))
    var open: Bool = false

    func run() async throws {
        outputOptions.write("Creating project \(projectName) from template \(createOptions.template)")

        let outputFolder = createOptions.dir ?? "."
        var isDir: Foundation.ObjCBool = false
        if !FileManager.default.fileExists(atPath: outputFolder, isDirectory: &isDir) {
            throw AppLaunchError(errorDescription: "Specified output folder does not exist: \(outputFolder)")
        }
        if isDir.boolValue == false {
            throw AppLaunchError(errorDescription: "Specified output folder is not a directory: \(outputFolder)")
        }

        let projectFolder = outputFolder + "/" + projectName
        if FileManager.default.fileExists(atPath: projectFolder) {
            throw AppLaunchError(errorDescription: "Specified project path already exists: \(projectFolder)")
        }

        let downloadURL: URL = try await outputOptions.monitor("Downloading template \(createOptions.template)") {
            let downloadURL = try createOptions.projectTemplateURL
            let (url, response) = try await URLSession.shared.download(from: downloadURL)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200..<300).contains(code) {
                throw AppLaunchError(errorDescription: "Download for template URL \(downloadURL.absoluteString) returned error: \(code)")
            }
            return url
        }

        let projectFolderURL = URL(fileURLWithPath: projectFolder, isDirectory: true)

        try await outputOptions.run("Unpacking template \(createOptions.template) for project \(projectName)", ["unzip", downloadURL.path, "-d", projectFolderURL.path])

        let packageJSONString = try await outputOptions.run("Checking project \(projectName)", [toolOptions.swift, "package", "dump-package", "--package-path", projectFolderURL.path]).out

        let packageJSON = try JSONDecoder().decode(PackageManifest.self, from: Data(packageJSONString.utf8))

        if buildOptions.build == true {
            try await outputOptions.run("Building project \(projectName) for package \(packageJSON.name)", [toolOptions.swift, "build", "-c", createOptions.configuration, "--package-path", projectFolderURL.path])
        }

        if buildOptions.test == true {
            try await outputOptions.run("Testing project \(projectName)", [toolOptions.swift, "test", "-j", "1", "-c", createOptions.configuration, "--package-path", projectFolderURL.path])
        }

        let projectPath = projectFolderURL.path + "/" + "App.xcodeproj"
        if !FileManager.default.isReadableFile(atPath: projectPath) {
            outputOptions.write("Warning: path did not exist at: \(projectPath)", error: true, flush: true)
        }

        if open == true {
            try await outputOptions.run("Launching project \(projectPath)", ["open", projectPath])
        }

        outputOptions.write("Created project: \(projectPath)")
    }
}

// MARK: InitCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct InitCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize a new Skip library project",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Create Options")
    var createOptions: CreateOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @OptionGroup(title: "Build Options")
    var buildOptions: BuildOptions

    @Argument(help: ArgumentHelp("Project folder name"))
    var projectName: String

    @Argument(help: ArgumentHelp("The module name(s) to create"))
    var moduleNames: [String]

    func run() async throws {
        outputOptions.write("Initializing Skip library \(projectName)")

        let outputFolder = createOptions.dir ?? "."
        var isDir: Foundation.ObjCBool = false
        if !FileManager.default.fileExists(atPath: outputFolder, isDirectory: &isDir) {
            throw AppLaunchError(errorDescription: "Specified output folder does not exist: \(outputFolder)")
        }
        if isDir.boolValue == false {
            throw AppLaunchError(errorDescription: "Specified output folder is not a directory: \(outputFolder)")
        }

        let projectFolder = outputFolder + "/" + projectName
        if FileManager.default.fileExists(atPath: projectFolder) {
            throw AppLaunchError(errorDescription: "Specified project path already exists: \(projectFolder)")
        }

        let projectFolderURL = URL(fileURLWithPath: projectFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolderURL, withIntermediateDirectories: true)

        let packageURL = projectFolderURL.appending(path: "Package.swift")

        let sourcesURL = projectFolderURL.appending(path: "Sources")
        try FileManager.default.createDirectory(at: sourcesURL, withIntermediateDirectories: false)

        let testsURL = projectFolderURL.appending(path: "Tests")
        try FileManager.default.createDirectory(at: testsURL, withIntermediateDirectories: false)

        let dependencies = """
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "0.0.0"),
                .package(url: "https://source.skip.tools/skip-unit.git", from: "0.0.0"),
                .package(url: "https://source.skip.tools/skip-lib.git", from: "0.0.0"),
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "0.0.0"),
            ]
        """

        var products = """
            products: [

        """

        var targets = """
            // Each pure Swift target "ModuleName"
            // must have a peer target "ModuleNameKt"
            // that contains the Skip/skip.yml configuration
            // and any custom Kotlin.
            targets: [

        """

        for moduleName in moduleNames {
            let moduleKtName = moduleName + "Kt"

            let sourceDir = sourcesURL.appending(path: moduleName)
            try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: false)

            let sourceKtDir = sourcesURL.appending(path: moduleKtName)
            try FileManager.default.createDirectory(at: sourceKtDir, withIntermediateDirectories: false)

            let sourceSkipDir = sourceKtDir.appending(path: "Skip")
            try FileManager.default.createDirectory(at: sourceSkipDir, withIntermediateDirectories: false)

            let sourceSkipYamlFile = sourceSkipDir.appending(path: "skip.yml")
            try """
            # Configuration file for https://skip.tools project

            """.write(to: sourceSkipYamlFile, atomically: true, encoding: .utf8)

            let sourceSwiftFile = sourceDir.appending(path: "\(moduleName).swift")
            try """
            public class \(moduleName)Module {
            }

            """.write(to: sourceSwiftFile, atomically: true, encoding: .utf8)

            let sourceKtSwiftFile = sourceKtDir.appending(path: "\(moduleName)Bundle.swift")
            try """
            import Foundation
            public extension Bundle {
                static let \(moduleName)Bundle = Bundle.module
            }

            """.write(to: sourceKtSwiftFile, atomically: true, encoding: .utf8)

            let testDir = testsURL.appending(path: moduleName + "Tests")
            try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: false)

            let testKtDir = testsURL.appending(path: moduleKtName + "Tests")
            try FileManager.default.createDirectory(at: testKtDir, withIntermediateDirectories: false)

            let testSkipDir = testKtDir.appending(path: "Skip")
            try FileManager.default.createDirectory(at: testSkipDir, withIntermediateDirectories: false)

            let testSwiftFile = testDir.appending(path: "\(moduleName)Tests.swift")

            try """
            import XCTest
            import OSLog
            import Foundation

            let logger: Logger = Logger(subsystem: "\(moduleName)", category: "Tests")

            @available(macOS 13, macCatalyst 16, iOS 16, tvOS 16, watchOS 8, *)
            final class \(moduleName)Tests: XCTestCase {
                func test\(moduleName)() throws {
                    logger.log("running test\(moduleName)")
                    XCTAssertEqual(1 + 2, 3, "basic test")
                }
            }

            """.write(to: testSwiftFile, atomically: true, encoding: .utf8)

            let testKtSwiftFile = testKtDir.appending(path: "\(moduleName)KtTests.swift")
            try """
            import SkipUnit

            /// This test case will run the transpiled tests for the Skip module.
            @available(macOS 13, macCatalyst 16, *)
            final class SkipFoundationKtTests: XCTestCase, XCGradleHarness {
                /// This test case will run the transpiled tests defined in the Swift peer module.
                /// New tests should be added there, not here.
                public func testSkipModule() async throws {
                    try await gradle(actions: ["testDebug"])
                }
            }

            """.write(to: testKtSwiftFile, atomically: true, encoding: .utf8)

            let testSkipYamlFile = testSkipDir.appending(path: "skip.yml")
            try """
            # Configuration file for https://skip.tools project

            """.write(to: testSkipYamlFile, atomically: true, encoding: .utf8)

            products += """
                    .library(name: "\(moduleName)", targets: ["\(moduleName)"]),
                    .library(name: "\(moduleKtName)", targets: ["\(moduleKtName)"]),

            """
            targets += """
                    .target(name: "\(moduleName)", plugins: [.plugin(name: "preflight", package: "skip")]),
                    .testTarget(name: "\(moduleName)Tests", dependencies: ["\(moduleName)"], plugins: [.plugin(name: "preflight", package: "skip")]),

                    .target(name: "\(moduleKtName)", dependencies: [
                        "\(moduleName)",
                        .product(name: "SkipUnitKt", package: "skip-unit"),
                        .product(name: "SkipLibKt", package: "skip-lib"),
                        .product(name: "SkipFoundationKt", package: "skip-foundation"),
                    ], resources: [.process("Skip")], plugins: [.plugin(name: "transpile", package: "skip")]),
                    .testTarget(name: "\(moduleKtName)Tests", dependencies: [
                        "\(moduleKtName)",
                        .product(name: "SkipUnit", package: "skip-unit"),
                    ], resources: [.process("Skip")], plugins: [.plugin(name: "transpile", package: "skip")]),

            """
        }

        products += """
            ]
        """
        targets += """
            ]
        """

        let packageSource = """
        // swift-tools-version: 5.8
        // This is a [Skip](https://skip.tools) package,
        // containing Swift "ModuleName" library targets
        // alongside peer "ModuleNameKt" targets that
        // will use the Skip plugin to transpile the
        // Swift Package, Sources, and Tests into an
        // Android Gradle Project with Kotlin sources and JUnit tests.
        import PackageDescription

        let package = Package(
            name: "\(projectName)",
            defaultLocalization: "en",
            platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)],
        \(products),
        \(dependencies),
        \(targets)
        )
        """

        try packageSource.write(to: packageURL, atomically: true, encoding: .utf8)


        let readmeURL = projectFolderURL.appending(path: "README.md")

        try """
        # \(projectName)

        This is a [Skip](https://skip.tools) Swift/Kotlin library project containing the following modules:

        \(moduleNames.joined(separator: "\n"))

        """.write(to: readmeURL, atomically: true, encoding: .utf8)

        let packageJSONString = try await outputOptions.run("Checking project \(projectName)", [toolOptions.swift, "package", "dump-package", "--package-path", projectFolderURL.path]).out

        let packageJSON = try JSONDecoder().decode(PackageManifest.self, from: Data(packageJSONString.utf8))

        if buildOptions.build == true {
            try await outputOptions.run("Building project \(projectName) for package \(packageJSON.name)", [toolOptions.swift, "build", "-c", createOptions.configuration, "--package-path", projectFolderURL.path])
        }

        if buildOptions.test == true {
            try await outputOptions.run("Testing project \(projectName)", [toolOptions.swift, "test", "-c", createOptions.configuration, "--package-path", projectFolderURL.path])
        }

        outputOptions.write("Created library \(projectName) in \(projectFolder)")
    }
}

// MARK: GradleCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct GradleCommand: SkipCommand, GradleHarness {
    static var configuration = CommandConfiguration(
        commandName: "gradle",
        abstract: "Launch the gradle build tool",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @Option(help: ArgumentHelp("App package name", valueName: "package-name"))
    var package: String

    @Option(help: ArgumentHelp("App module name", valueName: "ModuleName"))
    var module: String

    @Argument(help: ArgumentHelp("The arguments to pass to the gradle command"))
    var gradleArguments: [String]

    func run() async throws {
        try await self.gradleExec(appName: module, packageName: package, arguments: gradleArguments)
    }
}


// MARK: TestCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct TestCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Run parity tests and generate reports",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    // cannot use shared `BuildOptions` since it defaults `test` to false
    //@OptionGroup(title: "Build Options")
    //var buildOptions: BuildOptions

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Run the project tests"))
    var test: Bool = true

    @Option(help: ArgumentHelp("Project folder", valueName: "dir"))
    var project: String = "."

    @Option(help: ArgumentHelp("Path to xunit test report", valueName: "xunit.xml"))
    var xunit: String?

    @Option(help: ArgumentHelp("Path to junit test report", valueName: "folder"))
    var junit: String?

    @Option(help: ArgumentHelp("Maximum table column length", valueName: "n"))
    var maxColumnLength: Int = 25

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(name: [.customShort("c"), .long], help: ArgumentHelp("Configuration debug/release", valueName: "c"))
    var configuration: String = "debug"

    func run() async throws {
        let xunit = xunit ?? ".build/xcunit-\(UUID().uuidString).xml"

        func packageName() async throws -> String {
            let packageJSONString = try await outputOptions.run("Checking project", [toolOptions.swift, "package", "dump-package", "--package-path", project]).out
            let packageJSON = try JSONDecoder().decode(PackageManifest.self, from: Data(packageJSONString.utf8))
            let packageName = packageJSON.name
            return packageName
        }

        if test == true {
            try await outputOptions.run("Testing project", [toolOptions.swift, "test", "--parallel", "-c", configuration, "--enable-code-coverage", "--xunit-output", xunit, "--package-path", project])
        } else if self.xunit == nil {
            // we can only use the generated xunit if we are running the tests
            throw SkipDriveError(errorDescription: "Must either specify --xunit path or run tests with --test")
        }

        // load the xunit results file
        let xunitResults = try GradleDriver.TestSuite.parse(contentsOf: URL(fileURLWithPath: xunit))
        if xunitResults.count == 0 {
            throw SkipDriveError(errorDescription: "No test results found in \(xunit)")
        }


        func testNameComparison(_ t1: GradleDriver.TestCase, _ t2: GradleDriver.TestCase) -> Bool {
            t1.classname < t2.classname || (t1.classname == t2.classname && t1.name < t2.name)
        }

        let xunitCases = xunitResults.flatMap(\.testCases).sorted(by: testNameComparison)

        // <testcase classname="SkipZipKtTests.SkipZipKtTests" name="testSkipModule" time="7.729628">
        let skipModuleTests = xunitCases.filter({ $0.name == "testSkipModule" && $0.classname.split(separator: ".").first?.hasSuffix("KtTests") == true })

        if skipModuleTests.isEmpty {
            throw SkipDriveError(errorDescription: "Could not find Skip test testSkipModule in: \(xunitCases.map(\.name))")
        }

        let skipModules = skipModuleTests.compactMap({ ($0.classname.split(separator: ".").first)?.dropLast("KtTests".count) })

        // XUnit: <testcase name="testDeflateInflate" classname="SkipZipTests.SkipZipTests" time="0.047230875">
        // JUnit: <testcase name="testDeflateInflate$SkipZip_debugUnitTest" classname="skip.zip.SkipZipTests" time="0.024"/>

        // load the junit result folders
        for skipModule in skipModules {
            //outputOptions.write("skipModule: \(skipModule)")

            let junitFolder: URL
            if let junit = junit {
                // TODO: use the skip modules to form the junit path relative to the project folder
                // .build/plugins/outputs/skip-zip/SkipZipKtTests/skip-transpiler/SkipZip/.build/SkipZip/test-results/testDebugUnitTest/TEST-skip.zip.SkipZipTests.xml
                junitFolder = URL(fileURLWithPath: junit, isDirectory: true)
            } else {
                let packageName = try await packageName()
                let testOutput = ".build/plugins/outputs/\(packageName)/\(skipModule)KtTests/skip-transpiler/\(skipModule)/.build/\(skipModule)/test-results/test\(configuration.capitalized)UnitTest/"
                junitFolder = URL(fileURLWithPath: testOutput, isDirectory: true)
            }

            var isDir: Foundation.ObjCBool = false
            if !FileManager.default.fileExists(atPath: junitFolder.path, isDirectory: &isDir) || isDir.boolValue == false {
                throw SkipDriveError(errorDescription: "JUnit test output folder did not exist at: \(junitFolder.path)")
            }

            let testResultFiles = try FileManager.default.contentsOfDirectory(at: junitFolder, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "xml" && $0.lastPathComponent.hasPrefix("TEST-") })
            if testResultFiles.isEmpty {
                throw SkipDriveError(errorDescription: "JUnit test output folder did not contain any results at: \(junitFolder.path)")
            }

            var junitCases: [GradleDriver.TestCase] = []
            for testResultFile in testResultFiles {
                // load the xunit results file
                let junitResults = try GradleDriver.TestSuite.parse(contentsOf: testResultFile)
                if junitResults.count == 0 {
                    throw SkipDriveError(errorDescription: "No test results found in \(testResultFile)")
                }

                junitCases.append(contentsOf: junitResults.flatMap(\.testCases))
            }

            // now we have all the test cases; for each xunit test, check for an equivalent JUnit test
            // note that xunit: classname="SkipZipTests.SkipZipTests" name="testDeflateInflate"
            // maps to junit: classname="skip.zip.SkipZipTests" name="testDeflateInflate$SkipZip_debugUnitTest"
            var matchedCases: [(xunit: GradleDriver.TestCase, junit: GradleDriver.TestCase?)] = []

            func junitModuleCases(for className: String) -> [GradleDriver.TestCase] {
                junitCases.filter({ $0.classname.hasSuffix("." + className) })
            }

            for xunitCase in xunitCases.filter({ $0.classname.hasPrefix(skipModule + "Tests.") }) {
                let testName = xunitCase.name // e.g., testDeflateInflate
                // match xunit classname "SkipZipTests.SkipZipTests" to junit classname "skip.zip.SkipZipTests"
                let className = xunitCase.classname.split(separator: ".").last?.description ?? xunitCase.classname
                let junitModuleCases = junitModuleCases(for: className)

                // in JUnit, test names are sometimes the raw test name, and other times will be something like "testName$ModuleName_debugUnitTest"
                // async tests are prefixed with "run"
                let cases = junitModuleCases.filter({ $0.name == testName || $0.name.hasPrefix(testName + "$") || $0.name.hasPrefix("run" + testName + "$") })
                if cases.count > 1 {
                    throw SkipDriveError(errorDescription: "Multiple conflicting XUnit and JUnit test cases named “\(testName)” in \(skipModule).")
                }

                if cases.count == 0 {
                    // permit missing cases (e.g., ones inside an #if !SKIP block)
                    // throw SkipDriveError(errorDescription: "Could not match XUnit and JUnit test case named “\(testName)” in \(skipModule).")
                }
                matchedCases.append((xunit: xunitCase, junit: cases.first))
            }

            // now output all of the test cases
            var outputColumns: [[String]] = [[], [], [], []]

            func addSeparator() {
                (0..<outputColumns.count).forEach({ outputColumns[$0].append("-") }) // add header dashes
            }

            /// Add a row with the given columns
            func addRow(_ values: [String]) {
                values.enumerated().forEach({ outputColumns[$0.offset].append($0.element) })
            }

            //addSeparator()
            addRow(["Test", "Case", "Swift", "Kotlin"])
            addSeparator()

            struct Stats {
                var passed: Int = 0
                var failed: Int = 0
                var skipped: Int = 0
                var missing: Int = 0

                var total: Int {
                    passed + failed + skipped + missing
                }

                mutating func update(_ test: GradleDriver.TestCase?) {
                    if test?.skipped == true {
                        skipped += 1
                    } else if test?.failures.isEmpty == false {
                        failed += 1
                    } else if test == nil {
                        missing += 1
                    } else {
                        passed += 1
                    }
                }

                var passRate: String {
                    NumberFormatter.localizedString(from: (Double(passed) / Double(total)) as NSNumber, number: .percent)
                }
            }

            var (xunitStats, junitStats) = (Stats(), Stats())

            for (xunit, junit) in matchedCases.sorted(by: { testNameComparison($0.xunit, $1.xunit) }) {
                let testName = xunit.name
                outputColumns[0].append(xunit.classname.split(separator: ".").last?.description ?? "")
                outputColumns[1].append(testName)
                
                xunitStats.update(xunit)
                junitStats.update(junit)

                func desc(_ test: GradleDriver.TestCase?) -> String {
                    guard let test = test else {
                        return "????" // unmatched
                    }
                    let result = (test.skipped == true ? "SKIP" : test.failures.count > 0 ? "FAIL" : "PASS")
                    //result += " (" + ((round(test.time * 1000) / 1000).description) + ")"
                    return result

                }

                outputColumns[2].append(desc(xunit))
                outputColumns[3].append(desc(junit))
            }

            // add summary
            //addSeparator()  // add footer dashes
            addRow(["", "", xunitStats.passRate, junitStats.passRate])
            //addSeparator()  // add footer dashes

            // pad all the columns for nice output
            let lengths = outputColumns.map({ $0.reduce(0, { max($0, $1.count) })})
            for (index, length) in lengths.enumerated() {
                outputColumns[index] = outputColumns[index].map { $0.pad(min(length, maxColumnLength), paddingCharacter: $0 == "-" ? "-" : " ") }
            }

            let rowCount = outputColumns.map({ $0.count }).min() ?? 0
            for row in 0..<rowCount {
                let row = outputColumns.map({ $0[row] })

                // these look nice in the terminal, but they don't generate valid markdown tables
                // header columns are all "-"
                //let sep = Set(row.flatMap({ Array($0) })) == ["-"] ? "-" : " "
                // corners of headers are "+"
                //let term = sep == "-" ? "+" : "|"

                let sep = " "
                let term = "|"

                outputOptions.write("", terminator: term)
                for cell in row {
                    outputOptions.write(sep + cell + sep, terminator: term)
                }
                outputOptions.write("", terminator: "\n")
            }
        }
    }
}

extension String {
    /// Pads the given string to the specified length
    func pad(_ length: Int, paddingCharacter: Character = " ") -> String {
        if self.count == length {
            return self
        } else if self.count < length {
            return self + String(repeating: paddingCharacter, count: length - self.count)
        } else {
            return String(self[..<self.index(self.startIndex, offsetBy: length)])
        }
    }
}

struct ToolOptions: ParsableArguments {
    @Option(help: ArgumentHelp("Xcode command path", valueName: "path"))
    var xcode: String = "/usr/bin/xcodebuild"

    @Option(help: ArgumentHelp("Swift command path", valueName: "path"))
    var swift: String = "/usr/bin/swift"

    // TODO: check processor for intel vs. arm for homebrew location rather than querying file system
    @Option(help: ArgumentHelp("Gradle command path", valueName: "path"))
    var gradle: String = FileManager.default.fileExists(atPath: "/usr/local/bin/gradle") ? "/usr/local/bin/gradle" : "/opt/homebrew/bin/gradle"

    @Option(help: ArgumentHelp("Path to the Android SDK (ANDROID_HOME)", valueName: "path"))
    var androidHome: String?
}

struct BuildOptions: ParsableArguments {
    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Run the project build"))
    var build: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Run the project tests"))
    var test: Bool = false
}

struct CreateOptions: ParsableArguments {
    /// TODO: dynamic loading of template data
    static let templates = [
        ProjectTemplate(id: "skipapp", url: URL(string: "https://github.com/skiptools/skipapp/releases/latest/download/skip-template-source.zip")!, localizedTitle: [
            "en": "Skip Sample App"
        ], localizedDescription: [
            "en": """
                A Skip sample app for iOS and Android.
                """
        ])
    ]

    @Option(help: ArgumentHelp("Application identifier"))
    var id: String = "net.example.MyApp"

    @Option(name: [.customShort("d"), .long], help: ArgumentHelp("Base folder for project creation", valueName: "directory"))
    var dir: String?

    @Option(name: [.customShort("c"), .long], help: ArgumentHelp("Configuration debug/release", valueName: "c"))
    var configuration: String = "debug"

    @Option(name: [.customShort("t"), .long], help: ArgumentHelp("Template name/ID for new project", valueName: "id"))
    var template: String = templates.first!.id

    var projectTemplateURL: URL {
        get throws {
            guard let sample = Self.templates.first(where: { $0.id == template }) else {
                throw SkipDriveError(errorDescription: "Sample named \(template) could not be found")
            }
            return sample.url
        }
    }

}

struct ProjectTemplate : Codable {
    let id: String
    let url: URL
    let localizedTitle: [String: String]
    let localizedDescription: [String: String]
}

/// An incomplete representation of package JSON, to be filled in as needed for the purposes of the tool
/// The output from `swift package dump-package`.
public struct PackageManifest : Hashable, Decodable {
    public var name: String
    //public var toolsVersion: String // can be string or dict
    public var products: [Product]
    public var dependencies: [Dependency]
    //public var targets: [Either<Target>.Or<String>]
    public var platforms: [SupportedPlatform]
    public var cModuleName: String?
    public var cLanguageStandard: String?
    public var cxxLanguageStandard: String?

    public struct Target: Hashable, Decodable {
        public enum TargetType: String, Hashable, Decodable {
            case regular
            case test
            case system
        }

        public var `type`: TargetType
        public var name: String
        public var path: String?
        public var excludedPaths: [String]?
        //public var dependencies: [String]? // dict
        //public var resources: [String]? // dict
        public var settings: [String]?
        public var cModuleName: String?
        // public var providers: [] // apt, brew, etc.
    }


    public struct Product : Hashable, Decodable {
        //public var `type`: ProductType // can be string or dict
        public var name: String
        public var targets: [String]

        public enum ProductType: String, Hashable, Decodable, CaseIterable {
            case library
            case executable
        }
    }

    public struct Dependency : Hashable, Decodable {
        public var name: String?
        public var url: String?
        //public var requirement: Requirement // revision/range/branch/exact
    }

    public struct SupportedPlatform : Hashable, Decodable {
        var platformName: String
        var version: String
    }
}


/// The output from `xcodebuild -showBuildSettings -json -project Project.xcodeproj -scheme SchemeName`
public struct ProjectBuildSettings : Decodable {
    public let target: String
    public let action: String
    public let buildSettings: [String: String]
}


@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
public struct OutputOptions: ParsableArguments {
    @Option(name: [.customShort("o"), .long], help: ArgumentHelp("Send output to the given file (stdout: -)", valueName: "path"))
    var output: String?

    @Flag(name: [.customShort("v"), .long], help: ArgumentHelp("Whether to display verbose messages"))
    var verbose: Bool = false

    @Flag(name: [.customShort("q"), .long], help: ArgumentHelp("Quiet mode: suppress output"))
    var quiet: Bool = false

    /// progress animation sequences
    static let progressAimations = [
        "⠙⠸⢰⣠⣄⡆⠇⠋", // clockwise line
        "⠐⢐⢒⣒⣲⣶⣷⣿⡿⡷⡧⠧⠇⠃⠁⠀⡀⡠⡡⡱⣱⣳⣷⣿⢿⢯⢧⠧⠣⠃⠂⠀⠈⠨⠸⠺⡺⡾⡿⣿⡿⡷⡗⡇⡅⡄⠄⠀⡀⡐⣐⣒⣓⣳⣻⣿⣾⣼⡼⡸⡘⡈⠈⠀", // fade
        "⣀⡠⠤⠔⠒⠊⠉⠑⠒⠢⠤⢄", // crawl up and down, tiny
        "⢇⢣⢱⡸⡜⡎", // vertical wobble up
        "⣾⣽⣻⢿⣿⣷⣯⣟⡿⣿", // alternating rain
        "⣀⣠⣤⣦⣶⣾⣿⡿⠿⠻⠛⠋⠉⠙⠛⠟⠿⢿⣿⣷⣶⣴⣤⣄", // crawl up and down, large
        "⣾⣷⣯⣽⣻⣟⡿⢿⣻⣟⣯⣽", // snaking
        "⠙⠚⠖⠦⢤⣠⣄⡤⠴⠲⠓⠋", // crawl up and down, small
        "⠄⡢⢑⠈⠀⢀⣠⣤⡶⠞⠋⠁⠀⠈⠙⠳⣆⡀⠀⠆⡷⣹⢈⠀⠐⠪⢅⡀⠀", // fireworks
        "⡀⣀⣐⣒⣖⣶⣾⣿⢿⠿⠯⠭⠩⠉⠁⠀", // swirl
        "⠁⠈⠐⠠⢀⡀⠄⠂", // clockwise dot
        "⠁⠋⠞⡴⣠⢀⠀⠈⠙⠻⢷⣦⣄⡀⠀⠉⠛⠲⢤⢀⠀", // falling water
        "⣾⣽⣻⢿⡿⣟⣯⣷", // counter-clockwise
        "⣾⣷⣯⣟⡿⢿⣻⣽", // clockwise
        "⣾⣷⣯⣟⡿⢿⣻⣽⣷⣾⣽⣻⢿⡿⣟⣯⣷", // bouncing clockwise and counter-clockwise
        "⡀⣄⣦⢷⠻⠙⠈⠀⠁⠋⠟⡾⣴⣠⢀⠀", // slide up and down
        "⡇⡎⡜⡸⢸⢱⢣⢇", // vertical wobble down
        "⠁⠐⠄⢀⢈⢂⢠⣀⣁⣐⣄⣌⣆⣤⣥⣴⣼⣶⣷⣿⣾⣶⣦⣤⣠⣀⡀⠀⠀", // snowing and melting
    ]

    /// The characters for the current progress sequence
    private var progressSeq: [Character] {
        Self.progressAimations.first!.map({ $0 })
    }

    /// A transient handler for tool output; this acts as a temporary holder of output streams
    internal var streams: OutputHandler = OutputHandler()

    public init() {
    }

    internal final class OutputHandler : Decodable {
        var out: WritableByteStream = stdoutStream
        var err: WritableByteStream = stderrStream
        var file: LocalFileOutputByteStream? = nil

        func fileStream(for outputPath: String?) -> LocalFileOutputByteStream? {
            guard let outputPath else { return nil }
            if let file = file { return file }
            do {
                let path = URL(fileURLWithPath: outputPath)
                self.file = try LocalFileOutputByteStream(path)
                return self.file
            } catch {
                // should we re-throw? that would make any logging message become throwable
                return nil
            }
        }

        /// The closure that will output a message to standard out
        func write(error: Bool, output: String?, _ message: String, terminator: String = "\n") {
            let stream = (error ? err : fileStream(for: output) ?? out)
            stream.write(message + terminator)
            if !terminator.isEmpty { stream.flush() }
        }

        init() {
        }

        /// Not really decodable; this is just a transient holder of output streams
        convenience init(from decoder: Decoder) throws {
            self.init()
        }
    }

    /// Write the given message to the output streams buffer
    func write(_ value: String, error: Bool = false, terminator: String = "\n", flush: Bool = false) {
        streams.write(error: error, output: output, value, terminator: terminator)
        if flush {
            if error {
                streams.err.flush()
            } else {
                streams.out.flush()
            }
        }
    }

    @discardableResult
    func run(_ message: String, flush: Bool = true, progress: Bool = true, _ args: [String], environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> (out: String, err: String) {
        let (out, err) = try await monitor(message, progress: progress) {
            //try await Process.checkNonZeroExit(arguments: args, environment: environment, loggingHandler: nil)

            let result = try await Process.popen(arguments: args, environment: environment, loggingHandler: nil)
            // Throw if there was a non zero termination.
            guard result.exitStatus == .terminated(code: 0) else {
                throw ProcessResult.Error.nonZeroExit(result)
            }
            let (out, err) = try (result.utf8Output(), result.utf8stderrOutput())
            return (out: out, err: err)
        }

        if flush { // write a final newline (since monitor does not
            write("", flush: true)
        }

        return (out, err)
    }

    static var isTerminal: Bool { isatty(fileno(stdout)) != 0 }

    /// Perform an operation with a given progress animation
    @discardableResult func monitor<T>(_ message: String, progress: Bool = Self.isTerminal, block: () async throws -> T) async throws -> T {
        var progressMonitor: Task<(), Error>? = nil

        @Sendable func clear(_ count: Int) {
            // clear the current line
            write(String(repeating: "\u{8}", count: count), terminator: "", flush: true)
        }

        if !progress {
            write(message)
        } else {
            progressMonitor = Task {
                var lastMessage: String? = nil
                func printMessage(_ char: Character) {
                    if let lastMessage = lastMessage {
                        clear(lastMessage.count)
                    }
                    lastMessage = "[\(char)] \(message)"
                    if let lastMessage = lastMessage {
                        write(lastMessage, terminator: "", flush: true)
                    }
                }

                while true {
                    for char in progressSeq {
                        printMessage(char)
//                        do {
//                            try await Task.sleep(for: .milliseconds(150))
//                        } catch {
//                            break // cancelled
//                        }
                        try Task.checkCancellation()
                        try await Task.sleep(for: .milliseconds(150))
                        try Task.checkCancellation()

                    }
                }
            }
        }

        do {
            let result = try await block()
            progressMonitor?.cancel() // cancel the progress task
            clear(message.count + 4)
            write("[✓] " + message, terminator: "", flush: true)
            return result
        } catch {
            progressMonitor?.cancel() // cancel the progress task
            clear(message.count + 4)
            write("[✗] " + message, flush: true)
            throw error
        }
    }

}

public struct SkipDriveError : LocalizedError {
    public var errorDescription: String?
}
