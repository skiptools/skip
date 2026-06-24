// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ArgumentParser
import SkipSyntax
import TSCBasic
#if canImport(SkipDriveExternal)
import SkipDriveExternal
fileprivate let testCommandEnabled = true
#else
fileprivate let testCommandEnabled = false
#endif

/// The format for `skip test` result output: a human-readable `table` (default) or structured `json`.
enum TestOutputFormat: String, CaseIterable, ExpressibleByArgument {
    case table
    case json
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct TestCommand: SkipCommand, StreamingCommand, ToolOptionsCommand {
    typealias Output = MessageBlock
    
    static var configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Run parity tests and generate reports",
        usage: """
        # Run Swift and Kotlin parity tests
        skip test

        # Run tests for a specific project folder
        skip test --project path/to/project

        # Run tests on a connected Android device instead of Robolectric
        skip test --android-serial auto

        # Run tests targeting a specific emulator
        skip test --android-serial emulator-5554

        # Run a subset of Swift tests and matching Kotlin (Gradle --tests)
        skip test --filter URLTests
        """,
        discussion: """
        Builds and runs Swift (XCTest) and transpiled Kotlin (JUnit) tests, then \
        produces a side-by-side parity report. By default, Kotlin tests run locally \
        via Robolectric. Use --android-serial to run instrumented tests on a device or emulator.

        With --filter, the same patterns are passed to swift test (OR semantics) and also \
        forwarded to Gradle as --tests via the SKIP_TEST_FILTER environment variable when \
        the XCSkipTests harness runs.
        """,
        shouldDisplay: testCommandEnabled)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    // cannot use shared `BuildOptions` since it defaults `test` to false
    //@OptionGroup(title: "Build Options")
    //var buildOptions: BuildOptions

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Run the project tests"))
    var test: Bool = true

    @Option(help: ArgumentHelp("Test filter(s) for swift test and Gradle --tests", valueName: "pattern"))
    var filter: [String] = []

    @Option(help: ArgumentHelp("Project folder", valueName: "dir"))
    var project: String = "."

    @Option(help: ArgumentHelp("Path to xunit test report", valueName: "xunit.xml"))
    var xunit: String?

    @Option(help: ArgumentHelp("Path to junit test report", valueName: "folder"))
    var junit: String?

    @Option(help: ArgumentHelp("Maximum table column length", valueName: "n"))
    var maxColumnLength: Int = 25

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(name: [.customShort("c"), .long], help: ArgumentHelp("Configuration debug/release", valueName: "c"))
    var configuration: String = "debug"

    @Option(name: [.long], help: ArgumentHelp("Output summary table", valueName: "path"))
    var summaryFile: String?

    @Option(name: [.long], help: ArgumentHelp("Test result output format: table (default) or json", valueName: "format"))
    var testOutput: TestOutputFormat = .table

    @Option(name: [.long], help: ArgumentHelp("Write the test result output to this file instead of standard out", valueName: "path"))
    var testOutputFile: String?

    @Option(help: ArgumentHelp("Android device or emulator serial for instrumented tests (omit for local Robolectric testing)", valueName: "ANDROID_SERIAL"))
    var androidSerial: String?

    func performCommand(with out: MessageQueue) async {
        await withLogStream(with: out) {
            try await runTestCommand(with: out)
        }
    }
}

extension TestCommand {

    struct Stats {
        var passed: Int = 0
        var failed: Int = 0
        var skipped: Int = 0
        var missing: Int = 0

        var total: Int {
            passed + failed + skipped + missing
        }

        mutating func update(_ test: TestCaseInfo?) {
            if test?.skipped == true {
                skipped += 1
            } else if test?.hasFailures == true {
                failed += 1
            } else if test == nil {
                missing += 1
            } else {
                passed += 1
            }
        }

        var passRate: String {
            NumberFormatter.localizedString(from: (Double(passed) / Double(total)) as NSNumber, number: .percent)
        }
    }

