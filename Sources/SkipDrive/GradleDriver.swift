// Copyright 2023 Skip
#if !SKIP
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

/// The `GradleDriver` controls the execution of the `gradle` tool,
/// which is expected to already be installed on the system in the
/// user's `PATH` environment.
@available(macOS 13, macCatalyst 16, iOS 16, tvOS 16, watchOS 8, *)
public struct GradleDriver {
    /// The minimum version of Kotlin we can work with
    public static let minimumKotlinVersion = Version(1, 8, 0)

    /// The minimum version of Gradle that we can work with
    /// https://github.com/actions/runner-images/blob/main/images/macos/macos-12-Readme.md#project-management
    public static let minimumGradleVersion = Version(8, 1, 1)

    /// The path to the `gradle` tool
    public let gradlePath: URL

    /// The output from `gradle --version`, parsed into Key/Value pairs
    public let gradleInfo: [String: String]

    /// The current version of the `gradle` tool
    public let gradleVersion: Version

    /// The current version of Kotlin as used by the `gradle` tool
    public let kotlinVersion: Version

    /// The default command args to use when executing the `gradle` tool
    let gradleArgs: [String]

    /// Creates a new `GradleDriver`. Creation will check that the Gradle and Kotlin versions are within the expected limits.
    @available(macOS 13, macCatalyst 16, *)
    public init() async throws {
        self.gradlePath = try Self.findGradle()
        self.gradleArgs = [
            gradlePath.path,
        ]

        self.gradleInfo = try await Self.execGradleInfo(gradleArgs: self.gradleArgs)

        guard let gradleVersionString = self.gradleInfo["Gradle"],
              let gradleVersion = try? Version(versionString: gradleVersionString, usesLenientParsing: true) else {
            throw GradleDriverError.noGradleVersion(gradle: self.gradlePath, props: self.gradleInfo)
        }

        self.gradleVersion = gradleVersion
        if self.gradleVersion < Self.minimumGradleVersion {
            throw GradleDriverError.gradleVersionTooLow(gradle: self.gradlePath, version: self.gradleVersion, minimum: Self.minimumGradleVersion)
        }

        guard let kotlinVersionString = self.gradleInfo["Kotlin"],
              let kotlinVersion = try? Version(versionString: kotlinVersionString, usesLenientParsing: true) else {
            throw GradleDriverError.noKotlinVersion(gradle: self.gradlePath)
        }

        self.kotlinVersion = kotlinVersion
        if self.kotlinVersion < Self.minimumKotlinVersion {
            throw GradleDriverError.kotlinVersionTooLow(gradle: self.gradlePath, version: self.kotlinVersion, minimum: Self.minimumKotlinVersion)
        }
    }

    private init(gradlePath: URL, gradleInfo: [String : String], gradleVersion: Version, kotlinVersion: Version, gradleArgs: [String]) {
        self.gradlePath = gradlePath
        self.gradleInfo = gradleInfo
        self.gradleVersion = gradleVersion
        self.kotlinVersion = kotlinVersion
        self.gradleArgs = gradleArgs
    }

    /// Creates a clone of this driver.
    public func clone() -> GradleDriver {
        GradleDriver(gradlePath: gradlePath, gradleInfo: gradleInfo, gradleVersion: gradleVersion, kotlinVersion: kotlinVersion, gradleArgs: gradleArgs)
    }

    /// Executes `gradle` with the current default arguments and the additional args and returns an async stream of the lines from the combined standard err and standard out.
    public func execGradle(in workingDirectory: URL?, args: [String], env: [String: String] = ProcessInfo.processInfo.environmentWithDefaultToolPaths, onExit: @escaping (ProcessResult) throws -> ()) async throws -> Process.AsyncLineOutput {
        // the resulting command will be something like:
        // java -Xmx64m -Xms64m -Dorg.gradle.appname=gradle -classpath /opt/homebrew/Cellar/gradle/8.0.2/libexec/lib/gradle-launcher-8.0.2.jar org.gradle.launcher.GradleMain info
        #if DEBUG
        // output the launch message in a format that makes it easy to copy and paste the result into the terminal
        print("execGradle:", (gradleArgs + args).joined(separator: " "))
        #endif

        return Process.streamLines(command: gradleArgs + args, environment: env, workingDirectory: workingDirectory, includeStdErr: true, onExit: onExit)
    }

