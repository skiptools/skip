// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation

/// A harness for invoking `gradle` and processing the output of builds and tests.
@available(macOS 13, macCatalyst 16, iOS 16, tvOS 16, watchOS 8, *)
public protocol GradleHarness {
    /// Scans the output line of the Gradle command and processes it for errors or issues.
    func scanGradleOutput(line: String)
}

@available(macOS 13, macCatalyst 16, iOS 16, tvOS 16, watchOS 8, *)
extension GradleHarness {
    /// Returns the URL to the folder that holds the top-level `settings.gradle.kts` file for the destination module.
    /// - Parameters:
    ///   - moduleTranspilerFolder: the output folder for the transpiler plug-in
    ///   - linkFolder: when specified, the module's root folder will first be linked into the linkFolder, which enables the output of the project to be browsable from the containing project (e.g., Xcode)
    /// - Returns: the folder that contains the buildable gradle project, either in the DerivedData/ folder, or re-linked through the specified linkFolder
    public func pluginOutputFolder(moduleTranspilerFolder: String, linkingInto linkFolder: URL?) throws -> URL {
        let env = ProcessInfo.processInfo.environment

        // if we are running tests from Xcode, this environment variable should be set; otherwise, assume the .build folder for an SPM build
        // also seems to be __XPC_DYLD_LIBRARY_PATH or __XPC_DYLD_FRAMEWORK_PATH;
        // this will be something like ~/Library/Developer/Xcode/DerivedData/PROJ-ABC/Build/Products/Debug
        //
        // so we build something like:
        //
        // ~/Library/Developer/Xcode/DerivedData/PROJ-ABC/Build/Products/Debug/../../../SourcePackages/plugins/skiphub.output/
        //
        if let xcodeBuildFolder = self.xcodeBuildFolder {
            let buildBaseFolder = URL(fileURLWithPath: xcodeBuildFolder, isDirectory: true)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let xcodeFolder = buildBaseFolder.appendingPathComponent("SourcePackages/plugins", isDirectory: true)
            return try findModuleFolder(in: xcodeFolder, extension: "output")
        } else {
            // when run from the CLI with a custom --build-path, there seems to be no way to know where the gradle folder was output, so we need to also specify it as an environment variable:
            // SWIFTBUILD=/tmp/swiftbuild swift test --build-path /tmp/swiftbuild
            let buildBaseFolder = env["SWIFTBUILD"] ?? ".build"
            // note that unlike Xcode, the local SPM output folder is just the package name without the ".output" suffix
            return try findModuleFolder(in: URL(fileURLWithPath: buildBaseFolder + "/plugins/outputs", isDirectory: true), extension: "")
        }

        /// The only known way to figure out the package name asociated with the test's module is to brute-force search through the plugin output folders.
        func findModuleFolder(in pluginOutputFolder: URL, extension pathExtension: String) throws -> URL {
            for outputFolder in try FileManager.default.contentsOfDirectory(at: pluginOutputFolder, includingPropertiesForKeys: [.isDirectoryKey]) {
                if !pathExtension.isEmpty && !outputFolder.lastPathComponent.hasSuffix("." + pathExtension) {
                    continue // only check known path extensions (e.g., ".output" with running from Xcode, and no extension from SPM)
                }

                let pluginModuleOutputFolder = URL(fileURLWithPath: moduleTranspilerFolder, isDirectory: true, relativeTo: outputFolder)
                //print("findModuleFolder: pluginModuleOutputFolder:", pluginModuleOutputFolder)
                if (try? pluginModuleOutputFolder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    // found the folder; now make a link from its parent folder to the project source…
                    if let linkFolder = linkFolder {
                        let localModuleLink = URL(fileURLWithPath: outputFolder.lastPathComponent, isDirectory: false, relativeTo: linkFolder)
                        //print("findModuleFolder: localModuleLink:", localModuleLink.path)

                        // make sure the output root folder exists
                        try FileManager.default.createDirectory(at: linkFolder, withIntermediateDirectories: true)

                        let linkFrom = localModuleLink.path, linkTo = outputFolder.path
                        //print("findModuleFolder: createSymbolicLink:", linkFrom, linkTo)

                        if (try? FileManager.default.destinationOfSymbolicLink(atPath: linkFrom)) != linkTo {
                            try? FileManager.default.removeItem(atPath: linkFrom) // if it exists
                            try FileManager.default.createSymbolicLink(atPath: linkFrom, withDestinationPath: linkTo)
                        }

                        let localTranspilerOut = URL(fileURLWithPath: outputFolder.lastPathComponent, isDirectory: true, relativeTo: localModuleLink)
                        let linkedPluginModuleOutputFolder = URL(fileURLWithPath: moduleTranspilerFolder, isDirectory: true, relativeTo: localTranspilerOut)
                        //print("findModuleFolder: linkedPluginModuleOutputFolder:", linkedPluginModuleOutputFolder.path)
                        return linkedPluginModuleOutputFolder
                    } else {
                        return pluginModuleOutputFolder
                    }
                }
            }
            throw NoModuleFolder(errorDescription: "Unable to find module folders in \(pluginOutputFolder.path)")
        }
    }

