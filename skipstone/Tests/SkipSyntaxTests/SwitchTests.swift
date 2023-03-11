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
