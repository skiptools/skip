@testable import SkipSyntax
import XCTest

final class NamingTests: XCTestCase {
    func testPackageNaming() throws {
        XCTAssertEqual("net.scape", KotlinTranslator.packageName(forModule: "NetScape"))
        XCTAssertEqual("my.module", KotlinTranslator.packageName(forModule: "MyModule"))
        XCTAssertEqual("my.mmodule", KotlinTranslator.packageName(forModule: "MyMModule"))
        XCTAssertEqual("my.mmmmodule", KotlinTranslator.packageName(forModule: "MyMMMModule"))
        XCTAssertEqual("com.package.name.some.module", KotlinTranslator.packageName(forModule: "ComPackageNameSomeModule"))
        XCTAssertEqual("urlutility.library", KotlinTranslator.packageName(forModule: "URLUtilityLibrary"))
    }

    /// Checks that Kotlin's "hard" keywords are escaped by appending an undescore to the end of the name.
    func testCheckReservedKeywords() async throws {
        try await check(swiftCode: {
            class KeywordHolder {
                let null = "ABC"
                var interface: Int = 2
                var this = 1.234
                var `enum`: EnumType = EnumType.null
            }
            enum EnumType {
                case null,
                     interface,
                     this
            }
            let holder = KeywordHolder()
            assert(holder.null == "ABC")
            holder.interface += 1
            holder.enum = EnumType.this
            holder.this += holder.this
            assert(holder.this == 2.468)
            return holder.null
        }, kotlin: """
            open class KeywordHolder {
                val null_ = "ABC"
                var interface_: Int = 2
                var this_ = 1.234
                var enum: EnumType = EnumType.null_
            }
            enum class EnumType {
                null_,
                interface_,
                this_;
            }
            val holder = KeywordHolder()
            assert(holder.null_ == "ABC")
            holder.interface_ += 1
            holder.enum = EnumType.this_
            holder.this_ += holder.this_
            assert(holder.this_ == 2.468)
            return holder.null_
            """)
    }
}
