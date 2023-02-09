import Foundation
import Skip
import SymbolKit
import os.log
#if canImport(Cocoa)
import class Cocoa.NSWorkspace
#endif

/// The set of targets for this transpilation.
public struct SkipTargetSet {
    public let sourceBase: StaticString
    public let target: GradleTarget
    public let dependencies: [SkipTargetSet]

    public init(sourceBase: StaticString = #file, _ target: GradleTarget, dependencies: [SkipTargetSet] = []) {
        self.sourceBase = sourceBase
        self.target = target
        self.dependencies = dependencies
    }

    public var targets: [GradleTarget] {
        [target] + dependencies.map(\.target)
    }

    public var deepTargets: [GradleTarget] {
        [target] + dependencies.flatMap(\.targets)
    }

    public var deepTargetSet: [SkipTargetSet] {
        [self] + dependencies.flatMap(\.deepTargetSet)
    }

}

public struct SkipAssembler {
    /// The output folder name for the kotlin interop project (kip)
    public static let kipFolderName = "kip"

    /// The bundle identifier for the Android Studio.app installation
    public static let androidStudioBundleID = "com.google.android.studio"

    public static let logger = Logger(subsystem: "skip", category: "assembler")

    /// Returns the home folder for the local Android Studio install based on the bundle ID (`com.google.android.studio`), which contains `kotlinc` and gradle libraries.
    ///
    /// Android Studio can be downloaded and installed from https://developer.android.com/studio/
    static func studioRoot(bundleID: String) throws -> URL {
        struct BundleIDNotFound : LocalizedError {
            let failureReason: String? = "Android Studio not found; install from: https://developer.android.com/studio/"
        }
        #if canImport(Cocoa)
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw BundleIDNotFound()
        }
        return appURL
        #else
        // TODO: figure out how to find studio in Linux
        throw BundleIDNotFound()
        #endif
    }

    static var kotlinCompiler: URL {
        get throws {
            let studioRoot = try studioRoot(bundleID: androidStudioBundleID)
            // e.g.: /Applications/Android Studio.app/Contents/plugins/Kotlin/kotlinc/bin/kotlinc
            let kotlinc = URL(fileURLWithPath: "Contents/plugins/Kotlin/kotlinc/bin/kotlinc", isDirectory: false, relativeTo: studioRoot)
            return kotlinc
        }
    }

    /// Forks the
    /// - Parameters:
    ///   - studioID: the ID of the app container for the `kotlinc` command
    ///   - script: the script to execute
    /// - Returns: the string result of the script
    public static func kotlinc(script: String) async throws -> [String] {
        var output: [String] = []
        try await System.exec(arguments: ["/bin/sh", kotlinCompiler.path, "-e", script], environment: nil) { line in
            output.append(line)
        }
        return output
    }

    /// Converts the given Kotlin script to JavaScript.
    public static func kotlinToJS(_ kotlin: String, cleanup: Bool = true) async throws -> String {
        var env: [String: String] = [:]
        // activates Kotlin->JavaScript mode
        env["KOTLIN_COMPILER"] = "org.jetbrains.kotlin.cli.js.K2JSCompiler"

        let tmpDir = URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { if cleanup { try? FileManager.default.removeItem(at: tmpDir) } }

        let sourceURL = URL(fileURLWithPath: "source.kt", isDirectory: false, relativeTo: tmpDir)
        try kotlin.write(to: sourceURL, atomically: true, encoding: .utf8)
        defer { if cleanup { try? FileManager.default.removeItem(at: sourceURL) } }

        let outputURL = URL(fileURLWithPath: "output.js", isDirectory: false, relativeTo: tmpDir)

        var output: [String] = []
        try await System.exec(arguments: ["/bin/sh", kotlinCompiler.path, "-output", outputURL.path, sourceURL.path], environment: env, workingDirectory: tmpDir) { line in
            logger.info("kotlinToJS: \(line)")
            output.append(line)
        }

        defer { if cleanup { try? FileManager.default.removeItem(at: outputURL) } }
        return try String(contentsOf: outputURL)
    }

    public static func assemble(root packageRoot: URL, moduleRootPath: String?, sourceFolder: String, testsFolder: String?, targets: SkipTargetSet, destRoot: String, overwrite: Bool = true, studioID: String = androidStudioBundleID) async throws -> (root: URL, files: [URL]) {
        let destRoot = URL(fileURLWithPath: destRoot, isDirectory: true, relativeTo: packageRoot)

        // use the passed-in list of modules, or else default to all the sources in the folder
        let sourceRoot = URL(fileURLWithPath: sourceFolder, isDirectory: true, relativeTo: packageRoot)
        let testRoot = testsFolder.flatMap({ URL(fileURLWithPath: $0, isDirectory: true, relativeTo: packageRoot) })

        let fm = FileManager.default
        //let isDir = { (url: URL) in try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }

        try fm.createDirectory(at: destRoot, withIntermediateDirectories: true)

        var savedURLs: [URL] = []
        /// Writes the given String to the specified URL, only if it has changed
        func write(_ string: String, to url: URL, ifChanged: Bool, encoding: String.Encoding = .utf8) throws {
            savedURLs.append(url)
            // if the size has changed, always write; otherwise, compare string contents
            if !ifChanged // i.e., always write
                || (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) != string.lengthOfBytes(using: encoding) // compare sizes
                || (try? String(contentsOf: url, encoding: encoding)) != string { // compare contents
                try string.write(to: url, atomically: true, encoding: encoding)
            }
        }

        let moduleURL = URL.moduleBuildFolder

        // gather the symbols for all the targets
        let collector = GraphCollector(extensionGraphAssociationStrategy: .extendingGraph)
        for targetSet in targets.deepTargetSet {
            let moduleName = targetSet.target.moduleName
            let symbolGraphs = try await System.extractSymbols(moduleURL, moduleName: moduleName)
            for (url, graph) in symbolGraphs {
                logger.debug("adding symbol graph for: \(url)")
                collector.mergeSymbolGraph(graph, at: url)
            }
        }
        let (unifiedGraphs, _) = collector.finishLoading()

        for targetSet in targets.deepTargetSet {
            let moduleName = targetSet.target.moduleName

            let packageName = KotlinTranslator.packageName(forModule: moduleName)

            logger.info("module: \(moduleName) package: \(packageName)")

            let symbolInfo = SymbolInfo(graphs: unifiedGraphs)

            let moduleSwiftSourceRoot = URL(fileURLWithPath: moduleName, isDirectory: true, relativeTo: sourceRoot)
            let moduleSwiftTestRoot = testRoot.flatMap({ testRoot in URL(fileURLWithPath: moduleName + "Tests", isDirectory: true, relativeTo: testRoot) })

            try Task.checkCancellation()

            // only place the modules in a sub-folder if it has been specified
            let moduleRootFolder = moduleRootPath.flatMap({ URL(fileURLWithPath: $0, isDirectory: true, relativeTo: destRoot) })

            let moduleRoot = URL(fileURLWithPath: moduleName, isDirectory: true, relativeTo: moduleRootFolder ?? destRoot)

            // translate sources: Sources/MODULE/**/*.swift -> DEST/MODULE/src/main/java/MODULE/**/*.kt
            try fm.createDirectory(at: moduleRoot, withIntermediateDirectories: true)

            // resources (e.g., drawable/, font/, values/)
            //let moduleResRoot = URL(fileURLWithPath: "src/main/res", isDirectory: true, relativeTo: moduleRoot)

            // if package path were simply the module name (e.g., "CrossLibrary") rather than the more idiomatic "com.example.package"
            // let packagePath = moduleName
            let packagePath = packageName.split(separator: ".").joined(separator: "/")

            let moduleKotlinSourceRoot = URL(fileURLWithPath: "src/main/kotlin", isDirectory: true, relativeTo: moduleRoot)
                .appendingPathComponent(packagePath, isDirectory: true)
            let moduleKotlinTestRoot = URL(fileURLWithPath: "src/test/kotlin", isDirectory: true, relativeTo: moduleRoot)
                .appendingPathComponent(packagePath, isDirectory: true)

            try fm.createDirectory(at: moduleKotlinSourceRoot, withIntermediateDirectories: true)

            logger.info("scanning: \(moduleSwiftSourceRoot.path)")

            for (testCase, kotlinRoot, swiftRoot) in [
                (false, moduleKotlinSourceRoot, moduleSwiftSourceRoot),
                (true, moduleKotlinTestRoot, moduleSwiftTestRoot),
            ] {
                // the sources we have scanned, which will all be transpiled together
                var swiftSources: Set<URL> = []
                var kotlinSources: Set<URL> = []
                var buildFiles: Set<URL> = []

                try await swiftRoot?.walkFileURL { fileURL in
                    logger.debug("file: \(fileURL.relativePath)")
                    try Task.checkCancellation()

                    let isDir = try fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
                    switch (fileURL.lastPathComponent, fileURL.pathExtension) {
                    case (_, "swift") where isDir == false:
                        swiftSources.insert(fileURL)
                    case ("build.gradle.kts", _):
                        buildFiles.insert(fileURL)
                    case ("gradle.properties", _):
                        buildFiles.insert(fileURL)
                    case ("settings.gradle.kts", _):
                        buildFiles.insert(fileURL)
                    case (_, "kt") where isDir == false:
                        kotlinSources.insert(fileURL)
                    case (_, "strings") where isDir == false:
                        // TODO: translation localized files to …/res/…
                        logger.warning("warning: unhandled strings: \(fileURL.relativePath)")
                        break
                    case (_, "xcassets") where isDir == true:
                        // TODO: translate assets to somewhere
                        logger.warning("warning: unhandled xcassets: \(fileURL.relativePath)")
                        break
                    default:
                        logger.warning("warning: unhandled path: \(fileURL.relativePath)")
                        break
                    }
                }

                func transpileSources(sources: Set<URL>) async throws {
                    let sourceURLs = Dictionary(grouping: sources.map({ (path: $0.path, url: $0) }), by: \.path)
                    let sources = sourceURLs.keys.sorted().map({ Source.File(path: $0) })

                    let tp = Transpiler(sourceFiles: sources, packageName: packageName, symbolInfo: symbolInfo)
                    try await tp.transpile { transpilation in
                        logger.trace("transpilation: \(transpilation.output.content)")
                        guard let sourceURL = sourceURLs[transpilation.sourceFile.path]?.first?.url else {
                            fatalError("missing source URL for path")
                        }
                        let destPath = URL(fileURLWithPath: sourceURL.relativePath, isDirectory: false, relativeTo: kotlinRoot)
                            .deletingPathExtension()
                            .appendingPathExtension("kt")
                        logger.debug("transpiling: \(sourceURL.relativePath) to: \(destPath.path)")
                        try fm.createDirectory(at: destPath.deletingLastPathComponent(), withIntermediateDirectories: true)
                        let kotlin = transpilation.output.content

                        let processed = try postProcess(kotlin: kotlin, options: testCase ? [.testCase] : [])
                        try write(processed, to: destPath, ifChanged: true)
                    }
                }

                try await transpileSources(sources: swiftSources)

                /// Copies over the raw Kotlin files from the source folder
                func copySourceFiles(sources: Set<URL>) async throws {
                    for sourceURL in sources {
                        let destPath = URL(fileURLWithPath: sourceURL.relativePath, isDirectory: false, relativeTo: kotlinRoot)
                        logger.debug("copying: \(sourceURL.relativePath) to: \(destPath.path)")
                        // try FileManager.default.copyItem(at: sourceURL, to: destPath)
                        // only copy when the contents have changed, to avoid triggering unnecessary gradle rebuild
                        try write(String(contentsOf: sourceURL), to: destPath, ifChanged: true)
                    }
                }


                // copy the kotlin files after transpilation, allowing override of same-named .kt/.swift files
                try await copySourceFiles(sources: kotlinSources)

                // finally, copy over the build files, overriding the generated ones
                // FIXME: this is run over the Sources/, so top-level build files won't by copied to the correct destination
                // try await copySourceFiles(sources: buildFiles)

            }

            struct TranslationOptions : OptionSet {
                public let rawValue: Int
                public init(rawValue: Int) { self.rawValue = rawValue }
                //public static let autoport = Self(rawValue: 1<<0)
                public static let testCase = Self(rawValue: 1<<1)
            }

            func postProcess(kotlin sourceKotlin: String, options: TranslationOptions) throws -> String {
                var kotlin = sourceKotlin
                func replace(_ string: String, with replacement: String) {
                    kotlin = kotlin.replacingOccurrences(of: string, with: replacement)
                }

                // replace("convenience constructor", with: "constructor") // Gryphon bug // construtor delegation doesn't work

                //replace(": RawRepresentable()", with: "")
                //replace("@JvmInline\n\ndata class", with: "@JvmInline value class")


                // convert XCTest to a JUnit test runner
                if options.contains(.testCase) {
                    // replace common XCTest assertions with their JUnit equivalent

                    //replace(" try ", with: " ") // trim out `try`

                    // any functions prefixed with "test" will get the JUnit @Test annotation
                    replace("open fun test", with: "@Test fun test")
                    replace("private fun test", with: "@Test fun test")
                    replace("internal fun test", with: "@Test fun test")
                    replace("fun test", with: "@Test fun test")
                    replace("@Test @Test fun test", with: "@Test fun test") // fixup multiple annotations

                    // add the test runner to the top
                    replace("internal class", with: """
                    import kotlin.test.*
                    import org.junit.Test
                    import org.junit.Assert
                    import org.junit.runner.RunWith

                    import kotlinx.coroutines.*
                    import kotlinx.coroutines.test.*

                    @RunWith(org.robolectric.RobolectricTestRunner::class)
                    @org.robolectric.annotation.Config(manifest=org.robolectric.annotation.Config.NONE)
                    internal class
                    """)

                    // only add the conversions to a SkipTranspilerTestCase test case subclass
                    // this allows us to just have the conversions in a single generated file
                    if kotlin.contains("SkipTranspilerTestCase") {
                        kotlin += XCTestJunitConversions
                    }
                }

                kotlin = """
                // =========================================
                // GENERATED FILE; EDITS WILL BE OVERWRITTEN
                // =========================================

                """ + kotlin

                return kotlin
            }

            func createModuleLevelGradleBuild() throws {
                // we'd prefer to just specify the shallow dependencies here and let gradle resolve the transitive module dependencies, but it seems to not be supported, so instead we need to specify the deep dependencies (uniqued; in no particular order)
                let localDependencies = Set(targetSet.dependencies.map(\.target.moduleName)).sorted()
                //let localDependencies = Set(targetSet.dependencies.flatMap(\.deepTargets).map(\.moduleName)).sorted()

                // - api: “dependencies appearing in the api configurations will be transitively exposed to consumers of the library, and as such will appear on the compile classpath of consumers. Dependencies found in the implementation configuration will, on the other hand, not be exposed to consumers, and therefore not leak into the consumers' compile classpath.”
                func modDependency(mod: String, api: Bool = true) -> String {
                    let dep = api ? "api" : "implementation"

                    if let moduleRootPath = moduleRootPath {
                        return "\(dep)(project(\":\(moduleRootPath):\(mod)\"))"
                    } else {
                        return "\(dep)(project(\":\(mod)\"))"
                    }
                }

                // the module-level build config
                let buildGradle = URL(fileURLWithPath: "build.gradle.kts", isDirectory: false, relativeTo: moduleRoot)
                let buildGradleSource = """
                group = "\(packageName)"

                plugins {
                    kotlin("android") version "1.8.+"
                    kotlin("plugin.serialization") version "1.8.+"
                    id("com.android.library") version "7.+"
                }

                dependencies {
                    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:+")
                    testImplementation("org.jetbrains.kotlin:kotlin-test:1.8.+")
                    testImplementation("org.jetbrains.kotlin:kotlin-test-junit:1.8.+")
                    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.6.+")
                    testImplementation("org.robolectric:robolectric:4.+")
                    androidTestImplementation("com.android.support.test:runner:+")

                    \(localDependencies.map({ modDependency(mod: $0) }).joined(separator: "\n    "))
                }

                android {
                    namespace = group as String
                    sourceSets.getByName("main") {
                        kotlin.setSrcDirs(listOf("src/main/kotlin"))
                    }
                    sourceSets.getByName("test") {
                        kotlin.setSrcDirs(listOf("src/test/kotlin"))
                    }
                    sourceSets.getByName("androidTest") {
                        kotlin.setSrcDirs(listOf("src/test/kotlin"))
                    }
                    compileSdkVersion(33)
                    defaultConfig {
                        minSdk = 24
                        targetSdk = 33
                        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
                    }

                    compileOptions {
                        sourceCompatibility = JavaVersion.VERSION_11
                        targetCompatibility = JavaVersion.VERSION_11
                    }
                    kotlinOptions {
                        jvmTarget = "11"
                    }
                    lintOptions {
                    }
                }

                tasks.withType<Test> {
                    this.testLogging {
                        this.showStandardStreams = true
                    }
                }

                tasks.withType<Test>().configureEach {
                    systemProperties.put("robolectric.logging", "stdout")
                }

                """

                try write(buildGradleSource, to: buildGradle, ifChanged: true)
            }

            try createModuleLevelGradleBuild()
        }

        func createTopLevelGradleBuild() throws {
            // the top-level build configurations files that will be created
            let buildGradle = URL(fileURLWithPath: "build.gradle.kts", isDirectory: false, relativeTo: destRoot)
            let buildGradleSource = """
            buildscript {
                repositories {
                    google()
                    mavenCentral()
                }
            }

            subprojects {
                repositories {
                    google()
                    mavenCentral()
                }
            }
            """
            try write(buildGradleSource, to: buildGradle, ifChanged: true)

            let gradleProperties = URL(fileURLWithPath: "gradle.properties", isDirectory: false, relativeTo: destRoot)
            let gradlePropertiesSource = """
            # Project-wide Gradle settings
            # http://www.gradle.org/docs/current/userguide/build_environment.html
            #org.gradle.jvmargs=-Xmx2048m
            android.useAndroidX=true
            android.enableJetifier=true
            kotlin.code.style=official
            """
            try write(gradlePropertiesSource, to: gradleProperties, ifChanged: true)

            let settingsGradle = URL(fileURLWithPath: "settings.gradle.kts", isDirectory: false, relativeTo: destRoot)
            var settingsGradleSource = """
            pluginManagement {
                repositories {
                    gradlePluginPortal()
                    google()
                    mavenCentral()
                }
            }

            dependencyResolutionManagement {
                repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
                repositories {
                    google()
                    mavenCentral()
                }
            }

            
            """

            if let moduleRootPath = moduleRootPath {
                // just include everything under the module root path
                settingsGradleSource += """
                val modules = file("\(moduleRootPath)").listFiles().filter { it.isDirectory }.map { it.name }
                for (module in modules) {
                    include("\(moduleRootPath):$module")
                }
                """
            } else {
                // not module root; modules are stored in a shallow folder
                for moduleName in Set(targets.deepTargets.map(\.moduleName)).sorted() {
                    settingsGradleSource += "include(\":\(moduleName)\")\n"
                }
            }

            try write(settingsGradleSource, to: settingsGradle, ifChanged: true)
        }

        try createTopLevelGradleBuild()

        /// Creates the gradlew command and the gradle/wrapper/gradle-wrapper.jar that is expected by convention
        /// - Parameter gradleVersion: the version to specify (a release from https://gradle.org/releases/ like "7.6")
        ///
        /// Currently overridden to 7.6 because dependent Android libraries require that.
        func createGradleWrapper(gradleVersion: String? = "7.6") async throws {
            // Gradle wrapper configuration
            let gradlew = URL(fileURLWithPath: "gradlew", isDirectory: false, relativeTo: destRoot)
            let gradleWrapper = URL(fileURLWithPath: "gradle/wrapper", isDirectory: true, relativeTo: destRoot)
            try fm.createDirectory(at: gradleWrapper, withIntermediateDirectories: true)

            let gradleWrapperJar = URL(fileURLWithPath: "gradle-wrapper.jar", isDirectory: false, relativeTo: gradleWrapper)
            let gradleWrapperProps = URL(fileURLWithPath: "gradle-wrapper.properties", isDirectory: false, relativeTo: gradleWrapper)

            // copy the gradle-wrapper over from the Studio install
            let studioRoot = try studioRoot(bundleID: androidStudioBundleID)
            let studioGradleRoot = URL(fileURLWithPath: "Contents/plugins/gradle/lib", isDirectory: true, relativeTo: studioRoot)
            try await studioGradleRoot.walkFileURL { url in
                // e.g.: gradle-wrapper-7.4.jar
                let wrapperPrefix = "gradle-wrapper-"
                if url.lastPathComponent.hasPrefix(wrapperPrefix) && url.pathExtension == "jar" {
                    // if we have not specified a specific version, then use the suffix of the wrapper included at /Applications/Android Studio.app/Contents/plugins/gradle/lib/gradle-wrapper-7.4.jar
                    let currentGradleVersion = url.deletingPathExtension().lastPathComponent.dropFirst(wrapperPrefix.count).description // e.g., 7.4
                    let distributionGradleVersion = gradleVersion ?? currentGradleVersion
                    try? fm.removeItem(at: gradleWrapperJar) // clear the destination in case it already exists
                    try fm.copyItem(at: url, to: gradleWrapperJar)

                    // now we need to create the gradle-wrapper.properties, which will be based on the version of the gradle wrapper we specified or that us included with Studio
                    let gradlePropertiesContents = """
                    distributionBase=GRADLE_USER_HOME
                    distributionUrl=https\\://services.gradle.org/distributions/gradle-\(distributionGradleVersion)-bin.zip
                    distributionPath=wrapper/dists
                    zipStorePath=wrapper/dists
                    zipStoreBase=GRADLE_USER_HOME
                    """

                    try write(gradlePropertiesContents, to: gradleWrapperProps, ifChanged: true)

                    // finally create the idiomatic `gradelw` root script, but one which just uses the installed Android Studio's JBR (https://github.com/JetBrains/JetBrainsRuntime) java to run gradle
                    let gradlewContents = """
                    #!/bin/bash
                    ${JAVA_HOME:-"$(mdfind "kMDItemCFBundleIdentifier == '\(studioID)'" | head -n 1)/Contents/jbr/Contents/Home"}/bin/java ${JAVA_OPTS} ${GRADLE_OPTS} -classpath "$(dirname "${0}")/gradle/wrapper/gradle-wrapper.jar":"${CLASSPATH}" org.gradle.wrapper.GradleWrapperMain ${@}
                    """

                    try write(gradlewContents, to: gradlew, ifChanged: true)
                    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gradlew.path) // make the script executable
                }
            }
        }

        try await createGradleWrapper()

        return (destRoot, savedURLs)
    }
}

