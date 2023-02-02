@testable import Skip
import SymbolKit
import XCTest

final class SwiftSymbolsTests: XCTestCase {
    func testSwiftSymbols() async throws {
        let swift = """
        public struct TopStruct : Equatable, Encodable, Sendable {
            public let int: Int
            public let str: String? = nil
            internal var num = 1.1 + 2.2
            private var bol = false
            let subStruct = SubStruct(otherField: [])

            fileprivate let array = ["Q", "R", Optional.some("S")]
            fileprivate let array2: Array<Float?> = [.infinity, 1, nil]

            public func doStuff(with arg1: String, and arg2: Int? = nil) async throws -> SubStruct {
                SubStruct(otherField: [arg2 ?? -999])
            }

            public struct SubStruct: Hashable, Codable, Sendable {
                /// This is a doc comment
                internal var otherField: Set<Int>
            }
        }
        """

        let swiftURL = try tmpFile(named: "Source.swift", contents: swift)
        let symbolGraph = try await Process.buildSymbols(swift: swiftURL)
        let graph = try XCTUnwrap(UnifiedSymbolGraph(fromSingleGraph: symbolGraph, at: swiftURL))
        //graph.mergeGraph(graph: otherGraph, at: swiftURL2)

        dump(graph)

        // symbols mapped by "precise identifier" (like "s:6Source9TopStructV3strSSSgvp")
        let symbolNameMap = graph.symbols

        // Looks up a symbol by the path
        func lookup(_ name: String...) throws -> UnifiedSymbolGraph.Symbol {
            try XCTUnwrap(graph.symbols.values.first(where: { $0.pathComponents.values.contains(name) }))
        }

        // here is how we might index by position, noting that there may be more than one Symbol at a given position…
        let locations: [SymbolGraph.LineList.SourceRange.Position?: [UnifiedSymbolGraph.Symbol]] = Dictionary(grouping: symbolNameMap.values.map({ (($0.mixins.values.first?["location"] as? SymbolKit.SymbolGraph.Symbol.Location)?.position, $0) }), by: \.0).mapValues({ $0.compactMap({ $0.1 }) })

        func symbol(at position: SymbolGraph.LineList.SourceRange.Position) throws -> UnifiedSymbolGraph.Symbol {
            try XCTUnwrap(locations[position]?.first)
        }

        // check structs

        //let topStruct = try XCTUnwrap(locations[.init(line: 0, character: 14)]?.first(where: { $0.kind.identifier == .struct } ))
        let topStruct = try lookup("TopStruct")
        XCTAssertEqual("TopStruct", topStruct.names.first!.value.title)
        XCTAssertEqual(["TopStruct"], topStruct.pathComponents.first?.value)
        XCTAssertEqual(.struct, topStruct.kind.first!.value.identifier)
        XCTAssertEqual("public", topStruct.accessLevel.first!.value.rawValue)
        XCTAssertEqual("s:6Source9TopStructV", topStruct.uniqueIdentifier)
        XCTAssertEqual(["struct", " ", "TopStruct"], topStruct.names.first!.value.subHeading?.map(\.spelling))

        // check relationships

        let memberOf = graph.relationshipsByLanguage.values.joined().filter({ $0.target == topStruct.uniqueIdentifier && $0.kind == .memberOf })
        XCTAssertEqual(11, memberOf.count)
        XCTAssertEqual(["s:6Source9TopStructV03SubC0V", "s:6Source9TopStructV03subC0AC03SubC0Vvp", "s:6Source9TopStructV3bol33_A585AEAB28D15CB704B838A9B0AB5A10LLSbvp", "s:6Source9TopStructV3int3num3bolACSi_SdSbtc33_A585AEAB28D15CB704B838A9B0AB5A10Llfc", "s:6Source9TopStructV3intSivp", "s:6Source9TopStructV3numSdvp", "s:6Source9TopStructV3strSSSgvp", "s:6Source9TopStructV5array33_A585AEAB28D15CB704B838A9B0AB5A10LLSaySSSgGvp", "s:6Source9TopStructV6array233_A585AEAB28D15CB704B838A9B0AB5A10LLSaySfSgGvp", "s:6Source9TopStructV7doStuff4with3andAC03SubC0VSS_SiSgtYaKF", "s:SQsE2neoiySbx_xtFZ::SYNTHESIZED::s:6Source9TopStructV"], memberOf.map(\.source).sorted())

        let relations = graph.relationshipsByLanguage.values.joined().filter({ $0.source == topStruct.uniqueIdentifier })

        // check possible relations: memberOf, conformsTo, inheritsFrom, defaultImplementationOf, overrides, requirementOf, optionalRequirementOf, extensionTo
        let conformsTo = relations.filter({ $0.kind == .conformsTo })
        XCTAssertEqual(["s:SE", "s:SQ", "s:s8SendableP"], conformsTo.map(\.target).sorted())
        XCTAssertEqual(["Swift.Encodable", "Swift.Equatable", "Swift.Sendable"], conformsTo.compactMap(\.targetFallback).sorted())

        // check properties

        //let int = try XCTUnwrap(locations[.init(line: 1, character: 15)]?.first)
        let int = try lookup("TopStruct", "int")

        XCTAssertEqual("int", int.names.first!.value.title)
        XCTAssertEqual(.property, int.kind.first!.value.identifier)
        XCTAssertEqual("public", int.accessLevel.first!.value.rawValue)
        XCTAssertEqual("s:6Source9TopStructV3intSivp", int.uniqueIdentifier)
        XCTAssertEqual(["let", " ", "int", ": ", "Int"], int.names.first!.value.subHeading?.map(\.spelling))

        //let str = try XCTUnwrap(locations[.init(line: 2, character: 15)]?.first)
        let str = try lookup("TopStruct", "str")
        XCTAssertEqual("str", str.names.first!.value.title)
        XCTAssertEqual(.property, str.kind.first!.value.identifier)
        XCTAssertEqual("public", str.accessLevel.first!.value.rawValue)
        XCTAssertEqual("s:6Source9TopStructV3strSSSgvp", str.uniqueIdentifier)
        XCTAssertEqual("?", str.names.first!.value.subHeading?.last?.spelling)
        XCTAssertEqual("String", str.names.first!.value.subHeading?.dropLast(1).last?.spelling)
        XCTAssertEqual(["let", " ", "str", ": ", "String", "?"], str.names.first!.value.subHeading?.map(\.spelling))

        let array = try lookup("TopStruct", "array")
        //let array = try XCTUnwrap(locations[.init(line: 5, character: 20)]?.first)
        XCTAssertTrue(array.docComment.isEmpty)
        XCTAssertEqual(["TopStruct", "array"], array.pathComponents.values.first)
        XCTAssertEqual("array", array.names.first!.value.title)
        XCTAssertEqual("fileprivate", array.accessLevel.first!.value.rawValue)
        XCTAssertEqual(.property, array.kind.first!.value.identifier)
        XCTAssertEqual("s:6Source9TopStructV5array33_A585AEAB28D15CB704B838A9B0AB5A10LLSaySSSgGvp", array.uniqueIdentifier)
        XCTAssertEqual(["let", " ", "array", ": [", "Optional", "<", "String", ">]"], array.names.first!.value.subHeading?.map(\.spelling))
//        XCTAssertEqual(["let", " ", "array", ": [", "Optional", "<", "String", ">]"], array.fragments?.map(\.spelling))
//        XCTAssertEqual([.keyword, .text, .identifier, .text, .typeIdentifier, .text, .typeIdentifier, .text], array.fragments?.map(\.kind))
//        XCTAssertEqual([nil, nil, nil, nil, "s:Sq", nil, "s:SS", nil], array.fragments?.map(\.preciseIdentifier))

        let array2 = try lookup("TopStruct", "array2")
        XCTAssertEqual(["let", " ", "array2", ": ", "Array", "<", "Float", "?>"], array2.fragments?.map(\.spelling))
        XCTAssertEqual([nil, nil, nil, nil, "s:Sa", nil, "s:Sf", nil], array2.fragments?.map(\.preciseIdentifier))

        let subField = try lookup("TopStruct", "subStruct")
        XCTAssertEqual(["let", " ", "subStruct", ": ", "TopStruct", ".", "SubStruct"], subField.fragments?.map(\.spelling))
        XCTAssertEqual([nil, nil, nil, nil, "s:6Source9TopStructV", nil, "s:6Source9TopStructV03SubC0V"], subField.fragments?.map(\.preciseIdentifier))

        let subStruct = try lookup("TopStruct", "SubStruct")
        XCTAssertEqual(.struct, subStruct.kind.first!.value.identifier)


        let set = try lookup("TopStruct", "SubStruct", "otherField")
        //let set = try XCTUnwrap(locations[.init(line: 13, character: 21)]?.first)
        //XCTAssertEqual("This is a doc comment", set.docComment.first?.value.lines.first?.text) // only works with singlePass, were swiftc itself outputs the doc comments
        XCTAssertEqual(["TopStruct", "SubStruct", "otherField"], set.pathComponents.first!.value)
        XCTAssertEqual("internal", set.accessLevel.first!.value.rawValue)
        XCTAssertEqual("otherField", set.names.first!.value.title)
        XCTAssertEqual("s:6Source9TopStructV03SubC0V10otherFieldShySiGvp", set.uniqueIdentifier)
        XCTAssertEqual(["var", " ", "otherField", ": ", "Set", "<", "Int", ">"], set.names.first!.value.subHeading?.map(\.spelling))
    }
}