    /// Next to the primary XCTest report, SwiftPM writes Swift Testing results to `<stem>-swift-testing.<ext>` when `--xunit-output` is passed as its own argument (not `--xunit-output=path`).
    private func swiftTestingXUnitCompanionPath(xunitPath: String) -> String {
        let url = URL(fileURLWithPath: xunitPath)
        let directory = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        return directory.appendingPathComponent("\(stem)-swift-testing.\(ext)").path
    }

    func runTestCommand(with out: MessageQueue) async throws {

        // only run tests when there is a Tests/ folder
        if !FileManager.default.fileExists(atPath: project + "/Tests") {
            await out.write(status: .fail, "No Tests folder in project: \(project)")
            return
        }

        // Resolve ANDROID_SERIAL when --android-serial is explicitly set
        var additionalEnv: [String: String] = [:]
        if let androidSerial = androidSerial {
            if let serial = try await resolveAndroidSerial(androidSerial: androidSerial, with: out) {
                additionalEnv["ANDROID_SERIAL"] = serial
            }
        }

        // Newline-separated patterns for XCGradleHarness (Gradle --tests); omit when unset so the harness runs the full Kotlin suite.
        if !filter.isEmpty {
            additionalEnv["SKIP_TEST_FILTER"] = filter.joined(separator: "\n")
        }

        let xunit = xunit ?? ".build/xcunit-\(UUID().uuidString).xml"

        var testResult: Result<ProcessOutput, Error>? = nil
        if test == true {
            var testArgs = ["swift", "test", "--parallel", "-c", configuration, "--enable-code-coverage", "--xunit-output", xunit, "--package-path", project]
            for pattern in filter {
                testArgs += ["--filter", pattern]
            }
            if !filter.isEmpty && !filter.contains("testSkipModule") {
                testArgs += ["--filter", "testSkipModule"]
            }
            testResult = try await run(with: out, "Test project", testArgs, additionalEnvironment: additionalEnv)
        } else if self.xunit == nil {
            // we can only use the generated xunit if we are running the tests
            throw SkipDriveError(errorDescription: "Must either specify --xunit path or run tests with --test")
        }

        #if !canImport(SkipDriveExternal)
        throw SkipDriveError(errorDescription: "SkipDrive not linked")
        #else
        // load XCTest XUnit and, when SwiftPM emits it, merge Swift Testing XUnit from the sibling file
        let primaryXunitURL = URL(fileURLWithPath: xunit)
        let primarySuites = try GradleDriver.TestSuite.parse(contentsOf: primaryXunitURL)
        let swiftTestingPath = swiftTestingXUnitCompanionPath(xunitPath: xunit)
        let swiftTestingSuites: [GradleDriver.TestSuite]
        if FileManager.default.fileExists(atPath: swiftTestingPath) {
            swiftTestingSuites = try GradleDriver.TestSuite.parse(contentsOf: URL(fileURLWithPath: swiftTestingPath))
        } else {
            swiftTestingSuites = []
        }
        let xunitResults = primarySuites + swiftTestingSuites
        if xunitResults.flatMap(\.testCases).isEmpty {
            throw SkipDriveError(errorDescription: "No test results found in \(xunit)" + (swiftTestingSuites.isEmpty ? "" : " or \(swiftTestingPath)"))
        }

        func testNameComparison(_ t1: TestCaseInfo, _ t2: TestCaseInfo) -> Bool {
            t1.classname < t2.classname || (t1.classname == t2.classname && t1.name < t2.name)
        }

        let xunitCasesAll = xunitResults.flatMap(\.testCases).sorted(by: testNameComparison)

        // <testcase classname="SkipZipTests.SkipZipTests" name="testSkipModule" time="7.729628">
        let skipModuleTests = xunitCasesAll.filter({ $0.name == "testSkipModule" })
        let xunitCases = xunitCasesAll.filter({ $0.name != "testSkipModule" })

        // A `mode: native` Swift Testing test module is a CONVENTIONAL Skip test module (skipstone plugin
        // + `SkipTest`), so it always produces a `testSkipModule` harness case and is driven through the
        // Gradle path below (connectedDebugAndroidTest on device / testDebug on Robolectric) — see the
        // generated runners + gradle blocks in SwiftTestingHarness.swift.
        if skipModuleTests.isEmpty {
            throw SkipDriveError(errorDescription: "Could not find Skip test testSkipModule in: \(xunitCases.map(\.name))")
        }

        let skipModules = skipModuleTests.compactMap({ ($0.classname.split(separator: ".").first)?.dropLast("Tests".count) })

        // XUnit: <testcase name="testDeflateInflate" classname="SkipZipTests.SkipZipTests" time="0.047230875">
        // JUnit: <testcase name="testDeflateInflate$SkipZip_debugUnitTest" classname="skip.zip.SkipZipTests" time="0.024"/>


        var allXunitStats: [Stats] = []
        var allJunitStats: [Stats] = []

        // per-module matched results, rendered together (table or json) after the loop
        var moduleResults: [(module: String, darwin: String, android: String, cases: [(xunit: TestCaseInfo, junit: TestCaseInfo?)])] = []

        // load the junit result folders
        for skipModule in skipModules {
            //outputOptions.write("skipModule: \(skipModule)")

            let junitFolder: URL
            if let junit = junit {
                // TODO: use the skip modules to form the junit path relative to the project folder
                // .build/plugins/outputs/skip-zip/SkipZipTests/skipstone/SkipZip/.build/SkipZip/test-results/testDebugUnitTest/TEST-skip.zip.SkipZipTests.xml
                junitFolder = URL(fileURLWithPath: junit, isDirectory: true)
            } else {
                let buildFolderBase = try AbsolutePath(validating: ".build", relativeTo: AbsolutePath(validating: project, relativeTo: AbsolutePath(validating: FileManager.default.currentDirectoryPath)))
                let testOutputBase = try buildPluginOutputFolder(forModule: skipModule + "Tests", inBuildFolder: buildFolderBase)

                // connectedAndroidTest (emulator/device) writes results under outputs/androidTest-results/connected/<config>;
                // testDebugUnitTest (Robolectric, no device) writes under test-results/test<Config>UnitTest.
                let testOutput: AbsolutePath
                if additionalEnv["ANDROID_SERIAL"] != nil {
                    testOutput = testOutputBase.appending(components: [skipModule.description, ".build", skipModule.description, "outputs", "androidTest-results", "connected", configuration])
                } else {
                    testOutput = testOutputBase.appending(components: [skipModule.description, ".build", skipModule.description, "test-results", "test\(configuration.capitalized)UnitTest"])
                }

                junitFolder = testOutput.asURL
            }

            var isDir: Foundation.ObjCBool = false
            if !FileManager.default.fileExists(atPath: junitFolder.path, isDirectory: &isDir) || isDir.boolValue == false {
                throw SkipDriveError(errorDescription: "JUnit test output folder did not exist at: \(junitFolder.path)")
            }

            let testResultFiles = try FileManager.default.contentsOfDirectory(at: junitFolder, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "xml" && $0.lastPathComponent.hasPrefix("TEST-") })
            if testResultFiles.isEmpty {
                throw SkipDriveError(errorDescription: "JUnit test output folder did not contain any results at: \(junitFolder.path)")
            }

            var junitCases: [TestCaseInfo] = []
            for testResultFile in testResultFiles {
                // load the xunit results file
                let junitResults = try GradleDriver.TestSuite.parse(contentsOf: testResultFile)
                if junitResults.count == 0 {
                    throw SkipDriveError(errorDescription: "No test results found in \(testResultFile)")
                }

                junitCases.append(contentsOf: junitResults.flatMap(\.testCases))
            }

            // A `mode: native` module runs its whole Swift Testing suite inside one JUnit case
            // (`SwiftTestRunner.nativeSwiftTests`), so Gradle only reports that aggregate. The native test
            // harness additionally writes the swt ABI-v0 event stream to `swt-events.jsonl` in the junit
            // output dir; recover per-test results from it so each test is reported individually (matched
            // against its host/Darwin counterpart) and the aggregate row is dropped.
            let swtEventsURL = junitFolder.appendingPathComponent("swt-events.jsonl")
            let nativeCases = FileManager.default.fileExists(atPath: swtEventsURL.path) ? parseNativeSwtEvents(swtEventsURL) : []
            junitCases.append(contentsOf: nativeCases.map { $0 as TestCaseInfo })

            // now we have all the test cases; for each xunit test, check for an equivalent JUnit test
            // note that xunit: classname="SkipZipTests.SkipZipTests" name="testDeflateInflate"
            // maps to junit: classname="skip.zip.SkipZipTests" name="testDeflateInflate$SkipZip_debugUnitTest"
            var matchedCases: [(xunit: TestCaseInfo, junit: TestCaseInfo?)] = []

            func junitModuleCases(for className: String) -> [TestCaseInfo] {
                junitCases.filter({ $0.classname.hasSuffix("." + className) })
            }

            for xunitCase in xunitCases.filter({ $0.classname.hasPrefix(skipModule + "Tests.") }) {
                let testName = xunitCase.name // e.g., testDeflateInflate
                // match xunit classname "SkipZipTests.SkipZipTests" to junit classname "skip.zip.SkipZipTests"
                let className = xunitCase.classname.split(separator: ".").last?.description ?? xunitCase.classname
                let junitModuleCases = junitModuleCases(for: className)

                // Swift Testing XUnit uses function-style names with "()", e.g. "add()"; JUnit Gradle output uses "add$SkipLib_debugUnitTest".
                let junitMatchLabel = testName.hasSuffix("()") ? String(testName.dropLast(2)) : testName
                // in JUnit, test names are sometimes the raw test name, and other times will be something like "testName$ModuleName_debugUnitTest"
                // async tests are prefixed with "run"
                let cases = junitModuleCases.filter({
                    $0.name == testName
                        || $0.name == junitMatchLabel
                        || $0.name.hasPrefix(junitMatchLabel + "$")
                        || $0.name.hasPrefix("run" + junitMatchLabel + "$")
                })
                if cases.count > 1 {
                    throw SkipDriveError(errorDescription: "Multiple conflicting XUnit and JUnit test cases named “\(testName)” in \(skipModule).")
                }

                if cases.count == 0 {
                    // permit missing cases (e.g., ones inside an #if !SKIP block)
                    // throw SkipDriveError(errorDescription: "Could not match XUnit and JUnit test case named “\(testName)” in \(skipModule).")
                }

                matchedCases.append((xunit: xunitCase, junit: cases.first))
            }

            // When per-test native results were recovered (above), they're matched individually, so the
            // aggregate `SwiftTestRunner.nativeSwiftTests` case is redundant. Only fall back to reporting it
            // directly (paired with itself) when no per-test stream was available, so its pass/fail still
            // shows rather than being silently dropped.
            if nativeCases.isEmpty {
                let matchedJunitNames = Set(matchedCases.compactMap(\.junit).map(\.name))
                for junitCase in junitCases where junitCase.classname.hasSuffix(".SwiftTestRunner") && !matchedJunitNames.contains(junitCase.name) {
                    matchedCases.append((xunit: junitCase, junit: junitCase))
                }
            }

            // Descriptive column titles: the host (XUnit) column is always Darwin/macOS; the Gradle (JUnit)
            // column reflects the Android build mode — Fuse-compiled native (the run produced a
            // SwiftTestRunner harness case) vs Lite-transpiled — and where it ran (a connected
            // device/emulator named by ANDROID_SERIAL, else Robolectric on the host JVM).
            let darwinTitle = "Darwin (macOS)"
            let androidMode = (junitCases.contains(where: { $0.classname.hasSuffix(".SwiftTestRunner") }) || !nativeCases.isEmpty) ? "Fuse" : "Lite"
            let androidTarget = additionalEnv["ANDROID_SERIAL"] ?? "Robolectric"
            let androidTitle = "Android (\(androidMode) \(androidTarget))"

            let (xunit, junit) = computeStats(matchedCases)
            allXunitStats.append(xunit)
            allJunitStats.append(junit)
            // collect for the post-loop render (table or json); the in-loop CI summary file stays markdown
            moduleResults.append((module: String(skipModule), darwin: darwinTitle, android: androidTitle, cases: matchedCases))

            // when we are running in CI, the "GITHUB_STEP_SUMMARY" contains the path of a file that can be used to write a markdown summary of the tests
            // https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#adding-a-job-summary
            if let summaryFile = self.summaryFile ?? ProcessInfo.processInfo.environment["GITHUB_STEP_SUMMARY"] ?? ProcessInfo.processInfo.environment["CI_STEP_SUMMARY"], !summaryFile.isEmpty {
                let (summaryTable, _, _) = createTestSummaryTable(columnLength: 1024, darwinTitle: darwinTitle, androidTitle: androidTitle, matchedCases, testNameComparison)

                if !FileManager.default.fileExists(atPath: summaryFile) {
                    _ = FileManager.default.createFile(atPath: summaryFile, contents: nil, attributes: nil)
                }

                if let handle = FileHandle(forWritingAtPath: summaryFile) {
                    defer { try? handle.close() }
                    handle.seekToEndOfFile()
                    try? handle.write(contentsOf: (summaryTable + "\n").utf8Data)
                }
            }
        }

