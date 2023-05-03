@testable import SkipSyntax
import XCTest

final class TypeInferenceTests: XCTestCase {
    func testEnumCase() async throws {
        let supportingSwift = """
        enum E {
            case case1
            case case2
        }
        // Ensure we're not just guessing when we see e.g. .case1
        enum DuplicateE {
            case case1
            case case2
        }

        func eParamFunc(_ value: E) {
        }

        func eReturnFunc() -> E {
            return .case1
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        let e: E = .case1
        """, kotlin: """
        internal val e: E = E.case1
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        eParamFunc(.case2)
        """, kotlin: """
        eParamFunc(E.case2)
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        eReturnFunc() == .case2
        """, kotlin: """
        eReturnFunc() == E.case2
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        func enumReturn() -> E {
            return .case1
        }
        """, kotlin: """
        internal fun enumReturn(): E = E.case1
        """)
    }

    func testStaticMemberOfSameType() async throws {
        let supportingSwift = """
        class C {
            static let instance = C()

            func classReturnMemberFunc() -> C {
                return .instance
            }
        }

        // Ensure we're not just guessing when we see e.g. .instance
        class DuplicateC {
            static let instance = DuplicateC()
        }

        func cParamFunc(_ value: C) {
        }
        """
        
        try await check(supportingSwift: supportingSwift, swift: """
        let i: C = .instance
        """, kotlin: """
        internal val i: C = C.instance
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        cParamFunc(.instance)
        """, kotlin: """
        cParamFunc(C.instance)
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        func classReturn() -> C {
            return .instance
        }
        """, kotlin: """
        internal fun classReturn(): C = C.instance
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        class C2 {
            func classReturnMemberFunc() -> C {
                return .instance
            }
            func f() -> Bool {
                return classReturnMemberFunc() == .instance
            }
        }
        """, kotlin: """
        internal open class C2 {
            internal open fun classReturnMemberFunc(): C = C.instance
            internal open fun f(): Boolean = classReturnMemberFunc() == C.instance
        }
        """)
    }

    func testLocalParameterType() async throws {
        try await check(supportingSwift: """
        class C {
            static let instance = C()
        }
        """, swift: """
        func f(cls: C) -> Bool {
            let c = cls
            return c == .instance
        }
        """, kotlin: """
        internal fun f(cls: C): Boolean {
            val c = cls
            return c == C.instance
        }
        """)
    }

    func testDictionaries() async throws {
        try await check(supportingSwift: """
        class DictionaryHolder {
            var dictionaryOfDictionaries: [String: [String: Int]] = [:]
        }
        """, swift: """
        {
            let holder = DictionaryHolder()
            holder.dictionaryOfDictionaries["a"] = ["a": 1, "b": 2, "c": 3]
            let b = holder.dictionaryOfDictionaries["a"]!["b"] == .myZero
        }
        """, kotlin: """
        {
            val holder = DictionaryHolder()
            holder.dictionaryOfDictionaries["a"] = dictionaryOf(Tuple2("a", 1), Tuple2("b", 2), Tuple2("c", 3))
            val b = holder.dictionaryOfDictionaries["a"]!!["b"] == Int.myZero
        }
        """)
    }

    func testInit() async throws {
        try await check(supportingSwift: """
        class C {
            var v = 1
            init(v: Int = 1) {
                self.v = v
            }
        }
        func cParamFunc(_ value: C) {
        }
        """, swift: """
        {
            let c: C = .init(v: 100)
            cParamFunc(.init(v: 101))
        }
        """, kotlin: """
        {
            val c: C = C(v = 100)
            cParamFunc(C(v = 101))
        }
        """)
    }

    func testStaticVsInstanceContext() async throws {
        try await check(supportingSwift: """
        enum E {
            case case1
            case case2
        }
        enum DuplicateE {
            case case1
            case case2
        }
        """, swift: """
        class C {
            static func returnEnum() -> E {
                return .case1
            }
            func returnEnum() -> DuplicateE {
                return .case1
            }

            static func staticContext() -> Bool {
                return returnEnum() == .case1
            }
            func instanceContext() -> Bool {
                return returnEnum() == .case1
            }
        }
        """, kotlin: """
        internal open class C {
            internal open fun returnEnum(): DuplicateE = DuplicateE.case1
            internal open fun instanceContext(): Boolean = returnEnum() == DuplicateE.case1

            companion object {
                internal fun returnEnum(): E = E.case1

                internal fun staticContext(): Boolean = returnEnum() == E.case1
            }
        }
        """)
    }

    func testStaticMember() async throws {
        try await check(supportingSwift: """
        enum E {
            case case1
            case case2
        }
        enum DuplicateE {
            case case1
            case case2
        }
        class C {
            static func returnEnum() -> E {
                return .case1
            }
            func returnEnum() -> DuplicateE {
                return .case1
            }
        }
        """, swift: """
        {
            let b = C.returnEnum() == .case1
        }
        """, kotlin: """
        {
            val b = C.returnEnum() == E.case1
        }
        """)
    }

    func testGenericMemberIdentifier() async throws {
        try await check(supportingSwift: """
        class C<T> {
            var v: T
        }
        extension Int {
            static let myZero = 0
        }
        """, swift: """
        func f(c: C<Int>) -> Bool {
            return c.v == .myZero
        }
        """, kotlin: """
        internal fun f(c: C<Int>): Boolean = c.v == Int.myZero
        """)

        try await check(supportingSwift: """
        protocol P: AnyObject {
            func pfunc() -> Int
        }
        extension Int {
            static let myZero = 0
        }
        """, swift: """
        class C<T: P> {
            var v: T
            func f() -> Boolean {
                return v.pfunc() == .myZero
            }
        }
        """, kotlin: """
        internal open class C<T> where T: P {
            internal var v: T
            internal open fun f(): Boolean = v.pfunc() == Int.myZero
        }
        """)

        try await check(supportingSwift: """
        class C<T> {
            var v: T
        }
        extension Int {
            static let myZero = 0
        }
        """, swift: """
        func f(c: C<Array<Int>>) -> Bool {
            return c.v[1] == .myZero
        }
        """, kotlin: """
        internal fun f(c: C<Array<Int>>): Boolean = c.v[1] == Int.myZero
        """)
    }

    func testInheritedGenericMemberIdentifier() async throws {
        try await check(supportingSwift: """
        class Base<T, U> {
            var v: T
            var u: U
        }
        class C<X>: Base<Int, X> {
        }
        extension Int {
            static let myZero = 0
        }
        extension String {
            static let myEmpty = ""
        }
        """, swift: """
        func f(c: C<String>) -> Bool {
            return c.v == .myZero && c.u == .myEmpty
        }
        """, kotlin: """
        internal fun f(c: C<String>): Boolean = c.v == Int.myZero && c.u == String.myEmpty
        """)
    }

    func testGenericMemberFunction() async throws {
        try await check(supportingSwift: """
        class C<T> {
            func f() -> T {
            }
            func g(p: String) -> String {
            }
            func g(p: T) -> T {
            }
        }
        extension Int {
            static let myValue = 0
        }
        extension String {
            static let myValue = ""
        }
        """, swift: """
        func f(c: C<Int>) -> Bool {
            let b1 = c.f() == .myValue
            let b2 = c.g(p: 1) == .myValue
            let b3 = c.g(p: "1") == .myValue
        }
        """, kotlin: """
        internal fun f(c: C<Int>): Boolean {
            val b1 = c.f() == Int.myValue
            val b2 = c.g(p = 1) == Int.myValue
            val b3 = c.g(p = "1") == String.myValue
        }
        """)
    }

    func testGenericConstructor() async throws {
        try await check(supportingSwift: """
        class C<T> {
            var v: T
            init(v: T) {
                self.v = v
            }
        }
        extension Int {
            static let myZero = 0
        }
        """, swift: """
        {
            let c1 = C(v: 1)
            let b1 = c1.v == .myZero
            let c2 = C<Int>(v: 2)
            let b2 = c2.v == .myZero
        }
        """, kotlin: """
        {
            val c1 = C(v = 1)
            val b1 = c1.v == Int.myZero
            val c2 = C<Int>(v = 2)
            val b2 = c2.v == Int.myZero
        }
        """)

        try await check(supportingSwift: """
        class C<T> {
            var single: T
            init(array: [T]) {
                self.single = array[0]
            }
        }
        extension Int {
            static let myZero = 0
        }
        """, swift: """
        {
            let c = C(array: [1, 2, 3])
            let b = c.single == .myZero
        }
        """, kotlin: """
        {
            val c = C(array = arrayOf(1, 2, 3))
            val b = c.single == Int.myZero
        }
        """)
    }

    func testGenericFunctionReturnType() async throws {
        try await check(supportingSwift: """
        func max<T>(_ a: T, _ b: T) -> T {
        }
        extension Int {
            static let myValue = 0
        }
        extension String {
            static let myValue = ""
        }
        """, swift: """
        {
            let b1 = max(1, 2) == .myValue
            let b2 = max("a", "b") == .myValue
        }
        """, kotlin: """
        {
            val b1 = max(1, 2) == Int.myValue
            val b2 = max("a", "b") == String.myValue
        }
        """)
    }

    func testGenericFunctionParameters() async throws {
        try await check(supportingSwift: """
        enum E {
            case one, two
        }
        func f() -> E {
            return .one
        }
        func g<T>(_ a: T?, _ b: T?, c: Int = 0) -> Bool {
            return true
        }
        """, swift: """
        g(f(), .one)
        g(.one, f())
        """, kotlin: """
        g(f(), E.one)
        g(E.one, f())
        """)

        try await check(supportingSwift: """
        enum E {
            case one, two
        }
        func f() -> [E] {
            return []
        }
        func g<T>(_ a: T?, _ b: T?, c: Int = 0) -> Bool {
            return true
        }
        """, swift: """
        g(f(), [.one])
        g([.one], f())
        """, kotlin: """
        g(f(), arrayOf(E.one))
        g(arrayOf(E.one), f())
        """)
    }

    func testGenericExtension() async throws {
        try await check(supportingSwift: """
        class C<T> {
            init(t: T) {
            }
        }
        extension C {
            func f() -> T {
            }
        }
        extension Int {
            static let myZero = 0
        }
        """, swift: """
        {
            let b = C(t: 1).f() == .myZero
        }
        """, kotlin: """
        {
            val b = C(t = 1).f() == Int.myZero
        }
        """)
    }

    func testGenericsConstrainedExtension() async throws {
        try await check(supportingSwift: """
        class C<T> {
            init(t: T) {
            }
        }
        extension C where T == Int {
            func f() -> Int {
            }
        }
        extension C where T == String {
            func f() -> String {
            }
        }
        extension Int {
            static let myValue = 0
        }
        extension String {
            static let myValue = ""
        }
        """, swift: """
        {
            let b1 = C(t: 1).f() == .myValue
            let b2 = C(t: "1").f() == .myValue
        }
        """, kotlin: """
        {
            val b1 = C(t = 1).f() == Int.myValue
            val b2 = C(t = "1").f() == String.myValue
        }
        """)
    }

    func testMap() async throws {
        let supportingSwift = """
        extension Int {
            static let myValue = 0
        }
        extension String {
            static let myValue = ""
            var length: Int {
                return 0
            }
        }
        class Container<T> {
            func map<R>(_ transform: (T) -> R) -> [R] {
                return []
            }
        }
        struct Element {
            var id: Int?
        }
        enum ElementEnum: String {
            case one, two, three
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        {
            let c = Container<String>()
            let a = c.map { $0.length }
            let b = a[0] == .myValue
        }
        """, kotlin: """
        {
            val c = Container<String>()
            val a = c.map {
                it.length
            }
            val b = a[0] == Int.myValue
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        {
            let c = Container<Int>()
            let a = c.map { i in
                return Element(id: i)
            }
            let b = a[0].id == .myValue
        }
        """, kotlin: """
        {
            val c = Container<Int>()
            val a = c.map llabel@{ i ->
                return@llabel Element(id = i)
            }
            val b = a[0].id == Int.myValue
        }
        """)

        try await check(supportingSwift: supportingSwift, swift: """
        {
            let enums = Container<String>().map { ElementEnum(rawValue: $0) }
            let b = enums[1] == .two
        }
        """, kotlin: """
        {
            val enums = Container<String>().map {
                ElementEnum(rawValue = it)
            }
            val b = enums[1] == ElementEnum.two
        }
        """)
    }

    func testReduce() async throws {
        let supportingSwift = """
        extension Int {
            static let myValue = 0
        }
        extension String {
            static let myValue = ""
            var length: Int {
                return 0
            }
        }
        class Container<T> {
            func reduce<R>(into: R, perform: (inout R, T) -> Void) -> R {
            }
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        {
            let c = Container<Int>()
            let result = c.reduce(into: [Int: String]()) { result, i in
                result[i] = "\\(i)"
            }
            let b = result[1] == .myValue
        }
        """, kotlin: """
        {
            val c = Container<Int>()
            val result = c.reduce(into = Dictionary<Int, String>()) { result, i ->
                result.value[i] = "${i}"
            }
            val b = result[1] == String.myValue
        }
        """)
    }

    func testKnownUnavailableAPI() async throws {
        try await checkProducesMessage(preflight: true, swift: """
        {
            var s = "this is a string"
            s.append("foo")
        }
        """)
    }
}
