@testable import SkipSyntax
import XCTest

final class MemberDeclarationTests: XCTestCase {
    func testOptionalVariableInitialization() async throws {
        try await check(swift: """
        class A {
            var i: Int?
            var j: Int? = nil
            var k = 10
        }
        """, kotlin: """
        internal open class A {
            internal var i: Int? = null
            internal var j: Int? = null
            internal var k = 10
        }
        """)
    }

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

            internal var i = 1

            companion object {
                internal val staticLet = 1
                internal var staticVar = 10

                internal fun staticFunc(): Int {
                    return 20
                }
            }
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

            internal open fun f(): T {
            }

            companion object {
                internal val staticLet = 1

                internal fun staticFunc(): Int {
                    return 20
                }

                internal fun <T> staticFunc2(p: T): T {
                }

                internal fun <T, U> staticFunc3(p1: T, p2: U): T {
                }
            }
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
            static func staticFunc() -> T {
            }

            func f() -> T {
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
            get() {
                return 10
            }
        internal fun C.Companion.staticFunc(): Int {
            return 20
        }
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

        try await check(supportingSwift: """
        class C<T, U> {
        }
        """, swift: """
        extension C where T: Equatable {
            static func staticFunc(p: T) -> T {
            }
        }
        """, kotlin: """
        internal fun <T> C.Companion.staticFunc(p: T): T {
        }
        """)
    }

    func testComputedVariableGetSet() async throws {
        try await check(swift: """
        class A {
            var i: Int {
                return 10
            }
            var j: Int {
                get {
                    return 10
                }
                set {
                    print(newValue)
                }
            }
        }
        """, kotlin: """
        internal open class A {
            internal open val i: Int
                get() {
                    return 10
                }
            internal open var j: Int
                get() {
                    return 10
                }
                set(newValue) {
                    print(newValue)
                }
        }
        """)

        // Custom set label
        try await check(swift: """
        class A {
            var i: Int {
                get {
                    return 10
                }
                set(value) {
                    print(value)
                }
            }
        }
        """, kotlin: """
        internal open class A {
            internal open var i: Int
                get() {
                    return 10
                }
                set(newValue) {
                    val value = newValue
                    print(value)
                }
        }
        """)
    }

    func testVariableWillDidSet() async throws {
        try await check(swift: """
        class A {
            var i = 1 {
                willSet {
                    print(newValue)
                }
            }
            var j = 2 {
                didSet {
                    print(j == 2)
                }
            }
        }
        """, kotlin: """
        internal open class A {
            internal var i = 1
                set(newValue) {
                    print(newValue)
                    field = newValue
                }
            internal var j = 2
                set(newValue) {
                    field = newValue
                    print(j == 2)
                }
        }
        """)

        // Custom willSet label
        try await check(swift: """
        class A {
            var i = 1 {
                willSet(value) {
                    print(value)
                }
            }
        }
        """, kotlin: """
        internal open class A {
            internal var i = 1
                set(newValue) {
                    val value = newValue
                    print(value)
                    field = newValue
                }
        }
        """)

        try await check(swift: """
        class A {
            var i = 1 {
                didSet {
                    if newValue != oldValue {
                        print(newValue)
                    }
                }
            }
        }
        """, kotlin: """
        internal open class A {
            internal var i = 1
                set(newValue) {
                    val oldValue = field
                    field = newValue
                    if (newValue != oldValue) {
                        print(newValue)
                    }
                }
        }
        """)
    }

    func testMutableStructVariableWillDidSet() async throws {
        try await check(swift: """
        struct A {
              var i = 1 {
                  willSet {
                      print(newValue)
                  }
              }
              var j = 2 {
                  didSet {
                      print(j == 2)
                  }
              }
        }
        """, kotlin: """
        internal class A: MutableStruct {
            internal var i = 1
                set(newValue) {
                    willmutate()
                    try {
                        if (!suppresssideeffects) {
                            print(newValue)
                        }
                        field = newValue
                    } finally {
                        didmutate()
                    }
                }
            internal var j = 2
                set(newValue) {
                    willmutate()
                    try {
                        field = newValue
                        if (!suppresssideeffects) {
                            print(j == 2)
                        }
                    } finally {
                        didmutate()
                    }
                }

            constructor(i: Int = 1, j: Int = 2) {
                suppresssideeffects = true
                try {
                    this.i = i
                    this.j = j
                } finally {
                    suppresssideeffects = false
                }
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct {
                return A(i, j)
            }

            private var suppresssideeffects = false
        }
        """)
    }

