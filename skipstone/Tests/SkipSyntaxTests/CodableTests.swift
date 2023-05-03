import XCTest

final class CodableTests: XCTestCase {
    func testImmutableStructSynthesis() async throws {
        try await check(swift: """
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

            private fun CodingKeys(rawValue: String): CodingKeys? {
                return when (rawValue) {
                    "i" -> {
                        CodingKeys.i
                    }
                    "s" -> {
                        CodingKeys.s
                    }
                    else -> {
                        null
                    }
                }
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

            companion object: DecodableCompanion {
                override fun init(from: Decoder): Any = S(from = from)
            }
        }
        """)
    }

    func testMutableStructSynthesis() async throws {
        try await check(swift: """
        struct S: Codable {
            var i = 0
            var s = ""
        }
        """, kotlin: """
        internal class S: Codable, MutableStruct {
            internal var i = 0
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }
            internal var s = ""
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

            private fun CodingKeys(rawValue: String): CodingKeys? {
                return when (rawValue) {
                    "i" -> {
                        CodingKeys.i
                    }
                    "s" -> {
                        CodingKeys.s
                    }
                    else -> {
                        null
                    }
                }
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

            companion object: DecodableCompanion {
                override fun init(from: Decoder): Any = S(from = from)
            }
        }
        """)
    }

    func testCustomCodingKeys() async throws {
        try await check(swift: """
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

            private fun CodingKeys(rawValue: String): S.CodingKeys? {
                return when (rawValue) {
                    "i" -> {
                        CodingKeys.i
                    }
                    "dbl" -> {
                        CodingKeys.d
                    }
                    else -> {
                        null
                    }
                }
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

            companion object: DecodableCompanion {
                override fun init(from: Decoder): Any = S(from = from)
            }
        }
        """)

        try await check(swift: """
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

            private fun CodingKeys(rawValue: Int): S.CodingKeys? {
                return when (rawValue) {
                    100 -> {
                        CodingKeys.i
                    }
                    101 -> {
                        CodingKeys.d
                    }
                    else -> {
                        null
                    }
                }
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

            companion object: DecodableCompanion {
                override fun init(from: Decoder): Any = S(from = from)
            }
        }
        """)
    }

    func testCustomCodable() async throws {
        try await check(swift: """
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

            private fun CK(rawValue: String): S.CK? {
                return when (rawValue) {
                    "i" -> {
                        CK.i
                    }
                    "s" -> {
                        CK.s
                    }
                    else -> {
                        null
                    }
                }
            }

            override fun encode(to: Encoder) = Unit

            constructor(from: Decoder) {
            }

            companion object: DecodableCompanion {
                override fun init(from: Decoder): Any = S(from = from)
            }
        }
        """)
    }

    func testGenerics() async throws {
        try await check(swift: """
        struct S: Codable {
            let a: [Int]
        }
        """, kotlin: """
        internal class S: Codable {
            internal val a: Array<Int>
                get() {
                    return field.sref()
                }

            constructor(a: Array<Int>) {
                this.a = a
            }

            private enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                a("a");
            }

            private fun CodingKeys(rawValue: String): CodingKeys? {
                return when (rawValue) {
                    "a" -> {
                        CodingKeys.a
                    }
                    else -> {
                        null
                    }
                }
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encode(a, forKey = CodingKeys.a)
            }

            constructor(from: Decoder) {
                val container = from.container(keyedBy = CodingKeys::class)
                this.a = container.decode(Array::class, forKey = CodingKeys.a)
            }

            companion object: DecodableCompanion {
                override fun init(from: Decoder): Any = S(from = from)
            }
        }
        """)
    }

    func testEncodableOnlySynthesis() async throws {
        try await check(swift: """
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

            private fun CodingKeys(rawValue: String): CodingKeys? {
                return when (rawValue) {
                    "i" -> {
                        CodingKeys.i
                    }
                    "s" -> {
                        CodingKeys.s
                    }
                    else -> {
                        null
                    }
                }
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encode(i, forKey = CodingKeys.i)
                container.encode(s, forKey = CodingKeys.s)
            }
        }
        """)
    }

    func testCustomEncodable() async throws {
        try await check(swift: """
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

            private fun CK(rawValue: String): S.CK? {
                return when (rawValue) {
                    "i" -> {
                        CK.i
                    }
                    "s" -> {
                        CK.s
                    }
                    else -> {
                        null
                    }
                }
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

            private fun CodingKeys(rawValue: String): CodingKeys? {
                return when (rawValue) {
                    "i" -> {
                        CodingKeys.i
                    }
                    "s" -> {
                        CodingKeys.s
                    }
                    else -> {
                        null
                    }
                }
            }

            constructor(from: Decoder) {
                val container = from.container(keyedBy = CodingKeys::class)
                this.i = container.decode(Int::class, forKey = CodingKeys.i)
                this.s = container.decode(String::class, forKey = CodingKeys.s)
            }

            companion object: DecodableCompanion {
                override fun init(from: Decoder): Any = S(from = from)
            }
        }
        """)
    }

    func testDecodableOnlySynthesis() async throws {
        try await check(swift: """
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

            private fun CodingKeys(rawValue: String): CodingKeys? {
                return when (rawValue) {
                    "i" -> {
                        CodingKeys.i
                    }
                    "s" -> {
                        CodingKeys.s
                    }
                    else -> {
                        null
                    }
                }
            }

            constructor(from: Decoder) {
                val container = from.container(keyedBy = CodingKeys::class)
                this.i = container.decode(Int::class, forKey = CodingKeys.i)
                this.s = container.decode(String::class, forKey = CodingKeys.s)
            }

            companion object: DecodableCompanion {
                override fun init(from: Decoder): Any = S(from = from)
            }
        }
        """)
    }

