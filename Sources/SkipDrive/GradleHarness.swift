// Copyright 2023–2025 Skip
#if !SKIP
import Foundation

/// The `GradleHarness` is the interface to launching the `gradle` command and processing the output.
///
/// It is used by the `skip` command when it needs to launch Gradle (e.g., with `skip export`),
/// as well as from the `XCSkiptests` unit test runner, which will use it to launch the JUnit test runner
/// on the transpied Kotlin.
@available(macOS 13, macCatalyst 16, iOS 16, tvOS 16, watchOS 8, *)
public protocol GradleHarness {
    /// Scans the output line of the Gradle command and processes it for errors or issues.
    func scanGradleOutput(line1: String, line2: String)
}

let pluginFolderName = "skipstone"

@available(macOS 13, macCatalyst 16, iOS 16, tvOS 16, watchOS 8, *)
extension GradleHarness {
    /// Returns the URL to the folder that holds the top-level `settings.gradle.kts` file for the destination module.
    /// - Parameters:
    ///   - moduleTranspilerFolder: the output folder for the transpiler plug-in
    ///   - linkFolder: when specified, the module's root folder will first be linked into the linkFolder, which enables the output of the project to be browsable from the containing project (e.g., Xcode)
    /// - Returns: the folder that contains the buildable gradle project, either in the DerivedData/ folder, or re-linked through the specified linkFolder
    public func pluginOutputFolder(moduleName: String, linkingInto linkFolder: URL?) throws -> URL {
        let env = ProcessInfo.processInfo.environment

        func isDir(_ url: URL) -> Bool {
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

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
            var pluginsFolder = buildBaseFolder.appendingPathComponent("Build/Intermediates.noindex/BuildToolPluginIntermediates", isDirectory: true) // Xcode 16.3+
            if !isDir(pluginsFolder) {
                pluginsFolder = buildBaseFolder.appendingPathComponent("SourcePackages/plugins", isDirectory: true) // Xcode 16.2-
            }
            return try findModuleFolder(in: pluginsFolder, extension: "output")
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

                // check for new "destination" output folder that Xcode16b3's SwiftPM started adding to the plugin output hierarchy
                // See: https://forums.swift.org/t/swiftpm-included-with-xcode-16b3-changes-plugin-output-folder-to-destination/73220
                // If it is not there, then check older SwiftPM 5's destination folder without the
                var moduleTranspilerFolder = moduleName + "/destination/skipstone"
                var pluginModuleOutputFolder = URL(fileURLWithPath: moduleTranspilerFolder, isDirectory: true, relativeTo: outputFolder)
                if !isDir(pluginModuleOutputFolder) {
                    moduleTranspilerFolder = moduleName + "/skipstone"
                    pluginModuleOutputFolder = URL(fileURLWithPath: moduleTranspilerFolder, isDirectory: true, relativeTo: outputFolder)
                }

                //print("findModuleFolder: pluginModuleOutputFolder:", pluginModuleOutputFolder)
                if isDir(pluginModuleOutputFolder) {
                    // found the folder; now make a link from its parent folder to the project source…
                    if let linkFolder = linkFolder {
                        let localModuleLink = URL(fileURLWithPath: outputFolder.lastPathComponent, isDirectory: false, relativeTo: linkFolder)
                        // make sure the output root folder exists
                        try FileManager.default.createDirectory(at: linkFolder, withIntermediateDirectories: true)

                        let linkFrom = localModuleLink.path, linkTo = outputFolder.path
                        if (try? FileManager.default.destinationOfSymbolicLink(atPath: linkFrom)) != linkTo {
                            try? FileManager.default.removeItem(atPath: linkFrom) // if it exists
                            try FileManager.default.createSymbolicLink(atPath: linkFrom, withDestinationPath: linkTo)
                        }

                        let localTranspilerOut = URL(fileURLWithPath: outputFolder.lastPathComponent, isDirectory: true, relativeTo: localModuleLink)
                        let linkedPluginModuleOutputFolder = URL(fileURLWithPath: moduleTranspilerFolder, isDirectory: true, relativeTo: localTranspilerOut)
                        return linkedPluginModuleOutputFolder
                    } else {
                        return pluginModuleOutputFolder
                    }
                }
            }
            throw NoModuleFolder(errorDescription: "Unable to find module folders in \(pluginOutputFolder.path)")
        }
    }

    public func linkFolder(from linkFolderBase: String? = "Skip/build", forSourceFile sourcePath: StaticString?) -> URL? {
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
    ///
    /// From https://developer.apple.com/documentation/xcode/running-custom-scripts-during-a-build#Log-errors-and-warnings-from-your-script :
    ///
    /// Log errors and warnings from your script
    ///
    /// During your script’s execution, you can report errors, warnings, and general notes to the Xcode build system. Use these messages to diagnose problems or track your script’s progress. To write messages, use the echo command and format your message as follows:
    ///
    /// ```
    /// [filename]:[linenumber]: error | warning | note : [message]
    /// ```
    ///
    /// If the error:, warning:, or note: string is present, Xcode adds your message to the build logs. If the issue occurs in a specific file, include the filename as an absolute path. If the issue occurs at a specific line in the file, include the line number as well. The filename and line number are optional.
    public func scanGradleOutput(line1: String, line2: String) {
        if let kotlinIssue = parseKotlinIssue(line1: line1, line2: line2) {
            // check for match Swift source lines; this will result in reporting two separate errors: one for the matched Swift source line, and one in the transpiled Kotlin
            if let swiftIssue = try? kotlinIssue.location?.findSourceMapLine() {
                print(GradleIssue(kind: kotlinIssue.kind, message: kotlinIssue.message, location: swiftIssue).xcodeMessageString)
            }
            print(kotlinIssue.xcodeMessageString)
        }
    }


    /// Parse a 2-line output buffer for the gradle command and look for error or warning pattern, optionally mapping back to the source Swift location when the location is found in a known .skipcode.json file.
    public func parseKotlinIssue(line1: String, line2: String) -> GradleIssue? {
        // check against known Kotlin error patterns
        // e.g.: "e: file:///PATH/build.gradle.kts:102:17: Unresolved reference: option"
        if let issue = parseKotlinErrorOutput(line: line1) {
            return issue
        }
        // check against other Gradle error output patterns
        if let issue = parseGradleErrorOutput(line1: line1, line2: line2) {
            return issue
        }
        return nil
    }

    private func parseGradleErrorOutput(line1: String, line2: String) -> GradleIssue? {
        // general task failure
        if line1 == "* What went wrong:" {
            return GradleIssue(kind: .error, message: line2)
        }

        if line1.hasPrefix("> Failed to apply plugin") {
            // e.g.:
            // * What went wrong:
            // An exception occurred applying plugin request [id: 'skip-plugin']
            // > Failed to apply plugin 'skip-plugin'.
            //    > Could not read script '~/Library/Developer/Xcode/DerivedData/Skip-Everything-aqywrhrzhkbvfseiqgxuufbdwdft/SourcePackages/plugins/skipapp-packname.output/PackName/skipstone/settings.gradle.kts' as it does not exist.
            return GradleIssue(kind: .error, message: line2.trimmingCharacters(in: CharacterSet(charactersIn: " >")))
        }

        if line1.hasPrefix("Unable to install ") {
            // e.g.:
            // Unable to install /opt/src/github/skiptools/skipapp-showcase/.build/Android/app/outputs/apk/debug/app-debug.apk
            // com.android.ddmlib.InstallException: INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package org.appfair.app.Showcase signatures do not match newer version; ignoring!
            return GradleIssue(kind: .error, message: line2.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if exceptionPattern.firstMatch(in: line1, range: NSRange(line1.startIndex..., in: line1)) != nil {
            // TODO: do we really want to match all exception messages?
            //return GradleIssue(kind: .warning, message: line2.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard let matchResult = gradleFailurePattern.firstMatch(in: line1, range: NSRange(line1.startIndex..., in: line1)) else {
            return nil
        }

        func match(at index: Int) -> String {
            (line1 as NSString).substring(with: matchResult.range(at: index))
        }

        // turn "Error:" and "Warning:" into a error or warning
        let kind: GradleIssue.Kind
        switch match(at: 5) {
        case "Error": kind = .error
        case "Warning": kind = .warning
        default: fatalError("Should have matched either Error or Warning: \(line1)")
        }

        let path = "/" + match(at: 1) // the regex removes the leading slash

        // the issue description is on the line(s) following the expression pattern
        return GradleIssue(kind: kind, message: line2.trimmingCharacters(in: .whitespacesAndNewlines), location: SourceLocation(path: path, position: SourceLocation.Position(line: Int(match(at: 2)) ?? 0, column: Int(match(at: 3)) ?? 0)))
    }

    private func parseKotlinErrorOutput(line: String) -> GradleIssue? {
        guard let match = gradleIssuePattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
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

    public func projectRoot(forModule moduleName: String?, packageName: String?, projectFolder: String) throws -> URL? {
        guard let moduleName = moduleName, let packageName = packageName else {
            return nil
        }
        let env = ProcessInfo.processInfo.environment

        //for (key, value) in env.sorted(by: { $0.0 < $1.0 }) {
        //    print("ENV: \(key)=\(value)")
        //}

        let isXcode = env["__CFBundleIdentifier"] == "com.apple.dt.Xcode" || xcodeBuildFolder != nil

        if isXcode || xcodeBuildFolder != nil {
            // Diagnostics.warning("ENVIRONMENT: \(env)")
            let packageFolderExtension = isXcode ? ".output" : ""

            guard let buildFolder = xcodeBuildFolder else {
                throw AppLaunchError(errorDescription: "The BUILT_PRODUCTS_DIR environment variable must be set to the output of the build process")
            }

            return URL(fileURLWithPath: "../../../SourcePackages/plugins/\(packageName)\(packageFolderExtension)/\(moduleName)/\(pluginFolderName)/", isDirectory: true, relativeTo: URL(fileURLWithPath: buildFolder, isDirectory: true))
        } else {
            // SPM-derived project: .build/plugins/outputs/hello-skip/HelloSkip/skipstone
            // TODO: make it relative to project path
            return URL(fileURLWithPath: (projectFolder) + "/.build/plugins/outputs/\(packageName)/\(moduleName)/skipstone", isDirectory: true)
        }
    }

    func preprocessGradleArguments(in projectFolder: URL?, arguments: [String]) {
        // warn when we detect that the Gradle project needs to be upgraded
        var project = projectFolder ?? URL.currentDirectory()
        if let projectFlagIndex = arguments.firstIndex(where: { $0 == "-p" }),
           let projectArg = arguments.dropFirst(projectFlagIndex + 1).first {
            project.appendPathComponent(projectArg, isDirectory: true)
        }
        project.appendPathComponent("settings.gradle.kts", isDirectory: false)

        if FileManager.default.fileExists(atPath: project.path) {
            if let settingsContents = try? String(String(contentsOf: project, encoding: .utf8)) {
                if !settingsContents.contains(#""skip", "plugin""#) { // check for the new "skip plugin --prebuild" command we should be running
                    let issue = GradleIssue(kind: .warning, message: "Android project upgrade required. Please open a Terminal and cd to the project folder, then run `skip upgrade` and `skip verify --fix` to update the project.", location: SourceLocation(path: project.path, position: SourceLocation.Position(line: 0, column: 0)))
                    print(issue.xcodeMessageString)
                }
            }
        }
    }

    public func gradleExec(in projectFolder: URL?, moduleName: String?, packageName: String?, arguments: [String]) async throws {
        preprocessGradleArguments(in: projectFolder, arguments: arguments)

        let driver = try await GradleDriver()
        let acts: [String] = [] // releaseBuild ? ["assembleRelease"] : ["assembleDebug"] // expected in the arguments to the command

        var exitCode: ProcessResult.ExitStatus? = nil
        let (output, _) = try await driver.launchGradleProcess(in: projectFolder, module: moduleName, actions: acts, arguments: arguments, environment: ProcessInfo.processInfo.environmentWithDefaultToolPaths, info: false, rerunTasks: false, exitHandler: { result in
            print("note: Gradle \(result.resultDescription)")
            exitCode = result.exitStatus
        })

        var lines: [String] = []
        for try await pout in output {
            let line = pout.line
            print(line)

            // check for errors and report them to the IDE with a 1-line buffer
            scanGradleOutput(line1: lines.last ?? line, line2: line)
            lines.append(line)
        }

        guard let exitCode = exitCode, case .terminated(0) = exitCode else {
            // output the gradle build to a temporary location to make the file reference clickable
            let logPath = (ProcessInfo.processInfo.environment["TEMP_DIR"] ?? URL.temporaryDirectory.path) + "/skip-gradle.log.txt"
            var logPrefix: String = ""
            do {
                let logContents = lines.joined(separator: "\n")
                // TODO: add debugging tips and pointers to the documentation
                let endContents = """
                """
                try (logContents + endContents).write(toFile: logPath, atomically: false, encoding: .utf8)
                // if we were able to write to the log file, add the xcode-compatible prefix for the error location
                // https://developer.apple.com/documentation/xcode/running-custom-scripts-during-a-build#Log-errors-and-warnings-from-your-script
                logPrefix = "\(logPath):\(lines.count):0: "
            } catch {
                // shouldn't fail
            }
            throw AppLaunchError(errorDescription: "\(logPrefix)error: The gradle command failed. Review the log for details and consult https://skip.tools/docs/faq for common solutions. Command: gradle \(arguments.joined(separator: " "))")
        }
    }

}

public struct MissingEnvironmentError : LocalizedError {
    public var errorDescription: String?
}

public struct AppLaunchError : LocalizedError {
    public var errorDescription: String?
}



// /DerivedData/Skip-Everything/SourcePackages/plugins/skipapp-weather.output/WeatherAppUI/skipstone/WeatherAppUI/src/main/AndroidManifest.xml:18:13-69 Error:


/// Gradle-formatted lines start with "e:" or "w:", and the line:column specifer seems to sometimes trail with a colon and other times not
let gradleIssuePattern = try! NSRegularExpression(pattern: #"^([we]): file://(.*):([0-9]+):([0-9]+)[:]* +(.*)$"#)
let gradleFailurePattern = try! NSRegularExpression(pattern: #"^/(.*):([0-9]+):([0-9]+)-([0-9]+) (Error|Warning):$"#)

// e.g.: com.xyz.SomeException: Some message
let exceptionPattern = try! NSRegularExpression(pattern: #"^([a-zA-Z.]*)Exception: +(.*)$"#)


extension NSRegularExpression {
    func matches(in string: String, options: MatchingOptions = []) -> [NSTextCheckingResult] {
        matches(in: string, options: options, range: NSRange(string.startIndex ..< string.endIndex, in: string))
    }
}

/// A source-related issue reported during the execution of Gradle. In the form of:
///
/// ```
/// e: file:///tmp/Foo.kt:12:13 Compile Error
/// ```
public struct GradleIssue {
    public var kind: Kind
    public var message: String
    public var location: SourceLocation? = nil

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
    
    /// A message string that will show up in the Xcode Issue Navigator
    public var xcodeMessageString: String {
        let msg = "\(kind.xcode): \(message)"
        if let location = location {
            return "\(location.path):\(location.position.line):\(location.position.column): " + msg
        } else {
            return msg
        }
    }
}

public struct NoModuleFolder : LocalizedError {
    public var errorDescription: String?
}

public struct ADBError : LocalizedError {
    public var errorDescription: String?
}
#endif
