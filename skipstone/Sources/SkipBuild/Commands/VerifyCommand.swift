import Foundation
import ArgumentParser
//import TSCUtility

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct VerifyCommand: SkipCommand, StreamingCommand, ProjectCommand, ToolOptionsCommand {

    static var configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Verify the Skip project",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(help: ArgumentHelp("Project folder", valueName: "dir"))
    var project: String = "."

    func performCommand(with out: MessageQueue) async {
        do {
            try await performVerifyCommand(project: project, with: out)
        } catch {
            await out.yield(MessageBlock(status: .fail, error.localizedDescription))
        }
        await reportMessageQueue(with: out, title: "Verify skip project (\(skipVersion)) checks complete")
    }
}


struct NoResultOutputError : LocalizedError {
    var errorDescription: String?
}

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
}

/** Skip app project layout:

```
 .
 ├── Android
 │   ├── README.md
 │   ├── app
 │   │   ├── build.gradle.kts
 │   │   └── src
 │   │       └── main
 │   │           ├── AndroidManifest.xml
 │   │           ├── kotlin
 │   │           │   └── hello
 │   │           │       └── skip
 │   │           │           └── Main.kt
 │   │           └── res
 │   │               ├── mipmap-anydpi-v26
 │   │               │   └── ic_launcher.xml
 │   │               ├── mipmap-mdpi
 │   │               │   ├── ic_launcher.png
 │   │               │   ├── ic_launcher_background.png
 │   │               │   ├── ic_launcher_foreground.png
 │   │               │   └── ic_launcher_monochrome.png
 │   ├── gradle
 │   │   └── wrapper
 │   │       └── gradle-wrapper.properties
 │   ├── gradle.properties
 │   ├── install_apk.sh
 │   ├── local.properties
 │   └── settings.gradle.kts
 ├── Darwin
 │   ├── Assets.xcassets
 │   │   ├── AccentColor.colorset
 │   │   │   └── Contents.json
 │   │   ├── AppIcon.appiconset
 │   │   │   ├── AppIcon-29@2x~ipad.png
 │   │   │   ├── AppIcon-29@3x.png
 │   │   │   └── Contents.json
 │   │   └── Contents.json
 │   ├── Entitlements.plist
 │   ├── HelloSkip.xcconfig
 │   ├── HelloSkip.xcodeproj
 │   │   └── project.pbxproj
 │   ├── README.md
 │   └── Sources
 │       └── HelloSkipAppMain.swift
 ├── Package.resolved
 ├── Package.swift
 ├── README.md
 ├── Sources
 │   └── HelloSkip
 │       ├── ContentView.swift
 │       ├── HelloSkip.swift
 │       ├── HelloSkipApp.swift
 │       ├── Resources
 │       │   └── Localizable.xcstrings
 │       └── Skip
 │           └── skip.yml
 └── Tests
     └── HelloSkipTests
         ├── HelloSkipTests.swift
         ├── Resources
         │   └── TestData.json
         ├── Skip
         │   └── skip.yml
         └── XCSkipTests.swift
```
 */
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
    let androidGradleSettings: URL
    let androidAppFolder: URL
    let androidAppBuild: URL
    let androidAppSrc: URL
    let androidAppSrcMain: URL
    let androidManifest: URL
    let androidAppSrcMainRes: URL
    let androidAppSrcMainKotlin: URL


    init(moduleName: String, root: URL, check: (URL, Bool) throws -> () = checkURLExists) rethrows {
        self.moduleName = moduleName

        self.skipEnv = try root.resolve("Skip.env", check: check)

        self.sourcesFolder = try root.resolve("Sources/", check: check)
        self.moduleSourcesFolder = try sourcesFolder.resolve(moduleName + "/", check: check)
        self.moduleSourcesSkipFolder = try moduleSourcesFolder.resolve("Skip/", check: check)
        self.moduleSourcesSkipConfig = try moduleSourcesSkipFolder.resolve("skip.yml", check: check)

        self.testsFolder = root.resolve("Tests/", check: Self.noURLChecks) // Tests are optional
        self.moduleTestsFolder = testsFolder.resolve(moduleName + "Tests/", check: Self.noURLChecks)

        self.darwinFolder = try root.resolve("Darwin/", check: check)
        self.darwinREADME = darwinFolder.resolve("README.md", check: Self.noURLChecks)
        self.darwinSourcesFolder = try darwinFolder.resolve("Sources/", check: check)
        self.darwinMainAppSwift = try darwinSourcesFolder.resolve(moduleName + "AppMain.swift", check: check)
        self.darwinProjectConfig = try darwinFolder.resolve(moduleName + ".xcconfig", check: check)
        self.darwinProjectFolder = try darwinFolder.resolve(moduleName + ".xcodeproj/", check: check)
        self.darwinProjectContents = try darwinProjectFolder.resolve("project.pbxproj", check: check)
        self.darwinEntitlementsPlist = try darwinFolder.resolve("Entitlements.plist", check: check)
        self.darwinAssetsFolder = try darwinFolder.resolve("Assets.xcassets/", check: check)
        self.darwinAccentColorFolder = try darwinAssetsFolder.resolve("AccentColor.colorset/", check: check)
        self.darwinAccentColorContents = try darwinAccentColorFolder.resolve("Contents.json", check: check)
        self.darwinAppIconFolder = try darwinAssetsFolder.resolve("AppIcon.appiconset/", check: check)
        self.darwinAppIconContents = try darwinAppIconFolder.resolve("Contents.json", check: check)

        self.androidFolder = try root.resolve("Android/", check: check)
        self.androidREADME = androidFolder.resolve("README.md", check: Self.noURLChecks)
        self.androidGradleProperties = try androidFolder.resolve("gradle.properties", check: check)
        self.androidGradleSettings = try androidFolder.resolve("settings.gradle.kts", check: check)
        self.androidAppFolder = try androidFolder.resolve("app/", check: check)
        self.androidAppBuild = try androidAppFolder.resolve("build.gradle.kts", check: check)
        self.androidAppSrc = try androidAppFolder.resolve("src/", check: check)
        self.androidAppSrcMain = try androidAppSrc.resolve("main/", check: check)
        self.androidManifest = try androidAppSrcMain.resolve("AndroidManifest.xml", check: check)
        self.androidAppSrcMainRes = try androidAppSrcMain.resolve("res/", check: check)
        //self.androidAppSrcIconMDPI = try androidAppSrcRes.resolve("mipmap-mdpi/", check: check)
        self.androidAppSrcMainKotlin = try androidAppSrcMain.resolve("kotlin/", check: check)

        //self.androidAppSrcMainKotlinModule = try androidAppSrcMainKotlin.resolve("src/", check: check)

        try super.init(root: root, check: check)
    }
}

