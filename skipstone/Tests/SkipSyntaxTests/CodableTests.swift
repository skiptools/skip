import XCTest

final class CodableTests: XCTestCase {
    private let codableDeclaration = """
    protocol Encodable {}
    protocol Decodable {}
    protocol Codable: Encodable, Decodable {}
    """

    func testImmutableStructSynthesis() async throws {
        try await check(supportingSwift: codableDeclaration, swift: """
        struct S: Codable {
            let i: Int
            let s: String
        }
        """, kotlin: """
        internal class S: Codable {
            internal val i: Int
            internal val s: String

            constructor(i: Int, s: String) {
                this.i = i
                this.s = s
            }

            private enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                i("i"),
                s("s");
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encode(i, forKey = CodingKeys.i)
                container.encode(s, forKey = CodingKeys.s)
            }

            constructor(from: Decoder) {
                val container = from.container(keyedBy = CodingKeys::class)
                this.i = container.decode(Int::class, forKey = CodingKeys.i)
                this.s = container.decode(String::class, forKey = CodingKeys.s)
            }

            companion object: DecodableCompanion<S> {
                override fun init(from: Decoder): S = S(from = from)

                private fun CodingKeys(rawValue: String): CodingKeys? {
                    return when (rawValue) {
                        "i" -> CodingKeys.i
                        "s" -> CodingKeys.s
                        else -> null
                    }
                }
            }
        }
        """)
    }

    func testMutableStructSynthesis() async throws {
        try await check(supportingSwift: codableDeclaration, swift: """
        struct S: Codable {
            var i = 0
            var s = ""
        }
        """, kotlin: """
        internal class S: Codable, MutableStruct {
            internal var i: Int
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }
            internal var s: String
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }

            constructor(i: Int = 0, s: String = "") {
                this.i = i
                this.s = s
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(i, s)

            private enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                i("i"),
                s("s");
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encode(i, forKey = CodingKeys.i)
                container.encode(s, forKey = CodingKeys.s)
            }

            constructor(from: Decoder) {
                val container = from.container(keyedBy = CodingKeys::class)
                this.i = container.decode(Int::class, forKey = CodingKeys.i)
                this.s = container.decode(String::class, forKey = CodingKeys.s)
            }

            companion object: DecodableCompanion<S> {
                override fun init(from: Decoder): S = S(from = from)

                private fun CodingKeys(rawValue: String): CodingKeys? {
                    return when (rawValue) {
                        "i" -> CodingKeys.i
                        "s" -> CodingKeys.s
                        else -> null
                    }
                }
            }
        }
        """)
    }

    func testCustomCodingKeys() async throws {
        try await check(supportingSwift: codableDeclaration, swift: """
        struct S: Codable {
            let i: Int
            let d: Double
            let s = "foo"

            private enum CodingKeys: CodingKey {
                case i
                case d = "dbl"
            }
        }
        """, kotlin: """
        internal class S: Codable {
            internal val i: Int
            internal val d: Double
            internal val s = "foo"

            private enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                i("i"),
                d("dbl");
            }

            constructor(i: Int, d: Double) {
                this.i = i
                this.d = d
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encode(i, forKey = CodingKeys.i)
                container.encode(d, forKey = CodingKeys.d)
            }

            constructor(from: Decoder) {
                val container = from.container(keyedBy = CodingKeys::class)
                this.i = container.decode(Int::class, forKey = CodingKeys.i)
                this.d = container.decode(Double::class, forKey = CodingKeys.d)
            }

            companion object: DecodableCompanion<S> {
                override fun init(from: Decoder): S = S(from = from)

                private fun CodingKeys(rawValue: String): S.CodingKeys? {
                    return when (rawValue) {
                        "i" -> CodingKeys.i
                        "dbl" -> CodingKeys.d
                        else -> null
                    }
                }
            }
        }
        """)

        try await check(supportingSwift: codableDeclaration, swift: """
        struct S: Codable {
            let i: Int
            let d: Double
            let s = "foo"

            private enum CodingKeys: Int, CodingKey {
                case i = 100
                case d
            }
        }
        """, kotlin: """
        internal class S: Codable {
            internal val i: Int
            internal val d: Double
            internal val s = "foo"

            private enum class CodingKeys(override val rawValue: Int, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<Int> {
                i(100),
                d(101);
            }

            constructor(i: Int, d: Double) {
                this.i = i
                this.d = d
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encode(i, forKey = CodingKeys.i)
                container.encode(d, forKey = CodingKeys.d)
            }

            constructor(from: Decoder) {
                val container = from.container(keyedBy = CodingKeys::class)
                this.i = container.decode(Int::class, forKey = CodingKeys.i)
                this.d = container.decode(Double::class, forKey = CodingKeys.d)
            }

            companion object: DecodableCompanion<S> {
                override fun init(from: Decoder): S = S(from = from)

                private fun CodingKeys(rawValue: Int): S.CodingKeys? {
                    return when (rawValue) {
                        100 -> CodingKeys.i
                        101 -> CodingKeys.d
                        else -> null
                    }
                }
            }
        }
        """)
    }

