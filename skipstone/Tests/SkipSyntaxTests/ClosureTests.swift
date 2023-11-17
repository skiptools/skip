import XCTest

final class ClosureTests: XCTestCase {
    func testNoParameters() async throws {
        try await check(swift: """
        call {
            print("f")
        }
        """, kotlin: """
        call { print("f") }
        """)

        try await check(swift: """
        call(100) {
            print("f")
        }
        """, kotlin: """
        call(100) { print("f") }
        """)

        try await check(swift: """
        call(100, { print("f") })
        """, kotlin: """
        call(100, { print("f") })
        """)
    }

    func testExplicitSingleParameter() async throws {
        try await check(swift: """
        call { x in
            print(x)
        }
        """, kotlin: """
        call { x -> print(x) }
        """)

        try await check(swift: """
        call { (x: Int) in
            print(x)
        }
        """, kotlin: """
        call { x: Int -> print(x) }
        """)
    }

    func testExplicitMultipleParameters() async throws {
        try await check(swift: """
        call { x, y in
            print(x)
        }
        """, kotlin: """
        call { x, y -> print(x) }
        """)

        try await check(swift: """
        call { (x: Int, y: String) in
            print(x)
        }
        """, kotlin: """
        call { x: Int, y: String -> print(x) }
        """)
    }

    func testExplicitReturnType() async throws {
        // Without explicit return
        try await check(swift: """
        call { (x: Int, y: String) -> Int in
            1
        }
        """, kotlin: """
        call(fun(x: Int, y: String): Int = 1)
        """)

        // With explicit return
        try await check(swift: """
        call { (x: Int, y: String) -> Int in
            return 1
        }
        """, kotlin: """
        call(fun(x: Int, y: String): Int = 1)
        """)
    }

    func testReturnLabel() async throws {
        try await check(swift: """
        call { _ in
            return 1
        }
        """, kotlin: """
        call l@{ _ -> return@l 1 }
        """)
    }

    func testImmediatelyExecuted() async throws {
        try await check(swift: """
        {
            let x = { 1 }()
        }
        """, kotlin: """
        {
            val x = { 1 }()
        }
        """)

        try await check(swift: """
        {
            let x = { (i: Int) in i }(1)
        }
        """, kotlin: """
        {
            val x = { i: Int -> i }(1)
        }
        """)

        try await check(swift: """
        {
            let x = {
                if $0 % 2 == 0 {
                    return "YES"
                } else {
                    return "NO"
                }
            }(1)
        }
        """, kotlin: """
        {
            val x = linvoke(1) l@{ it ->
                if (it % 2 == 0) {
                    return@l "YES"
                } else {
                    return@l "NO"
                }
            }
        }
        """)
    }

    func testImplicitSingleParameter() async throws {
        try await check(swift: """
        call { $0 + 1 }
        """, kotlin: """
        call { it -> it + 1 }
        """)
    }

    func testImplicitMultipleParameters() async throws {
        try await check(swift: """
        call { $0 + $1 + $2 }
        """, kotlin: """
        call { it, it_1, it_2 -> it + it_1 + it_2 }
        """)
    }

    func testUseInvokeForOptionalClosure() async throws {
        try await check(swift: """
        {
            let c: ((String) -> Int)? = nil
            let i = c?("s")
        }
        """, kotlin: """
        {
            val c: ((String) -> Int)? = null
            val i = c?.invoke("s")
        }
        """)

        try await check(swift: """
        {
            let c: ((String) -> Int)? = nil
            if let c {
                let i = c("s")
            }
        }
        """, kotlin: """
        {
            val c: ((String) -> Int)? = null
            if (c != null) {
                val i = c("s")
            }
        }
        """)

        // The simple != null trick doesn't work with member closures
        try await check(swift: """
        class C {
            var varc: ((String) -> Int)? = nil
            let valc: ((String) -> Int)? = nil

            func f() {
                if let varc {
                    let i = varc("s")
                }
                if let valc {
                    let i = valc("s")
                }
            }

            func g() {
                if let varc {
                    let i = varc("s")
                } else {
                    print("else")
                }
                if let valc {
                    let i = valc("s")
                } else {
                    print("else")
                }
            }
        }
        """, kotlin: """
        internal open class C {
            internal open var varc: ((String) -> Int)? = null
            internal val valc: ((String) -> Int)? = null

            internal open fun f() {
                varc?.let { varc ->
                    val i = varc("s")
                }
                valc?.let { valc ->
                    val i = valc("s")
                }
            }

            internal open fun g() {
                val matchtarget_0 = varc
                if (matchtarget_0 != null) {
                    val varc = matchtarget_0
                    val i = varc("s")
                } else {
                    print("else")
                }
                val matchtarget_1 = valc
                if (matchtarget_1 != null) {
                    val valc = matchtarget_1
                    val i = valc("s")
                } else {
                    print("else")
                }
            }
        }
        """)
    }