    func testPropertySideEffectOrdering() {
        sideEffectOrdering = []
        let cls = MemberDeclarationTestsSideEffectsClass()
        XCTAssertEqual([], sideEffectOrdering)
        cls.sideEffectsStruct.i += 1
        XCTAssertEqual(["willSetI", "didSetI", "willSetOwner", "didSetOwner"], sideEffectOrdering)

        sideEffectOrdering = []
        cls.sideEffectsStruct.j += 1
        XCTAssertEqual(["willSetJ", "willSetI", "didSetI", "willSetI", "didSetI", "didSetJ", "willSetOwner", "didSetOwner"], sideEffectOrdering)
    }

    func testAsyncProperty() async throws {
        try await checkProducesMessage(swift: """
        class C {
            var v: Int {
                get async {
                    return await f()
                }
            }
            func f() async -> Int {
                return 0
            }
        }
        """)
    }

    func testThrowingProperty() async throws {
        try await check(supportingSwift: """
        struct E: Error {
        }
        """, swift: """
        class C {
            var v: Int {
                get throws {
                    throw E()
                }
            }
        }
        """, kotlin: """
        internal open class C {
            internal open val v: Int
                get() {
                    throw E()
                }
        }
        """)
    }

    func testLazyProperty() async throws {
        try await check(supportingSwift: """
        class V {
        }
        """, swift: """
        class C {
            lazy var v = V()
        }
        """, kotlin: """
        internal open class C {
            internal var v: V
                get() {
                    if (!vinitialized) {
                        vstorage = V()
                        vinitialized = true
                    }
                    return vstorage
                }
                set(newValue) {
                    vstorage = newValue
                    vinitialized = true
                }
            private lateinit var vstorage: V
            private var vinitialized = false
        }
        """)

        try await check(supportingSwift: """
        struct S {
            var i = 0
        }
        """, swift: """
        class C {
            lazy var s = S()
        }
        """, kotlin: """
        internal open class C {
            internal var s: S
                get() {
                    if (!sinitialized) {
                        sstorage = S()
                        sinitialized = true
                    }
                    return sstorage.sref({ this.s = it })
                }
                set(newValue) {
                    sstorage = newValue.sref()
                    sinitialized = true
                }
            private lateinit var sstorage: S
            private var sinitialized = false
        }
        """)

        try await check(supportingSwift: """
        class V {
        }
        """, swift: """
        class C {
            lazy var v = V() {
                didSet {
                    if v != oldValue {
                        print("did set")
                    }
                }
            }
        }
        """, kotlin: """
        internal open class C {
            internal var v: V
                get() {
                    if (!vinitialized) {
                        vstorage = V()
                        vinitialized = true
                    }
                    return vstorage
                }
                set(newValue) {
                    val oldValue = this.v
                    vstorage = newValue
                    vinitialized = true
                    if (v != oldValue) {
                        print("did set")
                    }
                }
            private lateinit var vstorage: V
            private var vinitialized = false
        }
        """)

        try await check(supportingSwift: """
        class V {
        }
        """, swift: """
        struct S {
            lazy var v = V()
        }
        """, kotlin: """
        internal class S: MutableStruct {
            internal var v: V
                get() {
                    val isinitialized = vinitialized
                    if (!isinitialized) willmutate()
                    try {
                        if (!vinitialized) {
                            vstorage = V()
                            vinitialized = true
                        }
                        return vstorage
                    } finally {
                        if (!isinitialized) didmutate()
                    }
                }
                set(newValue) {
                    willmutate()
                    vstorage = newValue
                    vinitialized = true
                    didmutate()
                }
            private lateinit var vstorage: V
            private var vinitialized = false

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct {
                return S()
            }
        }
        """)
    }

