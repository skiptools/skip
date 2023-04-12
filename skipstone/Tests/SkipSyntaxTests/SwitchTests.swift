@testable import SkipSyntax
import XCTest

final class SwitchTests: XCTestCase {
    func testValues() async throws {
        try await check(swift: """
        let i = 100
        switch i {
        case 0:
            print(0)
        case 1:
            print(1)
        case 1 + 1:
            print(2)
        case f(i):
            print("f")
        default:
            print("default")
        }
        """, kotlin: """
        internal val i = 100
        when (i) {
            0 -> {
                print(0)
            }
            1 -> {
                print(1)
            }
            1 + 1 -> {
                print(2)
            }
            f(i) -> {
                print("f")
            }
            else -> {
                print("default")
            }
        }
        """)
    }

    func testMultipleValues() async throws {
        try await check(swift: """
        let i = 100
        switch i {
        case 0, 1, 2:
            print("<2")
        case 3
            print(3)
        default:
            print("default")
        }
        """, kotlin: """
        internal val i = 100
        when (i) {
            0, 1, 2 -> {
                print("<2")
            }
            3 -> {
                print(3)
            }
            else -> {
                print("default")
            }
        }
        """)
    }

    func testBreak() async throws {
        try await check(swift: """
        let i = 100
        switch i {
        case 0:
            if i % 2 == 0 {
                print("0 is even")
                break
            }
            print("0 is odd")
        default:
            break
        }
        print("here")
        """, kotlin: """
        internal val i = 100
        linvoke wlabel@{
            when (i) {
                0 -> {
                    if (i % 2 == 0) {
                        print("0 is even")
                        return@wlabel
                    }
                    print("0 is odd")
                }
                else -> {
                    return@wlabel
                }
            }
        }
        print("here")
        """)
    }

    func testEnum() async throws {
        try await check(supportingSwift: """
        enum E {
            case case1
            case case2
        }
        func enumFactory() -> E {
            return .case1
        }
        """, swift: """
        switch enumFactory() {
        case .case1
            print("1")
        case .case2
            print("2")
        }
        """, kotlin: """
        when (enumFactory()) {
            E.case1 -> {
                print("1")
            }
            E.case2 -> {
                print("2")
            }
        }
        """)
    }

    func testAssociatedValueEnum() async throws {
        let supportingSwift = """
        enum E {
            case case1(d: Double)
            case case2(Int, String)
        }
        func enumFactory() -> E {
            return .case1(d: 100.0)
        }
        extension Double {
            var zero: Double {
                return 0.0
            }
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        let e = enumFactory()
        switch e {
        case let .case1(d: dvalue):
            print(dvalue == .zero)
        case .case2(_, var s):
            s += "..."
            print(s)
        }
        """, kotlin: """
        internal val e = enumFactory()
        when (e) {
            is E.case1case -> {
                val dvalue = e.d
                print(dvalue == Double.zero)
            }
            is E.case2case -> {
                var s = e.associated1
                s += "..."
                print(s)
            }
        }
        """)