    /// Invokes the given target for a gradle project.
    /// 
    /// - Parameters:
    ///   - workingDirectory: the directory in which to fork the gradle process
    ///   - buildFolder: the directory in which the build contents are output (`--build-path SWIFTBUILD`)
    ///   - module: the name of the module to test
    ///   - actions: the gradle actions to run, such as `["test"]`
    ///   - arguments: additional arguments to specify
    ///   - daemon: whether the enable the forking of a persistent gradle daemon that will make subsequent runs faster (e.g., 5 secs vs. 15 secs)
    ///   - failFast: whether to pass the "--fail-fast" flag
    ///   - continue: whether to permit failing tests to complete with the "--continue" flag
    ///   - offline: whether to pass the "--offline" flag
    ///   - rerunTasks: whether to pass the "--rerun-tasks" flag
    ///   - exitHandler: the exit handler, which may want to permit a process failure in order to have time to parse the tests
    /// - Returns: an array of parsed test suites containing information about the test run
    @available(macOS 13, macCatalyst 16, iOS 16, tvOS 16, watchOS 8, *)
    public func launchGradleProcess(in workingDirectory: URL?, buildFolder: String = ".build", module: String?, actions: [String], arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environmentWithDefaultToolPaths, daemon enableDaemon: Bool = true, info infoFlag: Bool = false, quiet quietFlag: Bool = false, plain plainFlag: Bool = true, maxMemory: UInt64? = nil, failFast failFastFlag: Bool = false, noBuildCache noBuildCacheFlag: Bool = false, continue continueFlag: Bool = false, offline offlineFlag: Bool = false, rerunTasks rerunTasksFlag: Bool = true, exitHandler: @escaping (ProcessResult) throws -> ()) async throws -> (output: Process.AsyncLineOutput, result: () throws -> [TestSuite]) {


        var args = actions + arguments

        var env: [String: String] = environment

        // add in the project dir for explicitness (even though it is assumed from the current working directory as well)
        if let workingDirectory = workingDirectory {
            args += ["--project-dir", workingDirectory.path]
        }

        // this enables reporting on deprecated features
        args += ["--warning-mode", "all"]

        var testResultFolder: URL? = nil

        if let module = module {
            let moduleURL = URL(fileURLWithPath: module, isDirectory: true, relativeTo: workingDirectory)
            if !FileManager.default.fileExists(atPath: moduleURL.path) {
                throw GradleDriverError("The expected gradle folder did not exist, which may mean the Skip transpiler is not enabled or encountered errors. Try running `skip doctor` to diagnose and re-building the project. See https://skip.tools/docs/. Missing path: \(moduleURL.path)")
            }
            // rather than the top-level "build" folder, we place the module in per-module .build/ sub-folder in order to enable concurrent testing as well as placing generated files in a typically-gitignored
            let buildDir = "\(buildFolder)/\(module)"
            let testResultPath = "\(buildDir)/test-results"
            args += ["-PbuildDir=\(buildDir)"]
            testResultFolder = URL(fileURLWithPath: testResultPath, isDirectory: true, relativeTo: moduleURL)
        }

        // this allows multiple simultaneous gradle builds to take place
        // args += ["--parallel"]

        // args += ["-Dorg.gradle.configureondemand=true"]

        if noBuildCacheFlag {
            args += ["--no-build-cache"]
        }

        if rerunTasksFlag {
            args += ["--rerun-tasks"]
        }

        if failFastFlag {
            args += ["--fail-fast"]
        }

        if continueFlag {
            args += ["--continue"]
        }

        if offlineFlag {
            // // tests don't work offline until the user has a ~/.gradle/caches/ with all the base dependencies
            args += ["--offline"]
        }

        if infoFlag {
            args += ["--info"]
        }

        if quietFlag {
            args += ["--quiet"]
        }

        if plainFlag {
            args += ["--console=plain"]
        }

        // attempt to run in the same process without forking the daemon
        if enableDaemon == false {
            args += ["--no-daemon"]
        }

        if let maxMemory = maxMemory {

            // also need to add in JVM flags, lest we be countermanded with: “To honour the JVM settings for this build a single-use Daemon process will be forked. See https://docs.gradle.org/8.0.2/userguide/gradle_daemon.html#sec:disabling_the_daemon.”
            // these seem to be quite specific to the gradle version being used, so disabling the daemon in future gradle versions might require tweaking these args (which can be seen by enabling the info flag):

            // Checking if the launcher JVM can be re-used for build. To be re-used, the launcher JVM needs to match the parameters required for the build process: -Xms256m -Xmx512m -Dfile.encoding=UTF-8 -Duser.country=US -Duser.language=en -Duser.variant

            var jvmargs: [String] = []

            jvmargs += ["-Dfile.encoding=UTF-8"]
            jvmargs += ["-Xms256m"]

            // large amounts of log output can cause connected Android tests to fail with an error like:
            // io.grpc.StatusRuntimeException: RESOURCE_EXHAUSTED: gRPC message exceeds maximum size 4194304: 9677208
            // TODO: add in gRPC max package size here
            //jvmargs += ["-Dxxx.maxSize=XXX"]

            // make a nice memory string if we are dividible by kb/mb/gb
            let memstr: String
            let kb = Double(maxMemory) / 1024
            let mb = kb / 1024
            let gb = mb / 1024
            if round(gb) == gb {
                memstr = "\(Int64(gb))g"
            } else if round(mb) == mb {
                memstr = "\(Int64(mb))m"
            } else if round(kb) == kb {
                memstr = "\(Int64(kb))k"
            } else {
                memstr = maxMemory.description // raw bytes description
            }

            jvmargs += ["-Xmx\(memstr)"]

            env["GRADLE_OPTS"] = jvmargs.joined(separator: " ")
            //args += ["-Dorg.gradle.jvmargs=" + jvmargs.joined(separator: " ")]

        }

        if let testResultFolder = testResultFolder {
            #if os(macOS)
            try? FileManager.default.trashItem(at: testResultFolder, resultingItemURL: nil) // remove the test folder, since a build failure won't clear it and it will appear as if the tests ran successfully
            #else
            try? FileManager.default.removeItem(atPath: testResultPath)
            #endif
        }

        let output = try await execGradle(in: workingDirectory, args: args, env: env, onExit: exitHandler)
        return (output, { try Self.parseTestResults(in: testResultFolder) })
    }