    func testExplicitlyUnwrappedOptionalProperty() async throws {
        try await check(supportingSwift: """
        class V {
        }
        """, swift: """
        class C {
            var v: V!
            setUp() {
                v = V()
            }
        }
        """, kotlin: """
        internal open class C {
            internal lateinit var v: V
            internal open fun setUp() {
                v = V()
            }
        }
        """)

        try await check(supportingSwift: """
        struct S {
            var i = 0
        }
        """, swift: """
        class C {
            var s: S!
            setUp() {
                s = S()
            }
        }
        """, kotlin: """
        internal open class C {
            internal var s: S
                get() {
                    return sstorage.sref({ this.s = it })
                }
                set(newValue) {
                    sstorage = newValue.sref()
                }
            private lateinit var sstorage: S
            internal open fun setUp() {
                s = S()
            }
        }
        """)

        try await check(supportingSwift: """
        class V {
        }
        """, swift: """
        class C {
            var v: V! {
                didSet {
                    print("did set")
                }
            }
            setUp() {
                v = V()
            }
        }
        """, kotlin: """
        internal open class C {
            internal var v: V
                get() {
                    return vstorage
                }
                set(newValue) {
                    vstorage = newValue
                    print("did set")
                }
            private lateinit var vstorage: V
            internal open fun setUp() {
                v = V()
            }
        }
        """)

        try await check(supportingSwift: """
        class V {
        }
        """, swift: """
        struct S {
            var v: V!
            setUp() {
                v = V()
            }
        }
        """, kotlin: """
        internal class S: MutableStruct {
            internal var v: V
                get() {
                    return vstorage
                }
                set(newValue) {
                    willmutate()
                    vstorage = newValue
                    didmutate()
                }
            private lateinit var vstorage: V
            internal fun setUp() {
                v = V()
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct {
                return S()
            }
        }
        """)
    }

    func testDiscardableResult() async throws {
        try await check(swift: """
        @discardableResult func f() -> Int {
            return 1
        }
        """, kotlin: """
        internal fun f(): Int {
            return 1
        }
        """)
    }

    func testInOutParameter() async throws {
        try await check(swift: """
        func f(param: inout Int) {
            param += 1
        }
        func f2() {
            var i = 0
            f(param: &i)
            print(i)
        }
        """, kotlin: """
        internal fun f(param: InOut<Int>) {
            param.value += 1
        }
        internal fun f2() {
            var i = 0
            f(param = InOut({ i }, { i = it }))
            print(i)
        }
        """)

        // Test struct references
        try await check(swift: """
        func f(param s: inout Struct) -> Struct {
            s.member = Struct()
            var s2 = s
            s2.member = s.member
            return s2
        }
        func f2() {
            var s = Struct()
            let s2 = f(param: &s)
            print(s.member == s2.member)
        }
        """, kotlin: """
        internal fun f(param: InOut<Struct>): Struct {
            val s = param
            s.value.member = Struct()
            var s2 = s.value.sref()
            s2.member = s.value.member
            return s2.sref()
        }
        internal fun f2() {
            var s = Struct()
            val s2 = f(param = InOut({ s }, { s = it }))
            print(s.member == s2.member)
        }
        """)

        try await check(swift: """
        func f(param: inout Int) {
            param += 1
            f(param: &param)
        }
        """, kotlin: """
        internal fun f(param: InOut<Int>) {
            param.value += 1
            f(param = InOut({ param.value }, { param.value = it }))
        }
        """)
    }

    func testOverrideProtocolMember() async throws {
        try await check(supportingSwift: """
        protocol P {
            var i: Int { get }
            func f()
        }
        """, swift: """
        class PImpl: P {
            var i = 0
            func f() {
            }
        }
        """, kotlin: """
        internal open class PImpl: P {
            override var i = 0
            override fun f() {
            }
        }
        """)
    }

    func testSubscript() async throws {
        try await checkProducesMessage(swift: """
        class C {
            subscript(index: Int) -> Int {
                get {
                    return 0
                }
                set {
                }
            }
            subscript(key: String, defaultValue: Int) -> Int {
                return defaultValue
            }
        }
        """)
    }

