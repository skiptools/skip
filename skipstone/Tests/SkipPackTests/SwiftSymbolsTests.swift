import SkipPack
import SymbolKit
import XCTest
import os.log

fileprivate let logger = Logger(subsystem: "skip", category: "test")

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
        let symbolGraph = try await System.buildSymbols(swift: swiftURL)

        //let graph = try XCTUnwrap(UnifiedSymbolGraph(fromSingleGraph: symbolGraph, at: swiftURL))
        //graph.mergeGraph(graph: otherGraph, at: swiftURL2)

        let collector = GraphCollector(extensionGraphAssociationStrategy: .extendingGraph)
        collector.mergeSymbolGraph(symbolGraph, at: swiftURL)
        // TODO: add more graphs for extensions, etc…
        let (unifiedGraphs, graphSources) = collector.finishLoading()
        XCTAssertEqual(["Source"], Array(graphSources.keys))
        XCTAssertEqual(["Source"], Array(unifiedGraphs.keys))
        let graph = try XCTUnwrap(unifiedGraphs["Source"])
        //dump(graph)

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

extension XCTestCase {
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
