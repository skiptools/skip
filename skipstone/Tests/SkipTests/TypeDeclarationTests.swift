@testable import Skip
import XCTest

final class TypeDeclarationTests: XCTestCase {
    func testStruct0Props() async throws {
        try await check(swift: """
        struct Foo {
        }
        """, kotlin: """
        internal class Foo {

            companion object {
            }
        }
        """)
    }
}
