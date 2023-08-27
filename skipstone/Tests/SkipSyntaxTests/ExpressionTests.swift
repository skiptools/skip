import XCTest

final class ExpressionTests: XCTestCase {
    func testSelf() async throws {
        try await check(swift: """
        class C {
            static func staticf() -> Int {
                return 10
            }
        
            func f() -> Int {
                return Self.staticf()
            }
        }
        """, kotlin: """
        internal open class C {
        
            internal open fun f(): Int = Companion.staticf()

            companion object {
                internal fun staticf(): Int = 10
            }
        }
        """)

        try await check(swift: """
        class C {
            func instancef() -> Int {
                return 10
            }

            func f() -> Int {
                return self.instancef()
            }
        }
        """, kotlin: """
        internal open class C {
            internal open fun instancef(): Int = 10

            internal open fun f(): Int = this.instancef()
        }
        """)
    }

    func testWildcardVariable() async throws {
        try await check(swift: """
        func f() -> Int {
            let _ = f()
            _ = f()
        }
        """, kotlin: """
        internal fun f(): Int {
            f()
            f()
        }
        """)
    }

    func testOptionalSomeNone() async throws {
        try await checkProducesMessage(swift: """
        let i: Int? = nil
        switch i {
        case .none:
            print("nil")
        case .some(1):
            print(1)
        case .some(var x):
            x += 1
            print(x)
        }
        """)
    }

    func testStaticMemberUsingClassReference() async throws {
        try await check(swift: """
        class C {
            static let typeVar = C.self

            static func staticFunc() {
            }
        }
        typealias X = C

        func f() {
            g(c: C.self)
            g(c: C.typeVar)
            C.staticFunc()
            X.staticFunc()
            C.typeVar.staticFunc()
        }

        func g(c: C.Type) {
        }
        """, kotlin: """
        import kotlin.reflect.KClass
        import kotlin.reflect.full.companionObjectInstance

        internal open class C {

            companion object {
                internal val typeVar = C::class

                internal fun staticFunc() = Unit
            }
        }
        internal typealias X = C

        internal fun f() {
            g(c = C::class)
            g(c = C.typeVar)
            C.staticFunc()
            C.staticFunc()
            (C.typeVar.companionObjectInstance as C.Companion).staticFunc()
        }

        internal fun g(c: KClass<C>) = Unit
        """)

        try await check(compiler: nil, swiftCode: {
            class Foo {
                class Bar {
                    class Baz {
                        static let prop = "ABC"
                    }
                }
            }
            return Foo.Bar.Baz.prop
        }, kotlin: """
        open class Foo {
            open class Bar {
                open class Baz {

                    companion object {
                        val prop = "ABC"
                    }
                }
            }
        }
        return Foo.Bar.Baz.prop
        """)

        // Test nested type that is not fully qualified
        try await check(swift: """
        class A {
            class B {
                class C {
                    static var a = 100
                }
            }
            func f() {
                let x = B.C.a
            }
        }
        """, kotlin: """
        internal open class A {
            internal open class B {
                internal open class C {

                    companion object {
                        internal var a = 100
                    }
                }
            }
            internal open fun f() {
                val x = B.C.a
            }
        }
        """)
    }

    func testSelfAssignMutatingFunction() async throws {
        try await check(swift: """
        struct S {
            let i: Int
            var a: [String] = [] {
                didSet {
                    print("didset")
                }
            }

            init(i: Int) {
                self.i = i
            }

            mutating func copy(_ copy: S) {
                self = copy
            }
        }
        """, kotlin: """
        import skip.lib.Array

        internal class S: MutableStruct {
            internal var i: Int
            internal var a: Array<String> = arrayOf()
                get() = field.sref({ this.a = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                    willmutate()
                    try {
                        field = newValue
                        if (!suppresssideeffects) {
                            print("didset")
                        }
                    } finally {
                        didmutate()
                    }
                }

            internal constructor(i: Int) {
                suppresssideeffects = true
                try {
                    this.i = i
                } finally {
                    suppresssideeffects = false
                }
            }

            internal fun copy(copy: S) {
                willmutate()
                try {
                    assignfrom(copy)
                } finally {
                    didmutate()
                }
            }

            private constructor(copy: MutableStruct) {
                suppresssideeffects = true
                try {
                    @Suppress("NAME_SHADOWING") val copy = copy as S
                    this.i = copy.i
                    this.a = copy.a
                } finally {
                    suppresssideeffects = false
                }
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(this as MutableStruct)

            private fun assignfrom(target: S) {
                suppresssideeffects = true
                try {
                    this.i = target.i
                    this.a = target.a
                } finally {
                    suppresssideeffects = false
                }
            }

            private var suppresssideeffects = false
        }
        """)
    }

    func testOperatorAsParameter() async throws {
        try await check(supportingSwift: """
        func perform(on: Int, operation: (Int, Int) -> Int) -> Int {
            return operation(on, on)
        }
        """, swift: """
        perform(on: 10, +)
        """, kotlin: """
        perform(on = 10, { it, it_1 -> it + it_1 })
        """)
    }

