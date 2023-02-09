#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class LocaleTests: XCTestCase {
    var logger = Logger(subsystem: "test", category: "LocaleTests")

    func testLanguageCodes() throws {
        let fr = Locale(identifier: "fr_FR")
        XCTAssertNotNil(fr)
        logger.info("fr_FR: \(fr.identifier)")

        #if SKIP
        XCTAssertEqual("fr_fr", fr.identifier)
        #else
        XCTAssertEqual("fr_FR", fr.identifier)
        #endif

//        XCTAssertEqual("fr", fr.languageCode)

//        XCTAssertEqual("français", fr.localizedString(forLanguageCode: "fr"))
//        XCTAssertEqual("anglais", fr.localizedString(forLanguageCode: "en"))
//        XCTAssertEqual("chinois", fr.localizedString(forLanguageCode: "zh"))

        let zh = Locale(identifier: "zh_HK")
        logger.info("zh_HK: \(zh.identifier)")
        XCTAssertNotNil(zh)

        #if SKIP
        XCTAssertEqual("zh_hk", zh.identifier)
        #else
        XCTAssertEqual("zh_HK", zh.identifier)
        #endif

//        XCTAssertEqual("zh_HK", zh.identifier)
//        XCTAssertEqual("zh", zh.languageCode)
//
//        XCTAssertEqual("法文", zh.localizedString(forLanguageCode: "fr"))
//        XCTAssertEqual("英文", zh.localizedString(forLanguageCode: "en"))
//        XCTAssertEqual("中文", zh.localizedString(forLanguageCode: "zh"))
    }
}
