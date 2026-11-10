import XCTest
@testable import SkipSyntax

final class TupleTests: XCTestCase {
    func testDeclarations() async throws {
        try await check(swift: """
        var unit = ()
        """, kotlin: """
        internal var unit = Unit
        """)

        try await check(swift: """
        var pair: (Int, String) = (1, "s")
        """, kotlin: """
        internal var pair: Tuple2<Int, String> = Tuple2(1, "s")
        """)

        try await check(swift: """
        var triple: (Int, String, Double) = (1, "s", 0.5)
        """, kotlin: """
        internal var triple: Tuple3<Int, String, Double> = Tuple3(1, "s", 0.5)
        """)

        try await check(swift: """
        func f() -> (Int, String) {
            return (1, "s")
        }
        """, kotlin: """
        internal fun f(): Tuple2<Int, String> = Tuple2(1, "s")
        """)
    }

    func testLabels() async throws {
        try await check(swift: """
        let pair = (i: 1, s: "a")
        """, kotlin: """
        internal val pair = Tuple2(1, "a")
        """, kotlinPackageSupport: """
        internal val <E0, E1> Tuple2<E0, E1>.i: E0
            get() = element0

        internal val <E0, E1> Tuple2<E0, E1>.s: E1
            get() = element1
        """)

        try await check(swift: """
        func f(p: (String, Int)) -> [(x: Int, y: Int, z: Double)] {
            return [(1, 2, 3.0)]
        }
        """, kotlin: """
        import skip.lib.Array
        
        internal fun f(p: Tuple2<String, Int>): Array<Tuple3<Int, Int, Double>> = arrayOf(Tuple3(1, 2, 3.0))
        """, kotlinPackageSupport: """
        internal val <E0, E1, E2> Tuple3<E0, E1, E2>.x: E0
            get() = element0

        internal val <E0, E1, E2> Tuple3<E0, E1, E2>.y: E1
            get() = element1

        internal val <E0, E1, E2> Tuple3<E0, E1, E2>.z: E2
            get() = element2
        """)

        try await checkProducesMessage(swift: """
        let pair1 = (i: 1, s: "a")
        let pair2 = (d: 1.0, i: 1)
        """)
    }

    func testReturnSharedMutableStruct() async throws {
        // Newly-constructed instances do not need sref call
        try await check(swift: """
        func f() -> (A, B) {
            return (A(), B())
        }
        """, kotlin: """
        internal fun f(): Tuple2<A, B> = Tuple2(A(), B())
        """)

        try await check(swift: """
        func f(a: A, b: B) -> (A, B) {
            return (a, b)
        }
        """, kotlin: """
        internal fun f(a: A, b: B): Tuple2<A, B> = Tuple2(a.sref(), b.sref())
        """)
    }

    func testDestructuring() async throws {
        try await check(swift: """
        {
            let (a, b) = (1, 2)
            print(a)
            print(b)
        }
        """, kotlin: """
        { ->
            val (a, b) = Tuple2(1, 2)
            print(a)
            print(b)
        }
        """)

        try await check(swift: """
        {
            let t = (1, 2)
            let (a, b) = t
            print(a)
            print(b)
        }
        """, kotlin: """
        { ->
            val t = Tuple2(1, 2)
            val (a, b) = t
            print(a)
            print(b)
        }
        """)

        try await check(swift: """
        {
            let t = (1, 2)
            let (a, _) = t
            print(a)
        }
        """, kotlin: """
        { ->
            val t = Tuple2(1, 2)
            val (a, _) = t
            print(a)
        }
        """)
    }

    func testDestructuringReassignment() async throws {
        try await check(swift: """
        {
            var (a, b) = (1, 2)
            (a, b) = (3, 4))
        }
        """, kotlin: """
        { ->
            var (a, b) = Tuple2(1, 2)
            for (unusedi in 0..0) { val tmptuple = Tuple2(3, 4); a = tmptuple.element0; b = tmptuple.element1 }
        }
        """)
    }

    func testDestructuringSharedMutableStruct() async throws {
        try await check(swift: """
        {
            let (a, b) = (x, y)
            print(a)
            print(b)
        }
        """, kotlin: """
        { ->
            val (a, b) = Tuple2(x.sref(), y.sref())
            print(a)
            print(b)
        }
        """)

        try await check(swift: """
        {
            let (a, b) = t
            print(a)
            print(b)
        }
        """, kotlin: """
        { ->
            val (a, b) = t.sref()
            print(a)
            print(b)
        }
        """)
    }

