import XCTest

final class TypealiasTests: XCTestCase {
    func testTypealiasSubstitution() async throws {
        try await check(swift: """
        typealias AA = a.b.C

        class Sub: AA {
            let a: AA = AA()
            let b: B = AA.f()

            func subf(p: AA) -> [AA]? {
                return nil
            }
        }
        """, kotlin: """
        import skip.lib.Array

        internal typealias AA = a.b.C

        internal open class Sub: a.b.C() {
            internal val a: a.b.C = a.b.C()
            internal val b: B = a.b.C.f()

            internal open fun subf(p: a.b.C): Array<a.b.C>? = null
        }
        """)
    }

    func testMemberTypealias() async throws {
        try await check(swift: """
        class A {
            static let a = A()
        }
        class B {
            typealias Member = A
            let b = Member.a
            let b2: Member = .a
        }
        class C {
            let c = B.Member.a
            func f(m: B.Member) -> B.Member {
                return .a
            }
        }
        """, kotlin: """
        internal open class A {

            companion object {
                internal val a = A()
            }
        }
        internal open class B {
            internal val b = A.a
            internal val b2: A = A.a
        }
        internal open class C {
            internal val c = A.a
            internal open fun f(m: A): A = A.a
        }
        """)
    }

    func testTypealiasWithGenerics() async throws {
        try await check(supportingSwift: """
        extension Int {
            static var max = 1
        }
        """, swift: """
        typealias AA = Array<Int>
        func f(a: AA) -> Bool {
            return a[0] == .max
        }
        """, kotlin: """
        import skip.lib.Array

        internal typealias AA = Array<Int>
        internal fun f(a: Array<Int>): Boolean = a[0] == Int.max
        """)
    }

    func testProtocolGenericsResolutionUsingUnknownTypealiasMember() async throws {
        // Figure out generic type of P based on S.v
        try await check(swift: """
        typealias Alias<T> = java.util.A<T>
        protocol P {
            associatedtype T
            var v: Alias<T> { get }
        }
        struct S: P {
            let v: Alias<Int>
        }
        """, kotlin: """
        internal typealias Alias<T> = java.util.A<T>
        internal interface P<T> {
            val v: java.util.A<T>
        }
        internal class S: P<Int> {
            override val v: java.util.A<Int>

            constructor(v: java.util.A<Int>) {
                this.v = v
            }
        }
        """)
    }