    func testCustomCodable() async throws {
        try await check(supportingSwift: codableDeclaration, swift: """
        struct S: Codable {
            let i: Int
            let s: String

            private enum CK: CodingKey {
                case i, s
            }

            func encode(to encoder: Encoder) {
            }

            init(from decoder: Decoder) {
            }
        }
        """, kotlin: """
        internal class S: Codable {
            internal val i: Int
            internal val s: String

            private enum class CK(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                i("i"),
                s("s");
            }

            override fun encode(to: Encoder) = Unit

            constructor(from: Decoder) {
            }

            constructor(i: Int, s: String) {
                this.i = i
                this.s = s
            }

            companion object: DecodableCompanion<S> {
                override fun init(from: Decoder): S = S(from = from)

                private fun CK(rawValue: String): S.CK? {
                    return when (rawValue) {
                        "i" -> CK.i
                        "s" -> CK.s
                        else -> null
                    }
                }
            }
        }
        """)
    }

    func testGenerics() async throws {
        try await check(supportingSwift: codableDeclaration, swift: """
        struct S: Codable {
            let a: [Int]
            let d: [String: S]
            let na: [[Int]]
            let nd: [String: [S]]
        }
        """, kotlin: """
        import skip.lib.Array

        internal class S: Codable {
            internal val a: Array<Int>
            internal val d: Dictionary<String, S>
            internal val na: Array<Array<Int>>
            internal val nd: Dictionary<String, Array<S>>

            constructor(a: Array<Int>, d: Dictionary<String, S>, na: Array<Array<Int>>, nd: Dictionary<String, Array<S>>) {
                this.a = a.sref()
                this.d = d.sref()
                this.na = na.sref()
                this.nd = nd.sref()
            }

            private enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                a("a"),
                d("d"),
                na("na"),
                nd("nd");
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encode(a, forKey = CodingKeys.a)
                container.encode(d, forKey = CodingKeys.d)
                container.encode(na, forKey = CodingKeys.na)
                container.encode(nd, forKey = CodingKeys.nd)
            }

            constructor(from: Decoder) {
                val container = from.container(keyedBy = CodingKeys::class)
                this.a = container.decode(Array::class, elementType = Int::class, forKey = CodingKeys.a)
                this.d = container.decode(Dictionary::class, keyType = String::class, valueType = S::class, forKey = CodingKeys.d)
                this.na = container.decode(Array::class, elementType = Array::class, nestedElementType = Int::class, forKey = CodingKeys.na)
                this.nd = container.decode(Dictionary::class, keyType = String::class, valueType = Array::class, nestedElementType = S::class, forKey = CodingKeys.nd)
            }

            companion object: DecodableCompanion<S> {
                override fun init(from: Decoder): S = S(from = from)

                private fun CodingKeys(rawValue: String): CodingKeys? {
                    return when (rawValue) {
                        "a" -> CodingKeys.a
                        "d" -> CodingKeys.d
                        "na" -> CodingKeys.na
                        "nd" -> CodingKeys.nd
                        else -> null
                    }
                }
            }
        }
        """)
    }

