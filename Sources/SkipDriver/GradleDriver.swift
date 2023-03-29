// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation

#if os(macOS) || os(Linux)
/// The `GradleDriver` controls the execution of the `gradle` tool,
/// which is expected to already be installed on the system in the
/// user's `PATH` environment.
public struct GradleDriver {
    /// The minimum version of Kotlin we can work with
    public static let minimumKotlinVersion = Version(1, 8, 0)

    /// The minimum version of Gradle that we can work with
    /// https://github.com/actions/runner-images/blob/main/images/macos/macos-12-Readme.md#project-management
    public static let minimumGradleVersion = Version(8, 0, 1)

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
    public init() async throws {
        self.gradlePath = try Self.findGradle()
        self.gradleArgs = [
            gradlePath.path,
        ]

        self.gradleInfo = try await Self.execGradleInfo(gradleArgs: self.gradleArgs)

        guard let gradleVersionString = self.gradleInfo["Gradle"],
              let gradleVersion = Version(gradleVersionString) else {
            throw GradleDriverError.noGradleVersion(gradle: self.gradlePath)
        }

        self.gradleVersion = gradleVersion
        if self.gradleVersion < Self.minimumGradleVersion {
            throw GradleDriverError.gradleVersionTooLow(gradle: self.gradlePath, version: self.gradleVersion, minimum: Self.minimumGradleVersion)
        }

        guard let kotlinVersionString = self.gradleInfo["Kotlin"],
              let kotlinVersion = Version(kotlinVersionString) else {
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

    /// Locates the given tool in the user's path
    public static func findInPath(toolName: String, withAdditionalPaths extraPATH: [String]) throws -> URL {
        let env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? ""
        let pathParts = path.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
        for pathPart in pathParts + extraPATH {
            let dir = URL(fileURLWithPath: pathPart, isDirectory: true)
            let exePath = URL(fileURLWithPath: toolName, relativeTo: dir)
            if FileManager.default.isExecutableFile(atPath: exePath.path) {
                return exePath
            }
        }

        throw GradleDriverError.toolPathNotFound(toolName)
    }

    /// Executes `gradle` with the current default arguments and the additional args and returns an async stream of the lines from the combined standard err and standard out.
    public func execGradle(in workingDirectory: URL, args: [String], env: [String: String] = [:], onExit: @escaping (ProcessResult) throws -> ()) async throws -> Process.AsyncLineOutput {
        // the resulting command will be something like:
        // java -Xmx64m -Xms64m -Dorg.gradle.appname=gradle -classpath /opt/homebrew/Cellar/gradle/8.0.2/libexec/lib/gradle-launcher-8.0.2.jar org.gradle.launcher.GradleMain info
        #if DEBUG
        // output the launch message in a format that makes it easy to copy and paste the result into the terminal
        print("execGradle:", env.keys.sorted().map { $0 + "=\"" + env[$0, default: ""] + "\"" }.joined(separator: " "), (gradleArgs + args).joined(separator: " "))
        #endif

        // transfer process environment along with the additional environment
        var penv = ProcessInfo.processInfo.environment
        for (key, value) in env {
            penv[key] = value
        }
        return Process.streamLines(command: gradleArgs + args, environment: penv, workingDirectory: workingDirectory, onExit: onExit)
    }

    /// Invokes the tests for the given gradle project.
    /// - Parameters:
    ///   - check: whether to run "grade check" or "gradle test"
    ///   - failFast: whether to pass the "--fail-fast" flag
    ///   - continue: whether to permit failing tests to complete with the "--continue" flag
    ///   - offline: whether to pass the "--offline" flag
    ///   - rerunTasks: whether to pass the "--rerun-tasks" flag
    ///   - workingDirectory: the directory in which to fork the gradle process
    ///   - module: the name of the module to test
    ///   - testResultPath: the relative path for the test output XML files
    ///   - exitHandler: the exit handler, which may want to permit a process failure in order to have time to parse the tests
    /// - Returns: an array of parsed test suites containing information about the test run
    public func runTests(in workingDirectory: URL, module: String, check: Bool = false, info infoFlag: Bool = false, plain plainFlag: Bool = true, maxTestMemory: UInt64? = nil, failFast failFastFlag: Bool = false, continue continueFlag: Bool = false, offline offlineFlag: Bool = false, rerunTasks rerunTasksFlag: Bool = true, testResultPath: String = "build/test-results", exitHandler: @escaping (ProcessResult) throws -> ()) async throws -> (output: Process.AsyncLineOutput, result: () throws -> [TestSuite]) {
        var args = [
            check ? "check" : "test" // check will run the @Test funcs regardless of @Ignore, as well as other checks
        ]

        var env: [String: String] = [:]

        // add in the project dir for explicitness (even though it is assumed from the current working directory as well)
        args += ["--project-dir", workingDirectory.path]

        // this can also be set in a top-level gradle.properties file, but we include it here for good measure
        args += ["-Pandroid.useAndroidX=true"]

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

        if plainFlag {
            args += ["--console=plain"]
        }

        if let maxTestMemory = maxTestMemory {
            // attempt to run in the same process without forking the daemon
            args += ["--no-daemon"]

            // also need to add in JVM flags, lest we be countermanded with: “To honour the JVM settings for this build a single-use Daemon process will be forked. See https://docs.gradle.org/8.0.2/userguide/gradle_daemon.html#sec:disabling_the_daemon.”
            // these seem to be quite specific to the gradle version being used, so disabling the daemon in future gradle versions might require tweaking these args (which can be seen by enabling the info flag):

            // Checking if the launcher JVM can be re-used for build. To be re-used, the launcher JVM needs to match the parameters required for the build process: -Xms256m -Xmx512m -Dfile.encoding=UTF-8 -Duser.country=US -Duser.language=en -Duser.variant

            var jvmargs: [String] = []

            jvmargs += ["-Dfile.encoding=UTF-8"]
            jvmargs += ["-Xms256m"]

            // make a nice memory string if we are dividible by kb/mb/gb
            let memstr: String
            let kb = Double(maxTestMemory) / 1024
            let mb = kb / 1024
            let gb = mb / 1024
            if round(gb) == gb {
                memstr = "\(Int64(gb))g"
            } else if round(mb) == mb {
                memstr = "\(Int64(mb))m"
            } else if round(kb) == kb {
                memstr = "\(Int64(kb))k"
            } else {
                memstr = maxTestMemory.description // raw bytes description
            }

            jvmargs += ["-Xmx\(memstr)"]

            env["GRADLE_OPTS"] = jvmargs.joined(separator: " ")
            //args += ["-Dorg.gradle.jvmargs=" + jvmargs.joined(separator: " ")]

        }

        let moduleURL = URL(fileURLWithPath: module, isDirectory: true, relativeTo: workingDirectory)
        if !FileManager.default.fileExists(atPath: moduleURL.path) {
            throw URLError(.fileDoesNotExist, userInfo: [NSFilePathErrorKey: moduleURL.path])
        }

        let testResultFolder = URL(fileURLWithPath: testResultPath, isDirectory: true, relativeTo: moduleURL)
        try? FileManager.default.trashItem(at: testResultFolder, resultingItemURL: nil) // remove the test folder, since a build failure won't clear it and it will appear as if the tests ran successfully

        let output = try await execGradle(in: workingDirectory, args: args, env: env, onExit: exitHandler)
        return (output, { try Self.parseTestResults(in: testResultFolder) })
    }

    /// Executes `skiptool info` and returns the info dictionary.
    private static func execGradleInfo(gradleArgs: [String]) async throws -> [String: String] {
        // gradle --version will output an unstructued mess like this:
        /*
         ------------------------------------------------------------
         Gradle 8.0.2
         ------------------------------------------------------------

         Build time:   2023-03-03 16:41:37 UTC
         Revision:     7d6581558e226a580d91d399f7dfb9e3095c2b1d

         Kotlin:       1.8.10
         Groovy:       3.0.13
         Ant:          Apache Ant(TM) version 1.10.11 compiled on July 10 2021
         JVM:          19.0.2 (Homebrew 19.0.2)
         OS:           Mac OS X 13.2.1 aarch64
         */

        let lines = try await Process.streamLines(command: gradleArgs + ["--version"], onExit: Process.expectZeroExitCode).reduce([]) { $0 + [$1] }
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
        let homeBrewPaths = [
            "/opt/homebrew/bin", // ARM
            "/usr/local/bin", // Intel
        ]
        return try findInPath(toolName: "gradle", withAdditionalPaths: homeBrewPaths)
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

        #if os(macOS) || os(Linux)
        /// Loads the test suite information from the JUnit-compatible XML format.
        @available(macOS 10.15, *)
        @available(iOS, unavailable)
        public init(contentsOf url: URL) throws {
            let results = try XMLDocument(contentsOf: url)
            //print("parsed XML results:", results)

            guard let testsuite = results.rootElement(),
                  testsuite.name == "testsuite" else {
                throw GradleDriverError.missingProperty(url: url, propertyName: "testsuite")
            }

            guard let testSuiteName = testsuite.attribute(forName: "name")?.stringValue else {
                throw GradleDriverError.missingProperty(url: url, propertyName: "name")
            }

            guard let tests = testsuite.attribute(forName: "tests")?.stringValue,
                let testCount = Int(tests) else {
                throw GradleDriverError.missingProperty(url: url, propertyName: "tests")
            }

            guard let skips = testsuite.attribute(forName: "skipped")?.stringValue,
                let skipCount = Int(skips) else {
                throw GradleDriverError.missingProperty(url: url, propertyName: "skipped")
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
            self = suite
        }
        #endif
    }

    public struct TestCase {
        /// e.g.: someTestCaseThatAlwaysFails()
        public var name: String
        /// e.g.: sample.project.LibraryTest
        public var classname: String
        /// The amount of time it took the test case to run
        public var time: TimeInterval
        /// The failures, if any
        public var failures: [TestFailure]

        public init(name: String, classname: String, time: TimeInterval, failures: [TestFailure]) {
            self.name = name
            self.classname = classname
            self.time = time
            self.failures = failures
        }

        #if os(macOS) || os(Linux)
        @available(macOS 10.15, *)
        @available(iOS, unavailable)
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
        public var type: String
        /// e.g.: "at app//org.junit.jupiter.api.AssertionUtils.fail(AssertionUtils.java:38)"…
        public var contents: String?

        public init(message: String, type: String, contents: String?) {
            self.message = message
            self.type = type
            self.contents = contents
        }

        #if os(macOS) || os(Linux)
        @available(macOS 10.15, *)
        @available(iOS, unavailable)
        init(from element: XMLElement, in url: URL) throws {
            guard let message = element.attribute(forName: "message")?.stringValue else {
                throw GradleDriverError.missingProperty(url: url, propertyName: "message")
            }

            guard let type = element.attribute(forName: "type")?.stringValue else {
                throw GradleDriverError.missingProperty(url: url, propertyName: "type")
            }

            let contents = element.stringValue
            
            self.message = message
            self.type = type
            self.contents = contents
        }
        #endif
    }

    #if os(macOS) || os(Linux)
    private static func parseTestResults(in testFolder: URL) throws -> [TestSuite] {
        let fm = FileManager.default
        if !fm.fileExists(atPath: testFolder.path) {
            // missing folder
            throw URLError(.fileDoesNotExist, userInfo: [NSFilePathErrorKey: testFolder.path])
        }

        func parseTestSuite(resultURL: URL) throws -> TestSuite? {
            if try resultURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != false {
                return Optional<TestSuite>.none
            }

            if resultURL.pathExtension != "xml" {
                print("skipping non .xml test file:", resultURL.path)
                return Optional<TestSuite>.none
            }

            return try TestSuite(contentsOf: resultURL)
        }

        let dirs = try fm.contentsOfDirectory(at: testFolder, includingPropertiesForKeys: [.isDirectoryKey])

        // check each subdir (e.g., "build/test-results/test" and "build/test-results/testDebugUnitTest/" and "build/test-results/testReleaseUnitTest/"
        let subdirs = try dirs.flatMap({ try fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: [.isDirectoryKey]) })

        return try subdirs.compactMap(parseTestSuite)
    }
    #endif
}

public enum GradleDriverError : Error, LocalizedError {
    case toolPathNotFound(String)

    /// The command did not return any output
    case commandNoResult(String)

    /// The Gradle version could not be parsed from the output of `gradle --version`
    case noGradleVersion(gradle: URL)
    /// The Gradle version is unsupported
    case gradleVersionTooLow(gradle: URL, version: Version, minimum: Version)

    /// The Kotlin version could not be parsed from the output of `gradle --version`
    case noKotlinVersion(gradle: URL)
    /// The Gradle version is unsupported
    case kotlinVersionTooLow(gradle: URL, version: Version, minimum: Version)

    /// A property was expected to have been found in the given URL
    case missingProperty(url: URL, propertyName: String)

    public var errorDescription: String? {
        switch self {
        case .toolPathNotFound(let string):
            return "Could not locate tool: «\(string)»"
        case .commandNoResult(let string):
            return "The command «\(string)» returned no result."
        case .noGradleVersion(let gradle):
            return "The instaled Gradle version from \(gradle.path) could not be parsed at \(gradle.path). Install with the command: brew install gradle."
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
#endif // os(macOS) || os(Linux)
