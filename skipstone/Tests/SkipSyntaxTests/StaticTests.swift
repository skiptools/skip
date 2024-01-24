import XCTest

final class StaticTests: XCTestCase {
    func testStaticMembers() async throws {
        try await check(swift: """
        class A {
            static let staticLet = 1
            static var staticVar = 10

            static func staticFunc() -> Int {
                return 20
            }

            var i = 1
        }
        """, kotlin: """
        internal open class A {

            internal open var i = 1

            open class CompanionClass {
                internal val staticLet = 1
                internal var staticVar = 10

                internal fun staticFunc(): Int = 20
            }
            companion object: CompanionClass()
        }
        """)

        try await check(swift: """
        class A<T: Equatable> {
            static let staticLet = 1

            static func staticFunc() -> Int {
                return 20
            }

            static func staticFunc2(p: T) -> T {
            }

            static func staticFunc3<U>(p1: T, p2: U) -> T {
            }

            func f() -> T {
            }
        }
        """, kotlin: """
        internal open class A<T> {

            internal open fun f(): T = Unit

            open class CompanionClass {
                internal val staticLet = 1

                internal fun staticFunc(): Int = 20

                internal fun <T> staticFunc2(p: T): T = Unit

                internal fun <T, U> staticFunc3(p1: T, p2: U): T = Unit
            }
            companion object: CompanionClass()
        }
        """)

        try await checkProducesMessage(swift: """
        class A<T> {
            static var staticVar: T

            func f() -> T {
            }
        }
        """)

        try await checkProducesMessage(swift: """
        class A<T> {
            static func staticFunc() -> T
            }

            func f() -> T {
            }
        }
        """)
    }

    func testStaticMembersInheritance() async throws {
        try await check(swift: """
        class A {
            static var staticVar = 10
            class func staticFunc() -> Int {
                return 20
            }
        }
        class B: A {
        }
        final class C: B {
            override class func staticFunc() -> Int {
                return 30
            }
        }
        """, kotlin: """
        internal open class A {

            open class CompanionClass {
                internal var staticVar = 10
                internal open fun staticFunc(): Int = 20
            }
            companion object: CompanionClass()
        }
        internal open class B: A() {

            open class CompanionClass: A.CompanionClass() {
            }
            companion object: CompanionClass()
        }
        internal class C: B() {

            companion object: B.CompanionClass() {
                override fun staticFunc(): Int = 30
            }
        }
        """)
    }

    func testStaticExtensionMembers() async throws {
        // Intentionally do not define the type we're extending so simulate a type in another module
        try await check(swift: """
        extension C {
            static var staticVar: Int {
                return 10
            }
            static func staticFunc() -> Int {
                return 20
            }
        }
        """, kotlin: """
        internal val C.Companion.staticVar: Int
            get() = 10
        internal fun C.Companion.staticFunc(): Int = 20
        """)

        try await check(swift: """
        extension C {
            static var staticVar: Int?
            static let staticConst = 10
        }
        """, kotlin: """
        internal var C.Companion.staticVar: Int?
            get() = CCompanionstaticVarstorage
            set(newValue) {
                CCompanionstaticVarstorage = newValue
            }
        private var CCompanionstaticVarstorage: Int? = null
        internal val C.Companion.staticConst: Int
            get() = CCompanionstaticConststorage
        private val CCompanionstaticConststorage = 10
        """)

        try await checkProducesMessage(swift: """
        class C<T> {
        }
        extension C where T: Equatable {
            static var staticVar: Int {
                return 1
            }
        }
        """)

        try await checkProducesMessage(swift: """
        class C<T> {
        }
        extension C where T: Equatable {
            static func staticFunc() {
            }
        }
        """)

        try await check(swift: """
        class C<T, U> {
        }
        extension C where T: Equatable {
            static func staticFunc(p: T) -> T {
            }
        }
        """, kotlin: """
        internal open class C<T, U> {

            open class CompanionClass {
            }
            companion object: CompanionClass()
        }

        internal fun <T> C.CompanionClass.staticFunc(p: T): T = Unit
        """)
    }

    func testProtocolStaticRequirements() async throws {
        try await check(swift: """
        protocol P {
            static func f()
            static var i: Int { get }
        }
        """, kotlin: """
        internal interface P {
        }
        internal interface PCompanion {
            fun f()
            val i: Int
        }
        """)
    }