    /// Executes `skiptool info` and returns the info dictionary.
    @available(macOS 13, macCatalyst 16, *)
    private static func execGradleInfo(gradleArgs: [String]) async throws -> [String: String] {
        // gradle --version will output an unstructued mess like this:
        /*
         ------------------------------------------------------------
         Gradle 8.1.1
         ------------------------------------------------------------
         Build time:   2023-04-21 12:31:26 UTC
         Revision:     1cf537a851c635c364a4214885f8b9798051175b
         Kotlin:       1.8.10
         Groovy:       3.0.15
         Ant:          Apache Ant(TM) version 1.10.11 compiled on July 10 2021
         JVM:          17.0.7 (Eclipse Adoptium 17.0.7+7)
         OS:           Mac OS X 13.3.1 x86_64
         */

        let lines = try await Process.streamLines(command: gradleArgs + ["--version"], includeStdErr: true, onExit: Process.expectZeroExitCode).reduce([]) { $0 + [$1] }
        //print("gradle info", lines.joined(separator: "\n"))
        var lineMap: [String: String] = [:]
        let gradlePrefix = "Gradle"
        for line in lines {
            // properties are "Key: Value", except the "Gradle" version. Ugh.
            if line.hasPrefix(gradlePrefix + " ") {
                lineMap[gradlePrefix] = line.dropFirst(gradlePrefix.count).trimmingCharacters(in: .whitespaces)
            } else {
                let parts = line.split(separator: ":", maxSplits: 2).map({ $0.trimmingCharacters(in: .whitespacesAndNewlines )})
                if parts.count == 2 {
                    lineMap[parts[0]] = parts[1]
                }
            }
        }

        return lineMap
    }

    /// Finds the given tool in the current process' `PATH`.
    private static func findGradle() throws -> URL {
        // add in standard Homebrew paths, in case they aren't in the user's PATH
        return try URL.findCommandInPath(toolName: "gradle", withAdditionalPaths: [ProcessInfo.homebrewRoot + "/bin"])
    }