    public func linkFolder(from linkFolderBase: String? = "Packages/Skip", forSourceFile sourcePath: StaticString?) -> URL? {
        // walk up from the test case swift file until we find the folder that contains "Package.swift", which we treat as the package root
        if let sourcePath = sourcePath, let linkFolderBase = linkFolderBase {
            if let packageRootURL = packageBaseFolder(forSourceFile: sourcePath) {
                return packageRootURL.appendingPathComponent(linkFolderBase, isDirectory: true)
            }
        }

        return nil
    }

    /// For any given source file, find the nearest parent folder that contains a `Package.swift` file.
    /// - Parameter forSourceFile: the source file for the request, typically from the `#file` directive at the call site
    /// - Returns: the URL containing the `Package.swift` file, or `.none` if it could not be found.
    public func packageBaseFolder(forSourceFile sourcePath: StaticString) -> URL? {
        var packageRootURL = URL(fileURLWithPath: sourcePath.description, isDirectory: false)

        let isPackageRoot = {
            (try? packageRootURL.appendingPathComponent("Package.swift", isDirectory: false).checkResourceIsReachable()) == true
        }

        while true {
            let parent = packageRootURL.deletingLastPathComponent()
            if parent.path == packageRootURL.path {
                return nil // top of the fs and not found
            }
            packageRootURL = parent
            if isPackageRoot() {
                return packageRootURL
            }
        }
    }

