import XCTest
@testable import SkipSyntax

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

    func testNestedClass() async throws {
        try await check(swift: """
        class A {
            var b1: B

            class B {
            }

            var b2: B
        }
        """, kotlin: """
        internal open class A {
            internal open var b1: A.B

            internal open class B {
            }

            internal open var b2: A.B
        }
        """)
    }

    func testNestedGenericClassForced() async throws {
        try await check(swift: """
        class A<T> {
            // SKIP NOWARN
            class B<T> {
                // SKIP NOWARN
                class C<T> {
                }

                func f(b: B.C<T>) {
                }
            }
        }
        """, kotlin: """
        internal open class A<T> {
            internal open class B<T> {
                internal open class C<T> {
                }

                internal open fun f(b: A.B.C<T>) = Unit
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

    func testExtensionMove() async throws {
        try await check(supportingSwift: """
        import Module1

        extension S: I {
            func f() {
            }
        }
        """, swift: """
        struct S {
        }
        """, kotlin: """
        import module1.module.*
        internal class S: I {

            internal fun f() = Unit
        }
        """)

        try await check(supportingSwift: """
        import Module1
        import Module2

        extension S: I {
            func f() {
            }
        }
        """, swift: """
        import Module1

        struct S {
        }
        """, kotlin: """
        import module1.module.*
        import module2.module.*

        internal class S: I {

            internal fun f() = Unit
        }
        """)

        try await check(supportingSwift: """
        struct S {
        }
        """, swift: """
        import Module1

        private extension S {
            private func f() {
            }
        }
        """, kotlin: """
        import module1.module.*

        private fun S.f() = Unit
        """)

        try await check(swift: """
        import Module1

        private extension S {
            private func f() {
            }
        }
        struct S {
        }
        """, kotlin: """
        import module1.module.*
        internal class S {

            private fun f() = Unit
        }
        """)

        try await check(supportingSwift: """
        extension S {
            func f() {
            }
        }
        class T {
            private func f() {
            }
        }
        """, swift: """
        struct S {
        }
        """, kotlin: """
        internal class S {

            internal fun f() = Unit
        }
        """)

        try await check(expectMessages: true, supportingSwift: """
        extension S {
            func f() {
            }
        }
        class T {
            fileprivate func f() {
            }
        }
        """, swift: """
        struct S {
        }
        """, kotlin: """
        internal class S {

            internal fun f() = Unit
        }
        """)

        try await check(expectMessages: true, supportingSwift: """
        extension S {
            func f() {
            }
        }
        private class T {
            func f() {
            }
        }
        """, swift: """
        struct S {
        }
        """, kotlin: """
        internal class S {

            internal fun f() = Unit
        }
        """)

        try await check(supportingSwift: """
        extension S {
            func f() {
            }
        }
        class T {
            private class R {
            }
        }
        """, swift: """
        struct S {
        }
        """, kotlin: """
        internal class S {

            internal fun f() = Unit
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
            fun h(): Unit = print("h")
        }
        """)

        try await checkProducesMessage(swift: """
        public protocol P {
        }
        extension P {
            func f() {
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

    func testGenericProtocolSelfEqual() async throws {
        try await check(supportingSwift: """
        extension Int {
            let min = 0
        }
        """, swift: """
        struct S: P {
        }
        protocol P {
        }
        extension P where Self == S {
            static let value = 1
            static let ref = S()
            static func refFunc() -> S {
                return S()
            }
        }
        func f(p: P = .ref, q: P = .refFunc()) {
            let b = S.value == .max
        }
        """, kotlin: """
        internal class S: P {

            companion object: PCompanion {

                val value = 1
                val ref = S()
                fun refFunc(): S = S()
            }
        }
        internal interface P {
        }
        internal interface PCompanion {
        }
        internal fun f(p: P = S.ref, q: P = S.refFunc()) {
            val b = S.value == Int.max
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
        import skip.lib.Array

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

        try await check(swift: """
        protocol P {
            associatedtype T
            func add(t: T)
        }
        class C {
            func add(t: Int) {
            }
        }
        extension C: P {
        }
        """, kotlin: """
        internal interface P<T> {
            fun add(t: T)
        }
        internal open class C: P<Int> {
            override fun add(t: Int) = Unit
        }
        """)

        try await check(supportingSwift: """
        protocol Identifiable {
            associatedtype ID
            var id: ID { get }
        }
        """, swift: """
        protocol P: Identifiable {
            var id: String { get }
            var name: String { get }
        }
        extension P {
            var id: String { "X" }
        }
        """, kotlin: """
        internal interface P: Identifiable<String> {
            override val id: String
                get() = "X"
            val name: String
        }
        """)
    }

    func testIdentifiableClassConformance() async throws {
        try await check(supportingSwift: """
        protocol Identifiable {
            associatedtype ID
            var id: ID { get }
        }
        """, swift: """
        class A: Identifiable {
            var id: String
        }
        class B: Identifiable {
        }
        """, kotlin: """
        internal open class A: Identifiable<String> {
            override var id: String
        }
        internal open class B: Identifiable<ObjectIdentifier> {
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
        import skip.lib.Array
        
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

    func testGenericSelfType() async throws {
        try await check(swift: """
        class C<T> {
            var c: Self? {
                return nil
            }
        }
        extension C<Int> {
            var i: Self? {
                return nil
            }
        }
        """, kotlin: """
        internal open class C<T> {
            internal open val c: C<T>?
                get() = null
        }

        internal val C<Int>.i: C<Int>?
            get() = null
        """)

        try await check(swift: """
        class C<T> {
        }
        extension C where Self.T == Int {
            var c: Self? {
                return nil
            }
        }
        """, kotlin: """
        internal open class C<T> {
        }

        internal val C<Int>.c: C<Int>?
            get() = null
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

        try await check(swift: """
        class C<T> {
            func f() -> T? {
                return nil
            }
        }
        extension C where Self.T == Int {
            var v: Int {
                return 1
            }
        }
        """, kotlin: """
        internal open class C<T> {
            internal open fun f(): T? = null
        }

        internal val C<Int>.v: Int
            get() = 1
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

    func testTypeDeclaredWithinExtension() async throws {
        try await check(swift: """
        public class C {
        }
        extension C {
            class Sub1 {
            }
        }
        public extension C {
            class Sub2 {
            }
        }
        """, kotlin: """
        open class C {
        
            internal open class Sub1 {
            }

            open class Sub2 {

                companion object: CompanionClass() {
                }
                open class CompanionClass {
                }
            }

            companion object: CompanionClass() {
            }
            open class CompanionClass {
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

        try await check(supportingSwift: """
        class C {
            var sub: Sub
        }
        extension C {
            class Sub {
                var x = 1
            }
        }
        extension Int {
            let min = 0
        }
        """, swift: """
        func f(c: C) {
            let b = c.sub.x == .min
        }
        """, kotlin: """
        internal fun f(c: C) {
            val b = c.sub.x == Int.min
        }
        """)
    }

    func testStringEncoding() async throws {
        try await check(supportingSwift: """
        extension String {
            typealias Encoding = StringEncoding
            typealias Index = Int
        }
        """, swift: """
        {
            let encoding: String.Encoding = String.Encoding.utf8
            let whatever: String.Whatever = String.Whatever.abcd
            let strindex: String.Index = 0
        }
        """, kotlin: """
        { ->
            val encoding: StringEncoding = StringEncoding.utf8
            val whatever: String.Whatever = String.Whatever.abcd.sref()
            val strindex: Int = 0
        }
        """)

        try await check(supportingSwift: """
        typealias PlatformStringEncoding = StringEncoding
        struct StringEncoding {
            static let utf8 = StringEncoding()
        }
        struct String {
        }
        """, swift: """
        struct Data {
        }
        func String(data: Data, encoding: PlatformStringEncoding) -> String {
        }
        String(data: Data(), encoding: .utf8)
        """, kotlin: """
        internal class Data {
        }
        internal fun String(data: Data, encoding: StringEncoding): String = Unit
        String(data = Data(), encoding = StringEncoding.utf8)
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
        internal class S: OptionSet<S, Int>, MutableStruct {
            override var rawValue: Int

            override val rawvaluelong: ULong
                get() = ULong(rawValue)
            override fun makeoptionset(rawvaluelong: ULong): S = S(rawValue = Int(rawvaluelong))
            override fun assignoptionset(target: S) {
                willmutate()
                try {
                    assignfrom(target)
                } finally {
                    didmutate()
                }
            }

            constructor(rawValue: Int) {
                this.rawValue = rawValue
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(rawValue)

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
        internal class S: OptionSet<S, ULong>, MutableStruct {
            internal var rawValue: ULong

            override val rawvaluelong: ULong
                get() = rawValue
            override fun makeoptionset(rawvaluelong: ULong): S = S(rawValue = rawvaluelong)
            override fun assignoptionset(target: S) {
                willmutate()
                try {
                    assignfrom(target)
                } finally {
                    didmutate()
                }
            }

            constructor(rawValue: ULong) {
                this.rawValue = rawValue
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S(rawValue)

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
        internal fun g(): Unit = f(opts = Opts.of())
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
            internal class S: OptionSet<Outer.S, Int>, MutableStruct {
                override var rawValue: Int

                override val rawvaluelong: ULong
                    get() = ULong(rawValue)
                override fun makeoptionset(rawvaluelong: ULong): Outer.S = S(rawValue = Int(rawvaluelong))
                override fun assignoptionset(target: Outer.S) {
                    willmutate()
                    try {
                        assignfrom(target)
                    } finally {
                        didmutate()
                    }
                }

                constructor(rawValue: Int) {
                    this.rawValue = rawValue
                }

                override var supdate: ((Any) -> Unit)? = null
                override var smutatingcount = 0
                override fun scopy(): MutableStruct = Outer.S(rawValue)

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

    func testTypeSignatureStringParsing() async throws {
        XCTAssertEqual(TypeSignature.for(name: "String", genericTypes: []), .string)
        XCTAssertEqual(TypeSignature.for(name: "Swift.Int", genericTypes: []), .int)
        XCTAssertEqual(TypeSignature.for(name: "A", genericTypes: []), .named("A", []))
        XCTAssertEqual(TypeSignature.for(name: "A<Int>", genericTypes: []), .named("A", [.int]))
        XCTAssertEqual(TypeSignature.for(name: "Dictionary<Int, String>", genericTypes: []), .dictionary(.int, .string))
        XCTAssertEqual(TypeSignature.for(name: "Array<S<String>>", genericTypes: []), .array(.named("S", [.string])))
        XCTAssertEqual(TypeSignature.for(name: "Dictionary<S<String>, Array<Int>>", genericTypes: []), .dictionary(.named("S", [.string]), .array(.int)))
    }

    func testNestedTypeMatchingGenericTypeName() async throws {
        try await check(supportingSwift: """
        struct Result<Success, Failure> {
        }
        """, swift: """
        struct Action {
            struct Result {
                static let success = Result()
                static func failure(error: Error) -> Result {
                    return Result.success
                }
            }
            let handler: () -> Result
        }
        """, kotlin: """
        internal class Action {
            internal class Result {

                companion object {
                    internal val success = Result()
                    internal fun failure(error: Error): Action.Result = Result.success
                }
            }
            internal val handler: () -> Action.Result

            constructor(handler: () -> Action.Result) {
                this.handler = handler
            }
        }
        """)
    }
}