    func testProtocolStaticRequirementsInheritance() async throws {
        try await check(swift: """
        protocol P {
            static func f()
            static var i: Int { get }
        }
        protocol Q: P {
        }
        protocol R: P {
            static func g()
        }

        struct S: R {
            static func f() {
            }
            static let i = 10
            static func g() {
            }
        }
        """, kotlin: """
        internal interface P {
        }
        internal interface PCompanion {
            fun f()
            val i: Int
        }
        internal interface Q: P {
        }
        internal interface QCompanion: PCompanion {
        }
        internal interface R: P {
        }
        internal interface RCompanion: PCompanion {
            fun g()
        }

        internal class S: R {

            companion object: RCompanion {
                override fun f() = Unit
                override val i = 10
                override fun g() = Unit
            }
        }
        """)
    }

    func testProtocolStaticRequirementOverride() async throws {
        try await check(supportingSwift: """
        protocol P {
            static var si: Int { get }
            static func sf()
        }
        """, swift: """
        class PImpl: P {
            static var si = 0
            static func sf() {
        }
        """, kotlin: """
        internal open class PImpl: P {

            open class CompanionClass: PCompanion {
                override var si = 0
                override fun sf() = Unit
            }
            companion object: CompanionClass()
        }
        """)
    }

    func testGenericProtocolStaticRequirements() async throws {
        try await check(swift: """
        protocol P {
            associatedtype T
            static func f(p: T)
        }
        class C: P {
            static func f(p: Int) {
            }
        }
        struct S: P {
            static func f(p: Int) {
            }
        }
        """, kotlin: """
        internal interface P<T> {
        }
        internal interface PCompanion<T> {
            fun f(p: T)
        }
        internal open class C: P<Int> {

            open class CompanionClass: PCompanion<Int> {
                override fun f(p: Int) = Unit
            }
            companion object: CompanionClass()
        }
        internal class S: P<Int> {

            companion object: PCompanion<Int> {
                override fun f(p: Int) = Unit
            }
        }
        """)

        try await check(swift: """
        protocol P {
            associatedtype T
            func f(p: T)
            static func sf(p: Int)
        }
        class C<T>: P {
            func f(p: T) {
            }
            static func sf(p: Int) {
            }
        }
        struct S<T>: P {
            func f(p: T) {
            }
            static func sf(p: Int) {
            }
        }
        """, kotlin: """
        internal interface P<T> {
            fun f(p: T)
        }
        internal interface PCompanion<T> {
            fun sf(p: Int)
        }
        internal open class C<T>: P<T> {
            override fun f(p: T) = Unit

            open class CompanionClass: PCompanion<Any> {
                override fun sf(p: Int) = Unit
            }
            companion object: CompanionClass()
        }
        internal class S<T>: P<T> {
            override fun f(p: T) = Unit

            companion object: PCompanion<Any> {
                override fun sf(p: Int) = Unit
            }
        }
        """)

        try await checkProducesMessage(swift: """
        protocol P {
            associatedtype T
            func f(p: T)
            static func sf(p: T)
        }
        class C<T>: P {
            func f(p: T) {
            }
            static func sf(p: T) {
            }
        }
        """)
    }

    func testProtocolInitRequirements() async throws {
        try await check(swift: """
        protocol P {
            init(i: Int)
        }
        """, kotlin: """
        internal interface P {
        }
        internal interface PCompanion {
            fun init(i: Int): P
        }
        """)

        try await checkProducesMessage(swift: """
        protocol P {
            init(i: Int)
        }
        extension P {
            init(x: Double) {
                self.init(i: Int(x))
            }
        }
        """)

        try await check(swift: """
        protocol P {
            init(i: Int)
        }
        class A: P {
            let i: Int
            init(i: Int) {
                self.i = i
            }
        }
        class B: A {
        }
        """, kotlin: """
        internal interface P {
        }
        internal interface PCompanion {
            fun init(i: Int): P
        }
        internal open class A: P {
            internal val i: Int
            internal constructor(i: Int) {
                this.i = i
            }

            open class CompanionClass: PCompanion {
                override fun init(i: Int): A {
                    return A(i = i)
                }
            }
            companion object: CompanionClass()
        }
        internal open class B: A {

            internal constructor(i: Int): super(i) {
            }

            open class CompanionClass: A.CompanionClass() {
                override fun init(i: Int): B {
                    return B(i = i)
                }
            }
            companion object: CompanionClass()
        }
        """)
    }

