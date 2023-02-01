@testable import Skip
import XCTest

final class BaseTypeTests: XCTestCase {
    func testBaseTypeConversions() async throws {
        try await check(swift: """
        var a: Any
        var ao: AnyObject
        var b: Bool
        var c: Character
        var i: Int
        var i8: Int8
        var i16: Int16
        var i32: Int32
        var i64: Int64
        var s: String
        var ui: UInt
        var ui8: UInt8
        var ui16: UInt16
        var ui32: UInt32
        var ui64: UInt64
        """, kotlin: """
        internal var a: Any
        internal var ao: Any
        internal var b: Boolean
        internal var c: Char
        internal var i: Long
        internal var i8: Byte
        internal var i16: Short
        internal var i32: Int
        internal var i64: Long
        internal var s: String
        internal var ui: ULong
        internal var ui8: UByte
        internal var ui16: UShort
        internal var ui32: UInt
        internal var ui64: ULong
        """)
    }
}
