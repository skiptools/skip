@testable import Skip
import XCTest
import SymbolKit

final class SkipTests: XCTestCase {
    func testSwiftSymbols() async throws {
        let swift = """
        public struct TopStruct : Equatable, Encodable, Sendable {
            public let int: Int
            public let str: String? = nil
            internal var num = 1.1 + 2.2
            private var bol = false
            fileprivate let array = ["Q", "R", Optional.some("S")]

            public func doStuff(with arg1: String, and arg2: Int? = nil) async throws -> SubStruct {
                SubStruct(otherField: [arg2 ?? -999])
            }

            public struct SubStruct: Hashable, Codable, Sendable {
                internal var otherField: Set<Int>
            }
        }
        """

        let symbols = try await Process.buildSymbols(swift: tmpFile(named: "Source.swift", contents: swift))
        dump(symbols)

        // symbols mapped by "precise identifier" (like "s:6Source9TopStructV3strSSSgvp")
        let symbolNameMap = symbols.symbols

        XCTAssertEqual("str", symbolNameMap["s:6Source9TopStructV3strSSSgvp"]?.names.title)

        // here is how we might index by position…
        let locations = Dictionary(symbolNameMap.values.map({ (($0.mixins["location"] as? SymbolKit.SymbolGraph.Symbol.Location)?.position, $0) }), uniquingKeysWith: { $1 })

        let int = locations[.init(line: 1, character: 15)]
        XCTAssertEqual("int", int?.names.title)
        XCTAssertEqual("s:6Source9TopStructV3intSivp", int?.identifier.precise)
        XCTAssertEqual(["let", " ", "int", ": ", "Int"], int?.names.subHeading?.map(\.spelling))

        let str = locations[.init(line: 2, character: 15)]
        XCTAssertEqual("str", str?.names.title)
        XCTAssertEqual("s:6Source9TopStructV3strSSSgvp", str?.identifier.precise)
        XCTAssertEqual("?", str?.names.subHeading?.last?.spelling)
        XCTAssertEqual("String", str?.names.subHeading?.dropLast(1).last?.spelling)
        XCTAssertEqual(["let", " ", "str", ": ", "String", "?"], str?.names.subHeading?.map(\.spelling))

        let array = locations[.init(line: 5, character: 20)]
        XCTAssertEqual("array", array?.names.title)
        XCTAssertEqual("s:6Source9TopStructV5array33_A585AEAB28D15CB704B838A9B0AB5A10LLSaySSSgGvp", array?.identifier.precise)
        XCTAssertEqual(["let", " ", "array", ": [", "Optional", "<", "String", ">]"], array?.names.subHeading?.map(\.spelling))

        // ambiguous! There is also the `init(otherField:)` function at that position…
//        let subStruct = locations[.init(line: 11, character: 18)]
//        XCTAssertEqual("TopStruct.SubStruct", subStruct?.names.title)
//        XCTAssertEqual("s:6Source9TopStructV03SubC0V", subStruct?.identifier.precise)
//        XCTAssertEqual(["struct", " ", "SubStruct"], subStruct?.names.subHeading?.map(\.spelling))

        let set = locations[.init(line: 12, character: 21)]
        XCTAssertEqual("otherField", set?.names.title)
        XCTAssertEqual("s:6Source9TopStructV03SubC0V10otherFieldShySiGvp", set?.identifier.precise)
        XCTAssertEqual(["var", " ", "otherField", ": ", "Set", "<", "Int", ">"], set?.names.subHeading?.map(\.spelling))

    }

    func testStruct0Props() async throws {
        try await check(swift: """
        struct Foo {
        }
        """, kotlin: """
        internal data class Foo {

            companion object {
            }
        }
        """)
    }
}

/// Position is Equatable but not Hashable
extension SymbolGraph.LineList.SourceRange.Position : Hashable {
    public func hash(into hasher: inout Hasher) {
        self.line.hash(into: &hasher)
        self.character.hash(into: &hasher)
    }
}