        // Extract switch value to avoid side effects from repeating it for bindings
        try await check(supportingSwift: supportingSwift, swift: """
        switch enumFactory() {
        case let .case1(d: dvalue):
            print(dvalue == .zero)
        case .case2(_, var s):
            s += "..."
            print(s)
        }
        """, kotlin: """
        val matchtarget_0 = enumFactory()
        when (matchtarget_0) {
            is E.case1case -> {
                val dvalue = matchtarget_0.d
                print(dvalue == Double.zero)
            }
            is E.case2case -> {
                var s = matchtarget_0.associated1
                s += "..."
                print(s)
            }
        }
        """)
    }

    func testGenericEnum() async throws {
        try await check(supportingSwift: """
        extension Double {
            var zero: Double {
                return 0.0
            }
        }
        """, swift: """
        enum E<T> {
            case case1
            case case2(T, String)
        }
        func enumFactory() -> E<Double> {
            return .case2(100.0, "abc")
        }
        func g() {
            let e = enumFactory()
            switch e {
            case E<Double>.case1:
                print("case1")
            case .case2(let d, var s):
                let b = d == .zero
                s += "..."
                print(s + b)
            }
        }
        """, kotlin: """
        internal sealed class E<out T> where T: Any {
            class case1case: E<Nothing>() {
            }
            class case2case<T>(val associated0: T, val associated1: String): E<T>() where T: Any {
            }

            companion object {
                val case1: E<Nothing> = case1case()
                fun <T> case2(associated0: T, associated1: String): E<T> where T: Any {
                    return case2case(associated0, associated1)
                }
            }
        }
        internal fun enumFactory(): E<Double> {
            return E.case2(100.0, "abc")
        }
        internal fun g() {
            val e = enumFactory()
            when (e) {
                is E.case1case -> {
                    print("case1")
                }
                is E.case2case -> {
                    val d = e.associated0
                    var s = e.associated1
                    val b = d == Double.zero
                    s += "..."
                    print(s + b)
                }
            }
        }
        """)
    }

    func testRange() async throws {
        try await check(swift: """
        let i = 100
        switch i {
        case ..<0:
            print(-1)
        case 0..<10:
            print(0)
        case 10...20:
            print(1)
        case 21...:
            print(21)
        default:
            print("default")
        }
        """, kotlin: """
        internal val i = 100
        when (i) {
            in Int.min until 0 -> {
                print(-1)
            }
            in 0 until 10 -> {
                print(0)
            }
            in 10 .. 20 -> {
                print(1)
            }
            in 21 .. Int.max -> {
                print(21)
            }
            else -> {
                print("default")
            }
        }
        """)
    }

    func testIs() async throws {
        try await check(swift: """
        {
            let a: Any
            switch a {
            case is Int:
                print("Int")
            case is Double:
                print("Double")
            default:
                print("default")
            }
        }
        """, kotlin: """
        {
            val a: Any
            when (a) {
                is Int -> {
                    print("Int")
                }
                is Double -> {
                    print("Double")
                }
                else -> {
                    print("default")
                }
            }
        }
        """)
    }

    func testAsBinding() async throws {
        try await check(swift: """
        {
            let a: Any
            switch a {
            case let i as Int:
                print(i)
            case let d as Double:
                print(d)
            case let s as SomeStruct:
                print(s)
            default:
                print("default")
            }
        }
        """, kotlin: """
        {
            val a: Any
            when (a) {
                is Int -> {
                    val i = a
                    print(i)
                }
                is Double -> {
                    val d = a
                    print(d)
                }
                is SomeStruct -> {
                    val s = a.sref()
                    print(s.sref())
                }
                else -> {
                    print("default")
                }
            }
        }
        """)
    }

    func testLetBinding() async throws {
        try await check(swift: """
        let i: Int
        switch i {
        case 0:
            print(0)
        case let x:
            print(x)
        }
        """, kotlin: """
        internal val i: Int
        when (i) {
            0 -> {
                print(0)
            }
            else -> {
                val x = i
                print(x)
            }
        }
        """)

        try await check(swift: """
        let i: Int
        switch i {
        case 0:
            print(0)
        case _:
            print("default")
        }
        """, kotlin: """
        internal val i: Int
        when (i) {
            0 -> {
                print(0)
            }
            else -> {
                print("default")
            }
        }
        """)

        try await check(swift: """
        let t = (1, "s")
        switch t {
        case (0, ""):
            print(0)
        case let (i, s):
            print(i)
            print(s)
        }
        """, kotlin: """
        internal val t = Pair(1, "s")
        when (t) {
            Pair(0, "") -> {
                print(0)
            }
            else -> {
                val i = t.first
                val s = t.second
                print(i)
                print(s)
            }
        }
        """)

        try await check(swift: """
        let t = (1, "s")
        switch t {
        case (0, ""):
            print(0)
        case (var i, let s):
            i += 1
            print(i)
            print(s)
        }
        """, kotlin: """
        internal val t = Pair(1, "s")
        when (t) {
            Pair(0, "") -> {
                print(0)
            }
            else -> {
                var i = t.first
                val s = t.second
                i += 1
                print(i)
                print(s)
            }
        }
        """)

        try await check(swift: """
        let t = (1, "s")
        switch t {
        case (0, ""):
            print(0)
        case var (i, _):
            i += 1
            print(i)
        }
        """, kotlin: """
        internal val t = Pair(1, "s")
        when (t) {
            Pair(0, "") -> {
                print(0)
            }
            else -> {
                var i = t.first
                i += 1
                print(i)
            }
        }
        """)
    }

    func testPartialBinding() async throws {
        // Note: we don't support this for the same reason we don't support 'where' clauses in case statements:
        // we'd have to match the general case and then use an 'if' in the case body, but that could prevent a
        // subsequent case that would have matched from being executed
        try await checkProducesMessage(swift: """
        let t = (1, "s")
        switch t {
        case (0, "s"):
            print(0)
        case (let i, "s"):
            print(i)
        default:
            print("default")
        }
        """)
    }

    func testOptionals() async throws {
        try await check(swift: """
        let i: Int? = nil
        switch i {
        case nil:
            print("nil")
        case 1:
            print(1)
        default:
            print("default")
        }
        """, kotlin: """
        internal val i: Int? = null
        when (i) {
            null -> {
                print("nil")
            }
            1 -> {
                print(1)
            }
            else -> {
                print("default")
            }
        }
        """)
    }

    func testOptionalBindings() async throws {
        try await check(swift: """
        var i: Int?
        switch i {
        case nil:
            print("nil")
        case 1?:
            print(1)
        case var x?:
            x += 1
            print(x)
        default:
            print("default")
        }
        """, kotlin: """
        internal var i: Int? = null
        when {
            i == null -> {
                print("nil")
            }
            i == 1 -> {
                print(1)
            }
            i != null -> {
                var x = i
                x += 1
                print(x)
            }
            else -> {
                print("default")
            }
        }
        """)
    }
}
