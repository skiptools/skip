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

            internal open var b: A.B
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
                @Suppress("NAME_SHADOWING") val copy = copy as A
                this.i = copy.i
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = A(this as MutableStruct)
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
            internal open var i = 0
            override fun f() = Unit
            internal open fun g() = Unit
        }
        """)

        // Extend unknown types so that we can simulate out-of-module extensions
        try await check(swift: """
        extension C {
            func f() {
            }
        }
        """, kotlin: """
        internal fun C.f() = Unit
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
                get() = 1
            val j: Int
            fun f(i: Int = 1): String = "f"
            fun g()
            val k: Int
                get() = 2
            fun h() = print("h")
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

        try await checkProducesMessage(swift: """
        class Dict<K, V> {
            var entries: [Entry] = []

            class Entry {
                let key: K
                let value: V
                init(key: K, value: V) {
                    self.key = key
                    self.value = value
                }
            }
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
        try await check(swift: """
        protocol P {
            associatedtype T
        }
        class C: P {
            typealias T = Int
        }
        """, kotlin: """
        internal interface P<T> {
        }
        internal open class C: P<Int> {
        }
        """)

        try await check(swift: """
        protocol P {
            associatedtype T
            func add(t: T)
            func get() -> T
        }
        class C: P {
            func add(t: Int) {
            }
            func get() -> Int {
                return 0
            }
        }
        """, kotlin: """
        internal interface P<T> {
            fun add(t: T)
            fun get(): T
        }
        internal open class C: P<Int> {
            override fun add(t: Int) = Unit
            override fun get(): Int = 0
        }
        """)

        try await check(swift: """
        protocol P {
            associatedtype T
            func add(t: [T])
        }
        protocol U: P {
            associatedtype K
            associatedtype V
            var map: [K: V] { get }
        }
        class C: U {
            var map = [String: Double]()
            func add(t: [Int]) {
            }
            func add(x: Double) {
            }
        }
        """, kotlin: """
        internal interface P<T> {
            fun add(t: Array<T>)
        }
        internal interface U<T, K, V>: P<T> {
            val map: Dictionary<K, V>
        }
        internal open class C: U<Int, String, Double> {
            override var map = Dictionary<String, Double>()
                get() = field.sref({ this.map = it })
                set(newValue) {
                    field = newValue.sref()
                }
            override fun add(t: Array<Int>) = Unit
            internal open fun add(x: Double) = Unit
        }
        """)
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
            internal open fun f(): U? = null
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
            internal open fun f(): T? = null
        }
        internal val C<Int>.v: Int
            get() = 1
        internal fun C<Int>.plusOne(): Int = (f() ?: 0) + 1
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
            internal open fun f(): T? = null
        }
        internal val C<Int>.v: Int
            get() = 1
        internal fun C<Int>.plusOne(): Int = (f() ?: 0) + 1
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
        internal fun <T, U> C<T, U>.f(p: T) where T: P = Unit
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
            get() = null
        internal fun <U, V> C<Int, U>.f(p1: U, p2: V): Int where U: P, V: P = 1
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

    func testSynthesizedStructEqualsHash() async throws {
        try await check(swift: """
        struct S: Equatable
            var i: Int
            var j: String {
                return 1
            }
        }
        """, kotlin: """
        internal class S: MutableStruct {
            internal var i: Int
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }
            internal val j: String
                get() = 1

            constructor(i: Int) {
                this.i = i
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(i)

            override fun equals(other: Any?): Boolean {
                if (other !is S) return false
                return i == other.i
            }
        }
        """)

        try await check(swift: """
        struct S: Equatable
            let i: Int
            let j: String

            init(i: Int, j: String) {
                self.i = i
                self.j = j
            }
        }
        """, kotlin: """
        internal class S {
            internal val i: Int
            internal val j: String

            internal constructor(i: Int, j: String) {
                this.i = i
                this.j = j
            }

            override fun equals(other: Any?): Boolean {
                if (other !is S) return false
                return i == other.i && j == other.j
            }
        }
        """)

        try await check(swift: """
        struct S: Equatable
            let i: Int
            let j: String

            init(i: Int, j: String) {
                self.i = i
                self.j = j
            }

            static func == (lhs: S, rhs: S) -> Bool {
                return true
            }
        }
        """, kotlin: """
        internal class S {
            internal val i: Int
            internal val j: String

            internal constructor(i: Int, j: String) {
                this.i = i
                this.j = j
            }

            override fun equals(other: Any?): Boolean {
                if (other !is S) {
                    return false
                }
                val lhs = this
                val rhs = other
                return true
            }
        }
        """)

        try await check(swift: """
        struct S: Hashable
            var i: Int
        }
        """, kotlin: """
        internal class S: MutableStruct {
            internal var i: Int
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }

            constructor(i: Int) {
                this.i = i
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(i)

            override fun equals(other: Any?): Boolean {
                if (other !is S) return false
                return i == other.i
            }

            override fun hashCode(): Int {
                var result = 1
                result = Hasher.combine(result, i)
                return result
            }
        }
        """)

        try await check(swift: """
        struct S: Hashable
            let i: Int
            let j: String

            init(i: Int, j: String) {
                self.i = i
                self.j = j
            }
        }
        """, kotlin: """
        internal class S {
            internal val i: Int
            internal val j: String

            internal constructor(i: Int, j: String) {
                this.i = i
                this.j = j
            }

            override fun equals(other: Any?): Boolean {
                if (other !is S) return false
                return i == other.i && j == other.j
            }

            override fun hashCode(): Int {
                var result = 1
                result = Hasher.combine(result, i)
                result = Hasher.combine(result, j)
                return result
            }
        }
        """)
    }

    func testTypeDeclaredWithinExtension() async throws {
        try await check(swift: """
        class C {
        }
        extension C {
            class Sub {
            }
        }
        """, kotlin: """
        internal open class C {
            internal open class Sub {
            }
        }
        """)

        try await checkProducesMessage(swift: """
        class C<T> {
        }
        extension C where T: Equatable {
            class Sub {
            }
        }
        """)
    }

    func testStringEncoding() async throws {
        try await check(swift: """
        {
            let encoding: String.Encoding = String.Encoding.utf8
            let whatever: String.Whatever = String.Whatever.abcd
            let strindex: String.Index = 0
        }
        """, kotlin: """
        {
            val encoding: StringEncoding = StringEncoding.utf8.sref()
            val whatever: String.Whatever = String.Whatever.abcd.sref()
            val strindex: StringIndex = 0
        }
        """)
    }

    func testActor() async throws {
        try await checkProducesMessage(swift: """
        actor A {
        }
        """)
    }

    func testRawRepresentableStruct() async throws {
        try await check(supportingSwift: """
        protocol RawRepresentable {
            associatedtype T
            var rawValue: T { get }
        }
        """, swift: """
        struct S: RawRepresentable {
            let rawValue: Int
        }
        """, kotlin: """
        internal class S: RawRepresentable<Int> {
            override val rawValue: Int

            constructor(rawValue: Int) {
                this.rawValue = rawValue
            }
        }
        """)
    }

    func testOptionSet() async throws {
        try await check(supportingSwift: """
        protocol RawRepresentable {
            associatedtype T
            var rawValue: T { get }
        }
        protocol OptionSet: RawRepresentable {
        }
        extension OptionSet {
            func contains(_ member: Self) -> Bool {
                return false
            }
        }
        """, swift: """
        struct S: OptionSet {
            let rawValue: Int

            static let s1 = S(rawValue: 1 << 0)
            static let s2 = S(rawValue: 1 << 1)
            static let all: S = [.s1, .s2]
        }

        func has1(s: S) -> Bool {
            return s.contains(.s1)
        }
        """, kotlin: """
        internal class S: OptionSet<S, Int> {
            override var rawValue: Int

            override val rawvaluelong: ULong
                get() = ULong(rawValue)
            override fun makeoptionset(rawvaluelong: ULong): S = S(rawValue = Int(rawvaluelong))
            override fun assignoptionset(target: S) = assignfrom(target)

            constructor(rawValue: Int) {
                this.rawValue = rawValue
            }

            private fun assignfrom(target: S) {
                this.rawValue = target.rawValue
            }

            companion object {

                internal val s1 = S(rawValue = 1 shl 0)
                internal val s2 = S(rawValue = 1 shl 1)
                internal val all: S = S.of(S.s1, S.s2)

                fun of(vararg options: S): S {
                    val value = options.fold(Int(0)) { result, option -> result or option.rawValue }
                    return S(rawValue = value)
                }
            }
        }

        internal fun has1(s: S): Boolean = s.contains(S.s1)
        """)

        try await check(swift: """
        struct S: OptionSet {
            let rawValue: UInt64

            static let s1 = S(rawValue: 1 << 0)
            static let s2 = S(rawValue: 1 << 1)
            static let all: S = [.s1, .s2]
        }
        """, kotlin: """
        internal class S: OptionSet<S, ULong> {
            internal var rawValue: ULong

            override val rawvaluelong: ULong
                get() = rawValue
            override fun makeoptionset(rawvaluelong: ULong): S = S(rawValue = rawvaluelong)
            override fun assignoptionset(target: S) = assignfrom(target)

            constructor(rawValue: ULong) {
                this.rawValue = rawValue
            }

            private fun assignfrom(target: S) {
                this.rawValue = target.rawValue
            }

            companion object {

                internal val s1 = S(rawValue = 1 shl 0)
                internal val s2 = S(rawValue = 1 shl 1)
                internal val all: S = S.of(S.s1, S.s2)

                fun of(vararg options: S): S {
                    val value = options.fold(ULong(0)) { result, option -> result or option.rawValue }
                    return S(rawValue = value)
                }
            }
        }
        """)

        try await checkProducesMessage(swift: """
        class C: OptionSet {
            let rawValue: Int

            init(rawValue: Int) {
                self.rawValue = rawValue
            }

            static let c1 = C(rawValue: 1 << 0)
            static let c2 = C(rawValue: 1 << 1)
        }
        """)
    }

    func testOptionSetInitFromEmptyArrayLiteral() async throws {
        try await check(supportingSwift: """
        struct Opts : OptionSet {
            let rawValue: Int
            static let a = Opts(rawValue: 1 << 0)
            static let b = Opts(rawValue: 1 << 1)
        }
        """, swift: """
        func f(opts: Opts) {
        }
        func g() {
            f(opts: [])
        }
        """, kotlin: """
        internal fun f(opts: Opts) = Unit
        internal fun g() = f(opts = Opts.of())
        """)
    }

    func testNestedClassOptionSet() async throws {
        try await check(supportingSwift: """
        protocol RawRepresentable {
            associatedtype T
            var rawValue: T { get }
        }
        protocol OptionSet: RawRepresentable {
        }
        extension OptionSet {
            func contains(_ member: Self) -> Bool {
                return false
            }
        }
        """, swift: """
        struct Outer {
            struct S: OptionSet {
                let rawValue: Int

                static let s1 = S(rawValue: 1 << 0)
                static let s2 = S(rawValue: 1 << 1)
                static let all: S = [.s1, .s2]
            }
        }
        """, kotlin: """
        internal class Outer {
            internal class S: OptionSet<Outer.S, Int> {
                override var rawValue: Int

                override val rawvaluelong: ULong
                    get() = ULong(rawValue)
                override fun makeoptionset(rawvaluelong: ULong): Outer.S = S(rawValue = Int(rawvaluelong))
                override fun assignoptionset(target: Outer.S) = assignfrom(target)

                constructor(rawValue: Int) {
                    this.rawValue = rawValue
                }

                private fun assignfrom(target: Outer.S) {
                    this.rawValue = target.rawValue
                }

                companion object {

                    internal val s1 = S(rawValue = 1 shl 0)
                    internal val s2 = S(rawValue = 1 shl 1)
                    internal val all: Outer.S = Outer.S.of(Outer.S.s1, Outer.S.s2)

                    fun of(vararg options: Outer.S): Outer.S {
                        val value = options.fold(Int(0)) { result, option -> result or option.rawValue }
                        return S(rawValue = value)
                    }
                }
            }
        }
        """)
    }

    func testMutableGenericStructNoConstructor() async throws {
        try await check(swift: """
        struct Gen<T, U, V> {
            var name: String
        }
        """, kotlin: """
        internal class Gen<T, U, V>: MutableStruct {
            internal var name: String
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }

            constructor(name: String) {
                this.name = name
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = Gen<T, U, V>(name)
        }
        """)
    }

    func testMutableGenericStructWithConstructor() async throws {
        try await check(swift: """
        struct Gen<T> {
            var name: String? = nil
            init() {
            }
        }
        """, kotlin: """
        internal class Gen<T>: MutableStruct {
            internal var name: String? = null
                set(newValue) {
                    willmutate()
                    field = newValue
                    didmutate()
                }
            internal constructor() {
            }
        
            private constructor(copy: MutableStruct) {
                @Suppress("NAME_SHADOWING") val copy = copy as Gen<T>
                this.name = copy.name
            }
        
            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = Gen<T>(this as MutableStruct)
        }
        """)
    }

    func testReifiedTypes() async throws {
        try await check(swift: """
        class C<T> {
            @inline(__always) func f() -> T? {
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
            internal open fun f(): T? = null
        }
        internal val C<Int>.v: Int
            get() = 1
        internal fun C<Int>.plusOne(): Int = (f() ?: 0) + 1
        """)

        try await check(swift: """
        class C<T> {
            @inline(__always) func f() -> T? {
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
            internal open fun f(): T? = null
        }
        internal val C<Int>.v: Int
            get() = 1
        internal fun C<Int>.plusOne(): Int = (f() ?: 0) + 1
        """)

        try await check(supportingSwift: """
        protocol P {
        }
        """, swift: """
        class C<T, U> {
        }
        extension C where T: P {
            @inline(__always) func f(p: T) {
            }
        }
        """, kotlin: """
        internal open class C<T, U> {
        }
        internal inline fun <reified T, reified U> C<T, U>.f(p: T) where T: P = Unit
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
            @inline(__always) func f<V: P>(p1: U, p2: V) -> Int {
                return 1
            }
        }
        """, kotlin: """
        internal open class C<T, U> {
        }
        internal val <U> C<Int, U>.v: U? where U: P
            get() = null
        internal inline fun <reified U, reified V> C<Int, U>.f(p1: U, p2: V): Int where U: P, V: P = 1
        """)
    }
}