extension URL {
    /// The folder where built modules will be placed.
    ///
    /// When running within Xcode, which will query the `__XCODE_BUILT_PRODUCTS_DIR_PATHS` environment.
    /// Otherwise, it assumes SPM's standard ".build" folder relative to the working directory.
    public static var moduleBuildFolder: URL {
        // if we are running tests from Xcode, this environment variable should be set; otherwise, assume the .build folder for an SPM build
        let xcodeBuildFolder = ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] // also seems to be __XPC_DYLD_LIBRARY_PATH or __XPC_DYLD_FRAMEWORK_PATH; this will be something like ~/Library/Developer/Xcode/DerivedData/MODULENAME-bsjbchzxfwcrveckielnbyhybwdr/Build/Products/Debug

        #if DEBUG
        let swiftBuildFolder = ".build/debug"
        #else
        let swiftBuildFolder = ".build/release"
        #endif

        return URL(fileURLWithPath: xcodeBuildFolder ?? swiftBuildFolder, isDirectory: true)
    }
}

/// The target mode for generating Gradle config
public enum GradleTarget {
    /// An app module target
    case app(String)
    /// A library module target
    case lib(String)

    public var moduleName: String {
        switch self {
        case .app(let moduleName): return moduleName
        case .lib(let moduleName): return moduleName
        }
    }
}

