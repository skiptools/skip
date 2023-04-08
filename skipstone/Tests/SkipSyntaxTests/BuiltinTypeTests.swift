@testable import SkipSyntax
import XCTest

final class BuiltinTypeTests: XCTestCase {
    func testBuiltinTypeConversions() async throws {
        try await check(swift: """
        {
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
        }
        """, kotlin: """
        {
            var a: Any
            var ao: Any
            var b: Boolean
            var c: Char
            var d: Double
            var f: Float
            var i: Int
            var i8: Byte
            var i16: Short
            var i32: Int
            var i64: Long
            var s: String
            var ui: UInt
            var ui8: UByte
            var ui16: UShort
            var ui32: UInt
            var ui64: ULong
            var v: Unit
        }
        """)
    }

    func testContainerTypeConversions() async throws {
        try await check(swift: """
        {
            var a: [Any]
            var ai: [Int]
            var ai2: Array<Int>
            var ai3 = Array<Int>()
            var m: [Any: Any]
            var mis: [Int: String]
            var mis2: Dictionary<Int, String>
            var mis3 = Dictionary<Int, String>()
            var mkis = Dictionary<Int, String>.Key()
            var mkis2 = Dictionary<Int, String>.Key<Int, String>()
            var tis: (Int, String)
            var tis2: (Int, String, Double)
        }
        """, kotlin: """
        {
            var a: Array<Any>
            var ai: Array<Int>
            var ai2: Array<Int>
            var ai3 = Array<Int>()
            var m: Dictionary<Any, Any>
            var mis: Dictionary<Int, String>
            var mis2: Dictionary<Int, String>
            var mis3 = Dictionary<Int, String>()
            var mkis = Dictionary<Int, String>.Key()
            var mkis2 = Dictionary<Int, String>.Key<Int, String>()
            var tis: Pair<Int, String>
            var tis2: Triple<Int, String, Double>
        }
        """)
    }

    func testCustomTypeConversions() async throws {
        try await check(swift: """
        var c: CustomType
        """, kotlin: """
        internal var c: CustomType
            get() {
                return field.sref({ c = it })
            }
            set(newValue) {
                field = newValue.sref()
            }
        """)
    }

    func testOptionalTypeConversions() async throws {
        try await check(swift: """
        var i: Int?
        var c: CustomType?
        var u: CustomType!
        """, kotlin: """
        internal var i: Int? = null
        internal var c: CustomType? = null
            get() {
                return field.sref({ c = it })
            }
            set(newValue) {
                field = newValue.sref()
            }
        internal lateinit var u: CustomType
            get() {
                return field.sref({ u = it })
            }
            set(newValue) {
                field = newValue.sref()
            }
        """)
    }
}