    func testFunctionSignatureConflicts() async throws {
        try await check(swift: """
        func f(a: Int) {
        }
        func f(c: Int) {
        }
        func f(b: Int) {
        }
        func f(a: Double) {
        }
        func g(a: Int) {
        }
        """, kotlin: """
        internal fun f(a: Int, unusedp_0: Nothing? = null) {
        }
        internal fun f(c: Int) {
        }
        internal fun f(b: Int, unusedp_0: Nothing? = null, unusedp_1: Nothing? = null) {
        }
        internal fun f(a: Double) {
        }
        internal fun g(a: Int) {
        }
        """)
    }

    func testMemberFunctionSignatureConflicts() async throws {
        try await check(swift: """
        class A {
            func f(a: Int) {
            }
            func f(b: Int) {
            }
        }
        """, kotlin: """
        internal open class A {
            internal open fun f(a: Int, unusedp_0: Nothing? = null) {
            }
            internal open fun f(b: Int) {
            }
        }
        """)

        try await check(swift: """
        open class A {
            open func f(a: Int) {
            }
            func f(b: Int) {
            }
        }
        """, kotlin: """
        open class A {
            open fun f(a: Int) {
            }
            internal open fun f(b: Int, unusedp_0: Nothing? = null) {
            }

            companion object {
            }
        }
        """)

        try await check(swift: """
        class A {
            func f(a: Int) {
            }
        }
        class B: A {
            func f(b: Int) {
            }
        }
        class C {
            func f(c: Int) {
            }
        }
        """, kotlin: """
        internal open class A {
            internal open fun f(a: Int) {
            }
        }
        internal open class B: A() {
            internal open fun f(b: Int, unusedp_0: Nothing? = null) {
            }
        }
        internal open class C {
            internal open fun f(c: Int) {
            }
        }
        """)

        try await check(swift: """
        class A {
            func f(a: Int) {
            }
        }
        class B: A {
            override func f(a: Int) {
            }
        }
        """, kotlin: """
        internal open class A {
            internal open fun f(a: Int) {
            }
        }
        internal open class B: A() {
            override fun f(a: Int) {
            }
        }
        """)

        // Make sure we aren't dependent on param alpha order
        try await check(swift: """
        class A {
            func f(c: Int) {
            }
        }
        class B: A {
            func f(b: Int) {
            }
        }
        class C {
            func f(a: Int) {
            }
        }
        """, kotlin: """
        internal open class A {
            internal open fun f(c: Int) {
            }
        }
        internal open class B: A() {
            internal open fun f(b: Int, unusedp_0: Nothing? = null) {
            }
        }
        internal open class C {
            internal open fun f(a: Int) {
            }
        }
        """)

        try await check(swift: """
        class A {
            func f(a: Int) {
            }
            func g(z: Int) {
            }
        }
        class B: A {
            func f(b: Int) {
            }
        }
        class C: B {
            func f(c: Int) {
            }
            func g(a: Int) {
            }
        }
        """, kotlin: """
        internal open class A {
            internal open fun f(a: Int) {
            }
            internal open fun g(z: Int) {
            }
        }
        internal open class B: A() {
            internal open fun f(b: Int, unusedp_0: Nothing? = null) {
            }
        }
        internal open class C: B() {
            internal open fun f(c: Int, unusedp_0: Nothing? = null, unusedp_1: Nothing? = null) {
            }
            internal open fun g(a: Int, unusedp_0: Nothing? = null) {
            }
        }
        """)

        try await checkProducesMessage(swift: """
        open class A {
            open func f(a: Int) {
            }
            open func f(b: Int) {
            }
        }
        """)
    }

