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
        try await check(symbols: symbols, swift: """
        switch switchTestsEnumFactory() {
        case .case1
            print("1")
        case .case2
            print("2")
        }
        """, kotlin: """
        when (switchTestsEnumFactory()) {
            SwitchTestsEnum.case1 -> {
                print("1")
            }
            SwitchTestsEnum.case2 -> {
                print("2")
            }
        }
        """)
    }

    func testAssociatedValueEnum() async throws {
        try await check(symbols: symbols, swift: """
        let e = switchTestsAssociatedValueEnumFactory()
        switch e {
        case let .case1(d: dvalue):
            print(dvalue == .zero)
        case .case2(_, var s):
            s += "..."
            print(s)
        }
        """, kotlin: """
        internal val e = switchTestsAssociatedValueEnumFactory()
        when (e) {
            is SwitchTestsAssociatedValueEnum.case1 -> {
                val dvalue = e.d
                print(dvalue == Double.zero)
            }
            is SwitchTestsAssociatedValueEnum.case2 -> {
                var s = e.associated1
                s += "..."
                print(s)
            }
        }
        """)

        // Extract switch value to avoid side effects from repeating it for bindings
        try await check(symbols: symbols, swift: """
        switch switchTestsAssociatedValueEnumFactory() {
        case let .case1(d: dvalue):
            print(dvalue == .zero)
        case .case2(_, var s):
            s += "..."
            print(s)
        }
        """, kotlin: """
        val matchtarget_0 = switchTestsAssociatedValueEnumFactory()
        when (matchtarget_0) {
            is SwitchTestsAssociatedValueEnum.case1 -> {
                val dvalue = matchtarget_0.d
                print(dvalue == Double.zero)
            }
            is SwitchTestsAssociatedValueEnum.case2 -> {
                var s = matchtarget_0.associated1
                s += "..."
                print(s)
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
        // by matching the general case and then using an 'if' in the case body, we could prevent a subsequent case
        // that would have matched from being executed
        try await check(expectFailure: true, swift: """
        let t = (1, "s")
        switch t {
        case (0, "s"):
            print(0)
        case (let i, "s"):
            print(i)
        default:
            print("default")
        }
        """, kotlin: """
        internal val t = Pair(1, "s")
        when (t) {
            Pair(0, "") -> {
                print(0)
            }
            else -> {
                if (t.second = "s") {
                    val i = t.first
                    print(i)
                }
            }
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

private enum SwitchTestsEnum {
    case case1
    case case2
}
private enum SwitchTestsAssociatedValueEnum {
    case case1(d: Double)
    case case2(Int, String)
}
private func switchTestsEnumFactory() -> SwitchTestsEnum {
    return .case1
}
private func switchTestsAssociatedValueEnumFactory() -> SwitchTestsAssociatedValueEnum {
    return .case1(d: 100.0)
}

private extension Double {
    var zero: Double {
        return 0.0
    }
}