    func testEncodableOnlySynthesis() async throws {
        try await check(supportingSwift: codableDeclaration, swift: """
        struct S: Encodable {
            let i: Int
            let s: String
        }
        """, kotlin: """
        internal class S: Encodable {
            internal val i: Int
            internal val s: String

            constructor(i: Int, s: String) {
                this.i = i
                this.s = s
            }

            private enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                i("i"),
                s("s");
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encode(i, forKey = CodingKeys.i)
                container.encode(s, forKey = CodingKeys.s)
            }

            companion object {

                private fun CodingKeys(rawValue: String): CodingKeys? {
                    return when (rawValue) {
                        "i" -> CodingKeys.i
                        "s" -> CodingKeys.s
                        else -> null
                    }
                }
            }
        }
        """)
    }

    func testCustomEncodable() async throws {
        try await check(supportingSwift: codableDeclaration, swift: """
        struct S: Codable {
            let i: Int
            let s: String

            private enum CK: CodingKey {
                case i, s
            }

            func encode(to encoder: Encoder) {
            }
        }
        """, kotlin: """
        internal class S: Codable {
            internal val i: Int
            internal val s: String

            private enum class CK(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                i("i"),
                s("s");
            }

            override fun encode(to: Encoder) = Unit

            constructor(i: Int, s: String) {
                this.i = i
                this.s = s
            }

            private enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                i("i"),
                s("s");
            }

            constructor(from: Decoder) {
                val container = from.container(keyedBy = CodingKeys::class)
                this.i = container.decode(Int::class, forKey = CodingKeys.i)
                this.s = container.decode(String::class, forKey = CodingKeys.s)
            }

            companion object: DecodableCompanion<S> {
                override fun init(from: Decoder): S = S(from = from)

                private fun CK(rawValue: String): S.CK? {
                    return when (rawValue) {
                        "i" -> CK.i
                        "s" -> CK.s
                        else -> null
                    }
                }

                private fun CodingKeys(rawValue: String): CodingKeys? {
                    return when (rawValue) {
                        "i" -> CodingKeys.i
                        "s" -> CodingKeys.s
                        else -> null
                    }
                }
            }
        }
        """)
    }

    func testDecodableOnlySynthesis() async throws {
        try await check(supportingSwift: codableDeclaration, swift: """
        struct S: Decodable {
            let i: Int
            let s: String
        }
        """, kotlin: """
        internal class S: Decodable {
            internal val i: Int
            internal val s: String

            constructor(i: Int, s: String) {
                this.i = i
                this.s = s
            }

            private enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                i("i"),
                s("s");
            }

            constructor(from: Decoder) {
                val container = from.container(keyedBy = CodingKeys::class)
                this.i = container.decode(Int::class, forKey = CodingKeys.i)
                this.s = container.decode(String::class, forKey = CodingKeys.s)
            }

            companion object: DecodableCompanion<S> {
                override fun init(from: Decoder): S = S(from = from)

                private fun CodingKeys(rawValue: String): CodingKeys? {
                    return when (rawValue) {
                        "i" -> CodingKeys.i
                        "s" -> CodingKeys.s
                        else -> null
                    }
                }
            }
        }
        """)
    }

    func testCustomDecodable() async throws {
        try await check(supportingSwift: codableDeclaration, swift: """
        struct S: Codable {
            let i: Int
            let s: String

            private enum CodingKeys: CodingKey {
                case i, s
            }

            init(from decoder: Decoder) {
            }
        }
        """, kotlin: """
        internal class S: Codable {
            internal val i: Int
            internal val s: String

            private enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                i("i"),
                s("s");
            }

            constructor(from: Decoder) {
            }

            constructor(i: Int, s: String) {
                this.i = i
                this.s = s
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encode(i, forKey = CodingKeys.i)
                container.encode(s, forKey = CodingKeys.s)
            }

            companion object: DecodableCompanion<S> {
                override fun init(from: Decoder): S = S(from = from)

                private fun CodingKeys(rawValue: String): S.CodingKeys? {
                    return when (rawValue) {
                        "i" -> CodingKeys.i
                        "s" -> CodingKeys.s
                        else -> null
                    }
                }
            }
        }
        """)
    }

