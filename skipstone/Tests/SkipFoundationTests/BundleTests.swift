#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class BundleTests: XCTestCase {
    var logger = Logger(subsystem: "test", category: "BundleTests")

    func testBundle() throws {
        // SKIP INSERT: val nil = null
        let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "textasset", withExtension: "txt", subdirectory: nil, localization: nil))
        logger.info("resourceURL: \(resourceURL.absoluteString)")

        // Swift will be: Contents/Resources/ -- file:///~/Library/Developer/Xcode/DerivedData/DemoApp-ABCDEF/Build/Products/Debug/SkipFoundationTests.xctest/Contents/Resources/Skip_SkipFoundationTests.bundle/
        // Kotlin will be: file:/SRCDIR/Skip/kip/SkipFoundationTests/modules/SkipFoundation/build/tmp/kotlin-classes/debugUnitTest/skip/foundation/

        let str = try String(contentsOf: resourceURL)
        XCTAssertEqual("Some text\n", str)
    }
}