        // render the collected results in the requested format and route them to a file or standard out
        let outputText: String
        switch testOutput {
        case .table:
            outputText = moduleResults.map { createTestSummaryTable(columnLength: maxColumnLength, darwinTitle: $0.darwin, androidTitle: $0.android, $0.cases, testNameComparison).table }.joined(separator: "\n")
        case .json:
            outputText = try renderJSONReport(moduleResults, testNameComparison)
        }
        if let testOutputFile = self.testOutputFile, !testOutputFile.isEmpty {
            try outputText.write(toFile: testOutputFile, atomically: true, encoding: .utf8)
            await out.write(status: nil, "Wrote \(testOutput.rawValue) test results to \(testOutputFile)")
        } else {
            await out.write(status: nil, outputText)
        }

        let exitCode = try? testResult?.get().exitCode

        let aggregateStats = { ($0 as [Stats]).reduce(into: Stats()) { stats, result in
            stats.failed += result.failed
            stats.passed += result.passed
            stats.skipped += result.skipped
            stats.missing += result.missing
        }
        }

        let allJStats = aggregateStats(allJunitStats)
        let allXStats = aggregateStats(allXunitStats)

        let totalFailures = allJStats.failed + allXStats.failed
        let totalMissing = allJStats.missing + allXStats.missing

