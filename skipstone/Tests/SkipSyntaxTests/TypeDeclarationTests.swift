@testable import SkipSyntax
import XCTest

final class TypeDeclarationTests: XCTestCase {
    func testClass() async throws {
        try await check(swift: """
        class A {
        }
        """, kotlin: """
        internal open class A {
        }
        """)
    }

    func testPublicClass() async throws {
        try await check(swift: """
        public class A {
        }
        """, kotlin: """
        open class A {

            companion object {
            }
        }
        """)
    }

    func testNestedClass() async throws {
        try await check(swift: """
        class A {
            class B {
            }

            var b: B
        }
        """, kotlin: """
        internal open class A {
            internal open class B {
            }

            internal var b: A.B
        }
        """)
    }

    func testImmutableStruct() async throws {
        try await check(swift: """
        struct A {
            let i: Int

            init(i: Int) {
                self.i = i
            }
        }
        """, kotlin: """
        internal class A {
            internal val i: Int

            internal constructor(i: Int) {
                this.i = i
            }
        }
        """)
    }

    func testMutableStruct() async throws {
        try await check(swift: """
        struct A {
            internal var i: Int

            init(i: Int) {
                self.i = i
            }
        }
        """, kotlin: """
        internal class A: MutableStruct {
            internal var i: Int
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }

            internal constructor(i: Int) {
                this.i = i
            }

            private constructor(copy: MutableStruct) {
                val copy = copy as A
                this.i = copy.i
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct {
                return A(this as MutableStruct)
            }
        }
        """)
    }

    func testExtension() async throws {
        try await check(supportingSwift: """
        protocol TypeDeclarationTestsProtocol {
            func f()
        }
        """, swift: """
        class TypeDeclarationTestsClass {
            var i = 0
        }
        extension TypeDeclarationTestsClass: TypeDeclarationTestsProtocol {
            func f() {
            }
            func g() {
            }
        }
        """, kotlin: """
        internal open class TypeDeclarationTestsClass: TypeDeclarationTestsProtocol {
            internal var i = 0
            override fun f() {
            }
            internal open fun g() {
            }
        }
        """)

        // Extend unknown types so that we can simulate out-of-module extensions
        try await check(swift: """
        extension C {
            func f() {
            }
        }
        """, kotlin: """
        internal fun C.f() {
        }
        """)
        try await checkProducesMessage(swift: """
        extension C: I {
            func f() {
            }
        }
        """)
        try await checkProducesMessage(swift: """
        extension C {
            init(i: Int)
        }
        """)
    }

    func testProtocol() async throws {
        try await check(swift: """
        protocol P {
            var i: Int { get }
            var j: String { get set }
            func f(i: Int) -> String
            mutating func g()
        }
        """, kotlin: """
        internal interface P {
            val i: Int
            var j: String
            fun f(i: Int): String
            fun g()
        }
        """)

        try await checkProducesMessage(swift: """
        protocol P {
            static var i: Int { get }
        }
        """)
        try await checkProducesMessage(swift: """
        protocol P {
            init(i: Int)
        }
        """)
    }

    func testProtocolStaticMembers() async throws {
        try await checkProducesMessage(swift: """
        protocol P {
            static func f()
            var i: Int { get }
        }
        """)

        try await checkProducesMessage(swift: """
        protocol P {
            static var s: Int { get }
            var i: Int { get }
        }
        """)
    }

    func testProtocolExtension() async throws {
        try await check(swift: """
        protocol P {
            var i: Int { get }
            var j: Int { get }
            func f(i: Int) -> String
            func g()
        }
        extension P: I {
            var i: Int {
                return 1
            }
            var k: Int {
                return 2
            }
            func f(i: Int = 1) -> String {
                return "f"
            }
            func h() {
                print("h")
            }
        }
        """, kotlin: """
        internal interface P: I {
            val i: Int
                get() {
                    return 1
                }
            val j: Int
            fun f(i: Int = 1): String {
                return "f"
            }
            fun g()
            val k: Int
                get() {
                    return 2
                }
            fun h() {
                print("h")
            }
        }
        """)
    }

    func testTypealias() async throws {
        try await check(swift: """
        private typealias IArray = Array<Bool>
        """, kotlin: """
        private typealias IArray = Array<Boolean>
        """)

        try await check(swift: """
        typealias SkipUUID = java.util.UUID
        {
            let u = SkipUUID.uuidString()
        }
        """, kotlin: """
        internal typealias SkipUUID = java.util.UUID
        {
            val u = SkipUUID.uuidString()
        }
        """)
    }

    func testTypealiasToSelf() async throws {
        // Note: this is invalid Swift, so it doesn't really matter that the output is also invalid
        try await check(swift: """
        typealias A = A

        class A {
        }

        class B : A {
        }
        """, kotlin: """
        internal typealias A = A

        internal open class A {
        }

        internal open class B: A {

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }

            internal constructor(): super() {
            }
        }
        """)
    }

    func testGenericClass() async throws {
        try await check(swift: """
        class C<T, U> {
        }
        """, kotlin: """
        internal open class C<T, U> {
        }
        """)

        try await check(swift: """
        class Base {
        }
        class C<T: I, U>: Base where U: A, U: B {
        }
        """, kotlin: """
        internal open class Base {
        }
        internal open class C<T, U>: Base() where T: I, U: A, U: B {
        }
        """)
    }