    func testDestructuringOptionalBinding() async throws {
        try await check(swift: """
        var t: (Int, String)?
        if let (i, s) = t {
            print(i)
            print(s)
        }
        """, kotlin: """
        internal var t: Tuple2<Int, String>? = null
        t?.let { (i, s) ->
            print(i)
            print(s)
        }
        """)

        try await check(swift: """
        var t: (Int, String)?
        if let (_, s) = t {
            print(s)
        }
        """, kotlin: """
        internal var t: Tuple2<Int, String>? = null
        t?.let { (_, s) ->
            print(s)
        }
        """)

        try await check(supportingSwift: """
        func f() -> (Int, String)? {
            return nil
        }
        """, swift: """
        if let (i, s) = f() {
            print(i)
            print(s)
        }
        """, kotlin: """
        f()?.let { (i, s) ->
            print(i)
            print(s)
        }
        """)
    }

    func testDestructuringOptionalBindingSharedMutableStruct() async throws {
        try await check(swift: """
        if let (i, s) = t {
            print(i)
            print(s)
        }
        """, kotlin: """
        t.sref()?.let { (i, s) ->
            print(i)
            print(s)
        }
        """)
    }

    func testDictionaryForeachDestructuring() async throws {
        try await check(supportingSwift: """
        struct Dictionary<Key, Value>: Collection {
            typealias Index = Int
            typealias Element = (key: Key, value: Value)
        }
        protocol Collection {
            associatedtype Element
            func forEach(_ body: (Element) throws -> Void) rethrows {
            }
        }
        """, swift: """
        {
            let dict = ["a": 1, "b": 2]
            dict.forEach { (key, value) in
                print(key)
                print(value)
            }
        }
        """, kotlin: """
        { ->
            val dict = dictionaryOf(Tuple2("a", 1), Tuple2("b", 2))
            dict.forEach { (key, value) ->
                print(key)
                print(value)
            }
        }
        """)
    }

    func testMemberAccess() async throws {
        try await check(swift: """
        {
            let t = (1, "s", 0.5)
            let i = t.0
            let s = t.1
            let d = t.2
        }
        """, kotlin: """
        { ->
            val t = Tuple3(1, "s", 0.5)
            val i = t.element0
            val s = t.element1
            val d = t.element2
        }
        """)
    }

    func testMemberAccessSharedMutableStruct() async throws {
        // No need to sref() on member access
        try await check(swift: """
        {
            let t = (a, b, c)
            let i = t.0
            let s = t.1
            let d = t.2
        }
        """, kotlin: """
        { ->
            val t = Tuple3(a.sref(), b.sref(), c.sref())
            val i = t.element0
            val s = t.element1
            val d = t.element2
        }
        """)
    }

    func testDictionaryElementInferredClosureType() async throws {
        try await check(supportingSwift: """
        extension Int {
            static var min: Int { 0 }
        }
        struct Dictionary<Key, Value>: Collection {
            typealias Element = (key: Key, value: Value)
        }
        protocol Collection {
            associatedtype Element
            func compactMap<RE>(transform: (Element) -> RE?) -> [RE] {
            }
        }
        """, swift: """
        func f(d: [String: Int]) {
            let a = d.compactMap { $0.value == .min }
        }
        """, kotlin: """
        internal fun f(d: Dictionary<String, Int>) {
            val a = d.compactMap { it -> it.value == Int.min }
        }
        """, kotlinPackageSupport: """
        internal val <E0, E1> Tuple2<E0, E1>.value: E1
            get() = element1
        """)
    }

    func testKeyPathPackageSupport() async throws {
        KotlinTupleLabelTransformer.gatherLabelsFromTypeSignatures = false
        defer { KotlinTupleLabelTransformer.gatherLabelsFromTypeSignatures = true }
        try await check(supportingSwift: """
        struct Array<E>: Collection {
            typealias Element = E
        }
        protocol Collection {
            associatedtype Element
            func enumerated() -> [(index: Int, element: Element)] {
            }
        }
        """, swift: """
        func f(a: [String]) {
            g(elements: a.enumerated(), id: \\.index)
        }
        func g<E>(elements: [E], id: (E) -> Int) {
        }
        """, kotlin: """
        import skip.lib.Array

        internal fun f(a: Array<String>): Unit = g(elements = a.enumerated(), id = { it.index })
        internal fun <E> g(elements: Array<E>, id: (E) -> Int) = Unit
        """, kotlinPackageSupport: """
        internal val <E0, E1> Tuple2<E0, E1>.index: E0
            get() = element0
        """)
    }
}