        if totalFailures > 0 {
            await out.yield(MessageBlock(status: .fail, "Tests failed with \(totalFailures) failures"))
        } else if totalMissing > 0 {
            await out.yield(MessageBlock(status: .warn, "Tests (\(allXStats.passed) / \(allJStats.passed)) passed with \(totalMissing) missing"))
        } else if let code = exitCode, code != 0 {
            //await out.yield(with: .failure(TestFailureError(errorDescription: "Tests failed with exit: \(code)")))
            await out.yield(MessageBlock(status: .fail, "Tests failed with exit: \(code)"))
        } else {
            await out.yield(MessageBlock(status: .pass, "Tests \(allXStats.passed) / \(allJStats.passed) passed"))
        }
        #endif
    }

    /// Parse the native test harness's swt ABI-v0 JSON event stream (`swt-events.jsonl`, one record per
    /// line) into per-test results. The `kind:"test"`/`kind:"function"` records catalog each test's
    /// function-style `name` and its `id` (`<Module.Suite>/<fn()>/<file>:<line>:<col>`); the
    /// `kind:"event"` `testEnded`/`issueRecorded`/`testSkipped` records (keyed by `testID`) give pass/
    /// fail/skip. Returns one `NativeTestCase` per function that ran, with `classname` = the suite id
    /// (so it matches the host xunit case for the same test) and `name` = the function name.
    private func parseNativeSwtEvents(_ url: URL) -> [NativeTestCase] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        struct State { var failed = false; var skipped = false; var ran = false; var started: Double? = nil; var ended: Double? = nil }
        var names: [String: String] = [:]    // function id -> "demoFramework()"
        var suites: [String: String] = [:]   // function id -> "Module.Suite"
        var states: [String: State] = [:]
        func instant(_ payload: [String: Any]) -> Double? { (payload["instant"] as? [String: Any])?["absolute"] as? Double }
        for line in text.split(separator: "\n") {
            // Tolerate any leading text before the JSON object: the connected (device) path recovers the
            // stream from logcat, where some records arrive raw and others carry a "Test line: " prefix.
            guard let brace = line.firstIndex(of: "{") else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line[brace...].utf8)) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any] else { continue }
            switch obj["kind"] as? String {
            case "test":
                if (payload["kind"] as? String) == "function",
                   let id = payload["id"] as? String, let name = payload["name"] as? String {
                    names[id] = name
                    suites[id] = String(id.prefix(while: { $0 != "/" }))   // "Module.Suite" before the first '/'
                }
            case "event":
                guard let testID = payload["testID"] as? String, names[testID] != nil else { break }
                switch payload["kind"] as? String {
                case "testStarted":
                    states[testID, default: State()].started = instant(payload)
                case "issueRecorded":
                    if let issue = payload["issue"] as? [String: Any], (issue["isFailure"] as? Bool) == true {
                        states[testID, default: State()].failed = true
                    }
                case "testSkipped":
                    states[testID, default: State()].skipped = true
                    states[testID, default: State()].ran = true
                case "testEnded":
                    let symbol = (payload["messages"] as? [[String: Any]])?.first?["symbol"] as? String
                    if symbol == "fail" { states[testID, default: State()].failed = true }
                    states[testID, default: State()].ended = instant(payload)
                    states[testID, default: State()].ran = true
                default: break
                }
            default: break
            }
        }
        return names.compactMap { id, name in
            guard let state = states[id], state.ran else { return nil }   // only tests that actually ran
            // duration from the testStarted/testEnded monotonic `absolute` instants (0 = unknown)
            let duration: TimeInterval
            if let started = state.started, let ended = state.ended { duration = max(0, ended - started) } else { duration = 0 }
            return NativeTestCase(name: name, classname: suites[id] ?? "", time: duration, skipped: state.skipped, hasFailures: state.failed)
        }
    }

    /// The Darwin (xunit) and Android (junit) pass/fail/skip/missing tallies for a module's matched cases.
    private func computeStats(_ matchedCases: [(xunit: TestCaseInfo, junit: TestCaseInfo?)]) -> (xunit: Stats, junit: Stats) {
        var (xunitStats, junitStats) = (Stats(), Stats())
        for (xunit, junit) in matchedCases {
            xunitStats.update(xunit)
            junitStats.update(junit)
        }
        return (xunitStats, junitStats)
    }

    /// Render the matched results across all modules as a structured JSON document (per-test status +
    /// duration for each platform, plus per-platform tallies). Slashes are left unescaped for readability.
    private func renderJSONReport(_ moduleResults: [(module: String, darwin: String, android: String, cases: [(xunit: TestCaseInfo, junit: TestCaseInfo?)])], _ testNameComparison: (TestCaseInfo, TestCaseInfo) -> Bool) throws -> String {
        func result(_ test: TestCaseInfo?) -> TestReport.Result? {
            guard let test = test else { return nil }   // unmatched on this platform
            let status = test.skipped ? "skip" : test.hasFailures ? "fail" : "pass"
            return TestReport.Result(status: status, time: test.time > 0 ? test.time : nil)
        }
        var (allXunit, allJunit) = (Stats(), Stats())
        let modules: [TestReport.Module] = moduleResults.map { mr in
            let cases: [TestReport.Case] = mr.cases.sorted(by: { testNameComparison($0.xunit, $1.xunit) }).map { (xunit, junit) in
                allXunit.update(xunit)
                allJunit.update(junit)
                return TestReport.Case(suite: xunit.classname.split(separator: ".").last?.description ?? xunit.classname, name: xunit.name, darwin: result(xunit), android: result(junit))
            }
            return TestReport.Module(module: mr.module, darwin: mr.darwin, android: mr.android, cases: cases)
        }
        func counts(_ s: Stats) -> TestReport.Counts { TestReport.Counts(passed: s.passed, failed: s.failed, skipped: s.skipped, missing: s.missing) }
        let report = TestReport(modules: modules, summary: TestReport.Summary(darwin: counts(allXunit), android: counts(allJunit)))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(report), as: UTF8.self)
    }

    private func createTestSummaryTable(columnLength: Int, darwinTitle: String, androidTitle: String, _ matchedCases: [(xunit: TestCaseInfo, junit: TestCaseInfo?)], _ testNameComparison: (TestCaseInfo, TestCaseInfo) -> Bool) -> (table: String, xunit: Stats, junit: Stats) {
        // now output all of the test cases
        var outputColumns: [[String]] = [[], [], [], []]

        func addSeparator() {
            (0..<outputColumns.count).forEach({ outputColumns[$0].append("-") }) // add header dashes
        }

        /// Add a row with the given columns
        func addRow(_ values: [String]) {
            values.enumerated().forEach({ outputColumns[$0.offset].append($0.element) })
        }

        //addSeparator()
        addRow(["Test", "Case", darwinTitle, androidTitle])
        addSeparator()

        var (xunitStats, junitStats) = (Stats(), Stats())
        for (xunit, junit) in matchedCases.sorted(by: { testNameComparison($0.xunit, $1.xunit) }) {
            let testName = xunit.name
            outputColumns[0].append(xunit.classname.split(separator: ".").last?.description ?? "")
            outputColumns[1].append(testName)

            xunitStats.update(xunit)
            junitStats.update(junit)

            func desc(_ test: TestCaseInfo?) -> String {
                guard let test = test else {
                    return "????" // unmatched
                }
                var result = (test.skipped == true ? "SKIP" : test.hasFailures ? "FAIL" : "PASS")
                // append the per-test duration when known (0 = unknown, e.g. an unmatched/aggregate case)
                if test.time > 0 {
                    result += String(format: " (%.2fs)", test.time)
                }
                return result
            }

            outputColumns[2].append(desc(xunit))
            outputColumns[3].append(desc(junit))
        }

        // add summary
        //addSeparator()  // add footer dashes
        addRow(["", "", xunitStats.passRate, junitStats.passRate])
        //addSeparator()  // add footer dashes

        // pad all the columns for nice output
        let lengths = outputColumns.map({ $0.reduce(0, { max($0, $1.count) })})
        for (index, length) in lengths.enumerated() {
            // Cap the variable-length Test/Case columns at columnLength; let the fixed Darwin/Android
            // result-column headers size to their full width so the mode/device labels aren't truncated.
            let width = index <= 1 ? min(length, columnLength) : length
            outputColumns[index] = outputColumns[index].map { $0.pad(width, paddingCharacter: $0 == "-" ? "-" : " ") }
        }

        let rowCount = outputColumns.map({ $0.count }).min() ?? 0
        var testsTable = ""
        for row in 0..<rowCount {
            let row = outputColumns.map({ $0[row] })

            // these look nice in the terminal, but they don't generate valid markdown tables
            // header columns are all "-"
            //let sep = Set(row.flatMap({ Array($0) })) == ["-"] ? "-" : " "
            // corners of headers are "+"
            //let term = sep == "-" ? "+" : "|"

            let sep = " "
            let div = "|"

            testsTable += div
            for cell in row {
                testsTable += sep + cell + sep + div
            }
            testsTable += "\n"
        }

        return (testsTable, xunitStats, junitStats)
    }
}