    func testCustomDecodable() async throws {
        try await check(swift: """
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

            private fun CodingKeys(rawValue: String): S.CodingKeys? {
                return when (rawValue) {
                    "i" -> {
                        CodingKeys.i
                    }
                    "s" -> {
                        CodingKeys.s
                    }
                    else -> {
                        null
                    }
                }
            }

            constructor(from: Decoder) {
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encode(i, forKey = CodingKeys.i)
                container.encode(s, forKey = CodingKeys.s)
            }

            companion object: DecodableCompanion {
                override fun init(from: Decoder): Any = S(from = from)
            }
        }
        """)
    }

    func testOptional() async throws {
        try await check(swift: """
        struct S: Codable {
            let i: Int?
            let s: String?
        }
        """, kotlin: """
        internal class S: Codable {
            internal val i: Int?
            internal val s: String?

            constructor(i: Int? = null, s: String? = null) {
                this.i = i
                this.s = s
            }

            private enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                i("i"),
                s("s");
            }

            private fun CodingKeys(rawValue: String): CodingKeys? {
                return when (rawValue) {
                    "i" -> {
                        CodingKeys.i
                    }
                    "s" -> {
                        CodingKeys.s
                    }
                    else -> {
                        null
                    }
                }
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encodeIfPresent(i, forKey = CodingKeys.i)
                container.encodeIfPresent(s, forKey = CodingKeys.s)
            }

            constructor(from: Decoder) {
                val container = from.container(keyedBy = CodingKeys::class)
                this.i = container.decodeIfPresent(Int::class, forKey = CodingKeys.i)
                this.s = container.decodeIfPresent(String::class, forKey = CodingKeys.s)
            }

            companion object: DecodableCompanion {
                override fun init(from: Decoder): Any = S(from = from)
            }
        }
        """)
    }

    func testConstantBecomesWritable() async throws {
        try await check(swift: """
        struct S: Codable {
            let i: Int
            let a = ["foo"]
        }
        """, kotlin: """
        internal class S: Codable {
            internal val i: Int
            internal var a = arrayOf("foo")
                get() {
                    return field.sref()
                }
                set(newValue) {
                    field = newValue.sref()
                }

            constructor(i: Int) {
                this.i = i
            }

            private enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                i("i"),
                a("a");
            }

            private fun CodingKeys(rawValue: String): CodingKeys? {
                return when (rawValue) {
                    "i" -> {
                        CodingKeys.i
                    }
                    "a" -> {
                        CodingKeys.a
                    }
                    else -> {
                        null
                    }
                }
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encode(i, forKey = CodingKeys.i)
                container.encode(a, forKey = CodingKeys.a)
            }

            constructor(from: Decoder) {
                val container = from.container(keyedBy = CodingKeys::class)
                this.i = container.decode(Int::class, forKey = CodingKeys.i)
                this.a = container.decode(Array::class, forKey = CodingKeys.a)
            }

            companion object: DecodableCompanion {
                override fun init(from: Decoder): Any = S(from = from)
            }
        }
        """)
    }

    func testSubclass() async throws {
        try await check(supportingSwift: """
        class Base {
            var i = 100
        }
        """, swift: """
        class Sub: Base, Codable {
            var s = "string"
        }
        """, kotlin: """
        internal open class Sub: Base, Codable {
            internal var s = "string"

            private enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                s("s");
            }

            private fun CodingKeys(rawValue: String): CodingKeys? {
                return when (rawValue) {
                    "s" -> {
                        CodingKeys.s
                    }
                    else -> {
                        null
                    }
                }
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encode(s, forKey = CodingKeys.s)
            }

            constructor(from: Decoder): super() {
                val container = from.container(keyedBy = CodingKeys::class)
                this.s = container.decode(String::class, forKey = CodingKeys.s)
            }

            companion object: DecodableCompanion {
                override fun init(from: Decoder): Any = Sub(from = from)
            }
        }
        """)
    }

    func testRawValueEnum() async throws {
        try await check(swift: """
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

            companion object: DecodableCompanion {
                override fun init(from: Decoder): Any = E(from = from)
            }
        }

        internal fun E(rawValue: Int): E? {
            return when (rawValue) {
                0 -> {
                    E.a
                }
                1 -> {
                    E.b
                }
                else -> {
                    null
                }
            }
        }

        internal fun E(from: Decoder): E {
            val container = from.singleValueContainer()
            val rawValue = container.decode(Int::class)
            return E(rawValue = rawValue) ?: throw ErrorException(cause = NullPointerException())
        }
        """)

        try await check(swift: """
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

            companion object: DecodableCompanion {
                override fun init(from: Decoder): Any = E(from = from)
            }
        }

        internal fun E(from: Decoder): E = E.a

        internal fun E(rawValue: Int): E? {
            return when (rawValue) {
                0 -> {
                    E.a
                }
                1 -> {
                    E.b
                }
                else -> {
                    null
                }
            }
        }
        """)
    }

    func testNonRawValueEnum() async throws {
        try await checkProducesMessage(swift: """
        enum E: Codable {
            case a, b
        }
        """)

        try await check(swift: """
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

            companion object: DecodableCompanion {
                override fun init(from: Decoder): Any = E(from = from)
            }
        }

        internal fun E(from: Decoder): E = E.a
        """)
    }

    func testAssociatedValueEnum() async throws {
        try await checkProducesMessage(swift: """
        enum E: Codable {
            case a(Int)
            case b
        }
        """)

        try await check(swift: """
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

            companion object: DecodableCompanion {
                fun a(associated0: Int): E = ACase(associated0)
                val b: E = BCase()

                override fun init(from: Decoder): Any = E(from = from)
            }
        }

        internal fun E(from: Decoder): E = E.a(100)
        """)
    }
}
