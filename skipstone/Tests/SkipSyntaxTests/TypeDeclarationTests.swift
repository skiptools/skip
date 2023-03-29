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

        // These types are not present in symbols so that we can simulate out-of-module extensions
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
    }

    func testGenericInheritance() async throws {
        //~~~
//        try await check(swift: """
//        class Base<T> {
//        }
//        class C<T>: Base<T> {
//            func f() -> T? {
//                return nil
//            }
//        }
//        """, kotlin: """
//        internal open class Base<T> {
//        }
//        internal open class C<T>: Base<T>() {
//            internal open fun f(): T? {
//                return null
//            }
//        }
//        """)
    }

    func testGenericExtension() async throws {
        //~~~
//        try await check(symbols: symbols, swift: """
//        class C<T> {
//            func f() -> T? {
//                return nil
//            }
//        }
//        extension C where T == Int {
//            func plusOne() -> Int {
//                return (f() ?? 0) + 1
//            }
//        }
//        """, kotlin: """
//        internal open class C<T> {
//            internal open fun f(): T? {
//                return null
//            }
//            internal fun plusOne(): Int {
//                return (f() ?: 0) + 1
//            }
//        }
//        """)
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

    func testTypeDeclaredWithinExtension() throws {
        throw XCTSkip("TODO: Test declaring a type within an extension. We need to move it to the original type extended type definition if in module, error if not")
    }

    func testTypeDeclaredWithinFunction() throws {
        throw XCTSkip("TODO: Test declaring a type within a function. This includes making sure our plugins process in-function types correctly")
    }
}
