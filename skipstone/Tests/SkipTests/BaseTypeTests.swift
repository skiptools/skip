@testable import Skip
import XCTest

final class BaseTypeTests: XCTestCase {
    func testBaseTypeConversions() async throws {
        try await check(swift: """
        var a: Any
        var ao: AnyObject
        var b: Bool
        var c: Character
        var d: Double
        var f: Float
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
        var v: Void
        """, kotlin: """
        internal var a: Any
        internal var ao: Any
        internal var b: Boolean
        internal var c: Char
        internal var d: Double
        internal var f: Float
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
        internal var v: Unit
        """)
    }

    func testContainerTypeConversions() async throws {
        try await check(swift: """
        var a: [Any]
        var ai: [Int]
        var ai2: Array<Int>
        var m: [Any: Any]
        var mis: [Int: String]
        var mis2: Dictionary<Int, String>
        var tis: (Int, String)
        var tis2: (Int, String, Double)
        """, kotlin: """
        internal var a: Array<Any>
        internal var ai: Array<Long>
        internal var ai2: Array<Long>
        internal var m: MutableMap<Any, Any>
        internal var mis: MutableMap<Long, String>
        internal var mis2: MutableMap<Long, String>
        internal var tis: Pair<Long, String>
        internal var tis2: Triple<Long, String, Double>
        """)
    }

    func testCustomTypeConversions() async throws {
        try await check(swift: """
        var c: CustomType
        """, kotlin: """
        internal var c: CustomType
        """)
    }

    func testOptionalTypeConversions() async throws {
        try await check(swift: """
        var i: Int?
        var c: CustomType?
        var u: CustomType!
        """, kotlin: """
        internal var i: Long?
        internal var c: CustomType?
        internal lateinit var u: CustomType
        """)
    }
}
