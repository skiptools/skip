@testable import Skip
import XCTest

final class BuiltinTypeTests: XCTestCase {
    func testBuiltinTypeConversions() async throws {
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
            get() {
                return field.valref({ a = it })
            }
            set(newValue) {
                field = newValue.valref()
            }
        internal var ao: Any
        internal var b: Boolean
        internal var c: Char
        internal var d: Double
        internal var f: Float
        internal var i: Int
        internal var i8: Byte
        internal var i16: Short
        internal var i32: Int
        internal var i64: Long
        internal var s: String
        internal var ui: UInt
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
            get() {
                return field.valref({ a = it })
            }
            set(newValue) {
                field = newValue.valref()
            }
        internal var ai: Array<Int>
            get() {
                return field.valref({ ai = it })
            }
            set(newValue) {
                field = newValue.valref()
            }
        internal var ai2: Array<Int>
            get() {
                return field.valref({ ai2 = it })
            }
            set(newValue) {
                field = newValue.valref()
            }
        internal var m: Dictionary<Any, Any>
            get() {
                return field.valref({ m = it })
            }
            set(newValue) {
                field = newValue.valref()
            }
        internal var mis: Dictionary<Int, String>
            get() {
                return field.valref({ mis = it })
            }
            set(newValue) {
                field = newValue.valref()
            }
        internal var mis2: Dictionary<Int, String>
            get() {
                return field.valref({ mis2 = it })
            }
            set(newValue) {
                field = newValue.valref()
            }
        internal var tis: Pair<Int, String>
        internal var tis2: Triple<Int, String, Double>
        """)
    }

    func testCustomTypeConversions() async throws {
        try await check(swift: """
        var c: CustomType
        """, kotlin: """
        internal var c: CustomType
            get() {
                return field.valref({ c = it })
            }
            set(newValue) {
                field = newValue.valref()
            }
        """)
    }

    func testOptionalTypeConversions() async throws {
        try await check(swift: """
        var i: Int?
        var c: CustomType?
        var u: CustomType!
        """, kotlin: """
        internal var i: Int?
        internal var c: CustomType?
            get() {
                return field.valref({ c = it })
            }
            set(newValue) {
                field = newValue.valref()
            }
        internal lateinit var u: CustomType
            get() {
                return field.valref({ u = it })
            }
            set(newValue) {
                field = newValue.valref()
            }
        """)
    }
}
