import Foundation
import ArgumentParser
import SkipSyntax
import TSCBasic
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct LibInitCommand: MessageCommand, CreateOptionsCommand, ToolOptionsCommand, BuildOptionsCommand, StreamingCommand {
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

    func performCommand(with out: MessageQueue) async throws {
        await out.yield(MessageBlock(status: nil, "Initializing Skip library \(self.projectName)"))

        let dir = self.createOptions.dir ?? "."

        let projectURL = try await initSkipLibrary(projectName: self.projectName, moduleNames: moduleNames, resourceFolder: createOptions.resourcePath, dir: dir, configuration: createOptions.configuration, build: buildOptions.build, test: buildOptions.test, with: out)
        await showFileTree(in: try projectURL.absolutePath, with: out)
        await out.yield(MessageBlock(status: .pass, "Created module \(moduleNames.joined(separator: ", ")) in \(dir)"))
    }
}

extension ToolOptionsCommand {
    func initSkipLibrary(projectName: String, moduleNames: [String], resourceFolder: String?, dir outputFolder: String, configuration: String, build: Bool, test: Bool, with out: MessageQueue) async throws -> URL {
        var isDir: Foundation.ObjCBool = false
        if !FileManager.default.fileExists(atPath: outputFolder, isDirectory: &isDir) {
            throw InitError(errorDescription: "Specified output folder does not exist: \(outputFolder)")
        }
        if isDir.boolValue == false {
            throw InitError(errorDescription: "Specified output folder is not a directory: \(outputFolder)")
        }

        let projectFolder = outputFolder + "/" + projectName
        if FileManager.default.fileExists(atPath: projectFolder) {
            throw InitError(errorDescription: "Specified project path already exists: \(projectFolder)")
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
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "0.0.0"),
            ]
        """

        var products = """
            products: [

        """

        var targets = """
            targets: [

        """

        for moduleName in moduleNames {
            //let moduleKtName = moduleName + "Kt"

            let sourceDir = sourcesURL.appending(path: moduleName)
            try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: false)

            let sourceKtDir = sourceDir // sourcesURL.appending(path: moduleKtName)
            //try FileManager.default.createDirectory(at: sourceKtDir, withIntermediateDirectories: false)

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

            let testDir = testsURL.appending(path: moduleName + "Tests")
            try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: false)

            let testKtDir = testDir // testsURL.appending(path: moduleKtName + "Tests")
            //try FileManager.default.createDirectory(at: testKtDir, withIntermediateDirectories: false)

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

            let testKtSwiftFile = testKtDir.appending(path: "XCSkipTests.swift")
            try """
            #if os(macOS) // Skip transpiled tests only run on macOS targets
            import SkipTest

            /// This test case will run the transpiled tests for the Skip module.
            @available(macOS 13, *)
            final class XCSkipTests: XCTestCase, XCGradleHarness {
                public func testSkipModule() async throws {
                    try await runGradleTests(device: .none) // set device ID to run in Android emulator vs. robolectric
                }
            }
            #endif
            """.write(to: testKtSwiftFile, atomically: true, encoding: .utf8)

            let testSkipYamlFile = testSkipDir.appending(path: "skip.yml")
            try """
            # Configuration file for https://skip.tools project

            """.write(to: testSkipYamlFile, atomically: true, encoding: .utf8)

            products += """
                    .library(name: "\(moduleName)", targets: ["\(moduleName)"]),

            """
            targets += """
                    .target(name: "\(moduleName)", dependencies: [.product(name: "SkipFoundation", package: "skip-foundation", condition: .when(platforms: [.macOS]))], plugins: [.plugin(name: "skipstone", package: "skip")]),
                    .testTarget(name: "\(moduleName)Tests", dependencies: ["\(moduleName)", .product(name: "SkipTest", package: "skip", condition: .when(platforms: [.macOS]))], plugins: [.plugin(name: "skipstone", package: "skip")]),

            """
        }

        products += """
            ]
        """
        targets += """
            ]
        """

        let packageSource = """
        // swift-tools-version: 5.9
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

        //        let packageJSONString = try await outputOptions.exec("Checking project \(projectName)", [toolOptions.swift, "package", "dump-package", "--package-path", projectFolderURL.path], resultHandler: { result in
        //            guard let stdout = try result?.get().out else { return nil }
        //            return try JSONDecoder().decode(PackageManifest.self, from: Data(stdout.utf8))
        //        })

        let packageJSONString = try await run(with: out, "Checking project \(projectName)", ["swift", "package", "dump-package", "--package-path", projectFolderURL.path]).get().stdout

        let packageJSON = try JSONDecoder().decode(PackageManifest.self, from: Data(packageJSONString.utf8))
        _ = packageJSON

        if build == true {
            await run(with: out, "Building \(projectName)", ["swift", "build", "-v", "-c", configuration, "--package-path", projectFolderURL.path])
        }

        if test == true {
            try await runSkipTests(in: projectFolderURL, configuration: configuration, swift: true, kotlin: true, with: out)
        }

        return projectFolderURL
    }
}

struct InitError : LocalizedError {
    var errorDescription: String?
}