    /* The contents of the JUnit test case XML result files look a bit like this:

    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <testsuite name="sample.project.LibraryTest" tests="2" skipped="0" failures="1" errors="0" timestamp="2023-03-13T16:47:39" hostname="zap.local" time="0.021">
        <properties>
        </properties>
        <testcase name="someLibraryMethodReturnsTrue()" classname="sample.project.LibraryTest" time="0.015">
        </testcase>
        <testcase name="someTestCaseThatAlwaysFails()" classname="sample.project.LibraryTest" time="0.005">
            <failure message="org.opentest4j.AssertionFailedError: THIS TEST CASE ALWAYS FAILS" type="org.opentest4j.AssertionFailedError">org.opentest4j.AssertionFailedError: THIS TEST CASE ALWAYS FAILS"
            type="org.opentest4j.AssertionFailedError">
               org.opentest4j.AssertionFailedError: THIS TEST CASE ALWAYS FAILS
                 at app//org.junit.jupiter.api.AssertionUtils.fail(AssertionUtils.java:38)
                 …
                 at app//worker.org.gradle.process.internal.worker.GradleWorkerMain.main(GradleWorkerMain.java:74)
           </failure>
        </testcase>
        <system-out>
        </system-out>
        <system-err>
        </system-err>
    </testsuite>
    */

    public struct TestSuite {
        // e.g.: "sample.project.LibraryTest"
        public var name: String
        public var tests: Int
        public var skipped: Int
        public var failures: Int
        public var errors: Int
        //public var timestamp: Date
        //public var hostname: String
        public var time: TimeInterval
        public var testCases: [TestCase]
        // public var properties: [String: String]? // TODO
         public var systemOut: String?
         public var systemErr: String?

        public init(name: String, tests: Int, skipped: Int, failures: Int, errors: Int, time: TimeInterval, testCases: [TestCase], systemOut: String?, systemErr: String?) {
            self.name = name
            self.tests = tests
            self.skipped = skipped
            self.failures = failures
            self.errors = errors
            self.time = time
            self.testCases = testCases
            self.systemOut = systemOut
            self.systemErr = systemErr
        }

        /// Loads the test suite information from the JUnit-compatible XML format.
        public static func parse(contentsOf url: URL) throws -> [TestSuite] {
            #if os(macOS) || os(Linux) || targetEnvironment(macCatalyst)
            let results = try XMLDocument(contentsOf: url)
            //print("parsed XML results:", results)

            guard let root = results.rootElement() else {
                throw GradleDriverError.missingProperty(url: url, propertyName: "root")
            }

            let testsuites: [XMLElement]

            if root.name == "testsuites" {
                // multiple top-level testsuites (single-file XUnit output style)
                testsuites = root.children?.compactMap({ $0 as? XMLElement }) ?? []
            } else if root.name == "testsuite" {
                // single top-level testsuite (multiple-file JUnit output style)
                testsuites = [root]
            } else {
                throw GradleDriverError.missingProperty(url: url, propertyName: "testsuite")
            }

            var suites: [TestSuite] = []

            for testsuite in testsuites {
                guard let testSuiteName = testsuite.attribute(forName: "name")?.stringValue else {
                    throw GradleDriverError.missingProperty(url: url, propertyName: "name")
                }

                guard let tests = testsuite.attribute(forName: "tests")?.stringValue,
                      let testCount = Int(tests) else {
                    throw GradleDriverError.missingProperty(url: url, propertyName: "tests")
                }

                let skipCount: Int
                if let skips = testsuite.attribute(forName: "skipped")?.stringValue, let skipValue = Int(skips) {
                    // JUnit
                    skipCount = skipValue
                //} else if let skips = testsuite.children?.filter({ $0.name == "skipped" }).first {
                    // Swift test xunit output does not handle skipped tests; it just looks like it passed
                    // fixing this would invole updating the `func run(_ tests: [UnitTest]) throws -> [TestResult]` to include skip information at:
                    // https://github.com/apple/swift-package-manager/blob/main/Sources/Commands/SwiftTestTool.swift#L764C5-L764C57
                    //skipCount = 1
                } else {
                    skipCount = 0
                }

                guard let failures = testsuite.attribute(forName: "failures")?.stringValue,
                      let failureCount = Int(failures) else {
                    throw GradleDriverError.missingProperty(url: url, propertyName: "failures")
                }

                guard let errors = testsuite.attribute(forName: "errors")?.stringValue,
                      let errorCount = Int(errors) else {
                    throw GradleDriverError.missingProperty(url: url, propertyName: "errors")
                }

                guard let time = testsuite.attribute(forName: "time")?.stringValue,
                      let duration = TimeInterval(time) else {
                    throw GradleDriverError.missingProperty(url: url, propertyName: "time")
                }

                var testCases: [TestCase] = []

                func addTestCase(for element: XMLElement) throws {
                    testCases.append(try TestCase(from: element, in: url))
                }

                var systemOut = ""
                var systemErr = ""

                for childElement in testsuite.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                    switch childElement.name {
                    case "testcase":
                        try addTestCase(for: childElement)
                    case "system-out":
                        systemOut += childElement.stringValue ?? ""
                    case "system-err":
                        systemErr += childElement.stringValue ?? ""
                    case "properties":
                        break // TODO: figure out key/value format
                    default:
                        break // unrecognized key
                    }
                }

                let suite = TestSuite(name: testSuiteName, tests: testCount, skipped: skipCount, failures: failureCount, errors: errorCount, time: duration, testCases: testCases, systemOut: systemOut.isEmpty ? nil : systemOut, systemErr: systemErr.isEmpty ? nil : systemErr)
                suites.append(suite)
            }

