// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation
import Darwin

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
public protocol SkipParsableCommand : AsyncParsableCommand {
    var outputOptions: OutputOptions { get set }

}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
extension AsyncParsableCommand {
    /// Run the transpiler on the given arguments.
    public static func run(_ arguments: [String], out: WritableByteStream? = nil, err: WritableByteStream? = nil) async throws {
        var cmd: ParsableCommand = try parseAsRoot(arguments)
        if var cmd = cmd as? any SkipParsableCommand {
            if let outputFile = cmd.outputOptions.output {
                let path = URL(fileURLWithPath: outputFile)
                cmd.outputOptions.streams.out = try LocalFileOutputByteStream(path)
            } else if let out = out {
                cmd.outputOptions.streams.out = out
            }
            if let err = err {
                cmd.outputOptions.streams.err = err
            }
            try await cmd.run()
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
            CreateCommand.self,
            InitCommand.self,
            DoctorCommand.self,
            UpdateCommand.self,
            GradleCommand.self,
            //CheckCommand.self,
            //RunCommand.self,
            //TestCommand.self,
            //AssembleCommand.self,
            //UploadCommand.self,
        ]
    )

    public init() {
    }
}

// MARK: VersionCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct VersionCommand: SkipParsableCommand {
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

// MARK: UpdateCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct UpdateCommand: SkipParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update to the latest Skip version using Homebrew",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    func run() async throws {
        outputOptions.write("Checking for skip updates")
        try await outputOptions.run("Updating Homebew", ["brew", "update"])
        let upgradeOutput = try await outputOptions.run("Updating Skip", ["brew", "upgrade", "skip"])
        outputOptions.write(upgradeOutput.out)
        outputOptions.write(upgradeOutput.err)
    }
}


// MARK: DoctorCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct DoctorCommand: SkipParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Evaluate and diagnose Skip development environmental",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    func run() async throws {
        outputOptions.write("Skip Doctor")

        let v = outputOptions.verbose

        func run(_ title: String, _ args: [String]) async throws -> String {
            let (out, err) = try await outputOptions.run(title, flush: false, args)

            return out.trimmingCharacters(in: .newlines) + err.trimmingCharacters(in: .newlines)
        }

        let skip = try? await run("Checking Skip", ["skip", "version"])
        outputOptions.write(": " + ((try? skip?.extract(pattern: "Skip version ([0-9.]+)")) ?? "unknown"))
        if let output = skip, v { outputOptions.write(output) }

        let swift = try? await run("Checking Swift", ["swift", "-version"])
        outputOptions.write(": " + ((try? swift?.extract(pattern: "Swift version ([0-9.]+)")) ?? "unknown"))
        if let output = swift, v { outputOptions.write(output) }

        let xcode = try? await run("Checking Xcode", ["xcodebuild", "-version"])
        outputOptions.write(": " + ((try? xcode?.extract(pattern: "Xcode ([0-9.]+)")) ?? "unknown"))
        if let output = xcode, v { outputOptions.write(output) }

        let gradle = try? await run("Checking Gradle", ["gradle", "-version"])
        outputOptions.write(": " + ((try? gradle?.extract(pattern: "Gradle ([0-9.]+)")) ?? "unknown"))
        if let output = gradle, v { outputOptions.write(output) }

        let java = try? await run("Checking Java", ["java", "-version"])
        outputOptions.write(": " + ((try? java?.extract(pattern: "version \"([0-9.]+)\"")) ?? "unknown"))
        if let output = java, v { outputOptions.write(output) }

        let studio = try? await run("Checking Android Studio", ["/usr/libexec/PlistBuddy", "-c", "Print CFBundleShortVersionString", "/Applications/Android Studio.app/Contents/Info.plist"])
        outputOptions.write(": " + ((try? studio?.extract(pattern: "([0-9.]+)")) ?? "unknown"))
        if let output = studio, v { outputOptions.write(output) }

        let latestVersion: String? = try await outputOptions.monitor("Skip Updates") {
            try await fetchLatestRelease(from: URL(string: "https://source.skip.tools/skip/releases.atom")!)
        }
        outputOptions.write(": " + ((try? latestVersion?.extract(pattern: "([0-9.]+)")) ?? "unknown"))

        if let latestVersion = latestVersion, latestVersion != skipVersion {
            outputOptions.write("A new version is Skip (\(latestVersion)) is available to update with: skip update")
        } else {
            outputOptions.write("Skip (\(skipVersion)) checks complete")
        }
    }
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
struct CreateCommand: SkipParsableCommand {
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

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Run the project build"))
    var build: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Run the project tests"))
    var test: Bool = false

    @Argument(help: ArgumentHelp("Project folder name"))
    var projectName: String

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

        if build == true {
            try await outputOptions.run("Building project \(projectName) for package \(packageJSON.name)", [toolOptions.swift, "build", "-c", createOptions.configuration, "--package-path", projectFolderURL.path])
        }

        if test == true {
            try await outputOptions.run("Testing project \(projectName)", [toolOptions.swift, "test", "-j", "1", "-c", createOptions.configuration, "--package-path", projectFolderURL.path])
        }

        outputOptions.write("Created project \(projectName) from template \(createOptions.template) in \(projectFolder)")
    }
}

// MARK: InitCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct InitCommand: SkipParsableCommand {
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

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Run the project build"))
    var build: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Run the project tests"))
    var test: Bool = false

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

        if build == true {
            try await outputOptions.run("Building project \(projectName) for package \(packageJSON.name)", [toolOptions.swift, "build", "-c", createOptions.configuration, "--package-path", projectFolderURL.path])
        }

        if test == true {
            try await outputOptions.run("Testing project \(projectName)", [toolOptions.swift, "test", "-c", createOptions.configuration, "--package-path", projectFolderURL.path])
        }

        outputOptions.write("Created library \(projectName) in \(projectFolder)")
    }
}

// MARK: GradleCommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct GradleCommand: SkipParsableCommand, GradleHarness {
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

struct CreateOptions: ParsableArguments {
    /// TODO: dynamic loading of template data
    static let templates = [
        ProjectTemplate(id: "skipapp", url: URL(string: "https://github.com/skiptools/skipapp/releases/latest/download/App-Source.zip")!, localizedTitle: [
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
