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
        internal interface PCompanionInterface {
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
        internal interface PCompanionInterface {
            fun f()
            val i: Int
        }
        internal interface Q: P {
        }
        internal interface QCompanionInterface: PCompanionInterface {
        }
        internal interface R: P {
        }
        internal interface RCompanionInterface: PCompanionInterface {
            fun g()
        }

        internal class S: R {

            companion object: RCompanionInterface {
                override fun f() = Unit
                override val i = 10
                override fun g() = Unit
            }
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
        internal interface PCompanionInterface<T> {
            fun f(p: T)
        }
        internal open class C: P<Int> {

            open class CompanionClass: PCompanionInterface<Int> {
                override fun f(p: Int) = Unit
            }
            companion object: CompanionClass()
        }
        internal class S: P<Int> {

            companion object: PCompanionInterface<Int> {
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
        internal interface PCompanionInterface<T> {
            fun sf(p: Int)
        }
        internal open class C<T>: P<T> {
            override fun f(p: T) = Unit

            open class CompanionClass: PCompanionInterface<Any> {
                override fun sf(p: Int) = Unit
            }
            companion object: CompanionClass()
        }
        internal class S<T>: P<T> {
            override fun f(p: T) = Unit

            companion object: PCompanionInterface<Any> {
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
}