    func testPassFunctionForClosure() async throws {
        try await check(swift: """
        class C {
            func visitor(i: Int) {
            }

            func visit(with: (Int) -> Void) {
            }

            func f() {
                visit(with: self.visitor)
            }

            func g() {
                visit(with: visitor)
            }
        }
        """, kotlin: """
        internal open class C {
            internal open fun visitor(i: Int) = Unit

            internal open fun visit(with: (Int) -> Unit) = Unit

            internal open fun f(): Unit = visit(with = this::visitor)

            internal open fun g(): Unit = visit(with = ::visitor)
        }
        """)
    }

    func testCaptureList() async throws {
        try await check(swift: """
        class C {
            func f() {
                let c = { [weak self] in
                    if let strongSelf = self {
                        strongSelf.g()
                    }
                }
            }
            func g() {}
        }
        """, kotlin: """
        internal open class C {
            internal open fun f() {
                val c = {
                    this?.let { strongSelf ->
                        strongSelf.g()
                    }
                }
            }
            internal open fun g() = Unit
        }
        """)
        
        try await check(swift: """
        class C {
            func f() {
                let o = C()
                let c = { [weak weakSelf = self, unowned weakO = o] in
                    if let strongSelf = weakSelf, let o = weakO {
                        strongSelf.g(c: o)
                    }
                }
            }
            func g(c: C) {}
        }
        """, kotlin: """
        internal open class C {
            internal open fun f() {
                val o = C()
                val c = {
                    val weakSelf = this
                    val weakO = o
                    weakSelf?.let { strongSelf ->
                        weakO?.let { o ->
                            strongSelf.g(c = o)
                        }
                    }
                }
            }
            internal open fun g(c: C) = Unit
        }
        """)

        try await checkProducesMessage(swift: """
        class C {
            func f() {
                let c = { [weak weakSelf = self] in
                    if let self = weakSelf {
                    }
                }
            }
        }
        """)

        try await checkProducesMessage(swift: """
        class C {
            func f() {
                let c = { [weak weakSelf = self] in
                    guard let self = weakSelf else {
                        return
                    }
                }
            }
        }
        """)

        try await check(swift: """
        class C {
            func f() {
                let c = { [weak self] in
                    guard let self else {
                        return
                    }
                    self.g()
                }
            }
            func g() {}
        }
        """, kotlin: """
        internal open class C {
            internal open fun f() {
                val c = l@{
                    if (this == null) {
                        return@l
                    }
                    this.g()
                }
            }
            internal open fun g() = Unit
        }
        """)

        try await check(swift: """
        class C {
            func f() {
                let c = { [weak self] in
                    if let self {
                        self.g()
                    }
                }
            }
            func g() {}
        }
        """, kotlin: """
        internal open class C {
            internal open fun f() {
                val c = {
                    if (this != null) {
                        this.g()
                    }
                }
            }
            internal open fun g() = Unit
        }
        """)
    }

    func testInOut() async throws {
        try await check(swift: """
        let c: (inout Int) -> Void = { $0 += 1 }
        """, kotlin: """
        internal val c: (InOut<Int>) -> Unit = { it -> it.value += 1 }
        """)

        try await check(swift: """
        struct S {
            let i: Int
            let c: (inout Int) -> Void
        }
        func f(s: S) -> S {
            return S(i: 1) { $0 += 1 }
        }
        """, kotlin: """
        internal class S {
            internal val i: Int
            internal val c: (InOut<Int>) -> Unit

            constructor(i: Int, c: (InOut<Int>) -> Unit) {
                this.i = i
                this.c = c
            }
        }
        internal fun f(s: S): S {
            return S(i = 1) { it -> it.value += 1 }
        }
        """)
    }

    func testSwiftUIBinding() async throws {
        try await check(swift: """
        List($items, id: \\.i) { $item in
            Text(item.s)
        }
        """, kotlin: """
        List(Binding({ _items.wrappedValue }, { it -> _items.wrappedValue = it }), id = { it.i }) { item -> Text(item.wrappedValue.s) }
        """)

        try await check(swift: """
        List($items, id: \\.i) { $item in
            Toggle(item.$value)
            Toggle($item.value)
            CustomView($item)
        }
        """, kotlin: """
        List(Binding({ _items.wrappedValue }, { it -> _items.wrappedValue = it }), id = { it.i }) { item ->
            Toggle(Binding({ item.wrappedValue._value.wrappedValue }, { it -> item.wrappedValue._value.wrappedValue = it }))
            Toggle(Binding.fromBinding(item, { it.value }, { it, newvalue -> it.value = newvalue }))
            CustomView(item)
        }
        """)
    }

    func testModifierCallFormatting() async throws {
        try await check(swift: """
        Base()
            .trailing {
                Base()
                    .trailing()
            }
            .trailing()
        """, kotlin: """
        Base()
            .trailing {
                Base()
                    .trailing()
            }
            .trailing()
        """)

        try await check(swift: """
        Base {
            Inner().trailing {
                X()
                Y()
            }
            .trailing()
        }
        .trailing()
        .trailing()
        """, kotlin: """
        Base {
            Inner().trailing {
                X()
                Y()
            }
            .trailing()
        }
        .trailing()
        .trailing()
        """)
    }
}
