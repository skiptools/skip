@testable import SkipSyntax
import XCTest

final class EnumTests: XCTestCase {
//    func testBasic() async throws {
//        try await check(swift: """
//        enum E {
//            case a
//            case b
//        }
//        """, kotlin: """
//        internal enum class E {
//            a,
//            b;
//
//            companion object {
//            }
//        }
//        """)
//    }
//
//    func testExtends() async throws {
//        try await check(swift: """
//        enum E: Int {
//            case a
//            case b
//            case c = 100
//        }
//        """, kotlin: """
//        internal enum class E(val rawValue: Int) {
//            a(0),
//            b(1),
//            b(100);
//
//            companion object {
//            }
//        }
//        """)
//    }
//
//    func testFunction() async throws {
//        try await check(swift: """
//        enum E: Int {
//            case a
//
//            func plusOne() -> Int {
//                return rawValue + 1
//            }
//
//            case b
//        }
//        """, kotlin: """
//        internal enum class E(val rawValue: Int) {
//            a(0),
//            b(1);
//
//            internal fun plusOne(): Int {
//                return rawValue + 1
//            }
//
//            companion object {
//            }
//        }
//        """)
//    }
}
