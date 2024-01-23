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

        // Test several things including meta type argument matching, differentiating .init from embedding type constructor, etc
        try await check(supportingSwift: """
        enum E: Error {
            case err(Any.Type, E.Context)

            struct Context {
                init(a: String, b: Int, c: String? = nil) {
                }
            }
        }
        """, swift: """
        struct S {
            func f() throws {
                throw E.err(E.self, .init(a: "", b: 1))
            }
        }
        """, kotlin: """
        internal class S {
            internal fun f() {
                throw E.err(E::class, E.Context(a = "", b = 1))
            }
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

            open class CompanionClass {
                internal fun returnEnum(): E = E.case1

                internal fun staticContext(): Boolean = returnEnum() == E.case1
            }
            companion object: CompanionClass()
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
            internal open var v: T
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
        import skip.lib.Array
        
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
        import skip.lib.Array

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
        import skip.lib.Array

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

    func testSelfGenericProtocol() async throws {
        try await check(supportingSwift: """
        public protocol SetAlgebra<Element> {
            associatedtype Element
        }
        extension SetAlgebra {
            public func contains(_ element: Element) -> Bool {
                fatalError()
            }
        }
        protocol P: SetAlgebra where Element == Self {
        }
        struct S: P {
            static let s1 = S()
        }
        """, swift: """
        func f(s: S) {
            let b = s.contains(.s1)
        }
        """, kotlin: """
        internal fun f(s: S) {
            val b = s.contains(S.s1)
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
            val a = c.map { it -> it.length }
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
            val a = c.map l@{ i -> return@l Element(id = i) }
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
            val enums = Container<String>().map { it -> ElementEnum(rawValue = it) }
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
            val result = c.reduce(into = Dictionary<Int, String>()) { result, i -> result.value[i] = "${i}" }
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

    func testExtensionInSameFile() async throws {
        try await check(supportingSwift: """
        enum E {
            case a, b
        }
        """, swift: """
        class C {
            func f() -> E {
                return .a
            }
        }
        extension C {
            func g() -> Bool {
                return C().f() == .a
            }
        }
        """, kotlin: """
        internal open class C {
            internal open fun f(): E = E.a

            internal open fun g(): Boolean = C().f() == E.a
        }
        """)
    }

    func testExtensionInDifferentFile() async throws {
        try await check(supportingSwift: """
        enum E {
            case a, b
        }
        extension C {
            func g() -> Bool {
                return C().f() == .a
            }
        }
        """, swift: """
        class C {
            func f() -> E {
                return .a
            }
        }
        """, kotlin: """
        internal open class C {
            internal open fun f(): E = E.a

            internal open fun g(): Boolean = C().f() == E.a
        }
        """)
    }

    func testEscapedProperty() async throws {
        try await check(supportingSwift: """
        struct Notification {
            struct Name {
                init(_ value: String) {
                }
            }
        }
        extension Notification.Name {
            static let test: Notification.Name {
                return Notification.Name("test")
            }
        }
        class NotificationCenter {
            static let `default` = NotificationCenter()
            func post(name: Notification.Name) {
            }
        }
        """, swift: """
        func f() {
            NotificationCenter.default.post(name: .test)
        }
        """, kotlin: """
        internal fun f(): Unit = NotificationCenter.default.post(name = Notification.Name.test)
        """)
    }

    func testCastCausingModuleNameFalsePositive() async throws {
        // The fact that the 'callingClass.kotlin' member access type is known due to the cast even though the
        // base type of the expression is unknown was causing us to think that callingClass was a module name.
        // We restructured the code to require a type inference match rather than just a known member type
        try await check(swift: """
        class Bundle {
            var module: Bundle {
                let callingClass = Class.forName("name")
                return Bundle(callingClass.kotlin as AnyClass)
            }
        }
        """, kotlin: """
        internal open class Bundle {
            internal open val module: Bundle
                get() {
                    val callingClass = Class.forName("name")
                    return Bundle(callingClass.kotlin as AnyClass)
                }
        }
        """)
    }

    func testCustomSequence() async throws {
        try await check(supportingSwift: """
        protocol Sequence {
            associatedtype Element
        }
        extension Sequence {
            func makeIterator() -> any IteratorProtocol<Element> {
            }
        }
        protocol IteratorProtocol {
            associatedtype Element
            func next() -> Element?
        }
        extension Int {
            static let zero = 0
        }
        class S1: S1Base {
        }
        class S1Base: Sequence {
            func makeIterator() -> IntIterator {
                return IntIterator()
            }
        }
        class IntIterator: IteratorProtocol {
            func next() -> Int? {
                return nil
            }
        }
        """, swift: """
        func f1(p1: S1, p2: any Sequence<Int>) {
            for i in p1 {
                let b = i == .zero
            }
            for i in p2 {
                let b = i == .zero
            }
        }
        """, kotlin: """
        import skip.lib.Sequence

        internal fun f1(p1: S1, p2: Sequence<Int>) {
            for (i in p1) {
                val b = i == Int.zero
            }
            for (i in p2.sref()) {
                val b = i == Int.zero
            }
        }
        """)
    }

    func testSelfReturnTypeInference() async throws {
        try await check(swift: """
        class C {
            static let c: Self {
                .init(name: "c")
            }
            init(name: String) {
            }
        }
        """, kotlin: """
        internal open class C {
            internal constructor(name: String) {
            }

            open class CompanionClass {
                internal val c: C
                    get() = C(name = "c")
            }
            companion object: CompanionClass()
        }
        """)
    }

    func testElementSpecialization() async throws {
        let supportingSwift = """
        protocol Sequence {
            associatedtype Element
        }
        extension Sequence {
            func joined<RE>() -> [RE] where Element: Sequence<RE> {
                fatalError()
            }
        }
        struct Array<Element>: Sequence {
            init(_ sequence: any Sequence<Element>) {
            }
        }
        enum E {
            case a
            case b
            case c
        }
        """

        try await check(supportingSwift: supportingSwift, swift: """
        func f() {
            let a: [[E]] = [[.a], [.b, .c]]
            let j = a.joined()
            let b = Array(j) == [.a, .b, .c]
        }
        """, kotlin: """
        import skip.lib.Array

        internal fun f() {
            val a: Array<Array<E>> = arrayOf(arrayOf(E.a), arrayOf(E.b, E.c))
            val j = a.joined()
            val b = Array(j) == arrayOf(E.a, E.b, E.c)
        }
        """)
    }

    func testUnqualifiedMemberMatch() async throws {
        try await check(supportingSwift: """
        struct S1 {
        }
        struct S2 {
            static let all = S2()
        }
        """, swift: """
        func f(_ s: S1) {
        }
        
        func f(_ s: S2) {
        }
        
        func f() {
            f(.all)
        }
        """, kotlin: """
        internal fun f(s: S1) = Unit
        
        internal fun f(s: S2) = Unit
        
        internal fun f(): Unit = f(S2.all)
        """)
    }

    func testUnqualifiedMemberChain() async throws {
        try await check(supportingSwift: """
        struct S {
            static let s = S()
            static func factory() -> S {
                return S()
            }

            let is = S()
            func ifactory() -> S {
                return S()
            }
        }
        """, swift: """
        func f() {
            let b1 = g(.s)
            let b2 = g(.factory())
            let b3 = g(.s.is.is)
            let b4 = g(.factory().is.ifactory())
            let b5 = g(.s.ifactory().ifactory().is)
        }
        func g(_ s: S) {
        }
        """, kotlin: """
        internal fun f() {
            val b1 = g(S.s)
            val b2 = g(S.factory())
            val b3 = g(S.s.is_.is_)
            val b4 = g(S.factory().is_.ifactory())
            val b5 = g(S.s.ifactory().ifactory().is_)
        }
        internal fun g(s: S) = Unit
        """)
    }

    func testInferUsingCollectionElementType() async throws {
        try await check(supportingSwift: """
        func s(_ s: String) {
        }
        func s(_ s: Any) {
        }
        extension String {
            static let empty = ""
        }
        protocol C {
            associatedtype E
        }
        struct A<E>: C {
        }
        func f<T>(a: any C<T>, block: (T) -> Void) {
        }
        """, swift: """
        func g(a: A<String>) {
            f(a: a) {
                let b = $0 == .empty
                s($0)
            }
        }
        """, kotlin: """
        internal fun g(a: A<String>) {
            f(a = a) { it ->
                val b = it == String.empty
                s(it)
            }
        }
        """)
    }

    func testDefaultedClosureFollowedByRequiredClosureParameters() async throws {
        try await check(supportingSwift: """
        extension Int {
            static let zero = 0
        }
        func f(a: Int, b: (() -> Void)? = nil, c: () -> Void) -> Int {
        }
        """, swift: """
        let b = f(a: 1) { } == .zero
        """, kotlin: """
        internal val b = f(a = 1) {  } == Int.zero
        """)
    }

    func testUnavailableAndAvailableFunctionsWithSameIdentifier() async throws {
        try await check(swift: """
        protocol P {
        }
        extension P {
            @available(*, unavailable)
            func f(x: Int = 0, block: () -> Void) {
            }
            func f(a: Int = 0) {
            }
            func g() {
                f()
            }
        }
        """, kotlin: """
        internal interface P {

            @Deprecated("This API is not yet available in Skip. Consider placing it within a #if !SKIP block. You can file an issue against the owning library at https://github.com/skiptools, or see the library README for information on adding support", level = DeprecationLevel.ERROR)
            fun f(x: Int = 0, block: () -> Unit) = Unit
            fun f(a: Int = 0) = Unit
            fun g(): Unit = f()
        }
        """)
    }

    func testAnyProtocolWithoutSpecifiedGenerics() async throws {
        try await check(supportingSwift: """
        protocol P {
            associatedtype Data
            var data: Data { get }
            func doSomething()
        }
        """, swift: """
        struct S: P {
            let data: Int
            func doSomething() {
                print(data)
            }
        }
        func f(p: any P) {
            p.doSomething()
        }
        func f<D>(s: S<D>) {
            s.doSomething()
        }
        func f<P>(p: P) {
            print(p)
        }
        """, kotlin: """
        internal class S: P<Int> {
            override val data: Int
            override fun doSomething(): Unit = print(data)

            constructor(data: Int) {
                this.data = data
            }
        }
        internal fun f(p: P<*>): Unit = p.doSomething()
        internal fun <D> f(s: S<D>): Unit = s.doSomething()
        internal fun <P> f(p: P): Unit = print(p)
        """)

        try await check(supportingSwift: """
        protocol Base {
            associatedtype Data
            var data: Data { get }
        }
        protocol P: Base {
            func doSomething()
        }
        """, swift: """
        struct S: P {
            let data: Int
            func doSomething() {
                print(data)
            }
        }
        func f(p: any P) {
            p.doSomething()
        }
        func f<D>(s: S<D>) {
            s.doSomething()
        }
        """, kotlin: """
        internal class S: P<Int> {
            override val data: Int
            override fun doSomething(): Unit = print(data)

            constructor(data: Int) {
                this.data = data
            }
        }
        internal fun f(p: P<*>): Unit = p.doSomething()
        internal fun <D> f(s: S<D>): Unit = s.doSomething()
        """)
    }

    func testExtensionOfUnknownTypeReference() async throws {
        try await check(supportingSwift: """
        extension Modifier {
            static func ext() -> Int {
                return 0
            }
        }
        """, swift: """
        func f() {
            let m = Modifier.ext()
        }
        """, kotlin: """
        internal fun f() {
            val m = Modifier.ext()
        }
        """)
    }
}
