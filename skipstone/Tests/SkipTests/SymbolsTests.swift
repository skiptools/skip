@testable import Skip
import SkipBuild
import XCTest
import SymbolKit

final class SymbolsTests: XCTestCase {
    let symbolCache = SymbolCache()

    func testSkipSymbols() async throws {
        let skipTestsSymbols = try await symbolCache.symbols(for: "SkipTests", accessLevel: "private")
        let skipSymbols = try await symbolCache.symbols(for: "Skip", accessLevel: "public")

        XCTAssertLessThan(10, skipTestsSymbols.symbols.count)
        XCTAssertLessThan(50, skipSymbols.symbols.count)
    }

}