/// The structured `skip test` results emitted by `--test-output=json`: per-test status and duration on
/// each platform, plus per-platform tallies. A `null` per-platform result means the test was unmatched
/// there; a `null`/omitted `time` means the duration is unknown (e.g. an aggregate or unmatched case).
struct TestReport: Encodable {
    struct Result: Encodable {
        let status: String          // "pass" / "fail" / "skip"
        let time: TimeInterval?     // seconds; omitted when unknown
    }
    struct Case: Encodable {
        let suite: String
        let name: String
        let darwin: Result?
        let android: Result?
    }
    struct Module: Encodable {
        let module: String
        let darwin: String          // Darwin column title
        let android: String         // Android column title
        let cases: [Case]
    }
    struct Counts: Encodable {
        let passed: Int
        let failed: Int
        let skipped: Int
        let missing: Int
    }
    struct Summary: Encodable {
        let darwin: Counts
        let android: Counts
    }
    let modules: [Module]
    let summary: Summary
}

protocol TestCaseInfo {
    /// e.g.: someTestCaseThatAlwaysFails()
    var name: String { get }
    /// e.g.: sample.project.LibraryTest
    var classname: String { get }
    /// The amount of time it took the test case to run
    var time: TimeInterval { get }
    /// Whether the test was skipped by throwing `XCTSkip` (`org.junit.AssumptionViolatedException`)
    var skipped: Bool { get }
    /// The failures, if any
    var hasFailures: Bool { get }
}

