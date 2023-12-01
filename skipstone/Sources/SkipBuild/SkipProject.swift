import Foundation
import SkipSyntax

struct MissingProjectFileError : LocalizedError {
    var errorDescription: String?
}

struct AppVerifyError : LocalizedError {
    var errorDescription: String?
}

class FrameworkProjectLayout {
    var packageSwift: URL

    init(root: URL, check: (URL, Bool) throws -> () = checkURLExists) rethrows {
        self.packageSwift = try root.resolve("Package.swift", check: check)
    }

    /// A check that passes every time
    static func noURLChecks(url: URL, isDirectory: Bool) {
    }

    /// A check that verifies that the file URL exists
    static func checkURLExists(url: URL, isDirectory: Bool) throws {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            throw MissingProjectFileError(errorDescription: "Expected path at \(url.path) does not exist")
        }
        if isDir.boolValue != isDirectory {
            throw MissingProjectFileError(errorDescription: "Expected path at \(url.path) should be a \(isDirectory ? "directory" : "file")")
        }
    }


    static func createSkipLibrary(projectName: String, productName: String?, modules: [PackageModule], resourceFolder: String?, dir outputFolder: URL, chain: Bool, gitRepo: Bool, free: Bool, zero skipZeroSupport: Bool, app: Bool, moduleTests: Bool, packageResolved packageResolvedURL: URL?) throws -> URL {
        var isDir: Foundation.ObjCBool = false
        if !FileManager.default.fileExists(atPath: outputFolder.path, isDirectory: &isDir) {
            throw InitError(errorDescription: "Specified output folder does not exist: \(outputFolder)")
        }
        if isDir.boolValue == false {
            throw InitError(errorDescription: "Specified output folder is not a directory: \(outputFolder)")
        }

        let projectFolderURL = outputFolder.appendingPathComponent(projectName, isDirectory: true)
        if FileManager.default.fileExists(atPath: projectFolderURL.path) {
            throw InitError(errorDescription: "Specified project path already exists: \(projectFolderURL.path)")
        }

        try FileManager.default.createDirectory(at: projectFolderURL, withIntermediateDirectories: true)

        let sourcesURL = try projectFolderURL.append(path: "Sources", create: true)

        let sourceHeader = free ? licenseLGPLHeader : ""

        // the part of a target parameter that will only include skip when zero is not set
        //let skipCondition = skipZeroSupport ? ", condition: skip" : "" // we don't use the condition parameter of target because it excludes
        let skipPluginArray = skipZeroSupport ? "skipstone" : #"[.plugin(name: "skipstone", package: "skip")]"#

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
        var packageHeader = """
        // swift-tools-version: 5.9

        """

        if free {
            packageHeader += licenseLGPLHeader
        } else {
            packageHeader += """
            // This is a Skip (https://skip.tools) package,
            // containing a Swift Package Manager project
            // that will use the Skip build plugin to transpile the
            // Swift Package, Sources, and Tests into an
            // Android Gradle Project with Kotlin sources and JUnit tests.
            
            """
        }

        packageHeader += """
        import PackageDescription
        \(skipZeroSupport ? """
        import Foundation

        // Set SKIP_ZERO=1 to build without Skip libraries
        let zero = ProcessInfo.processInfo.environment["SKIP_ZERO"] != nil
        let skipstone = !zero ? [Target.PluginUsage.plugin(name: "skipstone", package: "skip")] : []
        
        """ : "")
        """

        var packageDependencies: [String] = [
            ".package(url: \"https://source.skip.tools/skip.git\", from: \"\(skipPackageVersion)\")"
        ]

        for moduleIndex in modules.indices {
            let module = modules[moduleIndex]
            let moduleName = module.moduleName
            // the isAppModule is the initial module in the list when we specify we want to create an app module
            let isAppModule = app == true && moduleIndex == modules.startIndex
            // the model module is the second in the chain
            let isModelModule = app == true && moduleIndex == modules.startIndex + 1
            // this is the final module in the chain, which will add a dependency on SkipFoundation
            let isFinalModule = moduleIndex == modules.endIndex - 1

            // the subsequent module
            let nextModule = moduleIndex < modules.endIndex - 1 ? modules[moduleIndex+1] : nil
            let nextModuleName = nextModule?.moduleName

            let sourceDir = try sourcesURL.append(path: moduleName, create: true)
            let sourceSkipDir = try sourceDir.append(path: "Skip", create: true)

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
            build:
              contents:

            """

            try (isAppModule ? skipYamlApp : skipYamlGeneric).write(to: sourceSkipYamlFile, atomically: true, encoding: .utf8)

            let sourceSwiftFile = sourceDir.appending(path: "\(moduleName).swift")
            try """
            \(sourceHeader)public class \(moduleName)Module {
            }

            """.write(to: sourceSwiftFile, atomically: true, encoding: .utf8)

            var resourcesAttribute: String = ""
            if let resourceFolder = resourceFolder, !resourceFolder.isEmpty {
                let sourceResourcesDir = try sourceDir.append(path: resourceFolder, create: true)
                let sourceResourcesFile = sourceResourcesDir.appending(path: "Localizable.xcstrings")
                try """
                {
                  "sourceLanguage" : "en",
                  "strings" : {},
                  "version" : "1.0"
                }
                """.write(to: sourceResourcesFile, atomically: true, encoding: .utf8)
            }


            if moduleTests {
                let testsURL = try projectFolderURL.append(path: "Tests", create: true)
                let testDir = try testsURL.append(path: moduleName + "Tests", create: true)
                let testSkipDir = try testDir.append(path: "Skip", create: true)
                let testSwiftFile = testDir.appending(path: "\(moduleName)Tests.swift")

                try """
                \(sourceHeader)import XCTest
                import OSLog
                import Foundation
                @testable import \(moduleName)

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
                \(sourceHeader)#if os(macOS) // Skip transpiled tests only run on macOS targets
                import SkipTest

                /// This test case will run the transpiled tests for the Skip module.
                @available(macOS 13, macCatalyst 16, *)
                final class XCSkipTests: XCTestCase, XCGradleHarness {
                    public func testSkipModule() async throws {
                        // Run the transpiled JUnit tests for the current test module.
                        // These tests will be executed locally using Robolectric.
                        // Connected device or emulator tests can be run by setting the
                        // `ANDROID_SERIAL` environment variable to an `adb devices`
                        // ID in the scheme's Run settings.
                        //
                        // Note that it isn't currently possible to filter the tests to run.
                        try await runGradleTests()
                    }
                }
                #endif
                """.write(to: testSkipModuleFile, atomically: true, encoding: .utf8)

                let skipYamlAppTests = """
                # Configuration file for https://skip.tools project
                #build:
                #  contents:
                """
                let testSkipYamlFile = testSkipDir.appending(path: "skip.yml")
                try (isAppModule ? skipYamlAppTests : skipYamlGeneric).write(to: testSkipYamlFile, atomically: true, encoding: .utf8)

                if let resourceFolder = resourceFolder, !resourceFolder.isEmpty {
                    let testResourcesDir = try testDir.append(path: resourceFolder, create: true)
                    let testResourcesFile = testResourcesDir.appending(path: "TestData.json")
                    try """
                    {
                      "testModuleName": "\(moduleName)"
                    }
                    """.write(to: testResourcesFile, atomically: true, encoding: .utf8)

                    resourcesAttribute = ", resources: [.process(\"\(resourceFolder)\")]"
                }
            }

            // when we are an app module, override the module name with the product name, since we need a distinct name for importing into the project
            if isAppModule {
                products += """
                        .library(name: "\(productName ?? moduleName)", type: .dynamic, targets: ["\(moduleName)"]),

                """
            } else {
                products += """
                        .library(name: "\(moduleName)", targets: ["\(moduleName)"]),

                """
            }

            var moduleDeps: [String] = []
            if let nextModuleName = nextModuleName, chain == true {
                moduleDeps.append("\"" + nextModuleName + "\"") // the internal module names are just referred to by string
            }

            var modDeps = module.dependencies
            if modDeps.isEmpty {
                // add implicit dependency on SkipUI (for app target), SkipModel, and SkipFoundation, based in their position in the chain
                if isAppModule {
                    modDeps.append(PackageModule(repositoryName: "skip-ui", moduleName: "SkipUI"))
                } else if isFinalModule || chain == false {
                    // only add SkipFoundation to the innermost module, or else
                    modDeps.append(PackageModule(repositoryName: "skip-foundation", moduleName: "SkipFoundation"))
                }

                // in addition to a top-level dependency on SkipUI and a bottom-level dependency on SkipFoundation, a secondary module will also have a dependency on SkipModel for observability
                if isModelModule {
                    modDeps.append(PackageModule(repositoryName: "skip-model", moduleName: "SkipModel"))
                }
            }
            var skipModuleDeps: [String] = []
            for modDep in modDeps {
                if let repoName = modDep.repositoryName {
                    let depVersion = modDep.repositoryVersion ?? "0.0.0"
                    let packDep = ".package(url: \"https://source.skip.tools/\(repoName).git\", from: \"\(depVersion)\")"
                    if !packageDependencies.contains(packDep) {
                        packageDependencies.append(packDep)
                    }
                    let dep = ".product(name: \"\(modDep.moduleName)\", package: \"\(repoName)\")"
                    if !skipModuleDeps.contains(dep) {
                        skipModuleDeps.append(dep)
                    }
                }
            }

            // if we are using the SKIP_ZERO conditional, then split up the dependencies and only include the skip dependencies conditionally
            let bracket = { "[" + $0 + "]" }
            let interModuleDep = moduleDeps.joined(separator: ", ")
            let skipModuleDep = skipModuleDeps.joined(separator: ", ")
            let zeroSkipModuleCondition = skipZeroSupport && !skipModuleDeps.isEmpty ? "(zero ? [] : " + bracket(skipModuleDep) + ")" : bracket(skipModuleDep)

            let moduleDep = !interModuleDep.isEmpty && !skipModuleDep.isEmpty
                ? (!skipZeroSupport
                   ? bracket(interModuleDep + ", " + skipModuleDep)
                   : bracket(interModuleDep) + " + " + zeroSkipModuleCondition)
                : !skipModuleDep.isEmpty 
                    ? (skipZeroSupport ? zeroSkipModuleCondition : bracket(skipModuleDep))
                : bracket(interModuleDep)

            targets += """
                    .target(name: "\(moduleName)", dependencies: \(moduleDep)\(resourcesAttribute), plugins: \(skipPluginArray)),

            """

            if moduleTests {
                let skipTestProduct = #".product(name: "SkipTest", package: "skip")"#
                let skipTestDependency = skipZeroSupport
                    ? "] + (zero ? [] : [\(skipTestProduct)])"
                    : ", \(skipTestProduct)]"

                targets += """
                        .testTarget(name: "\(moduleName)Tests", dependencies: ["\(moduleName)"\(skipTestDependency)\(resourcesAttribute), plugins: \(skipPluginArray)),

                """
            }
        }

        products += """
            ]
        """
        targets += """
            ]
        """

        let dependencies = "    dependencies: [\n        " + packageDependencies.joined(separator: ",\n        ") + "\n    ]"

        let packageSource = """
        \(packageHeader)
        let package = Package(
            name: "\(projectName)",
            defaultLocalization: "en",
            platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)],
        \(products),
        \(dependencies),
        \(targets)
        )

        """

        let packageSwiftURL = projectFolderURL.appending(path: "Package.swift")
        try packageSource.write(to: packageSwiftURL, atomically: true, encoding: .utf8)

        // now snapshot the file tree for inclusion in the README
        // let fileTree = try localFileSystem.treeASCIIRepresentation(at: projectFolderURL.absolutePath, hideHiddenFiles: true)

        // if we've specified a Package.resolved source file, simply copy it over in order to re-use the pinned dependencies
        if let packageResolvedURL = packageResolvedURL {
            try FileManager.default.copyItem(at: packageResolvedURL, to: projectFolderURL.appending(path: "Package.resolved"))
        }

        let readmeURL = projectFolderURL.appending(path: "README.md")
        let primaryModuleName = modules.first?.moduleName ?? "Module"

        let libREADME = """
        # \(primaryModuleName)

        This is a \(free ? "free " : "")[Skip](https://skip.tools) Swift/Kotlin library project containing the following modules:

        \(modules.map(\.moduleName).joined(separator: "\n"))

        ## Building

        This project is a \(free ? "free " : "")Swift Package Manager module that uses the
        [Skip](https://skip.tools) plugin to transpile Swift into Kotlin.

        Building the module requires that Skip be installed using 
        [Homebrew](https://brew.sh) with `brew install skiptools/skip/skip`.
        This will also install the necessary build prerequisites:
        Kotlin, Gradle, and the Android build tools.

        ## Testing

        The module can be tested using the standard `swift test` command
        or by running the test target for the macOS destination in Xcode,
        which will run the Swift tests as well as the transpiled
        Kotlin JUnit tests in the Robolectric Android simulation environment.

        Parity testing can be performed with `skip test`,
        which will output a table of the test results for both platforms.

        """


        let appREADME = """
        # \(primaryModuleName)

        This is a \(free ? "free " : "")[Skip](https://skip.tools) dual-platform app project.
        It builds a native app for both iOS and Android.

        ## Building

        This project is both a stand-alone Swift Package Manager module,
        as well as an Xcode project that builds and transpiles the project
        into a Kotlin Gradle project for Android using the Skip plugin.

        Building the module requires that Skip be installed using
        [Homebrew](https://brew.sh) with `brew install skiptools/skip/skip`.

        This will also install the necessary transpiler prerequisites:
        Kotlin, Gradle, and the Android build tools.

        Installation prerequisites can be confirmed by running `skip checkup`.

        ## Testing

        The module can be tested using the standard `swift test` command
        or by running the test target for the macOS destination in Xcode,
        which will run the Swift tests as well as the transpiled
        Kotlin JUnit tests in the Robolectric Android simulation environment.

        Parity testing can be performed with `skip test`,
        which will output a table of the test results for both platforms.

        ## Running

        Xcode and Android Studio must be downloaded and installed in order to
        run the app in the iOS simulator / Android emulator.
        An Android emulator must already be running, which can be launched from 
        Android Studio's Device Manager.

        To run both the Swift and Kotlin apps simultaneously, 
        launch the \(primaryModuleName)App target from Xcode.
        A build phases runs the "Launch Android APK" script that
        will deploy the transpiled app a running Android emulator or connected device.
        Logging output for the iOS app can be viewed in the Xcode console, and in
        Android Studio's logcat tab for the transpiled Kotlin app.

        """

        try (app ? appREADME : libREADME).write(to: readmeURL, atomically: true, encoding: .utf8)

        if free == true {
            try licenseLGPL.write(to: projectFolderURL.appending(path: "LICENSE.LGPL"), atomically: true, encoding: .utf8)
        }

        return projectFolderURL
    }
}

class AppProjectLayout : FrameworkProjectLayout {
    let moduleName: String

    let skipEnv: URL

    let sourcesFolder: URL
    let moduleSourcesFolder: URL
    let moduleSourcesSkipFolder: URL
    let moduleSourcesSkipConfig: URL
    let testsFolder: URL
    let moduleTestsFolder: URL

    let darwinFolder: URL
    let darwinREADME: URL
    let darwinAssetsFolder: URL
    let darwinAssetsContents: URL
    let darwinAccentColorFolder: URL
    let darwinAccentColorContents: URL
    let darwinAppIconFolder: URL
    let darwinAppIconContents: URL
    let darwinEntitlementsPlist: URL
    let darwinProjectConfig: URL
    let darwinProjectFolder: URL
    let darwinProjectContents: URL
    let darwinSourcesFolder: URL
    let darwinMainAppSwift: URL

    let androidFolder: URL
    let androidREADME: URL

    let androidGradleProperties: URL
    let androidGradleWrapperProperties: URL
    let androidGradleSettings: URL
    let androidAppFolder: URL
    let androidAppBuildGradle: URL
    let androidAppProguardRules: URL
    let androidAppSrc: URL
    let androidAppSrcMain: URL
    let androidManifest: URL
    let androidAppSrcMainRes: URL
    let androidAppSrcMainKotlin: URL


    init(moduleName: String, root: URL, check: (URL, Bool) throws -> () = checkURLExists) rethrows {
        self.moduleName = moduleName

        let optional = Self.noURLChecks

        self.skipEnv = try root.resolve("Skip.env", check: check)

        self.sourcesFolder = try root.resolve("Sources/", check: check)
        self.moduleSourcesFolder = try sourcesFolder.resolve(moduleName + "/", check: check)
        self.moduleSourcesSkipFolder = try moduleSourcesFolder.resolve("Skip/", check: check)
        self.moduleSourcesSkipConfig = try moduleSourcesSkipFolder.resolve("skip.yml", check: check)

        self.testsFolder = root.resolve("Tests/", check: optional) // Tests are optional
        self.moduleTestsFolder = testsFolder.resolve(moduleName + "Tests/", check: optional)

        self.darwinFolder = try root.resolve("Darwin/", check: check)
        self.darwinREADME = darwinFolder.resolve("README.md", check: optional)
        self.darwinSourcesFolder = try darwinFolder.resolve("Sources/", check: check)
        self.darwinMainAppSwift = try darwinSourcesFolder.resolve(moduleName + "AppMain.swift", check: check)
        self.darwinProjectConfig = try darwinFolder.resolve(moduleName + ".xcconfig", check: check)
        self.darwinProjectFolder = try darwinFolder.resolve(moduleName + ".xcodeproj/", check: check)
        self.darwinProjectContents = try darwinProjectFolder.resolve("project.pbxproj", check: check)
        self.darwinEntitlementsPlist = try darwinFolder.resolve("Entitlements.plist", check: check)
        self.darwinAssetsFolder = try darwinFolder.resolve("Assets.xcassets/", check: check)
        self.darwinAssetsContents = try darwinAssetsFolder.resolve("Contents.json", check: check)
        self.darwinAccentColorFolder = try darwinAssetsFolder.resolve("AccentColor.colorset/", check: check)
        self.darwinAccentColorContents = try darwinAccentColorFolder.resolve("Contents.json", check: check)
        self.darwinAppIconFolder = try darwinAssetsFolder.resolve("AppIcon.appiconset/", check: check)
        self.darwinAppIconContents = try darwinAppIconFolder.resolve("Contents.json", check: check)

        self.androidFolder = try root.resolve("Android/", check: check)
        self.androidREADME = androidFolder.resolve("README.md", check: optional)
        self.androidGradleProperties = try androidFolder.resolve("gradle.properties", check: check)
        self.androidGradleWrapperProperties = androidFolder.resolve("gradle/wrapper/gradle-wrapper.properties", check: optional)
        self.androidGradleSettings = try androidFolder.resolve("settings.gradle.kts", check: check)
        self.androidAppFolder = try androidFolder.resolve("app/", check: check)
        self.androidAppBuildGradle = try androidAppFolder.resolve("build.gradle.kts", check: check)
        self.androidAppProguardRules = try androidAppFolder.resolve("proguard-rules.pro", check: check)
        self.androidAppSrc = try androidAppFolder.resolve("src/", check: check)
        self.androidAppSrcMain = try androidAppSrc.resolve("main/", check: check)
        self.androidManifest = try androidAppSrcMain.resolve("AndroidManifest.xml", check: check)
        self.androidAppSrcMainRes = androidAppSrcMain.resolve("res/", check: optional)
        //self.androidAppSrcIconMDPI = try androidAppSrcRes.resolve("mipmap-mdpi/", check: check)
        self.androidAppSrcMainKotlin = try androidAppSrcMain.resolve("kotlin/", check: check)

        //self.androidAppSrcMainKotlinModule = try androidAppSrcMainKotlin.resolve("src/", check: check)

        try super.init(root: root, check: check)
    }


    static func createSkipAppProject(projectName: String, productName: String?, modules: [PackageModule], resourceFolder: String?, dir outputFolder: URL, configuration: String, build: Bool, test: Bool, chain: Bool, gitRepo: Bool, free: Bool, zero skipZeroSupport: Bool, appid: String?, iconColor: String?, version: String?, moduleTests: Bool, packageResolved packageResolvedURL: URL? = nil, apk: Bool, ipa: Bool) throws -> (baseURL: URL, project: AppProjectLayout) {

        let sourceHeader = free ? licenseLGPLHeader : ""
        let projectURL = try createSkipLibrary(projectName: projectName, productName: productName, modules: modules, resourceFolder: resourceFolder, dir: outputFolder, chain: chain, gitRepo: gitRepo, free: free, zero: skipZeroSupport, app: appid != nil, moduleTests: moduleTests, packageResolved: packageResolvedURL)

        let projectPath = try projectURL.absolutePath

        let primaryModuleName = modules.first?.moduleName ?? "Module"

        // get the layout of the project for writing files
        let appProject = AppProjectLayout(moduleName: primaryModuleName, root: projectPath.asURL, check: AppProjectLayout.noURLChecks)

        let sourcesFolderName = "Sources"
        let appModuleName = primaryModuleName
        let primaryModuleAppTarget = appModuleName + "App"
        let appModulePackage = KotlinTranslator.packageName(forModule: appModuleName)

        let hasIcon = (iconColor ?? "").count == 6

        guard let appid = appid else { // we have specified that an app should be created
            return (projectURL, appProject)
        }

        try appProject.darwinProjectFolder.createDirectory()

        let primaryModuleAppMainURL = appProject.darwinMainAppSwift
        let appMainSwiftFileName = primaryModuleAppMainURL.lastPathComponent
        let primaryModuleAppMainPath = primaryModuleAppMainURL.deletingLastPathComponent().lastPathComponent + "/" + appMainSwiftFileName
        let primaryModuleSources = sourcesFolderName + "/" + primaryModuleName
        let entitlements_name = appProject.darwinEntitlementsPlist.lastPathComponent
        let entitlements_path = entitlements_name // same folder

        // Sources/PlaygroundApp/Entitlements.plist
        let appEntitlementsContents = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        </dict>
        </plist>

        """

        try appEntitlementsContents.write(to: appProject.darwinEntitlementsPlist.createParentDirectory(), atomically: true, encoding: .utf8)

        // create the top-level Skip.env which is the source or truth for Xcode and Gradle
        let skipEnvContents = """
        // The configuration file for your Skip App (https://skip.tools)
        // Properties specified here are shared between Darwin/\(appModuleName).xcconfig and Android/settings.gradle.kts

        // The name of the project, which must match the SPM project name in Package.swift
        SKIP_PROJECT_NAME = \(projectName)

        // PRODUCT_NAME is the default title of the app
        PRODUCT_NAME = \(appModuleName)

        // PRODUCT_BUNDLE_IDENTIFIER is the unique id for both the iOS and Android app
        PRODUCT_BUNDLE_IDENTIFIER = \(appid)

        // The semantic version of the app
        MARKETING_VERSION = \(version ?? "0.0.1")

        // The build number specifying the internal app version
        CURRENT_PROJECT_VERSION = 1

        // The package name for the Android entry point, referenced by the AndroidManifest.xml
        ANDROID_PACKAGE_NAME = \(appModulePackage)

        """

        try skipEnvContents.write(to: appProject.skipEnv, atomically: true, encoding: .utf8)
        //let skipEnvFileName = appProject.skipEnv.lastPathComponent

        let skipEnvBaseName = "Skip.env"
        let skipEnvFileName = "../\(skipEnvBaseName)"

        // create the top-level ModuleName.xcconfig which is the source or truth for the iOS and Android builds
        let configContents = """
        #include "\(skipEnvFileName)"

        // Set the action that will be executed as part of the Xcode Run Script phase
        // Setting to "launch" will build and run the app in the first open Android emulator or device
        // Setting to "build" will just run gradle build, but will no launc the app
        SKIP_ACTION = launch
        //SKIP_ACTION = build

        ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor

        GENERATE_INFOPLIST_FILE = YES

        // The user-visible name of the app (localizable)
        //INFOPLIST_KEY_CFBundleDisplayName = App Name
        //INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.utilities

        // iOS-specific Info.plist property keys
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation[sdk=iphone*] = YES
        INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents[sdk=iphone*] = YES
        INFOPLIST_KEY_UILaunchScreen_Generation[sdk=iphone*] = YES
        INFOPLIST_KEY_UIStatusBarStyle[sdk=iphone*] = UIStatusBarStyleDefault
        INFOPLIST_KEY_UISupportedInterfaceOrientations[sdk=iphone*] = UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown

        IPHONEOS_DEPLOYMENT_TARGET = 16.0
        MACOSX_DEPLOYMENT_TARGET = 13.0

        // the name of the product module; this can be anything, but cannot conflict with any Swift module names
        PRODUCT_MODULE_NAME = $(PRODUCT_NAME:c99extidentifier)App

        // On-device testing may need to override the bundle ID
        // PRODUCT_BUNDLE_IDENTIFIER[config=Debug][sdk=iphoneos*] = cool.beans.BundleIdentifer

        // Development team ID for on-device testing
        CODE_SIGNING_REQUIRED = NO
        CODE_SIGN_STYLE = Automatic
        CODE_SIGN_ENTITLEMENTS = Entitlements.plist
        //CODE_SIGNING_IDENTITY = -
        //DEVELOPMENT_TEAM =

        """

        try configContents.write(to: appProject.darwinProjectConfig, atomically: true, encoding: .utf8)
        let xcconfigFileName = appProject.darwinProjectConfig.lastPathComponent


        // Darwin/Sources/MODULEAppMain.swift
        let appMainContents = """
        \(sourceHeader)import SwiftUI
        import \(primaryModuleName)

        /// The entry point to the app simply loads the App implementation from SPM module.
        @main struct AppMain: App, \(primaryModuleAppTarget) {
        }

        """
        try appMainContents.write(to: primaryModuleAppMainURL.createParentDirectory(), atomically: true, encoding: .utf8)

        // Sources/Playground/PlaygroundApp.swift
        let appExtContents = """
        \(sourceHeader)import Foundation
        import OSLog
        import SwiftUI

        let logger: Logger = Logger(subsystem: "\(appid)", category: "\(primaryModuleName)")

        /// The Android SDK number we are running against, or `nil` if not running on Android
        let androidSDK = ProcessInfo.processInfo.environment["android.os.Build.VERSION.SDK_INT"].flatMap({ Int($0) })

        /// The shared top-level view for the app, loaded from the platform-specific App delegates below.
        ///
        /// The default implementation merely loads the `ContentView` for the app and logs a message.
        public struct RootView : View {
            public init() {
            }
        
            public var body: some View {
                ContentView()
                    .task {
                        logger.log("Welcome to Skip on \\(androidSDK != nil ? "Android" : "Darwin")!")
                        logger.warning("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
                    }
            }
        }

        #if !SKIP
        public protocol \(primaryModuleAppTarget) : App {
        }

        /// The entry point to the \(primaryModuleName) app.
        /// The concrete implementation is in the \(primaryModuleName)App module.
        public extension \(primaryModuleAppTarget) {
            var body: some Scene {
                WindowGroup {
                    RootView()
                }
            }
        }
        #endif

        """

        let appModuleApplicationStubFileBase = primaryModuleAppTarget + ".swift"
        let appModuleApplicationStubFilePath = primaryModuleSources + "/" + appModuleApplicationStubFileBase

        let appModuleApplicationStubFileURL = projectURL.appending(path: appModuleApplicationStubFilePath)
        try FileManager.default.createDirectory(at: appModuleApplicationStubFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try appExtContents.write(to: appModuleApplicationStubFileURL, atomically: true, encoding: .utf8)


        // Sources/Playground/PlaygroundApp.swift
        let contentViewContents = """
        \(sourceHeader)import SwiftUI

        public struct ContentView: View {
            @AppStorage("setting") var setting = true

            public init() {
            }

            public var body: some View {
                TabView {
                    VStack {
                        Text("Welcome Skipper!")
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                    }
                    .font(.largeTitle)
                    .tabItem { Label("Welcome", systemImage: "heart.fill") }

                    NavigationStack {
                        List {
                            ForEach(1..<1_000) { i in
                                NavigationLink("Home \\(i)", value: i)
                            }
                        }
                        .navigationTitle("Navigation")
                        .navigationDestination(for: Int.self) { i in
                            Text("Destination \\(i)")
                                .font(.title)
                                .navigationTitle("Navigation \\(i)")
                        }
                    }
                    .tabItem { Label("Home", systemImage: "house.fill") }

                    Form {
                        Text("Settings")
                            .font(.largeTitle)
                        Toggle("Option", isOn: $setting)
                    }
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                }
            }
        }

        """

        let contentViewFileBase = "ContentView.swift"
        let contentViewRelativePath = primaryModuleSources + "/" + contentViewFileBase

        let contentViewURL = projectURL.appending(path: contentViewRelativePath)
        try FileManager.default.createDirectory(at: contentViewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contentViewContents.write(to: contentViewURL, atomically: true, encoding: .utf8)


        let Assets_xcassets_URL = try appProject.darwinAssetsFolder.createDirectory()
        let Assets_xcassets_name = appProject.darwinAssetsFolder.lastPathComponent
        let Assets_xcassets_path = Assets_xcassets_name // the path is in the root Darwin/ folder

        let Assets_xcassets_Contents_URL = appProject.darwinAssetsContents
        let Assets_xcassets_Contents = """
        {
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        try Assets_xcassets_Contents.write(to: Assets_xcassets_Contents_URL, atomically: true, encoding: .utf8)

        let Assets_xcassets_AccentColor = try Assets_xcassets_URL.append(path: "AccentColor.colorset", create: true)
        let Assets_xcassets_AccentColor_Contents = """
        {
          "colors" : [
            {
              "idiom" : "universal"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """


        let Assets_xcassets_AccentColor_ContentsURL = Assets_xcassets_AccentColor.appending(path: "Contents.json")
        try Assets_xcassets_AccentColor_Contents.write(to: Assets_xcassets_AccentColor_ContentsURL, atomically: true, encoding: .utf8)

        let Assets_xcassets_AppIcon_Contents: String
        if hasIcon {
            typealias IconInfo = (url: URL, size: Int)

            /// the URL for an iOS icon
            let ios = { appProject.darwinAppIconFolder.appendingPathComponent($0, isDirectory: false) }

            /// the URL for an Android icon
            let android = { appProject.androidAppSrcMainRes.appendingPathComponent($0, isDirectory: false) }

            let iconInfos: [IconInfo] = [
                IconInfo(url: ios("AppIcon-20@2x.png"), size: 40),
                IconInfo(url: ios("AppIcon-20@2x~ipad.png"), size: 40),
                IconInfo(url: ios("AppIcon-20@3x.png"), size: 60),
                IconInfo(url: ios("AppIcon-20~ipad.png"), size: 20),
                IconInfo(url: ios("AppIcon-29.png"), size: 29),
                IconInfo(url: ios("AppIcon-29@2x.png"), size: 58),
                IconInfo(url: ios("AppIcon-29@2x~ipad.png"), size: 58),
                IconInfo(url: ios("AppIcon-29@3x.png"), size: 87),
                IconInfo(url: ios("AppIcon-29~ipad.png"), size: 29),
                IconInfo(url: ios("AppIcon-40@2x.png"), size: 80),
                IconInfo(url: ios("AppIcon-40@2x~ipad.png"), size: 80),
                IconInfo(url: ios("AppIcon-40@3x.png"), size: 120),
                IconInfo(url: ios("AppIcon-40~ipad.png"), size: 40),
                IconInfo(url: ios("AppIcon-83.5@2x~ipad.png"), size: 167),
                IconInfo(url: ios("AppIcon@2x.png"), size: 120),
                IconInfo(url: ios("AppIcon@2x~ipad.png"), size: 152),
                IconInfo(url: ios("AppIcon@3x.png"), size: 180),
                IconInfo(url: ios("AppIcon~ios-marketing.png"), size: 1024),
                IconInfo(url: ios("AppIcon~ipad.png"), size: 76),

                IconInfo(url: android("mipmap-hdpi/ic_launcher.png"), size: 72),
                IconInfo(url: android("mipmap-mdpi/ic_launcher.png"), size: 48),
                IconInfo(url: android("mipmap-xhdpi/ic_launcher.png"), size: 96),
                IconInfo(url: android("mipmap-xxhdpi/ic_launcher.png"), size: 144),
                IconInfo(url: android("mipmap-xxxhdpi/ic_launcher.png"), size: 192),
            ]

            for info in iconInfos {
                if let imgData = createSolidColorPNG(width: info.size, height: info.size, hexString: iconColor) {
                    try imgData.write(to: info.url.createParentDirectory())
                }
            }

            Assets_xcassets_AppIcon_Contents = """
            {
              "images" : [
                {
                  "filename" : "AppIcon-20@2x.png",
                  "idiom" : "iphone",
                  "scale" : "2x",
                  "size" : "20x20"
                },
                {
                  "filename" : "AppIcon-20@3x.png",
                  "idiom" : "iphone",
                  "scale" : "3x",
                  "size" : "20x20"
                },
                {
                  "filename" : "AppIcon-29.png",
                  "idiom" : "iphone",
                  "scale" : "1x",
                  "size" : "29x29"
                },
                {
                  "filename" : "AppIcon-29@2x.png",
                  "idiom" : "iphone",
                  "scale" : "2x",
                  "size" : "29x29"
                },
                {
                  "filename" : "AppIcon-29@3x.png",
                  "idiom" : "iphone",
                  "scale" : "3x",
                  "size" : "29x29"
                },
                {
                  "filename" : "AppIcon-40@2x.png",
                  "idiom" : "iphone",
                  "scale" : "2x",
                  "size" : "40x40"
                },
                {
                  "filename" : "AppIcon-40@3x.png",
                  "idiom" : "iphone",
                  "scale" : "3x",
                  "size" : "40x40"
                },
                {
                  "filename" : "AppIcon@2x.png",
                  "idiom" : "iphone",
                  "scale" : "2x",
                  "size" : "60x60"
                },
                {
                  "filename" : "AppIcon@3x.png",
                  "idiom" : "iphone",
                  "scale" : "3x",
                  "size" : "60x60"
                },
                {
                  "filename" : "AppIcon-20~ipad.png",
                  "idiom" : "ipad",
                  "scale" : "1x",
                  "size" : "20x20"
                },
                {
                  "filename" : "AppIcon-20@2x~ipad.png",
                  "idiom" : "ipad",
                  "scale" : "2x",
                  "size" : "20x20"
                },
                {
                  "filename" : "AppIcon-29~ipad.png",
                  "idiom" : "ipad",
                  "scale" : "1x",
                  "size" : "29x29"
                },
                {
                  "filename" : "AppIcon-29@2x~ipad.png",
                  "idiom" : "ipad",
                  "scale" : "2x",
                  "size" : "29x29"
                },
                {
                  "filename" : "AppIcon-40~ipad.png",
                  "idiom" : "ipad",
                  "scale" : "1x",
                  "size" : "40x40"
                },
                {
                  "filename" : "AppIcon-40@2x~ipad.png",
                  "idiom" : "ipad",
                  "scale" : "2x",
                  "size" : "40x40"
                },
                {
                  "filename" : "AppIcon~ipad.png",
                  "idiom" : "ipad",
                  "scale" : "1x",
                  "size" : "76x76"
                },
                {
                  "filename" : "AppIcon@2x~ipad.png",
                  "idiom" : "ipad",
                  "scale" : "2x",
                  "size" : "76x76"
                },
                {
                  "filename" : "AppIcon-83.5@2x~ipad.png",
                  "idiom" : "ipad",
                  "scale" : "2x",
                  "size" : "83.5x83.5"
                },
                {
                  "filename" : "AppIcon~ios-marketing.png",
                  "idiom" : "ios-marketing",
                  "scale" : "1x",
                  "size" : "1024x1024"
                }
              ],
              "info" : {
                "author" : "xcode",
                "version" : 1
              }
            }

            """

        } else {
            // no icon specified
            Assets_xcassets_AppIcon_Contents = """
            {
              "images" : [
                {
                  "idiom" : "universal",
                  "platform" : "ios",
                  "size" : "1024x1024"
                }
              ],
              "info" : {
                "author" : "xcode",
                "version" : 1
              }
            }

            """
        }

        try Assets_xcassets_AppIcon_Contents.write(to: appProject.darwinAppIconContents.createParentDirectory(), atomically: true, encoding: .utf8)

        func createXcodeProj() -> String {
            // the .xcodeproj file is located in the Darwin/ folder
            let relativeSwiftPackageRoot = ".."

            let skipGradleLaunchScript = """
            if [ "${SKIP_ZERO}" != "" ]; then
                echo "note: skipping skip due to SKIP_ZERO"
                exit 0
            fi
            if [ "${ACTION}" = "install" ]; then
                SKIP_ACTION="build"
            else
                SKIP_ACTION="${SKIP_ACTION:-launch}"
            fi
            PATH=${BUILD_ROOT}/Debug:${BUILD_ROOT}/../../SourcePackages/artifacts/skip/skip/skip.artifactbundle/macos:${PATH}:${HOMEBREW_PREFIX:-/opt/homebrew}/bin
            echo "note: running gradle build with: $(which skip) gradle -p ${PWD}/../Android ${SKIP_ACTION:-launch}${CONFIGURATION:-Debug}"
            skip gradle -p ../Android ${SKIP_ACTION:-launch}${CONFIGURATION:-Debug}

            """
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\"", with: "\\\"")


            return """
    // !$*UTF8*$!
    {
        archiveVersion = 1;
        classes = {
        };
        objectVersion = 56;
        objects = {

    /* Begin PBXBuildFile section */
            49231BAC2AC5BCEF00F98ADF /* \(primaryModuleAppTarget) in Frameworks */ = {isa = PBXBuildFile; productRef = 49231BAB2AC5BCEF00F98ADF /* \(primaryModuleAppTarget) */; };
            49231BAD2AC5BCEF00F98ADF /* \(primaryModuleAppTarget) in Embed Frameworks */ = {isa = PBXBuildFile; productRef = 49231BAB2AC5BCEF00F98ADF /* \(primaryModuleAppTarget) */; settings = {ATTRIBUTES = (CodeSignOnCopy, ); }; };
            499CD43B2AC5B799001AE8D8 /* \(appMainSwiftFileName) in Sources */ = {isa = PBXBuildFile; fileRef = 49F90C2B2A52156200F06D93 /* \(appMainSwiftFileName) */; };
            499CD4402AC5B799001AE8D8 /* \(Assets_xcassets_name) in Resources */ = {isa = PBXBuildFile; fileRef = 49F90C2F2A52156300F06D93 /* \(Assets_xcassets_name) */; };
    /* End PBXBuildFile section */

    /* Begin PBXCopyFilesBuildPhase section */
            499CD44A2AC5B9C6001AE8D8 /* Embed Frameworks */ = {
                isa = PBXCopyFilesBuildPhase;
                buildActionMask = 2147483647;
                dstPath = "";
                dstSubfolderSpec = 10;
                files = (
                    49231BAD2AC5BCEF00F98ADF /* \(appModuleName) in Embed Frameworks */,
                );
                name = "Embed Frameworks";
                runOnlyForDeploymentPostprocessing = 0;
            };
    /* End PBXCopyFilesBuildPhase section */

    /* Begin PBXFileReference section */
            493609562A6B7EAE00C401E2 /* \(appModuleName) */ = {isa = PBXFileReference; lastKnownFileType = wrapper; name = \(appModuleName); path = \(relativeSwiftPackageRoot); sourceTree = "<group>"; };
            496EB72F2A6AE4DE00C1253A /* \(skipEnvFileName) */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; name = \(skipEnvBaseName); path = \(skipEnvFileName); sourceTree = "<group>"; };
            496EB72F2A6AE4DE00C1253B /* \(xcconfigFileName) */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = \(xcconfigFileName); sourceTree = "<group>"; };
            496EB72F2A6AE4DE00C1253C /* README.md */ = {isa = PBXFileReference; name = README.md; path = ../README.md; sourceTree = "<group>"; };
            4990AB3B2A91AFC5005777FD /* XCTest.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = XCTest.framework; path = Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework; sourceTree = DEVELOPER_DIR; };
            499CD4442AC5B799001AE8D8 /* \(appModuleName).app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = \(appModuleName).app; sourceTree = BUILT_PRODUCTS_DIR; };
            499AB9082B0581F4005E8330 /* plugins */ = {isa = PBXFileReference; lastKnownFileType = folder; name = plugins; path = ../../../SourcePackages/plugins; sourceTree = BUILT_PRODUCTS_DIR; };
            49F90C2B2A52156200F06D93 /* \(appMainSwiftFileName) */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = \(appMainSwiftFileName); path = \(primaryModuleAppMainPath); sourceTree = SOURCE_ROOT; };
            49F90C2F2A52156300F06D93 /* \(Assets_xcassets_name) */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; name = \(Assets_xcassets_name); path = \(Assets_xcassets_path); sourceTree = "<group>"; };
            49F90C312A52156300F06D93 /* \(entitlements_name) */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; name = \(entitlements_name); path = \(entitlements_path); sourceTree = "<group>"; };
    /* End PBXFileReference section */

    /* Begin PBXFrameworksBuildPhase section */
            499CD43C2AC5B799001AE8D8 /* Frameworks */ = {
                isa = PBXFrameworksBuildPhase;
                buildActionMask = 2147483647;
                files = (
                    49231BAC2AC5BCEF00F98ADF /* \(appModuleName) in Frameworks */,
                );
                runOnlyForDeploymentPostprocessing = 0;
            };
    /* End PBXFrameworksBuildPhase section */

    /* Begin PBXGroup section */
            49AB54462B066A7E007B79B2 /* SkipStone */ = {
                    isa = PBXGroup;
                    children = (
                            499AB9082B0581F4005E8330 /* plugins */,
                    );
                    name = SkipStone;
                    sourceTree = "<group>";
            };
            49F90C1F2A52156200F06D93 = {
                isa = PBXGroup;
                children = (
                    496EB72F2A6AE4DE00C1253C /* README.md */,
                    496EB72F2A6AE4DE00C1253A /* \(skipEnvBaseName) */,
                    496EB72F2A6AE4DE00C1253B /* \(xcconfigFileName) */,
                    493609562A6B7EAE00C401E2 /* \(appModuleName) */,
                    49F90C2A2A52156200F06D93 /* App */,
                    49AB54462B066A7E007B79B2 /* SkipStone */,
                );
                sourceTree = "<group>";
            };
            49F90C2A2A52156200F06D93 /* App */ = {
                isa = PBXGroup;
                children = (
                    49F90C2B2A52156200F06D93 /* \(appMainSwiftFileName) */,
                    49F90C2F2A52156300F06D93 /* \(Assets_xcassets_name) */,
                    49F90C312A52156300F06D93 /* \(entitlements_name) */,
                );
                name = App;
                sourceTree = "<group>";
            };
    /* End PBXGroup section */

    /* Begin PBXNativeTarget section */
            499CD4382AC5B799001AE8D8 /* \(appModuleName) */ = {
                isa = PBXNativeTarget;
                buildConfigurationList = 499CD4412AC5B799001AE8D8 /* Build configuration list for PBXNativeTarget "\(appModuleName)" */;
                buildPhases = (
                    499CD43A2AC5B799001AE8D8 /* Sources */,
                    499CD43C2AC5B799001AE8D8 /* Frameworks */,
                    499CD43E2AC5B799001AE8D8 /* Resources */,
                    499CD4452AC5B869001AE8D8 /* Run skip gradle */,
                    499CD44A2AC5B9C6001AE8D8 /* Embed Frameworks */,
                );
                buildRules = (
                );
                dependencies = (
                );
                name = \(appModuleName);
                packageProductDependencies = (
                    49231BAB2AC5BCEF00F98ADF /* \(primaryModuleAppTarget) */,
                );
                productName = App;
                productReference = 499CD4442AC5B799001AE8D8 /* \(appModuleName).app */;
                productType = "com.apple.product-type.application";
            };
    /* End PBXNativeTarget section */

    /* Begin PBXProject section */
            49F90C202A52156200F06D93 /* Project object */ = {
                isa = PBXProject;
                attributes = {
                    BuildIndependentTargetsInParallel = 1;
                    LastSwiftUpdateCheck = 1430;
                    LastUpgradeCheck = 1500;
                };
                buildConfigurationList = 49F90C232A52156200F06D93 /* Build configuration list for PBXProject "\(appModuleName)" */;
                compatibilityVersion = "Xcode 14.0";
                developmentRegion = en;
                hasScannedForEncodings = 0;
                knownRegions = (
                    en,
                    Base,
                );
                mainGroup = 49F90C1F2A52156200F06D93;
                packageReferences = (
                );
                productRefGroup = 49F90C292A52156200F06D93 /* Products */;
                projectDirPath = "";
                projectRoot = "";
                targets = (
                    499CD4382AC5B799001AE8D8 /* \(appModuleName) */,
                );
            };
    /* End PBXProject section */

    /* Begin PBXResourcesBuildPhase section */
            499CD43E2AC5B799001AE8D8 /* Resources */ = {
                isa = PBXResourcesBuildPhase;
                buildActionMask = 2147483647;
                files = (
                    499CD4402AC5B799001AE8D8 /* \(Assets_xcassets_name) in Resources */,
                );
                runOnlyForDeploymentPostprocessing = 0;
            };
    /* End PBXResourcesBuildPhase section */

    /* Begin PBXShellScriptBuildPhase section */
            499CD4452AC5B869001AE8D8 /* Run skip gradle */ = {
                isa = PBXShellScriptBuildPhase;
                alwaysOutOfDate = 1;
                buildActionMask = 2147483647;
                files = (
                );
                inputFileListPaths = (
                );
                inputPaths = (
                );
                name = "Run skip gradle";
                outputFileListPaths = (
                );
                outputPaths = (
                );
                runOnlyForDeploymentPostprocessing = 0;
                shellPath = "/bin/sh -e";
                shellScript = "\(skipGradleLaunchScript)";
            };
    /* End PBXShellScriptBuildPhase section */

    /* Begin PBXSourcesBuildPhase section */
            499CD43A2AC5B799001AE8D8 /* Sources */ = {
                isa = PBXSourcesBuildPhase;
                buildActionMask = 2147483647;
                files = (
                    499CD43B2AC5B799001AE8D8 /* \(appMainSwiftFileName) in Sources */,
                );
                runOnlyForDeploymentPostprocessing = 0;
            };
    /* End PBXSourcesBuildPhase section */

    /* Begin XCBuildConfiguration section */
            491FCC8E2AD18D38002FB1E1 /* Skippy */ = {
                isa = XCBuildConfiguration;
                baseConfigurationReference = 496EB72F2A6AE4DE00C1253B /* \(xcconfigFileName) */;
                buildSettings = {
                    ALWAYS_SEARCH_USER_PATHS = NO;
                    ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
                    COPY_PHASE_STRIP = NO;
                    DEBUG_INFORMATION_FORMAT = dwarf;
                    ENABLE_BITCODE = NO;
                    ENABLE_NS_ASSERTIONS = NO;
                    ENABLE_STRICT_OBJC_MSGSEND = YES;
                    ENABLE_USER_SCRIPT_SANDBOXING = NO;
                    LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
                    MTL_ENABLE_DEBUG_INFO = NO;
                    MTL_FAST_MATH = YES;
                    SWIFT_COMPILATION_MODE = wholemodule;
                };
                name = Skippy;
            };
            491FCC8F2AD18D38002FB1E1 /* Skippy */ = {
                isa = XCBuildConfiguration;
                buildSettings = {
                    ENABLE_PREVIEWS = YES;
                    LD_RUNPATH_SEARCH_PATHS = "@executable_path/Frameworks";
                    "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]" = "@executable_path/../Frameworks";
                    SDKROOT = auto;
                    SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
                    SWIFT_EMIT_LOC_STRINGS = YES;
                    SWIFT_VERSION = 5.0;
                    TARGETED_DEVICE_FAMILY = "1,2";
                };
                name = Skippy;
            };
            499CD4422AC5B799001AE8D8 /* Debug */ = {
                isa = XCBuildConfiguration;
                buildSettings = {
                    ENABLE_PREVIEWS = YES;
                    LD_RUNPATH_SEARCH_PATHS = "@executable_path/Frameworks";
                    "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]" = "@executable_path/../Frameworks";
                    SDKROOT = auto;
                    SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
                    SWIFT_EMIT_LOC_STRINGS = YES;
                    SWIFT_VERSION = 5.0;
                    TARGETED_DEVICE_FAMILY = "1,2";
                };
                name = Debug;
            };
            499CD4432AC5B799001AE8D8 /* Release */ = {
                isa = XCBuildConfiguration;
                buildSettings = {
                    ENABLE_PREVIEWS = YES;
                    LD_RUNPATH_SEARCH_PATHS = "@executable_path/Frameworks";
                    "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]" = "@executable_path/../Frameworks";
                    SDKROOT = auto;
                    SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
                    SWIFT_EMIT_LOC_STRINGS = YES;
                    SWIFT_VERSION = 5.0;
                    TARGETED_DEVICE_FAMILY = "1,2";
                };
                name = Release;
            };
            49F90C4B2A52156300F06D93 /* Debug */ = {
                isa = XCBuildConfiguration;
                baseConfigurationReference = 496EB72F2A6AE4DE00C1253B /* \(xcconfigFileName) */;
                buildSettings = {
                    ALWAYS_SEARCH_USER_PATHS = NO;
                    ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
                    COPY_PHASE_STRIP = NO;
                    DEBUG_INFORMATION_FORMAT = dwarf;
                    ENABLE_BITCODE = NO;
                    ENABLE_STRICT_OBJC_MSGSEND = YES;
                    ENABLE_TESTABILITY = YES;
                    ENABLE_USER_SCRIPT_SANDBOXING = NO;
                    LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
                    MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
                    MTL_FAST_MATH = YES;
                    ONLY_ACTIVE_ARCH = YES;
                    SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
                    SWIFT_OPTIMIZATION_LEVEL = "-Onone";
                };
                name = Debug;
            };
            49F90C4C2A52156300F06D93 /* Release */ = {
                isa = XCBuildConfiguration;
                baseConfigurationReference = 496EB72F2A6AE4DE00C1253B /* \(xcconfigFileName) */;
                buildSettings = {
                    ALWAYS_SEARCH_USER_PATHS = NO;
                    ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
                    COPY_PHASE_STRIP = NO;
                    DEBUG_INFORMATION_FORMAT = dwarf;
                    ENABLE_BITCODE = NO;
                    ENABLE_NS_ASSERTIONS = NO;
                    ENABLE_STRICT_OBJC_MSGSEND = YES;
                    ENABLE_USER_SCRIPT_SANDBOXING = NO;
                    LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
                    MTL_ENABLE_DEBUG_INFO = NO;
                    MTL_FAST_MATH = YES;
                    SWIFT_COMPILATION_MODE = wholemodule;
                };
                name = Release;
            };
    /* End XCBuildConfiguration section */

    /* Begin XCConfigurationList section */
            499CD4412AC5B799001AE8D8 /* Build configuration list for PBXNativeTarget "\(appModuleName)" */ = {
                isa = XCConfigurationList;
                buildConfigurations = (
                    499CD4422AC5B799001AE8D8 /* Debug */,
                    499CD4432AC5B799001AE8D8 /* Release */,
                    491FCC8F2AD18D38002FB1E1 /* Skippy */,
                );
                defaultConfigurationIsVisible = 0;
                defaultConfigurationName = Release;
            };
            49F90C232A52156200F06D93 /* Build configuration list for PBXProject "\(appModuleName)" */ = {
                isa = XCConfigurationList;
                buildConfigurations = (
                    49F90C4B2A52156300F06D93 /* Debug */,
                    49F90C4C2A52156300F06D93 /* Release */,
                    491FCC8E2AD18D38002FB1E1 /* Skippy */,
                );
                defaultConfigurationIsVisible = 0;
                defaultConfigurationName = Release;
            };
    /* End XCConfigurationList section */

    /* Begin XCSwiftPackageProductDependency section */
            49231BAB2AC5BCEF00F98ADF /* \(primaryModuleAppTarget) */ = {
                isa = XCSwiftPackageProductDependency;
                productName = \(primaryModuleAppTarget);
            };
    /* End XCSwiftPackageProductDependency section */
        };
        rootObject = 49F90C202A52156200F06D93 /* Project object */;
    }

    """
        }

        let xcodeProjectContents = createXcodeProj()
        let xcodeProjectPbxprojURL = appProject.darwinProjectContents
        // change spaces to tabs in the pbxproj, since that is what Xcode will do when it saves it
        try xcodeProjectContents.replacingOccurrences(of: "    ", with: "\t").write(to: xcodeProjectPbxprojURL, atomically: true, encoding: .utf8)

        let androidIconName: String? = hasIcon ? "mipmap/ic_launcher" : nil
        try createAndroidManifest(androidIconName: androidIconName).write(to: appProject.androidManifest.createParentDirectory(), atomically: true, encoding: .utf8)
        try createSettingsGradle().write(to: appProject.androidGradleSettings, atomically: true, encoding: .utf8)
        try createAppBuildGradle().write(to: appProject.androidAppBuildGradle, atomically: true, encoding: .utf8)
        try defaultProguardContents().write(to: appProject.androidAppProguardRules, atomically: true, encoding: .utf8)
        try defaultGradleProperties().write(to: appProject.androidGradleProperties, atomically: true, encoding: .utf8)
        try defaultGradleWrapperProperties().write(to: appProject.androidGradleWrapperProperties.createParentDirectory(), atomically: true, encoding: .utf8)

        let sourceMainKotlinPackage = appProject.androidAppSrcMainKotlin.appendingPathComponent(appModulePackage.split(separator: ".").joined(separator: "/"), isDirectory: true)
        let sourceMainKotlinSourceFile = sourceMainKotlinPackage.appendingPathComponent("Main.kt")
        try createKotlinMain(appModulePackage: appModulePackage, appModuleName: appModuleName).write(to: sourceMainKotlinSourceFile.createParentDirectory(), atomically: true, encoding: .utf8)

//        if gitRepo == true {
//            func createGitRepo(url: URL) throws -> CheckStatus {
//                // create the .gitignore file
//                let gitignore = """
//                .*.swp
//                .DS_Store
//                .build
//                build
//                /Packages
//                xcuserdata/
//                DerivedData/
//                .swiftpm/configuration/registries.json
//                .swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata
//                .netrc
//
//                """
//
//                try gitignore.write(to: projectURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
//                return CheckStatus(status: .pass, message: "Create git repository")
//            }
//
//            await checkFile(projectURL, with: out, title: "Create git repository", handle: createGitRepo)
//        }

        return (projectURL, appProject)
    }
}


extension FrameworkProjectLayout {
    static func createAndroidManifest(androidIconName: String?) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <!-- This AndroidManifest.xml template was generated by Skip -->
        <manifest xmlns:android="http://schemas.android.com/apk/res/android">
            <!-- example permissions for using device location -->
            <!-- <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/> -->
            <!-- <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/> -->

            <!-- permissions needed for using the internet or an embedded WebKit browser -->
            <uses-permission android:name="android.permission.INTERNET" />
            <!-- <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" /> -->

            <application
                android:label="${PRODUCT_NAME}"
                android:name=".AndroidAppMain"
                android:supportsRtl="true"
                android:allowBackup="true"
                \(androidIconName != nil ? "android:icon=\"@\(androidIconName!)\"" : "")>
                <activity
                    android:name=".MainActivity"
                    android:exported="true"
                    android:configChanges="orientation|screenSize|screenLayout|keyboardHidden|mnc|colorMode|density|fontScale|fontWeightAdjustment|keyboard|layoutDirection|locale|mcc|navigation|smallestScreenSize|touchscreen|uiMode"
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
    }

    static func createSettingsGradle() -> String {
        """
        // This is the top-level Gradle settings for a Skip App project.
        // It reads from the Skip.env file in the root of the project

        pluginManagement {
            repositories {
                maven("https://maven.skip.tools")
                gradlePluginPortal()
                mavenCentral()
                google()
            }
        }

        dependencyResolutionManagement {
            repositories {
                maven("https://maven.skip.tools")
                mavenCentral()
                google()
            }
        }

        // Use the properties in the Skip.env file for configuration
        val parentFolder = file("..")
        val envFile = parentFolder.resolve("Skip.env")
        if (!envFile.exists()) {
            throw GradleException("Skip.env file missing from ${parentFolder}")
        }

        val skipenv = loadSkipEnv(envFile)

        // Use the shared ../.build/Android/ build folder as the gradle build output
        val buildOutput = parentFolder.resolve(".build/Android/")
        gradle.projectsLoaded {
            rootProject.allprojects {
                layout.buildDirectory.set(buildOutput.resolve(project.name))
            }
        }

        rootProject.name = prop(key = "ANDROID_PACKAGE_NAME")
        val swiftProjectName = prop(key = "SKIP_PROJECT_NAME")
        val swiftModuleName = prop(key = "PRODUCT_NAME")

        // After the settings have been evaluated, resolve the Skip transpilation output folders
        gradle.settingsEvaluated {
            addSkipModules()
        }

        // Parse .env file into a map of strings
        fun loadSkipEnv(file: File): Map<String, String> {
            val envMap = mutableMapOf<String, String>()
            file.forEachLine { line ->
                if (line.isNotBlank() && line[0] != '#' && !line.startsWith("//")) {
                    val parts = line.split("=", limit = 2)
                    if (parts.size == 2) {
                        val key = parts[0].trim()
                        val value = parts[1].trim()
                        envMap[key] = value
                    }
                }
            }

            // Set system properties prefixed with SKIP_ for each key-value pair in the .env file
            // access with getProperty("SKIP_PRODUCT_BUNDLE_IDENTIFIER")
            envMap.forEach { (key, value) ->
                System.setProperty("SKIP_" + key, value)
            }

            return envMap
        }


        fun prop(key: String): String {
            val value = System.getProperty("SKIP_" + key, System.getenv(key))
            if (value == null) {
                throw GradleException("Required key ${key} is not set in environment or Skip.env")
            }
            return value
        }

        fun addSkipModules() {
            // When running from Xcode, the BUILT_PRODUCTS_DIR environment
            // variable will point to the project's DerivedData path, like:
            // ~/Library/Developer/Xcode/DerivedData/NAME-HASH/Build/Products/Debug-iphonesimulator
            //
            // When unset, we assume using the local SwiftPM .build folder, and
            // will invoke `swift build` to perform transpilation at the
            // beginning of the build
            var builtProductsDir = System.getenv("BUILT_PRODUCTS_DIR")

            // In order to build and debug in an IDE using locally-sourced modules,
            // temporarily override this setting with the known-local BUILT_PRODUCTS_DIR,
            // which can be found in Xcode's Reports Navigator Build log for the app in the
            // environment settings list of the "Run custom shell script 'Run skip gradle'" log entry
            // builtProductsDir = "/Users/marc/Library/Developer/Xcode/DerivedData/Skip-App-aqywrhrzhkbvfseiqgxuufbdwdft/Build/Products/Debug-iphonesimulator"

            var skipOutputs: File
            if (builtProductsDir != null) {
                // BUILT_PRODUCTS_DIR is set when building from Xcode, in which case we will use Xcode's DerivedData plugin output
                skipOutputs = file(builtProductsDir).resolve("../../../SourcePackages/plugins/")
            } else {
                // SPM output folder is a peer of the parent Package.swift
                skipOutputs = parentFolder.resolve(".build/plugins/outputs/")

                // not running from xcode, so fork swift to build locally to ../.build/
                exec {
                    logger.log(LogLevel.LIFECYCLE, "Skip transpile swift to kotlin")
                    commandLine("swift", "build")
                }
            }

            val outputExt = if (builtProductsDir != null) ".output" else ""
            val projectDir = skipOutputs
                .resolve(swiftProjectName + outputExt)
                .resolve(swiftModuleName)
                .resolve("skipstone")

            if (!projectDir.exists()) {
                // If the directory does not exist, fail the build
                throw GradleException("Skip output directory does not exist at: $projectDir")
            }

            var skipDependencies: List<String> = listOf()
            projectDir.listFiles()?.forEach { outputDir ->
                // for each child package, include it in this build
                if (outputDir.resolve("build.gradle.kts").exists()) {
                    val moduleName = outputDir.name
                    logger.log(LogLevel.LIFECYCLE, "Skip module :${moduleName} added to project: ${outputDir}")
                    include(":${moduleName}")
                    project(":${moduleName}").projectDir = outputDir
                    skipDependencies += ":${moduleName}"
                }
            }

            // pass down the list of dynamic Skip dependencies to the app build
            // we would prefer to use the `exta` property for this, but it doesn't seem to be readable in app/build.gradle.kts
            System.setProperty("SKIP_DEPENDENCIES", skipDependencies.joinToString(separator = ":"))
            include(":app")
        }

        """
    }


    static func createAppBuildGradle() -> String {
        """
        plugins {
            kotlin("android") version "1.9.0"
            id("com.android.application") version "8.1.0"
        }

        android {
            defaultConfig {
                minSdk = 29
                testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
                manifestPlaceholders["PRODUCT_NAME"] = prop("PRODUCT_NAME")
                manifestPlaceholders["PRODUCT_BUNDLE_IDENTIFIER"] = prop("PRODUCT_BUNDLE_IDENTIFIER")
                manifestPlaceholders["MARKETING_VERSION"] = prop("MARKETING_VERSION")
                manifestPlaceholders["CURRENT_PROJECT_VERSION"] = prop("CURRENT_PROJECT_VERSION")
                manifestPlaceholders["ANDROID_PACKAGE_NAME"] = prop("ANDROID_PACKAGE_NAME")
                applicationId = manifestPlaceholders["PRODUCT_BUNDLE_IDENTIFIER"]?.toString()
                versionCode = (manifestPlaceholders["CURRENT_PROJECT_VERSION"]?.toString())?.toInt()
                versionName = manifestPlaceholders["MARKETING_VERSION"]?.toString()
            }
            buildFeatures {
                buildConfig = true
                compose = true
            }
            buildTypes {
                release {
                    signingConfig = signingConfigs.findByName("release")
                    isMinifyEnabled = true
                    isShrinkResources = true
                    isDebuggable = true
                    proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
                }
            }
            composeOptions {
                kotlinCompilerExtensionVersion = "1.5.1"
            }
            namespace = group as String
            compileSdk = 34
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
            testOptions {
                unitTests {
                    isIncludeAndroidResources = true
                }
            }
        }

        afterEvaluate {
            dependencies {
                // SKIP_DEPENDENCIES is set by the settings.gradle.kts as a list of the modules that were created as a result of the Skip build
                var deps = prop(key = "DEPENDENCIES")
                deps.split(":").filter { it.isNotEmpty() }.forEach { skipModuleName ->
                    if (skipModuleName != "SkipUnit") {
                        implementation(project(":" + skipModuleName))
                    }
                }
            }
        }

        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>() {
            kotlinOptions {
                suppressWarnings = true
            }
        }

        tasks.withType<Test>().configureEach {
            systemProperties.put("robolectric.logging", "stdout")
            systemProperties.put("robolectric.graphicsMode", "NATIVE")
            testLogging {
                this.showStandardStreams = true
            }
        }

        fun prop(key: String): String {
            val value = System.getProperty("SKIP_" + key, System.getenv(key))
            if (value == null) {
                throw GradleException("Required key ${key} is not set")
            }
            return value
        }

        // add the "launchDebug" and "launchRelease" commands
        listOf("Debug", "Release").forEach { buildType ->
            task("launch" + buildType) {
                dependsOn("install" + buildType)

                doLast {
                    val activity = prop("PRODUCT_BUNDLE_IDENTIFIER") + "/" + prop("ANDROID_PACKAGE_NAME") + ".MainActivity"

                    var adbCommand = "adb"
                    if (org.gradle.internal.os.OperatingSystem.current().isWindows) {
                        adbCommand += ".exe"
                    }

                    exec {
                        commandLine = listOf(
                            adbCommand,
                            "shell",
                            "am",
                            "start",
                            "-a",
                            "android.intent.action.MAIN",
                            "-c",
                            "android.intent.category.LAUNCHER",
                            "-n",
                            "$activity"
                        )
                    }
                }
            }
        }

        """
    }

    static func createKotlinMain(appModulePackage: String, appModuleName: String) -> String {
        """
        package \(appModulePackage)

        import skip.lib.*
        import skip.model.*
        import skip.foundation.*
        import skip.ui.*

        import androidx.compose.runtime.Composable
        import androidx.compose.runtime.getValue
        import androidx.compose.runtime.mutableStateOf
        import androidx.compose.runtime.remember
        import androidx.compose.runtime.saveable.Saver
        import androidx.compose.runtime.saveable.rememberSaveable
        import androidx.compose.runtime.setValue

        import android.Manifest
        import android.app.Application
        import androidx.activity.compose.setContent
        import androidx.appcompat.app.AppCompatActivity
        import androidx.compose.foundation.isSystemInDarkTheme
        import androidx.compose.foundation.layout.fillMaxSize
        import androidx.compose.foundation.layout.Box
        import androidx.compose.material3.MaterialTheme
        import androidx.compose.material3.darkColorScheme
        import androidx.compose.material3.dynamicDarkColorScheme
        import androidx.compose.material3.dynamicLightColorScheme
        import androidx.compose.material3.lightColorScheme
        import androidx.compose.runtime.saveable.rememberSaveableStateHolder
        import androidx.compose.ui.Alignment
        import androidx.compose.ui.Modifier
        import androidx.compose.ui.platform.LocalContext
        import androidx.core.app.ActivityCompat

        internal val logger: SkipLogger = SkipLogger(subsystem = "\(appModulePackage)", category = "\(appModuleName)")

        /// AndroidAppMain is the `android.app.Application` entry point, and must match `application android:name` in the AndroidMainfest.xml file.
        open class AndroidAppMain: Application {
            constructor() {
            }

            override fun onCreate() {
                super.onCreate()
                logger.info("starting app")
                ProcessInfo.launch(applicationContext)
            }

            companion object {
            }
        }

        /// AndroidAppMain is initial `androidx.appcompat.app.AppCompatActivity`, and must match `activity android:name` in the AndroidMainfest.xml file.
        open class MainActivity: AppCompatActivity {
            constructor() {
            }

            override fun onCreate(savedInstanceState: android.os.Bundle?) {
                super.onCreate(savedInstanceState)

                setContent {
                    val saveableStateHolder = rememberSaveableStateHolder()
                    saveableStateHolder.SaveableStateProvider(true) {
                        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { MaterialThemedRootView() }
                    }
                }

                // Example of requesting permissions on startup.
                // These must match the permissions in the AndroidManifest.xml file.
                //let permissions = listOf(
                //    Manifest.permission.ACCESS_COARSE_LOCATION,
                //    Manifest.permission.ACCESS_FINE_LOCATION
                //    Manifest.permission.CAMERA,
                //    Manifest.permission.WRITE_EXTERNAL_STORAGE,
                //)
                //let requestTag = 1
                //ActivityCompat.requestPermissions(self, permissions.toTypedArray(), requestTag)
            }

            override fun onSaveInstanceState(bundle: android.os.Bundle): Unit = super.onSaveInstanceState(bundle)

            override fun onRestoreInstanceState(bundle: android.os.Bundle) {
                // Usually you restore your state in onCreate(). It is possible to restore it in onRestoreInstanceState() as well, but not very common. (onRestoreInstanceState() is called after onStart(), whereas onCreate() is called before onStart().
                logger.info("onRestoreInstanceState")
                super.onRestoreInstanceState(bundle)
            }

            override fun onRestart() {
                logger.info("onRestart")
                super.onRestart()
            }

            override fun onStart() {
                logger.info("onStart")
                super.onStart()
            }

            override fun onResume() {
                logger.info("onResume")
                super.onResume()
            }

            override fun onPause() {
                logger.info("onPause")
                super.onPause()
            }

            override fun onStop() {
                logger.info("onStop")
                super.onStop()
            }

            override fun onDestroy() {
                logger.info("onDestroy")
                super.onDestroy()
            }

            override fun onRequestPermissionsResult(requestCode: Int, permissions: kotlin.Array<String>, grantResults: IntArray) {
                super.onRequestPermissionsResult(requestCode, permissions, grantResults)
                logger.info("onRequestPermissionsResult: ${requestCode}")
            }

            companion object {
            }
        }

        @Composable
        internal fun MaterialThemedRootView() {
            val context = LocalContext.current.sref()
            val darkMode = isSystemInDarkTheme()
            // Dynamic color is available on Android 12+
            val dynamicColor = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S

            val colorScheme = if (dynamicColor) (if (darkMode) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)) else (if (darkMode) darkColorScheme() else lightColorScheme())

            MaterialTheme(colorScheme = colorScheme) { RootView().Compose() }
        }


        """
    }
    static func defaultProguardContents() -> String {
        """
        -keep class skip.** { *; }
        """
    }

    static func defaultGradleProperties() -> String {
        """
        org.gradle.jvmargs=-Xmx2048m
        android.useAndroidX=true
        kotlin.code.style=official
        android.suppressUnsupportedCompileSdk=34

        """
    }

    /// the Gradle version string to generate
    static let gradleVersion = "8.4"

    static func defaultGradleWrapperProperties() -> String {
        """
        distributionUrl=https\\://services.gradle.org/distributions/gradle-\(gradleVersion)-all.zip

        """
    }
}

fileprivate let licenseLGPL = """
                   GNU LESSER GENERAL PUBLIC LICENSE
                       Version 3, 29 June 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.


  This version of the GNU Lesser General Public License incorporates
the terms and conditions of version 3 of the GNU General Public
License, supplemented by the additional permissions listed below.

  0. Additional Definitions.

  As used herein, "this License" refers to version 3 of the GNU Lesser
General Public License, and the "GNU GPL" refers to version 3 of the GNU
General Public License.

  "The Library" refers to a covered work governed by this License,
other than an Application or a Combined Work as defined below.

  An "Application" is any work that makes use of an interface provided
by the Library, but which is not otherwise based on the Library.
Defining a subclass of a class defined by the Library is deemed a mode
of using an interface provided by the Library.

  A "Combined Work" is a work produced by combining or linking an
Application with the Library.  The particular version of the Library
with which the Combined Work was made is also called the "Linked
Version".

  The "Minimal Corresponding Source" for a Combined Work means the
Corresponding Source for the Combined Work, excluding any source code
for portions of the Combined Work that, considered in isolation, are
based on the Application, and not on the Linked Version.

  The "Corresponding Application Code" for a Combined Work means the
object code and/or source code for the Application, including any data
and utility programs needed for reproducing the Combined Work from the
Application, but excluding the System Libraries of the Combined Work.

  1. Exception to Section 3 of the GNU GPL.

  You may convey a covered work under sections 3 and 4 of this License
without being bound by section 3 of the GNU GPL.

  2. Conveying Modified Versions.

  If you modify a copy of the Library, and, in your modifications, a
facility refers to a function or data to be supplied by an Application
that uses the facility (other than as an argument passed when the
facility is invoked), then you may convey a copy of the modified
version:

   a) under this License, provided that you make a good faith effort to
   ensure that, in the event an Application does not supply the
   function or data, the facility still operates, and performs
   whatever part of its purpose remains meaningful, or

   b) under the GNU GPL, with none of the additional permissions of
   this License applicable to that copy.

  3. Object Code Incorporating Material from Library Header Files.

  The object code form of an Application may incorporate material from
a header file that is part of the Library.  You may convey such object
code under terms of your choice, provided that, if the incorporated
material is not limited to numerical parameters, data structure
layouts and accessors, or small macros, inline functions and templates
(ten or fewer lines in length), you do both of the following:

   a) Give prominent notice with each copy of the object code that the
   Library is used in it and that the Library and its use are
   covered by this License.

   b) Accompany the object code with a copy of the GNU GPL and this license
   document.

  4. Combined Works.

  You may convey a Combined Work under terms of your choice that,
taken together, effectively do not restrict modification of the
portions of the Library contained in the Combined Work and reverse
engineering for debugging such modifications, if you also do each of
the following:

   a) Give prominent notice with each copy of the Combined Work that
   the Library is used in it and that the Library and its use are
   covered by this License.

   b) Accompany the Combined Work with a copy of the GNU GPL and this license
   document.

   c) For a Combined Work that displays copyright notices during
   execution, include the copyright notice for the Library among
   these notices, as well as a reference directing the user to the
   copies of the GNU GPL and this license document.

   d) Do one of the following:

       0) Convey the Minimal Corresponding Source under the terms of this
       License, and the Corresponding Application Code in a form
       suitable for, and under terms that permit, the user to
       recombine or relink the Application with a modified version of
       the Linked Version to produce a modified Combined Work, in the
       manner specified by section 6 of the GNU GPL for conveying
       Corresponding Source.

       1) Use a suitable shared library mechanism for linking with the
       Library.  A suitable mechanism is one that (a) uses at run time
       a copy of the Library already present on the user's computer
       system, and (b) will operate properly with a modified version
       of the Library that is interface-compatible with the Linked
       Version.

   e) Provide Installation Information, but only if you would otherwise
   be required to provide such information under section 6 of the
   GNU GPL, and only to the extent that such information is
   necessary to install and execute a modified version of the
   Combined Work produced by recombining or relinking the
   Application with a modified version of the Linked Version. (If
   you use option 4d0, the Installation Information must accompany
   the Minimal Corresponding Source and Corresponding Application
   Code. If you use option 4d1, you must provide the Installation
   Information in the manner specified by section 6 of the GNU GPL
   for conveying Corresponding Source.)

  5. Combined Libraries.

  You may place library facilities that are a work based on the
Library side by side in a single library together with other library
facilities that are not Applications and are not covered by this
License, and convey such a combined library under terms of your
choice, if you do both of the following:

   a) Accompany the combined library with a copy of the same work based
   on the Library, uncombined with any other library facilities,
   conveyed under the terms of this License.

   b) Give prominent notice with the combined library that part of it
   is a work based on the Library, and explaining where to find the
   accompanying uncombined form of the same work.

  6. Revised Versions of the GNU Lesser General Public License.

  The Free Software Foundation may publish revised and/or new versions
of the GNU Lesser General Public License from time to time. Such new
versions will be similar in spirit to the present version, but may
differ in detail to address new problems or concerns.

  Each version is given a distinguishing version number. If the
Library as you received it specifies that a certain numbered version
of the GNU Lesser General Public License "or any later version"
applies to it, you have the option of following the terms and
conditions either of that published version or of any later version
published by the Free Software Foundation. If the Library as you
received it does not specify a version number of the GNU Lesser
General Public License, you may choose any version of the GNU Lesser
General Public License ever published by the Free Software Foundation.

  If the Library as you received it specifies that a proxy can decide
whether future versions of the GNU Lesser General Public License shall
apply, that proxy's public statement of acceptance of any version is
permanent authorization for you to choose that version for the
Library.

"""

/// The header that will be inserted into any source files (Kotin or Swift) created by the `skip` tool when the `--free` flag is set.
fileprivate let licenseLGPLHeader = """
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org


"""
