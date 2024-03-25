import XCTest

final class ErrorHandlingTests: XCTestCase {
    func testDoWithoutCatch() async throws {
        try await check(swift: """
        do {
            action1()
            action2()
        }
        """, kotlin: """
        run {
            action1()
            action2()
        }
        """)

        try await check(swift: """
        do {
            action1()
            defer { finalAction() }
            action2()
        }
        """, kotlin: """
        var deferaction_0: (() -> Unit)? = null
        try {
            action1()
            deferaction_0 = {
                finalAction()
            }
            action2()
        } finally {
            deferaction_0?.invoke()
        }
        """)
    }

    func testCatchAll() async throws {
        try await check(supportingSwift: """
        struct S: Error {
            var message = ""
        }
        """, swift: """
        do {
            action1()
            action2()
            throw S()
        } catch {
            print("Caught error: \\(error)")
        }
        """, kotlin: """
        try {
            action1()
            action2()
            throw S()
        } catch (error: Throwable) {
            @Suppress("NAME_SHADOWING") val error = error.aserror()
            print("Caught error: ${error}")
        }
        """)
    }

    func testCatchIs() async throws {
        try await check(supportingSwift: """
        struct S: Error {
            var message = ""
        }
        """, swift: """
        do {
            action1()
            action2()
        } catch is S {
            print("Caught error: \\(error)")
        } catch {
        }
        """, kotlin: """
        try {
            action1()
            action2()
        } catch (error: S) {
            print("Caught error: ${error}")
        } catch (error: Throwable) {
            @Suppress("NAME_SHADOWING") val error = error.aserror()
        }
        """)
    }

    func testCatchLet() async throws {
        try await check(swift: """
        do {
            action1()
        } catch let e {
            print("Caught error: \\(e)")
        }
        """, kotlin: """
        try {
            action1()
        } catch (error: Throwable) {
            @Suppress("NAME_SHADOWING") val error = error.aserror()
            val e = error
            print("Caught error: ${e}")
        }
        """)

        try await check(swift: """
        do {
            action1()
        } catch var error {
            print("Caught error: \\(error)")
        }
        """, kotlin: """
        try {
            action1()
        } catch (error: Throwable) {
            @Suppress("NAME_SHADOWING") var error = error.aserror()
            print("Caught error: ${error}")
        }
        """)
    }

    func testCatchLetAs() async throws {
        try await check(supportingSwift: """
        struct S: Error {
            var message = ""
        }
        """, swift: """
        do {
            action1()
            action2()
        } catch let e as S {
            print("Caught error: \\(e)")
        } catch {
        }
        """, kotlin: """
        try {
            action1()
            action2()
        } catch (e: S) {
            print("Caught error: ${e}")
        } catch (error: Throwable) {
            @Suppress("NAME_SHADOWING") val error = error.aserror()
        }
        """)

        try await check(supportingSwift: """
        struct S: Error {
            var message = ""
        }
        """, swift: """
        do {
            action1()
            action2()
        } catch let error as S {
            print("Caught error: \\(error)")
        }
        """, kotlin: """
        try {
            action1()
            action2()
        } catch (error: S) {
            print("Caught error: ${error}")
        }
        """)

        try await check(supportingSwift: """
        struct S: Error {
            var message = ""
        }
        """, swift: """
        do {
            action1()
            action2()
        } catch var error as S {
            print("Caught error: \\(error)")
        }
        """, kotlin: """
        try {
            action1()
            action2()
        } catch (error: S) {
            var error = error
            print("Caught error: ${error}")
        }
        """)
    }

    func testEnum() async throws {
        try await check(supportingSwift: """
        enum E: Error {
            case case1
            case case2
        }
        """, swift: """
        do {
            action1()
            action2()
        } catch E.case1 {
            print("case1")
        } catch E.case2 {
            print("case2")
        }
        """, kotlin: """
        try {
            action1()
            action2()
        } catch (error: E.Case1Case) {
            print("case1")
        } catch (error: E.Case2Case) {
            print("case2")
        }
        """)
    }

