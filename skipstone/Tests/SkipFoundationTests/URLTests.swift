#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class URLTests: XCTestCase {
    func testURLs() throws {
        let url: URL? = URL.init(string: "https://www.example.org/path/to/file.ext")
        XCTAssertEqual("https://www.example.org/path/to/file.ext", url?.absoluteString)
        XCTAssertEqual("/path/to/file.ext", url?.path)
        XCTAssertEqual("www.example.org", url?.host)
        XCTAssertEqual("ext", url?.pathExtension)
        XCTAssertEqual("file.ext", url?.lastPathComponent)
        XCTAssertEqual(false, url?.isFileURL)
    }
}
