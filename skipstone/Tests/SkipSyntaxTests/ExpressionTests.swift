@testable import SkipSyntax
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
        import kotlin.reflect.*
        import kotlin.reflect.full.*

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
            X.staticFunc()
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
        internal class S: MutableStruct {
            internal var i: Int
            internal var a: Array<String> = arrayOf()
                get() = field.sref({ this.a = it })
                set(newValue) {
                    val newValue = newValue.sref()
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
        {
            perform(on: 10, +)
        }
        """, kotlin: """
        {
            perform(on = 10, { it, it_1 -> it + it_1 })
        }
        """)
    }

    func testReduceParameterLabel() async throws {
        try await check(swift: """
        {
            let arr = [1, 2, 3]
            let result = arr.reduce(0, +)
        }
        """, kotlin: """
        {
            val arr = arrayOf(1, 2, 3)
            val result = arr.reduce(initialResult = 0, { it, it_1 -> it + it_1 })
        }
        """)
    }

    func testAsyncInvocationStructCopy() async throws {
        try await check(swift: """
        {
            let result = await calculation(with: arg)
        }
        """, kotlin: """
        {
            val result = calculation(with = arg.sref())
        }
        """)

        try await check(swift: """
        {
            let result = await dosomething(with: calculation(with: arg), and: arg)
        }
        """, kotlin: """
        {
            val result = dosomething(with = calculation(with = arg.sref()), and = arg.sref())
        }
        """)

        try await check(swift: """
        {
            let arg = 1
            let result = await dosomething(with: calculation(with: arg), and: arg)
        }
        """, kotlin: """
        {
            val arg = 1
            val result = dosomething(with = calculation(with = arg), and = arg)
        }
        """)

        try await check(swift: """
        for await i in sequenceGenerator(arg1, arg2Generator(arg3)) {
            doSomething(with: i)
        }
        """, kotlin: """
        for (i in sequenceGenerator(arg1.sref(), arg2Generator(arg3.sref()))) {
            doSomething(with = i)
        }
        """)
    }

    func testKeyPaths() async throws {
        try await checkProducesMessage(swift: """
        struct S {
            let i = 0
        }
        func get(keyPath: KeyPath<S, Int>, from: S) -> Int {
            return from[keyPath: keyPath]
        }
        func f() {
            let s = S()
            let i = s[keyPath: \\.i]
            let j = get(keyPath: \\.i, from: s)
        }
        """)
    }
}