    /// Uses the system `adb` process to install and launch the given APK, following the
    public func launchAPK(device: String?, appid: String, log: [String] = [], apk: String, relativeTo sourcePath: StaticString = #file) async throws {
        let env: [String: String] = [:]

        let apkPath = URL(fileURLWithPath: apk, isDirectory: false, relativeTo: packageBaseFolder(forSourceFile: sourcePath))

        guard FileManager.default.isReadableFile(atPath: apkPath.path) else {
            throw ADBError(errorDescription: "APK did not exist at \(apkPath.path)")
        }

        // List of devices attached:
        // adb-R9TT50AJWEX-F9Ujyu._adb-tls-connect._tcp.    device
        // emulator-5554    device
        let adbDevices = [
            "adb",
            "devices",
        ]

        for try await outputLine in Process.streamLines(command: adbDevices, environment: env, onExit: { result in
            guard case .terminated(0) = result.exitStatus else {
                // we failed, but did not expect an error
                throw ADBError(errorDescription: "error listing devices: \(result)")
            }
        }) {
            print("ADB DEVICE>", outputLine)
        }

        let adb = ["adb"] + (device.flatMap { ["-s", $0] } ?? [])

        // adb install -r Packages/Skip/skipapp.swiftpm.output/AppDemoKtTests/skip-transpiler/AppDemo/.build/AppDemo/outputs/apk/debug/AppDemo-debug.apk
        let adbInstall = adb + [
            "install",
            "-r", // replace existing application
            "-t", // allow test packages
            apkPath.path,
        ]

        print("running:", adbInstall.joined(separator: " "))

        for try await outputLine in Process.streamLines(command: adbInstall, environment: env, onExit: { result in
            guard case .terminated(0) = result.exitStatus else {
                // we failed, but did not expect an error
                throw ADBError(errorDescription: "error installing APK: \(result)")
            }
        }) {
            print("ADB>", outputLine)
        }

        // adb shell am start -n app.demo/.MainActivity
        let adbStart = adb + [
            "shell",
            "am",
            "start-activity",
            "-S", // force stop the target app before starting the activity
            "-W", // wait for launch to complete
            "-n", appid,
        ]

        for try await outputLine in Process.streamLines(command: adbStart, environment: env, onExit: { result in
            guard case .terminated(0) = result.exitStatus else {
                throw ADBError(errorDescription: "error launching APK: \(result)")
            }
        }) {
            print("ADB>", outputLine)
        }

        // GOOD:
        // ADB> Starting: Intent { cmp=app.demo/.MainActivity }

        // BAD:
        // ADB> Error: Activity not started, unable to resolve Intent { act=android.intent.action.VIEW dat= flg=0x10000000 }


        if !log.isEmpty {
            // adb shell am start -n app.demo/.MainActivity
            let logcat = adb + [
                "logcat",
                "-T", "1000", // start with only the 1000 most recent entries
                // "-v", "time",
                // "-d", // dump then exit
            ]
            + log // e.g., ["*:W"] or ["app.demo*:E"],


            for try await outputLine in Process.streamLines(command: logcat, environment: env, onExit: { result in
                guard case .terminated(0) = result.exitStatus else {
                    throw ADBError(errorDescription: "error watching log: \(result)")
                }
            }) {
                print("LOGCAT>", outputLine)
            }
        }
    }

    /// The default implementation of output scanning will match lines against the Gradle error/warning patten,
    /// and then output them as Xcode-formatted error/warning patterns.
    ///
    /// An attempt will be made to map the Kotlin line to original Swift line by parsing the `.sourcemap` JSON.
    ///
    /// For example, the following Gradle output:
    /// ```
    /// e: file:///tmp/Foo.kt:12:13 Compile Error
    /// ```
    ///
    /// will be converted to the following Xcode error line:
    /// ```
    /// /tmp/Foo.swift:12:0: error: Compile Error
    /// ```
    public func scanGradleOutput(line: String) {
        func report(_ issue: GradleIssue) {
            print("\(issue.location.path):\(issue.location.position.line):\(issue.location.position.column): \(issue.kind.xcode): \(issue.message)")
        }

        if let kotlinIssue = parseGradleOutput(line: line) {
            if let swiftIssue = try? kotlinIssue.location.findSourceMapLine() {
                report(GradleIssue(kind: kotlinIssue.kind, message: kotlinIssue.message, location: swiftIssue))
            }
            report(kotlinIssue)
        }
    }


    /// Parse the given gradle output line for error or warning pattern, optionally mapping back to the source Swift locationl
    public func parseGradleOutput(line: String) -> GradleIssue? {
        guard let match = gradleRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }
        let l = (line as NSString)
        // turn "e" and "w" into a error or warning
        guard let kind = GradleIssue.Kind(rawValue: l.substring(with: match.range(at: 1))) else {
            return nil
        }
        let path = l.substring(with: match.range(at: 2))
        guard let line = Int(l.substring(with: match.range(at: 3))) else {
            return nil
        }
        guard let col = Int(l.substring(with: match.range(at: 4))) else {
            return nil
        }
        let message = l.substring(with: match.range(at: 5))