/// A per-test result synthesized from a `mode: native` module's swt event stream, so each native Swift
/// Testing case can be reported (and matched against its host/Darwin counterpart) individually.
struct NativeTestCase: TestCaseInfo {
    var name: String
    var classname: String
    var time: TimeInterval
    var skipped: Bool
    var hasFailures: Bool
}

#if canImport(SkipDriveExternal) // needed for GradleDriver.TestCase
extension GradleDriver.TestCase : TestCaseInfo {
    var hasFailures: Bool {
        !failures.isEmpty
    }
}
#endif


extension ToolOptionsCommand where Self : OutputOptionsCommand & StreamingCommand  {

    func runSkipTests(in projectFolderURL: URL, configuration: String, swift: Bool, kotlin: Bool, separateModule: String? = "testSkipModule", with out: MessageQueue) async throws {
        let env = ProcessInfo.processInfo.environmentWithDefaultToolPaths // an environment with a default ANDROID_HOME
        if let separateModule = separateModule {
            try await run(with: out, "Test Swift", ["swift", "test", "--verbose", "--configuration", configuration, "--skip", separateModule, "--package-path", projectFolderURL.path], environment: env)

            try await run(with: out, "Test Kotlin", ["swift", "test", "--verbose", "--configuration", configuration, "--filter", "testSkipModule", "--package-path", projectFolderURL.path], environment: env)
        } else {
            // run Swift and Kotlin tests at the same time
            try await run(with: out, "Test Project", ["swift", "test", "--verbose", "--configuration", configuration, "--package-path", projectFolderURL.path], environment: env)
        }
    }
}

