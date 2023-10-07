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

    @Option(help: ArgumentHelp("Embed the library as an app with the given bundle id"))
    var appid: String? = nil

    @Option(help: ArgumentHelp("Set the initial version to the given value"))
    var version: String? = nil

    @Flag(help: ArgumentHelp("Build the Android .apk file"))
    var assemble: Bool = false

    @Flag(help: ArgumentHelp("Build the iOS .ipa file"))
    var archive: Bool = false

    /// Attempts to parse module names like "skiptools/skip-ui/SkipUI" into a full repo and path
    var modules: [PackageModule] {
        get throws {
            try self.moduleNames.map {
                try PackageModule(parse: $0)
            }
        }
    }

    func performCommand(with out: MessageQueue) async throws {
        await out.yield(MessageBlock(status: nil, "Initializing Skip library \(self.projectName)"))

        let dir = self.createOptions.dir ?? "."

        let createdURL = try await buildSkipProject(projectName: self.projectName, modules: self.modules, resourceFolder: createOptions.resourcePath, dir: dir, configuration: createOptions.configuration, build: buildOptions.build, test: buildOptions.test, tree: self.createOptions.tree, chain: createOptions.chain, appid: self.appid, version: self.version, assemble: assemble, archive: archive, with: out)

        await out.yield(MessageBlock(status: .pass, "Created module \(moduleNames.joined(separator: ", ")) in \(createdURL.path)"))
    }
}

extension ToolOptionsCommand {
    func buildSkipProject(projectName: String, modules: [PackageModule], resourceFolder: String?, dir outputFolder: String, configuration: String, build: Bool, test: Bool, tree: Bool, chain: Bool, appid: String?, version: String?, assemble: Bool, archive: Bool, with out: MessageQueue) async throws -> URL {
        let projectURL = try await initSkipLibrary(projectName: projectName, modules: modules, resourceFolder: resourceFolder, dir: outputFolder, chain: chain, app: appid != nil, with: out)

        
        if tree {
            await showFileTree(in: try projectURL.absolutePath, with: out)
        }

        if build == true || assemble == true {
            await run(with: out, "Resolving dependencies", ["swift", "package", "resolve", "-v", "--package-path", projectURL.path])
            await run(with: out, "Building \(projectName)", ["swift", "build", "-v", "-c", configuration, "--package-path", projectURL.path])

            if assemble == true {
                // TODO: override PRODUCT_NAME/MARKETING_VERSION/PRODUCT_BUNDLE_IDENTIFIER with environment variables
                let env = ProcessInfo.processInfo.environment

                let primaryModuleName = modules.first?.moduleName ?? "App"
                let gradleProjectDir = projectURL.path + "/.build/plugins/outputs/" + projectName + "/" + primaryModuleName + "/skipstone"
                let relativeBuildDir = ".build/" + projectName

                let action = "assemble" + configuration.capitalized // turn "debug" into "Debug" and "release" into "Release"
                await run(with: out, "Assembling \(primaryModuleName).apk", ["gradle", action, "--console=plain", "--info", "--project-dir", gradleProjectDir, "-PbuildDir=" + relativeBuildDir], environment: env)
                    //{ result in (result, nil) }

                // the expected path for the gradle output folder of the assemble action
                let outputsPath = gradleProjectDir + "/" + primaryModuleName  + "/" + relativeBuildDir + "/outputs"

                // for example: skipapp-playground/.build/plugins/outputs/skipapp-playground/Playground/skipstone/Playground/.build/skipapp-playground/outputs/apk/release/Playground-release.apk
                let apkPath = outputsPath + "/apk/" + configuration + "/" + primaryModuleName + "-" + configuration + ".apk"
                let apkURL = URL(fileURLWithPath: apkPath, isDirectory: false)
                await outputOptions.monitor(with: out, "Checking \(apkURL.lastPathComponent)", resultHandler: { result in
                    let fileSize = try? result?.get().resourceValues(forKeys: [.fileSizeKey]).fileSize
                    return (result, MessageBlock(status: result?.messageStatusAny, "Assembled \(apkURL.lastPathComponent) \(ByteCountFormatter.string(fromByteCount: Int64(fileSize ?? 0), countStyle: .file))"))
                }) { loggingHandler in
                    return apkURL
                }
            }
        }

        if test == true {
            try await runSkipTests(in: projectURL, configuration: configuration, swift: true, kotlin: true, with: out)
        }

        return projectURL
    }

