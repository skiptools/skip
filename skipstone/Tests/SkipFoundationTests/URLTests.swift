#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class URLTests: XCTestCase {
    func testURLs() throws {
        let url: URL? = URL(string: "https://github.com/jectivex/CrossFoundation.git")
        XCTAssertEqual("https://github.com/jectivex/CrossFoundation.git", url?.absoluteString)
        XCTAssertEqual("/jectivex/CrossFoundation.git", url?.path)
        XCTAssertEqual("github.com", url?.host)
        XCTAssertEqual("git", url?.pathExtension)
        XCTAssertEqual("CrossFoundation.git", url?.lastPathComponent)
        XCTAssertEqual(false, url?.isFileURL)
    }
}
