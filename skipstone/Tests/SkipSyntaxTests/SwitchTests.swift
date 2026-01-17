// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

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
            0 -> print(0)
            1 -> print(1)
            1 + 1 -> print(2)
            f(i) -> print("f")
            else -> print("default")
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
            0, 1, 2 -> print("<2")
            3 -> print(3)
            else -> print("default")
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
        for (unusedi in 0..0) {
            when (i) {
                0 -> {
                    if (i % 2 == 0) {
                        print("0 is even")
                        break
                    }
                    print("0 is odd")
                }
                else -> break
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
            E.case1 -> print("1")
            E.case2 -> print("2")
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
            is E.Case1Case -> {
                val dvalue = e.d
                print(dvalue == Double.zero)
            }
            is E.Case2Case -> {
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
            is E.Case1Case -> {
                val dvalue = matchtarget_0.d
                print(dvalue == Double.zero)
            }
            is E.Case2Case -> {
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
        internal sealed class E<out T> {
            class Case1Case: E<Nothing>() {
            }
            class Case2Case<T>(val associated0: T, val associated1: String): E<T>() {
            }

            companion object {
                val case1: E<Nothing> = Case1Case()
                fun <T> case2(associated0: T, associated1: String): E<T> = Case2Case(associated0, associated1)
            }
        }
        internal fun enumFactory(): E<Double> = E.case2(100.0, "abc")
        internal fun g() {
            val e = enumFactory()
            when (e) {
                is E.Case1Case -> print("case1")
                is E.Case2Case -> {
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
            in Int.min..<0 -> print(-1)
            in 0..<10 -> print(0)
            in 10..20 -> print(1)
            in 21..Int.max -> print(21)
            else -> print("default")
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
        { ->
            val a: Any
            when (a) {
                is Int -> print("Int")
                is Double -> print("Double")
                else -> print("default")
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
        { ->
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
                    print(s)
                }
                else -> print("default")
            }
        }
        """)
    }

    func testIsAsBindingToTypeErased() async throws {
        try await check(swift: """
        {
            let a: Any
            switch a {
            case is Array<Any>:
                print("Array")
            default:
                print("default")
            }
        }
        """, kotlin: """
        import skip.lib.Array

        { ->
            val a: Any
            when (a) {
                is Array<*> -> print("Array")
                else -> print("default")
            }
        }
        """)

        try await check(swift: """
        {
            let a: Any
            switch a {
            case let arr as Array<Any>:
                print("Array")
            default:
                print("default")
            }
        }
        """, kotlin: """
        import skip.lib.Array

        { ->
            val a: Any
            when (a) {
                is Array<*> -> {
                    val arr = a.sref()
                    print("Array")
                }
                else -> print("default")
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
            0 -> print(0)
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
            0 -> print(0)
            else -> print("default")
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
        internal val t = Tuple2(1, "s")
        when (t) {
            Tuple2(0, "") -> print(0)
            else -> {
                val i = t.element0
                val s = t.element1
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
        internal val t = Tuple2(1, "s")
        when (t) {
            Tuple2(0, "") -> print(0)
            else -> {
                var i = t.element0
                val s = t.element1
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
        internal val t = Tuple2(1, "s")
        when (t) {
            Tuple2(0, "") -> print(0)
            else -> {
                var i = t.element0
                i += 1
                print(i)
            }
        }
        """)
    }

    func testLetBindingTypeInference() async throws {
        try await check(supportingSwift: """
        extension Int {
            static let min = 0
        }
        enum E {
            case i(Int)
        }
        """, swift: """
        func f(e: E) {
            switch e {
            case let .i(value):
                let b = value == .min
            }
        }
        """, kotlin: """
        internal fun f(e: E) {
            when (e) {
                is E.ICase -> {
                    val value = e.associated0
                    val b = value == Int.min
                }
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
            null -> print("nil")
            1 -> print(1)
            else -> print("default")
        }
        """)

        try await checkProducesMessage(swift: """
        func f() {
            let dict = ["a": 1, "b": 2]
            switch dict["a"] {
            case 1:
                print(1)
            case .none:
                print("nil")
            default:
                print("other")
            }
        }
        """)

        try await check(swift: """
        func f() {
            let dict = ["a": 1, "b": 2]
            switch dict["a"] {
            case 1:
                print(1)
            case nil:
                print("nil")
            default:
                print("other")
            }
        }
        """, kotlin: """
        internal fun f() {
            val dict = dictionaryOf(Tuple2("a", 1), Tuple2("b", 2))
            when (dict["a"]) {
                1 -> print(1)
                null -> print("nil")
                else -> print("other")
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
            i == null -> print("nil")
            i == 1 -> print(1)
            i != null -> {
                var x = i
                x += 1
                print(x)
            }
            else -> print("default")
        }
        """)
    }

    func testGuardIntroducedMatchTarget() async throws {
        try await check(swift: """
        func f(_ object: Any?) {
            guard let obj = object else {
                return
            }
            switch (obj) {
            case let str as String:
                print(str)
            default:
                print("?")
            }
        }
        """, kotlin: """
        internal fun f(object_: Any?) {
            val obj_0 = object_.sref()
            if (obj_0 == null) {
                return
            }
            val matchtarget_0 = (obj_0)
            when (matchtarget_0) {
                is String -> {
                    val str = matchtarget_0
                    print(str)
                }
                else -> print("?")
            }
        }
        """)
    }

    func testSwitchAsAssignmentExpression() async throws {
        try await check(swift: """
        func f(i: Int) {
            let i = switch i {
            case ...0: -1
            default: 100
            }
        }
        """, kotlin: """
        internal fun f(i: Int) {
            val i = when (i) {
                in Int.min..0 -> -1
                else -> 100
            }
        }
        """)

        try await check(swift: """
        func f() {
            let i = switch g() {
            case let x as Int: x
            default: 100
            }
        }
        """, kotlin: """
        internal fun f() {
            val i = linvoke l@{
                val matchtarget_0 = g()
                when (matchtarget_0) {
                    is Int -> {
                        val x = matchtarget_0
                        return@l x
                    }
                    else -> return@l 100
                }
            }
        }
        """)
    }

    func testSwitchAsReturnExpression() async throws {
        try await check(swift: """
        func f(i: Int) -> Int {
            return switch i {
            case ...0: -1
            default: 100
            }
        }
        func g(i: Int) -> Int {
            switch i {
            case ...0: -1
            default: 100
            }
        }
        """, kotlin: """
        internal fun f(i: Int): Int {
            return when (i) {
                in Int.min..0 -> -1
                else -> 100
            }
        }
        internal fun g(i: Int): Int {
            return when (i) {
                in Int.min..0 -> -1
                else -> 100
            }
        }
        """)

        try await check(swift: """
        func f() -> Int {
            return switch g() {
            case let x as Int: x
            default: 100
            }
        }
        func g() -> Int {
            return switch g() {
            case let x as Int: x
            default: 100
            }
        }
        """, kotlin: """
        internal fun f(): Int {
            return linvoke l@{
                val matchtarget_0 = g()
                when (matchtarget_0) {
                    is Int -> {
                        val x = matchtarget_0
                        return@l x
                    }
                    else -> return@l 100
                }
            }
        }
        internal fun g(): Int {
            return linvoke l@{
                val matchtarget_1 = g()
                when (matchtarget_1) {
                    is Int -> {
                        val x = matchtarget_1
                        return@l x
                    }
                    else -> return@l 100
                }
            }
        }
        """)
    }

    func testSwitchAsClosureReturnExpression() async throws {
        // We have no reliable way to detect using 'switch' as an implicit return value vs. a statement in a closure
        try await check(expectFailure: true, swift: """
        func f(i: Int) {
            let c = {
                switch g() {
                case let x as Int: print(x)
                default: print(100)
            }
        }
        """, kotlin: """
        internal fun f(i: Int) {
            val c = {
                val matchtarget_1 = g()
                when (matchtarget_1) {
                    is Int -> {
                        val x = matchtarget_1
                        print(x)
                    }
                    else -> print(100)
                }
            }
        }
        """)

        // We have no reliable way to detect using 'switch' as an implicit return value vs. a statement in a closure
        try await check(expectFailure: true, swift: """
        func f(i: Int) {
            let c = {
                switch g() {
                case let x as Int: x
                default: 100
            }
        }
        """, kotlin: """
        internal fun f(i: Int) {
            val c = l@{
                val matchtarget_0 = g()
                when (matchtarget_0) {
                    is Int -> {
                        val x = matchtarget_0
                        return@l x
                    }
                    else -> return@l 100
                }
            }
        }
        """)

        try await check(expectFailure: true, swift: """
        func f(i: Int) {
            let c: () -> Int = {
                switch g() {
                case let x as Int: x
                default: 100
            }
        }
        """, kotlin: """
        internal fun f(i: Int) {
            val c: () -> Int = l@{
                val matchtarget_0 = g()
                when (matchtarget_0) {
                    is Int -> {
                        val x = matchtarget_0
                        return@l x
                    }
                    else -> return@l 100
                }
            }
        }
        """)

        try await check(swift: """
        func f(i: Int) {
            let c1 = {
                switch g() {
                case let x as Int: return x
                default: return 100
            }
        }
        """, kotlin: """
        internal fun f(i: Int) {
            val c1 = l@{ ->
                val matchtarget_0 = g()
                when (matchtarget_0) {
                    is Int -> {
                        val x = matchtarget_0
                        return@l x
                    }
                    else -> return@l 100
                }
            }
        }
        """)
    }

    func testNestedAsExpression() async throws {
        try await check(swift: """
        func f(i: Int) -> Int {
            return switch i {
            case ...0:
            switch i {
                case -1: 1
                default: -1
            }
            default: 100
            }
        }
        """, kotlin: """
        internal fun f(i: Int): Int {
            return when (i) {
                in Int.min..0 -> {
                    when (i) {
                        -1 -> 1
                        else -> -1
                    }
                }
                else -> 100
            }
        }
        """)

        try await check(swift: """
        func f(i: Int) -> Int {
            switch g() {
            case let x as Int: switch x {
                case ...0: -1
                default: x
            }
            default: 100
            }
        }
        """, kotlin: """
        internal fun f(i: Int): Int {
            return linvoke l@{
                val matchtarget_0 = g()
                when (matchtarget_0) {
                    is Int -> {
                        val x = matchtarget_0
                        when (x) {
                            in Int.min..0 -> return@l -1
                            else -> return@l x
                        }
                    }
                    else -> return@l 100
                }
            }
        }
        """)

        try await check(swift: """
        func f(i: Int) -> Int {
            switch g() {
            case let x as Int: switch g(x) {
                case let y as Double: 0.0
                default: x
            }
            default: 100
            }
        }
        """, kotlin: """
        internal fun f(i: Int): Int {
            return linvoke l@{
                val matchtarget_0 = g()
                when (matchtarget_0) {
                    is Int -> {
                        val x = matchtarget_0
                        val matchtarget_1 = g(x)
                        when (matchtarget_1) {
                            is Double -> {
                                val y = matchtarget_1
                                return@l 0.0
                            }
                            else -> return@l x
                        }
                    }
                    else -> return@l 100
                }
            }
        }
        """)
    }
}