    func initSkipLibrary(projectName: String, modules: [PackageModule], resourceFolder: String?, dir outputFolder: String, chain: Bool, app: Bool, with out: MessageQueue) async throws -> URL {
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

        let sourcesURL = try projectFolderURL.mkdir(path: "Sources")
        let testsURL = try projectFolderURL.mkdir(path: "Tests")

        var products = """
            products: [

        """

        var targets = """
            targets: [

        """


        #if DEBUG
        let skipPackageVersion = "0.0.0"
        #else
        let skipPackageVersion = skipVersion
        #endif
        var packageDependencies: [String] = [
            ".package(url: \"https://source.skip.tools/skip.git\", from: \"\(skipPackageVersion)\")"
        ]

        for i in modules.indices {
            let module = modules[i]
            let moduleName = module.moduleName

            // the isAppModule is the initial module in the list when we specify we want to create an app module
            let isAppModule = app && i == modules.startIndex ? true : false

            // the subsequent module
            let nextModule = i < modules.endIndex - 1 ? modules[i+1] : nil
            let nextModuleName = nextModule?.moduleName

            //let moduleKtName = moduleName + "Kt"

            let sourceDir = try sourcesURL.mkdir(path: moduleName)
            let sourceSkipDir = try sourceDir.mkdir(path: "Skip")

            let sourceSkipYamlFile = sourceSkipDir.appending(path: "skip.yml")

            let skipYamlGeneric = """
            # Configuration file for https://skip.tools project
            #
            # Kotlin dependencies and Gradle build options for this module can be configured here
            #build:
            #  contents:
            #    - block: 'dependencies'
            #      contents:
            #        - 'implementation("androidx.compose.runtime:runtime")'

            """

            let skipYamlApp = """
            # Configuration file for https://skip.tools project
            #
            # This skip.yml file is associated with an Android App project,
            # and buiding it will create an installable .apk file.
            #
            # The app's metadata is derived from the top-level
            # App.xcconfig file, which in turn are used to generate both the
            # AndroidManifest.xml (for the Android apk) and the
            # Info.plist (for the iOS ipa).
            build:
              contents:
                - block: 'plugins'
                  contents:
                    - 'id("com.android.application") version "8.1.0"'
                  remove:
                    - 'id("com.android.library") version "8.1.0"'
                - block: 'android'
                  contents:
                    - 'namespace = System.getenv("PRODUCT_BUNDLE_IDENTIFIER") ?: "app.ui"'
                    - block: 'defaultConfig'
                      contents:
                        # transfer App.xcconfig configuration over to the Android metadata
                        - 'applicationId = System.getenv("PRODUCT_BUNDLE_IDENTIFIER") ?: "app.ui"'
                        - 'versionCode = System.getenv("CURRENT_PROJECT_VERSION")?.toInt() ?: 1'
                        - 'versionName = System.getenv("MARKETING_VERSION") ?: "0.0.0"'
                        - 'manifestPlaceholders["PRODUCT_NAME"] = System.getenv("PRODUCT_NAME") ?: "Skip App"'
                        - 'manifestPlaceholders["PRODUCT_BUNDLE_IDENTIFIER"] = System.getenv("PRODUCT_BUNDLE_IDENTIFIER") ?: "app.ui"'
                    - block: 'buildFeatures'
                      contents:
                        - 'buildConfig = true'
                    - block: 'buildTypes'
                      contents:
                        - block: 'release'
                          contents:
                            # by default we sign with the debug key; for publishing to an app store, the developer key will need to be supplied
                            - 'signingConfig = signingConfigs.getByName("debug")'
                            # enabling minification reduces compose dependency classe size ~85%
                            - 'isMinifyEnabled = true'
                            - 'proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")'
            """

            try (isAppModule ? skipYamlApp : skipYamlGeneric).write(to: sourceSkipYamlFile, atomically: true, encoding: .utf8)

            let sourceSwiftFile = sourceDir.appending(path: "\(moduleName).swift")
            try """
            public class \(moduleName)Module {
            }

            """.write(to: sourceSwiftFile, atomically: true, encoding: .utf8)

            let testDir = try testsURL.mkdir(path: moduleName + "Tests")

            let testSkipDir = try testDir.mkdir(path: "Skip")

            let testSwiftFile = testDir.appending(path: "\(moduleName)Tests.swift")

            try """
            import XCTest
            import OSLog
            import Foundation

            let logger: Logger = Logger(subsystem: "\(moduleName)", category: "Tests")

            @available(macOS 13, *)
            final class \(moduleName)Tests: XCTestCase {
                func test\(moduleName)() throws {
                    logger.log("running test\(moduleName)")
                    XCTAssertEqual(1 + 2, 3, "basic test")
                    \(resourceFolder.flatMap { folderName in
                    """

                    // load the TestData.json file from the \(folderName) folder and decode it into a struct
                    let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "TestData", withExtension: "json"))
                    let testData = try JSONDecoder().decode(TestData.self, from: Data(contentsOf: resourceURL))
                    XCTAssertEqual("\(moduleName)", testData.testModuleName)
                    """
                    } ?? "")
                }
            }
            \(resourceFolder.flatMap { folderName in
            """