    func testPartialTypealiaseGenerics() async throws {
        let supportingSwift = """
        extension Int {
            static let max = 1
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        typealias StringIntDict = Dictionary<String, Int>
        func f(dict: StringIntDict) -> Bool {
            return dict["a"] == .max
        }
        """, kotlin: """
        internal typealias StringIntDict = Dictionary<String, Int>
        internal fun f(dict: Dictionary<String, Int>): Boolean = dict["a"] == Int.max
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        typealias StringDict<T> = Dictionary<String, T>
        func f(dict: StringDict<Int>) -> Bool {
            return dict["a"] == .max
        }
        """, kotlin: """
        internal typealias StringDict<T> = Dictionary<String, T>
        internal fun f(dict: Dictionary<String, Int>): Boolean = dict["a"] == Int.max
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        typealias IntValueDict<T> = Dictionary<T, Int>
        func f(dict: IntValueDict<String>) -> Bool {
            return dict["a"] == .max
        }
        """, kotlin: """
        internal typealias IntValueDict<T> = Dictionary<T, Int>
        internal fun f(dict: Dictionary<String, Int>): Boolean = dict["a"] == Int.max
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        typealias MixedDict<V, K> = Dictionary<K, V>
        func f(dict: MixedDict<Int, String>) -> Bool {
            return dict["a"] == .max
        }
        """, kotlin: """
        internal typealias MixedDict<V, K> = Dictionary<K, V>
        internal fun f(dict: Dictionary<String, Int>): Boolean = dict["a"] == Int.max
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        typealias ArraysDict<T> = Dictionary<[T], [T]>
        func f(dict: ArraysDict<Int>) -> Bool {
            return dict[[1]]?[0] == .max
        }
        """, kotlin: """
        import skip.lib.Array
        
        internal typealias ArraysDict<T> = Dictionary<Array<T>, Array<T>>
        internal fun f(dict: Dictionary<Array<Int>, Array<Int>>): Boolean = dict[arrayOf(1)]?.get(0) == Int.max
        """)
    }

    func testRecursivelyNamedUnknownTypealias() async throws {
        try await check(swift: """
        public typealias MessageDigest = java.security.MessageDigest
        public protocol NamedHashFunction {
            var digest: MessageDigest { get }
        }
        """, kotlin: """
        typealias MessageDigest = java.security.MessageDigest
        interface NamedHashFunction {
            val digest: java.security.MessageDigest
        }
        """)
    }

    func testTypealiasParameter() async throws {
        try await check(supportingSwift: """
        protocol Collection {
            associatedtype Element
            // SKIP NOWARN
            subscript(i: Int) -> Element
            func firstIndex(of: Element) -> Int?
        }
        struct S: Collection {
            typealias Element = Character
            typealias Index = Int
        }
        """, swift: """
        func f(s: S) {
            let i: S.Index = s.firstIndex(of: "a")!
            let b = s[i] == "a"
        }
        """, kotlin: """
        internal fun f(s: S) {
            val i: Int = s.firstIndex(of = 'a')!!
            val b = s[i] == 'a'
        }
        """)
    }

    func testConstrainedGenericTypealias() async throws {
        try await checkProducesMessage(swift: """
        private typealias EArray<E> = Array<E> where E: Comparable
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

    func testTypealiasConstructorCall() async throws {
        try await check(swift: """
        typealias A = S
        func A(p1: String) -> A {
        }
        class S {
            init(p2: String) {
            }
        }
        func f() {
            let s1 = A(p1: "")
            let s2 = A(p2: "")
        }
        """, kotlin: """
        internal typealias A = S
        internal fun A(p1: String): S = Unit
        internal open class S {
            internal constructor(p2: String) {
            }
        }
        internal fun f() {
            val s1 = A(p1 = "")
            val s2 = S(p2 = "")
        }
        """)

        try await check(swift: """
        typealias A = java.util.S
        func A(p1: String) -> A {
        }
        func f() {
            let s1 = A(p1: "")
            let s2 = A(p2: "")
        }
        """, kotlin: """
        internal typealias A = java.util.S
        internal fun A(p1: String): java.util.S = Unit
        internal fun f() {
            val s1 = A(p1 = "")
            val s2 = java.util.S(p2 = "")
        }
        """)
    }

    func testLocalFunctionDoesNotOverrideType() async throws {
        // Make sure that a function name in the current file does not override all consideration of a same-named type
        try await check(supportingSwift: """
        typealias A = AA
        struct AA {
            init(a: String) {
            }
        }
        """, swift: """
        func A(b: String) -> AA? {
        }
        func f() {
            let string = ""
            let a = A(a: string)
            let b = A(b: string)
        }
        """, kotlin: """
        internal fun A(b: String): AA? = Unit
        internal fun f() {
            val string = ""
            val a = AA(a = string)
            val b = A(b = string)
        }
        """)
    }

    func testTypealiasFunctionArgumentMatchingInExtension() async throws {
        // Checks that we resolve typealiases in extensions as well
        try await check(swift: """
        typealias CGFloat = Double
        struct S {
            static let all = S()
        }
        protocol P {
        }
        extension P {
            public func f(_ s: S, _ c: CGFloat? = nil) -> P {
                return self
            }
            public func g(_ arg: CGFloat) -> P {
                return f(.all, arg)
            }
        }
        """, kotlin: """
        internal typealias CGFloat = Double
        internal class S {

            companion object {
                internal val all = S()
            }
        }
        internal interface P {
        
            fun f(s: S, c: Double? = null): P = this.sref()
            fun g(arg: Double): P = f(S.all, arg)
        }
        """)
    }
}