    func testReduceParameterLabel() async throws {
        try await check(swift: """
        {
            let arr = [1, 2, 3]
            let result = arr.reduce(0, +)
        }
        """, kotlin: """
        import skip.lib.Array
        
        {
            val arr = arrayOf(1, 2, 3)
            val result = arr.reduce(initialResult = 0, { it, it_1 -> it + it_1 })
        }
        """)
    }

    func testKeyPaths() async throws {
        try await check(supportingSwift: """
        class A {
            var b = B()
            var ob: B?
        }
        class B {
            var x = 1
        }
        """, swift: """
        func f(a: [A]) -> [Int] {
            return a.map(\\.b.x)
        }
        func g(a: [A]) -> [Int?] {
            return a.map(\\.self.ob?.x)
        }
        """, kotlin: """
        import skip.lib.Array

        internal fun f(a: Array<A>): Array<Int> = a.map({ it.b.x })
        internal fun g(a: Array<A>): Array<Int?> = a.map({ it.ob?.x })
        """)

        try await check(supportingSwift: """
        extension Int {
            static let zero = 0
        }
        extension String {
            var count: Int {
            }
            func map<T>(_ operation: (String) -> T) -> T {
            }
        }
        """, swift: """
        func f(s: String) {
            let b = s.map(\\.count) == .zero
        }
        """, kotlin: """
        internal fun f(s: String) {
            val b = s.map({ it.count }) == Int.zero
        }
        """)

        try await checkProducesMessage(swift: """
        func f(a: [A]) -> [Int] {
            return a.map(\\.arr[0])
        }
        """)

        try await checkProducesMessage(swift: """
        struct S {
            let i = 0
        }
        func get(keyPath: KeyPath<S, Int>, from: S) -> Int {
        }
        """)

        try await checkProducesMessage(swift: """
        func f() {
            let s = S()
            let i = s[keyPath: \\.i]
        }
        """)
    }

    func testOptionalChaining() async throws {
        // In Swift you can do: instance.optional?.actual.actual
        // But Kotlin seems to need: instance.optional?.actual?.actual
        let supportingSwift = """
        class Foo {
            var bar: Bar?
            func barf() -> Bar? {
                return bar
            }
        }
        class Bar {
            var baz: Baz = Baz()
            var bazs: [Baz]?
            func bazf() -> Baz {
                return baz
            }
        }
        class Baz {
            var str: String = "ABC"
            var strs: [String?] = []
            func strf() -> String {
                return str
            }
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        func f() -> String? {
            return Foo().bar?.baz.str
        }
        func g() -> String {
            return Foo().bar!.baz.str
        }
        """, kotlin: """
        internal fun f(): String? = Foo().bar?.baz?.str
        internal fun g(): String = Foo().bar!!.baz.str
        """)

        try await check(expectMessages: true, supportingSwift: supportingSwift, swift: """
        func f() -> String? {
            return Foo().bar?.bazs?[0].str
        }
        func g() -> String? {
            return Foo().bar?.baz.strs[0]
        }
        func h() -> String? {
            return Foo().bar?.bazs![0].str
        }
        """, kotlin: """
        internal fun f(): String? = Foo().bar?.bazs?.get(0)?.str
        internal fun g(): String? = Foo().bar?.baz?.strs?.get(0)
        internal fun h(): String? = Foo().bar?.bazs!![0].str
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        func f() -> String? {
            return Foo().barf()?.bazf().str
        }
        func g() -> String {
            return Foo().barf()!.bazf().str
        }
        """, kotlin: """
        internal fun f(): String? = Foo().barf()?.bazf()?.str
        internal fun g(): String = Foo().barf()!!.bazf().str
        """)
    }

    func testOptionalChainingClosure() async throws {
        try await check(supportingSwift: """
        class C {
            let c: () -> Int = { }
        }
        """, swift: """
        func f() {
            let o: C? = C()
            let i = o?.c()
        }
        """, kotlin: """
        internal fun f() {
            val o: C? = C()
            val i = o?.c?.invoke()
        }
        """)
    }

    func testTrailingClosureCalls() async throws {
        try await check(supportingSwift: """
        func f(s: String, a: (Int) -> Int, b: () -> Int) {
        }
        """, swift: """
        f(s: "") { _ in 1 }
        f(s: "", b: { 2 })
        """, kotlin: """
        f(s = "") { _ -> 1 }
        f(s = "", b = { 2 })
        """)
    }

    func testImport() async throws {
        try await check(swift: """
        import Swift
        import Foundation
        import Foo
        import FooBar
        import com.xyz.Bar
        """, kotlin: """
        import skip.foundation.*
        import foo.*
        import foo.bar.*
        import com.xyz.Bar
        """)

        try await checkProducesMessage(swift: """
        import func Foundation.x
        """)
    }

    func testFatalError() async throws {
        // Should not be implemented in single-statement format because returns Never
        try await check(swift: """
        func f() {
            fatalError()
        }
        """, kotlin: """
        internal fun f() {
            fatalError()
        }
        """)
    }
}
