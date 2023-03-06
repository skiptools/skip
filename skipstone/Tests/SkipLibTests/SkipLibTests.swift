#if !SKIP
import XCTest
@testable import SkipLib
import SkipBuild
import SymbolKit
#endif

final class SkipLibTests: XCTestCase {
    func testSkipLib() throws {
        XCTAssertEqual(3, 1 + 2)
        XCTAssertEqual("SkipLib", SkipLibInternalModuleName())
        XCTAssertEqual("SkipLib", SkipLibPublicModuleName())
    }

    #if !SKIP
    func testSkipLibSymbols() async throws {
        let testModule = "SkipLibTests"
        let symbols = try await SkipSystem.extractSymbols(URL.moduleBuildFolder, moduleNames: [testModule], accessLevel: "private")
        let symbolGraph = try XCTUnwrap(symbols)
        XCTAssertEqual(1, symbolGraph.count)
        let graph = try XCTUnwrap(symbolGraph.values.first)

        let demoStruct = try XCTUnwrap(graph.symbols["s:12SkipLibTests10DemoStructV"])
        XCTAssertEqual(["DemoStruct"], demoStruct.pathComponents)

    }
    #endif
}

#if !SKIP
public struct DemoStruct {
    public let publicInt: Int = 1
    private var privateOptionalString: String?
    private var impliedDouble = (1.234 * 1)
}
#endif