extension XCTestCase {
    /// Checks that the given Swift compiles to the specified Kotlin.
    func check(swift: String, kotlin: String? = nil, file: StaticString = #file, line: UInt = #line) async throws {
        let tmpdir = URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        try FileManager.default.createDirectory(at: tmpdir, withIntermediateDirectories: true)
        let srcFile = try tmpFile(named: "Source.swift", contents: swift)
        if let kotlin = kotlin {
            let tp = Transpiler(sourceFiles: [Source.File(path: srcFile.path)])
            try await tp.transpile(handler: { transpilation in
                //print("transpilation:", transpilation.output)
                XCTAssertEqual(kotlin.trimmingCharacters(in: .whitespacesAndNewlines), transpilation.output.content.trimmingCharacters(in: .whitespacesAndNewlines), file: file, line: line)
            })
        }
    }

    /// Creates a temporary file with the given name and optional contents.
    func tmpFile(named fileName: String, contents: String? = nil) throws -> URL {
        let tmpDir = URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tmpFile = URL(fileURLWithPath: fileName, isDirectory: false, relativeTo: tmpDir)
        if let contents = contents {
            try contents.write(to: tmpFile, atomically: true, encoding: .utf8)
        }
        return tmpFile
    }
}

extension Process {
    /// Takes the Swift file at the given URL and compiles it with the parameters for extracting symbols, and then returns the parsed symbol graph.
    ///
    /// - Parameters:
    ///   - url: the URL of the Swift file to compile. If this is a `Package.swift` file, then the build will be run with `swift build`, otherwise it will use `swiftc` for a single file.
    ///   - accessLevel: the default access level for the generated symbols
    /// - Returns: the parsed SymbolGraph that resulted from the compilation
    static func buildSymbols(swift url: URL, accessLevel: String = "private") async throws -> SymbolGraph {
        let process = Process()
        #if os(macOS)
        // use xcrun, which will use whichever Swift we have set up with Xcode
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun", isDirectory: false)
        #elseif os(Linux)
        // use `env` to resolve the swift/swiftc command in the current environment
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env", isDirectory: false)
        #else
        #error("unsupported platform")
        #endif

        var args: [String] = []

        if url.lastPathComponent == "Package.swift" {
            // this is based on how docc gathers symbols: https://github.com/apple/swift-docc/blob/main/Sources/generate-symbol-graph/main.swift#L157
            args += ["swift", "build"]
            args += [
                "-Xswiftc", "-emit-symbol-graph",
                "-Xswiftc", "-emit-symbol-graph-dir", "-Xswiftc", url.deletingLastPathComponent().path,
                "-Xswiftc", "-symbol-graph-minimum-access-level", "-Xswiftc", accessLevel,
            ]
            args += [
                "--package-path", url.deletingLastPathComponent().path,
            ]
        } else { // single-swift file compile
            args += ["swiftc"]
            args += [
                "-emit-symbol-graph",
                "-emit-module-path", url.deletingLastPathComponent().path,
                "-emit-symbol-graph-dir", url.deletingLastPathComponent().path,
                "-symbol-graph-minimum-access-level", accessLevel,
            ]
            args += [
                url.path
            ]
        }

        process.arguments = args

        //print("running:", args.joined(separator: " "))

        let (stdout, stderr): (Pipe, Pipe)
        do {
            (stdout, stderr) = try await process.execute()
        } catch let RunProcessError.nonZeroExit(exitCode, stdout, stderr) {
            let output = String(data: try stdout.readData() ?? Data(), encoding: .utf8)
            let errput = String(data: try stderr.readData() ?? Data(), encoding: .utf8)
            print("buildSymbols: error: output:", output ?? "", "errput:", errput ?? "")
            throw RunProcessError.nonZeroExit(exitCode, stdout, stderr)
        }
        let (_, _) = (stdout, stderr)

        let symFile = url.deletingPathExtension().appendingPathExtension("symbols.json")
        let graphData = try Data(contentsOf: symFile)
        let graph = try JSONDecoder().decode(SymbolGraph.self, from: graphData)
        return graph
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

extension Pipe {
    /// Reads all the remaining data available for the pipe.
    func readData() throws -> Data? {
        try fileHandleForReading.readToEnd()
    }
}