            return suites
            #else
            // no XMLDocument on iOS
            return []
            #endif
        }
    }

    public struct TestCase {
        /// e.g.: someTestCaseThatAlwaysFails()
        public var name: String
        /// e.g.: sample.project.LibraryTest
        public var classname: String
        /// The amount of time it took the test case to run
        public var time: TimeInterval
        /// Whether the test was skipped by throwing `XCTSkip` (`org.junit.AssumptionViolatedException`)
        public var skipped: Bool
        /// The failures, if any
        public var failures: [TestFailure]

        public init(name: String, classname: String, time: TimeInterval, skipped: Bool, failures: [TestFailure]) {
            self.name = name
            self.classname = classname
            self.time = time
            self.skipped = skipped
            self.failures = failures
        }

        /// `classname.name` with any trailing "$" cruft trimmed off
        public var fullName: String {
            classname + "." + (name.split(separator: "$").first?.description ?? name)
        }

        #if os(macOS) || os(Linux) || targetEnvironment(macCatalyst)
        init(from element: XMLElement, in url: URL) throws {
            guard let testCaseName = element.attribute(forName: "name")?.stringValue else {
                throw GradleDriverError.missingProperty(url: url, propertyName: "name")
            }

            guard let classname = element.attribute(forName: "classname")?.stringValue else {
                throw GradleDriverError.missingProperty(url: url, propertyName: "classname")
            }

            guard let time = element.attribute(forName: "time")?.stringValue,
                let duration = TimeInterval(time) else {
                throw GradleDriverError.missingProperty(url: url, propertyName: "time")
            }

            self.name = testCaseName
            self.classname = classname
            self.time = duration

            var skipped = false
            for child in element.children ?? [] {
                if child.name == "skipped" {
                    skipped = true
                }
            }

            self.skipped = skipped

            var testFailures: [TestFailure] = []
            func addTestFailure(for element: XMLElement) throws {
                testFailures.append(try TestFailure(from: element, in: url))
            }


            for childElement in element.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                switch childElement.name {
                case "failure": try addTestFailure(for: childElement)
                default: break // unrecognized key
                }
            }

            self.failures = testFailures
        }
        #endif
    }

    public struct TestFailure {
        /// e.g.: "org.opentest4j.AssertionFailedError: THIS TEST CASE ALWAYS FAILS"
        public var message: String
        /// e.g.: "org.opentest4j.AssertionFailedError"
        public var type: String?
        /// e.g.: "at app//org.junit.jupiter.api.AssertionUtils.fail(AssertionUtils.java:38)"…
        public var contents: String?

        public init(message: String, type: String?, contents: String?) {
            self.message = message
            self.type = type
            self.contents = contents
        }

        #if os(macOS) || os(Linux) || targetEnvironment(macCatalyst)
        init(from element: XMLElement, in url: URL) throws {
            guard let message = element.attribute(forName: "message")?.stringValue else {
                throw GradleDriverError.missingProperty(url: url, propertyName: "message")
            }

            let type = element.attribute(forName: "type")?.stringValue

            let contents = element.stringValue
            
            self.message = message
            self.type = type
            self.contents = contents
        }
        #endif
    }

    private static func parseTestResults(in testFolder: URL?) throws -> [TestSuite] {
        guard let testFolder = testFolder else {
            return []
        }
        let fm = FileManager.default
        if !fm.fileExists(atPath: testFolder.path) {
            // missing folder
            throw GradleDriverError("The expected test output folder did not exist, which may indicate that the gradle process encountered a build error or other issue. Missing folder: \(testFolder.path)")
        }

        func parseTestSuite(resultURL: URL) throws -> [TestSuite] {
            if try resultURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != false {
                return []
            }

            if resultURL.pathExtension != "xml" {
                print("skipping non .xml test file:", resultURL.path)
                return []
            }

            return try TestSuite.parse(contentsOf: resultURL)
        }

        let dirs = try fm.contentsOfDirectory(at: testFolder, includingPropertiesForKeys: [.isDirectoryKey])

        // check each subdir (e.g., "build/test-results/test" and "build/test-results/testDebugUnitTest/" and "build/test-results/testReleaseUnitTest/"
        let subdirs = try dirs.flatMap({ try fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: [.isDirectoryKey]) })

        return try Array(subdirs.compactMap(parseTestSuite).joined())
    }
}