extension UnifiedSymbolGraph.Symbol {
    /// The location of this symbol, as stored in the `mixins` container.
    var location: SymbolGraph.Symbol.Location? {
        mixins.values.first?["location"] as? SymbolGraph.Symbol.Location
    }

    /// The fragments of this symbol, as stored in the `mixins` container.
    var fragments: [SymbolGraph.Symbol.DeclarationFragments.Fragment]? {
        (mixins.values.first?["declarationFragments"] as? SymbolGraph.Symbol.DeclarationFragments)?.declarationFragments
    }
}

/// Position is Equatable but not Hashable
extension SymbolGraph.LineList.SourceRange.Position : Hashable {
    public func hash(into hasher: inout Hasher) {
        self.line.hash(into: &hasher)
        self.character.hash(into: &hasher)
    }
}

extension Process {
    /// Takes the Swift file at the given URL and compiles it with the parameters for extracting symbols, and then returns the parsed symbol graph.
    ///
    /// - Parameters:
    ///   - url: the URL of the Swift file to compile. If this is a `Package.swift` file, then the build will be run with `swift build`, otherwise it will use `swiftc` for a single file.
    ///   - accessLevel: the default access level for the generated symbols
    /// - Returns: the parsed SymbolGraph that resulted from the compilation
    static func buildSymbols(swift url: URL, singlePass: Bool = false, sdk: String = "macosx", moduleName: String? = nil, accessLevel: String = "private") async throws -> SymbolGraph {
        // another alternative could be to fork `swift build` against a Package.swift
        // https://www.swift.org/documentation/docc/documenting-a-swift-framework-or-package#Create-Documentation-for-a-Swift-Package
        // swift build --target DeckOfPlayingCards -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc .build
        // this is based on how docc gathers symbols: https://github.com/apple/swift-docc/blob/main/Sources/generate-symbol-graph/main.swift#L157
        // e.g.: swift build -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc ./.build/ -Xswiftc -symbol-graph-minimum-access-level -Xswiftc private

        let urlBase = url.deletingPathExtension()
        let moduleName = moduleName ?? urlBase.lastPathComponent // if the module name is not set, default to the last part of the URL
        let dir = urlBase.deletingLastPathComponent()

        if singlePass {
            try await xcrun("swiftc", "-emit-symbol-graph", "-emit-module-path", url.deletingLastPathComponent().path, "-emit-symbol-graph-dir", url.deletingLastPathComponent().path, "-symbol-graph-minimum-access-level", accessLevel, url.path)
        } else {
            let targetInfo = try await JSONDecoder().decode(SwiftTarget.self, from: xcrun("swiftc", "-print-target-info").stdout.readData() ?? Data())
            try await xcrun("swiftc", "-target", targetInfo.target.triple, "-module-name", moduleName, "-emit-module-path", dir.path, url.path)
            let sdKPath = try await xcrun("--show-sdk-path", "--sdk", sdk).stdout.readString()
            try await xcrun("swift", "symbolgraph-extract", "-output-dir", dir.path, "-target", targetInfo.target.triple, "-sdk", sdKPath, "-minimum-access-level", accessLevel, "-I", dir.path, "-module-name", moduleName)
        }

        let symbolFile = urlBase.appendingPathExtension("symbols.json")
        let graphData = try Data(contentsOf: symbolFile)
        let graph = try JSONDecoder().decode(SymbolGraph.self, from: graphData)
        return graph
    }

