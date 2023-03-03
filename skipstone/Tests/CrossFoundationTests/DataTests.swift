#if !SKIP
@testable import CrossFoundation
import XCTest
#endif

final class DataTests: XCTestCase {
    var logger = Logger(subsystem: "test", category: "DataTests")

    func testData() throws {
        let hostsFile: URL = URL(fileURLWithPath: "/etc/hosts", isDirectory: false)

        let hostsData: Data = try Data(contentsOf: hostsFile)
        XCTAssertNotEqual(0, hostsData.count)

        // FIXME: force-unwrap doesn't transpile
        let url: URL = try XCTUnwrap(URL(string: "https://www.example.com"))
        let urlData: Data = try Data(contentsOf: url)

        logger.log("downloaded url size: \(urlData.count)") // ~1256
        XCTAssertNotEqual(0, urlData.count)

        let url2 = try XCTUnwrap(URL(string: "domains/reserved", relativeTo: URL(string: "https://www.iana.org")))
        let url2Data: Data = try Data(contentsOf: url2)

        logger.log("downloaded url2 size: \(url2Data.count)") // ~1256
        XCTAssertNotEqual(0, url2Data.count)
    }
}