        return GradleIssue(kind: kind, message: message, location: SourceLocation(path: path, position: SourceLocation.Position(line: line, column: col)))
    }

    /// Whether the current build should be a release build or a debug build
    public var releaseBuild: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    /// The build folder for Xcode
    var xcodeBuildFolder: String? {
        ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"]
            ?? ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"]
    }

    public func projectRoot(forModule moduleName: String, packageName: String) throws -> URL {
        let env = ProcessInfo.processInfo.environment

        //for (key, value) in env.sorted(by: { $0.0 < $1.0 }) {
        //    print("ENV: \(key)=\(value)")
        //}

        let isXcode = env["__CFBundleIdentifier"] == "com.apple.dt.Xcode" || xcodeBuildFolder != nil

        // Diagnostics.warning("ENVIRONMENT: \(env)")
        let packageFolderExtension = isXcode ? ".output" : ""

        guard let buildFolder = xcodeBuildFolder else {
            throw AppLaunchError(errorDescription: "The BUILT_PRODUCTS_DIR environment variable must be set to the output of the build process")
        }

        return URL(fileURLWithPath: "../../../SourcePackages/plugins/\(packageName)\(packageFolderExtension)/\(moduleName)/skip-transpiler/", isDirectory: true, relativeTo: URL(fileURLWithPath: buildFolder, isDirectory: true))
    }

    public func launch(appName: String, appId: String, packageName: String, deviceID: String? = ProcessInfo.processInfo.environment["SKIP_TEST_DEVICE"]) async throws {
        /// The default log levels when launching the .apk
        let logLevel = [
                "\(appId):V", // all app log messages
                "\(appId).\(appName):V", // all app log messages
                "AndroidRuntime:V", // info from runtime
                "*:S", // all other log messages are silenced
        ]

        let moduleName = appName + "Kt"

        let path = "\(appName)/.build/\(appName)/outputs/apk/"
        let artifact = releaseBuild ? "release/\(appName)-release.apk" : "debug/\(appName)-debug.apk"
        let apk = try URL(fileURLWithPath: path + artifact, isDirectory: false, relativeTo: projectRoot(forModule: moduleName, packageName: packageName))

        guard let fileSize = try? apk.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw AppLaunchError(errorDescription: "APK did not exist at path: \(apk.path)")
        }

        print("launching APK (\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))): \(apk.path)")

        // select device with: SKIP_TEST_DEVICE=emulator-5554
        // this avoids the error: adb: more than one device/emulator
        try await launchAPK(device: deviceID, appid: "\(appId)/.MainActivity", log: logLevel, apk: apk.path)
    }

    public func gradleExec(appName: String, packageName: String, arguments: [String], outputPrefix: String? = "GRADLE>") async throws {
        let driver = try await GradleDriver()

        let moduleName = appName + "Kt"
        let acts: [String] = [] // releaseBuild ? ["assembleRelease"] : ["assembleDebug"] // expected in the arguments to the command

        var exitCode: ProcessResult.ExitStatus? = nil
        let (output, _) = try await driver.launchGradleProcess(in: projectRoot(forModule: moduleName, packageName: packageName), module: appName, actions: acts, arguments: arguments, info: false, rerunTasks: false, exitHandler: { result in
            print("GRADLE RESULT: \(result)")
            exitCode = result.exitStatus
        })

        for try await line in output {
            if let outputPrefix = outputPrefix {
                print(outputPrefix, line)
            }
            scanGradleOutput(line: line) // check for errors and report them to the IDE
        }

        guard let exitCode = exitCode, case .terminated(0) = exitCode else {
            throw AppLaunchError(errorDescription: "Gradle run error: \(String(describing: exitCode))")
        }
    }

}

public struct MissingEnvironmentError : LocalizedError {
    public var errorDescription: String?
}

public struct AppLaunchError : LocalizedError {
    public var errorDescription: String?
}


fileprivate let gradleRegex = try! NSRegularExpression(pattern: #"^([we]): file://(.*):([0-9]+):([0-9]+) (.*)$"#)

/// A source-related issue reported during the execution of Gradle. In the form of:
///
/// ```
/// e: file:///tmp/Foo.kt:12:13 Compile Error
/// ```
public struct GradleIssue {
    public var kind: Kind
    public var message: String
    public var location: SourceLocation

    public enum Kind : String, CaseIterable {
        case error = "e"
        case warning = "w"

        // return the token for reporting the issue in xcode
        public var xcode: String {
            switch self {
            case .error: return "error"
            case .warning: return "warning"
            }
        }
    }
}

public struct NoModuleFolder : LocalizedError {
    public var errorDescription: String?
}

public struct ADBError : LocalizedError {
    public var errorDescription: String?
}