    func testAssociatedValueEnum() async throws {
        try await check(supportingSwift: """
        enum E: Error {
            case case1(Int)
            case case2(Int, String)
        }
        """, swift: """
        do {
            action1()
            action2()
        } catch E.case1(let code) {
            print("Caught error: \\(code)")
        } catch E.case2(_, var message) {
            print("Caught error: \\(message)")
        }
        """, kotlin: """
        try {
            action1()
            action2()
        } catch (error: E.Case1Case) {
            val code = error.associated0
            print("Caught error: ${code}")
        } catch (error: E.Case2Case) {
            var message = error.associated1
            print("Caught error: ${message}")
        }
        """)
    }

    func testMultipleMatches() async throws {
        try await check(supportingSwift: """
        struct S: Error {
        }
        enum E: Error {
            case case1(Int)
            case case2(Int, String)
        }
        """, swift: """
        do {
            action1()
            action2()
        } catch is S, E.case1 {
            print("Caught error")
        } catch let E.case2(code, message) {
            print("Caught error: \\(code): \\(message)")
        }
        """, kotlin: """
        try {
            action1()
            action2()
        } catch (error: S) {
            print("Caught error")
        } catch (error: E.Case1Case) {
            print("Caught error")
        } catch (error: E.Case2Case) {
            val code = error.associated0
            val message = error.associated1
            print("Caught error: ${code}: ${message}")
        }
        """)
    }

    func testCatchWithDefer() async throws {
        try await check(swift: """
        do {
            action1()
            defer { finalAction() }
            action2()
        } catch {
            print("Caught error: \\(error)")
        }
        """, kotlin: """
        var deferaction_0: (() -> Unit)? = null
        try {
            action1()
            deferaction_0 = {
                finalAction()
            }
            action2()
        } catch (error: Throwable) {
            @Suppress("NAME_SHADOWING") val error = error.aserror()
            print("Caught error: ${error}")
        } finally {
            deferaction_0?.invoke()
        }
        """)
    }

    func testMutatingFunctionCombinesTryCatch() async throws {
        try await check(swift: """
        struct S {
            var i = 0
            mutating func inc() {
                do {
                    i += 1
                } catch {
                    print("Caught error \\(error)")
                }
            }
            mutating func decinc() {
                i -= 1
                do {
                    i += 1
                } catch {
                    print("Caught error \\(error)")
                }
            }
        }
        """, kotlin: """
        internal class S: MutableStruct {
            internal var i: Int
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }
            internal fun inc() {
                willmutate()
                try {
                    i += 1
                } catch (error: Throwable) {
                    @Suppress("NAME_SHADOWING") val error = error.aserror()
                    print("Caught error ${error}")
                } finally {
                    didmutate()
                }
            }
            internal fun decinc() {
                willmutate()
                try {
                    i -= 1
                    try {
                        i += 1
                    } catch (error: Throwable) {
                        @Suppress("NAME_SHADOWING") val error = error.aserror()
                        print("Caught error ${error}")
                    }
                } finally {
                    didmutate()
                }
            }

            constructor(i: Int = 0) {
                this.i = i
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(i)
        }
        """)
    }

    func testErrorClass() async throws {
        try await check(swift: """
        class C: Error {
        }
        """, kotlin: """
        internal open class C: Exception(), Error {
        }
        """)

        try await check(swift: """
        class C: Error {
            var message = ""
        }
        """, kotlin: """
        internal open class C: Exception(), Error {
            override var message = ""
        }
        """)

        try await check(swift: """
        class C: Error {
            let i: Int

            init(param: Int) {
                self.i = param
            }
        }
        """, kotlin: """
        internal open class C: Exception, Error {
            internal val i: Int

            internal constructor(param: Int): super() {
                this.i = param
            }
        }
        """)
    }

    func testErrorStruct() async throws {
        try await check(swift: """
        struct S: Error {
        }
        """, kotlin: """
        internal class S: Exception(), Error {
        }
        """)

        try await check(swift: """
        struct S: Error {
            var message = ""
        }
        """, kotlin: """
        internal class S: Exception, Error, MutableStruct {
            override var message: String
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }

            constructor(message: String = ""): super() {
                this.message = message
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(message)
        }
        """)

        try await check(supportingSwift: """
        protocol Codable {}
        """, swift: """
        struct S: Error, Codable {
            let i: Int

            init(param: Int) {
                self.i = param
            }
        }
        """, kotlin: """
        internal class S: Exception, Error, Codable {
            internal val i: Int

            internal constructor(param: Int): super() {
                this.i = param
            }

            private enum class CodingKeys(override val rawValue: String, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): CodingKey, RawRepresentable<String> {
                i("i");
            }

            override fun encode(to: Encoder) {
                val container = to.container(keyedBy = CodingKeys::class)
                container.encode(i, forKey = CodingKeys.i)
            }

            constructor(from: Decoder): super() {
                val container = from.container(keyedBy = CodingKeys::class)
                this.i = container.decode(Int::class, forKey = CodingKeys.i)
            }

            companion object: DecodableCompanion<S> {
                override fun init(from: Decoder): S = S(from = from)

                private fun CodingKeys(rawValue: String): CodingKeys? {
                    return when (rawValue) {
                        "i" -> CodingKeys.i
                        else -> null
                    }
                }
            }
        }
        """)
    }

