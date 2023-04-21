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
            var s: Set<Any>
            var si: Set<Int>
            var si3 = Set<Int>()
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
            var mkis = Dictionary.Key()
            var mkis2 = Dictionary.Key<Int, String>()
            var s: Set<Any>
            var si: Set<Int>
            var si3 = Set<Int>()
            var tis: Tuple2<Int, String>
            var tis2: Tuple3<Int, String, Double>
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

    func testNumericMinMax() async throws {
        try await check(swift: """
        Double.min
        Float.max
        Int.min
        Int8.max
        Int16.min
        Int32.max
        Int64.min
        UInt.max
        UInt8.min
        UInt16.max
        UInt32.min
        UInt64.max
        """, kotlin: """
        Double.min
        Float.max
        Int.min
        Byte.max
        Short.min
        Int.max
        Long.min
        UInt.max
        UByte.min
        UShort.max
        UInt.min
        ULong.max
        """)
    }

    func testIntLiteral() async throws {
        try await check(swift: """
        123
        """, kotlin: """
        123
        """)

        try await check(swift: """
        -123
        """, kotlin: """
        -123
        """)

        try await check(swift: """
        123_000_000
        """, kotlin: """
        123_000_000
        """)
    }

    func testStringLiteral() async throws {
        try await check(swift: """
        "abc"
        """, kotlin: """
        "abc"
        """)

        try await check(swift: """
        "1 + 1 = \\(1 + 1)"
        """, kotlin: """
        "1 + 1 = ${1 + 1}"
        """)

        try await check(swift: """
        "i = \\(i)"
        """, kotlin: """
        "i = ${i}"
        """)

        try await check(swift: """
        "It costs ${x}"
        """, kotlin: """
        "It costs \\${x}"
        """)
    }

    func testRawStringLiteral() async throws {
        try await check(swift: """
        #"{"name":"John Smith","isEmployed":true,"age":30}"#
        """, kotlin: """
        \"""{"name":"John Smith","isEmployed":true,"age":30}""\"
        """)
    }

    func testArrayLiteral() async throws {
        try await check(swift: """
        {
            let a = [1, 2, 3]
        }
        """, kotlin: """
        {
            val a = arrayOf(1, 2, 3)
        }
        """)

        try await check(swift: """
        {
            let a: [Int] = [x, y, z]
        }
        """, kotlin: """
        {
            val a: Array<Int> = arrayOf(x, y, z)
        }
        """)

        try await check(swift: """
        {
            let a = [Int]()
        }
        """, kotlin: """
        {
            val a = Array<Int>()
        }
        """)
    }

    func testDictionaryLiteral() async throws {
        try await check(swift: """
        {
            let d = [1: "a", 2: "b", 3: "c"]
        }
        """, kotlin: """
        {
            val d = dictionaryOf(Tuple2(1, "a"), Tuple2(2, "b"), Tuple2(3, "c"))
        }
        """)

        try await check(swift: """
        {
            let d: [Int: String] = [x: a, y: b, z: c]
        }
        """, kotlin: """
        {
            val d: Dictionary<Int, String> = dictionaryOf(Tuple2(x, a), Tuple2(y, b), Tuple2(z, c))
        }
        """)

        try await check(swift: """
        {
            let d = [Int: String]()
        }
        """, kotlin: """
        {
            val d = Dictionary<Int, String>()
        }
        """)
    }

    func testArrayLiteralToSetMapping() async throws {
        try await check(supportingSwift: """
        func setf(set: Set<Int>) {
        }
        """, swift: """
        {
            let s: Set<Int> = [1, 2, 3]
            setf(set: s)
            setf(set: [1, 2, 3])
        }
        """, kotlin: """
        {
            val s: Set<Int> = setOf(1, 2, 3)
            setf(set = s)
            setf(set = setOf(1, 2, 3))
        }
        """)
    }
}
