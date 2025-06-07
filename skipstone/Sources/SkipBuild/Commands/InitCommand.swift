import Foundation
import ArgumentParser
import SkipSyntax
import TSCBasic
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct InitCommand: MessageCommand, CreateOptionsCommand, ProjectCommand, ToolOptionsCommand, BuildOptionsCommand, StreamingCommand {
    static var configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize a new Skip project",
        usage: """
# Create a new native Skip Fuse app project
skip init --native-app --appid=some.app.id app-project AppName

# Create a new transpiled Skip Lite app project
skip init --transpiled-app --appid=some.app.id app-project AppName

# Create a new native library project
skip init --native-model lib-project ModuleName

# Create a new transpiled library project
skip init --transpiled-model lib-project ModuleName

# Create a new app project with multiple modules
skip init --native-app --appid=some.app.id app-project AppName ModuleName
""",
        discussion: """
This command will create a conventional Skip app or library project.
""",
        shouldDisplay: true)

    // TODO: add dependencies @ syntax https://github.com/orgs/skiptools/discussions/417

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Create Options")
    var createOptions: CreateOptions

    @OptionGroup(title: "Project Options")
    var projectOptions: ProjectOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @OptionGroup(title: "Build Options")
    var buildOptions: BuildOptions

    @Argument(help: ArgumentHelp("Project folder name"))
    var projectName: String

    @Option(help: ArgumentHelp("Embed the library as an app with the given bundle id", valueName: "bundleID"))
    var appid: String? = nil

    @Flag(help: ArgumentHelp("Disable icon generation"))
    var noIcon: Bool = false

    @Option(help: ArgumentHelp("Path to icon input file (SVG, PDF, PNG)", valueName: "icon"))
    var icon: [String] = []

    @Option(help: ArgumentHelp("RGB hexadecimal color for icon background", valueName: "hex"))
    var iconBackground: String? = nil

    @Option(help: ArgumentHelp("RGB hexadecimal color for icon foreground", valueName: "hex"))
    var iconForeground: String? = nil

    @Option(help: ArgumentHelp("The amount of shadow to draw around the target", valueName: "decimal"))
    var iconShadow: Double? = nil

    @Option(help: ArgumentHelp("The amount of inset to place on the image", valueName: "decimal"))
    var iconInset: Double? = nil

    @Option(help: ArgumentHelp("Set the initial version to the given value"))
    var version: String? = nil

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Build the Android .apk file"))
    var apk: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Build the iOS .ipa file"))
    var ipa: Bool = false

    @Flag(help: ArgumentHelp("Open the resulting Xcode project"))
    var openXcode: Bool = false

    @Flag(help: ArgumentHelp("Open the resulting Gradle project"))
    var openGradle: Bool = false

    @Argument(help: ArgumentHelp("The module name(s) to create"))
    var moduleNames: [String]

    //@Flag(help: ArgumentHelp("Open the resulting project in Android Studio"))
    //var openStudio: Bool = false

    /// Attempts to parse module names like "skiptools/skip-ui/SkipUI" into a full repo and path
    var modules: [PackageModule] {
        get throws {
            try self.moduleNames.map {
                try PackageModule(parse: $0)
            }
        }
    }

    var project: String {
        (self.createOptions.dir ?? ".")
    }

    func performCommand(with out: MessageQueue) async {
        await withLogStream(with: out) {
            try await runInit(with: out)
        }
    }

    var nativeApp: Bool {
        projectOptions.projectMode.contains(.nativeApp)
    }

    var nativeMode: NativeMode {
        var mode: NativeMode = []
        if self.nativeApp {
            mode.insert(.nativeApp)
        }
        // model will be native iff
        if projectOptions.projectMode.contains(.nativeModel) || (!projectOptions.projectMode.contains(.transpiledModel) && self.nativeApp) {
            mode.insert(.nativeModel)
        }
        return mode
    }

    var isNative: Bool {
        !nativeMode.isEmpty
    }

    var moduleMode: ModuleMode {
        isNative && createOptions.kotlincompat ? ModuleMode.kotlincompat : isNative ? (nativeApp ? .native : .nativeBridged) : .transpiled
    }

    func runInit(with out: MessageQueue) async throws {
        await out.yield(MessageBlock(status: nil, "Initializing Skip \(appid == nil && !createOptions.appfair ? "library" : "application") \(self.projectName)"))

        let dir = URL(fileURLWithPath: self.createOptions.dir ?? self.projectName, isDirectory: true)

        let modules = try self.modules
        let icon: IconParameters? = noIcon == true ? nil : IconParameters(iconBackgroundColor: iconBackground, iconForegroundColor: iconForeground, iconSources: icon, iconShadow: iconShadow, iconInset: iconInset)

        let isApp = appid != nil || self.projectOptions.projectMode.contains(.nativeApp) || self.projectOptions.projectMode.contains(.transpiledApp)
        let moduleMode = self.moduleMode
        let nativeMode = self.nativeMode
        // for now we default to creating tests only when non-native
        let createTests = self.createOptions.moduleTests ?? nativeMode.isEmpty

        let (createdURL, project, _) = try await initSkipProject(
            baseName: self.projectName,
            modules: modules,
            resourceFolder: createOptions.resourcePath,
            dir: dir,
            verify: buildOptions.verify,
            configuration: createOptions.configuration,
            build: buildOptions.build,
            test: buildOptions.test,
            returnHashes: false,
            showTree: self.createOptions.showTree,
            chain: createOptions.chain,
            gitRepo: createOptions.gitRepo,
            free: createOptions.free,
            appfair: createOptions.appfair,
            zero: createOptions.zero,
            app: isApp,
            appid: self.appid,
            icon: icon,
            version: self.version,
            swiftVersion: self.createOptions.swiftVersion ?? nativeMode.swiftVersion,
            nativeMode: nativeMode,
            moduleMode: moduleMode,
            moduleTests: createTests,
            github: self.createOptions.github,
            fastlane: self.createOptions.fastlane,
            validatePackage: self.createOptions.validatePackage,
            apk: apk,
            ipa: ipa,
            with: out
        )

        await out.yield(MessageBlock(status: .pass, "Created module \(modules.map(\.moduleName).joined(separator: ", ")) in \(createdURL.path)"))

        if openXcode {
            try await run(with: out, "Opening Xcode project", ["open", project.workspaceFolder.path])
        }

        if openGradle {
            try await run(with: out, "Opening Gradle project", ["open", project.androidGradleSettings.path])
        }

        // TODO: ensure the project was transpiled, find the settings.gradle.kts for the primary module, and open it
        //if openAndroid {
        //    await run(with: out, "Opening Gradle project", ["open", projectGradleSettings.path])
        //}
    }
}