    func testCustomCodableGenerics() async throws {
        try await check(supportingSwift: codableDeclaration, swift: """
        struct S: Codable {
            let a: [Int]
            let d: [String: S]
            let na: [[Int]]
            let nd: [String: [S]]

            private enum CK: CodingKey {
                case a, d, na, nd
            }

            func encode(to encoder: Encoder) {
                let container = encoder.container(keyedBy: CK.self)
                container.encode(a, forKey: CK.a)
                container.encode(d, forKey: CK.d)
                container.encode(na, forKey: CK.na)
                container.encode(nd, forKey: CK.nd)
            }

            init(from decoder: Decoder) {
                let container = decoder.container(keyedBy: CK.self)
                self.a = container.decodeIfPresent([Int].self, forKey: CK.a) ?? []
                self.d = container.decode(Dictionary<String, S>.self, forKey: CK.d)
                self.na = container.decode(Array<[Int]>.self, forKey: CK.na)
                self.nd = container.decode([String: Array<S>].self, forKey: CK.nd)
            }
        }
        """, kotlin: """
        import skip.lib.Array

        internal class S: Codable {
            internal val a: Array<Int>
            internal val d: Dictionary<String, S>
            internal val na: Array<Array<Int>>
            internal val nd: Dictionary<String, Array<S>>

            private enum class CK(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                a("a"),
                d("d"),
                na("na"),
                nd("nd");
            }

            override fun encode(to: Encoder) {
                val encoder = to
                val container = encoder.container(keyedBy = CK::class)
                container.encode(a, forKey = CK.a)
                container.encode(d, forKey = CK.d)
                container.encode(na, forKey = CK.na)
                container.encode(nd, forKey = CK.nd)
            }

            constructor(from: Decoder) {
                val decoder = from
                val container = decoder.container(keyedBy = CK::class)
                this.a = (container.decodeIfPresent(Array::class, elementType = Int::class, forKey = CK.a) ?: arrayOf()).sref()
                this.d = container.decode(Dictionary::class, keyType = String::class, valueType = S::class, forKey = CK.d)
                this.na = container.decode(Array::class, elementType = Array::class, nestedElementType = Int::class, forKey = CK.na)
                this.nd = container.decode(Dictionary::class, keyType = String::class, valueType = Array::class, nestedElementType = S::class, forKey = CK.nd)
            }

            constructor(a: Array<Int>, d: Dictionary<String, S>, na: Array<Array<Int>>, nd: Dictionary<String, Array<S>>) {
                this.a = a.sref()
                this.d = d.sref()
                this.na = na.sref()
                this.nd = nd.sref()
            }

            companion object: DecodableCompanion<S> {
                override fun init(from: Decoder): S = S(from = from)

                private fun CK(rawValue: String): S.CK? {
                    return when (rawValue) {
                        "a" -> CK.a
                        "d" -> CK.d
                        "na" -> CK.na
                        "nd" -> CK.nd
                        else -> null
                    }
                }
            }
        }
        """)
    }

    func testOptional() async throws {
        try await check(supportingSwift: codableDeclaration, swift: """
        struct S: Codable {
            let i: Int?
            let s: String?
            let a: [Int]?
        }
        """, kotlin: """
        import skip.lib.Array

        internal class S: Codable {
            internal val i: Int?
            internal val s: String?
            internal val a: Array<Int>?

            constructor(i: Int? = null, s: String? = null, a: Array<Int>? = null) {
                this.i = i
                this.s = s
                this.a = a.sref()
            }

            private enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                i("i"),
                s("s"),
                a("a");
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encodeIfPresent(i, forKey = CodingKeys.i)
                container.encodeIfPresent(s, forKey = CodingKeys.s)
                container.encodeIfPresent(a, forKey = CodingKeys.a)
            }

            constructor(from: Decoder) {
                val container = from.container(keyedBy = CodingKeys::class)
                this.i = container.decodeIfPresent(Int::class, forKey = CodingKeys.i)
                this.s = container.decodeIfPresent(String::class, forKey = CodingKeys.s)
                this.a = container.decodeIfPresent(Array::class, elementType = Int::class, forKey = CodingKeys.a)
            }

            companion object: DecodableCompanion<S> {
                override fun init(from: Decoder): S = S(from = from)

                private fun CodingKeys(rawValue: String): CodingKeys? {
                    return when (rawValue) {
                        "i" -> CodingKeys.i
                        "s" -> CodingKeys.s
                        "a" -> CodingKeys.a
                        else -> null
                    }
                }
            }
        }
        """)
    }