    func testProtocolFunctionSignatureConflicts() async throws {
        try await check(swift: """
        class A: P {
            func f(a: Int) {
            }
            func f(b: Int) {
            }
        }
        protocol P {
            func f(a: Int)
        }
        """, kotlin: """
        internal open class A: P {
            override fun f(a: Int) {
            }
            internal open fun f(b: Int, unusedp_0: Nothing? = null) {
            }
        }
        internal interface P {
            fun f(a: Int)
        }
        """)

        try await check(swift: """
        protocol P1 {
            func f(a: Int)
        }
        protocol P2 {
            func f(a: Double)
        }
        protocol P3: P1, P2 {
            func f(b: Int)
        }
        class A: P1 {
            func f(a: Int) {
            }
        }
        class B: P2, P3 {
            func f(a: Int) {
            }
            func f(a: Double) {
            }
            func f(b: Int) {
            }
        }
        """, kotlin: """
        internal interface P1 {
            fun f(a: Int)
        }
        internal interface P2 {
            fun f(a: Double)
        }
        internal interface P3: P1, P2 {
            fun f(b: Int, unusedp_0: Nothing? = null)
        }
        internal open class A: P1 {
            override fun f(a: Int) {
            }
        }
        internal open class B: P2, P3 {
            override fun f(a: Int) {
            }
            override fun f(a: Double) {
            }
            override fun f(b: Int, unusedp_0: Nothing?) {
            }
        }
        """)

        try await checkProducesMessage(swift: """
        class A: P1, P2 {
            func f(a: Int) {
            }
            func f(b: Int) {
            }
        }
        public protocol P1 {
            func f(a: Int)
        }
        public protocol P2 {
            func f(b: Int)
        }
        """)
    }

    func testInitSignatureConflicts() async throws {
        try await check(swift: """
        class A {
            init(a: Int) {
            }
            init(b: Int) {
            }
        }
        class B: A {
            override init(a: Int) {
            }
            init(c: Int) {
            }
        }
        class C: A {
            init(c: Int) {
            }
        }
        """, kotlin: """
        internal open class A {
            internal constructor(a: Int, unusedp_0: Nothing? = null) {
            }
            internal constructor(b: Int) {
            }
        }
        internal open class B: A {
            internal constructor(a: Int, unusedp_0: Nothing? = null): super() {
            }
            internal constructor(c: Int): super() {
            }
        }
        internal open class C: A {
            internal constructor(c: Int): super() {
            }
        }
        """)
    }

    func testGenericFunction() async throws {
        try await check(swift: """
        func f<T, U>(a: T, b: U) -> T? {
        }
        """, kotlin: """
        internal fun <T, U> f(a: T, b: U): T? {
        }
        """)

        try await check(swift: """
        func f<T: I, U>(a: T, b: U) -> Int where U: J {
        }
        """, kotlin: """
        internal fun <T, U> f(a: T, b: U): Int where T: I, U: J {
        }
        """)
    }

    func testMissingGenericsAddedToMembers() async throws {
        try await check(swift: """
        class C<T> {
            var v: C
            func f(p: [C]) -> C? {
                return nil
            }
        }
        """, kotlin: """
        internal open class C<T> {
            internal var v: C<T>
            internal open fun f(p: Array<C<T>>): C<T>? {
                return null
            }
        }
        """)
    }

    func testCustomSubscript() async throws {
        try await checkProducesMessage(swift: """
        class C {
            subscript(index: Int) -> String {
                return ""
            }
        }
        """)
    }

    func testCustomOperator() async throws {
        try await checkProducesMessage(swift: """
        class C {
        }
        extension C {
            static func + (lhs: C: rhs: C) -> C {
                return lhs
            }
        }
        """)
    }

    func testCustomEquals() async throws {
        try await check(swift: """
        class C<T> where T: AnyObject, T: Equatable {
            var t: T
            init(t: T) {
                self.t = t
            }
            func f() -> Int {
                return 1
            }
            static func == (lhs: C, rhs: C) -> Bool {
                return lhs.t == rhs.t && lhs.f() == rhs.f()
            }
        }
        """, kotlin: """
        internal open class C<T> where T: Any {
            internal var t: T
            internal constructor(t: T) {
                this.t = t
            }
            internal open fun f(): Int {
                return 1
            }
            override fun equals(other: Any?): Boolean {
                if (other !is C<*>) {
                    return false
                }
                val lhs = this
                val rhs = other
                return lhs.t == rhs.t && lhs.f() == rhs.f()
            }
        }
        """)
    }

    func testCustomHash() async throws {
        try await check(swift: """
        class C<T>: Hashable where T: AnyObject, T: Hashable {
            var t: T
            init(t: T) {
                self.t = t
            }
            func f() -> Int {
                return 1
            }
            func hash(into hasher: inout Hasher) {
                hasher.combine(t)
                hasher.combine(f())
            }
        }
        """, kotlin: """
        internal open class C<T> where T: Any {
            internal var t: T
            internal constructor(t: T) {
                this.t = t
            }
            internal open fun f(): Int {
                return 1
            }
            override fun hashCode(): Int {
                var hasher = Hasher()
                hash(into = InOut<Hasher>({ hasher }, { hasher = it }))
                return hasher.finalize()
            }
            internal open fun hash(into: InOut<Hasher>) {
                val hasher = into
                hasher.value.combine(t)
                hasher.value.combine(f())
            }
        }
        """)
    }