let buildFolderName = ".build"
let darwinBuildFolder = buildFolderName + "/Darwin"
let androidBuildFolder = buildFolderName + "/Android"

/// The build configuration, either `debug` or `release`.
enum BuildConfiguration : String, ExpressibleByArgument {
    case debug, release
}

extension ToolOptionsCommand where Self : StreamingCommand {

    func createAPK(projectURL: URL, appModuleName: String, configuration: BuildConfiguration, out: MessageQueue, primaryModuleName: String, cfgSuffix: String, returnHashes: Bool, prefix re: String) async throws -> [URL : String?] {
        // assemble the .apk
        let env = ProcessInfo.processInfo.environmentWithDefaultToolPaths // environment that includes a default ANDROID_HOME
        
        let gradleProjectDir = projectURL.path + "/Android"
        let outputsPath = projectURL.path + "/" + androidBuildFolder + "/" + appModuleName + "/outputs"
        
        let action = "assemble" + configuration.rawValue.capitalized // turn "debug" into "Debug" and "release" into "Release"
        try await run(with: out, "Assembling Android apk", ["gradle", action, "--console=plain", "--project-dir", gradleProjectDir], environment: env)

        // the expected path for the gradle output folder of the assemble action

        // for example: skipapp-playground/.build/plugins/outputs/skipapp-playground/Playground/skipstone/Playground/.build/skipapp-playground/outputs/apk/release/Playground-release.apk
        let unsigned = configuration == .release ? "-unsigned" : "" // we do not sign the release builds for reproducibility, which leads to them having the "-unsigned" suffix

        let apkTitle = primaryModuleName + cfgSuffix + ".apk" // the name of the .apk for reporting purposes (don't include the -unsigned)
        let apkPath = outputsPath + "/apk/" + configuration.rawValue + "/" + appModuleName + cfgSuffix + unsigned + ".apk"
        let apkURL = URL(fileURLWithPath: apkPath, isDirectory: false)
        
        await checkFile(apkURL, with: out, title: "Verify \(apkTitle)") { title, url in
            return CheckStatus(status: .pass, message: try "\(title): \(url.fileSizeString)")
        }

        var hashes: [URL : String?] = [:]
        hashes[apkURL] = nil
        if returnHashes {
            await checkFile(apkURL, with: out, title: "\(re)Checksum Archive") { title, url in
                let apkHash = try url.SHA256Hash()
                hashes[apkURL] = apkHash
                return CheckStatus(status: .pass, message: "\(title): SHA256: \(apkHash)")
            }
        }
        return hashes
    }