    @discardableResult static func xcrun(_ args: String...) async throws -> (stdout: Pipe, stderr: Pipe) {
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

        process.arguments = args

        print("running: xcrun", args.joined(separator: " "))

        let (stdout, stderr): (Pipe, Pipe)
        do {
            (stdout, stderr) = try await process.execute()
        } catch let RunProcessError.nonZeroExit(exitCode, stdout, stderr) {
            let output = String(data: try stdout.readData() ?? Data(), encoding: .utf8)
            let errput = String(data: try stderr.readData() ?? Data(), encoding: .utf8)
            print("xcrun: error: output:", output ?? "", "errput:", errput ?? "")
            throw RunProcessError.nonZeroExit(exitCode, stdout, stderr)
        }
        return (stdout, stderr)
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

    /// Reads the whole pipe as a string.
    func readString(trim: Bool = true) throws -> String {
        (String(data: try readData() ?? Data(), encoding: .utf8) ?? "").trimmingCharacters(in: trim ? .whitespacesAndNewlines : .init())
    }
}

/// Pared-down contents of the JSON output of `swiftc -print-target-info`
struct SwiftTarget: Codable {
    struct Target: Codable {
        let triple: String
        let unversionedTriple: String
        let moduleTriple: String
    }

    let compilerVersion: String?

    let target: Target
}
