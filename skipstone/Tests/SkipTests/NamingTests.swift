@testable import Skip
import XCTest

final class NamingTests: XCTestCase {
    func testNaming() throws {
        XCTAssertEqual("net.scape", KotlinTranslator.packageName(forModule: "NetScape"))
        XCTAssertEqual("my.module", KotlinTranslator.packageName(forModule: "MyModule"))
        XCTAssertEqual("my.mmodule", KotlinTranslator.packageName(forModule: "MyMModule"))
        XCTAssertEqual("my.mmmmodule", KotlinTranslator.packageName(forModule: "MyMMMModule"))
        XCTAssertEqual("com.package.name.some.module", KotlinTranslator.packageName(forModule: "ComPackageNameSomeModule"))
        XCTAssertEqual("urlutility.library", KotlinTranslator.packageName(forModule: "URLUtilityLibrary"))

    }
}


