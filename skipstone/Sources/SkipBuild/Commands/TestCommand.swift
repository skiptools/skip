import Foundation
import Darwin
import ArgumentParser
import SkipSyntax
#if canImport(SkipDrive)
import SkipDrive
fileprivate let testCommandEnabled = true
#else
fileprivate let testCommandEnabled = false
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct TestCommand: SkipCommand {
    static var configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Run parity tests and generate reports",
        shouldDisplay: testCommandEnabled)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    // cannot use shared `BuildOptions` since it defaults `test` to false
    //@OptionGroup(title: "Build Options")
    //var buildOptions: BuildOptions

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Run the project tests"))
    var test: Bool = true

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

    func run() async throws {
        let xunit = xunit ?? ".build/xcunit-\(UUID().uuidString).xml"

        func packageName() async throws -> String {
            let packageJSONString = try await outputOptions.run("Checking project", [toolOptions.swift, "package", "dump-package", "--package-path", project]).out
            let packageJSON = try JSONDecoder().decode(PackageManifest.self, from: Data(packageJSONString.utf8))
            let packageName = packageJSON.name
            return packageName
        }

        if test == true {
            try await outputOptions.run("Testing project", [toolOptions.swift, "test", "--parallel", "-c", configuration, "--enable-code-coverage", "--xunit-output", xunit, "--package-path", project])
        } else if self.xunit == nil {
            // we can only use the generated xunit if we are running the tests
            throw SkipDriveError(errorDescription: "Must either specify --xunit path or run tests with --test")
        }

        #if !canImport(SkipDrive)
        throw SkipDriveError(errorDescription: "SkipDrive not linked")
        #else
        // load the xunit results file
        let xunitResults = try GradleDriver.TestSuite.parse(contentsOf: URL(fileURLWithPath: xunit))
        if xunitResults.count == 0 {
            throw SkipDriveError(errorDescription: "No test results found in \(xunit)")
        }


        func testNameComparison(_ t1: GradleDriver.TestCase, _ t2: GradleDriver.TestCase) -> Bool {
            t1.classname < t2.classname || (t1.classname == t2.classname && t1.name < t2.name)
        }

        let xunitCases = xunitResults.flatMap(\.testCases).sorted(by: testNameComparison)

        // <testcase classname="SkipZipKtTests.SkipZipKtTests" name="testSkipModule" time="7.729628">
        let skipModuleTests = xunitCases.filter({ $0.name == "testSkipModule" && $0.classname.split(separator: ".").first?.hasSuffix("KtTests") == true })

        if skipModuleTests.isEmpty {
            throw SkipDriveError(errorDescription: "Could not find Skip test testSkipModule in: \(xunitCases.map(\.name))")
        }

        let skipModules = skipModuleTests.compactMap({ ($0.classname.split(separator: ".").first)?.dropLast("KtTests".count) })

        // XUnit: <testcase name="testDeflateInflate" classname="SkipZipTests.SkipZipTests" time="0.047230875">
        // JUnit: <testcase name="testDeflateInflate$SkipZip_debugUnitTest" classname="skip.zip.SkipZipTests" time="0.024"/>

        // load the junit result folders
        for skipModule in skipModules {
            //outputOptions.write("skipModule: \(skipModule)")

            let junitFolder: URL
            if let junit = junit {
                // TODO: use the skip modules to form the junit path relative to the project folder
                // .build/plugins/outputs/skip-zip/SkipZipKtTests/skip-transpiler/SkipZip/.build/SkipZip/test-results/testDebugUnitTest/TEST-skip.zip.SkipZipTests.xml
                junitFolder = URL(fileURLWithPath: junit, isDirectory: true)
            } else {
                let packageName = try await packageName()
                let testOutput = ".build/plugins/outputs/\(packageName)/\(skipModule)KtTests/skip-transpiler/\(skipModule)/.build/\(skipModule)/test-results/test\(configuration.capitalized)UnitTest/"
                junitFolder = URL(fileURLWithPath: testOutput, isDirectory: true)
            }

            var isDir: Foundation.ObjCBool = false
            if !FileManager.default.fileExists(atPath: junitFolder.path, isDirectory: &isDir) || isDir.boolValue == false {
                throw SkipDriveError(errorDescription: "JUnit test output folder did not exist at: \(junitFolder.path)")
            }

            let testResultFiles = try FileManager.default.contentsOfDirectory(at: junitFolder, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "xml" && $0.lastPathComponent.hasPrefix("TEST-") })
            if testResultFiles.isEmpty {
                throw SkipDriveError(errorDescription: "JUnit test output folder did not contain any results at: \(junitFolder.path)")
            }

            var junitCases: [GradleDriver.TestCase] = []
            for testResultFile in testResultFiles {
                // load the xunit results file
                let junitResults = try GradleDriver.TestSuite.parse(contentsOf: testResultFile)
                if junitResults.count == 0 {
                    throw SkipDriveError(errorDescription: "No test results found in \(testResultFile)")
                }

                junitCases.append(contentsOf: junitResults.flatMap(\.testCases))
            }

            // now we have all the test cases; for each xunit test, check for an equivalent JUnit test
            // note that xunit: classname="SkipZipTests.SkipZipTests" name="testDeflateInflate"
            // maps to junit: classname="skip.zip.SkipZipTests" name="testDeflateInflate$SkipZip_debugUnitTest"
            var matchedCases: [(xunit: GradleDriver.TestCase, junit: GradleDriver.TestCase?)] = []

            func junitModuleCases(for className: String) -> [GradleDriver.TestCase] {
                junitCases.filter({ $0.classname.hasSuffix("." + className) })
            }

            for xunitCase in xunitCases.filter({ $0.classname.hasPrefix(skipModule + "Tests.") }) {
                let testName = xunitCase.name // e.g., testDeflateInflate
                // match xunit classname "SkipZipTests.SkipZipTests" to junit classname "skip.zip.SkipZipTests"
                let className = xunitCase.classname.split(separator: ".").last?.description ?? xunitCase.classname
                let junitModuleCases = junitModuleCases(for: className)

                // in JUnit, test names are sometimes the raw test name, and other times will be something like "testName$ModuleName_debugUnitTest"
                // async tests are prefixed with "run"
                let cases = junitModuleCases.filter({ $0.name == testName || $0.name.hasPrefix(testName + "$") || $0.name.hasPrefix("run" + testName + "$") })
                if cases.count > 1 {
                    throw SkipDriveError(errorDescription: "Multiple conflicting XUnit and JUnit test cases named “\(testName)” in \(skipModule).")
                }

                if cases.count == 0 {
                    // permit missing cases (e.g., ones inside an #if !SKIP block)
                    // throw SkipDriveError(errorDescription: "Could not match XUnit and JUnit test case named “\(testName)” in \(skipModule).")
                }
                matchedCases.append((xunit: xunitCase, junit: cases.first))
            }

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
            addRow(["Test", "Case", "Swift", "Kotlin"])
            addSeparator()

            struct Stats {
                var passed: Int = 0
                var failed: Int = 0
                var skipped: Int = 0
                var missing: Int = 0

                var total: Int {
                    passed + failed + skipped + missing
                }

                mutating func update(_ test: GradleDriver.TestCase?) {
                    if test?.skipped == true {
                        skipped += 1
                    } else if test?.failures.isEmpty == false {
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

            var (xunitStats, junitStats) = (Stats(), Stats())

            for (xunit, junit) in matchedCases.sorted(by: { testNameComparison($0.xunit, $1.xunit) }) {
                let testName = xunit.name
                outputColumns[0].append(xunit.classname.split(separator: ".").last?.description ?? "")
                outputColumns[1].append(testName)

                xunitStats.update(xunit)
                junitStats.update(junit)

                func desc(_ test: GradleDriver.TestCase?) -> String {
                    guard let test = test else {
                        return "????" // unmatched
                    }
                    let result = (test.skipped == true ? "SKIP" : test.failures.count > 0 ? "FAIL" : "PASS")
                    //result += " (" + ((round(test.time * 1000) / 1000).description) + ")"
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
                outputColumns[index] = outputColumns[index].map { $0.pad(min(length, maxColumnLength), paddingCharacter: $0 == "-" ? "-" : " ") }
            }

            let rowCount = outputColumns.map({ $0.count }).min() ?? 0
            for row in 0..<rowCount {
                let row = outputColumns.map({ $0[row] })

                // these look nice in the terminal, but they don't generate valid markdown tables
                // header columns are all "-"
                //let sep = Set(row.flatMap({ Array($0) })) == ["-"] ? "-" : " "
                // corners of headers are "+"
                //let term = sep == "-" ? "+" : "|"

                let sep = " "
                let term = "|"

                outputOptions.write("", terminator: term)
                for cell in row {
                    outputOptions.write(sep + cell + sep, terminator: term)
                }
                outputOptions.write("", terminator: "\n")
            }
        }
        #endif
    }
}