    func testCustomComparable() async throws {
        try await check(swift: """
        class C<T>: Comparable where T: AnyObject, T: Comparable {
            var t: T
            init(t: T) {
                self.t = t
            }
            static func == (lhs: C, rhs: C) -> Bool {
                return lhs.t == rhs.t
            }
            static func < (lhs: C, rhs: C) -> Bool {
                return lhs.t < rhs.t
            }
        }
        """, kotlin: """
        internal open class C<T>: Comparable<C<T>> where T: Any, T: Comparable<T> {
            internal var t: T
            internal constructor(t: T) {
                this.t = t
            }
            override fun equals(other: Any?): Boolean {
                if (other !is C<*>) {
                    return false
                }
                val lhs = this
                val rhs = other
                return lhs.t == rhs.t
            }
            override fun compareTo(other: C<T>): Int {
                if (this == other) return 0
                fun islessthan(lhs: C<T>, rhs: C<T>): Boolean {
                    return lhs.t < rhs.t
                }
                return if (islessthan(this, other)) -1 else 1
            }
        }
        """)
    }

    func testCustomDescription() async throws {
        try await check(swift: """
        class C {
            let description = "foo"
        }
        """, kotlin: """
        internal open class C {
            internal val description = "foo"
        }
        """)

        try await check(swift: """
        class C: CustomStringConvertible {
            let description = "foo"
        }
        """, kotlin: """
        internal open class C {
            internal val description = "foo"

            override fun toString(): String {
                return description
            }
        }
        """)

        try await check(swift: """
        class C {
            let i: Int
            init(param: Int) {
                self.i = param
            }
        }
        extension C: CustomStringConvertible {
            var description: String {
                return "foo"
            }
        }
        """, kotlin: """
        internal open class C {
            internal val i: Int
            internal constructor(param: Int) {
                this.i = param
            }
            internal open val description: String
                get() {
                    return "foo"
                }

            override fun toString(): String {
                return description
            }
        }
        """)
    }

    func testLocalFunction() async throws {
        try await check(supportingSwift: """
        extension Int {
            static let myValue = 0
        }
        extension String {
            static let myValue = ""
        }
        """, swift: """
        class C {
            var i: Int

            func f(s: String) {
                func doSomething(with: String) -> String {
                    return .myValue
                }
                print(doSomething(with: i) == .myValue)
                print(doSomething(with: s) == .myValue)
            }

            func doSomething(with: Int) -> Int {
                return .myValue
            }
        }
        """, kotlin: """
        internal open class C {
            internal var i: Int

            internal open fun f(s: String) {
                fun doSomething(with: String): String {
                    return String.myValue
                }
                print(doSomething(with = i) == Int.myValue)
                print(doSomething(with = s) == String.myValue)
            }

            internal open fun doSomething(with: Int): Int {
                return Int.myValue
            }
        }
        """)

        try await checkProducesMessage(swift: """
        func f() {
            func g(x: Int) {
            }
            g(1)
            func g(y: Double) {
            }
        }
        """)
    }
}

var sideEffectOrdering: [String] = []

private struct MemberDeclarationTestsSideEffectsStruct {
    var i = 0 {
        willSet {
            sideEffectOrdering.append("willSetI")
        }
        didSet {
            sideEffectOrdering.append("didSetI")
        }
    }

    var j = 0 {
        willSet {
            sideEffectOrdering.append("willSetJ")
            i += 1
        }
        didSet {
            i -= 1
            sideEffectOrdering.append("didSetJ")
        }
    }
}

private class MemberDeclarationTestsSideEffectsClass {
    fileprivate var sideEffectsStruct = MemberDeclarationTestsSideEffectsStruct() {
        willSet {
            sideEffectOrdering.append("willSetOwner")
        }
        didSet {
            sideEffectOrdering.append("didSetOwner")
        }
    }
}
