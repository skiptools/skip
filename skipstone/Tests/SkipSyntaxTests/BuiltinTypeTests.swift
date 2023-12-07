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
        import skip.lib.Array
        import skip.lib.Set

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
            get() = field.sref({ c = it })
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
            get() = field.sref({ c = it })
            set(newValue) {
                field = newValue.sref()
            }
        internal var u: CustomType
            get() = ustorage.sref({ u = it })
            set(newValue) {
                ustorage = newValue.sref()
            }
        private lateinit var ustorage: CustomType
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

    func testNumericCastRequired() async throws {
        try await check(swift: """
        let x: Float = Float(1.0)
        let y: Float = Float(1)
        let z: Float = Float(1 * 2)
        """, kotlin: """
        internal val x: Float = 1.0f
        internal val y: Float = 1f
        internal val z: Float = Float(1 * 2)
        """)

        try await checkProducesMessage(swift: """
        let x: Float = 1.0
        """)

        try await check(swift: """
        let x: UInt = UInt(1)
        let y: UInt64 = UInt64(1)
        """, kotlin: """
        internal val x: UInt = 1U
        internal val y: ULong = 1UL
        """)

        try await checkProducesMessage(swift: """
        let x: UInt = 1
        """)

        try await check(swift: """
        let i: Int = Int(1)
        let x: Long = Long(1)
        let y: Long = Long(1.0)
        """, kotlin: """
        internal val i: Int = Int(1)
        internal val x: Long = 1L
        internal val y: Long = Long(1.0)
        """)
    }

    func testHexLiteral() async throws {
        try await check(swift: """
        0xABABAB
        """, kotlin: """
        0xABABAB
        """)
    }

    func testOctalLiteral() async throws {
        // Swift supports octal literals: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/lexicalstructure/#Integer-Literals
        // Octal literals are not supported in Kotlin: https://kotlinlang.org/docs/numbers.html#literal-constants-for-numbers
        try await check(swift: """
        0o400
        """, kotlin: """
        256
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

        // Swift's form-feed '\f' does not exist in Kotlin
        try await check(swift: #""\f""#, kotlin: #""\u000C""#)
        try await check(swift: #""\\f""#, kotlin: #""\\f""#)
    }

    func testUnicodeLiteralStrings() async throws {
        try await check(swift: #""\u{2665}""# , kotlin: #""\u2665""#)
        try await check(swift: #""\\u{2665}""# , kotlin: #""\\u{2665}""#)
        try await check(swift: #""\u2665""# , kotlin: #""\u2665""#)
    }

    func testRawStringLiteral() async throws {
        try await check(swift: """
        #"{"name":"John Smith","isEmployed":true,"age":30}"#
        """, kotlin: """
        \"""{"name":"John Smith","isEmployed":true,"age":30}""\"
        """)
    }

    func testCharacterLiteral() async throws {
        try await check(swift: """
        let c1: Character = "a"
        let c2: Character = "'"
        """, kotlin: """
        internal val c1: Char = 'a'
        internal val c2: Char = '\\''
        """)
    }

    func testArrayLiteral() async throws {
        try await check(swift: """
        {
            let a = [1, 2, 3]
        }
        """, kotlin: """
        import skip.lib.Array

        {
            val a = arrayOf(1, 2, 3)
        }
        """)

        try await check(swift: """
        {
            let a: [Int] = [x, y, z]
        }
        """, kotlin: """
        import skip.lib.Array

        {
            val a: Array<Int> = arrayOf(x, y, z)
        }
        """)

        try await check(swift: """
        {
            let a = [Int]()
            let a = [[(String, String)]]()
        }
        """, kotlin: """
        import skip.lib.Array

        {
            val a = Array<Int>()
            val a = Array<Array<Tuple2<String, String>>>()
        }
        """)

        try await check(supportingSwift: """
        struct S {}
        """, swift: """
        {
            let a = [
                S(),
                S()
            ]
        }
        """, kotlin: """
        import skip.lib.Array

        {
            val a = arrayOf(
                S(),
                S()
            )
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
            let d = [[Int]: (String, String)]()
        }
        """, kotlin: """
        import skip.lib.Array
        
        {
            val d = Dictionary<Int, String>()
            val d = Dictionary<Array<Int>, Tuple2<String, String>>()
        }
        """)

        try await check(supportingSwift: """
        struct S {}
        """, swift: """
        {
            let d = [
                1: S(),
                2: S()
            ]
        }
        """, kotlin: """
        {
            val d = dictionaryOf(
                Tuple2(1, S()),
                Tuple2(2, S())
            )
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
        import skip.lib.Set

        {
            val s: Set<Int> = setOf(1, 2, 3)
            setf(set = s)
            setf(set = setOf(1, 2, 3))
        }
        """)

        try await check(supportingSwift: """
        func setf(set: Set<Character>) {
        }
        """, swift: """
        {
            let s: Set<Character> = ["1", "2", "3"]
            setf(set: s)
            setf(set: ["1", "2", "\\n"])
        }
        """, kotlin: """
        import skip.lib.Set

        {
            val s: Set<Char> = setOf('1', '2', '3')
            setf(set = s)
            setf(set = setOf('1', '2', '\\n'))
        }
        """)
    }

    func testAnyObjectProtocols() async throws {
        try await check(swift: """
        protocol P: AnyObject {
        }
        """, kotlin: """
        internal interface P {
        }
        """)
    }

    func testContainerLiteralClassReference() async throws {
        try await check(swift: """
        {
            let atype = [Int].self
            let dtype = [String: Int].self
        }
        """, kotlin: """
        import skip.lib.Array

        {
            val atype = Array::class
            val dtype = Dictionary::class
        }
        """)
    }

    func testExpressibleByStringInterpolationMatch() async throws {
        try await check(supportingSwift: """
        protocol ExpressibleByStringInterpolation {
        }
        struct LocalizedKey: ExpressibleByStringInterpolation {
            init(stringInterpolation: Interpolation) {
            }
            struct Interpolation {
            }
        }
        class Text {
            init(_ string: String) {
            }
            init(_ string: LocalizedKey) {
            }
        }
        func NSLocalizedString(_ string: String) {
        }
        func NSLocalizedString(_ string: LocalizedKey) {
        }
        func localize(key: String, comment: String? = nil) {
        }
        func localize(key: LocalizedKey, comment: String? = nil) {
        }
        """, swift: """
        Text("Hello!")
        Text("Hello \\(name)!")
        NSLocalizedString("Hello!")
        NSLocalizedString("Hello \\(name)!")
        localize(key: "Hello!")
        localize(key: "Hello!", comment: "Comment")
        localize(key: "Hello \\(name)!")
        localize(key: "Hello \\(name)!", comment: "Comment")
        """, kotlin: """
        Text("Hello!")
        Text({
            val str = LocalizedKey.Interpolation(literalCapacity = 0, interpolationCount = 0)
            str.appendLiteral("Hello ")
            str.appendInterpolation(name)
            str.appendLiteral("!")
            LocalizedKey(stringInterpolation = str)
        }())
        NSLocalizedString("Hello!")
        NSLocalizedString({
            val str = LocalizedKey.Interpolation(literalCapacity = 0, interpolationCount = 0)
            str.appendLiteral("Hello ")
            str.appendInterpolation(name)
            str.appendLiteral("!")
            LocalizedKey(stringInterpolation = str)
        }())
        localize(key = "Hello!")
        localize(key = "Hello!", comment = "Comment")
        localize(key = {
            val str = LocalizedKey.Interpolation(literalCapacity = 0, interpolationCount = 0)
            str.appendLiteral("Hello ")
            str.appendInterpolation(name)
            str.appendLiteral("!")
            LocalizedKey(stringInterpolation = str)
        }())
        localize(key = {
            val str = LocalizedKey.Interpolation(literalCapacity = 0, interpolationCount = 0)
            str.appendLiteral("Hello ")
            str.appendInterpolation(name)
            str.appendLiteral("!")
            LocalizedKey(stringInterpolation = str)
        }(), comment = "Comment")
        """)
    }
}
