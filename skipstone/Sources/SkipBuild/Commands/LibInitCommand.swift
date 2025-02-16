import Foundation
import ArgumentParser
import SkipSyntax
import TSCBasic
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct LibInitCommand: MessageCommand, CreateOptionsCommand, ProjectCommand, ToolOptionsCommand, BuildOptionsCommand, StreamingCommand {
    static var configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize a new Skip project",
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
    var moduleNames: [String] = []

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

    func runInit(with out: MessageQueue) async throws {
        await out.yield(MessageBlock(status: nil, "Initializing Skip \(appid == nil && !createOptions.appfair ? "library" : "application") \(self.projectName)"))

        let dir = URL(fileURLWithPath: self.createOptions.dir ?? self.projectName, isDirectory: true)

        let modules = try self.modules
        let icon: IconParameters? = noIcon == true ? nil : IconParameters(iconBackgroundColor: iconBackground, iconForegroundColor: iconForeground, iconSources: icon, iconShadow: iconShadow, iconInset: iconInset)

        let mode = self.createOptions.native && self.createOptions.kotlincompat ? ModuleMode.kotlincompat : self.createOptions.native ? .native : .transpiled
        let (createdURL, project, _) = try await initSkipProject(baseName: self.projectName, modules: modules, resourceFolder: createOptions.resourcePath, dir: dir, verify: buildOptions.verify, configuration: createOptions.configuration, build: buildOptions.build, test: buildOptions.test, returnHashes: false, showTree: self.createOptions.showTree, chain: createOptions.chain, gitRepo: createOptions.gitRepo, free: createOptions.free, appfair: createOptions.appfair, zero: createOptions.zero, appid: self.appid, icon: icon, version: self.version, mode: mode, moduleTests: self.createOptions.moduleTests, github: self.createOptions.github, fastlane: self.createOptions.fastlane, validatePackage: self.createOptions.validatePackage, apk: apk, ipa: ipa, with: out)

        await out.yield(MessageBlock(status: .pass, "Created module \(modules.map(\.moduleName).joined(separator: ", ")) in \(createdURL.path)"))

        if openXcode {
            try await run(with: out, "Opening Xcode project", ["open", project.darwinProjectFolder.path])
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
        
        await checkFile(apkURL, with: out, title: "Verify \(apkTitle)") { url in
            return CheckStatus(status: .pass, message: try "Verify \(apkTitle) \(url.fileSizeString)")
        }

        var hashes: [URL : String?] = [:]
        hashes[apkURL] = nil
        if returnHashes {
            await checkFile(apkURL, with: out, title: "\(re)Checksum Archive") { url in
                let apkHash = try url.SHA256Hash()
                hashes[apkURL] = apkHash
                return CheckStatus(status: .pass, message: "APK SHA256: \(apkHash)")
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
        return try await run(with: out, msg, ["zip", "-\(compressionLevel)", "-r", zipFile.path, folder.lastPathComponent], in: folder.deletingLastPathComponent(), resultHandler: returnFileSize)
    }

    func createIPA(configuration: BuildConfiguration, primaryModuleName: String, sdk: String = "iphoneos", cfgSuffix: String, projectURL: URL, out: MessageQueue, prefix re: String, xcodeProjectURL: URL, ipaURL ipaOutputURL: URL? = nil, xcarchiveURL: URL? = nil, teamID: String? = nil, verifyFile: Bool = true, returnHashes: Bool) async throws -> [URL : String?] {
        // xcodebuild -derivedDataPath .build/DerivedData -skipPackagePluginValidation -skipMacroValidation -archivePath "${ARCHIVE_PATH}" -configuration "${CONFIGURATION}" -scheme "${SKIP_MODULE}" -sdk "iphoneos" -destination "generic/platform=iOS" -jobs 1 archive CODE_SIGNING_ALLOWED=NO
        let cfg = configuration.rawValue.capitalized
        let archiveBasePath = darwinBuildFolder + "/Archives/" + cfg

        let archivePath = archiveBasePath + "/" + primaryModuleName + ".xcarchive"

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
            "-scheme", primaryModuleName,
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
        }

        // if no teamid is specified, then just zip up the output folder
        try await zipFolder(with: out, message: "\(re)Assemble \(ipaURL.lastPathComponent)", zipFile: ipaURL, folder: archiveAppPayloadURL)

        // also zip up the .xcarchive path
        if let xcarchiveURL = xcarchiveURL {
            try await zipFolder(with: out, message: "\(re)Archive \(xcarchiveURL.lastPathComponent)", zipFile: xcarchiveURL, folder: URL(fileURLWithPath: fullArchivePath))
        }

        if verifyFile {
            await checkFile(ipaURL, with: out, title: "\(re)Verifying \(ipaURL.lastPathComponent)") { url in
                CheckStatus(status: .pass, message: try "Verify \(ipaURL.lastPathComponent) \(url.fileSizeString)")
            }
        }

        var hashes: [URL : String?] = [:]
        hashes[ipaURL] = nil
        if returnHashes {
            await checkFile(ipaURL, with: out, title: "\(re)Checksum Archive") { url in
                let ipaHash = try url.SHA256Hash()
                hashes[ipaURL] = ipaHash
                return CheckStatus(status: .pass, message: "IPA SHA256: \(ipaHash)")
            }
        }
        return hashes
    }

    func initSkipProject(baseName: String, modules: [PackageModule], resourceFolder: String?, dir outputFolder: URL, verify: Bool, configuration: BuildConfiguration, build: Bool, test: Bool, returnHashes: Bool, messagePrefix: String? = nil, showTree: Bool, chain: Bool, gitRepo: Bool, free: Bool, appfair: Bool? = nil, zero skipZeroSupport: Bool, appid: String?, appModuleName: String = "app", icon: IconParameters?, version: String?, mode: ModuleMode, moduleTests: Bool, github: Bool, fastlane: Bool, validatePackage: Bool, packageResolved packageResolvedURL: URL? = nil, apk: Bool, ipa: Bool, with out: MessageQueue) async throws -> (projectURL: URL, project: AppProjectLayout, artifacts: [URL: String?]) {

        // the initial build/test is done with debug configuration regardless of the configuration setting; this is because unit tests don't always run correctly in release mode
        let debugConfiguration = "debug"
        let re = messagePrefix ?? ""
        let appid = appid ?? (appfair == true ? "io.github.\(baseName)" : nil)
        let projectNameModule = baseName.replacingOccurrences(of: "-", with: "")
        let free = appfair == true ? true : free
        let github = appfair == true ? true : free

        // the `appfair` flag changed the meaning of `baseName` to be the base name of the project and modules: "Sun-Bow" creates the modules "SunBow" and "SubBowModel" and the appid "io.github.Sun-Bow" and the project name "sun-bow-app"
        let modules = !modules.isEmpty ? modules : (appfair == true ? [PackageModule(moduleName: projectNameModule, dependencies: [PackageModule(organizationName: "appfair", repositoryName: "appfair-app", repositoryVersion: "1.0.0", moduleName: "AppFairUI")]), PackageModule(moduleName: projectNameModule + "Model")] : [])
        let projectName = appfair == true ? baseName.lowercased() + "-app" : baseName

        let primaryModuleName = modules.first?.moduleName ?? "Module"
        // the embedded framework must have a different name from the app name, or else it will try to archive a framework instead of an app
        let primaryModuleFrameworkName = primaryModuleName + "App"

        let (projectURL, project) = try await AppProjectLayout.createSkipAppProject(projectName: projectName, productName: primaryModuleFrameworkName, modules: modules, resourceFolder: resourceFolder, dir: outputFolder, configuration: configuration, build: build, test: test, chain: chain, gitRepo: gitRepo, appfair: appfair == true, free: free, zero: skipZeroSupport, appid: appid, icon: icon, version: version, mode: mode, moduleTests: moduleTests, github: github, fastlane: fastlane, packageResolved: packageResolvedURL)
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
            let ipaFiles = try await createIPA(configuration: configuration, primaryModuleName: primaryModuleName, cfgSuffix: cfgSuffix, projectURL: projectURL, out: out, prefix: re, xcodeProjectURL: xcodeProjectURL, returnHashes: returnHashes)
            artifactHashes.merge(ipaFiles, uniquingKeysWith: { $1 })
        }

        if apk == true {
            let apkFiles = try await createAPK(projectURL: projectURL, appModuleName: appModuleName, configuration: configuration, out: out, primaryModuleName: primaryModuleName, cfgSuffix: cfgSuffix, returnHashes: returnHashes, prefix: re)
            artifactHashes.merge(apkFiles, uniquingKeysWith: { $1 })
        }

        if verify {
            try await performVerifyCommand(project: projectPath.pathString, with: out.subqueue("Verify Project"), free: free)
        }

        if showTree {
            await showFileTree(in: projectPath, with: out)
        }

        return (projectURL, project, artifactHashes)
    }
}

extension ToolOptionsCommand {
    /// Perform a monitor check on the given URL
    @discardableResult func check<T, U>(_ item: T, with out: MessageQueue, title: String, handle: @escaping (T) throws -> U) async -> Result<U, Error> {
        await outputOptions.monitor(with: out, title, resultHandler: { result in
            return (nil, nil) as (result: Result<U, any Error>?, message: MessageBlock?)
        }) { line in
            try handle(item)
        }
    }


    /// Perform a monitor check on the given URL
    @discardableResult func checkFile(_ url: URL, with out: MessageQueue, title: String? = nil, handle: @escaping (URL) throws -> CheckStatus) async -> Bool {
        let title = title ?? "Check \(url.lastPathComponent)"
        let result = await outputOptions.monitor(with: out, title, resultHandler: { result in
            do {
                if let resultURL = try result?.get() {
                    let handleResult = try handle(resultURL)
                    return (result, MessageBlock(status: handleResult.status, handleResult.message ?? title))
                } else {
                    return (result, nil)
                }
            } catch {
                return (Result.failure(error), nil)
            }
        }) { loggingHandler in
            return url
        }
        return (try? result.get()) != nil
    }
}

struct CheckStatus {
    var status: MessageBlock.Status
    var message: String? = nil
}

struct PackageModule {
    var organizationName: String?
    var repositoryName: String?
    var moduleName: String
    var repositoryVersion: String?
    var dependencies: [PackageModule]

    init(organizationName: String? = nil, repositoryName: String? = nil, repositoryVersion: String? = nil, moduleName: String, dependencies: [PackageModule] = []) {
        self.organizationName = organizationName
        self.repositoryName = repositoryName
        self.repositoryVersion = repositoryVersion
        self.moduleName = moduleName
        self.dependencies = dependencies
    }

    init(parse: String) throws {
        let parts = parse.split(separator: ":").map(\.description)
        self.moduleName = parts.first ?? parse
        self.repositoryName = nil
        self.repositoryVersion = nil
        self.organizationName = nil
        self.dependencies = []
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