extension URL {
    /// Asynchronously walks the resursive file tree, executing the block on each file it finds.
    /// - Parameters:
    ///   - keys: the keys to include in the URL `resourcesValues`
    ///   - mask: the file enumeration options
    ///   - block: the block to execute on each file/directory URL encountered
    public func walkFileURL(includingPropertiesForKeys keys: [URLResourceKey] = [.isDirectoryKey], options mask: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .producesRelativePathURLs], with block: (URL) async throws -> ()) async throws {
        let enumerator: FileManager.DirectoryEnumerator = FileManager.default.enumerator(at: self, includingPropertiesForKeys: keys, options: mask, errorHandler: nil) ?? .init()
        for enumeratorItem in enumerator {
            guard let fileURL = enumeratorItem as? URL else {
                // should never happen…
                continue
            }

            try Task.checkCancellation()
            try await block(fileURL)
        }
    }
}

extension Process {
    /// Create a process with the given exeuctable and arguments.
    /// - Parameters:
    ///   - executableURL: the path to the executable
    ///   - argument: the array of argument strings
    public convenience init(executableURL: URL, arguments: [String], environment: [String: String]? = nil, workingDirectory: URL? = nil) {
        self.init()
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.currentDirectoryURL = workingDirectory
    }

    /// Runs the process with the specified arguments, asyncronously waits for the result, and then returns the stdout and stderr.
    public func execute() async throws -> (stdout: Pipe, stderr: Pipe) {
        let (stdout, stderr) = (Pipe(), Pipe())
        (self.standardOutput, self.standardError) = (stdout, stderr)
        let cancel = { self.interrupt() }

        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Pipe, Pipe), Error>) in
                self.terminationHandler = { task in
                    if task.terminationStatus == 0 {
                        continuation.resume(returning: (stdout, stderr))
                    } else {
                        continuation.resume(throwing: RunProcessError.nonZeroExit(task.terminationStatus, stdout, stderr))
                    }
                }

                do {
                    try self.run()
                } catch {
                    continuation.resume(throwing: RunProcessError.execError(error))
                }
            }
        } onCancel: {
            cancel()
        }
    }

    public enum RunProcessError: Error {
        case execError(Error)
        case nonZeroExit(_ exitCode: Int32, _ stdout: Pipe, _ stderr: Pipe)
    }
}