            struct TestData : Codable, Hashable {
                var testModuleName: String
            }
            """ } ?? "")
            """.write(to: testSwiftFile, atomically: true, encoding: .utf8)

            let testSkipModuleFile = testDir.appending(path: "XCSkipTests.swift")
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
            """.write(to: testSkipModuleFile, atomically: true, encoding: .utf8)

            // app tests won't build if this is in place
            let skipYamlAppTests = """
            # Configuration file for https://skip.tools project
            build:
              contents:
                - block: 'plugins'
                  remove:
                    - 'id("com.android.library") version "8.1.0"'
            """


            let testSkipYamlFile = testSkipDir.appending(path: "skip.yml")
            try (isAppModule ? skipYamlAppTests : skipYamlGeneric).write(to: testSkipYamlFile, atomically: true, encoding: .utf8)

            products += """
                    .library(name: "\(moduleName)", targets: ["\(moduleName)"]),

            """

            var resourcesAttribute: String = ""
            if let resourceFolder = resourceFolder, !resourceFolder.isEmpty {
                let sourceResourcesDir = try sourceDir.mkdir(path: resourceFolder)
                let sourceResourcesFile = sourceResourcesDir.appending(path: "Localizable.xcstrings")
                try """
                {
                  "sourceLanguage" : "en",
                  "strings" : {},
                  "version" : "1.0"
                }
                """.write(to: sourceResourcesFile, atomically: true, encoding: .utf8)

                let testResourcesDir = try testDir.mkdir(path: resourceFolder)
                let testResourcesFile = testResourcesDir.appending(path: "TestData.json")
                try """
                {
                  "testModuleName": "\(moduleName)"
                }
                """.write(to: testResourcesFile, atomically: true, encoding: .utf8)

                resourcesAttribute = ", resources: [.process(\"\(resourceFolder)\")]"
            }

            if isAppModule {
                let androidManifestContents = """
                <?xml version="1.0" encoding="utf-8"?>
                <manifest xmlns:android="http://schemas.android.com/apk/res/android">
                    <!-- example permissions for using device location -->
                    <!-- <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/> -->
                    <!-- <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/> -->

                    <!-- permissions needed for using the internet or an embedded WebKit browser -->
                    <uses-permission android:name="android.permission.INTERNET" />
                    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
                    <meta-data android:name="android.webkit.WebView.EnableSafeBrowsing" android:value="false" />

                    <application
                        android:label="${PRODUCT_NAME}"
                        android:name="${PRODUCT_BUNDLE_IDENTIFIER}.AndroidAppMain"
                        android:allowBackup="true">
                        <activity
                            android:name=".MainActivity"
                            android:exported="true"
                            android:theme="@style/Theme.AppCompat.DayNight.NoActionBar"
                            android:windowSoftInputMode="adjustResize">
                            <intent-filter>
                                <action android:name="android.intent.action.MAIN" />
                                <category android:name="android.intent.category.LAUNCHER" />
                            </intent-filter>
                        </activity>
                    </application>
                </manifest>