    /// Zip up the given folder.
    @discardableResult func zipFolder(with out: MessageQueue, message msg: String, compressionLevel: Int = 9, zipFile: URL, folder: URL) async throws -> Result<ProcessOutput, Error> {
        func returnFileSize(_ result: Result<ProcessOutput, Error>?) -> (result: Result<ProcessOutput, Error>?, message: MessageBlock?) {
            do {
                return (result: result, message: MessageBlock(status: .pass, try "\(msg) \(zipFile.fileSizeString)"))
            } catch {
                return (result: result, message: MessageBlock(status: .fail, msg))
            }
        }
        return try await run(with: out, msg, ["zip", "-\(compressionLevel)", "--symlinks", "-r", zipFile.path, folder.lastPathComponent], in: folder.deletingLastPathComponent(), resultHandler: returnFileSize)
    }

    func createIPA(configuration: BuildConfiguration, schemeName: String?, primaryModuleName: String, sdk: String = "iphoneos", cfgSuffix: String, projectURL: URL, out: MessageQueue, prefix re: String, xcodeProjectURL: URL, ipaURL ipaOutputURL: URL? = nil, xcarchiveURL: URL? = nil, teamID: String? = nil, verifyFile: Bool = true, returnHashes: Bool) async throws -> [URL : String?] {
        // xcodebuild -derivedDataPath .build/DerivedData -skipPackagePluginValidation -skipMacroValidation -archivePath "${ARCHIVE_PATH}" -configuration "${CONFIGURATION}" -scheme "${SKIP_MODULE}" -sdk "iphoneos" -destination "generic/platform=iOS" -jobs 1 archive CODE_SIGNING_ALLOWED=NO
        let cfg = configuration.rawValue.capitalized
        let archiveBasePath = darwinBuildFolder + "/Archives/" + cfg

        let archivePath = archiveBasePath + "/" + primaryModuleName + ".xcarchive"

        // Get the scheme list from the Xcode project
        let projectSchemes = try await run(with: out, "Check project schemes", ["xcodebuild", "-list", "-json", "-project", xcodeProjectURL.path]).get()
        let schemeList = try JSONDecoder().decode(XcodeProjectSchemes.self, from: projectSchemes.stdout.data(using: .utf8) ?? Data())

        guard let appSchemeName = schemeName ?? schemeList.project.targets?.first else {
            throw MissingProjectFileError(errorDescription: "No schemes found in project: \(xcodeProjectURL.path): \(projectSchemes.stdout)")
        }

        // note that derivedDataPath and archivePath are relative to CWD rather than
        let fullArchivePath = projectURL.path + "/" + archivePath
        let fullDerivedDataPath = projectURL.path + "/" + darwinBuildFolder + "/DerivedData"

        try await run(with: out, "\(re)Archive iOS ipa", [
            "xcodebuild",
            "-project", xcodeProjectURL.path,
            "-derivedDataPath", fullDerivedDataPath,
            "-skipPackagePluginValidation",
            "-skipMacroValidation",
            "-archivePath", fullArchivePath,
            "-configuration", cfg,
            "-scheme", appSchemeName,
            "-sdk", sdk,
            "-destination", "generic/platform=iOS",
            "archive",
            "CODE_SIGNING_ALLOWED=NO",
            "ZERO_AR_DATE=1", // excludes timestamps from archives for build reproducibility
        ], additionalEnvironment: ["SKIP_ZERO": "1", "SKIP_PLUGIN_DISABLED": "1"]) // SKIP_ZERO builds without Skip dependency libraries
        
        let archiveAppPath = archivePath + "/Products/Applications/" + primaryModuleName + ".app"
        let archiveAppURL = projectURL.appendingPathComponent(archiveAppPath, isDirectory: true)
        if archiveAppURL.isDirectoryFile == false {
            throw MissingProjectFileError(errorDescription: "Expected archive does not exist at: \(archiveAppURL.path)")
        }
        
        // Create an ipa (zip) file of the app contents
        
        // need to first copy the contents over to a "Payload" folder, since the root of the .ipa needs to be "Payload"
        let archiveAppPayloadURL = archiveAppURL
            .deletingLastPathComponent()
            .appendingPathComponent("Payload", isDirectory: true)
        try FileManager.default.createDirectory(at: archiveAppPayloadURL, withIntermediateDirectories: false)
        let archiveAppContentsURL = archiveAppPayloadURL
            .appendingPathComponent(archiveAppURL.lastPathComponent, isDirectory: true)
        
        try FileManager.default.copyItem(at: archiveAppURL, to: archiveAppContentsURL)
        try FileManager.default.zeroFileTimes(under: archiveAppPayloadURL)
        
        let ipaURL = ipaOutputURL ?? projectURL.appending(path: archiveBasePath + "/" + primaryModuleName + cfgSuffix + ".ipa")

        // TODO: check whether a teamid is specified, and if so, create an ExportOptions.plist and export with xcodebuild
        if let teamID = teamID {
            let _ = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>\(teamID)</string>
</dict>
</plist>
"""
            // TODO: run xcodebuild -exportArchive -archivePath ARCHIVE.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath ~/Desktop

            // TODO: edit each Payload/HelloSkip.app/Frameworks/HelloSkipApp.framework/Info.plist and Payload/HelloSkip.app/hello-skip_HelloSkip.bundle/Info.plist file and fix the random UUID that seems to get added to the CFBundleIdentifier like: `<string>-cf71430-498e-4613-9daa-84451ab9b11e.HelloSkip.resources</string>`
        }

        // if no teamid is specified, then just zip up the output folder
        try await zipFolder(with: out, message: "\(re)Assemble \(ipaURL.lastPathComponent)", zipFile: ipaURL, folder: archiveAppPayloadURL)

        // also zip up the .xcarchive path
        if let xcarchiveURL = xcarchiveURL {
            try await zipFolder(with: out, message: "\(re)Archive \(xcarchiveURL.lastPathComponent)", zipFile: xcarchiveURL, folder: URL(fileURLWithPath: fullArchivePath))
        }

        if verifyFile {
            await checkFile(ipaURL, with: out, title: "\(re)Verifying \(ipaURL.lastPathComponent)") { title, url in
                CheckStatus(status: .pass, message: try "\(title): \(url.fileSizeString)")
            }
        }

        var hashes: [URL : String?] = [:]
        hashes[ipaURL] = nil
        if returnHashes {
            await checkFile(ipaURL, with: out, title: "\(re)Checksum Archive") { title, url in
                let ipaHash = try url.SHA256Hash()
                hashes[ipaURL] = ipaHash
                return CheckStatus(status: .pass, message: "\(title): SHA256: \(ipaHash)")
            }
        }
        return hashes
    }

    func initSkipProject(baseName: String, modules: [PackageModule], resourceFolder: String?, dir outputFolder: URL, verify: Bool, configuration: BuildConfiguration, build: Bool, test: Bool, returnHashes: Bool, messagePrefix: String? = nil, showTree: Bool, chain: Bool, gitRepo: Bool, free: Bool, appfair: Bool? = nil, zero skipZeroSupport: Bool, app isApp: Bool, appid: String?, appModuleName: String = "app", icon: IconParameters?, version: String?, swiftVersion: String, nativeMode: NativeMode, moduleMode: ModuleMode, moduleTests: Bool, github: Bool, fastlane: Bool, validatePackage: Bool, packageResolved packageResolvedURL: URL? = nil, apk: Bool, ipa: Bool, with out: MessageQueue) async throws -> (projectURL: URL, project: AppProjectLayout, artifacts: [URL: String?]) {

        // the initial build/test is done with debug configuration regardless of the configuration setting; this is because unit tests don't always run correctly in release mode
        let debugConfiguration = "debug"
        let re = messagePrefix ?? ""
        let free = appfair == true ? true : free
        let github = appfair == true ? true : free

        // the `appfair` flag changed the meaning of `baseName` to be the base name of the project and modules: "Sun-Bow" creates the modules "SunBow" and "SubBowModel" and the appid "io.github.Sun-Bow" and the project name "sun-bow-app"
        var modules = modules

        if appfair == true, !modules.isEmpty {
            modules[0].dependencies += [PackageModule(organizationName: "appfair", repositoryName: "appfair-app", repositoryVersion: "1.0.0", moduleName: "AppFairUI")]
        }

        let projectName = appfair == true ? baseName.lowercased() + "-app" : baseName

        let primaryModuleName = modules.first?.moduleName ?? "Module"

        let defaultAppId = projectName + "." + primaryModuleName
        let appid = appid ?? defaultAppId

        // the embedded framework must have a different name from the app name, or else it will try to archive a framework instead of an app
        let primaryModuleFrameworkName = primaryModuleName + AppProjectLayout.appProductSuffix

        let (projectURL, project) = try await AppProjectLayout.createSkipAppProject(projectName: projectName, productName: primaryModuleFrameworkName, modules: modules, resourceFolder: resourceFolder, dir: outputFolder, configuration: configuration, build: build, test: test, chain: chain, gitRepo: gitRepo, appfair: appfair == true, free: free, zero: skipZeroSupport, app: isApp, appid: appid, icon: icon, version: version, swiftVersion: swiftVersion, nativeMode: nativeMode, moduleMode: moduleMode, moduleTests: moduleTests, github: github, fastlane: fastlane, packageResolved: packageResolvedURL)
        let projectPath = try projectURL.absolutePath

        if build == true || apk == true {
            try await run(with: out, "\(re)Resolve dependencies", ["swift", "package", "resolve", "-v", "--package-path", projectURL.path])

            // we need to build regardless of preference in order to build the apk
            try await run(with: out, "\(re)Build \(projectName)", ["swift", "build", "-v", "-c", debugConfiguration, "--package-path", projectURL.path])
        }

        if test == true {
            try await runSkipTests(in: projectURL, configuration: debugConfiguration, swift: true, kotlin: true, with: out)
        }

        // the output URLs to any ipa/apk artifacts that are generated by the build
        var artifactHashes: [URL: String?] = [:]

        // the suffix for build artifacts
        // TODO: include version number from xcconfig
        // let cfgSuffix = "-" + (version ?? "0.0.1") + "-" + configuration
        let cfgSuffix = "-" + configuration.rawValue

        let xcodeProjectURL = project.darwinProjectFolder
        if ipa == true  {
            let ipaFiles = try await createIPA(configuration: configuration, schemeName: nil, primaryModuleName: primaryModuleName, cfgSuffix: cfgSuffix, projectURL: projectURL, out: out, prefix: re, xcodeProjectURL: xcodeProjectURL, returnHashes: returnHashes)
            artifactHashes.merge(ipaFiles, uniquingKeysWith: { $1 })
        }

        if apk == true {
            let apkFiles = try await createAPK(projectURL: projectURL, appModuleName: appModuleName, configuration: configuration, out: out, primaryModuleName: primaryModuleName, cfgSuffix: cfgSuffix, returnHashes: returnHashes, prefix: re)
            artifactHashes.merge(apkFiles, uniquingKeysWith: { $1 })
        }

        if gitRepo == true {
            // https://github.com/skiptools/skip/issues/407
            try await run(with: out, "Initializing git repository", ["git", "-C", projectURL.path, "init"])
            try await run(with: out, "Adding files to git repository", ["git", "-C", projectURL.path, "add", "."])
        }

        if verify {
            try await performVerifyCommand(project: projectPath.pathString, autofix: false, free: free, with: out.subqueue("Verify Project"))
        }

        if showTree {
            await showFileTree(in: projectPath, with: out)
        }

        return (projectURL, project, artifactHashes)
    }
}

struct PackageModule {
    var organizationName: String?
    var repositoryName: String?
    var moduleName: String
    var repositoryVersion: String?
    var dependencies: [PackageModule]
    var condition: String?

    init(organizationName: String? = nil, repositoryName: String? = nil, repositoryVersion: String? = nil, moduleName: String, dependencies: [PackageModule] = [], condition: String? = nil) {
        self.organizationName = organizationName
        self.repositoryName = repositoryName
        self.repositoryVersion = repositoryVersion
        self.moduleName = moduleName
        self.dependencies = dependencies
        self.condition = condition
    }

    init(parse: String) throws {
        let parts = parse.split(separator: ":").map(\.description)
        self.moduleName = parts.first ?? parse
        self.repositoryName = nil
        self.repositoryVersion = nil
        self.organizationName = nil
        self.dependencies = []
        self.condition = nil
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