    func testGenericProtocol() async throws {
        try await check(swift: """
        protocol P {
            associatedtype T
            associatedtype U
        }
        """, kotlin: """
        internal interface P<T, U> {
        }
        """)

        try await check(swift: """
        protocol Base {
        }
        protocol P: Base {
            associatedtype T: I
            associatedtype U: A, B
        }
        """, kotlin: """
        internal interface Base {
        }
        internal interface P<T, U>: Base where T: I, U: A, U: B {
        }
        """)

        try await check(swift: """
        protocol Base {
            associatedtype T: A
        }
        protocol P: Base {
            associatedtype U: B
        }
        """, kotlin: """
        internal interface Base<T> where T: A {
        }
        internal interface P<T, U>: Base<T> where T: A, U: B {
        }
        """)

        try await check(swift: """
        protocol Base {
            associatedtype T
        }
        protocol P: Base where T == Int {
            associatedtype U
        }
        """, kotlin: """
        internal interface Base<T> {
        }
        internal interface P<U>: Base<Int> {
        }
        """)

        try await check(swift: """
        protocol Base {
            associatedtype T
        }
        protocol P: Base {
            associatedtype U where U == T
        }
        """, kotlin: """
        internal interface Base<T> {
        }
        internal interface P<U>: Base<U> {
        }
        """)
    }

    func testGenericProtocolConformance() async throws {
        //~~~
    }

    func testGenericInheritance() async throws {
        try await check(swift: """
        class Base<T> {
        }
        class C<U>: Base<U> {
            func f() -> U? {
                return nil
            }
        }
        class D: Base<Bool> {
        }
        class E: Base<Array<Custom<Bool>>> {
        }
        """, kotlin: """
        internal open class Base<T> {
        }
        internal open class C<U>: Base<U>() {
            internal open fun f(): U? {
                return null
            }
        }
        internal open class D: Base<Boolean>() {
        }
        internal open class E: Base<Array<Custom<Boolean>>>() {
        }
        """)
    }

    func testGenericExtension() async throws {
        try await check(swift: """
        class C<T> {
            func f() -> T? {
                return nil
            }
        }
        extension C<Int> {
            var v: Int {
                return 1
            }
            func plusOne() -> Int {
                return (f() ?? 0) + 1
            }
        }
        """, kotlin: """
        internal open class C<T> {
            internal open fun f(): T? {
                return null
            }
        }
        internal val C<Int>.v: Int
            get() {
                return 1
            }
        internal fun C<Int>.plusOne(): Int {
            return (f() ?: 0) + 1
        }
        """)

        try await check(swift: """
        class C<T> {
            func f() -> T? {
                return nil
            }
        }
        extension C where T == Int {
            var v: Int {
                return 1
            }
            func plusOne() -> Int {
                return (f() ?? 0) + 1
            }
        }
        """, kotlin: """
        internal open class C<T> {
            internal open fun f(): T? {
                return null
            }
        }
        internal val C<Int>.v: Int
            get() {
                return 1
            }
        internal fun C<Int>.plusOne(): Int {
            return (f() ?: 0) + 1
        }
        """)

        try await check(supportingSwift: """
        protocol P {
        }
        """, swift: """
        class C<T, U> {
        }
        extension C where T: P {
            func f(p: T) {
            }
        }
        """, kotlin: """
        internal open class C<T, U> {
        }
        internal fun <T, U> C<T, U>.f(p: T) where T: P {
        }
        """)

        try await check(supportingSwift: """
        protocol P {
        }
        """, swift: """
        class C<T, U> {
        }
        extension C where T == Int, U: P {
            var v: U? {
                return nil
            }
            func f<V: P>(p1: U, p2: V) -> Int {
                return 1
            }
        }
        """, kotlin: """
        internal open class C<T, U> {
        }
        internal val <U> C<Int, U>.v: U? where U: P
            get() {
                return null
            }
        internal fun <U, V> C<Int, U>.f(p1: U, p2: V): Int where U: P, V: P {
            return 1
        }
        """)

        try await checkProducesMessage(swift: """
        class C<T> {
            func f(p: T) {
            }
        }
        extension C<Int> {
            func f(p: Int) {
            }
        }
        """)

        try await checkProducesMessage(swift: """
        class C<T> {
            func f(p: T) {
            }
        }
        extension C where T == Int {
            func f(p: Int) {
            }
        }
        """)
    }

    func testGenericTypealias() async throws {
        try await check(swift: """
        private typealias EArray<E> = Array<E>
        """, kotlin: """
        private typealias EArray<E> = Array<E>
        """)

        try await checkProducesMessage(swift: """
        private typealias EArray<E> = Array<E> where E: Comparable
        """)
    }

    func testGenerics() async throws {
        throw XCTSkip("TODO: Generics in classes, structs, extensions, typealiases. Generic where clauses. Members of generic types, including types constrained so we know they're not mutable structs")
        //~~~ inner classes can use types from outer classes in Swift, but Kotlin has to declare the inner class generic
        /*
         class Dict<K, V> {
             struct Entry {
                 var key: K
                 var value: V
             }
             var entries: [Entry] = []
             func put(key: K, value: V) {
                 entries.append(Entry(key: key, value: value))
             }
         }
         func makeEntry() -> Dict<Int, String>.Entry {
             return Dict<Int, String>.Entry(key: 1, value: "s")
         }
         */
        //~~~ Swift determines implemented protocol types, but in Kotlin you must declare them
        /*
         protocol P {
             associatedtype T
             func f() -> T
         }
         class C: P {
             func f() -> Int {
                 return 0
             }
         }
         */
         // Test enums and extensions
    }

    func testLocalTypes() async throws {
        try await checkProducesMessage(swift: """
        func f() -> Int {
            class F {
                static let x = 1
            }
            return F.x + 1
        }
        """)
    }

    func testTypeDeclaredWithinExtension() throws {
        throw XCTSkip("TODO: Test declaring a type within an extension. We need to move it to the original type extended type definition if in module, error if not")
    }
}