                """
                let androidManifestFile = sourceSkipDir.appending(path: "AndroidManifest.xml")
                try androidManifestContents.write(to: androidManifestFile, atomically: true, encoding: .utf8)
            }

            var moduleDeps: [String] = []
            if let nextModuleName = nextModuleName, chain == true {
                moduleDeps.append("\"" + nextModuleName + "\"") // the internal module names are just referred to by string
            }

            for modDep in module.dependencies {
                if let repoName = modDep.repositoryName {
                    let depVersion = modDep.repositoryVersion ?? "0.0.0"
                    let packDep = ".package(url: \"https://source.skip.tools/\(repoName).git\", from: \"\(depVersion)\")"
                    if !packageDependencies.contains(packDep) {
                        packageDependencies.append(packDep)
                    }
                    moduleDeps.append(".product(name: \"\(modDep.moduleName)\", package: \"\(repoName)\")")

                }
            }

            let moduleDep = moduleDeps.joined(separator: ", ")

            targets += """
                    .target(name: "\(moduleName)", dependencies: [\(moduleDep)]\(resourcesAttribute), plugins: [.plugin(name: "skipstone", package: "skip")]),
                    .testTarget(name: "\(moduleName)Tests", dependencies: ["\(moduleName)", .product(name: "SkipTest", package: "skip")]\(resourcesAttribute), plugins: [.plugin(name: "skipstone", package: "skip")]),

            """
        }

        products += """
            ]
        """
        targets += """
            ]
        """

        let dependencies = "    dependencies: [\n        " + packageDependencies.joined(separator: ",\n        ") + "\n]"

        let packageSource = """
        // swift-tools-version: 5.9
        // This is a [Skip](https://skip.tools) package,
        // containing Swift "ModuleName" library targets
        // that will use the Skip plugin to transpile the
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

        \(modules.map(\.moduleName).joined(separator: "\n"))

        """.write(to: readmeURL, atomically: true, encoding: .utf8)

        //        let packageJSONString = try await outputOptions.exec("Checking project \(projectName)", [toolOptions.swift, "package", "dump-package", "--package-path", projectFolderURL.path], resultHandler: { result in
        //            guard let stdout = try result?.get().out else { return nil }
        //            return try JSONDecoder().decode(PackageManifest.self, from: Data(stdout.utf8))
        //        })

        let packageJSONString = try await run(with: out, "Checking project \(projectName)", ["swift", "package", "dump-package", "--package-path", projectFolderURL.path]).get().stdout

        let packageJSON = try JSONDecoder().decode(PackageManifest.self, from: Data(packageJSONString.utf8))
        _ = packageJSON

        return projectFolderURL
    }
}

struct PackageModule {
    var moduleName: String
    var organizationName: String? = nil
    var repositoryName: String? = nil
    var repositoryVersion: String? = nil
    var dependencies: [PackageModule] = []

    init(moduleName: String) {
        self.moduleName = moduleName
    }

    init(parse: String) throws {
        let parts = parse.split(separator: ":").map(\.description)
        self.moduleName = parts.first ?? parse
        for dep in parts.dropFirst() {
            // parse PlaygroundModel:skiptools/skip-model/SkipModel:skip-foundation@0.1.0/SkipFoundation
            var depParts = dep.split(separator: "/").map(\.description)
            let moduleName = depParts.last ?? dep // e.g., "SkipFoundation"
            depParts.removeLast()

            var depModule = PackageModule(moduleName: moduleName)
            defer { self.dependencies.append(depModule) }

            if !depParts.isEmpty {
                let orgName: String
                let repoPart: String
                if depParts.count == 1 {
                    orgName = "skiptools"
                    repoPart = depParts[0]
                } else {
                    orgName = depParts[0]
                    repoPart = depParts[1]
                }

                let repoName: String
                let repoVersion: String?

                let repoParts = repoPart.split(separator: "@")
                if repoParts.count > 1 { // see if the version is specified
                    repoName = repoParts.first?.description ?? repoPart
                    repoVersion = repoParts.last?.description
                } else { // no version specified
                    repoName = repoPart
                    repoVersion = nil
                }

                depModule.organizationName = orgName
                depModule.repositoryName = repoName
                depModule.repositoryVersion = repoVersion
            }
        }
    }
}


struct InitError : LocalizedError {
    var errorDescription: String?
}

extension URL {
    /// Create the child directory of the given parent
    func mkdir(path: String) throws -> URL {
        let dir = appending(path: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        return dir
    }
}
