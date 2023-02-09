#if !SKIP
@testable import SkipKotlin
import SkipUnit
import SymbolKit
#endif

final class SkipKotlinTests: XCTestCase {
    func testSkipKotlin() throws {
        XCTAssertEqual(3, 1 + 2)
        XCTAssertEqual("SkipKotlin", SkipKotlinInternalModuleName())
        XCTAssertEqual("SkipKotlin", SkipKotlinPublicModuleName())
    }

    #if !SKIP
    func testSkipKotlinSymbols() async throws {
        let testModule = "SkipKotlinTests"
        let symbols = try await System.extractSymbols(URL.moduleBuildFolder, moduleName: testModule, accessLevel: "private")
        let symbolGraph = try XCTUnwrap(symbols)
        XCTAssertEqual(1, symbolGraph.count)
        let graph = try XCTUnwrap(symbolGraph.values.first)

        dump(graph)

        let demoStruct = try XCTUnwrap(graph.symbols["s:15SkipKotlinTests10DemoStructV"])
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