public actor System {
    public var process: Process
    private var started: Bool = false

    public static let logger = Logger(subsystem: "skip", category: "system")

    public init(executableURL: URL, arguments: [String], environment: [String: String]? = nil, workingDirectory: URL? = nil) {
        let stdout = Pipe()
        let stderr = stdout // Pipe() // FIXME: we use the same pipe for both standard out and standard err since I can't figure out how to asynchronously read from two file handles at the same time
        let process = Process()
        process.standardOutput = stdout
        process.standardError = stderr
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = workingDirectory

        self.process = process
    }

    public var stdout: FileHandle.AsyncBytes {
        (process.standardOutput as! Pipe).fileHandleForReading.bytes
    }

    public var stderr: FileHandle.AsyncBytes {
        (process.standardError as! Pipe).fileHandleForReading.bytes
    }

    /// Executes the given process, sending lines to `outputHandler` and waiting for a non-zero exit code.
    public static func exec(_ executableURL: URL = URL(fileURLWithPath: "/usr/bin/env", isDirectory: false), arguments: [String], environment: [String: String]? = nil, workingDirectory: URL? = nil, outputHandler: (String) async throws -> ()) async throws {
        logger.info("exec: \(arguments.joined(separator: " "))")
        let process = System(executableURL: executableURL, arguments: arguments, environment: environment, workingDirectory: workingDirectory)
        try await process.run()
        let outLines = await process.stdout.lines
        for try await line in outLines where !Task.isCancelled {
            try await outputHandler(line)
        }
        try Task.checkCancellation()
        try await process.wait()
    }

    /// Starts the process
    public func run() throws {
        if !started {
            started = true
            try process.run()
        }
    }

    public struct SystemProcessFailed : LocalizedError {
        public let failureReason: String?
        public let terminationStatus: Int32
    }

    /// Runs the process with the specified arguments, asyncronously waits for the result, and then returns the stdout and stderr.
    @discardableResult public func wait() async throws -> Int32 {
        let cancel = { self.process.interrupt() }
        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { task in
                    if task.terminationStatus != 0 {
                        continuation.resume(throwing: SystemProcessFailed(failureReason: "Error code \(task.terminationStatus) returned.", terminationStatus: task.terminationStatus))
                    } else {
                        continuation.resume(returning: task.terminationStatus)
                    }
                }

                do {
                    if !started {
                        started = true
                        try process.run()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            cancel()
        }
    }
}

extension Pipe {
    /// Reads all the remaining data available for the pipe.
    public func readData() throws -> Data? {
        try fileHandleForReading.readToEnd()
    }

    /// Reads the pipe's remaining data as a string, optionally trimming off the leading and trailing whitespace and newlines.
    public func readString(trim: Bool = true) throws -> String {
        (String(data: try readData() ?? Data(), encoding: .utf8) ?? "").trimmingCharacters(in: trim ? .whitespacesAndNewlines : .init())
    }
}

/// The pass-through `XCTAssert*` functions that are converted to their JUnit `Assert.*` equivalents.
private let XCTestJunitConversions = """

// Mimics the API of XCTest for a JUnit test
// Behavior difference: JUnit assert* thows an exception, but XCTAssert* just reports the failure and continues

typealias SkipTranspilerTestCase = XCTestCase

interface XCTestCase {
    fun XCTFail() = Assert.fail()

    fun XCTFail(msg: String) = Assert.fail(msg)

    fun XCTUnwrap(ob: Any?) = { Assert.assertNotNull(ob); ob }
    fun XCTUnwrap(ob: Any?, msg: String) = { Assert.assertNotNull(msg, ob); ob }

    fun XCTAssert(a: Boolean) = Assert.assertTrue(a as Boolean)
    fun XCTAssertTrue(a: Boolean) = Assert.assertTrue(a as Boolean)
    fun XCTAssertTrue(a: Boolean, msg: String) = Assert.assertTrue(msg, a)
    fun XCTAssertFalse(a: Boolean) = Assert.assertFalse(a)
    fun XCTAssertFalse(a: Boolean, msg: String) = Assert.assertFalse(msg, a)

    fun XCTAssertNil(a: Any?) = Assert.assertNull(a)
    fun XCTAssertNil(a: Any?, msg: String) = Assert.assertNull(msg, a)
    fun XCTAssertNotNil(a: Any?) = Assert.assertNotNull(a)
    fun XCTAssertNotNil(a: Any?, msg: String) = Assert.assertNotNull(msg, a)

    fun XCTAssertIdentical(a: Any?, b: Any?) = Assert.assertSame(b, a)
    fun XCTAssertIdentical(a: Any?, b: Any?, msg: String) = Assert.assertSame(msg, b, a)
    fun XCTAssertNotIdentical(a: Any?, b: Any?) = Assert.assertNotSame(b, a)
    fun XCTAssertNotIdentical(a: Any?, b: Any?, msg: String) = Assert.assertNotSame(msg, b, a)

    fun XCTAssertEqual(a: Any?, b: Any?) = Assert.assertEquals(b, a)
    fun XCTAssertEqual(a: Any?, b: Any?, msg: String) = Assert.assertEquals(msg, b, a)
    fun XCTAssertNotEqual(a: Any?, b: Any?) = Assert.assertNotEquals(b, a)
    fun XCTAssertNotEqual(a: Any?, b: Any?, msg: String) = Assert.assertNotEquals(msg, b, a)

    // additional overloads needed for XCTAssert*() which have different signatures on Linux (@autoclosures) than on Darwin platforms (direct values)

    fun XCTUnwrap(ob: () -> Any?) = { val x = ob(); Assert.assertNotNull(x); x }
    fun XCTUnwrap(ob: () -> Any?, msg: () -> String) = { val x = ob(); Assert.assertNotNull(msg(), x); x }

    fun XCTAssertTrue(a: () -> Boolean) = Assert.assertTrue(a())
    fun XCTAssertTrue(a: () -> Boolean, msg: () -> String) = Assert.assertTrue(msg(), a())
    fun XCTAssertFalse(a: () -> Boolean) = Assert.assertFalse(a())
    fun XCTAssertFalse(a: () -> Boolean, msg: () -> String) = Assert.assertFalse(msg(), a())

    fun XCTAssertNil(a: () -> Any?) = Assert.assertNull(a())
    fun XCTAssertNil(a: () -> Any?, msg: () -> String) = Assert.assertNull(msg(), a())
    fun XCTAssertNotNil(a: () -> Any?) = Assert.assertNotNull(a())
    fun XCTAssertNotNil(a: () -> Any?, msg: () -> String) = Assert.assertNotNull(msg(), a())

    fun XCTAssertIdentical(a: () -> Any?, b: () -> Any?) = Assert.assertSame(a(), b())
    fun XCTAssertIdentical(a: () -> Any?, b: () -> Any?, msg: () -> String) = Assert.assertSame(msg(), a(), b())
    fun XCTAssertNotIdentical(a: () -> Any?, b: () -> Any?) = Assert.assertNotSame(a(), b())
    fun XCTAssertNotIdentical(a: () -> Any?, b: () -> Any?, msg: () -> String) = Assert.assertNotSame(msg(), a(), b())

    fun XCTAssertEqual(a: () -> Any?, b: () -> Any?) = Assert.assertEquals(a(), b())
    fun XCTAssertEqual(a: () -> Any?, b: () -> Any?, msg: () -> String) = Assert.assertEquals(msg(), a(), b())
    fun XCTAssertNotEqual(a: () -> Any?, b: () -> Any?) = Assert.assertNotEquals(a(), b())
    fun XCTAssertNotEqual(a: () -> Any?, b: () -> Any?, msg: () -> String) = Assert.assertNotEquals(msg(), a(), b())
}


"""