public enum GradleDriverError : Error, LocalizedError {
    public init(_ custom: String) {
        self = .custom(custom)
    }

    case custom(String)

    /// The command did not return any output
    case commandNoResult(String)

    /// The Gradle version could not be parsed from the output of `gradle --version`
    case noGradleVersion(gradle: URL, props: [String: String])

    /// The Gradle version is unsupported
    case gradleVersionTooLow(gradle: URL, version: Version, minimum: Version)

    /// The Kotlin version could not be parsed from the output of `gradle --version`
    case noKotlinVersion(gradle: URL)

    /// The Gradle version is unsupported
    case kotlinVersionTooLow(gradle: URL, version: Version, minimum: Version)

    /// A property was expected to have been found in the given URL
    case missingProperty(url: URL, propertyName: String)

    public var description: String {
        errorDescription ?? ""
    }

    public var errorDescription: String? {
        switch self {
        case .custom(let string):
            return string
        case .commandNoResult(let string):
            return "The command «\(string)» returned no result."
        case .noGradleVersion(let gradle, let props):
            return "The installed Gradle version from \(gradle.path) could not be parsed from \(props). Install with the command: brew install gradle."
        case .gradleVersionTooLow(let gradle, let version, let minimum):
            return "The Gradle version \(version) is below the minimum supported version \(minimum) at \(gradle.path). Update with the command: brew upgrade gradle."
        case .noKotlinVersion(let gradle):
            return "The instaled Kotlin version could not be parsed at \(gradle.path). Install with the command: brew install gradle."
        case .kotlinVersionTooLow(let gradle, let version, let minimum):
            return "The instaled Kotlin version \(version) is below the minimum supported version \(minimum) at \(gradle.path). Update with the command: brew upgrade gradle."
        case .missingProperty(let url, let propertyName):
            return "The property name “\(propertyName)” could not be found in \(url.path)"
        }
    }
}

extension ProcessInfo {
    /// The root path for Homebrew on this macOS
    public static let homebrewRoot: String = {
        ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"]
            ?? (ProcessInfo.isARM ? "/opt/homebrew" : "/usr/local")
    }()

    /// The current process environment along with the default paths to various tools set
    public var environmentWithDefaultToolPaths: [String: String] {
        var env = self.environment
        let ANDROID_HOME = "ANDROID_HOME"
        if (env[ANDROID_HOME] ?? "").isEmpty {
            #if os(macOS)
            env[ANDROID_HOME] = ("~/Library/Android/sdk" as NSString).expandingTildeInPath
            #elseif os(Windows)
            env[ANDROID_HOME] = ("~/AppData/Local/Android/Sdk" as NSString).expandingTildeInPath
            #elseif os(Linux)
            env[ANDROID_HOME] = ("~/Android/Sdk" as NSString).expandingTildeInPath
            #endif
        }

        let JAVA_HOME = "JAVA_HOME"
        if (env[JAVA_HOME] ?? "").isEmpty {
            #if os(macOS)
            // default to openjdk@17 if JAVA_HOME is unset
            env[JAVA_HOME] = "\(Self.homebrewRoot)/opt/openjdk@17"
            #endif
        }

        return env
    }
}

#endif