    func testConstantBecomesWritable() async throws {
        try await check(supportingSwift: codableDeclaration, swift: """
        struct S: Codable {
            let i: Int
            let a = ["foo"]
        }
        """, kotlin: """
        import skip.lib.Array

        internal class S: Codable {
            internal val i: Int
            internal val a = arrayOf("foo")

            constructor(i: Int) {
                this.i = i
            }

            private enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                i("i"),
                a("a");
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encode(i, forKey = CodingKeys.i)
                container.encode(a, forKey = CodingKeys.a)
            }

            constructor(from: Decoder) {
                val container = from.container(keyedBy = CodingKeys::class)
                this.i = container.decode(Int::class, forKey = CodingKeys.i)
            }

            companion object: DecodableCompanion<S> {
                override fun init(from: Decoder): S = S(from = from)

                private fun CodingKeys(rawValue: String): CodingKeys? {
                    return when (rawValue) {
                        "i" -> CodingKeys.i
                        "a" -> CodingKeys.a
                        else -> null
                    }
                }
            }
        }
        """)
    }

    func testUncodedProperties() async throws {
        try await check(supportingSwift: codableDeclaration, swift: """
        struct S: Codable {
            let i = 100
            var s = "str"
            let j = 200
            var t = "string"

            enum CodingKeys: CodingKey {
                case j, t
            }
        }
        """, kotlin: """
        internal class S: Codable, MutableStruct {
            internal val i: Int
            internal var s: String
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }
            internal val j: Int
            internal var t: String
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }

            internal enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                j("j"),
                t("t");
            }

            constructor(s: String = "str", t: String = "string") {
                this.i = 100
                this.j = 200
                this.s = s
                this.t = t
            }

            private constructor(copy: MutableStruct) {
                @Suppress("NAME_SHADOWING", "UNCHECKED_CAST") val copy = copy as S
                this.i = copy.i
                this.s = copy.s
                this.j = copy.j
                this.t = copy.t
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(this as MutableStruct)

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encode(j, forKey = CodingKeys.j)
                container.encode(t, forKey = CodingKeys.t)
            }

            constructor(from: Decoder) {
                this.i = 100
                this.j = 200
                val container = from.container(keyedBy = CodingKeys::class)
                this.s = "str"
                this.t = container.decode(String::class, forKey = CodingKeys.t)
            }

            companion object: DecodableCompanion<S> {
                override fun init(from: Decoder): S = S(from = from)

                internal fun CodingKeys(rawValue: String): S.CodingKeys? {
                    return when (rawValue) {
                        "j" -> CodingKeys.j
                        "t" -> CodingKeys.t
                        else -> null
                    }
                }
            }
        }
        """)
    }

    func testSubclass() async throws {
        try await check(supportingSwift: codableDeclaration +  """
        class Base {
            var i = 100
        }
        """, swift: """
        class Sub: Base, Codable {
            var s = "string"
        }
        """, kotlin: """
        internal open class Sub: Base, Codable {
            internal open var s = "string"

            private enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                s("s");
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encode(s, forKey = CodingKeys.s)
            }

            constructor(from: Decoder): super() {
                val container = from.container(keyedBy = CodingKeys::class)
                this.s = container.decode(String::class, forKey = CodingKeys.s)
            }

            companion object: DecodableCompanion<Sub> {
                override fun init(from: Decoder): Sub = Sub(from = from)

                private fun CodingKeys(rawValue: String): CodingKeys? {
                    return when (rawValue) {
                        "s" -> CodingKeys.s
                        else -> null
                    }
                }
            }
        }
        """)
    }

