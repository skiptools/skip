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
            internal open var i: Int? = null
            internal open var j: Int? = null
            internal open var k = 10
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

            internal open var i = 1

            companion object {
                internal val staticLet = 1
                internal var staticVar = 10

                internal fun staticFunc(): Int = 20
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

            internal open fun f(): T = Unit

            companion object {
                internal val staticLet = 1

                internal fun staticFunc(): Int = 20

                internal fun <T> staticFunc2(p: T): T = Unit

                internal fun <T, U> staticFunc3(p1: T, p2: U): T = Unit
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
            static func staticFunc() -> T
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
            get() = 10
        internal fun C.Companion.staticFunc(): Int = 20
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
        internal fun <T> C.Companion.staticFunc(p: T): T = Unit
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
                get() = 10
            internal open var j: Int
                get() = 10
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
                    10
                }
                set(value) {
                    print(value)
                }
            }
        }
        """, kotlin: """
        internal open class A {
            internal open var i: Int
                get() = 10
                set(newValue) {
                    val value = newValue
                    print(value)
                }
        }
        """)
    }

    func testOverrideComputedProperty() async throws {
        try await check(swift: """
        class C {
            var x: Int {
                return 1
            }
            var y: String {
                get {
                    return "C"
                }
                set {
                    print("set")
                }
            }
        }
        class S: C {
            override var x: Int {
                return 2
            }
            override var y: String {
                get {
                    return "S"
                }
                set {
                    print("set2")
                }
            }
        }
        """, kotlin: """
        internal open class C {
            internal open val x: Int
                get() = 1
            internal open var y: String
                get() = "C"
                set(newValue) {
                    print("set")
                }
        }
        internal open class S: C() {
            override val x: Int
                get() = 2
            override var y: String
                get() = "S"
                set(newValue) {
                    print("set2")
                }
        }
        """)
    }

    func testPropertyWillDidSet() async throws {
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
            internal open var i = 1
                set(newValue) {
                    print(newValue)
                    field = newValue
                }
            internal open var j = 2
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
            internal open var i = 1
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
            internal open var i = 1
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

    func testMutableStructPropertyWillDidSet() async throws {
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
            internal var i: Int
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
            internal var j: Int
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
            override fun scopy(): MutableStruct = A(i, j)

            private var suppresssideeffects = false
        }
        """)
    }

    func testOverrideWillDidSet() async throws {
        try await check(swift: """
        class C {
            var i = 1
        }
        class S: C {
            override var i: Int {
                willSet {
                    print("subwillset: \\(newValue)")
                }
                didSet {
                    print("subdidset: \\(i)")
                }
            }
        }
        """, kotlin: """
        internal open class C {
            internal open var i = 1
        }
        internal open class S: C() {
            override var i: Int
                get() = super.i
                set(newValue) {
                    print("subwillset: ${newValue}")
                    super.i = newValue
                    print("subdidset: ${i}")
                }
        }
        """)

        try await check(swift: """
        class C {
            var a: [Int] = []
        }
        class S: C {
            override var a: [Int] {
                willSet {
                    print("subwillset: \\(newValue)")
                }
                didSet {
                    print("subdidset: \\(a)")
                }
            }
        }
        """, kotlin: """
        import skip.lib.Array

        internal open class C {
            internal open var a: Array<Int> = arrayOf()
                get() = field.sref({ this.a = it })
                set(newValue) {
                    field = newValue.sref()
                }
        }
        internal open class S: C() {
            override var a: Array<Int>
                get() = super.a
                set(newValue) {
                    print("subwillset: ${newValue}")
                    super.a = newValue
                    print("subdidset: ${a}")
                }
        }
        """)

        try await check(swift: """
        class A {}
        class C {
            var a: A!
        }
        class S: C {
            override var a: A! {
                willSet {
                    print("subwillset: \\(newValue)")
                }
                didSet {
                    print("subdidset: \\(a)")
                }
            }
        }
        """, kotlin: """
        internal open class A {
        }
        internal open class C {
            internal open lateinit var a: A
        }
        internal open class S: C() {
            override var a: A
                get() = super.a
                set(newValue) {
                    print("subwillset: ${newValue}")
                    super.a = newValue
                    print("subdidset: ${a}")
                }
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
        let subcls = MemberDeclarationTestsSideEffectsSubclass()
        XCTAssertEqual([], sideEffectOrdering)
        subcls.sideEffectsStruct.i += 1
        XCTAssertEqual(["willSetI", "didSetI", "willSetSubclass", "willSetOwner", "didSetOwner", "didSetSubclass"], sideEffectOrdering)

        sideEffectOrdering = []
        cls.sideEffectsStruct.j += 1
        XCTAssertEqual(["willSetJ", "willSetI", "didSetI", "willSetI", "didSetI", "didSetJ", "willSetOwner", "didSetOwner"], sideEffectOrdering)
    }

    func testAsyncProperty() async throws {
        try await check(swift: """
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
        """, kotlin: """
        internal open class C {
            internal open suspend fun v(): Int = Async.run l@{
                return@l f()
            }
            internal open suspend fun f(): Int = Async.run l@{
                return@l 0
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
            internal open var v: V
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
            internal open var s: S
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
            internal open var v: V
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
            override fun scopy(): MutableStruct = S()
        }
        """)
    }

    func testLazyPrimitivePropertyInitialization() async throws {
        // Kotlin doesn't support lateinit on primitives
        try await check(swift: """
        class C {
            lazy var f = factorial(100)
            private func factorial(_ i: Int) -> Int {
                return 0
            }
        }
        """, kotlin: """
        internal open class C {
            internal open var f: Int
                get() {
                    if (!finitialized) {
                        fstorage = factorial(100)
                        finitialized = true
                    }
                    return fstorage
                }
                set(newValue) {
                    fstorage = newValue
                    finitialized = true
                }
            private var fstorage = Int(0)
            private var finitialized = false
            private fun factorial(i: Int): Int = 0
        }
        """)
    }

    func testExplicitlyUnwrappedOptionalProperty() async throws {
        try await check(supportingSwift: """
        class V {
        }
        """, swift: """
        class C {
            var v: V! {
                return a() ?? b()
            }
            private func a() -> V? {
                return nil
            }
            private func b() -> V? {
                return nil
            }
        }
        """, kotlin: """
        internal open class C {
            internal open val v: V
                get() = vstorage!!
            private val vstorage: V?
                get() = a() ?: b()
            private fun a(): V? = null
            private fun b(): V? = null
        }
        """)

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
            internal open lateinit var v: V
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
            internal open var s: S
                get() = sstorage.sref({ this.s = it })
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
            internal open var v: V
                get() = vstorage
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
                get() = vstorage
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
            override fun scopy(): MutableStruct = S()
        }
        """)

        try await checkProducesMessage(swift: """
        struct S {
            var i: Int!
            setUp() {
                i = 100
            }
        }
        """)
    }

    func testNonmutatingProperty() async throws {
        try await check(swift: """
        struct S {
            var x: String {
                get {
                    return "x"
                }
                nonmutating set {
                    print(newValue)
                }
            }
        }
        func f() -> S {
            let s = S()
            s.x = "y"
            return s
        }
        """, kotlin: """
        internal class S {
            internal var x: String
                get() = "x"
                set(newValue) {
                    print(newValue)
                }
        }
        internal fun f(): S {
            val s = S()
            s.x = "y"
            return s
        }
        """)
    }

    func testDiscardableResult() async throws {
        try await check(swift: """
        @discardableResult func f() -> Int {
            return 1
        }
        """, kotlin: """
        internal fun f(): Int = 1
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
        try await check(supportingSwift: """
        struct Struct {
            var member: Struct
        }
        """, swift: """
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
            override fun f() = Unit
        }
        """)

        try await check(supportingSwift: """
        protocol P {
            func f(i: Int, s: String)
        }
        """, swift: """
        class PImpl: P {
            func f(i: Double, s: String) {
            }
            func f(i: Int, s: String) {
            }
        }
        """, kotlin: """
        internal open class PImpl: P {
            internal open fun f(i: Double, s: String) = Unit
            override fun f(i: Int, s: String) = Unit
        }
        """)

        try await check(supportingSwift: """
        protocol P {
            associatedtype T
            func f(t: T)
        }
        """, swift: """
        class PImpl: P {
            func f(t: Int) {
            }
        }
        """, kotlin: """
        internal open class PImpl: P<Int> {
            override fun f(t: Int) = Unit
        }
        """)
    }

    func testSubscript() async throws {
        try await check(swift: """
        class C {
            subscript(index: Int) -> Int {
                get {
                    return 0
                }
                set {
                }
            }
            subscript(index: Double) -> Double {
                get { 1.0 }
                set(double) {
                }
            }
            subscript(key: String, defaultValue: Int) -> Int {
                return defaultValue
            }
        }
        """, kotlin: """
        internal open class C {
            internal open operator fun get(index: Int): Int = 0
            internal open operator fun set(index: Int, newValue: Int) = Unit
            internal open operator fun get(index: Double): Double = 1.0
            internal open operator fun set(index: Double, double: Double) = Unit
            internal open operator fun get(key: String, defaultValue: Int): Int = defaultValue
        }
        """)

        try await check(swift: """
        struct S1 {
            subscript(index: Int) -> Int { 0 }
        }
        struct S2 {
            subscript(index: Int) -> Int {
                get { 0 }
                set {
                    print(newValue)
                }
            }
        }
        """, kotlin: """
        internal class S1 {
            internal operator fun get(index: Int): Int = 0
        }
        internal class S2: MutableStruct {
            internal operator fun get(index: Int): Int = 0
            internal operator fun set(index: Int, newValue: Int) {
                willmutate()
                try {
                    print(newValue)
                } finally {
                    didmutate()
                }
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct = S2()
        }
        """)

        try await checkProducesMessage(swift: """
        class C {
            subscript(index: Int) -> Int {
                get async {
                    return 0
                }
            }
        }
        """)

        try await check(supportingSwift: """
        extension Int {
            static let zero = 0
        }
        extension Double {
            static let zero = 0.0
        }
        class C {
            subscript(index: Int) -> Int {
                get { 0 }
                set {}
            }
            subscript(index: Double) -> Double {
                get { 0.0 }
                set {}
            }
            subscript(index: Int, defaultValue: Int) -> Int {
                return 0
            }
        }
        """, swift: """
        func f(c: C) {
            let b1 = c[0] == .zero
            let b2 = c[0.0] == .zero
            c[0] = .zero
            c[0.0] = .zero
            let b3 = c[.zero, defaultValue: 0] == .zero
        }
        """, kotlin: """
        internal fun f(c: C) {
            val b1 = c[0] == Int.zero
            val b2 = c[0.0] == Double.zero
            c[0] = Int.zero
            c[0.0] = Double.zero
            val b3 = c[Int.zero, 0] == Int.zero
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
        internal fun f(a: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null) = Unit
        internal fun f(c: Int) = Unit
        internal fun f(b: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null, @Suppress("UNUSED_PARAMETER") unusedp_1: Nothing? = null) = Unit
        internal fun f(a: Double) = Unit
        internal fun g(a: Int) = Unit
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
            internal open fun f(a: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null) = Unit
            internal open fun f(b: Int) = Unit
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
            open fun f(a: Int) = Unit
            internal open fun f(b: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null) = Unit

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
            internal open fun f(a: Int) = Unit
        }
        internal open class B: A() {
            internal open fun f(b: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null) = Unit
        }
        internal open class C {
            internal open fun f(c: Int) = Unit
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
            internal open fun f(a: Int) = Unit
        }
        internal open class B: A() {
            override fun f(a: Int) = Unit
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
            internal open fun f(c: Int) = Unit
        }
        internal open class B: A() {
            internal open fun f(b: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null) = Unit
        }
        internal open class C {
            internal open fun f(a: Int) = Unit
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
            internal open fun f(a: Int) = Unit
            internal open fun g(z: Int) = Unit
        }
        internal open class B: A() {
            internal open fun f(b: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null) = Unit
        }
        internal open class C: B() {
            internal open fun f(c: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null, @Suppress("UNUSED_PARAMETER") unusedp_1: Nothing? = null) = Unit
            internal open fun g(a: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null) = Unit
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
            override fun f(a: Int) = Unit
            internal open fun f(b: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null) = Unit
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
            fun f(b: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null)
        }
        internal open class A: P1 {
            override fun f(a: Int) = Unit
        }
        internal open class B: P2, P3 {
            override fun f(a: Int) = Unit
            override fun f(a: Double) = Unit
            override fun f(b: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing?) = Unit
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
            internal constructor(a: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null) {
            }
            internal constructor(b: Int) {
            }
        }
        internal open class B: A {
            internal constructor(a: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null): super() {
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
        internal fun <T, U> f(a: T, b: U): T? = Unit
        """)

        try await check(swift: """
        func f<T: I, U>(a: T, b: U) -> Int where U: J {
        }
        """, kotlin: """
        internal fun <T, U> f(a: T, b: U): Int where T: I, U: J = Unit
        """)
    }

    func testGenericMemberFunction() async throws {
        try await check(swift: """
        protocol I {}
        class C<T> {
            func a(t: T) {}
            func b<U>(t: T, u: U) -> U  {
                return u
            }
            func c<U>(t: T, u: U) where U: I {}
        }
        """, kotlin: """
        internal interface I {
        }
        internal open class C<T> {
            internal open fun a(t: T) = Unit
            internal open fun <U> b(t: T, u: U): U = u.sref()
            internal open fun <U> c(t: T, u: U) where U: I = Unit
        }
        """)

        try await check(swift: """
        protocol I {}
        class C<T, Z> {
            func a(z: Z) {}
            func b<U>(t: T, u: U) where T: I {}
            func c<U>(t: String, u: U) where T == String {}
        }
        """, kotlin: """
        internal interface I {
        }
        internal open class C<T, Z> {
            internal open fun a(z: Z) = Unit
        }

        internal fun <T, Z, U> C<T, Z>.b(t: T, u: U) where T: I = Unit
        internal fun <Z, U> C<String, Z>.c(t: String, u: U) = Unit
        """)

        try await check(swift: """
        protocol I {}
        class C<T, Z> {
            func a(z: Z) {}
            func b<U>(t: T, u: U) where T: I {}
        }
        extension C where T == String {
            func c<U>(t: String, u: U)
            func d() where Z: I {
            }
        }
        """, kotlin: """
        internal interface I {
        }
        internal open class C<T, Z> {
            internal open fun a(z: Z) = Unit
        }

        internal fun <T, Z, U> C<T, Z>.b(t: T, u: U) where T: I = Unit

        internal fun <Z, U> C<String, Z>.c(t: String, u: U)
        internal fun <Z> C<String, Z>.d() where Z: I = Unit
        """)

        try await checkProducesMessage(swift: """
        protocol I {}
        class C<T> {
            init() where T: I {
            }
        }
        """)

        try await checkProducesMessage(swift: """
        protocol I {}
        struct S<T> {
            mutating func f() where T: I {
                self = S()
            }
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
        import skip.lib.Array

        internal open class C<T> {
            internal open var v: C<T>
            internal open fun f(p: Array<C<T>>): C<T>? = null
        }
        """)
    }

    func testAutoclosureFunctionParameter() async throws {
        try await checkProducesMessage(swift: """
        func f(c: @autoclosure () -> Void) {
            c()
        }
        """)
    }

    func testEscapingFunctionParameter() async throws {
        try await check(swift: """
        func f(c: @escaping () -> Void) {
            c()
        }
        """, kotlin: """
        internal fun f(c: () -> Unit): Unit = c()
        """)
    }

    func testVariadicFunctionParameter() async throws {
        try await check(swift: """
        func f(v: Int..., s: String) -> [Int] {
            let a = [0] + v
            return a
        }
        f(v: 1, 2, 3, s: "")
        """, kotlin: """
        import skip.lib.Array
        
        internal fun f(vararg v: Int, s: String): Array<Int> {
            val v = Array(v.asIterable())
            val a = (arrayOf(0) + v).sref()
            return a.sref()
        }
        f(1, 2, 3, s = "")
        """)

        try await check(swift: """
        func f(_ v: Int..., s: String) -> [Int] {
            let a = [0] + v
            return a
        }
        f(1, 2, 3, s: "")
        """, kotlin: """
        import skip.lib.Array
        
        internal fun f(vararg v: Int, s: String): Array<Int> {
            val v = Array(v.asIterable())
            val a = (arrayOf(0) + v).sref()
            return a.sref()
        }
        f(1, 2, 3, s = "")
        """)

        try await checkProducesMessage(swift: """
        func f(v: Int..., _ s: String) {
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
            internal open var t: T
            internal constructor(t: T) {
                this.t = t
            }
            internal open fun f(): Int = 1
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
            internal open var t: T
            internal constructor(t: T) {
                this.t = t
            }
            internal open fun f(): Int = 1
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
            internal open var t: T
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

            override fun toString(): String = description
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
                get() = "foo"

            override fun toString(): String = description
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
            internal open var i: Int

            internal open fun f(s: String) {
                fun doSomething(with: String): String = String.myValue
                print(doSomething(with = i) == Int.myValue)
                print(doSomething(with = s) == String.myValue)
            }

            internal open fun doSomething(with: Int): Int = Int.myValue
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

    func testLetWithInternalLabel() async throws {
        try await checkProducesMessage(swift: """
        func f(ext int: Int) -> Int {
            var int = int
            int += 1
            return int
        }
        """)

        try await check(swift: """
        func f(int: Int) -> Int {
            var int = int
            int += 1
            return int
        }
        func f(_ int: Int) -> Int {
            var int = int
            int += 1
            return int
        }
        """, kotlin: """
        internal fun f(int: Int): Int {
            var int = int
            int += 1
            return int
        }
        internal fun f(int: Int, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null): Int {
            var int = int
            int += 1
            return int
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
        public class C<T, U> {
        }
        extension C where T == Int, U: P {
            var v: U? {
                return nil
            }
            @inline(__always) public func f<V: P>(p1: U, p2: V) -> Int {
                return 1
            }
        }
        """, kotlin: """
        open class C<T, U> {

            companion object {
            }
        }

        internal val <U> C<Int, U>.v: U? where U: P
            get() = null
        inline fun <reified U, reified V> C<Int, U>.f(p1: U, p2: V): Int where U: P, V: P = 1
        """)
    }

    func testReifiedGenericsProtocolMember() async throws {
        try await check(swift: """
        protocol P {
        }
        extension P {
            @inline(__always) func f<T>(p: T) {
            }
        }
        """, kotlin: """
        internal interface P {
        }

        internal inline fun <reified T> P.f(p: T) = Unit
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

private class MemberDeclarationTestsSideEffectsSubclass: MemberDeclarationTestsSideEffectsClass {
    fileprivate override var sideEffectsStruct: MemberDeclarationTestsSideEffectsStruct {
        willSet {
            sideEffectOrdering.append("willSetSubclass")
        }
        didSet {
            sideEffectOrdering.append("didSetSubclass")
        }
    }
}