    func testGenericProtocolInitRequirements() async throws {
        try await check(swift: """
        protocol P {
            associatedtype T
            init(p: T)
        }
        protocol Q: P {
        }
        struct S: Q {
            let i: Int
            init(p: Int) {
                self.i = p
            }
        }
        """, kotlin: """
        internal interface P<T> {
        }
        internal interface PCompanion<T> {
            fun init(p: T): P<T>
        }
        internal interface Q<T>: P<T> {
        }
        internal interface QCompanion<T>: PCompanion<T> {
        }
        internal class S: Q<Int> {
            internal val i: Int
            internal constructor(p: Int) {
                this.i = p
            }

            companion object: QCompanion<Int> {
                override fun init(p: Int): S {
                    return S(p = p)
                }
            }
        }
        """)
    }

    func testProtocolInitRequirementsGenericType() async throws {
        try await checkProducesMessage(swift: """
        protocol P {
            associatedtype T
            init(p: T)
        }
        struct S<I>: P {
            let i: I
            init(p: I) {
                self.i = p
            }
        }
        """)
    }

    func testStaticProtocolMember() async throws {
        try await check(supportingSwift: """
        func type<T>(of: T) -> T.Type {
        }
        """, swift: """
        protocol P {
            static var i: Int { get }
            static func f()
        }
        protocol Q: P {
        }
        func g<T>(ptype: T.Type) where T: P {
            let i = ptype.i
            ptype.f()
        }
        func h<T>(p: T, q: any Q) where T: P {
            let i = type(of: p).i
            type(of: q).f()
        }
        """, kotlin: """
        import kotlin.reflect.KClass
        import kotlin.reflect.full.companionObjectInstance

        internal interface P {
        }
        internal interface PCompanion {
            val i: Int
            fun f()
        }
        internal interface Q: P {
        }
        internal interface QCompanion: PCompanion {
        }
        internal fun <T> g(ptype: KClass<T>) where T: P {
            val i = (ptype.companionObjectInstance as PCompanion).i
            (ptype.companionObjectInstance as PCompanion).f()
        }
        internal fun <T> h(p: T, q: Q) where T: P {
            val i = (type(of = p).companionObjectInstance as PCompanion).i
            (type(of = q).companionObjectInstance as QCompanion).f()
        }
        """)
    }

    func testInitProtocolMember() async throws {
        try await check(swift: """
        protocol P {
            init(i: Int)
        }
        protocol Q: P {
        }
        func f<T>(type: T.Type) -> T where T: Q {
            return type.init(i: 100) as T
        }
        """, kotlin: """
        import kotlin.reflect.KClass
        import kotlin.reflect.full.companionObjectInstance

        internal interface P {
        }
        internal interface PCompanion {
            fun init(i: Int): P
        }
        internal interface Q: P {
        }
        internal interface QCompanion: PCompanion {
        }
        internal fun <T> f(type: KClass<T>): T where T: Q = ((type.companionObjectInstance as QCompanion).init(i = 100) as T).sref()
        """)

        try await checkProducesMessage(swift: """
        protocol P {
            init(i: Int)
        }
        func f<T>(type: T.Type) -> T where T: P {
            return type.init(i: 100)
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

            open class CompanionClass {
                internal val typeVar = C::class

                internal fun staticFunc() = Unit
            }
            companion object: CompanionClass()
        }
        internal typealias X = C

        internal fun f() {
            g(c = C::class)
            g(c = C.typeVar)
            C.staticFunc()
            C.staticFunc()
            (C.typeVar.companionObjectInstance as C.CompanionClass).staticFunc()
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

                    open class CompanionClass {
                        val prop = "ABC"
                    }
                    companion object: CompanionClass()
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

                    open class CompanionClass {
                        internal var a = 100
                    }
                    companion object: CompanionClass()
                }
            }
            internal open fun f() {
                val x = B.C.a
            }
        }
        """)
    }
}
