#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class BundleTests: XCTestCase {
    var logger = Logger(subsystem: "test", category: "BundleTests")

    func testBundle() throws {
        let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "textasset", withExtension: "txt", subdirectory: nil, localization: nil))
        logger.info("resourceURL: \(resourceURL.absoluteString)")

        // Swift will be: Contents/Resources/ -- file:///~/Library/Developer/Xcode/DerivedData/DemoApp-ABCDEF/Build/Products/Debug/SkipFoundationTests.xctest/Contents/Resources/Skip_SkipFoundationTests.bundle/
        // Kotlin will be: file:/SRCDIR/Skip/kip/SkipFoundationTests/modules/SkipFoundation/build/tmp/kotlin-classes/debugUnitTest/skip/foundation/

        let str = try String(contentsOf: resourceURL)
        XCTAssertEqual("Some text\n", str)
    }

    func testLocalizedStrings() throws {
        let locstr = """
        /* A comment */
        "Yes" = "Oui";
        "The \\\"same\\\" text in English" = "Le \\\"même\\\" texte en anglais";
        """

        let data = try XCTUnwrap(locstr.data(using: StringEncoding.utf8, allowLossyConversion: false))

        // weird hackery for skip transpilation
        #if !SKIP
        typealias Map = Dictionary
        #endif

        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)

        let dict = try XCTUnwrap(plist as? Map<String, String>)

        XCTAssertEqual("Oui", dict["Yes"])
        logger.debug("KEYS: \(dict.keys)")
        XCTAssertEqual("Le \"même\" texte en anglais", dict["The \"same\" text in English"])
    }
}