extension ToolOptionsCommand {

    /// Invokes the given command that launches an executable and is expected to output JSON, which we parse into the specified data structure
    func decodeCommand<T: Decodable>(with out: MessageQueue, title: String, cmd: [String]) async -> Result<T, Error> {

        func decodeResult(_ result: Result<ProcessOutput, Error>) -> Result<T, Error> {
            do {
                let res = try result.get()
                let decoder = JSONDecoder()
                let decoded = try decoder.decode(T.self, from: res.stdout.utf8Data)
                return .success(decoded) // (result: .success(decoded), message: nil)
            } catch {
                return .failure(error) // (result: .failure(error), message: MessageBlock(status: .fail, title + ": error executing \(cmd.joined(separator: " ")): \(error)"))
            }
        }

        let output = await run(with: out, title, cmd)
        return decodeResult(output)
    }

    /// Run swift package dump-package and return the parsed JSON results
    func parseSwiftPackage(with out: MessageQueue, at projectPath: String) async throws -> PackageManifest {
        try await decodeCommand(with: out, title: "Check Swift Package", cmd: ["swift", "package", "dump-package", "--package-path", projectPath]).get()
    }

    func performVerifyCommand(project projectPath: String, with out: MessageQueue) async throws {
        let projectFolderURL = URL(fileURLWithPath: projectPath, isDirectory: true)

        let packageJSON = try await parseSwiftPackage(with: out, at: projectPath)
        let packageName = packageJSON.name
        guard let moduleName = packageJSON.products.first?.name else {
            throw AppVerifyError(errorDescription: "No products declared in package \(packageName) at \(projectPath)")
        }

        let androidDir = projectFolderURL.appendingPathComponent("Android", isDirectory: true)
        let darwinDir = projectFolderURL.appendingPathComponent("Darwin", isDirectory: true)
        let isAppProject = androidDir.fileExists(isDirectory: true) && darwinDir.fileExists(isDirectory: true)

        if isAppProject {
            let project = try AppProjectLayout(moduleName: moduleName, root: projectFolderURL)
        } else {
            let project = try FrameworkProjectLayout(root: projectFolderURL)

        }

        #if os(macOS)

        // -list for a pure SPM will look like: {"workspace":{"name":"skip-script","schemes":["skip-script"]}}
        // -list with a project will look like: {"project":{"configurations":["Debug","Release","Skippy"],"name":"DataBake","schemes":["DataBake","DataBakeApp","DataBakeModel"],"targets":["DataBakeApp"]}}
        // with a workspace will give the error: xcodebuild: error: The directory /opt/src/github/skiptools/skipstone contains 3 workspaces. Specify the workspace to use with the -workspace option
        //let _ = try await run(with: out, "Check schemes", ["xcodebuild", "-list", "-json", project]).get().stdout

        //let _ = try await run(with: out, "Check xcconfig", ["xcodebuild", "-showBuildSettings", "-json", project]).get().stdout

        // Check xcode project config: xcodebuild -describeAllArchivableProducts -json
        //let _ = try await run(with: out, "Check Xcode Project", ["xcodebuild", "-describeAllArchivableProducts", "-json", project]).get().stdout
        #endif
    }
}