    func testRawValueEnum() async throws {
        try await check(supportingSwift: codableDeclaration, swift: """
        enum E: Int, Codable {
            case a, b
        }
        """, kotlin: """
        internal enum class E(override val rawValue: Int, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): Codable, RawRepresentable<Int> {
            a(0),
            b(1);

            override fun encode(to: Encoder) {
                val container = to.singleValueContainer()
                container.encode(rawValue)
            }

            companion object: DecodableCompanion<E> {
                override fun init(from: Decoder): E = E(from = from)
            }
        }

        internal fun E(rawValue: Int): E? {
            return when (rawValue) {
                0 -> E.a
                1 -> E.b
                else -> null
            }
        }

        internal fun E(from: Decoder): E {
            val container = from.singleValueContainer()
            val rawValue = container.decode(Int::class)
            return E(rawValue = rawValue) ?: throw ErrorException(cause = NullPointerException())
        }
        """)

        try await check(supportingSwift: codableDeclaration, swift: """
        enum E: Int, Codable {
            case a, b

            func encode(to: Encoder) {
            }

            init(from: Decoder) {
                self = .a
            }
        }
        """, kotlin: """
        internal enum class E(override val rawValue: Int, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): Codable, RawRepresentable<Int> {
            a(0),
            b(1);

            override fun encode(to: Encoder) = Unit

            companion object: DecodableCompanion<E> {
                override fun init(from: Decoder): E = E(from = from)
            }
        }

        internal fun E(from: Decoder): E = E.a

        internal fun E(rawValue: Int): E? {
            return when (rawValue) {
                0 -> E.a
                1 -> E.b
                else -> null
            }
        }
        """)
    }

    func testNonRawValueEnum() async throws {
        try await checkProducesMessage(swift: codableDeclaration + """
        enum E: Codable {
            case a, b
        }
        """)

        try await check(supportingSwift: codableDeclaration, swift: """
        enum E: Codable {
            case a, b

            func encode(to: Encoder) {
            }

            init(from: Decoder) {
                self = .a
            }
        }
        """, kotlin: """
        internal enum class E: Codable {
            a,
            b;

            override fun encode(to: Encoder) = Unit

            companion object: DecodableCompanion<E> {
                override fun init(from: Decoder): E = E(from = from)
            }
        }

        internal fun E(from: Decoder): E = E.a
        """)
    }

    func testAssociatedValueEnum() async throws {
        try await checkProducesMessage(swift: codableDeclaration + """
        enum E: Codable {
            case a(Int)
            case b
        }
        """)

        try await check(supportingSwift: codableDeclaration, swift: """
        enum E: Codable {
            case a(Int)
            case b

            func encode(to: Encoder) {
            }

            init(from: Decoder) {
                self = .a(100)
            }
        }
        """, kotlin: """
        internal sealed class E: Codable {
            class ACase(val associated0: Int): E() {
            }
            class BCase: E() {
            }

            override fun encode(to: Encoder) = Unit

            companion object: DecodableCompanion<E> {
                fun a(associated0: Int): E = ACase(associated0)
                val b: E = BCase()

                override fun init(from: Decoder): E = E(from = from)
            }
        }

        internal fun E(from: Decoder): E = E.a(100)
        """)
    }

    func testDisallowedEnumCaseNames() async throws {
        try await check(supportingSwift: codableDeclaration, swift: """
        struct S: Codable {
            let name: String
            let package: String
        }
        """, kotlin: """
        internal class S: Codable {
            internal val name: String
            internal val package_: String

            constructor(name: String, package_: String) {
                this.name = name
                this.package_ = package_
            }

            private enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                name_("name"),
                package_("package");
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encode(name, forKey = CodingKeys.name_)
                container.encode(package_, forKey = CodingKeys.package_)
            }

            constructor(from: Decoder) {
                val container = from.container(keyedBy = CodingKeys::class)
                this.name = container.decode(String::class, forKey = CodingKeys.name_)
                this.package_ = container.decode(String::class, forKey = CodingKeys.package_)
            }

            companion object: DecodableCompanion<S> {
                override fun init(from: Decoder): S = S(from = from)

                private fun CodingKeys(rawValue: String): CodingKeys? {
                    return when (rawValue) {
                        "name" -> CodingKeys.name_
                        "package" -> CodingKeys.package_
                        else -> null
                    }
                }
            }
        }
        """)
    }
}