    func testErrorEnum() async throws {
        try await check(swift: """
        enum E: Error {
            case error1
            case error2
        }
        """, kotlin: """
        internal sealed class E: Exception(), Error {
            class Error1Case: E() {
                override fun equals(other: Any?): Boolean = other is Error1Case
                override fun hashCode(): Int = "Error1Case".hashCode()
            }
            class Error2Case: E() {
                override fun equals(other: Any?): Boolean = other is Error2Case
                override fun hashCode(): Int = "Error2Case".hashCode()
            }

            companion object {
                val error1: E
                    get() = Error1Case()
                val error2: E
                    get() = Error2Case()
            }
        }
        """)

        try await check(swift: """
        enum E: Int, Error {
            case error1 = 2
            case error2
        }
        """, kotlin: """
        internal sealed class E(override val rawValue: Int, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): Exception(), Error, RawRepresentable<Int> {
            class Error1Case: E(2) {
                override fun equals(other: Any?): Boolean = other is Error1Case
                override fun hashCode(): Int = "Error1Case".hashCode()
            }
            class Error2Case: E(3) {
                override fun equals(other: Any?): Boolean = other is Error2Case
                override fun hashCode(): Int = "Error2Case".hashCode()
            }

            companion object {
                val error1: E
                    get() = Error1Case()
                val error2: E
                    get() = Error2Case()
            }
        }

        internal fun E(rawValue: Int): E? {
            return when (rawValue) {
                2 -> E.error1
                3 -> E.error2
                else -> null
            }
        }
        """)
    }

    func testErrorEnumSynthesizedEqualsHash() async throws {
        try await check(swift: """
        enum E: Error, Hashable {
            case error1
            case error2
        }
        """, kotlin: """
        internal sealed class E: Exception(), Error {
            class Error1Case: E() {
                override fun equals(other: Any?): Boolean = other is Error1Case
                override fun hashCode(): Int = "Error1Case".hashCode()
            }
            class Error2Case: E() {
                override fun equals(other: Any?): Boolean = other is Error2Case
                override fun hashCode(): Int = "Error2Case".hashCode()
            }

            companion object {
                val error1: E
                    get() = Error1Case()
                val error2: E
                    get() = Error2Case()
            }
        }
        """)

        try await check(swift: """
        enum E: Int, Error, Hashable {
            case error1 = 2
            case error2
        }
        """, kotlin: """
        internal sealed class E(override val rawValue: Int, @Suppress("UNUSED_PARAMETER") unusedp: Nothing? = null): Exception(), Error, RawRepresentable<Int> {
            class Error1Case: E(2) {
                override fun equals(other: Any?): Boolean = other is Error1Case
                override fun hashCode(): Int = "Error1Case".hashCode()
            }
            class Error2Case: E(3) {
                override fun equals(other: Any?): Boolean = other is Error2Case
                override fun hashCode(): Int = "Error2Case".hashCode()
            }

            companion object {
                val error1: E
                    get() = Error1Case()
                val error2: E
                    get() = Error2Case()
            }
        }

        internal fun E(rawValue: Int): E? {
            return when (rawValue) {
                2 -> E.error1
                3 -> E.error2
                else -> null
            }
        }
        """)
    }

    func testThrowUnknownError() async throws {
        try await check(swift: """
        func throwit(error: Error) throws {
            throw error
        }
        """, kotlin: """
        internal fun throwit(error: Error) {
            throw error as Throwable
        }
        """)

        try await check(swift: """
        protocol MyError: Error {
        }
        func throwit(error: MyError) throws {
            throw error
        }
        """, kotlin: """
        internal interface MyError: Error {
        }
        internal fun throwit(error: MyError) {
            throw error as Throwable
        }
        """)
    }
}
