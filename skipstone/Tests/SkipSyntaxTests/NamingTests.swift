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
                let null_ = "DEF"
                var interface: Int = 2
                var this = 1.234
                var `enum`: EnumType = EnumType.null

                func packageFunction(package: String) { }
                func objectArgFunction(object o: EnumType) { }
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
            holder.packageFunction(package: "ABC")
            holder.objectArgFunction(object: EnumType.this)
            return holder.null
        }, kotlin: """
            open class KeywordHolder {
                val null_ = "ABC"
                val null__ = "DEF"
                var interface_: Int = 2
                var this_ = 1.234
                var enum: EnumType = EnumType.null_
                fun packageFunction(package_: String) = Unit
                fun objectArgFunction(object_: EnumType) = Unit
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
            holder.packageFunction(package_ = "ABC")
            holder.objectArgFunction(object_ = EnumType.this_)
            return holder.null_
            """)
    }
}





